#!/usr/bin/perl
use strict;
use warnings;

use Test::More tests => 9;

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


