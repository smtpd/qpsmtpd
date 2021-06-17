use Test::More tests => 10;
use Test::Output;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

# vrfy command
is(($smtpd->command('VRFY <foo@bar>'))[0], 252, 'VRFY command');

# plugins/count_unrecognized_commands
is(($smtpd->command('nonsense'))[0], 500, 'bad command 1');
is(($smtpd->command('nonsense'))[0], 500, 'bad command 2');
is(($smtpd->command('nonsense'))[0], 500, 'bad command 3');
is(($smtpd->command('nonsense'))[0], 521, 'bad command 4');

