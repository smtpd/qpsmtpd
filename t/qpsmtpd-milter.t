#!/usr/bin/perl
use strict;
use warnings;

use IO::Socket::IP;
use Mail::Header;
use Test::More;

use lib 't';
use lib 'lib';

use Qpsmtpd::Address;
use Qpsmtpd::Constants;
use Qpsmtpd::Milter;
use Qpsmtpd::Transaction;
use Test::Qpsmtpd;    # creates t/tmp, where the fake milter logs

use constant ALL_ACTIONS    => Qpsmtpd::Milter::ACTIONS;
use constant SMFIP_RCPT_REJ => 0x800;
use constant LEADSPC        => Qpsmtpd::Milter::SMFIP_HDR_LEADSPC;

__negotiate();
__unsupported_version();
__connect();
__no_reply_and_skipped_steps();
__progress();
__body_chunks_and_skip();
__end_of_body_modifications();
__header_whitespace();
__v2_milter_gets_no_data();
__body_replace();
__milter_gone();
__plugin();
__plugin_replies();
__plugin_changes();
__plugin_discard_at_connect();
__plugin_unreachable();
unhook_milter();

done_testing();

# A milter that serves one connection, logs every packet it receives, and
# answers each command with the scripted replies, or 'c'ontinue.
sub fake_milter {
    my (%script) = @_;
    my $log    = "t/tmp/milter-$$.log";
    my $listen = IO::Socket::IP->new(LocalHost => '127.0.0.1', LocalPort => 0,
                                     Listen => 1, ReuseAddr => 1)
      or die "listen: $@";
    unlink $log;

    my $pid = fork // die "fork: $!";
    if (!$pid) {
        alarm 30;
        my $sock = $listen->accept or exit 1;
        open my $fh, '>', $log or exit 1;
        $fh->autoflush(1);
        my %no_reply = map { $_ => 1 } qw(A D Q), @{$script{no_reply} || []};
        while (1) {
            read($sock, my $len, 4) == 4 or last;
            read($sock, my $packet, unpack('N', $len));
            my ($cmd, $data) = (substr($packet, 0, 1), substr($packet, 1));
            print $fh "$cmd " . unpack('H*', $data) . "\n";
            last if $cmd eq 'Q';
            my $replies = $cmd eq 'O'
              ? [['O', pack('NNN', @{$script{optneg} || [6, ALL_ACTIONS, 0]})]]
              : shift @{$script{$cmd} || []};
            next if !$replies && $no_reply{$cmd};
            for my $r (@{$replies || [['c', '']]}) {
                print $sock pack('N', 1 + length $r->[1]) . $r->[0] . $r->[1];
            }
            $sock->flush;
            last if $script{exit_after} && $cmd eq $script{exit_after};
        }
        exit 0;
    }

    my $port = $listen->sockport;
    close $listen;
    my $done = sub {
        waitpid $pid, 0;
        open my $fh, '<', $log or return [];
        my @packets = map { [/^(\S) (\S*)$/] } <$fh>;
        unlink $log;
        return [map { [$_->[0], pack('H*', $_->[1])] } @packets];
    };
    return ($port, $done);
}

sub client {
    my ($port) = @_;
    return Qpsmtpd::Milter->new(host => '127.0.0.1', port => $port,
                                timeout => 5)->negotiate;
}

sub __negotiate {
    my ($port, $done) = fake_milter(
        optneg => [6, ALL_ACTIONS, Qpsmtpd::Milter::SMFIP_NR_HDR | SMFIP_RCPT_REJ]);
    my $m = client($port);
    is($m->version, 6, 'negotiates version 6');
    is($m->actions, ALL_ACTIONS, 'milter actions');
    is($m->protocol, Qpsmtpd::Milter::SMFIP_NR_HDR,
       'unsupported protocol flags are masked off');
    $m->quit;

    my $sent = $done->();
    is($sent->[0][0], 'O', 'first packet is option negotiation');
    is_deeply([unpack 'NNN', $sent->[0][1]],
              [6, ALL_ACTIONS, Qpsmtpd::Milter::PROTOCOL],
              'offers v6, all actions, and every step flag');
    is($sent->[-1][0], 'Q', 'quit');
}

