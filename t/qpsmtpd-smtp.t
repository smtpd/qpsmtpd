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
__clean_authentication_results();
__authentication_results();

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
    ( $smtpd ) = Test::Qpsmtpd->new_conn();
    is( $smtpd->data_respond(DONE), 1, 'data_respond(DONE)' );
    response_is( undef, 'data_respond(DONE) response' );
    is( $smtpd->data_respond(DENY), 1, 'data_respond(DENY)' );
    response_is( '554 - Message denied', 'data_respond(DENY) response' );
    is( $smtpd->data_respond(DENYSOFT), 1, 'data_respond(DENYSOFT)' );
    response_is( '451 - Message denied temporarily',
        'data_respond(DENYSOFT) response' );

    $smtpd->connection->notes( disconnected => 0 );
    is( $smtpd->data_respond(DENY_DISCONNECT), 1,
        'data_respond(DENY_DISCONNECT)' );
    response_is( '554 - Message denied',
        'data_respond(DENY_DISCONNECT) response' );
    is( $smtpd->connection->notes('disconnected'), 1,
        'disconnect after data_respond(DENY_DISCONNECT)' );

    $smtpd->connection->notes( disconnected => 0 );
    is( $smtpd->data_respond(DENYSOFT_DISCONNECT), 1,
        'data_respond, DENYSOFT_DISCONNECT' );
    response_is( '451 - Message denied temporarily',
        'data_respond(DENYSOFT_DISCONNECT) response' );
    is( $smtpd->connection->notes('disconnected'), 1,
        'disconnect after data_respond(DENY_DISCONNECT)' );

    is( $smtpd->data_respond(DECLINED), 1,
        'data_respond(DECLINED) - no sender' );
    response_is( '503 - MAIL first',
        'data_respond(DECLINED) response - no sender' );
    $smtpd->transaction->sender(Qpsmtpd::Address->new('sender@example.com'));
    is( $smtpd->data_respond(DECLINED), 1,
        'data_respond(DECLINED) - no recips' );
    response_is( '503 - RCPT first',
        'data_respond(DECLINED) response - no recips' );
    $smtpd->transaction->add_recipient(Qpsmtpd::Address->new('recip@example.com'));

    # data_respond also runs the data_post hooks, so this will require a bit
    # more work to get under test. we also don't yet have a way to mock
    # message data; that will probably require overriding getline()
    #$smtpd->mock_data( _test_message() );
    #$smtpd->mock_hook( data_post => sub { return DECLINED } );
    #is( $smtpd->data_respond(DECLINED), 1, 'data_respond, DECLINED' );
}

sub __clean_authentication_results {

    my $smtpd = _transaction_with_headers();
    $smtpd->transaction->header->add('Authentication-Results', _test_ar_header());
    $smtpd->clean_authentication_results();
    ok(!$smtpd->transaction->header->get('Authentication-Results'), "clean_authentication_results removes A-R header");
    ok($smtpd->transaction->header->get('Original-Authentication-Results'), "clean_authentication_results adds Original-A-R header");

    # A-R header is _not_ DKIM signed
    $smtpd = _transaction_with_headers();
    $smtpd->transaction->header->add('Authentication-Results', _test_ar_header());
    $smtpd->transaction->header->add('DKIM-Signature', _test_dkim_header());
    $smtpd->clean_authentication_results();
    ok(!$smtpd->transaction->header->get('Authentication-Results'), "clean_authentication_results removes non-DKIM-signed A-R header");
    ok($smtpd->transaction->header->get('Original-Authentication-Results'), "clean_authentication_results adds non-DKIM-signed Original-A-R header");

    # A-R header _is_ DKIM signed
    $smtpd = _transaction_with_headers();
    $smtpd->transaction->header->add('Authentication-Results', _test_ar_header());
    $smtpd->transaction->header->add('DKIM-Signature', _test_dkim_sig_ar_signed());
    $smtpd->clean_authentication_results();
    ok($smtpd->transaction->header->get('Authentication-Results'), "clean_authentication_results removes non-DKIM-signed A-R header");
    ok(!$smtpd->transaction->header->get('Original-Authentication-Results'), "clean_authentication_results adds non-DKIM-signed Original-A-R header");
}

