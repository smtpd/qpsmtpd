#!/usr/bin/perl
use strict;
$^W = 1;

use Test::More qw/no_plan/;

BEGIN {
    use_ok('Qpsmtpd::Address');
}

my $as;
my $ao;

$as = '<>';
$ao = Qpsmtpd::Address->parse($as);
ok ($ao, "parse $as");
is ($ao->format, $as, "format $as");

$as = '<postmaster>';
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
ok ($ao = Qpsmtpd::Address->parse('<'.$as.'>'), "parse $as");
is ($ao && $ao->address, $as, "address $as");

# Not sure why we can change the address like this, but we can so test it ...
is ($ao && $ao->address('test@example.com'), 'test@example.com', 'address(test@example.com)');

$as = '<foo@foo.x.example.com>';
$ao = Qpsmtpd::Address->new($as);
ok ($ao, "new $as");
is ($ao->format, $as, "format $as");
is ("$ao", $as, "overloaded stringify $as");

$as = 'foo@foo.x.example.com';
ok ($ao = Qpsmtpd::Address->parse("<$as>"), "parse <$as>");
is ($ao && $ao->address, $as, "address $as");
ok ($ao eq $as, "overloaded 'cmp' operator");

my @unsorted_list = map { Qpsmtpd::Address->new($_) }
	qw(
	    "musa_ibrah@caramail.comandrea.luger"@wifo.ac.at
	    foo@example.com
	    ask@perl.org
	    foo@foo.x.example.com
	    jpeacock@cpan.org
	    test@example.com
	);

# NOTE that this is sorted by _host_ not by _domain_
my @sorted_list = map { Qpsmtpd::Address->new($_) }
	qw(
	    jpeacock@cpan.org
	    foo@example.com
	    test@example.com
	    foo@foo.x.example.com
	    ask@perl.org
	    "musa_ibrah@caramail.comandrea.luger"@wifo.ac.at
	);

my @test_list = sort @unsorted_list;

is_deeply( \@test_list, \@sorted_list, "sort via overloaded 'cmp' operator");

# RT#38746 - non-RFC compliant address should return undef

$as='<user@example.com#>';
$ao = Qpsmtpd::Address->new($as);
is ($ao, undef, "illegal $as");
