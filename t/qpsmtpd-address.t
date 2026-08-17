#!/usr/bin/perl
use strict;
use warnings;

use Data::Dumper;
use Test::More;

use lib 't';
use lib 'lib';

BEGIN {
    use_ok('Qpsmtpd::Address');
    use_ok('Qpsmtpd::Constants');
    use_ok('Test::Qpsmtpd');
}

__new();
__config();
__parse();
__canonify();
__utf8();

done_testing();

sub __new {
    my ($as, $ao);

    my @unsorted_list = map { Qpsmtpd::Address->new($_) } qw(
      "musa_ibrah@caramail.comandrea.luger"@wifo.ac.at
      foo@example.com
      ask@perl.org
      foo@foo.x.example.com
      jpeacock@cpan.org
      test@example.com
      );

    # NOTE that this is sorted by _host_ not by _domain_
    my @sorted_list = map { Qpsmtpd::Address->new($_) } qw(
      jpeacock@cpan.org
      foo@example.com
      test@example.com
      foo@foo.x.example.com
      ask@perl.org
      "musa_ibrah@caramail.comandrea.luger"@wifo.ac.at
      );

    my @test_list = sort @unsorted_list;

    is_deeply(\@test_list, \@sorted_list, "sort via overloaded 'cmp' operator");

    # RT#38746 - non-RFC compliant address should return undef

    $as = '<user@example.com#>';
    $ao = Qpsmtpd::Address->new($as);
    is($ao, undef, "illegal $as");
    is_deeply($ao, undef, "illegal $as, deeply");

    $ao = Qpsmtpd::Address->new(undef);
    is('<>', $ao, "new, user=undef, stringified");
    is('<>', $ao->format, "new, user=undef, format");
    is_deeply(bless({_user => undef, _host=>undef}, 'Qpsmtpd::Address'), $ao, "new, user=undef, deeply");

    $ao = Qpsmtpd::Address->new('<matt@test.com>');
    is('<matt@test.com>', $ao, 'new, user=matt@test.com, stringified');
    is('<matt@test.com>', $ao->format, 'new, user=matt@test.com, format');
    is_deeply(bless( { '_host' => 'test.com', '_user' => 'matt' }, 'Qpsmtpd::Address' ),
              $ao,
              'new, user=matt@test.com, deeply');

    $ao = Qpsmtpd::Address->new('postmaster');
    is('<>', $ao, "new, user=postmaster, stringified");
    is('<>', $ao->format, "new, user=postmaster, format");
    is_deeply(bless({_user => undef, _host=>undef}, 'Qpsmtpd::Address'), $ao, "new, user=postmaster, deeply");

}

sub __parse {
    my ($as, $ao);

    $as = '<>';
    $ao = Qpsmtpd::Address->parse($as);
    ok($ao, "parse $as");
    is($ao->format, $as, "format $as");

    $as = '<postmaster>';
    $ao = Qpsmtpd::Address->parse($as);
    ok($ao, "parse $as");
    is($ao->format, $as, "format $as");

    $as = '<foo@example.com>';
    $ao = Qpsmtpd::Address->parse($as);
    ok($ao, "parse $as");
    is($ao->format, $as, "format $as");

    is($ao->user, 'foo',         'user');
    is($ao->host, 'example.com', 'host');

    # the \ before the @ in the local part is not required, but
    # allowed. For simplicity we add a backslash before all characters
    # which are not allowed in a dot-string.
    $as = '<"musa_ibrah@caramail.comandrea.luger"@wifo.ac.at>';
    $ao = Qpsmtpd::Address->parse($as);
    ok($ao, "parse $as");
    is($ao->format, '<"musa_ibrah\@caramail.comandrea.luger"@wifo.ac.at>',
        "format $as");

    # email addresses with spaces
    $as = '<foo bar@example.com>';
    $ao = Qpsmtpd::Address->parse($as);
    ok($ao, "parse $as");
    is($ao->format, '<"foo\ bar"@example.com>', "format $as");

    $as = 'foo@example.com';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->address, $as, "address $as");

    $as = '<foo@example.com>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->address, 'foo@example.com', "address $as");

    $as = '<foo@foo.x.example.com>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->format, $as, "format $as");

    $as = 'foo@foo.x.example.com';
    ok($ao = Qpsmtpd::Address->parse('<' . $as . '>'), "parse $as");
    is($ao && $ao->address, $as, "address $as");

   # Not sure why we can change the address like this, but we can so test it ...
    is($ao && $ao->address('test@example.com'),
        'test@example.com', 'address(test@example.com)');

    $as = '<foo@foo.x.example.com>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->format, $as, "format $as");
    is("$ao",       $as, "overloaded stringify $as");

    $as = 'foo@foo.x.example.com';
    ok($ao = Qpsmtpd::Address->parse("<$as>"), "parse <$as>");
    is($ao && $ao->address, $as, "address $as");
    ok($ao eq $as, "overloaded 'cmp' operator");
}

