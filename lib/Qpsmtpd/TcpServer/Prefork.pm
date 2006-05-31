package Qpsmtpd::TcpServer::Prefork;
use Qpsmtpd::TcpServer;
use Qpsmtpd::SMTP::Prefork;

@ISA = qw(Qpsmtpd::SMTP::Prefork Qpsmtpd::TcpServer);

my $first_0; 

sub start_connection {
    my $self = shift;

    #reset info
    $self->{_connection} = Qpsmtpd::Connection->new(); #reset connection
    $self->{_transaction} = Qpsmtpd::Transaction->new(); #reset transaction
    $self->SUPER::start_connection();
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
      $self->log(LOGDEBUG, "dispatching $_");
      $self->connection->notes('original_string', $_);
      defined $self->dispatch(split / +/, $_)
        or $self->respond(502, "command unrecognized: '$_'");
      alarm $timeout;
    }
  };
  if ($@ =~ /^disconnect_tcpserver/) {
  	die "disconnect_tcpserver";
  } else {
  	die "died while reading from STDIN (probably broken sender) - $@";
  }
  alarm(0);
}

sub respond {
  my ($self, $code, @messages) = @_;
  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(LOGDEBUG, $line);
    print "$line\r\n" or ($self->log(LOGERROR, "Could not print [$line]: $!"), return 0);
  }
  return 1;
}

1;
