package Qpsmtpd::Transaction;
use strict;

sub new { start(@_) }

sub start {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;
  my $self = { _rcpt => [], started => time };
  bless ($self, $class);
}

sub add_header {
  my $self = shift;
}

sub add_recipient {
  my $self = shift;
  @_ and push @{$self->{_recipients}}, shift;
}

sub recipients {
  my $self = shift;
  ($self->{_recipients} ? @{$self->{_recipients}} : ());
}

sub sender {
  my $self = shift;
  @_ and $self->{_sender} = shift;
  $self->{_sender};

}

sub add_header_line {

}

sub add_body_line {

}

1;
