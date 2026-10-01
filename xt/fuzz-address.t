#!/usr/bin/perl
# Fuzz Qpsmtpd::Address with generated and mutated paths. Every input is
# checked for properties that must always hold, and canonify() is compared
# with an independent byte-at-a-time parser of the same grammar: RFC 5321
# 4.1.2 and 4.1.3, RFC 6531 3.3, and the localpart leniency Address.pm
# documents. The oracle shares no code or regexes with Address.pm, so a
# mistake in the grammar shows up as a disagreement.
#
#   QPSMTPD_DEVELOPER=1 prove -l xt/fuzz-address.t
#   QPSMTPD_DEVELOPER=1 FUZZ_ITERATIONS=2000000 FUZZ_SEED=42 prove -l xt/fuzz-address.t
use strict;
use warnings;

use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use Qpsmtpd::Address;

if (!$ENV{'QPSMTPD_DEVELOPER'}) {
    plan skip_all => "not a developer, skipping fuzz tests";
}

my $iterations = $ENV{FUZZ_ITERATIONS} || 50_000;
my $seed       = $ENV{FUZZ_SEED}       || int time;
srand($seed);
diag "FUZZ_SEED=$seed FUZZ_ITERATIONS=$iterations";

my %atext = map { $_ => 1 } ('a' .. 'z', 'A' .. 'Z', 0 .. 9, split //, q{!#$%&'*+-/=?^_`{|}~});

# length of the well-formed UTF-8 sequence at $i (RFC 3629 4), or 0
sub utf8_len {
    my ($s, $i) = @_;
    my $avail = length($s) - $i;
    my @b = map { $_ < $avail ? ord substr($s, $i + $_, 1) : -1 } 0 .. 3;
    my $in = sub { my ($k, $lo, $hi) = @_; $b[$k] >= $lo && $b[$k] <= $hi };
    my $tail = sub { !grep { !$in->($_, 0x80, 0xBF) } @_ };

    return 2 if $in->(0, 0xC2, 0xDF) && $tail->(1);
    return 3 if $b[0] == 0xE0 && $in->(1, 0xA0, 0xBF) && $tail->(2);
    return 3 if ($in->(0, 0xE1, 0xEC) || $in->(0, 0xEE, 0xEF)) && $tail->(1, 2);
    return 3 if $b[0] == 0xED && $in->(1, 0x80, 0x9F) && $tail->(2);
    return 4 if $b[0] == 0xF0 && $in->(1, 0x90, 0xBF) && $tail->(2, 3);
    return 4 if $in->(0, 0xF1, 0xF3) && $tail->(1, 2, 3);
    return 4 if $b[0] == 0xF4 && $in->(1, 0x80, 0x8F) && $tail->(2, 3);
    return 0;
}

# sub-domain *("." sub-domain), UTF-8 standing in for a letter: the position
# after it, or undef
sub o_domain {
    my ($s, $i) = @_;
    while (1) {
        my $start = $i;
        my $ends_in_let_dig = 0;
        while ($i < length $s) {
            my $ch = substr $s, $i, 1;
            if ($ch =~ /^[A-Za-z0-9]\z/) { $i++; $ends_in_let_dig = 1; next }
            if ($ch eq '-' && $i > $start) { $i++; $ends_in_let_dig = 0; next }
            if (my $len = utf8_len($s, $i)) { $i += $len; $ends_in_let_dig = 1; next }
            last;
        }
        return undef if $i == $start || !$ends_in_let_dig;
        return $i if $i >= length $s || substr($s, $i, 1) ne '.';
        $i++;
    }
}

sub o_ipv4 {
    my @snum = split /\./, shift, -1;
    return @snum == 4 && !grep { !/^[0-9]{1,3}\z/ || $_ > 255 } @snum;
}

sub o_ipv6 {
    my ($addr) = @_;
    my $budget = 8;
    if ($addr =~ /^(.*:)([^:]*\.[^:]*)\z/s) {
        return 0 if !o_ipv4($2);
        $addr = $1;
        $addr =~ s/(?<!:):\z//;
        $budget = 6;
    }
    my @halves = split /::/, $addr, -1;
    return 0 if @halves > 2;
    my @groups = map { length $_ ? split(/:/, $_, -1) : () } @halves;
    return 0 if grep { !/^[0-9A-Fa-f]{1,4}\z/ } @groups;

    # "::" stands for at least two groups of zeros
    return @halves == 2 ? @groups <= $budget - 2 : @groups == $budget;
}

sub o_literal {
    my ($s, $i) = @_;
    return undef if substr($s, $i, 1) ne '[';
    my $end = index $s, ']', $i;
    return undef if $end < 0;
    my $body = substr $s, $i + 1, $end - $i - 1;
    return $end + 1 if o_ipv4($body);
    return $end + 1 if $body =~ /^ipv6:(.*)\z/is && o_ipv6($1);
    return undef;
}

my $not_a_ulabel = qr/[\p{Zs}\p{Zl}\p{Zp}\p{Cc}\p{Cf}\p{Co}]/;

# (user, host, kind), or an empty list for a path that must be rejected
sub oracle {
    my ($path) = @_;
    return if $path !~ /^<(.*)>\z/s;
    my $s = $1;
    return ('', undef, 'empty') if $s eq '';
    return ('postmaster', undef, 'postmaster') if lc $s eq 'postmaster';

    my $i = 0;
    if (substr($s, 0, 1) eq '@') {
        while (1) {
            return if substr($s, $i, 1) ne '@';
            $i = o_domain($s, $i + 1) // return;
            my $ch = substr $s, $i++, 1;
            last if $ch eq ':';
            return if $ch ne ',';
        }
    }
    my $route = substr $s, 0, $i;

    my ($user, $kind) = ('');
    if (substr($s, $i, 1) eq '"') {
        $i++;
        while (1) {
            return if $i >= length $s;
            my $o = ord substr $s, $i, 1;
            if ($o == 0x22) { $i++; last }
            if ($o == 0x5C) {
                return if $i + 1 >= length $s;
                my $next = ord substr $s, $i + 1, 1;
                return if $next < 0x20 || $next > 0x7E;
                $user .= chr $next;
                $i += 2;
                next;
            }
            if ($o >= 0x20 && $o <= 0x7E) { $user .= chr $o; $i++; next }
            my $len = utf8_len($s, $i) or return;
            $user .= substr $s, $i, $len;
            $i += $len;
        }
        $kind = 'quoted string';
    }
    else {
        my $start = $i;
        while ($i < length $s) {
            my $ch = substr $s, $i, 1;
            if ($atext{$ch}) { $i++; next }
            if ($i > $start && ($ch eq '.' || $ch eq ' ')) { $i++; next }
            if (my $len = utf8_len($s, $i)) { $i += $len; next }
            last;
        }
        return if $i == $start;
        $user = substr $s, $start, $i - $start;
        $kind = $user =~ / |\.\.|\.\z/ ? 'lenient localpart' : 'local matches atom';
    }

    return if substr($s, $i++, 1) ne '@';
    my $host = substr $s, $i;
    my $end = o_literal($s, $i) // o_domain($s, $i) // return;
    return if $end != length $s;

    my $domains = $route . $host;
    utf8::decode($domains);
    return if $domains =~ $not_a_ulabel;
    return ($user, $host, $kind);
}

my @atext   = sort keys %atext;
my @special = ('(', ')', '<', '>', '[', ']', ':', ';', '@', '\\', ',', '.', '"', ' ');
my @control = map { chr } 0 .. 0x1F, 0x7F;
my @utf8    = ("\xc3\xbc", "\xe2\x82\xac", "\xf0\x9f\x90\xaa", "\xce\xbb", "\xe4\xbe\x8b");
my @not_a_ulabel = ("\xc2\xa0", "\xef\xbb\xbf", "\xe2\x80\x8b", "\xc2\xad",
    "\xee\x80\x80", "\xe3\x80\x80", "\xe2\x80\xae");
my @malformed = ("\xff", "\xc0\xaf", "\xed\xa0\x80", "\xf5\x80\x80\x80", "\x80",
    "\xc3", "\xe2\x82", "\xf0\x9f\x90");

sub pick   { $_[int rand @_] }
sub chance { rand() < $_[0] }

sub any_char {
    my $r = rand;
    return pick(@atext)        if $r < 0.70;
    return pick(@special)      if $r < 0.82;
    return pick(@utf8)         if $r < 0.90;
    return pick(@not_a_ulabel) if $r < 0.94;
    return pick(@malformed)    if $r < 0.97;
    return pick(@control);
}

sub gen_ipv4 {
    return join '.', map { chance(0.9) ? int rand 256 : chance(0.5) ? sprintf('%03d', rand 256) : int rand 1000 }
      1 .. (chance(0.95) ? 4 : pick(3, 5));
}

sub gen_ipv6 {
    my $v4 = chance(0.2);
    my $n = int rand(($v4 ? 6 : 8) + 2);
    my @g = map { sprintf(pick('%x', '%04x', '%X'), rand 65536) } 1 .. $n;
    push @g, sprintf '%05x', rand 0xFFFFF if chance(0.03);
    if (@g && chance(0.6)) {
        my $at = int rand(@g + 1);
        splice @g, $at, 0, '';
        $g[0] = ':' . $g[0] if $at == 0;
        $g[-1] .= ':' if $at == $#g;
    }
    my $addr = join ':', @g;
    $addr .= ($addr =~ /:\z/ || $addr eq '' ? '' : ':') . gen_ipv4() if $v4;
    $addr = '::' if $addr eq '';
    return pick('IPv6', 'IPv6', 'ipv6', 'IPV6') . ":$addr";
}

sub gen_label {
    join '', map { chance(0.85) ? pick('a' .. 'z', 0 .. 9, '-') : chance(0.7) ? pick(@utf8) : any_char() }
      1 .. 1 + int rand 6;
}

sub gen_domain {
    return '[' . gen_ipv4() . ']' if chance(0.06);
    return '[' . gen_ipv6() . ']' if chance(0.06);
    return '[' . join('', map { any_char() } 1 .. rand 8) . ']' if chance(0.02);
    return join '.', map { gen_label() } 1 .. 1 + int rand 4;
}

sub gen_local {
    if (chance(0.2)) {
        return '"' . join('', map { chance(0.15) ? '\\' . any_char() : any_char() } 0 .. rand 8) . '"';
    }
    my @atoms = map {
        join '', map { chance(0.9) ? pick(@atext, @utf8) : any_char() } 1 .. 1 + int rand 6
    } 1 .. 1 + int rand 3;
    return join(chance(0.9) ? '.' : pick('..', ' ', '. '), @atoms) . (chance(0.05) ? '.' : '');
}

sub gen_path {
    return pick('<>', '<postmaster>', '<PostMaster>') if chance(0.01);
    my $route = chance(0.1) ? join(',', map { '@' . gen_domain() } 1 .. 1 + int rand 3) . ':' : '';
    my $path = $route . gen_local() . '@' . gen_domain();
    return chance(0.97) ? "<$path>" : $path;
}

sub mutate {
    my ($s) = @_;
    for (1 .. 1 + int rand 3) {
        my $at = int rand(length($s) + 1);
        my $r  = rand;
        if    ($r < 0.35) { substr($s, $at, 0) = any_char() }
        elsif ($r < 0.60) { substr($s, $at, 1) = '' }
        elsif ($r < 0.85) { substr($s, $at, 1) = any_char() }
        else              { substr($s, $at, 0) = substr($s, $at, int rand 5) }
    }
    return $s;
}

my %known_reason = map { $_ => 1 } ('missing delimiters', 'empty path',
    'bare postmaster', 'control character in path', 'malformed UTF-8',
    'unquoted @ in localpart', 'disallowed in domain', 'syntax error',
    'local matches atom', 'quoted string', 'lenient localpart');
my %oracle_reason = (empty => 'empty path', postmaster => 'bare postmaster');

sub show {
    my ($s) = @_;
    return 'undef' if !defined $s;
    $s =~ s/([^\x20-\x7e])/sprintf '\\x%02x', ord $1/ge;
    return qq{"$s"};
}

sub same {
    my ($x, $y) = @_;
    return defined $x ? defined $y && $x eq $y : !defined $y;
}

my $reference = Qpsmtpd::Address->new('<a@example.com>');

# '' when every property holds, otherwise what broke. The text before the
# first ':' names the class of failure.
sub check {
    my ($in) = @_;
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };

    my $start = time;
    my @r = eval { Qpsmtpd::Address->canonify($in) };
    return "canonify died: $@" if $@;
    return sprintf('canonify slow: %.3fs', time - $start) if time - $start > 0.05;
    my ($user, $host, $why) = @r;
    return 'unknown reason: ' . show($why) if !defined $why || !$known_reason{$why};

    my ($o_user, $o_host, $o_kind) = oracle($in);
    if (!defined $o_user) {
        return 'accepted, oracle rejects: ' . show($user) . ' @ ' . show($host) if defined $user;
    }
    else {
        return "rejected, oracle accepts: $why" if !defined $user;
        return 'user differs: ' . show($user) . ' vs ' . show($o_user) if !same($user, $o_user);
        return 'host differs: ' . show($host) . ' vs ' . show($o_host) if !same($host, $o_host);
        my $o_why = $oracle_reason{$o_kind} // $o_kind;
        return "reason differs: $why vs $o_why" if $why ne $o_why;
    }

    if (defined $user) {
        for my $part (grep {defined} $user, $host) {
            return 'control character in result: ' . show($part) if $part =~ /[\x00-\x1f\x7f]/;
            my $copy = $part;
            return 'malformed UTF-8 in result: ' . show($part) if !utf8::decode($copy);
        }

        # format() feeds Received: lines, logs and plugin comparisons
        my $ao = eval { Qpsmtpd::Address->new($in) };
        return "new died: $@" if $@;
        return 'new rejects what canonify accepts' if !$ao;
        my $formatted = $ao->format;
        my $again = Qpsmtpd::Address->new($formatted);
        return 'format does not re-parse: ' . show($formatted) if !$again;
        return 'format changes the user: ' . show($formatted) if !same($again->user, $ao->user);
        return 'format changes the host: ' . show($formatted) if !same($again->host, $ao->host);
        return 'format is not idempotent: ' . show($formatted) if $again->format ne $formatted;
        return 'address ne its own format: ' . show($formatted) if !eval { $ao eq $formatted };
    }

    (my $bare = $in) =~ s/^<|>\z//g;
    eval { Qpsmtpd::Address->new($bare) };
    return "new died on unbracketed input: $@" if $@;
    eval { my @sorted = sort { $a cmp $b } $reference, $in; 1 } or return "cmp died: $@";
    return "warning: @warnings" if @warnings;
    return '';
}

