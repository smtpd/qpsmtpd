use Test::More tests => 23;
use strict;
use lib 't';

use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");
is(($smtpd->command('EHLO localhost'))[0], 250, 'EHLO localhost');

is(($smtpd->command('MAIL FROM:<ask@perl.org>'))[0],
    250, 'MAIL FROM:<ask@perl.org>');
is($smtpd->transaction->sender->address, 'ask@perl.org',
    'got the right sender');

is(($smtpd->command('MAIL FROM:<ask @perl.org>'))[0],
    250, 'MAIL FROM:<ask @perl.org>');
is($smtpd->transaction->sender->address,
    'ask @perl.org',
    'got the right sender');

is(($smtpd->command('MAIL FROM:ask@perl.org'))[0],
    250, 'MAIL FROM:ask@perl.org');
is($smtpd->transaction->sender->format,
    '<ask@perl.org>', 'got the right sender');

is(($smtpd->command('MAIL FROM:ask@[1.2.3.4]'))[0],
    250, 'MAIL FROM:ask@[1.2.3.4]');
is($smtpd->transaction->sender->format,
    '<ask@[1.2.3.4]>', 'got the right sender');

my $command = 'MAIL FROM:<ask@perl.org> SIZE=1230';
is(($smtpd->command($command))[0], 250, $command);
is($smtpd->transaction->sender->format,
    '<ask@perl.org>', 'got the right sender');

$command = 'MAIL FROM:<>';
is(($smtpd->command($command))[0],      250,  $command);
is($smtpd->transaction->sender->format, '<>', 'got the right sender');

$command = 'MAIL FROM:<ask@p.qpsmtpd-test.askask.com> SIZE=1230';
is(($smtpd->command($command))[0], 250, $command);
is($smtpd->transaction->sender->format,
    '<ask@p.qpsmtpd-test.askask.com>',
    'got the right sender');

$command = 'MAIL FROM:<ask@perl.org> SIZE=1230 CORRECT-WITHOUT-ARG';
is(($smtpd->command($command))[0], 250, $command);

$command = 'MAIL FROM:';
is(($smtpd->command($command))[0],      250,  $command);
is($smtpd->transaction->sender->format, '<>', 'got the right sender');

