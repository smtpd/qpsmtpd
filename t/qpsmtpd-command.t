#!/usr/bin/perl
use strict;
use warnings;

use Test::More;
use Time::HiRes qw(time);

use lib 't';
use lib 'lib';

use Qpsmtpd::Constants;
use_ok('Test::Qpsmtpd');
use_ok('Qpsmtpd::SMTP');       # Qpsmtpd::Command inherits from it
use_ok('Qpsmtpd::Command');

__esmtp_params();
__param_scaling();
__line_length_cap();

done_testing();

sub __esmtp_params {

    # Parameters are peeled off the end, right to left, stopping at the first
    # token from the right that is not one. Everything ahead of that is the
    # address, which may itself contain spaces (see t/qpsmtpd-address.t).
    my @t = (
        ['mail', 'from:<a@b.c>',                  '<a@b.c>', []],
        ['mail', 'from:<a@b.c> SIZE=100',         '<a@b.c>', ['SIZE=100']],
        ['mail', 'from:<a@b.c> SIZE=100 BODY=8BITMIME',
                                                  '<a@b.c>', ['SIZE=100','BODY=8BITMIME']],
        ['mail', 'from:<a@b.c> SMTPUTF8',         '<a@b.c>', ['SMTPUTF8']],
        ['mail', 'from:<a@b.c> SMTPUTF8 SIZE=12', '<a@b.c>', ['SMTPUTF8','SIZE=12']],
        ['mail', 'from:<a@b.c> CORRECT-WITHOUT-ARG',
                                                  '<a@b.c>', ['CORRECT-WITHOUT-ARG']],
        ['rcpt', 'to:<a@b.c> NOTIFY=NEVER',       '<a@b.c>', ['NOTIFY=NEVER']],
        ['rcpt', 'to:postmaster',                 'postmaster', []],

        # a trailing token that is not a well formed parameter stops the peel,
        # so it stays part of the address rather than being silently dropped
        ['mail', 'from:user=name@example.net',    'user=name@example.net', []],
    );
    for my $t (@t) {
        my ($cmd, $line, $addr, $params) = @$t;
        my ($ok, $got, @param) = Qpsmtpd::Command->parse($cmd, $line);
        is($ok, OK, "parse $cmd '$line'");
        is($got, $addr, "  address is $addr");
        is_deeply(\@param, $params, "  params are [@$params]");
    }

    # whitespace only differences must not change the result
    my ($ok, $addr, @p) = Qpsmtpd::Command->parse('mail', "from:<a\@b.c>   A   B  ");
    is_deeply([$ok, $addr, @p], [OK, '<a@b.c>', 'A', 'B'],
        'runs of whitespace between parameters');
}

sub __param_scaling {

    # _get_mail_params used to strip one parameter per $-anchored s///, which
    # rescans the whole line each time: 32k parameters took ~29s of CPU, before
    # AUTH. This is a guard against the quadratic form coming back
    my $n    = 32_000;
    my $line = 'from:<a@b.c>' . (' A' x $n);
    my $start = time;
    my ($ok, $addr, @param) = Qpsmtpd::Command->parse('mail', $line);
    my $elapsed = time - $start;

    is($ok, OK, "parse a MAIL line carrying $n parameters");
    is($addr, '<a@b.c>', '  address still parses out');
    is(scalar @param, $n, "  all $n parameters recovered");
    cmp_ok($elapsed, '<', 5,
        sprintf('  parsed in %.3fs, well under the 5s ceiling', $elapsed));
}

sub __line_length_cap {
    my ($smtpd) = Test::Qpsmtpd->new_conn();

    # RFC 5321 4.5.3.1.6.
    is($Qpsmtpd::SMTP::max_command_line, 998, 'the cap is 998 octets');

    for my $len (10, 500, 997, 998) {
        is($smtpd->command_line_too_long('x' x $len), 0,
            "a $len octet command line is accepted");
    }

    for my $len (999, 1000, 65_536) {
        my ($over) = Test::Qpsmtpd->new_conn();
        $over->{_response} = undef;
        is($over->command_line_too_long('x' x $len), 1,
            "a $len octet command line is refused");
        is_deeply($over->{_response}, [500, 'Line too long (#5.5.2)'],
            "  ... with 500 Line too long");
        ok($over->connection->notes('disconnected'),
            '  ... and the connection is dropped');
    }

    is($smtpd->command_line_too_long(undef), 0, 'undef is not too long');
}
