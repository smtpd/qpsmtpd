# $Id: Resolver.pm,v 1.3 2005/02/14 22:06:08 msergeant Exp $

package Danga::DNS::Resolver;
use base qw(Danga::Socket);

use fields qw(res dst cache cache_timeout queries);

use Net::DNS;
use Socket;
use strict;

our $last_cleanup = 0;

sub trace {
    my $level = shift;
    print ("$::DEBUG/$level [$$] dns lookup: @_") if $::DEBUG >= $level;
}

sub new {
    my Danga::DNS::Resolver $self = shift;
    
    $self = fields::new($self) unless ref $self;
    
    my $res = Net::DNS::Resolver->new;
    
    my $sock = IO::Socket::INET->new(       
            Proto => 'udp',
            LocalAddr => $res->{'srcaddr'},
            LocalPort => ($res->{'srcport'} || undef),
    ) || die "Cannot create socket: $!";
    IO::Handle::blocking($sock, 0);
    
    $self->{dst} = [];
    
    foreach my $ns (@{ $res->{nameservers} }) {
        trace(2, "Using nameserver $ns:$res->{port}\n");
        my $dst_sockaddr = sockaddr_in($res->{'port'}, inet_aton($ns));
        push @{$self->{dst}}, $dst_sockaddr;
    }
    
    $self->{res} = $res;
    $self->{queries} = {};
    $self->{cache} = {};
    $self->{cache_timeout} = {};
    
    $self->SUPER::new($sock);
    
    $self->watch_read(1);
    
    $self->AddTimer(5, sub { $self->_do_cleanup });
    
    return $self;
}

sub ns {
    my Danga::DNS::Resolver $self = shift;
    my $index = shift;
    return if $index > $#{$self->{dst}};
    return $self->{dst}->[$index];
}

sub pending {
    my Danga::DNS::Resolver $self = shift;
    
    return keys(%{$self->{queries}});
}

sub _query {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, $host, $type, $now) = @_;
    
    if ($ENV{NODNS}) {
        $asker->run_callback("NXDNS", $host);
        return 1;
    }
    if (exists $self->{cache}{$type}{$host}) {
        # print "CACHE HIT!\n";
        $asker->run_callback($self->{cache}{$type}{$host}, $host);
        return 1;
    }
    
    my $packet = $self->{res}->make_query_packet($host, $type);
    
    my $packet_data = $packet->data;
    my $id = $packet->header->id;
    
    my $query = Danga::DNS::Resolver::Query->new(
        $self, $asker, $host, $type, $now, $id, $packet_data,
        ) or return;
    $self->{queries}->{$id} = $query;
    
    return 1;
}

sub query_txt {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, @hosts) = @_;
    
    my $now = time();
    
    trace(2, "trying to resolve TXT: @hosts\n");

    foreach my $host (@hosts) {
        $self->_query($asker, $host, 'TXT', $now) || return;
    }
    
    return 1;
}

sub query_mx {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, @hosts) = @_;
    
    my $now = time();
    
    trace(2, "trying to resolve MX: @hosts\n");

    foreach my $host (@hosts) {
        $self->_query($asker, $host, 'MX', $now) || return;
    }
    
    return 1;
}

sub query {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, @hosts) = @_;
    
    my $now = time();
    
    trace(2, "trying to resolve A/PTR: @hosts\n");

    foreach my $host (@hosts) {
        $self->_query($asker, $host, 'A', $now) || return;
    }
    
    return 1;
}

sub _do_cleanup {
    my Danga::DNS::Resolver $self = shift;
    my $now = time;
    
    $self->AddTimer(5, sub { $self->_do_cleanup });
    
    my $idle = $self->max_idle_time;
    
    my @to_delete;
    while (my ($id, $obj) = each(%{$self->{queries}})) {
        if ($obj->{timeout} < ($now - $idle)) {
            push @to_delete, $id;
        }
    }
    
    foreach my $id (@to_delete) {
        my $query = delete $self->{queries}{$id};
        $query->timeout() and next;
        # add back in if timeout caused us to loop to next server
        $self->{queries}->{$id} = $query;
    }
    
    foreach my $type ('A', 'TXT', 'MX') {
        @to_delete = ();
        
        while (my ($query, $t) = each(%{$self->{cache_timeout}{$type}})) {
            if ($t < $now) {
                push @to_delete, $query;
            }
        }
        
        foreach my $q (@to_delete) {
            delete $self->{cache_timeout}{$type}{$q};
            delete $self->{cache}{$type}{$q};
         }
     }
}

# seconds max timeout!
sub max_idle_time { 30 }

# Danga::DNS
sub event_err { shift->close("dns socket error") }
sub event_hup { shift->close("dns socket error") }

