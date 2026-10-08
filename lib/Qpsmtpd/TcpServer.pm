package Qpsmtpd::TcpServer;
use strict;

use POSIX ();
use Socket;
use IO::Select;

use lib 'lib';
use Qpsmtpd::Constants;
use parent 'Qpsmtpd::SMTP';

my $first_0;

sub start_connection {
    my ($self, %info) = @_;

    # a PTR record can hold ANSI escapes, which would reach ps output via $0
    $info{remote_host} =~ tr/a-zA-Z.:0-9[]-//cd;
    $info{remote_info} //= $info{remote_host};
    $self->log(LOGNOTICE, "Connection from $info{remote_info} [$info{remote_ip}]");

    $first_0 = $0 unless $first_0;
    my $now = POSIX::strftime("%H:%M:%S %Y-%m-%d", localtime);
    $0 = "$first_0 [$info{remote_ip} : $info{remote_host} : $now]";

    $self->SUPER::connection->start(%info);
}

sub run {
    my ($self, $client) = @_;

# Set local client_socket to passed client object for testing socket state on writes
    $self->{__client_socket} = $client;

    $self->load_plugins if !$self->{hooks};

    my $rc = $self->start_conversation;
    return if $rc != DONE;

# this should really be the loop and read_input should just get one line; I think
    $self->read_input;
}

sub read_input {
    my $self = shift;

    my $timeout = $self->config('timeoutsmtpd')    # qmail smtpd control file
      || $self->config('timeout')                  # qpsmtpd control file
      || 1200;                                     # default value

    alarm $timeout;
    while (<STDIN>) {
        alarm 0;
        $_ =~ s/\r?\n$//s;                         # advanced chomp
        last if $self->command_line_too_long($_);
        my $log = $_;
        $log =~ s/AUTH PLAIN (.*)/AUTH PLAIN <hidden credentials>/
          unless ($self->config('loglevel') || '6') >= 7;
        $self->log(LOGINFO, "dispatching $log");
        $self->connection->notes('original_string', $_);
        defined $self->dispatch(split / +/, $_, 2)
          or $self->respond(502, "command unrecognized: '$_'");
        alarm $timeout;
    }
    alarm(0);
    return if $self->connection->notes('disconnected');
    $self->reset_transaction;
    $self->run_hooks('disconnect');
    $self->connection->notes(disconnected => 1);
}

sub respond {
    my ($self, $code, @messages) = @_;
    my $buf = '';

    if (!$self->check_socket()) {
        $self->log(LOGERROR,
                   "Lost connection to client, cannot send response.");
        return 0;
    }

    while (my $msg = shift @messages) {
        my $line = $code . (@messages ? "-" : " ") . $msg;
        $self->log(LOGINFO, $line);
        $buf .= "$line\r\n";
    }
    print $buf
      or ($self->log(LOGERROR, "Could not print [$buf]: $!"), return 0);
    return 1;
}

sub disconnect {
    my $self = shift;
    $self->log(LOGINFO, "click, disconnecting");
    $self->SUPER::disconnect(@_);
    $self->run_hooks("post-connection");
    $self->connection->reset;
    exit;
}

sub check_socket() {
    my $self = shift;

    my $sock = $self->{__client_socket} or return 1;
    return 0 if !$sock->connected;

    # A client that gave up and sent FIN still reports ->connected until the
    # socket is fully closed. Detect that half-closed state: if the socket is
    # readable but a non-destructive peek returns no data, the peer is gone.
    return 1 if !IO::Select->new($sock)->can_read(0);
    my $peek = '';
    my $rv = recv($sock, $peek, 1, MSG_PEEK);
    return 0 if defined $rv && $peek eq '';
    return 1;
}

1;
