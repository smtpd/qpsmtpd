package Qpsmtpd::TcpServer;
use Qpsmtpd;
@ISA = qw(Qpsmtpd);
use strict;

sub start_connection {
    my $self = shift;

    die "Qpsmtpd::TcpServer must be started by tcpserver\n"
      unless $ENV{TCPREMOTEIP};

    my $remote_host = $ENV{TCPREMOTEHOST} || ( $ENV{TCPREMOTEIP} ? "[$ENV{TCPREMOTEIP}]" : "[noip!]");
    my $remote_info = $ENV{TCPREMOTEINFO} ? "$ENV{TCPREMOTEINFO}\@$remote_host" : $remote_host;
    my $remote_ip   = $ENV{TCPREMOTEIP};

    $self->SUPER::connection->start(remote_info => $remote_info,
				    remote_ip   => $remote_ip,
				    remote_host => $remote_host,
				    @_);
}

sub run {
    my $self = shift;

    # should be somewhere in Qpsmtpd.pm and not here...
    $self->load_plugins;

    $self->start_conversation;

    # this should really be the loop and read_input should just get one line; I think

    $self->read_input;
}

sub read_input {
  my $self = shift;

  my $timeout = $self->config('timeout');
  alarm $timeout;
  while (<STDIN>) {
    alarm 0;
    $_ =~ s/\r?\n$//s; # advanced chomp
    $self->log(1, "dispatching $_");
    defined $self->dispatch(split / +/, $_)
      or $self->respond(502, "command unrecognized: '$_'");
    alarm $timeout;
  }
}

sub respond {
  my ($self, $code, @messages) = @_;
  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(1, "$line");
    print "$line\r\n" or ($self->log(1, "Could not print [$line]: $!"), return 0);
  }
  return 1;
}

sub disconnect {
  my $self = shift;
  $self->SUPER::disconnect(@_);
  exit;
}

1;
