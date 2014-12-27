#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;
use Test::Output;

use lib 't';
use lib 'lib';      # test lib/Qpsmtpd/SMTP (vs site_perl)
use Qpsmtpd::Constants;

use_ok('Test::Qpsmtpd');
use_ok('Qpsmtpd::SMTP');


ok(my $smtp = Qpsmtpd::SMTP->new(), "new smtp");
ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

__new();
__fault();
__helo_no_host();
__helo_repeat_host();
__helo_respond('helo_respond');
__helo_respond('ehlo_respond');
__data_respond('data_respond');

done_testing();

sub __new {
    isa_ok( $smtp, 'Qpsmtpd::SMTP' );

    ok( $smtp->{_commands}, "valid commands populated");
    $smtp = Qpsmtpd::SMTP->new( key => 'val' );
    cmp_ok( $smtp->{args}{key}, 'eq', 'val', "new with args");

}

sub __fault {

    my $fault;
    stderr_like { $fault = $smtpd->fault }
        qr/program fault - command not performed.*Last system error:/ms,
        'fault outputs proper warning to STDOUT';
    is($fault->[0], 451, 'fault returns 451');

    stderr_like { $fault = $smtpd->fault('test message') }
           qr/test message.*Last system error/ms,
           'fault outputs proper custom warning to STDOUT';
    is($fault->[1], 'Internal error - try again later - test message',
           'returns the input message');
}

sub __helo_no_host {
    is_deeply(
        $smtpd->helo_no_host('helo'),
        [501,'helo requires domain/address - see RFC-2821 4.1.1.1'],
        'return helo'
    );
    is_deeply(
        $smtpd->helo_no_host('ehlo'),
        [501,'ehlo requires domain/address - see RFC-2821 4.1.1.1'],
        'return ehlo'
    );
}

sub __helo_repeat_host {
    is_deeply(
        $smtpd->helo_repeat_host(),
        [503,'but you already said HELO ...'], 'repeated helo verb'
    );
}

sub __helo_respond {
    my $func = shift or die 'missing function name';
    $smtpd->{_response} = undef;  # reset connection
    $smtpd->$func(DONE, ["Good hair day"], ['helo.example.com']);
    is_deeply(
        $smtpd->{_response},
        undef,
        "$func DONE",
    );

    $smtpd->$func(DENY, ["Very bad hair day"], ['helo.example.com']);
    is_deeply(
        $smtpd->{_response},
        [550, 'Very bad hair day'],
        "$func DENY",
    );

    $smtpd->$func(DENYSOFT, ["Bad hair day"], ['helo.example.com']),
    is_deeply(
        $smtpd->{_response},
        [450, 'Bad hair day'],
        "$func DENYSOFT",
    );

    $smtpd->$func(DENYSOFT_DISCONNECT, ["Bad hair day"], ['helo.example.com']),
    is_deeply(
        $smtpd->{_response},
        [450, 'Bad hair day'],
        "$func DENYSOFT_DISCONNECT",
    );

    $smtpd->$func(DENY_DISCONNECT, ["Very bad hair day"], ['helo.example.com']),
    is_deeply(
        $smtpd->{_response},
        [550, 'Very bad hair day'],
        "$func DENY_DISCONNECT",
    );

    $smtpd->$func(OK, ["You have hair?"], ['helo.example.com']);
    ok($smtpd->{_response}[0] == 250, "$func, OK");
    ok($smtpd->{_response}[1] =~ / Hi /, "$func, OK");

    #warn Data::Dumper::Dumper($smtpd->{_response});
}

sub __data_respond {
    is( $smtpd->data_respond(DONE), 1, 'data_respond, DONE' );
    is( $smtpd->data_respond(DENY), 1, 'data_respond, DENY' );
    is( $smtpd->data_respond(DENYSOFT), 1, 'data_respond, DENYSOFT' );
    is( $smtpd->data_respond(DENY_DISCONNECT), 1, 'data_respond, DENY_DISCONNECT' );
    is( $smtpd->data_respond(DECLINED), 1, 'data_respond, DECLINED' );

    # the tests above all return 1 early due to DATA checks. Once the
    # transaction is populated, only checks that fail early will return.
    ($smtpd) = _new_transaction();
    is( $smtpd->data_respond(DONE), 1, 'data_respond, DONE' );

    ($smtpd) = _new_transaction();
    is( $smtpd->data_respond(DENY), 1, 'data_respond, DENY' );

    ($smtpd) = _new_transaction();
    is( $smtpd->data_respond(DENYSOFT), 1, 'data_respond, DENYSOFT' );

    ($smtpd) = _new_transaction();
    is( $smtpd->data_respond(DENY_DISCONNECT), 1, 'data_respond, DENY_DISCONNECT' );

    # data_respond also runs the data_post hooks, so this will require a bit
    # more work to get under test...
    #($smtpd) = _new_transaction();
    #is( $smtpd->data_respond(DECLINED, _test_message()), 1, 'data_respond, DECLINED' );
}

sub _new_transaction () {
    my ($smtpd, $conn) = Test::Qpsmtpd->new_conn();
    $smtpd->transaction->sender(Qpsmtpd::Address->new('sender@example.com'));
    $smtpd->transaction->add_recipient(Qpsmtpd::Address->new('recip@example.com'));
    return $smtpd;
};

sub _test_message {
    # with \r\n (aka CRLF) endings, as a proper SMTP formatted email would
    return <<"EOM"
From: Jennifer <jennifer\@example.com>\r
Subject: Persian New Year's Soup with Beans, Noodles, and Herbs Recipe at Epicurious.com\r
Date: Sun, 02 Oct 2011 14:06:06 -0700\r
Message-id: <67CC87B2-095C-45C6-BF9B-5A589AD6C264\@example.com>\r
To: Matt <matt\@example.net>\r
\r
\r
--Boundary_(ID_lBFzGVLdxsIk2GYiWhQRRQ)\r
Content-type: text/plain; CHARSET=US-ASCII\r
Content-transfer-encoding: 7BIT\r
\r
This sounds good.  Can we do have it this week?\r
\r
http://www.epicurious.com/recipes/food/views/Persian-New-Years-Soup-with-Beans-Noodles-and-Herbs-em-Ash-e-reshteh-em-363446\r
\r
.\r
EOM
;
}
