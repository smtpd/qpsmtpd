#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)

BEGIN {
    use_ok('Qpsmtpd');
    use_ok('Qpsmtpd::Constants');
}

use lib 't';
use_ok('Test::Qpsmtpd');

my $qp = bless {}, 'Qpsmtpd';

ok($qp->version(), "version, " . $qp->version());
is_deeply(Qpsmtpd::hooks(), {}, 'hooks, empty');

__authenticated();
__config_dir();
__get_qmail_config();
__config();
__log();
__load_logging();

done_testing();

sub __get_qmail_config {
    ok(!$qp->get_qmail_config('me'), "get_qmail_config, me");

    # TODO: add positive tests.
}

sub __config_from_file {

    # $configfile, $config, $visited

}

sub __log {
    my $warned = '';
    local $SIG{__WARN__} = sub {
        if ($_[0] eq "$$ test log message\n") {
            $warned = join ' ', @_;
        }
        else {
            warn @_;
        }
    };
    ok($qp->log(LOGWARN, "test log message"), 'log');
    is($warned, "$$ test log message\n", 'LOGWARN emitted correct warning');
}

sub __config_dir {
    my $dir = $qp->config_dir('logging');
    ok($dir, "config_dir, $dir");

    #warn Data::Dumper::Dumper($Qpsmtpd::config_dir_memo{logging});
    $dir = $Qpsmtpd::config_dir_memo{logging};
    ok($dir, "config_dir, $dir (memo)");
}

sub __load_logging {
    $Qpsmtpd::LOGGING_LOADED = 1;
    ok(!$qp->load_logging(), "load_logging, loaded");

    $Qpsmtpd::LOGGING_LOADED = 0;
    $Qpsmtpd::hooks->{logging} = 1;
    ok(!$qp->load_logging(), "load_logging, logging hook");

    $Qpsmtpd::hooks->{logging} = undef;    # restore
}

sub __authenticated {

    ok(!$qp->authenticated(), "authenticated, undef");

    $qp->{_auth} = 1;
    ok($qp->authenticated(), "authenticated, true");

    $qp->{_auth} = 0;
    ok(!$qp->authenticated(), "authenticated, false");
}

sub __config {
    my @r = $qp->config('badhelo');
    ok($r[0], "config, badhelo, @r");
    my $a = FakeAddress->new(test => 'test value');
    ok(my ($qp, $cxn) = Test::Qpsmtpd->new_conn(), "get new connection");
    my @test_data = (
        {
         pref  => 'size_threshold',
         hooks => {
                   user_config => [],
                   config      => [],
                  },
         expected => {
                      user   => 10000,
                      global => 10000,
                     },
         descr => 'no user or global config hooks, fall back to config file',
        },
        {
         pref  => 'timeout',
         hooks => {
                   user_config => [],
                   config      => [],
                  },
         expected => {
                      user   => 1200,
                      global => 1200,
                     },
         descr => 'no user or global config hooks, fall back to defaults',
        },
        {
         pref  => 'timeout',
         hooks => {
                   user_config => [DECLINED],
                   config      => [DECLINED],
                  },
         expected => {
                      user   => 1200,
                      global => 1200,
                     },
         descr => 'user and global config hooks decline, fall back to defaults',
        },
        {
         pref  => 'timeout',
         hooks => {
                   user_config => [DECLINED],
                   config      => [OK, 1000],
                  },
         expected => {
                      user   => 1000,
                      global => 1000,
                     },
         descr => 'user hook declines, global hook returns',
        },
        {
         pref  => 'timeout',
         hooks => {
                   user_config => [OK, 500],
                   config      => [OK, undef],
                  },
         expected => {
                      user   => 500,
                      global => undef,
                     },
         descr => 'user hook returns int, global hook returns undef',
        },
        {
         pref  => 'timeout',
         hooks => {
                   user_config => [OK, undef],
                   config      => [OK, 1000],
                  },
         expected => {
                      user   => undef,
                      global => 1000,
                     },
         descr => 'user hook returns undef, global hook returns int',
        },
    );
    for my $t (@test_data) {
        for my $hook (qw( config user_config )) {
            $qp->hooks->{$hook} = @{$t->{hooks}{$hook}}
              ? [
                {
                 name => 'test hook',
                 code => sub { return @{$t->{hooks}{$hook}} }
                }
              ]
              : undef;
        }
        is(
            $qp->config($t->{pref}, $a),
            $t->{expected}{user},
            "User config: $t->{descr}"
          );
        is($qp->config($t->{pref}),
            $t->{expected}{global},
            "Global config: $t->{descr}");
    }
}

package FakeAddress;

sub new {
    shift;
    return bless {@_};
}

sub address { }    # pass the can('address') conditional