sub __unsupported_version {
    my ($port, $done) = fake_milter(optneg => [7, 0, 0]);
    ok(!eval { client($port) }, 'version 7 is refused');
    like($@, qr/unsupported protocol version 7/, 'error names the version');
    $done->();
}

sub __connect {
    my ($port, $done) = fake_milter(C => [[['y', "554 5.7.1 go away\0"]]]);
    my $m = client($port);
    $m->macros('C', j => 'mx.example.com', '{client_addr}' => undef);
    is_deeply($m->connect('host.example.com', '192.0.2.1', 2525),
              {cmd => 'y', reply => '554 5.7.1 go away'}, 'replycode');
    $m->helo('helo.example.com');
    $m->quit;

    my $sent = $done->();
    is_deeply($sent->[1], ['D', "Cj\0mx.example.com\0"],
              'macros, undefined ones left out');
    is_deeply($sent->[2],
              ['C', "host.example.com\0" . '4' . pack('n', 2525) . "192.0.2.1\0"],
              'connect packet');
    is_deeply($sent->[3], ['H', "helo.example.com\0"], 'helo packet');

    ($port, $done) = fake_milter();
    $m = client($port);
    $m->connect('[2001:db8::1]', '2001:db8::1', 25);
    $m->quit;
    is(substr($done->()->[1][1], 14, 1), '6', 'IPv6 family');
}

sub __no_reply_and_skipped_steps {
    my $nr = Qpsmtpd::Milter::SMFIP_NR_CONN | Qpsmtpd::Milter::SMFIP_NR_HDR;
    my $skip = Qpsmtpd::Milter::SMFIP_NOHELO | Qpsmtpd::Milter::SMFIP_NOMAIL;
    my ($port, $done) = fake_milter(optneg => [6, 0, $nr | $skip],
                                    no_reply => [qw(C L)]);
    my $m = client($port);

    is_deeply([$m->connect('h', '192.0.2.1', 25)], [], 'NR_CONN: no reply read');
    is_deeply([$m->helo('h')], [], 'NOHELO: skipped');
    is_deeply([$m->mail('<a@example.com>')], [], 'NOMAIL: skipped');
    is_deeply($m->rcpt('<b@example.com>', 'NOTIFY=NEVER'), {cmd => 'c'},
              'rcpt replies');
    is_deeply([$m->header('Subject', 'hi')], [], 'NR_HDR: no reply read');
    $m->quit;

    my $sent = $done->();
    is_deeply([map { $_->[0] } @$sent], [qw(O C R L Q)],
              'skipped steps are never sent');
    is($sent->[2][1], "<b\@example.com>\0NOTIFY=NEVER\0", 'rcpt args');
}

sub __progress {
    my ($port, $done) = fake_milter(H => [[['p', ''], ['p', ''], ['t', '']]]);
    my $m = client($port);
    is_deeply($m->helo('h'), {cmd => 't'}, 'progress replies are skipped');
    $m->quit;
    $done->();
}

sub __body_chunks_and_skip {
    my $flags = Qpsmtpd::Milter::SMFIP_SKIP;
    my ($port, $done) = fake_milter(optneg => [6, 0, $flags],
                                    B => [[['c', '']], [['s', '']]]);
    my $m = client($port);
    is_deeply($m->body('x' x (3 * Qpsmtpd::Milter::MAX_BODY_CHUNK)),
              {cmd => 's'}, 'skip ends the body');
    $m->quit;

    my @bodies = grep { $_->[0] eq 'B' } @{$done->()};
    is(scalar @bodies, 2, 'no body chunks are sent after skip');
    is(length $bodies[0][1], Qpsmtpd::Milter::MAX_BODY_CHUNK,
       'body chunks are at most 64k');
}

