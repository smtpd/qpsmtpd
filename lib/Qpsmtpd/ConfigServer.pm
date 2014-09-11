package Qpsmtpd::ConfigServer;

use base ('Danga::Client');
use Qpsmtpd::Constants;

use strict;

use fields qw(
  _auth
  _commands
  _config_cache
  _connection
  _transaction
  _test_mode
  _extras
  other_fds
  );

my $PROMPT = "Enter command: ";

sub new {
    my Qpsmtpd::ConfigServer $self = shift;

    $self = fields::new($self) unless ref $self;
    $self->SUPER::new(@_);
    $self->write($PROMPT);
    return $self;
}

sub max_idle_time { 3600 }    # one hour

sub process_line {
    my $self = shift;
    my $line = shift || return;
    if ($::DEBUG > 1) { print "$$:" . ($self + 0) . "C($self->{mode}): $line"; }
    local $SIG{ALRM} = sub {
        my ($pkg, $file, $line) = caller();
        die "ALARM: $pkg, $file, $line";
    };
    my $prev = alarm(2);      # must process a command in < 2 seconds
    my $resp = eval { $self->_process_line($line) };
    alarm($prev);
    if ($@) {
        print STDERR "Error: $@\n";
    }
    return $resp || '';
}

sub respond {
    my $self = shift;
    my (@messages) = @_;
    while (my $msg = shift @messages) {
        $self->write("$msg\r\n");
    }
    return;
}

sub fault {
    my $self = shift;
    my ($msg) = shift || "program fault - command not performed";
    print STDERR "$0 [$$]: $msg\n";
    print STDERR $name, "[$$]: Last system error: $!"
        ." (Likely irelevant--debug the crashed plugin to ensure it handles \$! properly)";
    $self->respond("Error - " . $msg);
    return $PROMPT;
}

sub _process_line {
    my $self = shift;
    my $line = shift;

    $line =~ s/\r?\n//;
    my ($cmd, @params) = split(/ +/, $line);
    my $meth = "cmd_" . lc($cmd);
    if (my $lookup = $self->can($meth)) {
        my $resp = eval { $lookup->($self, @params); };
        if ($@) {
            my $error = $@;
            chomp($error);
            Qpsmtpd->log(LOGERROR, "Command Error: $error");
            return $self->fault("command '$cmd' failed unexpectedly");
        }
        return "$resp\n$PROMPT";
    }
    else {
        # No such method - i.e. unrecognized command
        return $self->fault("command '$cmd' unrecognised");
    }
}

my %helptext = (
    help   => "HELP [CMD] - Get help on all commands or a specific command",
    status => "STATUS - Returns status information about current connections",
    list =>
"LIST [LIMIT] - List the connections, specify limit or negative limit to shrink list",
    kill =>
"KILL (\$IP | \$REF) - Disconnect all connections from \$IP or connection reference \$REF",
    pause    => "PAUSE - Stop accepting new connections",
    continue => "CONTINUE - Resume accepting connections",
    reload   => "RELOAD - Reload all plugins and config",
    quit     => "QUIT - Exit the config server",
);

sub cmd_help {
    my $self = shift;
    my ($subcmd) = @_;

    $subcmd ||= 'help';
    $subcmd = lc($subcmd);

    if ($subcmd eq 'help') {
        my $txt = join("\n",
                       map { substr($_, 0, index($_, "-")) }
                       sort values(%helptext));
        return "Available Commands:\n\n$txt\n";
    }
    my $txt = $helptext{$subcmd}
      || "Unrecognised help option. Try 'help' for a full list.";
    return "$txt\n";
}

sub cmd_quit {
    my $self = shift;
    $self->close;
}

sub cmd_shutdown {
    exit;
}

sub cmd_pause {
    my $self = shift;

    my $other_fds = $self->OtherFds;

    $self->{other_fds} = {%$other_fds};
    %$other_fds = ();
    return "PAUSED";
}

sub cmd_continue {
    my $self = shift;

    my $other_fds = $self->{other_fds};

    $self->OtherFds(%$other_fds);
    %$other_fds = ();
    return "UNPAUSED";
}

