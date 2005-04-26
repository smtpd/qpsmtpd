# $Id: Resolver.pm,v 1.3 2005/02/14 22:06:08 msergeant Exp $

package Danga::DNS::Resolver;
use base qw(Danga::Socket);

use fields qw(res dst id_to_asker id_to_query timeout cache cache_timeout);

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
    
    trace(2, "Using nameserver $res->{nameservers}->[0]:$res->{port}\n");
    my $dst_sockaddr = sockaddr_in($res->{'port'}, inet_aton($res->{'nameservers'}->[0]));
    #my $dst_sockaddr = sockaddr_in($res->{'port'}, inet_aton('127.0.0.1'));
    #my $dst_sockaddr = sockaddr_in($res->{'port'}, inet_aton('10.2.1.20'));
    
    $self->{res} = $res;
    $self->{dst} = $dst_sockaddr;
    $self->{id_to_asker} = {};
    $self->{id_to_query} = {};
    $self->{timeout} = {};
    $self->{cache} = {};
    $self->{cache_timeout} = {};
    
    $self->SUPER::new($sock);
    
    $self->watch_read(1);
    
    return $self;
}

sub pending {
    my Danga::DNS::Resolver $self = shift;
    
    return keys(%{$self->{id_to_asker}});
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
    
    my $h = $packet->header;
    my $id = $h->id;
    
    if (!$self->sock->send($packet_data, 0, $self->{dst})) {
        return;
    }
    
    trace(2, "Query: $host ($id)\n");

    $self->{id_to_asker}->{$id} = $asker;
    $self->{id_to_query}->{$id} = $host;
    $self->{timeout}->{$id} = $now;
    
    return 1;
}

sub query_txt {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, @hosts) = @_;
    
    my $now = time();
    
    trace(2, "[" . keys(%{$self->{id_to_asker}}) . "] trying to resolve TXT: @hosts\n");

    foreach my $host (@hosts) {
        $self->_query($asker, $host, 'TXT', $now) || return;
    }
    
    # run cleanup every 5 seconds
    if ($now - 5 > $last_cleanup) {
        $last_cleanup = $now;
        $self->_do_cleanup($now);
    }
    
    #print "+Pending queries: " . keys(%{$self->{id_to_asker}}) .
    #    " / Cache Size: " . keys(%{$self->{cache}}) . "\n";
    
    return 1;
}

sub query_mx {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, @hosts) = @_;
    
    my $now = time();
    
    trace(2, "[" . keys(%{$self->{id_to_asker}}) . "] trying to resolve MX: @hosts\n");

    foreach my $host (@hosts) {
        $self->_query($asker, $host, 'MX', $now) || return;
    }
    
    # run cleanup every 5 seconds
    if ($now - 5 > $last_cleanup) {
        $last_cleanup = $now;
        $self->_do_cleanup($now);
    }
    
    #print "+Pending queries: " . keys(%{$self->{id_to_asker}}) .
    #    " / Cache Size: " . keys(%{$self->{cache}}) . "\n";
    
    return 1;
}

sub query {
    my Danga::DNS::Resolver $self = shift;
    my ($asker, @hosts) = @_;
    
    my $now = time();
    
    trace(2, "[" . keys(%{$self->{id_to_asker}}) . "] trying to resolve A/PTR: @hosts\n");

    foreach my $host (@hosts) {
        $self->_query($asker, $host, 'A', $now) || return;
    }
    
    # run cleanup every 5 seconds
    if ($now - 5 > $last_cleanup) {
        $last_cleanup = $now;
        $self->_do_cleanup($now);
    }
    
    #print "+Pending queries: " . keys(%{$self->{id_to_asker}}) .
    #    " / Cache Size: " . keys(%{$self->{cache}}) . "\n";
    
    return 1;
}

sub ticker {
    my Danga::DNS::Resolver $self = shift;
    my $now = time;
    # run cleanup every 5 seconds
    if ($now - 5 > $last_cleanup) {
        $last_cleanup = $now;
        $self->_do_cleanup($now);
    }
}

sub _do_cleanup {
    my Danga::DNS::Resolver $self = shift;
    my $now = shift;
    
    my $idle = $self->max_idle_time;
    
    my @to_delete;
    while (my ($id, $t) = each(%{$self->{timeout}})) {
        if ($t < ($now - $idle)) {
            push @to_delete, $id;
        }
    }
    
    foreach my $id (@to_delete) {
        delete $self->{timeout}{$id};
        my $asker = delete $self->{id_to_asker}{$id};
        my $query = delete $self->{id_to_query}{$id};
        $asker->run_callback("NXDOMAIN", $query);
    }
    
    foreach my $type ('A', 'TXT') {
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
        
        my $asker = delete $self->{id_to_asker}->{$id};
        my $query = delete $self->{id_to_query}->{$id};
        delete $self->{timeout}{$id};
                
        #print "-Pending queries: " . keys(%{$self->{id_to_asker}}) .
        #    " / Cache Size: " . keys(%{$self->{cache}}) . "\n";
        if (!$asker) {
            trace(1, "No asker for id: $id\n");
            return;
        }
        
        my $now = time();
        my @questions = $packet->question;
        #print STDERR "response to ", $questions[0]->string, "\n";
        foreach my $rr ($packet->answer) {
            # my $q = shift @questions;
            if ($rr->type eq "PTR") {
                my $rdns = $rr->ptrdname;
                if ($query) {
                    # NB: Cached as an "A" lookup as there's no overlap and they
                    # go through the same query() function above
                    $self->{cache}{A}{$query} = $rdns;
                    $self->{cache_timeout}{A}{$query} = $now + 60; # should use $rr->ttl but that would cache for too long
                }
                $asker->run_callback($rdns, $query);
            }
            elsif ($rr->type eq "A") {
                my $ip = $rr->address;
                if ($query) {
                    $self->{cache}{A}{$query} = $ip;
                    $self->{cache_timeout}{A}{$query} = $now + 60; # should use $rr->ttl but that would cache for too long
                }
                $asker->run_callback($ip, $query);
            }
            elsif ($rr->type eq "TXT") {
                my $txt = $rr->txtdata;
                if ($query) {
                    $self->{cache}{TXT}{$query} = $txt;
                    $self->{cache_timeout}{TXT}{$query} = $now + 60; # should use $rr->ttl but that would cache for too long
                }
                $asker->run_callback($txt, $query);
            }
            else {
                # came back, but not a PTR or A record
                $asker->run_callback("unknown", $query);
            }
            $answers++;
        }
        if (!$answers) {
            if ($err eq "NXDOMAIN") {
                # trace("found => NXDOMAIN\n");
                $asker->run_callback("NXDOMAIN", $query);
            }
            elsif ($err eq "SERVFAIL") {
                # try again???
                print "SERVFAIL looking for $query (Pending: " . keys(%{$self->{id_to_asker}}) . ")\n";
                #$self->query($asker, $query);
                $asker->run_callback($err, $query);
                #$self->{id_to_asker}->{$id} = $asker;
                #$self->{id_to_query}->{$id} = $query;
                #$self->{timeout}{$id} = time();
        
            }
            elsif($err) {
                print("error: $err\n");
                $asker->run_callback($err, $query);
            }
            else {
                # trace("no answers\n");
                $asker->run_callback("NXDOMAIN", $query);
            }
        }
    }
}

use Carp qw(confess);

sub close {
    my Danga::DNS::Resolver $self = shift;
    
    $self->SUPER::close(shift);
    confess "Danga::DNS::Resolver socket should never be closed!";
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
