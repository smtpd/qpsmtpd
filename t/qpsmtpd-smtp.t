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
__queue_liveness();
__hook_timeout();
__smtputf8();

done_testing();

sub __smtputf8 {
    my ($smtpd) = Test::Qpsmtpd->new_conn();

    # not offered unless configured
    is_deeply( [$smtpd->ehlo_smtputf8], [],
        'SMTPUTF8 is not offered by default' );

    $smtpd->mock_config( smtputf8 => 1 );
    is_deeply( [$smtpd->ehlo_smtputf8], ['SMTPUTF8'],
        'SMTPUTF8 is offered once configured' );

    $smtpd->{_response} = undef;
    $smtpd->ehlo_respond(DECLINED, [''], ['helo.example.com']);
    ok( grep({ $_ eq 'SMTPUTF8' } @{ $smtpd->{_response} }),
        'EHLO response advertises SMTPUTF8' );
    ok( grep({ $_ eq '8BITMIME' } @{ $smtpd->{_response} }),
        'EHLO response still advertises 8BITMIME' );
    $smtpd->unmock_config;

    # The parameter may only be used once it has been advertised.
    # (parse_addr_withhelo, when loaded, rejects any ESMTP parameter in a HELO
    # session earlier still; this is the check for setups without it.)
    my $offer_param = sub {
        my (%arg) = @_;
        my ($smtpd) = Test::Qpsmtpd->new_conn();
        $smtpd->mock_config(smtputf8 => 1) if $arg{configured};
        $smtpd->transaction->notes('capabilities', $arg{capabilities})
          if $arg{capabilities};
        my $greet = $arg{hello} eq 'ehlo' ? 'ehlo_respond' : 'helo_respond';
        $smtpd->$greet(DECLINED, [''], ['helo.example.com']);
        $smtpd->mock_hook('mail', sub { return OK });
        $smtpd->{_response} = undef;
        $smtpd->mail_pre_respond(DECLINED, [''],
                                 ['<ask@perl.org>', {smtputf8 => undef}]);
        $smtpd->unmock_hook('mail');
        $smtpd->unmock_config if $arg{configured};
        return $smtpd->{_response};
    };

    is_deeply($offer_param->(hello => 'helo', configured => 1),
        [555, 'SMTPUTF8 is not supported'],
        'the SMTPUTF8 parameter is refused in a HELO session');
    is_deeply($offer_param->(hello => 'ehlo', configured => 0),
        [555, 'SMTPUTF8 is not supported'],
        'the SMTPUTF8 parameter is refused when the extension is not configured');
    is_deeply($offer_param->(hello => 'ehlo', configured => 1),
        [250, '<ask@perl.org>, sender OK - how exciting to get mail from you!'],
        'the SMTPUTF8 parameter is accepted once it has been advertised');

    is_deeply(
        $offer_param->(hello => 'ehlo', capabilities => ['SMTPUTF8']),
        [250, '<ask@perl.org>, sender OK - how exciting to get mail from you!'],
        'the SMTPUTF8 parameter is accepted when a plugin advertised it');

    # RFC 6531 3.5: 550 for the sender, 553 for a recipient
    is_deeply( $smtpd->respond_smtputf8_required('mail'),
        [550, 'Non-ASCII address requires SMTPUTF8 (#5.6.7)'],
        'MAIL with a non-ASCII address is refused with 550' );
    is_deeply( $smtpd->respond_smtputf8_required('rcpt'),
        [553, 'Non-ASCII address requires SMTPUTF8 (#5.6.7)'],
        'RCPT with a non-ASCII address is refused with 553' );

    # RFC 6531 4.3: the WITH protocol type in the Received: trace field
    my %expect = (
        ''         => 'ESMTP',
        'smtputf8' => 'UTF8SMTP',
    );
    for my $note (sort keys %expect) {
        my ($smtpd) = Test::Qpsmtpd->new_conn();
        $smtpd->connection->hello('ehlo');
        $smtpd->connection->hello_host('helo.example.com');
        $smtpd->transaction->notes($note, 1) if $note;
        # data_respond() normally installs this before the trace field is added
        $smtpd->transaction->header(Mail::Header->new);
        $smtpd->received_line;
        my $received = $smtpd->transaction->header->get('Received');
        like( $received, qr/ with $expect{$note} /,
            "Received: says 'with $expect{$note}'" );
    }

    # the authenticated variant keeps its RFC 3848 suffix
    my ($auth) = Test::Qpsmtpd->new_conn();
    $auth->connection->hello('ehlo');
    $auth->connection->hello_host('helo.example.com');
    $auth->transaction->notes('smtputf8', 1);
    $auth->transaction->header(Mail::Header->new);
    @$auth{qw( _auth _auth_mechanism _auth_user )} = (OK, 'PLAIN', 'user');
    $auth->received_line;
    like( $auth->transaction->header->get('Received'), qr/ with UTF8SMTPA /,
        "Received: says 'with UTF8SMTPA' for an authenticated session" );

    # HELO stays SMTP even if a transaction somehow got flagged
    my ($helo) = Test::Qpsmtpd->new_conn();
    $helo->connection->hello('helo');
    $helo->connection->hello_host('helo.example.com');
    $helo->transaction->notes('smtputf8', 1);
    $helo->transaction->header(Mail::Header->new);
    $helo->received_line;
    like( $helo->transaction->header->get('Received'), qr/ with SMTP /,
        'a HELO session is never recorded as UTF8SMTP' );

    # RFC 6532: message data is opaque octets to qpsmtpd, so a UTF-8 header
    # and body must come back out of DATA exactly as they went in
    my ($data) = Test::Qpsmtpd->new_conn();
    $data->transaction->sender(Qpsmtpd::Address->new('sender@example.com'));
    $data->transaction->add_recipient(Qpsmtpd::Address->new('recip@example.com'));
    $data->connection->notes( disconnected => 0 );
    $data->mock_data([
        "Subject: Grüße aus München\r\n",
        "\r\n",
        "Hätten Sie's gewusst? 🐪\r\n",
        ".\r\n",
    ]);
    {
        no warnings 'redefine';
        local *Qpsmtpd::run_hooks = sub { return (DECLINED, '') };
        $data->data_respond(DECLINED);
    }
    is( $data->transaction->header->get('Subject'), "Grüße aus München\n",
        'UTF-8 header survives DATA unchanged' );
    like( $data->transaction->body_as_string, qr/\QHätten Sie's gewusst? 🐪\E/,
        'UTF-8 body survives DATA unchanged' );
}