sub _test_ar_header {
    return 'mail.theartfarm.com; iprev=pass; spf=pass smtp.mailfrom=ietf.org; dkim=fail (body hash did not verify) header.i=@kitterman.com; dkim=pass header.i=@ietf.org';
}

sub _test_dkim_header {
    return <<DKIM_HEADER
v=1; a=rsa-sha256; c=relaxed/simple; d=ietf.org; s=ietf1; t=1420404573; bh=Tq5JynLUBXNqn1f+10W+MuPhq+XAbL4oLNfT+QPVK54=; h=From:To:Date:Message-ID:In-Reply-To:References:MIME-Version:Subject:List-Id:List-Unsubscribe:List-Archive:List-Post:List-Help:List-Subscribe:Content-Type:Content-Transfer-Encoding:Sender; b=hsxkiq/cCNBJTOwv1wj+AA9w2ujXnpNVjpPREMSvidQQkDsnFPhASDi9hihEgEqo4LRMkbw/zHNyHBtF5TcT7WysNyItpmbnWiRksB9SuCBaqZMvqE/rNVca3goTgrb89O5SDZIWjcQ7rGvNqk/L+XL8VWCyNhOVlalnFMxKXyE=
DKIM_HEADER
}

sub _test_dkim_sig_ar_signed {
    return <<DKIM_AR_SIGNED_HEADER
v=1; a=rsa-sha256; c=relaxed/simple; d=ietf.org; s=ietf1; t=1420404573; bh=Tq5JynLUBXNqn1f+10W+MuPhq+XAbL4oLNfT+QPVK54=; h=Authentication-Results:From:To:Date:Message-ID:In-Reply-To:References:MIME-Version:Subject:List-Id:List-Unsubscribe:List-Archive:List-Post:List-Help:List-Subscribe:Content-Type:Content-Transfer-Encoding:Sender; b=hsxkiq/cCNBJTOwv1wj+AA9w2ujXnpNVjpPREMSvidQQkDsnFPhASDi9hihEgEqo4LRMkbw/zHNyHBtF5TcT7WysNyItpmbnWiRksB9SuCBaqZMvqE/rNVca3goTgrb89O5SDZIWjcQ7rGvNqk/L+XL8VWCyNhOVlalnFMxKXyE=
DKIM_AR_SIGNED_HEADER
}

sub _transaction_with_headers {
    ( $smtpd ) = Test::Qpsmtpd->new_conn();
    $smtpd->transaction->header(
        Mail::Header->new(Modify => 0, MailFrom => 'COERCE')
    );
    return $smtpd;
}

sub __authentication_results {
    my $smtpd = _transaction_with_headers();
    $smtpd->authentication_results();
    my $ar = $smtpd->transaction->header->get('Authentication-Results'); chomp $ar;
    ok($ar, "added A-R header: $ar");

    $smtpd->{_auth} = OK;
    $smtpd->{_auth_mechanism} = 'test_mech';
    $smtpd->{_auth_user} = 'test@example';
    $smtpd->authentication_results();
    $ar = $smtpd->transaction->header->get('Authentication-Results'); chomp $ar;
    ok($ar =~ /auth=pass/, "added A-R header with auth: $ar");

    delete $smtpd->{_auth};
    $smtpd->connection->notes('authentication_results', 'spf=pass smtp.mailfrom=ietf.org' );
    $smtpd->authentication_results();
    $ar = $smtpd->transaction->header->get('Authentication-Results'); chomp $ar;
    ok($ar =~ /spf/, "added A-R header with SPF: $ar");

}

sub response_is {
    my ( $expected, $descr ) = @_;
    my $response;
    my @r = @{ $smtpd->{_response} || [] };
    $response .= shift @r if @r;
    $response .= ' - ' . join( "\n", @r ) if @r;
    is( $response, $expected, $descr );
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
