#!/usr/bin/perl
use strict;
use warnings;

use Cwd;
use Data::Dumper;
use File::Path;
use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

BEGIN {
    use_ok('Qpsmtpd');
    use_ok('Qpsmtpd::Constants');
    use_ok('Test::Qpsmtpd');
}

my $qp = bless {}, 'Qpsmtpd';

ok($qp->version(), "version, " . $qp->version());
__hooks_none();

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");
__hooks();

__run_hooks_no_respond();
__run_hooks();

__register_hook();
__hook_responder();
__run_continuation();

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
__config();

done_testing();

sub __run_hooks {
    my @r = $qp->run_hooks('nope');
    is($r[0], 0, "run_hooks, invalid hook");

    @r = $smtpd->run_hooks('nope');
    is($r[0], 0, "run_hooks, invalid hook");

    foreach my $hook (qw/ connect helo rset /) {
        my $r = $smtpd->run_hooks('connect');
        is($r->[0], 220, "run_hooks, $hook code");
        ok($r->[1] =~ /ready/, "run_hooks, $hook result");
    }
}

sub __run_hooks_no_respond {
    my @r = $qp->run_hooks_no_respond('nope');
    is($r[0], 0, "run_hooks_no_respond, invalid hook");

    @r = $smtpd->run_hooks_no_respond('nope');
    is($r[0], 0, "run_hooks_no_respond, invalid hook");

    foreach my $hook (qw/ connect helo rset /) {
        @r = $smtpd->run_hooks_no_respond('connect');
        is($r[0], 909, "run_hooks_no_respond, $hook hook");
    }
}

sub __hooks {
    ok(Qpsmtpd::hooks(), "hooks, populated");
    my $r = $qp->hooks;
    ok(%$r, "hooks, populated returns a hashref");

    $r = $qp->hooks('connect');
    ok(@$r, "hooks, populated, connect");

    my @r = $qp->hooks('connect');
    ok(@r, "hooks, populated, connect, wants array");
}

sub __hooks_none {
    is_deeply(Qpsmtpd::hooks(), {}, 'hooks, empty');
    is_deeply($qp->hooks, {}, 'hooks, empty');

    my $r = $qp->hooks('connect');
    is_deeply($r, [], 'hooks, empty, specified');
}

sub __run_continuation {
    my $r;
    eval { $smtpd->run_continuation };
    is( $@, "No continuation in progress\n",
      'run_continuation dies without continuation');
    $smtpd->{_continuation} = [];
    eval { $smtpd->run_continuation };
    ok( $@ =~ /^No hook in the continuation/,
      'run_continuation dies without hook');
    $smtpd->{_continuation} = ['connect'];
    eval { $smtpd->run_continuation };
    ok( $@ =~ /^No hook args in the continuation/,
      'run_continuation dies without hook');


    my @local_hooks = @{ $smtpd->hooks->{connect} };
    $smtpd->{_continuation} = ['connect', [DECLINED, "test mess"], @local_hooks];
    $smtpd->mock_config( 'smtpgreeting', 'Hello there ESMTP' );

    eval { $r = $smtpd->run_continuation };
    ok(!$@, "run_continuation with a continuation doesn't throw exception");
    is($r->[0], 220, "hook_responder, code");
    is($r->[1], 'Hello there ESMTP', "hook_responder, message");
    $smtpd->unmock_config;

    my @test_data = (
        {
            hooks => [[DENY, 'noway']],
            expected_response => '550/noway',
            disconnected => 0,
            descr => 'DENY',
        },
        {
            hooks => [[DENY_DISCONNECT, 'boo']],
            expected_response => '550/boo',
            disconnected => 1,
            descr => 'DENY_DISCONNECT',
        },
        {
            hooks => [[DENYSOFT, 'comeback']],
            expected_response => '450/comeback',
            disconnected => 0,
            descr => 'DENYSOFT',
        },
        {
            hooks => [[DENYSOFT_DISCONNECT, 'wah']],
            expected_response => '450/wah',
            disconnected => 1,
            descr => 'DENYSOFT_DISCONNECT',
        },
        {
            hooks => [ [DECLINED,'nm'], [DENY, 'gotcha'] ],
            expected_response => '550/gotcha',
            disconnected => 0,
            descr => 'DECLINED -> DENY',
        },
        {
            hooks => [ [123456,undef], [DENY, 'goaway'] ],
            expected_response => '550/goaway',
            disconnected => 0,
            logged => 'LOGERROR:Plugin ___MockHook___, hook helo returned 123456',
            descr => 'INVALID -> DENY',
        },
        {
            hooks => [ sub { die "dead\n" }, [DENY, 'begone'] ],
            expected_response => '550/begone',
            disconnected => 0,
            logged => 'LOGCRIT:FATAL PLUGIN ERROR [___MockHook___]: dead',
            descr => 'fatal error -> DENY',
        },
        {
            hooks => [ [undef], [DENY, 'nm'] ],
            expected_response => '550/nm',
            disconnected => 0,
            logged => 'LOGERROR:Plugin ___MockHook___, hook helo returned undef!',
            descr => 'undef -> DENY',
        },
        {
            hooks => [ [OK, 'bemyguest'], [DENY, 'seeya'] ],
            expected_response => '250/fqdn Hi test@localhost [127.0.0.1];'
                               . ' I am so happy to meet you.',
            disconnected => 0,
            descr => 'OK -> DENY',
        },
    );
    for my $t (@test_data) {
        $smtpd->mock_config( me => 'fqdn' );
        for my $h ( reverse @{ $t->{hooks} } ) {
            my $sub = ( ref $h eq 'ARRAY' ? sub { return @$h } : $h );
            $smtpd->mock_hook( 'helo', $sub );
        }
        $smtpd->{_continuation} = [ 'helo', ['somearg'], @{ $smtpd->hooks->{helo} } ];
        delete $smtpd->{_response};
        delete $smtpd->{_logged};
        $smtpd->connection->notes( disconnected => undef );
        $smtpd->run_continuation;
        my $response = join '/', @{ $smtpd->{_response} || [] };
        is( $response, $t->{expected_response},
          "run_continuation(): Respond to $t->{descr} with $t->{expected_response}" );
        if ( $t->{disconnected} ) {
            ok( $smtpd->connection->notes('disconnected'),
              "run_continuation() disconnects on $t->{descr}" );
        }
        else {
            ok( ! $smtpd->connection->notes('disconnected'),
              "run_continuation() does not disconnect on $t->{descr}" );
        }
        if ( $t->{logged} ) {
            is( join("\n", @{ $smtpd->{_logged} || [] }), $t->{logged},
                "run_continuation() logging on $t->{descr}" );
        }
        $smtpd->unmock_hook('helo');
        $smtpd->unmock_config();
    }
}