sub failure_class { (split /:/, $_[0], 2)[0] }

# the shortest input that still fails the same way, by dropping ever smaller
# chunks of it
sub shrink {
    my ($in, $err) = @_;
    my $class = failure_class($err);
    my $chunk = length $in;
    while ($chunk > 1) {
        $chunk = int(($chunk + 1) / 2);
        my $i = 0;
        while ($i < length $in) {
            my $try = $in;
            substr($try, $i, $chunk) = '';
            my $e = check($try);
            if ($e ne '' && failure_class($e) eq $class) { $in = $try }
            else                                         { $i += $chunk }
        }
    }
    return $in;
}

my (%failures, $accepted);
for (1 .. $iterations) {
    my $in  = chance(0.6) ? gen_path() : mutate(gen_path());
    my $err = check($in);
    if ($err eq '') {
        $accepted++ if defined((Qpsmtpd::Address->canonify($in))[0]);
        next;
    }
    my $f = $failures{failure_class($err)} //= { count => 0 };
    $f->{count}++;
    next if defined $f->{input} && length $f->{input} <= 16;
    my $min = shrink($in, $err);
    if (!defined $f->{input} || length $min < length $f->{input}) {
        $f->{input} = $min;
        $f->{error} = check($min);
    }
}

cmp_ok($accepted, '>', $iterations / 5, "a fair share of inputs parse: $accepted of $iterations");
is(scalar keys %failures, 0, "every property holds across $iterations inputs");
for my $class (sort keys %failures) {
    my $f = $failures{$class};
    diag "$f->{count} x $class\n  input: " . show($f->{input}) . "\n  $f->{error}";
}

# Long runs of one hostile unit, where a backtracking parser goes quadratic
my $slowest = 0;
for (1 .. 300) {
    my $unit = join '', map { any_char() } 1 .. 1 + int rand 4;
    my $run  = $unit x (2_000 + int rand 8_000);
    for my $in ("<$run>", "<$run\@example.com>", "<a\@$run>", "<\@$run:a\@b>", "<a\@[IPv6:$run]>") {
        my $start = time;
        Qpsmtpd::Address->canonify($in);
        my $elapsed = time - $start;
        $slowest = $elapsed if $elapsed > $slowest;
    }
}

# generous: linear is milliseconds at this size
cmp_ok($slowest, '<', 0.5, sprintf('long hostile inputs, slowest %.4fs', $slowest));

done_testing();
