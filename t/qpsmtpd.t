#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 'lib';      # test lib/Qpsmtpd (vs site_perl)
BEGIN { use_ok('Qpsmtpd'); }
BEGIN { use_ok('Qpsmtpd::Constants'); }

my $qp = bless {}, 'Qpsmtpd';

ok( $qp->version(), "version, " . $qp->version());
is_deeply( Qpsmtpd::hooks(), {}, 'hooks, empty');

__authenticated();
__config_dir();
__get_qmail_config();
__config();
__log();
__load_logging();

done_testing();

sub __config {
    my @r = $qp->config('badhelo');
    ok( $r[0], "config, badhelo, @r");
};

sub __get_qmail_config {
    ok( !$qp->get_qmail_config('me'), "get_qmail_config, me");

    # TODO: add positive tests.
};

sub __config_from_file {
    # $configfile, $config, $visited

};

sub __log {
    my $warned = '';
    local $SIG{__WARN__} = sub {
        if ( $_[0] eq "$$ test log message\n" ) {
            $warned = join ' ', @_;
        }
        else {
            warn @_;
        }
    };
    ok( $qp->log(LOGWARN, "test log message"), 'log');
    is( $warned, "$$ test log message\n", 'LOGWARN emitted correct warning' );
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

sub __authenticated {

    ok( ! $qp->authenticated(), "authenticated, undef");

    $qp->{_auth} = 1;
    ok( $qp->authenticated(), "authenticated, true");

    $qp->{_auth} = 0;
    ok( !$qp->authenticated(), "authenticated, false");
};
