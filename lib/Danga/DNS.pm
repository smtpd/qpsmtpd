# $Id: DNS.pm,v 1.12 2005/02/14 22:06:08 msergeant Exp $

package Danga::DNS;

# This is the query class - it is really just an encapsulation of the
# hosts you want to query, plus the callback. All the hard work is done
# in Danga::DNS::Resolver.

use fields qw(client hosts num_hosts callback results start);
use strict;

use Danga::DNS::Resolver;

my $resolver;

sub trace {
    my $level = shift;
    print ("[$$] dns lookup: @_") if $::DEBUG >= $level;
}

sub new {
    my Danga::DNS $self = shift;
    my %options = @_;

    $resolver ||= Danga::DNS::Resolver->new();
    
    my $client = $options{client};
    $client->disable_read if $client;
    
    $self = fields::new($self) unless ref $self;

    $self->{hosts} = $options{hosts} ? $options{hosts} : [ $options{host} ];
    $self->{num_hosts} = scalar(@{$self->{hosts}}) || "No hosts supplied";
    $self->{client} = $client;
    $self->{callback} = $options{callback} || die "No callback given";
    $self->{results} = {};
    $self->{start} = time;

    if ($options{type}) {
        if ($options{type} eq 'TXT') {
            if (!$resolver->query_txt($self, @{$self->{hosts}})) {
                $client->watch_read(1) if $client;
                return;
            }
        }
        elsif ($options{type} eq 'A') {
            if (!$resolver->query($self, @{$self->{hosts}})) {
                $client->watch_read(1) if $client;
                return;
            }
        }
        elsif ($options{type} eq 'PTR') {
            if (!$resolver->query($self, @{$self->{hosts}})) {
                $client->watch_read(1) if $client;
                return;
            }
        }
        elsif ($options{type} eq 'MX') {
            if (!$resolver->query_mx($self, @{$self->{hosts}})) {
                $client->watch_read(1) if $client;
                return;
            }
        }
        else {
            die "Unsupported DNS query type: $options{type}";
        }
    }
    else {
        if (!$resolver->query($self, @{$self->{hosts}})) {
            $client->watch_read(1) if $client;
            return;
        }
    }
    
    return $self;
}

sub run_callback {
    my Danga::DNS $self = shift;
    my ($result, $query) = @_;
    $self->{results}{$query} = $result;
    trace(2, "got $query => $result\n");
    eval {
        $self->{callback}->($result, $query);
    };
    if ($@) {
        warn($@);
    }
}

sub DESTROY {
    my Danga::DNS $self = shift;
    my $now = time;
    foreach my $host (@{$self->{hosts}}) {
        if (!$self->{results}{$host}) {
            print "DNS timeout (presumably) looking for $host after " . ($now - $self->{start}) . " secs\n";
            $self->{callback}->("NXDOMAIN", $host);
        }
    }
    $self->{client}->enable_read if $self->{client};
}

1;

=head1 NAME

Danga::DNS - a DNS lookup class for the Danga::Socket framework

=head1 SYNOPSIS

  Danga::DNS->new(%options);

=head1 DESCRIPTION

This module performs asynchronous DNS lookups, making use of a single UDP
socket (unlike Net::DNS's bgsend/bgread combination), and blocking reading on
a client until the response comes back (this is useful for e.g. SMTP rDNS
lookups where you want the answer before you see the next SMTP command).

Currently this module will only perform A or PTR lookups. A rDNS (PTR) lookup
will be performed if the host matches the regexp: C</^\d+\.\d+\.\d+.\d+$/>.

The lookups time out after 15 seconds.

=head1 API

=head2 C<< Danga::DNS->new( %options ) >>

Create a new DNS query. You do not need to store the resulting object as this
class is all done with callbacks.

Example:

  Danga::DNS->new(
    callback => sub { print "Got result: $_[0]\n" },
    host => 'google.com',
    );

=over 4

=item B<[required]> C<callback>

The callback to call when results come in. This should be a reference to a
subroutine. The callback receives two parameters - the result of the DNS lookup
and the host that was looked up.

=item C<host>

A host name to lookup. Note that if the hostname is a dotted quad of numbers then
a reverse DNS (PTR) lookup is performend.

=item C<hosts>

An array-ref list of hosts to lookup.

B<NOTE:> One of either C<host> or C<hosts> is B<required>.

=item C<client>

It is possible to specify a C<Danga::Client> object (or subclass) which you wish
to disable for reading until your DNS result returns.

=item C<type>

You can specify one of: I<"A">, I<"PTR"> or I<"TXT"> here. Other types may be
supported in the future.

=back

=cut
