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

use Time::HiRes qw(time);

__new();
__config();
__parse();
__canonify();
__utf8();
__control_chars();
__unquoted_at();
__grammar();
__linear_time();
__cmp_safety();
__round_trip();
__address_literals();

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
    is_deeply(\@r, [ undef, undef, 'syntax error' ], 'canonify, syntax error, @192.168.1.1')
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

        # ... and so must every domain of a source route, though it is ignored
        my ($domain) = $bad =~ /\@(.*)>/;
        for my $routed ("<\@$domain:user\@example.com>",
                        "<\@a.example,\@$domain:user\@example.com>")
        {
            my @r = Qpsmtpd::Address->canonify($routed);
            is_deeply(\@r, [undef, undef, 'disallowed in domain'],
                      "canonify rejects $not_a_ulabel{$bad} in a source route")
              or diag Data::Dumper::Dumper(@r);
        }
    }

    ok(Qpsmtpd::Address->new("<\@b\xc3\xbccher.example:user\@example.com>"),
       'a U-label in a source route is fine');

    for my $ok ("<a\xc2\xa0b\@example.com>", "<a\xef\xbb\xbfb\@example.com>") {
        ok(Qpsmtpd::Address->new($ok), 'localpart is not held to U-label rules');
    }
}

sub __control_chars {

    # RFC 5321 permits no control character anywhere in a path. Before this was
    # enforced the domain separator was an unescaped '.' -- written "\." inside
    # a double-quoted string -- so it matched any octet, and the atom branch
    # returned the whole localpart after matching only a prefix of it. Either
    # route carried a NUL into $addr->address, which queue/qmail-queue writes
    # straight into a NUL-delimited envelope.
    my %ctrl = (
        "\x00" => 'NUL',
        "\x01" => 'SOH',
        "\x07" => 'BEL',
        "\x09" => 'TAB',
        "\x0a" => 'LF',
        "\x0d" => 'CR',
        "\x1b" => 'ESC',
        "\x1f" => 'US',
        "\x7f" => 'DEL',
    );
    for my $c (sort keys %ctrl) {
        my $name = $ctrl{$c};
        for my $spec (
            [ "<a\@ex${c}mple.com>",   'domain'              ],
            [ "<a${c}b\@example.com>", 'localpart'           ],
            [ qq{<"a${c}b"\@example.com>}, 'quoted localpart' ],
            [ "<a\@example.com${c}>",  'end of the domain'   ],
            [ "<${c}a\@example.com>",  'start of the path'   ],
          )
        {
            my ($addr, $where) = @$spec;
            my @r = Qpsmtpd::Address->canonify($addr);

            is_deeply(\@r, [undef, undef, 'control character in path'],
                      "canonify rejects $name in the $where")
              or diag Data::Dumper::Dumper(@r);
            is(Qpsmtpd::Address->new($addr), undef,
               "new returns undef for $name in the $where");
        }
    }

    # The separator is a literal dot again, so an arbitrary octet cannot stand
    # in for it. These are printable, so the control-character check is not
    # what rejects them.
    for my $bad ('<a@example!com>', '<a@example/com>', '<a@example#com>') {
        is(Qpsmtpd::Address->new($bad), undef,
           "new returns undef for $bad, separator is not a wildcard");
    }

    # ... while a single label and a genuine dotted domain both still parse
    for my $ok ('<a@examplecom>', '<a@example.com>', '<a@a.b.c.example.com>') {
        ok(Qpsmtpd::Address->new($ok), "still parses $ok");
    }
}

sub __unquoted_at {

    # '@' is not atext (RFC 5321 4.1.2, RFC 5322 3.2.3): outside a quoted
    # localpart the only legal '@' separates the localpart from the domain.
    # The atom branch only matches a prefix of the localpart, so these used
    # to be accepted with everything before the last '@' as the localpart.
    for my $bad ('<a@b@example.com>', '<a@@example.com>',
                 '<a@b.de@example.com>', '<a%b@c@example.com>',
                 '<x"@"y@example.com>', '<a@b@[192.168.1.1]>',
                 '<@r1.example:a@b@example.com>')
    {
        my @r = Qpsmtpd::Address->canonify($bad);
        is_deeply(\@r, [undef, undef, 'unquoted @ in localpart'],
                  "canonify rejects $bad")
          or diag Data::Dumper::Dumper(@r);
        is(Qpsmtpd::Address->new($bad), undef, "new returns undef for $bad");
    }

    # the quoted form is legal and must keep working
    my $ao = Qpsmtpd::Address->new('<"a@b"@example.com>');
    ok($ao, 'new <"a@b"@example.com>');
    is($ao && $ao->user, 'a@b', 'user of quoted localpart keeps its @');
    is($ao && $ao->host, 'example.com', 'host of quoted localpart');

    # as does a source route, the other place a path may hold several '@'
    $ao = Qpsmtpd::Address->new('<@r1.example,@r2.example:u@example.com>');
    is($ao && $ao->address, 'u@example.com', 'source route is still stripped');

    # the documented leniency survives
    for my $ok ('<a.@example.com>', '<a..b@example.com>', '<a b@example.com>') {
        ok(Qpsmtpd::Address->new($ok), "still parses $ok");
    }

    # and the SMTP layer answers with a syntax error
    ok(my ($qp, $cxn) = Test::Qpsmtpd->new_conn(), "get new connection");
    ok($qp->command('HELO test'), 'HELO');
    is(($qp->command('MAIL FROM:<a@b@example.com>'))[0], 501,
       'MAIL FROM:<a@b@example.com> gets 501');
    is(($qp->command('MAIL FROM:<"a@b"@example.com>'))[0], 250,
       'MAIL FROM:<"a@b"@example.com> is still accepted');
}

