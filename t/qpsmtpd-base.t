#!/usr/bin/perl
use strict;
use warnings;

use Test::More;

use lib 'lib';      # test lib/Qpsmtpd/Base (vs site_perl)
use lib 't';
use Test::FakeResolver;

BEGIN {
    use_ok('Qpsmtpd::Base');
    use_ok('Qpsmtpd::Constants');
}

my $base = Qpsmtpd::Base->new();

__tildeexp();
__is_localhost();
__is_valid_ip();
__get_resolver();
__resolve_a();
__resolve_aaaa();
__resolve_mx();
__resolve_ns();
__resolve_ptr();
__dnsbl_name();
__dnsbl_lookup();

done_testing();

sub __is_valid_ip {
    my @good = qw/ 1.2.3.4 1.0.0.0 254.254.254.254 2001:db8:ffff:ffff:ffff:ffff:ffff:ffff /;
    foreach my $ip ( @good ) {
        ok( $base->is_valid_ip($ip), "is_valid_ip: $ip");
    }

    my @bad = qw/ 1.2.3.256 256.1.1.1 2001:db8:ffff:ffff:ffff:ffff:ffff:fffj /;
    foreach my $ip ( @bad ) {
        ok( !$base->is_valid_ip($ip), "is_valid_ip, neg: $ip");
    }
}

sub __is_localhost {

    for my $local_ip (qw/ 127.0.0.1 ::1 2607:f060:b008:feed::127.0.0.1 127.0.0.2 /) {
        ok( $base->is_localhost($local_ip), "is_localhost, $local_ip");
    }

    for my $rem_ip (qw/ 128.0.0.1 ::2 2607:f060:b008:feed::128.0.0.1 /) {
        ok( !$base->is_localhost($rem_ip), "!is_localhost, $rem_ip");
    }
}

sub __tildeexp {
    my $path = $base->tildeexp('~root/foo.txt');
    ok( $path, "tildeexp, $path");

    $path = $base->tildeexp('no/tilde/in/path');
    cmp_ok( $path, 'eq', 'no/tilde/in/path', 'tildeexp, no expansion');
}

sub __get_resolver {
    my $res = $base->get_resolver();
    isa_ok( $res, 'Net::DNS::Resolver', "get_resolver returns a Net::DNS::Resolver");

}

sub __resolve_a {
    my @r = $base->resolve_a('simerson.net');
    ok(@r, "resolve_a: " . join(',', @r));
}

sub __resolve_aaaa {
    my @r = $base->resolve_aaaa('ns2.cadillac.net');
    ok(@r, "resolve_aaaa: " . join(',', @r));
}

sub __resolve_mx {
    my @r = $base->resolve_mx('simerson.net');
    ok(@r, "resolve_mx: " . join(',', @r));
}

sub __resolve_ns {
    my @r = $base->resolve_ns('simerson.net');
    ok(@r, "resolve_ns: " . join(', ', @r));
}

sub __resolve_ptr {
    my @r = $base->resolve_ptr('163.51.128.66.in-addr.arpa.');
    ok(@r, "resolve_ptr: FQDN: " . join(', ', @r));

    @r = $base->resolve_ptr('66.128.51.163');
    ok(@r, "resolve_ptr, IP: " . join(', ', @r));
}

sub __dnsbl_name {
    is($base->dnsbl_name('192.0.2.1'), '1.2.0.192', 'dnsbl_name: IPv4');
    is($base->dnsbl_name('2001:db8::1'),
       join('.', reverse split //, '20010db8' . ('0' x 23) . '1'),
       'dnsbl_name: IPv6 nibbles');
    ok(!$base->dnsbl_name('nonsense'), 'dnsbl_name: not an address');
}

sub __dnsbl_lookup {
    my %zone = (
        'listed.test'   => {A => ['127.0.0.2', '127.0.0.4'], TXT => ['spam', 'more']},
        'no-txt.test'   => {A => ['127.0.0.2']},
        'split.test'    => {A => ['127.0.0.2'], TXT => ['https://ex" "ample.test/']},
        'refused.test'  => {A => ['127.255.255.254']},
        'other.test'    => {A => ['127.255.255.2']},
        'outside.test'  => {A => ['192.0.2.1']},
        'servfail.test' => {error => 'SERVFAIL'},
    );
    local $base->{_resolver} = Test::FakeResolver->new(%zone);

    is_deeply($base->dnsbl_lookup('listed.test'),
              {codes => ['127.0.0.2', '127.0.0.4'], reason => 'spam more'},
              'dnsbl_lookup: listed, with the TXT reason');
    is_deeply($base->dnsbl_lookup('no-txt.test'),
              {codes => ['127.0.0.2'], reason => ''},
              'dnsbl_lookup: listed, without a reason');
    is($base->dnsbl_lookup('split.test')->{reason}, 'https://example.test/',
       'dnsbl_lookup: the strings of one TXT record are joined');
    ok(!defined $base->dnsbl_lookup('absent.test'),
       'dnsbl_lookup: NXDOMAIN is not listed');
    like($base->dnsbl_lookup('refused.test')->{error}, qr/refused/,
         'dnsbl_lookup: a Spamhaus error code is an error');
    is_deeply($base->dnsbl_lookup('other.test')->{codes}, ['127.255.255.2'],
              'dnsbl_lookup: another 127.255.255.x answer is a listing');
    like($base->dnsbl_lookup('outside.test')->{error}, qr/refused/,
         'dnsbl_lookup: an answer outside 127/8 is not a listing');
    like($base->dnsbl_lookup('servfail.test')->{error}, qr/SERVFAIL/,
         'dnsbl_lookup: a failed query is an error');
}
