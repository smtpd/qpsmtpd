#!/usr/bin/perl
use strict;
$^W = 1;

use Test::More tests => 24;

BEGIN {
    use_ok('Qpsmtpd::Address');
}

my $as;
my $ao;

$as = '<>';
$ao = Qpsmtpd::Address->parse($as);
ok ($ao, "parse $as");
is ($ao->format, $as, "format $as");

$as = '<foo@example.com>';
$ao = Qpsmtpd::Address->parse($as);
ok ($ao, "parse $as");
is ($ao->format, $as, "format $as");

is ($ao->user, 'foo', 'user');
is ($ao->host, 'example.com', 'host');

# the \ before the @ in the local part is not required, but
# allowed. For simplicity we add a backslash before all characters 
# which are not allowed in a dot-string.
$as = '<"musa_ibrah@caramail.comandrea.luger"@wifo.ac.at>';
$ao = Qpsmtpd::Address->parse($as);
ok ($ao, "parse $as");
is ($ao->format, '<"musa_ibrah\@caramail.comandrea.luger"@wifo.ac.at>', "format $as");

# email addresses with spaces
$as = '<foo bar@example.com>';
$ao = Qpsmtpd::Address->parse($as);
ok ($ao, "parse $as");
is ($ao->format, '<"foo\ bar"@example.com>', "format $as");


$as = 'foo@example.com';
$ao = Qpsmtpd::Address->parse($as);
is ($ao, undef, "can't parse $as");

$as = '<@example.com>';
is (Qpsmtpd::Address->parse($as), undef, "can't parse $as");

$as = '<@123>';
is (Qpsmtpd::Address->parse($as), undef, "can't parse $as");

$as = '<user>';
is (Qpsmtpd::Address->parse($as), undef, "can't parse $as");


$as = 'foo@example.com';
$ao = Qpsmtpd::Address->new($as);
ok ($ao, "new $as");
is ($ao->address, $as, "address $as");

$as = '<foo@example.com>';
$ao = Qpsmtpd::Address->new($as);
ok ($ao, "new $as");
is ($ao->address, 'foo@example.com', "address $as");

$as = '<foo@foo.x.example.com>';
$ao = Qpsmtpd::Address->new($as);
ok ($ao, "new $as");
is ($ao->format, $as, "format $as");

$as = 'foo@foo.x.example.com';
ok ($ao = Qpsmtpd::Address->parse($as), "parse $as");
is ($ao && $ao->address, $as, "address $as");

# Not sure why we can change the address like this, but we can so test it ...
is ($ao->address('test@example.com'), 'test@example.com', 'address(test@example.com)');