sub __end_of_body_modifications {
    my ($port, $done) = fake_milter(
        E => [[
            ['h', "X-Spam\0yes\0"],
            ['i', pack('N', 0) . "X-First\0top\0"],
            ['m', pack('N', 1) . "Subject\0\0"],
            ['+', "<new\@example.com>\0"],
            ['2', "<par\@example.com>\0NOTIFY=NEVER\0"],
            ['-', "<old\@example.com>\0"],
            ['e', "<from\@example.com>\0"],
            ['b', "new body\r\n"],
            ['q', "suspicious\0"],
            ['a', ''],
        ]],
        H => [[['h', "X-Early\0no\0"]]],
    );
    my $m = client($port);
    my @changes;
    my $verdict = $m->end_of_body(sub { push @changes, @_ });
    is_deeply($verdict, {cmd => 'a'}, 'the verdict follows the changes');
    is_deeply(
        \@changes,
        [
            {cmd => 'h', name => 'X-Spam', value => ' yes'},
            {cmd => 'i', index => 0, name => 'X-First', value => ' top'},
            {cmd => 'm', index => 1, name => 'Subject', value => ''},
            {cmd => '+', address => '<new@example.com>'},
            {cmd => '2', address => '<par@example.com>', args => 'NOTIFY=NEVER'},
            {cmd => '-', address => '<old@example.com>'},
            {cmd => 'e', address => '<from@example.com>', args => ''},
            {cmd => 'b', body => "new body\r\n"},
            {cmd => 'q', reason => 'suspicious'},
        ],
        'every change is decoded, negotiated or not, as it arrives'
    );

    ok(!eval { $m->helo('h'); 1 }, 'a change before end of message');
    like($@, qr/before the end of the message/, 'is a protocol error');
    $m->quit;
    $done->();
}

sub __header_whitespace {
    my %expect = (
        0       => ["Subject\0 two spaces\0", "X-Tab\0folded\n\tline\0"],
        (LEADSPC) => ["Subject\0  two spaces\0", "X-Tab\0\tfolded\n\tline\0"],
    );
    for my $leadspc (0, LEADSPC) {
        my $mode = $leadspc ? 'with' : 'without';
        my $sp   = $leadspc ? ' ' : '';
        my ($port, $done) = fake_milter(
            optneg => [6, ALL_ACTIONS, $leadspc],
            E      => [[['h', "X-A\0$sp two\0"], ['c', '']]],
        );
        my $m = client($port);
        $m->header('Subject', '  two spaces');
        $m->header('X-Tab', "\tfolded\n\tline");
        my @changes;
        $m->end_of_body(sub { push @changes, @_ });
        $m->quit;

        is_deeply([map { $_->[1] } grep { $_->[0] eq 'L' } @{$done->()}],
                  $expect{$leadspc},
                  "$mode HDR_LEADSPC, extra whitespace reaches the milter");
        is($changes[0]{value}, '  two',
           "$mode HDR_LEADSPC, a changed value is what follows the colon");
    }
}

sub __v2_milter_gets_no_data {
    my ($port, $done) = fake_milter(optneg => [2, 0, 0]);
    my $m = client($port);
    is($m->version, 2, 'a v2 milter is accepted');
    is($m->data, undef, 'DATA is not sent to a v2 milter');
    $m->quit;
    is_deeply([map { $_->[0] } @{$done->()}], [qw(O Q)], 'only O and Q sent');
}

sub __milter_gone {
    my ($port, $done) = fake_milter(exit_after => 'H');
    my $m = client($port);
    $m->helo('h');
    $done->();

    local $SIG{PIPE} = 'DEFAULT';
    ok(!eval { $m->body('x' x (1024 * 1024)); 1 },
       'writing to a milter that went away dies');
    like($@, qr/^milter (write failed|closed the connection)/,
         'with an error the plugin can catch, not SIGPIPE');
}

