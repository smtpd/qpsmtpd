#!/usr/bin/perl

use strict;
use warnings;
use Net::DNS::Resolver;
use Getopt::Long;

my ($server);

GetOptions(
    'server|s=s' => \$server,
);

my $res = Net::DNS::Resolver->new(
    $server ? ( nameservers => [$server] ) : (),
);
$res->tcp_timeout(10);
$res->udp_timeout(10);

if ( ! @ARGV ) {
    while (<>) {
        chomp;
        my $q = $res->query(split / /)
    }
} else {
    my ( $host, $type ) = @ARGV;
    die "Usage: dump_dns_lookup.pl <hostname|IP> <type> [-s server]\n"
        if ! $host or ! $type;
    my $q = $res->query($host,$type);
}

package Net::DNS::Resolver;

use Net::DNS::Resolver;

#sub search { shift->dump_result('search',@_) }
#sub query { shift->dump_result('query',@_) }
sub send { shift->dump_result('send',@_) }

sub dump_result {
    my ( $self, $type ) = ( shift, shift );
    my $sub = "SUPER::$type";
    my $result = $self->$sub( @_ );
    my ($host,$qtype) = (shift,shift);
    if ( ! $result ) {
        $host .= '.' unless $host =~ /\.$/;
        printf "%s\t\t%s\terror \"%s\"\n",
            $host, $qtype, $self->errorstring;
        return;
    }
    my $fn = lc join('-',$type,@_);
    my $answer = $result->string;
    if ( $answer =~ /;; ANSWER SECTION \(0 records\)/ ) {
        $host .= '.' unless $host =~ /\.$/;
        print "$host\tIN\t$qtype ; No record!\n";
    } else {
        $answer =~ /;; ANSWER SECTION \(\d+ records?\)\n(.*?)\n\n/ms
            or die "Unparsable answer:\n$answer";
        print "$1\n";
    }
    return $result;
}

package main;