sub __hook_responder {
    my ($code, $msg) = $qp->hook_responder('test-hook', [OK,'test mesg']);
    is($code, OK, "hook_responder, code");
    is($msg, 'test mesg', "hook_responder, test msg");

    ($code, $msg) = $smtpd->hook_responder('connect', [OK,'test mesg']);
    is($code->[0], 220, "hook_responder, code");
    ok($code->[1] =~ /ESMTP qpsmtpd/, "hook_responder, message: ". $code->[1]);

    my $rej_msg = 'Your father smells of elderberries';
    ($code, $msg) = $smtpd->hook_responder('connect', [DENY, $rej_msg]);
    is($code, undef, "hook_responder, disconnected yields undef code");
    is($msg, undef, "hook_responder, disconnected yields undef msg");
}

sub __register_hook {
    my $hook = 'test';
    is( $Qpsmtpd::hooks->{'test'}, undef, "_register_hook, test hook is undefined");

    $smtpd->_register_hook('test', 'fake-code-ref');
    is_deeply( $Qpsmtpd::hooks->{'test'}, ['fake-code-ref'], "test hook is registered");
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
    $qp->log(LOGWARN, "test log message");
    ok(-f 't/tmp/test-warn.log', 'log');
    is($warned, "$$ test log message\n", 'LOGWARN emitted correct warning');
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
    ok($dir, "spool_dir is at $dir");

    my $cwd = getcwd;
    chomp $cwd;
    open my $SD, '>', "./config.sample/spool_dir";
    print $SD "$cwd/t/tmp";
    close $SD;

    my $spool_dir = $smtpd->spool_dir();
    ok($spool_dir =~ m!/tmp/$!,   "Located the spool directory")
        or diag ("spool_dir: $spool_dir instead of tmp");

    my $tempfile  = $smtpd->temp_file();
    my $tempdir   = $smtpd->temp_dir();

    ok($tempfile =~ /^$spool_dir/, "Temporary filename");
    ok($tempdir =~ /^$spool_dir/,  "Temporary directory");
    ok(-d $tempdir,                "And that directory exists");

    unlink "./config.sample/spool_dir";
    rmtree($spool_dir);
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
    is( $qp->size_threshold(), 10000, "size_threshold from t/config is 1000")
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

sub __config_dir {
    my $dir = $qp->config_dir('logging');
    ok($dir, "config_dir, $dir");

    $dir = $Qpsmtpd::Config::dir_memo{logging};
    ok($dir, "config_dir, $dir (memo)");
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
                   user_config => undef,
                   config      => undef,
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
                   user_config => undef,
                   config      => undef,
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
        for my $hook ( grep { $t->{hooks}{$_} } qw( config user_config ) ) {
            $qp->mock_hook( $hook, sub { return @{ $t->{hooks}{$hook} } } );
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
    $qp->unmock_hook($_) for qw( config user_config );
}

1;

package FakeAddress;

sub new {
   my $class = shift;
   return bless {@_}, $class;
}

sub address { }    # pass the can('address') conditional

1;
