# $Id: Server.pm,v 1.10 2005/02/14 22:04:48 msergeant Exp $

package Qpsmtpd::PollServer;

use base ('Danga::Client', 'Qpsmtpd::SMTP');
# use fields required to be a subclass of Danga::Client. Have to include
# all fields used by Qpsmtpd.pm here too.
use fields qw(
    input_sock
    mode
    header_lines
    in_header
    data_size
    max_size
    hooks
    start_time
    _auth
    _auth_user
    _auth_mechanism
    _commands
    _config_cache
    _connection
    _transaction
    _test_mode
    _extras
    _continuation
);
use Qpsmtpd::Constants;
use Qpsmtpd::Auth;
use Qpsmtpd::Address;
use Danga::DNS;
use Mail::Header;
use POSIX qw(strftime);
use Socket qw(inet_aton AF_INET CRLF);
use Time::HiRes qw(time);
use strict;

sub max_idle_time { 60 }
sub max_connect_time { 1200 }

sub input_sock {
    my $self = shift;
    @_ and $self->{input_sock} = shift;
    $self->{input_sock} || $self;
}

sub new {
    my Qpsmtpd::PollServer $self = shift;
    
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new( @_ );
    $self->{start_time} = time;
    $self->{mode} = 'connect';
    $self->load_plugins;
    return $self;
}

sub uptime {
    my Qpsmtpd::PollServer $self = shift;
    
    return (time() - $self->{start_time});
}

sub reset_for_next_message {
    my $self = shift;
    $self->SUPER::reset_for_next_message(@_);
    
    $self->{_commands} = {
        ehlo => 1,
        helo => 1,
        rset => 1,
        mail => 1,
        rcpt => 1,
        data => 1,
        help => 1,
        vrfy => 1,
        noop => 1,
        quit => 1,
        auth => 0, # disabled by default
    };
    $self->{mode} = 'cmd';
    $self->{_extras} = {};
}

sub respond {
    my $self = shift;
    my ($code, @messages) = @_;
    while (my $msg = shift @messages) {
        my $line = $code . (@messages ? "-" : " ") . $msg;
        $self->write("$line\r\n");
    }
    return 1;
}

sub fault {
    my $self = shift;
    $self->SUPER::fault(@_);
    return;
}

sub process_line {
    my $self = shift;
    my $line = shift || return;
    if ($::DEBUG > 1) { print "$$:".($self+0)."C($self->{mode}): $line"; }
    local $SIG{ALRM} = sub {
        my ($pkg, $file, $line) = caller();
        die "ALARM: ($self->{mode}) $pkg, $file, $line";
    };
    my $prev = alarm(2); # must process a command in < 2 seconds
    eval { $self->_process_line($line) };
    alarm($prev);
    if ($@) {
        print STDERR "Error: $@\n";
        return $self->fault("command failed unexpectedly") if $self->{mode} eq 'cmd';
        return $self->fault("error processing data lines") if $self->{mode} eq 'data';
        return $self->fault("unknown error");
    }
    return;
}

sub _process_line {
    my $self = shift;
    my $line = shift;
    
    if ($self->{mode} eq 'connect') {
        $self->{mode} = 'cmd';
        my $rc = $self->start_conversation;
        return;
    }
    elsif ($self->{mode} eq 'cmd') {
        $line =~ s/\r?\n//;
        return $self->process_cmd($line);
    }
    elsif ($self->{mode} eq 'data') {
        return $self->data_line($line);
    }
    else {
        die "Unknown mode";
    }
}

sub process_cmd {
    my $self = shift;
    my $line = shift;
    my ($cmd, @params) = split(/ +/, $line);
    my $meth = lc($cmd);
    if (my $lookup = $self->{_commands}->{$meth} && $self->can($meth)) {
        my $resp = eval {
            $lookup->($self, @params);
        };
        if ($@) {
            my $error = $@;
            chomp($error);
            $self->log(LOGERROR, "Command Error: $error");
            return $self->fault("command '$cmd' failed unexpectedly");
        }
        return $resp;
    }
    else {
        # No such method - i.e. unrecognized command
        my ($rc, $msg) = $self->run_hooks("unrecognized_command", $meth, @params);
        return $self->unrecognized_command_respond($rc, $msg) unless $rc == CONTINUATION;
        return 1;
    }
}

sub disconnect {
    my $self = shift;
    $self->SUPER::disconnect(@_);
    $self->close;
}

sub start_conversation {
    my $self = shift;
    
    my $conn = $self->connection;
    # set remote_host, remote_ip and remote_port
    my ($ip, $port) = split(':', $self->peer_addr_string);
    $conn->remote_ip($ip);
    $conn->remote_port($port);
    $conn->remote_info("[$ip]");
    Danga::DNS->new(
        client     => $self,
        # NB: Setting remote_info to the same as remote_host
        callback   => sub { $conn->remote_info($conn->remote_host($_[0])) },
        host       => $ip,
    );
    
    my ($rc, $msg) = $self->run_hooks("connect");
    return $self->connect_respond($rc, $msg) unless $rc == CONTINUATION;
    return DONE;
}