sub __grammar {

    # specials are only legal inside a quoted localpart (RFC 5321 4.1.2)
    for my $bad ('<a"b@example.com>', '<a(b@example.com>', '<a)b@example.com>',
                 '<a<b@example.com>', '<a>b@example.com>', '<a,b@example.com>',
                 '<a;b@example.com>', '<a:b@example.com>', '<a[b@example.com>',
                 '<a]b@example.com>', '<a\\b@example.com>', '<.a@example.com>',
                 '<"a"b@example.com>', '<"a@example.com>')
    {
        my @r = Qpsmtpd::Address->canonify($bad);
        is_deeply(\@r, [undef, undef, 'syntax error'], "canonify rejects $bad")
          or diag Data::Dumper::Dumper(@r);
    }

    # qtextSMTP includes SP, so a quoted space needs no backslash
    my $ao = Qpsmtpd::Address->new('<"foo bar"@example.com>');
    ok($ao, 'new <"foo bar"@example.com>');
    is($ao && $ao->user,   'foo bar',                  'user keeps its space');
    is($ao && $ao->format, '<"foo\ bar"@example.com>', 'format re-quotes it');

    my %parsed = (
        '<"a\"b"@example.com>'  => ['a"b',   'example.com', 'quoted string'],
        '<"a.b"@example.com>'   => ['a.b',   'example.com', 'quoted string'],
        '<a..b@example.com>'    => ['a..b',  'example.com', 'lenient localpart'],
        '<a.@example.com>'      => ['a.',    'example.com', 'lenient localpart'],
        '<ask @perl.org>'       => ['ask ',  'perl.org',    'lenient localpart'],
        '<a.b-c@example.com>'   => ['a.b-c', 'example.com', 'local matches atom'],
        '<a@[IPv6:2001:db8::1]>' => ['a', '[IPv6:2001:db8::1]', 'local matches atom'],
    );
    for my $path (sort keys %parsed) {
        my @r = Qpsmtpd::Address->canonify($path);
        is_deeply(\@r, $parsed{$path}, "canonify $path")
          or diag Data::Dumper::Dumper(@r);
    }

    # whatever canonify accepts, format must write back as a valid path
    my %formatted = (
        '<a..b@example.com>' => '<"a..b"@example.com>',
        '<a.@example.com>'   => '<"a."@example.com>',
        '<ask @perl.org>'    => '<"ask\ "@perl.org>',
        '<""@example.com>'   => '<""@example.com>',
        '<a.b@example.com>'  => '<a.b@example.com>',
        '<"a.b"@example.com>' => '<a.b@example.com>',
        '<>'                 => '<>',
        '<postmaster>'       => '<postmaster>',
    );
    for my $path (sort keys %formatted) {
        my $ao = Qpsmtpd::Address->new($path);
        is($ao && $ao->format, $formatted{$path}, "format $path");
        my $again = $ao && Qpsmtpd::Address->new($ao->format);
        is($again && $again->user, $ao && $ao->user, "$path round-trips");
    }

    # a source route leads a mailbox; it is not a path of its own. Its
    # At-domain is a Domain only: address literals belong to the mailbox.
    for my $bad ('<@a.example:>', '<@a.example:postmaster>',
                 '<@[127.0.0.1]:u@example.com>',
                 '<@a.example,@[IPv6:::1]:u@example.com>')
    {
        my @r = Qpsmtpd::Address->canonify($bad);
        is_deeply(\@r, [undef, undef, 'syntax error'], "canonify rejects $bad");
    }

    my @routed = Qpsmtpd::Address->canonify('<@a.example,@b.example:u@[127.0.0.1]>');
    is_deeply(\@routed, ['u', '[127.0.0.1]', 'local matches atom'],
              'a routed mailbox may still end in an address literal');

    my @r = Qpsmtpd::Address->canonify("<a\@example.com>\n");
    is_deeply(\@r, [undef, undef, 'missing delimiters'],
              'canonify rejects a newline after the closing bracket');
}