sub __queue_liveness {
    # client still connected: queue proceeds to the queue hooks
    my ($smtpd) = Test::Qpsmtpd->new_conn();
    $smtpd->transaction->sender(Qpsmtpd::Address->new('sender@example.com'));
    $smtpd->transaction->add_recipient(Qpsmtpd::Address->new('r@example.com'));
    my $ran = 0;
    $smtpd->mock_hook('queue', sub { $ran = 1; return DONE });
    $smtpd->queue($smtpd->transaction);
    ok( $ran, "queue hooks run when the client is still connected" );
    $smtpd->unmock_hook('queue');

    # client gone before queue: discard without running queue hooks
    ($smtpd) = Test::Qpsmtpd->new_conn();
    $smtpd->transaction->sender(Qpsmtpd::Address->new('sender@example.com'));
    $smtpd->transaction->add_recipient(Qpsmtpd::Address->new('r@example.com'));
    $ran = 0;
    $smtpd->mock_hook('queue', sub { $ran = 1; return DONE });
    $smtpd->{_response} = undef;
    no warnings 'redefine';
    local *Test::Qpsmtpd::check_socket = sub { 0 };
    $smtpd->queue($smtpd->transaction);
    ok( !$ran, "queue hooks skipped when client disconnected before queue" );
    is( $smtpd->{_response}, undef, "no response sent to a disconnected client" );
    ok( !$smtpd->transaction->sender, "transaction discarded when client is gone" );
    $smtpd->unmock_hook('queue');
}

