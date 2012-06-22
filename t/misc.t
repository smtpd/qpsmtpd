use Test::More tests => 14;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

# check_spamhelo plugin
is(($smtpd->command('HELO yahoo.com'))[0], 550, 'HELO yahoo.com');


# fault method
is(($smtpd->command('HELO localhost'))[0], 250, 'HELO localhost');
is(($smtpd->fault)->[0], 451, 'fault returns 451');
is(($smtpd->fault("test message"))->[1],
   "Internal error - try again later - test message",
   'returns the input message'
  );


# vrfy command
is(($smtpd->command('VRFY <foo@bar>'))[0], 252, 'VRFY command');

# plugins/count_unrecognized_commands
is(($smtpd->command('nonsense'))[0], 500, 'bad command 1');
is(($smtpd->command('nonsense'))[0], 500, 'bad command 2');
is(($smtpd->command('nonsense'))[0], 500, 'bad command 3');
is(($smtpd->command('nonsense'))[0], 521, 'bad command 4');