sub event_read {
    my Danga::DNS::Resolver $self = shift;

    while (my $packet = $self->{res}->bgread($self->sock)) {
        my $err = $self->{res}->errorstring;
        my $answers = 0;
        my $header = $packet->header;
        my $id = $header->id;
        
        my $qobj = delete $self->{queries}->{$id};
        if (!$qobj) {
            trace(1, "No query for id: $id\n");
            return;
        }
        
        my $query = $qobj->{host};
        
        my $now = time();
        my @questions = $packet->question;
        #print STDERR "response to ", $questions[0]->string, "\n";
        foreach my $rr ($packet->answer) {
            # my $q = shift @questions;
            if ($rr->type eq "PTR") {
                my $rdns = $rr->ptrdname;
                # NB: Cached as an "A" lookup as there's no overlap and they
                # go through the same query() function above
                $self->{cache}{A}{$query} = $rdns;
                # $self->{cache_timeout}{A}{$query} = $now + 60; # should use $rr->ttl but that would cache for too long
                $self->{cache_timeout}{A}{$query} = $now + $rr->ttl;
                $qobj->run_callback($rdns);
            }
            elsif ($rr->type eq "A") {
                my $ip = $rr->address;
                $self->{cache}{A}{$query} = $ip;
                # $self->{cache_timeout}{A}{$query} = $now + 60; # should use $rr->ttl but that would cache for too long
                $self->{cache_timeout}{A}{$query} = $now + $rr->ttl;
                $qobj->run_callback($ip);
            }
            elsif ($rr->type eq "TXT") {
                my $txt = $rr->txtdata;
                $self->{cache}{TXT}{$query} = $txt;
                # $self->{cache_timeout}{TXT}{$query} = $now + 60; # should use $rr->ttl but that would cache for too long
                $self->{cache_timeout}{TXT}{$query} = $now + $rr->ttl;
                $qobj->run_callback($txt);
            }
            elsif ($rr->type eq "MX") {
                my $host = $rr->exchange;
                my $preference = $rr->preference;
                $self->{cache}{MX}{$query} = [$host, $preference];
                $self->{cache_timeout}{MX}{$query} = $now + $rr->ttl;
                $qobj->run_callback([$host, $preference]);
            }
            else {
                # came back, but not a PTR or A record
                $qobj->run_callback("UNKNOWN");
            }
            $answers++;
        }
        if (!$answers) {
            if ($err eq "NXDOMAIN") {
                # trace("found => NXDOMAIN\n");
                $qobj->run_callback("NXDOMAIN");
            }
            elsif ($err eq "SERVFAIL") {
                # try again???
                print "SERVFAIL looking for $query\n";
                #$self->query($asker, $query);
                $qobj->error($err) and next;
                # add back in if error() resulted in query being re-issued
                $self->{queries}->{$id} = $qobj;
            }
            elsif ($err eq "NOERROR") {
                $qobj->run_callback($err);
            }
            elsif($err) {
                print("error: $err\n");
                $qobj->error($err) and next;
                $self->{queries}->{$id} = $qobj;
            }
            else {
                # trace("no answers\n");
                $qobj->run_callback("NOANSWER");
            }
        }
    }
}

use Carp qw(confess);

sub close {
    my Danga::DNS::Resolver $self = shift;
    
    $self->SUPER::close(shift);
    # confess "Danga::DNS::Resolver socket should never be closed!";
}

package Danga::DNS::Resolver::Query;

use constant MAX_QUERIES => 10;

sub trace {
    my $level = shift;
    print ("$::DEBUG/$level [$$] dns lookup: @_") if $::DEBUG >= $level;
}

sub new {
    my ($class, $res, $asker, $host, $type, $now, $id, $data) = @_;
    
    my $self = {
        resolver    => $res,
        asker       => $asker,
        host        => $host,
        type        => $type,
        timeout     => $now,
        id          => $id,
        data        => $data,
        repeat      => 2, # number of retries
        ns          => 0,
        nqueries    => 0,
    };
    
    trace(2, "NS Query: $host ($id)\n");

    bless $self, $class;
    
    $self->send_query || return;
    
    return $self;
}

#sub DESTROY {
#    my $self = shift;
#    trace(2, "DESTROY $self\n");
#}

sub timeout {
    my $self = shift;
    
    trace(2, "NS Query timeout. Trying next host\n");
    if ($self->send_query) {
        # had another NS to send to, reset timeout
        $self->{timeout} = time();
        return;
    }
    
    # can we loop/repeat?
    if (($self->{nqueries} <= MAX_QUERIES) &&
        ($self->{repeat} > 1))
    {
        trace(2, "NS Query timeout. Next host failed. Trying loop\n");
        $self->{repeat}--;
        $self->{ns} = 0;
        return $self->timeout();
    }
    
    trace(2, "NS Query timeout. All failed. Running callback(TIMEOUT)\n");
    # otherwise we really must timeout.
    $self->run_callback("TIMEOUT");
    return 1;
}

sub error {
    my ($self, $error) = @_;
    
    trace(2, "NS Query error. Trying next host\n");
    if ($self->send_query) {
        # had another NS to send to, reset timeout
        $self->{timeout} = time();
        return;
    }
    
    # can we loop/repeat?
    if (($self->{nqueries} <= MAX_QUERIES) &&
        ($self->{repeat} > 1))
    {
        trace(2, "NS Query error. Next host failed. Trying loop\n");
        $self->{repeat}--;
        $self->{ns} = 0;
        return $self->error($error);
    }
    
    trace(2, "NS Query error. All failed. Running callback($error)\n");
    # otherwise we really must timeout.
    $self->run_callback($error);
    return 1;
}

sub run_callback {
    my ($self, $response) = @_;
    trace(2, "NS Query callback($self->{host} = $response\n");
    $self->{asker}->run_callback($response, $self->{host});
}

sub send_query {
    my ($self) = @_;
    
    my $dst = $self->{resolver}->ns($self->{ns}++);
    return unless defined $dst;
    if (!$self->{resolver}->sock->send($self->{data}, 0, $dst)) {
        return;
    }
    
    $self->{nqueries}++;
    return 1;
}

1;

=head1 NAME

Danga::DNS::Resolver - an asynchronous DNS resolver class

=head1 SYNOPSIS

  my $res = Danga::DNS::Resolver->new();
  
  $res->query($obj, @hosts); # $obj implements $obj->run_callback()

=head1 DESCRIPTION

This is a low level DNS resolver class that works within the Danga::Socket
asynchronous I/O framework. Do not attempt to use this class standalone - use
the C<Danga::DNS> class instead.

=cut
