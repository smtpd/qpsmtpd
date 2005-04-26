# $Id$

package Qpsmtpd::ConfigServer;

use base ('Danga::Client');

use fields qw(
    commands
    _auth
    _commands
    _config_cache
    _connection
    _transaction
    _test_mode
    _extras
);

sub new {
    my Qpsmtpd::ConfigServer $self = shift;
    
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new( @_ );
    $self->{commands} = { help => 1, status => 1, };
    $self->write("Enter command:\n");
    return $self;
}

sub process_line {
    my $self = shift;
    my $line = shift || return;
    if ($::DEBUG > 1) { print "$$:".($self+0)."C($self->{mode}): $line"; }
    local $SIG{ALRM} = sub {
        my ($pkg, $file, $line) = caller();
        die "ALARM: $pkg, $file, $line";
    };
    my $prev = alarm(2); # must process a command in < 2 seconds
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
  print STDERR "$0 [$$]: $msg ($!)\n";
  return $self->respond("Error - " . $msg, "Enter command:");
}

sub _process_line {
    my $self = shift;
    my $line = shift;

    $line =~ s/\r?\n//;
    my ($cmd, @params) = split(/ +/, $line);
    my $meth = lc($cmd);
    if (my $lookup = $self->{commands}->{$meth} && $self->can($meth)) {
        my $resp = eval {
            $lookup->($self, @params);
        };
        if ($@) {
            my $error = $@;
            chomp($error);
            $self->log(LOGERROR, "Command Error: $error");
            return $self->fault("command '$cmd' failed unexpectedly");
        }
        return $resp . "\nEnter command:\n";
    }
    else {
        # No such method - i.e. unrecognized command
        return $self->fault("command '$cmd' unrecognised");
    }
}

my %helptext = (
    all => "Available Commands:\n\nSTATUS\nHELP [CMD]",
    status => "STATUS - Returns status information about current connections",
    );

sub help {
    my $self = shift;
    my ($subcmd) = @_;
    
    $subcmd ||= 'all';
    $subcmd = lc($subcmd);
    
    my $txt = $helptext{$subcmd} || "Unrecognised help option. Try 'help all'";
    warn "help returning: $txt\n";
    return $txt . "\n";
}

sub status {
    my $self = shift;
    
    my $descriptors = Danga::Socket->DescriptorMap;
    
    my $current_connections = 0;
    my $current_dns = 0;
    foreach my $fd (keys %$descriptors) {
        my $pob = $descriptors->{$fd};
        if ($pob->isa("Qpsmtpd::PollServer")) {
            $current_connections++;
        }
        elsif ($pob->isa("Danga::DNS::Resolver")) {
            $current_dns = $pob->pending;
        }
    }
    
    return
"  Current Connections: $current_connections
  Current DNS Queries: $current_dns";
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