sub __linear_time {

    # Every one of these fails, which is where a backtracking parser goes
    # quadratic or worse. Linear is milliseconds at this size.
    my $n = 20_000;
    my %attack = (
        'long localpart, bad character' => '<' . ('a' x $n) . '(@example.com>',
        'dotted localpart, bad domain'  => '<' . ('a.' x $n) . 'a@' . ('a' x $n) . '!>',
        'many unquoted @'               => '<' . ('a@' x $n) . 'example.com!>',
        'unclosed quote'                => '<"' . ('a' x $n) . '@example.com>',
        'source route, no mailbox'      => '<' . ('@a,' x $n) . '>',
        'domain ending in a hyphen'     => '<a@' . ('a-' x $n) . '>',
        'domain ending in a dot'        => '<a@' . ('a.' x $n) . '>',
        'labels, bad last character'    => '<a@' . ('ab.' x $n) . 'a!>',
    );
    for my $name (sort keys %attack) {
        my $start = time;
        my ($user) = Qpsmtpd::Address->canonify($attack{$name});
        my $elapsed = time - $start;
        ok(!defined $user, "rejects $name");
        cmp_ok($elapsed, '<', 1, sprintf('%s: %.3fs', $name, $elapsed));
    }
}

sub __cmp_safety {

    # cmp is overloaded, so any string compared against an address is fed to
    # new(). That returns undef for anything canonify rejects
    my $addr = Qpsmtpd::Address->new('<a@example.com>');
    for my $junk ('', 'not an address', '<<>>', "a\x00b\@c.com", 'x@ex ample.com',
                  '@', '"', 'Foo <foo@example.com>')
    {
        my $r = eval { $addr eq $junk };
        my $err = $@;
        (my $show = $junk) =~ s/([\x00-\x1f])/sprintf("\\x%02x",ord $1)/ge;
        is($err, '', "comparing an address with '$show' does not die");
        ok(!$r, "  ... and does not compare equal");
    }

    my @sorted = eval { sort { $a cmp $b } map { Qpsmtpd::Address->new($_) }
                        ('<b@example.com>', '<a@example.com>', '<a@aaa.com>') };
    is($@, '', 'sorting addresses does not die');
    is(scalar @sorted, 3, '  ... and keeps every element');
}

sub __round_trip {

    # format() feeds Received: lines, logs and plugin comparisons, so whatever
    # it emits has to parse back to the same thing.
    my @addr = (
        '<foo@example.com>', '<foo.bar@a.b.example.com>', '<postmaster>', '<>',
        '<"foo bar"@example.com>', '<foo bar@example.com>',
        '<"musa_ibrah@caramail.com"@wifo.ac.at>', '<a@[192.168.1.1]>',
        "<user\@b\xc3\xbccher.example>", "<m\xc3\xbcller\@example.com>",
        '<a-b@c-d.example.com>', '<a@examplecom>',
    );
    for my $as (@addr) {
        my $ao = Qpsmtpd::Address->new($as);
        ok($ao, "round trip: parse $as") or next;
        my $f = $ao->format;
        my $bo = Qpsmtpd::Address->new($f);
        ok($bo, "  format $f re-parses") or next;
        is($bo->format, $f, '  ... and format is idempotent');
    }
}

sub __address_literals {

    # RFC 5321 4.1.3: a Snum is 0 through 255, leading zeros allowed, and "::"
    # stands for at least two zero groups, so it leaves room for six explicit
    # groups at most, or four beside an embedded IPv4 address. The tag, like
    # any ABNF string, is case-insensitive.
    for my $ok ('1.2.3.4', '0.0.0.0', '255.255.255.255', '010.001.000.099',
                'IPv6:2001:db8:0:0:0:0:0:1', 'IPv6:2001:db8::1', 'IPv6:::',
                'IPv6:::1', 'IPv6:1:2:3:4:5:6::', 'IPv6:1:2:3:4:5:6:1.2.3.4',
                'IPv6:::ffff:1.2.3.4', 'IPv6:1:2:3:4::1.2.3.4', 'ipv6:FE80::1')
    {
        my $ao = Qpsmtpd::Address->new("<a\@[$ok]>");
        is($ao && $ao->host, "[$ok]", "address literal [$ok]");
    }

    for my $bad ('256.0.0.1', '1.2.3.999', '1.2.3', '1.2.3.4.5', '1.2.3.0001',
                 'IPv6:', 'IPv6:.', 'IPv6:::::::::', 'IPv6:1.2.3.4.5.6',
                 'IPv6:1:2:3:4:5:6:7', 'IPv6:1:2:3:4:5:6:7:8:9',
                 'IPv6:1:2:3:4:5:6:7::', 'IPv6:1::2::3', 'IPv6:12345::',
                 'IPv6:1:2:3:4:5::1.2.3.4', 'IPv6:::256.1.1.1', 'IPv6:fe80::1%eth0',
                 'IPv6 ::1', 'IPv7:::1')
    {
        my @r = Qpsmtpd::Address->canonify("<a\@[$bad]>");
        is_deeply(\@r, [undef, undef, 'syntax error'], "canonify rejects [$bad]")
          or diag Data::Dumper::Dumper(@r);
    }
}
