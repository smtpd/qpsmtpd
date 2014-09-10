#!/usr/bin/perl
use strict;
use warnings;

use Test::More;

use lib 'lib';      # test lib/Qpsmtpd/Utils (vs site_perl)

BEGIN { use_ok('Qpsmtpd::Utils'); }

my $utils = bless {}, 'Qpsmtpd::Utils';

__tildeexp();
__is_localhost();

done_testing();

sub __is_localhost {

    for my $local_ip (qw/ 127.0.0.1 ::1 2607:f060:b008:feed::127.0.0.1 127.0.0.2 /) {
        ok( $utils->is_localhost($local_ip), "is_localhost, $local_ip");
    }

    for my $rem_ip (qw/ 128.0.0.1 ::2 2607:f060:b008:feed::128.0.0.1 /) {
        ok( !$utils->is_localhost($rem_ip), "!is_localhost, $rem_ip");
    }
};

sub __tildeexp {
    my $path = $utils->tildeexp('~root/foo.txt');
    ok( $path, "tildeexp, $path");

    $path = $utils->tildeexp('no/tilde/in/path');
    cmp_ok( $path, 'eq', 'no/tilde/in/path', 'tildeexp, no expansion');
};