sub __body_replace {
    for my $spool (0, 1) {
        my $txn = Qpsmtpd::Transaction->new;
        $txn->body_write("Subject: hi\n");
        $txn->set_body_start;
        $txn->body_write("\nold body\nmore\n");
        $txn->body_spool if $spool;
        open my $fh, '<', \"new\n";
        $txn->body_replace($fh);

        $txn->body_resetpos;
        my @lines;
        while (defined(my $l = $txn->body_getline)) { push @lines, $l }
        my $where = $spool ? 'file' : 'memory';
        is_deeply(\@lines, ["\n", "new\n"], "body_replace in $where");
        is($txn->data_size, length("Subject: hi\n\nnew\n"),
           "data_size after body_replace in $where");
    }
}

# hooks are global, and each loaded milter holds its session
sub unhook_milter {
    require Test::Qpsmtpd;
    for my $hook (values %{Test::Qpsmtpd->hooks}) {
        @$hook = grep { $_->{name} ne 'milter' } @$hook;
    }
}

sub plugin {
    my ($port) = @_;
    unhook_milter();
    my ($smtpd) = Test::Qpsmtpd->new_conn();
    my $plugin = $smtpd->_load_plugin("milter test 127.0.0.1:$port timeout 5",
                                      $smtpd->plugin_dirs);
    $plugin->{_qp} = $smtpd;
    return ($smtpd, $plugin);
}

sub __plugin {
    my ($port, $done) = fake_milter(
        R => [[['y', "550-5.7.1 no such\r\n550 5.7.1 user\0"]]],
        E => [[
            ['h', "X-Spam\0yes\0"],
            ['m', pack('N', 1) . "Subject\0changed\0"],
            ['b', "clean\r\nbody\r\n"],
            ['c', ''],
        ]],
    );
    my ($smtpd, $plugin) = plugin($port);
    my $txn = $smtpd->transaction;

    is($plugin->hook_connect($txn), DECLINED, 'connect continues');
    is($plugin->hook_ehlo($txn, 'helo.example.com'), DECLINED, 'ehlo continues');

    my $from = Qpsmtpd::Address->new('<from@example.com>');
    is($plugin->hook_mail($txn, $from, size => 100), DECLINED, 'mail continues');

    my $rcpt = Qpsmtpd::Address->new('<to@example.com>');
    is($plugin->hook_rcpt($txn, $rcpt), DONE, 'reply code rejects the recipient');
    is_deeply([$smtpd->response], [550, '5.7.1 no such', '5.7.1 user'],
              'with the milter\'s code and multi-line text');
    is($plugin->hook_rcpt($txn, $rcpt), DECLINED, 'next rcpt continues');

    $txn->sender($from);
    $txn->add_recipient($rcpt);
    is($plugin->hook_data($txn), DECLINED, 'data continues');

    $txn->header(Mail::Header->new(["Subject: hi\n", "From: <from\@example.com>\n"],
                                   Modify => 0));
    $txn->body_write("Subject: hi\nFrom: <from\@example.com>\n");
    $txn->set_body_start;
    $txn->body_write("\nspam body\n");

    is(($plugin->hook_data_post($txn))[0], DECLINED, 'data_post continues');
    is($txn->header->get('X-Spam'), "yes\n", 'header added');
    is($txn->header->get('Subject'), "changed\n", 'header changed');
    $txn->body_resetpos;
    $txn->body_getline;
    is(join('', $txn->body_getline, $txn->body_getline), "clean\nbody\n",
       'body replaced');
    is($plugin->hook_queue($txn), DECLINED, 'not discarded');

    $plugin->hook_disconnect($txn);
    my $sent = $done->();
    is_deeply([map { $_->[0] } grep { $_->[0] ne 'D' } @$sent],
              [qw(O C H M R R T L L N B E Q)], 'command sequence');
    my ($mail) = grep { $_->[0] eq 'M' } @$sent;
    is($mail->[1], "<from\@example.com>\0SIZE=100\0", 'mail args');
    my ($body) = grep { $_->[0] eq 'B' } @$sent;
    is($body->[1], "spam body\r\n", 'body sent with CRLF, without separator');

    ($port, $done) = fake_milter(M => [[['d', '']]]);
    ($smtpd, $plugin) = plugin($port);
    $txn = $smtpd->transaction;
    $plugin->hook_connect($txn);
    is($plugin->hook_mail($txn, $from), DECLINED, 'discard accepts');
    is($plugin->hook_rcpt($txn, $rcpt), DECLINED, 'rcpt after discard');
    is($plugin->hook_queue($txn), OK, 'discarded message is not queued');
    $plugin->hook_reset_transaction($txn);
    $plugin->hook_disconnect($txn);
    is_deeply([map { $_->[0] } grep { $_->[0] ne 'D' } @{$done->()}],
              [qw(O C M A Q)], 'milter is not consulted after discard; abort on reset');
}

