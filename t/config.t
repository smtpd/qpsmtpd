#!/usr/bin/perl -w
use Test::More qw(no_plan);
use File::Path;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

my @mes;

BEGIN { # need this to happen before anything else
    my $cwd = `pwd`;
    chomp($cwd);
    @mes = qw{ ./config.sample/me ./t/config/me };
    foreach my $f ( @mes ) {
        open my $me_config, '>', $f;
        print $me_config "some.host.example.org";
        close $me_config;
    };
}

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

is($smtpd->config('me'), 'some.host.example.org', 'config("me")');

# test for ignoring leading/trailing whitespace (relayclients has a
# line with both)
my $relayclients = join ",", sort $smtpd->config('relayclients');
is($relayclients, '127.0.0.1,192.0.', 'config("relayclients") are trimmed');

foreach my $f ( @mes ) {
    unlink $f if -f $f;
};