sub __hook_timeout {
    my ($smtpd) = Test::Qpsmtpd->new_conn();

    # config parsing: per-plugin override, comments, and global fallback
    no warnings 'redefine';
    local *Test::Qpsmtpd::config = sub {
        my ($self, $key) = @_;
        return (5)                                if $key eq 'hook_timeout';
        return ('# comment', 'slow 2', 'other:9') if $key eq 'plugin_timeouts';
        return;
    };
    delete $smtpd->{$_} for qw( _hook_timeouts _hook_timeout_default );
    is( $smtpd->hook_timeout('slow'),  2, "per-plugin timeout (space form)" );
    is( $smtpd->hook_timeout('other'), 9, "per-plugin timeout (colon form)" );
    is( $smtpd->hook_timeout('unlisted'), 5, "falls back to global hook_timeout" );

    # a hook that overruns its timeout is aborted rather than blocking forever
    $smtpd->{_hook_timeouts} = {};
    $smtpd->{_hook_timeout_default} = 1;
    my $finished = 0;
    $smtpd->mock_hook('slow_test_hook', sub { sleep 4; $finished = 1; return DECLINED });
    my $start = time;
    $smtpd->run_hooks('slow_test_hook');
    ok( time - $start < 4, "slow hook aborted by hook_timeout" );
    ok( !$finished, "hook did not run to completion after timeout" );
    $smtpd->unmock_hook('slow_test_hook');
}

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

    __data_respond_barelf();
}

sub __data_respond_barelf {
    # A well-formed message must not be rejected as bare-LF; a bare LF/CR on
    # any line must be.
    my $drive = sub {
        my @lines = @_;
        ( $smtpd ) = Test::Qpsmtpd->new_conn();
        $smtpd->transaction->sender(Qpsmtpd::Address->new('sender@example.com'));
        $smtpd->transaction->add_recipient(Qpsmtpd::Address->new('recip@example.com'));
        $smtpd->connection->notes( disconnected => 0 );
        $smtpd->mock_data( [@lines] );

        # Neutralize the data_* hooks so the barelf check in the DATA loop is
        # exercised in isolation from the configured plugins.
        no warnings 'redefine';
        local *Qpsmtpd::run_hooks = sub { return (DECLINED, '') };
        $smtpd->data_respond(DECLINED);
        return ($smtpd->response)[0];
    };

    my $code = $drive->("From: a\@example.com\r\n", "Date: now\r\n", "\r\n", "body\r\n", ".\r\n");
    isnt( $code, 421, 'well-formed message is not rejected as bare-LF' );
    isnt( $smtpd->connection->notes('disconnected'), 1,
        'well-formed message does not disconnect' );

    $code = $drive->("From: a\@example.com\r\n", "bare\n", ".\r\n");
    is( $code, 421, 'bare LF in body is rejected' );
    is( $smtpd->connection->notes('disconnected'), 1, 'bare LF in body disconnects' );

    $code = $drive->("From: a\@example.com\r\n", "\r\n", "body\r\n", ".\n");
    is( $code, 421, 'bare LF terminator is rejected' );
    is( $smtpd->connection->notes('disconnected'), 1, 'bare LF terminator disconnects' );
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
    $smtpd->connection->notes('authentication_results', 'iprev=pass' );
    $smtpd->authentication_results();
    $ar = $smtpd->transaction->header->get('Authentication-Results'); chomp $ar;
    ok($ar =~ /iprev/, "added A-R header with connection results: $ar");

    $smtpd->transaction->notes('authentication_results', 'spf=pass smtp.mailfrom=ietf.org' );
    $smtpd->authentication_results();
    $ar = $smtpd->transaction->header->get('Authentication-Results'); chomp $ar;
    ok($ar =~ /iprev/ && $ar =~ /spf/, "A-R header collates connection + transaction: $ar");

    # #322 regression: a second message on the same connection must not inherit
    # the first transaction's auth results, but must keep connection results.
    $smtpd->reset_transaction;
    $smtpd->transaction->header(
        Mail::Header->new(Modify => 0, MailFrom => 'COERCE')
    );
    $smtpd->authentication_results();
    $ar = $smtpd->transaction->header->get('Authentication-Results'); chomp $ar;
    ok($ar =~ /iprev/, "connection results persist to next transaction: $ar");
    ok($ar !~ /spf/, "transaction results do not leak to next transaction: $ar");

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