sub __plugin_replies {
    my $from = Qpsmtpd::Address->new('<from@example.com>');
    my $rcpt = Qpsmtpd::Address->new('<to@example.com>');

    my ($port, $done) = fake_milter(
        L => [[['y', "554 5.7.1 bad header\0"]]],
        E => [[['+', "<\xe7\x94\xa8\xe6\x88\xb7\@example.com>\0"], ['c', '']]],
        R => [[["c", ""]], [["c", ""]], [['y', "421 4.7.0 go away\0"]]],
    );
    my ($smtpd, $plugin) = plugin($port);
    my $txn = $smtpd->transaction;
    $plugin->hook_connect($txn);

    is($plugin->hook_data($txn), DECLINED, 'DATA without an envelope');
    $plugin->hook_mail($txn, $from);
    $plugin->hook_rcpt($txn, $rcpt);
    $txn->sender($from);
    $txn->add_recipient($rcpt);
    $txn->header(Mail::Header->new(["Subject: hi\n"], Modify => 0));

    is(($plugin->hook_data_post($txn))[0], DONE, 'reply code at end of message');
    is(($smtpd->response)[0], 554, 'keeps the milter\'s code');
    isnt($smtpd->transaction, $txn, 'and ends the transaction');

    $txn = $smtpd->transaction;
    $plugin->hook_mail($txn, $from);
    is($plugin->hook_rcpt($txn, $rcpt), DECLINED, 'rcpt continues');
    $txn->sender($from);
    $txn->add_recipient($rcpt);
    $txn->header(Mail::Header->new([], Modify => 0));
    is(($plugin->hook_data_post($txn))[0], DECLINED, 'message continues');
    ok($txn->notes('smtputf8'), 'an added UTF-8 recipient requires SMTPUTF8');

    $txn = $smtpd->reset_transaction;
    $plugin->hook_mail($txn, $from);
    is($plugin->hook_rcpt($txn, $rcpt), DONE, '421 at RCPT');
    is(($smtpd->response)[0], 421, 'keeps the 421');
    ok($smtpd->connection->notes('disconnected'), 'and disconnects');

    is_deeply([map { $_->[0] } grep { $_->[0] ne 'D' } @{$done->()}],
              [qw(O C M R L A M R N E M R Q)],
              'no DATA without an envelope; abort after a rejected message');
}

# Start a message on the plugin's session, ready for data_post.
sub message {
    my ($smtpd, $plugin, @header) = @_;
    my $txn  = $smtpd->reset_transaction;
    my $from = Qpsmtpd::Address->new('<from@example.com>');
    my $rcpt = Qpsmtpd::Address->new('<to@example.com>');
    $plugin->hook_mail($txn, $from);
    $plugin->hook_rcpt($txn, $rcpt);
    $txn->sender($from);
    $txn->add_recipient($rcpt);
    $txn->header(Mail::Header->new([@header], Modify => 0));
    $txn->body_write(join '', @header);
    $txn->set_body_start;
    $txn->body_write("\noriginal body\n");
    return $txn;
}

sub body_of {
    my $txn = shift;
    $txn->body_resetpos;
    $txn->body_getline;
    my $body = '';
    while (defined(my $l = $txn->body_getline)) { $body .= $l }
    return $body;
}

