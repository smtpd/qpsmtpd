package Test::FakeResolver;

# Answers queries from a table: {name => {A => [...], TXT => [...]}}, or
# {name => {error => 'SERVFAIL'}}. Any other name is NXDOMAIN.

use strict;
use warnings;

use Net::DNS;

sub new { my ($class, %zone) = @_; return bless {zone => \%zone}, $class }
sub errorstring { return $_[0]{error} }

sub query {
    my ($self, $name, $type) = @_;
    $type ||= 'A';
    my $zone = $self->{zone}{$name};
    $self->{error} = $zone ? $zone->{error} || 'NOERROR' : 'NXDOMAIN';
    my @data = $zone && $zone->{$type} ? @{$zone->{$type}} : () or return;
    my $packet = Net::DNS::Packet->new($name, $type);
    $packet->push(answer => Net::DNS::RR->new(
        $type eq 'TXT' ? "$name 60 TXT \"$_\"" : "$name 60 $type $_"))
      for @data;
    return $packet;
}

1;
