package Qpsmtpd::TcpServer;
use Qpsmtpd::SMTP;
use Qpsmtpd::Constants;
use Socket;

@ISA = qw(Qpsmtpd::SMTP);
use strict;

use POSIX ();

my $has_ipv6;
if (
    eval {require Socket6;} &&
    # INET6 prior to 2.01 will not work; sorry.
    eval {require IO::Socket::INET6; IO::Socket::INET6->VERSION("2.00");}
    ) {
    import Socket6;
    $has_ipv6=1;
}
else {
    $has_ipv6=0;
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
	$remote_ip   = $ENV{TCPREMOTEIP};
	$remote_host = $ENV{TCPREMOTEHOST} || "[$remote_ip]";
	$remote_info = $ENV{TCPREMOTEINFO} ? "$ENV{TCPREMOTEINFO}\@$remote_host" : $remote_host;
        $remote_port = $ENV{TCPREMOTEPORT};
        $local_ip    = $ENV{TCPLOCALIP};
        $local_port  = $ENV{TCPLOCALPORT};
        $local_host  = $ENV{TCPLOCALHOST};
    } else {
	# Started from inetd or similar.
	# get info on the remote host from the socket.
	# ignore ident/tap/...
	my $hersockaddr    = getpeername(STDIN)
	    or die "getpeername failed: $0 must be called from tcpserver, (x)inetd or a similar program which passes a socket to stdin";
	my ($port, $iaddr) = sockaddr_in($hersockaddr);
	$remote_ip     = inet_ntoa($iaddr);
	$remote_host    = gethostbyaddr($iaddr, AF_INET) || "[$remote_ip]";
	$remote_info	= $remote_host;
    }
    $self->log(LOGNOTICE, "Connection from $remote_info [$remote_ip]");

    # if the local dns resolver doesn't filter it out we might get
    # ansi escape characters that could make a ps axw do "funny"
    # things. So to be safe, cut them out.
    $remote_host =~ tr/a-zA-Z\.\-0-9\[\]//cd;

    $first_0 = $0 unless $first_0;
    my $now = POSIX::strftime("%H:%M:%S %Y-%m-%d", localtime);
    $0 = "$first_0 [$remote_ip : $remote_host : $now]";

    $self->SUPER::connection->start(remote_info => $remote_info,
                                    remote_ip   => $remote_ip,
                                    remote_host => $remote_host,
                                    remote_port => $remote_port,
                                    local_ip    => $local_ip,
                                    local_port  => $local_port,
                                    local_host  => $local_host,
				    @_);
}

sub run {
    my ($self, $client) = @_;

    # Set local client_socket to passed client object for testing socket state on writes
    $self->{__client_socket} = $client;

    $self->load_plugins unless $self->{hooks};

    my $rc = $self->start_conversation;
    return if $rc != DONE;

    # this should really be the loop and read_input should just get one line; I think
    $self->read_input;
}

sub read_input {
  my $self = shift;

  my $timeout =
    $self->config('timeoutsmtpd')   # qmail smtpd control file
      || $self->config('timeout')   # qpsmtpd control file
        || 1200;                    # default value

  alarm $timeout;
  while (<STDIN>) {
    alarm 0;
    $_ =~ s/\r?\n$//s; # advanced chomp
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

  if ( !$self->check_socket() ) {
    $self->log(LOGERROR, "Lost connection to client, cannot send response.");
    return(0);
  }

  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(LOGINFO, $line);
    $buf .= "$line\r\n";
  }
  print $buf or ($self->log(LOGERROR, "Could not print [$buf]: $!"), return 0);
  return 1;
}

sub disconnect {
  my $self = shift;
  $self->log(LOGINFO,"click, disconnecting");
  $self->SUPER::disconnect(@_);
  $self->run_hooks("post-connection");
  $self->connection->reset;
  exit;
}

# local/remote port and ip address
sub lrpip {
  my ($server, $client, $hisaddr) = @_;

  my ($port, $iaddr) = ($server->sockdomain == AF_INET) ? (sockaddr_in($hisaddr)) : (sockaddr_in6($hisaddr));
  my $localsockaddr = getsockname($client);
  my ($lport, $laddr) = ($server->sockdomain == AF_INET) ? (sockaddr_in($localsockaddr)) : (sockaddr_in6($localsockaddr));

  my $nto_iaddr = ($server->sockdomain == AF_INET) ? (inet_ntoa($iaddr)) : (inet_ntop(AF_INET6(), $iaddr));
  my $nto_laddr = ($server->sockdomain == AF_INET) ? (inet_ntoa($laddr)) : (inet_ntop(AF_INET6(), $laddr));
  $nto_iaddr =~ s/::ffff://;
  $nto_laddr =~ s/::ffff://;

  return ($port, $iaddr, $lport, $laddr, $nto_iaddr, $nto_laddr);
}

sub tcpenv {
  my ($nto_laddr, $nto_iaddr, $no_rdns) = @_;

  my $TCPLOCALIP  = $nto_laddr;
  my $TCPREMOTEIP = $nto_iaddr;

  if ($no_rdns) {
    return ($TCPLOCALIP, $TCPREMOTEIP, $TCPREMOTEIP ? "[$ENV{TCPREMOTEIP}]" : "[noip!]");
  }
  my $res = new Net::DNS::Resolver;
  $res->tcp_timeout(3);
  $res->udp_timeout(3);
  my $query = $res->query($nto_iaddr);
  my $TCPREMOTEHOST;
  if($query) {
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "PTR";
      $TCPREMOTEHOST = $rr->ptrdname;
    }
  }
  return ($TCPLOCALIP, $TCPREMOTEIP, $TCPREMOTEHOST || "Unknown");
}

sub check_socket() {
  my $self = shift;

  return 1 if ( $self->{__client_socket}->connected );

  return 0;
}

1;