sub __plugin_changes {
    my $utf8 = "<\xe7\x94\xa8\xe6\x88\xb7\@example.com>\0";
    my ($port, $done) = fake_milter(
        E => [
            # Rspamd's quarantine: never negotiated, followed by accept
            [   ['m', pack('N', 1) . "Subject\0quarantined\0"],
                ['q', "spam\0"],
                ['a', ''],
            ],

            # rejected: none of the changes are applied
            [   ['h', "X-Spam\0yes\0"],
                ['b', "replaced\r\n"],
                ['r', ''],
            ],

            # a body in chunks, with a CRLF split between two of them
            [   ['b', "line one\r"],
                ['b', "\nline two\r\n"],
                ['+', $utf8],
                ['-', $utf8],
                ['c', ''],
            ],
            [['e', $utf8], ['e', "<ascii\@example.com>\0"], ['c', '']],
        ],
    );
    my ($smtpd, $plugin) = plugin($port);
    $plugin->hook_connect($smtpd->transaction);

    my $txn = message($smtpd, $plugin, "Subject:  two  spaces\n");
    is(($plugin->hook_data_post($txn))[0], DECLINED, 'quarantine, then accept');
    is($txn->notes('milter_quarantine'), 'spam', 'quarantine reason is noted');
    is_deeply($txn->header->header, ["Subject: quarantined\n"],
              'changes sent with quarantine are applied');

    $txn = message($smtpd, $plugin, "Subject: hi\n");
    my @denied;
    $smtpd->mock_hook(deny => sub { shift; shift; push @denied, [@_]; DECLINED });
    is(($plugin->hook_data_post($txn))[0], DONE,
       'the milter still filters the next message');
    $smtpd->unmock_hook('deny');
    is_deeply([$smtpd->response], [550, '5.7.1 Command rejected'],
              'a reject gets Postfix\'s reply, not qpsmtpd\'s 552');
    is_deeply(\@denied, [['milter', DENY, '5.7.1 Command rejected']],
              'and runs the deny hooks');
    is_deeply($txn->header->header, ["Subject: hi\n"],
              'changes before a reject are not applied');
    is(body_of($txn), "original body\n", 'nor is the body replaced');

    $txn = message($smtpd, $plugin, "Subject: hi\n");
    $plugin->hook_data_post($txn);
    is(body_of($txn), "line one\nline two\n",
       'body chunks are joined, CRLF split between chunks included');
    ok(!$txn->notes('smtputf8'),
       'SMTPUTF8 follows the final envelope, not each change');

    $txn = message($smtpd, $plugin, "Subject: hi\n");
    $txn->notes('smtputf8', 1);
    $plugin->hook_data_post($txn);
    is($txn->sender->format, '<ascii@example.com>', 'sender changed twice');
    ok($txn->notes('smtputf8'), 'the client\'s SMTPUTF8 request is kept');

    $plugin->hook_disconnect;
    my @headers = map { $_->[1] } grep { $_->[0] eq 'L' } @{$done->()};
    is($headers[0], "Subject\0 two  spaces\0",
       'header whitespace reaches the milter');
}

sub __plugin_discard_at_connect {
    my ($port, $done) = fake_milter(C => [[['d', '']]]);
    my ($smtpd, $plugin) = plugin($port);
    $plugin->hook_connect($smtpd->transaction);
    my $txn = message($smtpd, $plugin, "Subject: hi\n");
    $plugin->hook_data_post($txn);
    is($plugin->hook_queue($txn), DECLINED,
       'discard at connect does not drop every message');
    $plugin->hook_disconnect;
    is_deeply([map { $_->[0] } grep { $_->[0] ne 'D' } @{$done->()}],
              [qw(O C M R L N B E Q)], 'and the milter is still consulted');
}

sub __plugin_unreachable {
    my $listen = IO::Socket::IP->new(LocalHost => '127.0.0.1', LocalPort => 0,
                                     Listen => 1);
    my $port = $listen->sockport;
    close $listen;

    my ($smtpd, $plugin) = plugin($port);
    my $txn = $smtpd->transaction;
    is($plugin->hook_connect($txn), DECLINED, 'unreachable milter is skipped');
    is($plugin->hook_helo($txn, 'h'), DECLINED, 'and stays skipped');
}
