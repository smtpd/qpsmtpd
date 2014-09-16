use strict;
use warnings;

use Data::Dumper;
use File::Path;
use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

my @mes;

BEGIN {
    use_ok('Qpsmtpd::Config');    # call classes directly
    use_ok('Qpsmtpd::Constants');

    use_ok('Test::Qpsmtpd');      # call via a connection object

    @mes = qw{ ./config.sample/me ./t/config/me };
    foreach my $f (@mes) {
        open my $me_config, '>', $f;
        print $me_config "host.example.org";
        close $me_config;
    }
}

my $config = Qpsmtpd::Config->new();

isa_ok($config, 'Qpsmtpd::Config');

__log();
__config_dir();
__from_file();
__get_qmail();
__config_via_smtpd();

foreach my $f (@mes) { unlink $f; }

done_testing();

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
    ok($config->log(LOGWARN, "test log message"), 'log');
    is($warned, "$$ test log message\n", 'LOGWARN emitted correct warning');
}

sub __get_qmail {
    is($config->get_qmail('me'), 'host.example.org', 'get_qmail("me")');
    ok(!$config->get_qmail('not-me'), 'get_qmail("not-me")');
}

sub __from_file {
    my $test_file = 't/config/test_config_file';
    my @r = $config->from_file($test_file, 'test_config_file');
    ok( @r, "from_file, $test_file");
    cmp_ok('1st line with content', 'eq', $r[0], "from_file string compare");
    ok( !$r[1], "from_file");
};

sub __config_dir {
    my $dir = $config->config_dir('logging');
    ok($dir, "config_dir, $dir");

    #warn Data::Dumper::Dumper($Qpsmtpd::config_dir_memo{logging});
    $dir = $Qpsmtpd::Config::dir_memo{logging};
    ok($dir, "config_dir, $dir (memo)");
}

sub __config_via_smtpd {
    ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

    is($smtpd->config('me'), 'host.example.org', 'config("me")');

# test for ignoring leading/trailing whitespace (relayclients has a
# line with both)
    my $relayclients = join ',', sort $smtpd->config('relayclients');
    is($relayclients,
    '127.0.0.1,192.0.,2001:0DB8,2001:0DB8:0000:0000:0000:0000:0000:0001,2001:DB8::1,2001:DB8::1/32',
        'config("relayclients") are trimmed'
    );
};
