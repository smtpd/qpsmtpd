#!/usr/bin/perl
# Does an internationalized envelope (RFC 6531) survive the trip to the next
# hop? Each queue plugin has to hand the SMTPUTF8 request on in its own way.
use strict;
use warnings;

use IO::Socket::INET;
use POSIX ();
use Test::More;

use lib 't';
use lib 'lib';

use Qpsmtpd::Constants;

use_ok('Test::Qpsmtpd');

__smtp_forward();
__postfix_queue();
__exim_bsmtp();

done_testing();

# A throwaway SMTP server that records the commands it was given into $logfile.
# It offers SMTPUTF8 only when asked to, so both sides of the decision can be
# tested. Returns the port it listens on and the pid serving it.
sub fake_smtpd {
    my (%arg) = @_;

    my $listen = IO::Socket::INET->new(
                                       LocalAddr => '127.0.0.1',
                                       LocalPort => 0,
                                       Listen    => 1,
                                       ReuseAddr => 1,
                                      ) or die "listen: $!";
    my $port = $listen->sockport;

    my $pid = fork();
    die "fork: $!" if !defined $pid;
    if ($pid) {
        close $listen;
        return ($port, $pid);
    }

    # Child. Never let a stuck helper hold the test harness open: time out, and
    # let go of the harness' stdout.
    alarm 20;
    open STDOUT, '>', '/dev/null';
    open STDERR, '>', '/dev/null';
    open my $log, '>', $arg{logfile} or POSIX::_exit(1);

    my $client = $listen->accept;
    if ($client) {
        binmode $client;
        print {$client} "220 relay.example ESMTP\r\n";
        my $in_data = 0;
        while (defined(my $line = <$client>)) {
            $line =~ s/\r?\n$//;
            if ($in_data) {
                next if $line ne '.';
                $in_data = 0;
                print {$client} "250 Ok: queued as 12345\r\n";
                next;
            }
            print {$log} "$line\n";
            if ($line =~ /^EHLO/i) {
                print {$client} "250-relay.example\r\n250-PIPELINING\r\n";
                print {$client} "250-SMTPUTF8\r\n" if $arg{smtputf8};
                print {$client} "250 8BITMIME\r\n";
            }
            elsif ($line =~ /^DATA/i) {
                $in_data = 1;
                print {$client} "354 go ahead\r\n";
            }
            elsif ($line =~ /^QUIT/i) {
                print {$client} "221 bye\r\n";
                last;
            }
            else {
                print {$client} "250 Ok\r\n";
            }
        }
        close $client;
    }
    close $log;    # _exit() skips buffer flushing, so flush by hand
    POSIX::_exit(0);
}

# Build a transaction that is ready to be queued.
sub transaction {
    my ($qp, %arg) = @_;
    my $transaction = $qp->reset_transaction;
    $transaction->sender(Qpsmtpd::Address->new($arg{sender}));
    $transaction->add_recipient(Qpsmtpd::Address->new('recip@example.com'));
    $transaction->notes('smtputf8', 1) if $arg{smtputf8};
    $transaction->header(Mail::Header->new);
    $transaction->header->add('Subject', 'test');
    $transaction->set_body_start;
    $transaction->body_write("body\n");
    return $transaction;
}

sub __smtp_forward {
    my ($qp) = Test::Qpsmtpd->new_conn();
    my $logfile = 't/tmp/smtp-forward-commands';

    my $run = sub {
        my (%arg) = @_;
        my ($port, $pid) =
          fake_smtpd(smtputf8 => $arg{hop_does_utf8}, logfile => $logfile);

        my $plugin =
          $qp->_load_plugin("queue/smtp-forward 127.0.0.1 $port",
                            $qp->plugin_dirs);
        my @rc;
        {
            local $plugin->{_qp} = $qp;    # as Qpsmtpd::Plugin::run_tests does
            @rc = eval {
                $plugin->hook_queue(
                    transaction($qp, sender   => $arg{sender},
                                     smtputf8 => $arg{smtputf8}));
            };
        }
        diag $@ if $@;
        waitpid($pid, 0);

        open my $read, '<', $logfile or die "$logfile: $!";
        chomp(my @commands = <$read>);
        close $read;
        return (\@rc, \@commands);
    };

    # a plain ASCII envelope is forwarded as before, with no extra parameter
    my ($rc, $commands) = $run->(hop_does_utf8 => 1, sender => 'ask@perl.org');
    is($rc->[0], OK, 'ASCII envelope is forwarded');
    ok(grep({ $_ eq 'MAIL FROM:<ask@perl.org>' } @$commands),
        'MAIL FROM carries no SMTPUTF8 parameter when it is not needed')
      or diag explain $commands;

    # NB: no 'use utf8' in this file, the address below is raw UTF-8 octets
    ($rc, $commands) = $run->(hop_does_utf8 => 1,
                              sender        => 'jörg@example.com',
                              smtputf8      => 1);
    is($rc->[0], OK, 'internationalized envelope is forwarded');
    ok(grep({ $_ eq 'MAIL FROM:<jörg@example.com> SMTPUTF8' } @$commands),
        'MAIL FROM carries the SMTPUTF8 parameter to a hop that supports it')
      or diag explain $commands;

    # ... and is held back rather than mangled if the hop cannot take it
    ($rc, $commands) = $run->(hop_does_utf8 => 0,
                              sender        => 'jörg@example.com',
                              smtputf8      => 1);
    is($rc->[0], DECLINED, 'not forwarded to a hop without SMTPUTF8');
    like($rc->[1], qr/does not advertise SMTPUTF8/,
        'and says why it was not forwarded');
    ok(!grep({ /^MAIL FROM/i } @$commands),
        'no MAIL FROM is attempted against a hop without SMTPUTF8')
      or diag explain $commands;

    unlink $logfile;
}

