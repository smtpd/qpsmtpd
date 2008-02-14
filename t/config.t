#!/usr/bin/perl -w
use Test::More qw(no_plan);
use File::Path;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

BEGIN { # need this to happen before anything else
    my $cwd = `pwd`;
    chomp($cwd);
    open my $me_config, '>', "./config.sample/me";
    print $me_config "some.host.example.org";
    close $me_config;
}

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

is($smtpd->config('me'), 'some.host.example.org', 'config("me")');

unlink "./config.sample/me";


