package Qpsmtpd::Connection;
use strict;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);
}

sub start {
  my $self = shift;
  $self = $self->new(@_) unless ref $self;

  my %args = @_;

  for my $f (qw(remote_host remote_ip remote_info)) {
    $self->$f($args{$f}) if $args{$f};
  }

  return $self;
}

sub remote_host {
  my $self = shift;
  @_ and $self->{_remote_host} = shift;
  $self->{_remote_host};
}

sub remote_ip {
  my $self = shift;
  @_ and $self->{_remote_ip} = shift;
  $self->{_remote_ip};
}

sub remote_info {
  my $self = shift;
  @_ and $self->{_remote_info} = shift;
  $self->{_remote_info};
}

sub hello {
  my $self = shift;
  @_ and $self->{_hello} = shift;
  $self->{_hello};
}

sub hello_host {
  my $self = shift;
  @_ and $self->{_hello_host} = shift;
  $self->{_hello_host};
}


1;
