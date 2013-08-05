use Test::More tests => 10;
use strict;
use lib 't';

use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");
is(($smtpd->command('EHLO localhost'))[0], 250, 'EHLO localhost');

is(($smtpd->command('MAIL FROM:<ask@perl.org>'))[0],
    250, 'MAIL FROM:<ask@perl.org>');
is($smtpd->transaction->sender->address, 'ask@perl.org',
    'got the right sender');
is(($smtpd->command('RSET'))[0], 250,   'RSET');
is($smtpd->transaction->sender,  undef, 'No sender stored after rset');
