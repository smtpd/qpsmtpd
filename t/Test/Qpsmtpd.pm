package Test::Qpsmtpd;
use strict;
use Carp qw(croak);
use base qw(Qpsmtpd::SMTP);
use Test::More;
use Qpsmtpd::Constants;

sub new_conn {
  ok(my $smtpd = __PACKAGE__->new(), "new");
  ok(my $conn  = $smtpd->start_connection(remote_host => 'localhost',
                                          remote_ip => '127.0.0.1'), "start_connection");
  is(($smtpd->response)[0], "220", "greetings");
  ($smtpd, $conn);
}

sub start_connection {
    my $self = shift;
    my %args = @_;

    my $remote_host = $args{remote_host} or croak "no remote_host parameter";
    my $remote_info = "test\@$remote_host";
    my $remote_ip   = $args{remote_ip} or croak "no remote_ip parameter";
    
    my $conn = $self->SUPER::connection->start(remote_info => $remote_info,
                                               remote_ip   => $remote_ip,
                                               remote_host => $remote_host,
                                               @_);


    $self->load_plugins;

    my $rc = $self->start_conversation;
    return if $rc != DONE;

    $conn;
}

sub respond {
  my $self = shift;
  $self->{_response} = [@_]; 
}

sub response {
  my $self = shift; 
  $self->{_response} ? (@{ delete $self->{_response} }) : ();
}

sub command {
  my ($self, $command) = @_;
  $self->input($command);
  $self->response;
}

sub input {
  my $self    = shift;
  my $command = shift;

  my $timeout = $self->config('timeout');
  alarm $timeout;

  $command =~ s/\r?\n$//s; # advanced chomp
  $self->log(LOGDEBUG, "dispatching $_");
  defined $self->dispatch(split / +/, $command, 2)
      or $self->respond(502, "command unrecognized: '$command'");
  alarm $timeout;
}

# sub run
# sub disconnect


1;