sub cmd_status {
    my $self = shift;

    # Status should show:
    #  - Total time running
    #  - Total number of mails received
    #  - Total number of mails rejected (5xx)
    #  - Total number of mails tempfailed (5xx)
    #  - Avg number of mails/minute
    #  - Number of current connections
    #  - Number of outstanding DNS queries

    my $output = "Current Status as of " . gmtime() . " GMT\n\n";

    if (defined &Qpsmtpd::Plugin::stats::get_stats) {

        # Stats plugin is loaded
        $output .= Qpsmtpd::Plugin::stats->get_stats;
    }

    my $descriptors = Danga::Socket->DescriptorMap;

    my $current_connections = 0;
    my $current_dns         = 0;
    foreach my $fd (keys %$descriptors) {
        my $pob = $descriptors->{$fd};
        if ($pob->isa("Qpsmtpd::PollServer")) {
            $current_connections++;
        }
        elsif ($pob->isa("ParaDNS::Resolver")) {
            $current_dns = $pob->pending;
        }
    }

    $output .= "Curr Connections: $current_connections / $::MAXconn\n"
      . "Curr DNS Queries: $current_dns";

    return $output;
}

sub cmd_list {
    my $self = shift;
    my ($count) = @_;

    my $descriptors = Danga::Socket->DescriptorMap;

    my $list =
        "Current"
      . ($count ? (($count > 0) ? " Oldest $count" : " Newest " . -$count) : "")
      . " Connections: \n\n";
    my @all;
    foreach my $fd (keys %$descriptors) {
        my $pob = $descriptors->{$fd};
        if ($pob->isa("Qpsmtpd::PollServer")) {
            next unless $pob->connection->remote_ip;  # haven't even started yet
            push @all,
              [
                $pob + 0,                      $pob->connection->remote_ip,
                $pob->connection->remote_host, $pob->uptime
              ];
        }
    }

    @all = sort { $a->[3] <=> $b->[3] } @all;
    if ($count) {
        if ($count > 0) {
            @all = @all[$#all - ($count - 1) .. $#all];
        }
        else {
            @all = @all[0 .. (abs($count) - 1)];
        }
    }
    foreach my $item (@all) {
        $list .= sprintf("%x : %s [%s] Connected %0.2fs\n",
                         map { defined() ? $_ : '' } @$item);
    }

    return $list;
}

sub cmd_kill {
    my $self = shift;
    my ($match) = @_;

    return "SYNTAX: KILL (\$IP | \$REF)\n" unless $match;

    my $descriptors = Danga::Socket->DescriptorMap;

    my $killed = 0;
    my $is_ip = (index($match, '.') >= 0);
    foreach my $fd (keys %$descriptors) {
        my $pob = $descriptors->{$fd};
        if ($pob->isa("Qpsmtpd::PollServer")) {
            if ($is_ip) {
                next
                  unless $pob->connection->remote_ip; # haven't even started yet
                if ($pob->connection->remote_ip eq $match) {
                    $pob->write(
"550 Your connection has been killed by an administrator\r\n");
                    $pob->disconnect;
                    $killed++;
                }
            }
            else {
                # match by ID
                if ($pob + 0 == hex($match)) {
                    $pob->write(
"550 Your connection has been killed by an administrator\r\n");
                    $pob->disconnect;
                    $killed++;
                }
            }
        }
    }

    return "Killed $killed connection" . ($killed > 1 ? "s" : "") . "\n";
}

sub cmd_dump {
    my $self = shift;
    my ($ref) = @_;

    return "SYNTAX: DUMP \$REF\n" unless $ref;
    require Data::Dumper;
    $Data::Dumper::Indent = 1;

    my $descriptors = Danga::Socket->DescriptorMap;
    foreach my $fd (keys %$descriptors) {
        my $pob = $descriptors->{$fd};
        if ($pob->isa("Qpsmtpd::PollServer")) {
            if ($pob + 0 == hex($ref)) {
                return Data::Dumper::Dumper($pob);
            }
        }
    }

    return "Unable to find the connection: $ref. Try the LIST command\n";
}

1;
__END__

=head1 NAME

Qpsmtpd::ConfigServer - a configuration server for qpsmtpd

=head1 DESCRIPTION

When qpsmtpd runs in multiplex mode it also provides a config server that you
can connect to. This allows you to view current connection statistics and other
gumph that you probably don't care about.

=cut
