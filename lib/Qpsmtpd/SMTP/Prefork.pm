package Qpsmtpd::SMTP::Prefork;
use Qpsmtpd::SMTP;
use Qpsmtpd::Constants;
@ISA = qw(Qpsmtpd::SMTP);

sub dispatch {
  my $self = shift;
  my ($cmd) = lc shift;

  $self->{_counter}++; 

  if ($cmd !~ /^(\w{1,12})$/ or !exists $self->{_commands}->{$1}) {
    my ($rc, @msg) = $self->run_hooks("unrecognized_command", $cmd, @_);
    @msg = map { split /\n/ } @msg;
    if ($rc == DENY_DISCONNECT) {
      $self->respond(521, @msg);
      $self->disconnect;
    }
    elsif ($rc == DENY) {
      $self->respond(500, @msg);
    }
    elsif ($rc == DONE) {
      1;
    }
    else {
      $self->respond(500, "Unrecognized command");
    }
    return 1
  }
  $cmd = $1;

  if (1 or $self->{_commands}->{$cmd} and $self->can($cmd)) {
    my ($result) = eval { $self->$cmd(@_) };
    if ($@ =~ /^disconnect_tcpserver/) {
    	die "disconnect_tcpserver"; 
    } elsif ($@) {
      $self->log(LOGERROR, "XX: $@") if $@;
    }
    return $result if defined $result;
    return $self->fault("command '$cmd' failed unexpectedly");
  }

  return;
}