sub __postfix_queue {
    my ($qp) = Test::Qpsmtpd->new_conn();

    # cleanup is told about SMTPUTF8 through the queue flags. Injection itself
    # needs a postfix cleanup socket, so only the flags are checked here.
    my $plugin = $qp->_load_plugin('queue/postfix-queue FLAG_FILTER',
                                   $qp->plugin_dirs);
    my $smtputf8_bit = 1 << 8;    # CLEANUP_FLAG_SMTPUTF8, postfix >= 3.0

    for my $utf8 (0, 1) {
        my $kind = $utf8 ? 'internationalized' : 'ASCII';
        my $transaction = transaction($qp, sender   => 'ask@perl.org',
                                           smtputf8 => $utf8);
        $transaction->notes('postfix-queue-sockets', ['/nonexistent']);
        local $plugin->{_qp} = $qp;
        eval { $plugin->hook_queue($transaction) };    # injection cannot succeed
        my $flags = $transaction->notes('postfix-queue-flags');
        is(!!($flags & $smtputf8_bit), !!$utf8,
            "CLEANUP_FLAG_SMTPUTF8 is "
              . ($utf8 ? 'set' : 'not set') . " for an $kind envelope");
        ok($flags & 0x2, "the configured flags are kept for an $kind envelope");
    }
}

sub __exim_bsmtp {
    my ($qp) = Test::Qpsmtpd->new_conn();

    # Stand in for exim -bS: keep the batch it was fed so it can be inspected.
    my $batch = 't/tmp/exim-bsmtp-batch';
    my $fake_exim = 't/tmp/fake-exim';
    open my $fh, '>', $fake_exim or die "$fake_exim: $!";
    print {$fh} "#!/bin/sh\ncat > $batch\n";
    close $fh;
    chmod 0755, $fake_exim or die "chmod: $!";

    my $plugin = $qp->_load_plugin("queue/exim-bsmtp exim_path ./$fake_exim",
                                   $qp->plugin_dirs);

    my $run = sub {
        my (%arg) = @_;
        unlink $batch;
        local $plugin->{_qp} = $qp;
        my @rc = $plugin->hook_queue(
            transaction($qp, sender   => $arg{sender},
                             smtputf8 => $arg{smtputf8}));
        open my $read, '<', $batch or die "$batch: $!";
        chomp(my @lines = <$read>);
        close $read;
        return (\@rc, \@lines);
    };

    my ($rc, $lines) = $run->(sender => 'ask@perl.org');
    is($rc->[0], OK, 'ASCII envelope is enqueued');
    is($lines->[1], 'MAIL FROM:<ask@perl.org>',
        'MAIL FROM carries no SMTPUTF8 parameter when it is not needed')
      or diag explain $lines;
    like($lines->[0], qr/^HELO /, 'an ASCII batch still opens with HELO');

    # NB: no 'use utf8' in this file, the address below is raw UTF-8 octets
    ($rc, $lines) = $run->(sender => 'jörg@example.com', smtputf8 => 1);
    is($rc->[0], OK, 'internationalized envelope is enqueued');
    is($lines->[1], 'MAIL FROM:<jörg@example.com> SMTPUTF8',
        'MAIL FROM carries the SMTPUTF8 parameter')
      or diag explain $lines;
    like($lines->[0], qr/^EHLO /,
        'the batch opens with EHLO, as SMTPUTF8 is an ESMTP parameter');

    unlink $batch, $fake_exim;
}