sub __config {
    ok(my ($qp, $cxn) = Test::Qpsmtpd->new_conn(), "get new connection");
    ok($qp->command('HELO test'));
    ok($qp->command('MAIL FROM:<test@example.com>'));
    my $sender = $qp->transaction->sender;
    my @test_data = (
            {
             pref     => 'size_threshold',
             result   => undef,
             expected => 10000,
             descr => 'fall back to global config when user_config is absent',
            },
            {
             pref     => 'test_config',
             result   => undef,
             expected => undef,
             descr    => 'return nothing when no user_config plugins exist',
            },
            {
             pref     => 'test_config',
             result   => [DECLINED],
             expected => undef,
             descr => 'return nothing when user_config plugins return DECLINED',
            },
            {
             pref     => 'test_config',
             result   => [OK, 'test value'],
             expected => 'test value',
             descr => 'return results when user_config plugin returns a value',
            },
    );
    for (@test_data) {
        $qp->mock_hook( 'user_config', sub { return @{$_->{result}} } )
            if $_->{result};
        is($sender->config($_->{pref}), $_->{expected}, $_->{descr});
    }
    $qp->unmock_hook('user_config');
}

sub __canonify {

    my $as = 'foo@x.example.com';
    my $ao = Qpsmtpd::Address->new($as);
    ok( ! defined $Qpsmtpd::Address::domain_expr, "domain_expr is undef");
    ok( $Qpsmtpd::Address::subdomain_expr, "subdomain_expr is defined, $Qpsmtpd::Address::subdomain_expr");

    my @r = Qpsmtpd::Address->canonify('sample@path');
    is_deeply(\@r, [ undef, undef, "missing delimiters" ], 'canonify, missing delimiters');

    @r = Qpsmtpd::Address->canonify('');
    is_deeply(\@r, [ undef, undef, "missing delimiters" ], 'canonify, empty path');

    @r = Qpsmtpd::Address->canonify('<postmaster>');
    is_deeply(\@r, [ 'postmaster', undef, "bare postmaster" ], 'canonify, bare postmaster');

    @r = Qpsmtpd::Address->canonify('<postmaster@test>');
    is_deeply(\@r, [ 'postmaster', 'test', 'local matches atom' ], 'canonify, postmaster@test');

    @r = Qpsmtpd::Address->canonify('<@a:postmaster@test>');
    is_deeply(\@r, [ 'postmaster', 'test', 'local matches atom' ], 'canonify, @a:postmaster@test (source route)');

    @r = Qpsmtpd::Address->canonify('<postmáster@test>');
    is_deeply(\@r, [ 'postmáster', 'test', 'local matches atom' ], 'canonify, postmáster@test, local matches atom');

    @r = Qpsmtpd::Address->canonify('<@192.168.1.1>');
    is_deeply(\@r, [ undef, undef, 'fall through' ], 'canonify, fall through, @192.168.1.1')
        or diag Data::Dumper::Dumper(@r);
}

