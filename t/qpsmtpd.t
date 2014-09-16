#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use File::Path;
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

__temp_file();
__temp_dir();
__size_threshold();
__authenticated();
__auth_user();
__auth_mechanism();
__spool_dir();

__log();
__load_logging();

__config_dir();
__config_from_file();
__get_qmail_config();
__config();

done_testing();

sub __get_qmail_config {
    ok(!$qp->get_qmail_config('me'), "get_qmail_config, me");

    # TODO: add positive tests.
}

sub __config_from_file {
    my $test_file = 't/config/test_config_file';
    my @r = $qp->_config_from_file($test_file);
    ok( @r, "_config_from_file, $test_file");
    cmp_ok('1st line with content', 'eq', $r[0], "_config_from_file string compare");
    ok( !$r[1], "_config_from_file");
};

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

sub __spool_dir {
    my $dir = $qp->spool_dir();
    ok( $dir, "spool_dir is at $dir");
}

sub __temp_file {
    my $r = $qp->temp_file();
    ok( $r, "temp_file at $r");
    if ($r && -f $r) {
        unlink $r;
        ok( unlink $r, "cleaned up temp file $r");
    }
}

sub __temp_dir {
    my $r = $qp->temp_dir();
    ok( $r, "temp_dir at $r");
    if ($r && -d $r) { File::Path::rmtree($r); }

    $r = $qp->temp_dir('0775');
    ok( $r, "temp_dir with mask, $r");
    if ($r && -d $r) { File::Path::rmtree($r); }
}

sub __size_threshold {
    ok( ! $qp->size_threshold(), "size_threshold is undefined")
        or warn "size_threshold: " . $qp->size_threshold;

    $Qpsmtpd::Size_threshold = 5;
    cmp_ok( 5, '==', $qp->size_threshold(), "size_threshold equals 5");

    $Qpsmtpd::Size_threshold = undef;
}

sub __authenticated {
    ok( ! $qp->authenticated(), "authenticated is undefined");

    $qp->{_auth} = 1;
    ok($qp->authenticated(), "authenticated is true");

    $qp->{_auth} = 0;
    ok(! $qp->authenticated(), "authenticated is false");
}

sub __auth_user {
    ok( ! $qp->auth_user(), "auth_user is undefined");

    $qp->{_auth_user} = 'matt';
    cmp_ok('matt', 'eq', $qp->auth_user(), "auth_user set");

    $qp->{_auth_user} = undef;
}

sub __auth_mechanism {
    ok( ! $qp->auth_mechanism(), "auth_mechanism is undefined");

    $qp->{_auth_mechanism} = 'MD5';
    cmp_ok('MD5', 'eq', $qp->auth_mechanism(), "auth_mechanism set");

    $qp->{_auth_mechanism} = undef;
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
   my $class = shift;
   return bless {@_}, $class;
}

sub address { }    # pass the can('address') conditional
