package Qpsmtpd::Transaction;
use strict;

sub new { start(@_) }

sub start {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;
  my $self = { _rcpt => [] };
  bless ($self, $class);
}

sub add_header {
  my $self = shift;
}

sub add_recipient {
  my $self = shift;

}

sub sender {
  my $self = shift;
  @_ and $self->{_sender} = shift;
  $self->{_sender};

}

1;