sub __utf8 {

    # NB: no 'use utf8' here on purpose -- qpsmtpd handles addresses as the
    # raw octets it read off the wire, so the literals below are UTF-8 bytes.
    # Malformed input is written as \x escapes to keep this file valid UTF-8.

    my ($as, $ao);

    $as = '<müller@example.com>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->format, $as, "format $as, UTF-8 localpart is not escaped");
    is($ao->has_utf8, 1, "has_utf8, UTF-8 localpart");

    $as = '<user@müller.example>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->format, $as, "format $as");
    is($ao->has_utf8, 1, "has_utf8, UTF-8 domain");

    $as = '<λ@παράδειγμα.δοκιμή>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->format, $as, "format $as");
    is($ao->user, 'λ',                'user, UTF-8');
    is($ao->host, 'παράδειγμα.δοκιμή', 'host, UTF-8');

    # non-BMP: an emoji localpart is a 4 byte sequence
    $as = '<🐪@example.com>';
    $ao = Qpsmtpd::Address->new($as);
    ok($ao, "new $as");
    is($ao->format, $as, "format $as");

    # quoted-string form, RFC 6531 QcontentSMTP. The quotes are not needed
    # for UTF-8, so canonify drops them
    $ao = Qpsmtpd::Address->new('<"müller"@example.com>');
    ok($ao, 'new <"müller"@example.com>');
    is($ao->format, '<müller@example.com>', 'format <"müller"@example.com>');

    $as = '<foo@example.com>';
    $ao = Qpsmtpd::Address->new($as);
    is($ao->has_utf8, 0, "has_utf8 is false for ASCII $as");

    $ao = Qpsmtpd::Address->new(undef);
    is($ao->has_utf8, 0, 'has_utf8 is false for the null sender');

    # only well-formed UTF-8 is acceptable (RFC 6531 3.3)
    my %malformed = (
        "<m\xffller\@example.com>"     => 'bare non-UTF-8 octet',
        "<m\xc3\@example.com>"         => 'truncated sequence',
        "<\xc0\xaf\@example.com>"      => 'overlong encoding',
        "<\xed\xa0\x80\@example.com>"  => 'surrogate half',
        "<\xf5\x80\x80\x80\@example.com>" => 'beyond U+10FFFF',
        "<user\@m\xffller.example>"    => 'bad octet in the domain',
        "<\x80\x80\@example.com>"      => 'stray continuation bytes',
    );
    for my $bad (sort keys %malformed) {
        my @r = Qpsmtpd::Address->canonify($bad);
        is_deeply(\@r, [undef, undef, 'malformed UTF-8'],
                  "canonify rejects $malformed{$bad}")
          or diag Data::Dumper::Dumper(@r);
        is(Qpsmtpd::Address->new($bad), undef,
           "new returns undef for $malformed{$bad}");
    }

    # a domain label must be a U-label, not any well-formed UTF-8 (RFC 6531 3.3)
    my %not_a_ulabel = (
        "<user\@example.com\xc2\xa0>"     => 'no-break space',
        "<user\@ex\xe3\x80\x80ample.com>" => 'ideographic space',
        "<user\@\xef\xbb\xbfexample.com>" => 'byte order mark',
        "<user\@ex\xe2\x80\x8bample.com>" => 'zero width space',
        "<user\@ex\xc2\xadample.com>"     => 'soft hyphen',
        "<user\@ex\xee\x80\x80ample.com>" => 'private use',
    );
    for my $bad (sort keys %not_a_ulabel) {
        my @r = Qpsmtpd::Address->canonify($bad);
        is_deeply(\@r, [undef, undef, 'disallowed in domain'],
                  "canonify rejects $not_a_ulabel{$bad} in the domain")
          or diag Data::Dumper::Dumper(@r);
        is(Qpsmtpd::Address->new($bad), undef,
           "new returns undef for $not_a_ulabel{$bad} in the domain");
    }

    for my $ok ("<a\xc2\xa0b\@example.com>", "<a\xef\xbb\xbfb\@example.com>") {
        ok(Qpsmtpd::Address->new($ok), 'localpart is not held to U-label rules');
    }
}
