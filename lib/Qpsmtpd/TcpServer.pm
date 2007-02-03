package Qpsmtpd::TcpServer;
use Qpsmtpd::SMTP;
use Qpsmtpd::Constants;
use Socket;

@ISA = qw(Qpsmtpd::SMTP);
use strict;

use POSIX ();

my $first_0; 

sub start_connection {
    my $self = shift;

    my ($remote_host, $remote_info, $remote_ip);

    if ($ENV{TCPREMOTEIP}) {
	# started from tcpserver (or some other superserver which
	# exports the TCPREMOTE* variables.
	$remote_ip   = $ENV{TCPREMOTEIP};
	$remote_host = $ENV{TCPREMOTEHOST} || "[$remote_ip]";
	$remote_info = $ENV{TCPREMOTEINFO} ? "$ENV{TCPREMOTEINFO}\@$remote_host" : $remote_host;
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
    $remote_host =~ tr/a-zA-Z\.\-0-9//cd;

    $first_0 = $0 unless $first_0;
    my $now = POSIX::strftime("%H:%M:%S %Y-%m-%d", localtime);
    $0 = "$first_0 [$remote_ip : $remote_host : $now]";

    $self->SUPER::connection->start(remote_info => $remote_info,
				    remote_ip   => $remote_ip,
				    remote_host => $remote_host,
				    @_);
}

sub run {
    my $self = shift;

    # should be somewhere in Qpsmtpd.pm and not here...
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
}

sub respond {
  my ($self, $code, @messages) = @_;
  my $buf = '';
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
  exit;
}

1;
