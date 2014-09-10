use Test::More tests => 14;
use Test::Output;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

# fault method
{
    my $fault;
    stderr_like { $fault = $smtpd->fault }
        qr/program fault - command not performed \(No such file or directory\)/,
        'fault outputs proper warning to STDOUT';
    is($fault->[0], 451, 'fault returns 451');
};
{
    my $fault;
    stderr_like { $fault = $smtpd->fault('test message') }
        qr/test message \(No such file or directory\)/,
        'fault outputs proper custom warning to STDOUT';
    is($fault->[1], 'Internal error - try again later - test message',
       'returns the input message');
};

# vrfy command
is(($smtpd->command('VRFY <foo@bar>'))[0], 252, 'VRFY command');

# plugins/count_unrecognized_commands
is(($smtpd->command('nonsense'))[0], 500, 'bad command 1');
is(($smtpd->command('nonsense'))[0], 500, 'bad command 2');
is(($smtpd->command('nonsense'))[0], 500, 'bad command 3');
is(($smtpd->command('nonsense'))[0], 521, 'bad command 4');

