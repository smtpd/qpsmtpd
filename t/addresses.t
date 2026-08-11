use Test::More;
use strict;
use lib 't';

use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");
is(($smtpd->command('EHLO localhost'))[0], 250, 'EHLO localhost');

is(($smtpd->command('MAIL FROM:<ask@perl.org>'))[0], 250, 'MAIL FROM:<ask@perl.org>');
is($smtpd->transaction->sender->address, 'ask@perl.org', 'got the right sender');

is(($smtpd->command('MAIL FROM:<ask @perl.org>'))[0], 250, 'MAIL FROM:<ask @perl.org>');
is($smtpd->transaction->sender->address, 'ask @perl.org', 'got the right sender');

is(($smtpd->command('MAIL FROM:ask@perl.org'))[0], 250, 'MAIL FROM:ask@perl.org');
is($smtpd->transaction->sender->format, '<ask@perl.org>', 'got the right sender');

is(($smtpd->command('MAIL FROM:ask@[1.2.3.4]'))[0], 250, 'MAIL FROM:ask@[1.2.3.4]');
is($smtpd->transaction->sender->format, '<ask@[1.2.3.4]>', 'got the right sender');

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

# SMTPUTF8, RFC 6531. NB: no 'use utf8' in this file, so the addresses below
# are the raw UTF-8 octets a client would put on the wire.

# Not configured: a non-ASCII address cannot be delivered, so it is refused
# rather than silently mangled into a quoted string.
$command = 'MAIL FROM:<jörg@example.com>';
is(($smtpd->command($command))[0], 550, "$command, refused without SMTPUTF8");

$command = 'MAIL FROM:<jörg@example.com> SMTPUTF8';
is(($smtpd->command($command))[0], 550,
    "$command, refused while SMTPUTF8 is not configured");

$smtpd->mock_config(smtputf8 => 1);

# Configured, but the client has to ask for it (RFC 6531 3.5)
$command = 'MAIL FROM:<jörg@example.com>';
is(($smtpd->command($command))[0], 550,
    "$command, refused when the client does not request SMTPUTF8");

$command = 'MAIL FROM:<jörg@example.com> SMTPUTF8';
is(($smtpd->command($command))[0], 250, $command);
is($smtpd->transaction->sender->format,
    '<jörg@example.com>', 'got the right sender, UTF-8 localpart');
ok($smtpd->transaction->notes('smtputf8'), 'transaction is flagged SMTPUTF8');

$command = 'MAIL FROM:<user@bücher.example> SMTPUTF8 SIZE=1230';
is(($smtpd->command($command))[0], 250, $command);
is($smtpd->transaction->sender->format,
    '<user@bücher.example>', 'got the right sender, UTF-8 domain');

# RFC 6531 3.4: the parameter must not carry a value
$command = 'MAIL FROM:<jörg@example.com> SMTPUTF8=yes';
is(($smtpd->command($command))[0], 501, $command);

# malformed UTF-8 is not an address, no matter what was negotiated
$command = "MAIL FROM:<j\xffrg\@example.com> SMTPUTF8";
is(($smtpd->command($command))[0], 501, 'MAIL FROM with malformed UTF-8');

# an ASCII sender still works with the parameter present, and then permits
# non-ASCII recipients
$smtpd->mock_hook('rcpt', sub { return Qpsmtpd::Constants::OK() });

$command = 'MAIL FROM:<ask@perl.org> SMTPUTF8';
is(($smtpd->command($command))[0], 250, $command);
$command = 'RCPT TO:<jörg@example.com>';
is(($smtpd->command($command))[0], 250, $command);
is(($smtpd->transaction->recipients)[0]->format,
    '<jörg@example.com>', 'got the right recipient');

# ... and refuses them again for a transaction that is not SMTPUTF8
is(($smtpd->command('MAIL FROM:<ask@perl.org>'))[0], 250, 'MAIL FROM:<ask@perl.org>');
$command = 'RCPT TO:<jörg@example.com>';
is(($smtpd->command($command))[0], 553, "$command, refused without SMTPUTF8");

$smtpd->unmock_hook('rcpt');
$smtpd->unmock_config;

done_testing();

