package Qpsmtpd::TcpServer;
use strict;

use POSIX ();
use Socket;

use lib 'lib';
use Qpsmtpd::Constants;
use parent 'Qpsmtpd::SMTP';

my $has_ipv6 = 0;
if (
    eval { require Socket6; } &&
    eval { require IO::Socket::INET6; IO::Socket::INET6->VERSION('2.51'); }
   )
{
    Socket6->import('inet_ntop');
    $has_ipv6 = 1;
}

sub has_ipv6 {
    return $has_ipv6;
}

my $first_0;

sub start_connection {
    my $self = shift;

    my (
        $remote_host, $remote_info, $remote_ip, $remote_port,
        $local_ip,    $local_port,  $local_host
       );

    if ($ENV{TCPREMOTEIP}) {

        # started from tcpserver (or some other superserver which
        # exports the TCPREMOTE* variables.
        $remote_ip = $ENV{TCPREMOTEIP};
        $remote_host = $ENV{TCPREMOTEHOST} || "[$remote_ip]";
        $remote_info =
          $ENV{TCPREMOTEINFO}
          ? "$ENV{TCPREMOTEINFO}\@$remote_host"
          : $remote_host;
        $remote_port = $ENV{TCPREMOTEPORT};
        $local_ip    = $ENV{TCPLOCALIP};
        $local_port  = $ENV{TCPLOCALPORT};
        $local_host  = $ENV{TCPLOCALHOST};
    }
    else {
        # Started from inetd or similar.
        # get info on the remote host from the socket.
        # ignore ident/tap/...
        my $hersockaddr = getpeername(STDIN)
          or die
"getpeername failed: $0 must be called from tcpserver, (x)inetd or a similar program which passes a socket to stdin";
        my ($port, $iaddr) = sockaddr_in($hersockaddr);
        $remote_ip   = inet_ntoa($iaddr);
        $remote_host = gethostbyaddr($iaddr, AF_INET) || "[$remote_ip]";
        $remote_info = $remote_host;
    }
    $self->log(LOGNOTICE, "Connection from $remote_info [$remote_ip]");

    # if the local dns resolver doesn't filter it out we might get
    # ansi escape characters that could make a ps axw do "funny"
    # things. So to be safe, cut them out.
    $remote_host =~ tr/a-zA-Z\.\-0-9\[\]//cd;

    $first_0 = $0 unless $first_0;
    my $now = POSIX::strftime("%H:%M:%S %Y-%m-%d", localtime);
    $0 = "$first_0 [$remote_ip : $remote_host : $now]";

    $self->SUPER::connection->start(
                                    remote_info => $remote_info,
                                    remote_ip   => $remote_ip,
                                    remote_host => $remote_host,
                                    remote_port => $remote_port,
                                    local_ip    => $local_ip,
                                    local_port  => $local_port,
                                    local_host  => $local_host,
                                    @_
                                   );
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
        $self->log(LOGINFO, "dispatching $_");
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

# local/remote port and ip address
sub lrpip {
    my ($self, $server, $client, $hisaddr) = @_;

    my $localsockaddr = getsockname($client);
    my ($port, $iaddr, $lport, $laddr, $nto_iaddr, $nto_laddr);

    if ($server->sockdomain == AF_INET6) {      # IPv6
        ($port, $iaddr) = sockaddr_in6($hisaddr);
        ($lport, $laddr) = sockaddr_in6($localsockaddr);
        $nto_iaddr = inet_ntop(AF_INET6(), $iaddr);
        $nto_laddr = inet_ntop(AF_INET6(), $laddr);
    }
    else {                                     # IPv4
        ($port, $iaddr) = sockaddr_in($hisaddr);
        ($lport, $laddr) = sockaddr_in($localsockaddr);
        $nto_iaddr = inet_ntoa($iaddr);
        $nto_laddr = inet_ntoa($laddr);
    }

    $nto_iaddr =~ s/::ffff://;
    $nto_laddr =~ s/::ffff://;

    return $port, $iaddr, $lport, $laddr, $nto_iaddr, $nto_laddr;
}

sub tcpenv {
    my ($self, $TCPLOCALIP, $TCPREMOTEIP, $no_rdns) = @_;

    if ($no_rdns) {
        return $TCPLOCALIP, $TCPREMOTEIP,
               $TCPREMOTEIP ? "[$ENV{TCPREMOTEIP}]" : "[noip!]";
    }
    my ($TCPREMOTEHOST) = $self->resolve_ptr($TCPREMOTEIP) || 'Unknown';
    return $TCPLOCALIP, $TCPREMOTEIP, $TCPREMOTEHOST;
}

sub check_socket() {
    my $self = shift;

    return 1 if ($self->{__client_socket}->connected);

    return 0;
}

1;