sub data {
    my $self = shift;
    
    my ($rc, $msg) = $self->run_hooks("data");
    return $self->data_respond($rc, $msg) unless $rc == CONTINUATION;
    return 1;
}

sub data_respond {
    my ($self, $rc, $msg) = @_;
    if ($rc == DONE) {
        return;
    }
    elsif ($rc == DENY) {
        $self->respond(554, $msg || "Message denied");
        $self->reset_transaction();
        return;
    }
    elsif ($rc == DENYSOFT) {
        $self->respond(451, $msg || "Message denied temporarily");
        $self->reset_transaction();
        return;
    } 
    elsif ($rc == DENY_DISCONNECT) {
        $self->respond(554, $msg || "Message denied");
        $self->disconnect;
        return;
    }
    elsif ($rc == DENYSOFT_DISCONNECT) {
        $self->respond(451, $msg || "Message denied temporarily");
        $self->disconnect;
        return;
    }
    return $self->respond(503, "MAIL first") unless $self->transaction->sender;
    return $self->respond(503, "RCPT first") unless $self->transaction->recipients;
    
    $self->{mode} = 'data';
    
    $self->{header_lines} = [];
    $self->{data_size} = 0;
    $self->{in_header} = 1;
    $self->{max_size} = ($self->config('databytes'))[0] || 0;  # this should work in scalar context
    
    $self->log(LOGDEBUG, "max_size: $self->{max_size} / size: $self->{data_size}");
    
    return $self->respond(354, "go ahead");
}

sub data_line {
    my $self = shift;
    
    my $line = shift;
    
    if ($line eq ".\r\n") {
        # add received etc.
        $self->{mode} = 'cmd';
        return $self->end_of_data;
    }

    # Reject messages that have either bare LF or CR. rjkaes noticed a
    # lot of spam that is malformed in the header.
    if ($line eq ".\n" or $line eq ".\r") {
        $self->respond(421, "See http://smtpd.develooper.com/barelf.html");
        $self->disconnect;
        return;
    }
    
    # add a transaction->blocked check back here when we have line by line plugin access...
    unless (($self->{max_size} and $self->{data_size} > $self->{max_size})) {
        $line =~ s/\r\n$/\n/;
        $line =~ s/^\.\./\./;
        
        if ($self->{in_header} and $line =~ m/^\s*$/) {
            # end of headers
            $self->{in_header} = 0;
            
            # ... need to check that we don't reformat any of the received lines.
            #
            # 3.8.2 Received Lines in Gatewaying
            #   When forwarding a message into or out of the Internet environment, a
            #   gateway MUST prepend a Received: line, but it MUST NOT alter in any
            #   way a Received: line that is already in the header.
    
            my $header = Mail::Header->new($self->{header_lines},
                                            Modify => 0, MailFrom => "COERCE");
            $self->transaction->header($header);

            #$header->add("X-SMTPD", "qpsmtpd/".$self->version.", http://smtpd.develooper.com/");
    
            # FIXME - call plugins to work on just the header here; can
            # save us buffering the mail content.
        }

        if ($self->{in_header}) {
            push @{ $self->{header_lines} }, $line;
        }
        else {
            $self->transaction->body_write($line);
        }
        
        $self->{data_size} += length $line;
    }
    
    return;
}

sub end_of_data {
    my $self = shift;
    
    #$self->log(LOGDEBUG, "size is at $size\n") unless ($i % 300);
    
    $self->log(LOGDEBUG, "max_size: $self->{max_size} / size: $self->{data_size}");
    
    my $smtp = $self->connection->hello eq "ehlo" ? "ESMTP" : "SMTP";
    
    my $header = $self->transaction->header;
    if (!$header) {
        $header = Mail::Header->new(Modify => 0, MailFrom => "COERCE");
        $self->transaction->header($header);
    }
    
    # only true if client authenticated
    if ( defined $self->{_auth} and $self->{_auth} == OK ) { 
        $header->add("X-Qpsmtpd-Auth","True");
    }
    
    $header->add("Received", "from ".$self->connection->remote_info
                 ." (HELO ".$self->connection->hello_host . ") (".$self->connection->remote_ip
                 . ")\n  by ".$self->config('me')." (qpsmtpd/".$self->version
                 .") with $smtp; ". (strftime('%a, %d %b %Y %H:%M:%S %z', localtime)),
                  0);
    
    return $self->respond(552, "Message too big!") if $self->{max_size} and $self->{data_size} > $self->{max_size};
    
    my ($rc, $msg) = $self->run_hooks("data_post");
    return $self->data_post_respond($rc, $msg) unless $rc == CONTINUATION;
    return 1;
}

1;

