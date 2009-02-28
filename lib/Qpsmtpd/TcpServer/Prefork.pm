package Qpsmtpd::TcpServer::Prefork;
use Qpsmtpd::TcpServer;
use Qpsmtpd::SMTP::Prefork;
use Qpsmtpd::Constants;

@ISA = qw(Qpsmtpd::SMTP::Prefork Qpsmtpd::TcpServer);

my $first_0; 

sub start_connection {
    my $self = shift;

    #reset info
    $self->{_connection} = Qpsmtpd::Connection->new(); #reset connection
    $self->reset_transaction;
    $self->SUPER::start_connection(@_);
}

sub read_input {
  my $self = shift;

  my $timeout =
    $self->config('timeoutsmtpd')   # qmail smtpd control file
      || $self->config('timeout')   # qpsmtpd control file
        || 1200;                    # default value

  alarm $timeout;
  eval {
    while (<STDIN>) {
      alarm 0;
      $_ =~ s/\r?\n$//s; # advanced chomp
      $self->log(LOGINFO, "dispatching $_");
      $self->connection->notes('original_string', $_);
      defined $self->dispatch(split / +/, $_, 2)
        or $self->respond(502, "command unrecognized: '$_'");
      alarm $timeout;
    }
    unless ($self->connection->notes('disconnected')) {
      $self->reset_transaction;
      $self->run_hooks('disconnect');
      $self->connection->notes(disconnected => 1);
    }
  };
  if ($@ =~ /^disconnect_tcpserver/) {
  	die "disconnect_tcpserver";
  } else {
  	$self->run_hooks("post-connection");
	$self->connection->reset;
  	die "died while reading from STDIN (probably broken sender) - $@";
  }
  alarm(0);
}

sub respond {
  my ($self, $code, @messages) = @_;

  if ( !$self->check_socket() ) {
    $self->log(LOGERROR, "Lost connection to client, cannot send response.");
    return(0);
  }

  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(LOGINFO, $line);
    print "$line\r\n" or ($self->log(LOGERROR, "Could not print [$line]: $!"), return 0);
  }
  return 1;
}

sub disconnect {
  my $self = shift;
  $self->log(LOGINFO,"click, disconnecting");
  $self->SUPER::disconnect(@_);
  $self->run_hooks("post-connection");
  $self->connection->reset;
  die "disconnect_tcpserver";
}

1;
