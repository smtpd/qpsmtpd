package Qpsmtpd::TcpServer;
use strict;
use base qw(Qpsmtpd);

sub start_connection {
    my $self = shift;

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

    $self->start_conversation;

    # this should really be the loop and read_input should just get one line; I think
    
    $self->read_input;
}

sub read_input {
  my $self = shift;
  alarm $self->config('timeout');
  while (<STDIN>) {
    alarm 0;
    $_ =~ s/\r?\n$//s; # advanced chomp
    $self->log(1, "dispatching $_");
    defined $self->dispatch(split / +/, $_)
      or $self->respond(502, "command unrecognized: '$_'");
    alarm $self->config('timeout');
  }
}

sub respond {
  my ($self, $code, @messages) = @_;
  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(1, "$line");
    print "$line\r\n" or ($self->log("Could not print [$line]: $!"), return 0);
  }
  return 1;
}


1;
