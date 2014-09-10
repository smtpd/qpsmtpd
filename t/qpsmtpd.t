#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 'lib';      # test lib/Qpsmtpd (vs site_perl)
BEGIN { use_ok('Qpsmtpd'); }
BEGIN { use_ok('Qpsmtpd::Constants'); }

my $package = 'Qpsmtpd';
my $qp = bless {}, $package;

ok( $qp->version(), "version, " . $qp->version());
is_deeply( Qpsmtpd::hooks(), {}, 'hooks, empty');

__config_dir();
__log();
__load_logging();

done_testing();

sub __log {
    ok( $qp->log(LOGWARN, "test log message"), 'log');
}

sub __config_dir {
    my $dir = $qp->config_dir('logging');
    ok( $dir, "config_dir, $dir");

    #warn Data::Dumper::Dumper($Qpsmtpd::config_dir_memo{logging});
    $dir = $Qpsmtpd::config_dir_memo{logging};
    ok( $dir, "config_dir, $dir (memo)");
};

sub __load_logging {
    $Qpsmtpd::LOGGING_LOADED = 1;
    ok( !$qp->load_logging(), "load_logging, loaded");

    $Qpsmtpd::LOGGING_LOADED = 0;
    $Qpsmtpd::hooks->{logging} = 1;
    ok( !$qp->load_logging(), "load_logging, logging hook");

    $Qpsmtpd::hooks->{logging} = undef;  # restore
}
