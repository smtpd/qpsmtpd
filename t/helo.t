use Test::More tests => 12;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");
is(($smtpd->command('HELO localhost'))[0], 250, 'HELO localhost');
is(($smtpd->command('EHLO localhost'))[0], 503, 'EHLO localhost (duplicate!)');

ok(($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");
is(($smtpd->command('EHLO localhost'))[0], 250, 'EHLO localhost');

