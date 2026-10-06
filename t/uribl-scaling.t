#!/usr/bin/perl
# The uribl patterns run under /g over attacker supplied message bodies. Any
# unbounded quantifier in them makes the scan quadratic in the length of a
# line, so the patterns are lifted straight out of the plugin here and timed:
# duplicating them in the test would let the two drift apart.
use strict;
use warnings;

use Test::More;
use Time::HiRes qw(time);

my $plugin = 'plugins/uribl';
plan skip_all => "$plugin not found" if !-r $plugin;

my $src = do { open my $fh, '<', $plugin or die "$plugin: $!"; local $/; <$fh> };

# Every m{...} applied to $l, i.e. to one line of the message body
my @pattern = $src =~ m/\$l \s* =~ \s* m\{(.*?)\}g[ix]*/gsx;
cmp_ok(scalar @pattern, '>=', 4, 'lifted the body-scanning patterns out of ' . $plugin)
  or BAIL_OUT("could not find the patterns in $plugin");

my $tlds4regex = join '|', qw(com net org info biz uk);   # stands in for the config

# Inputs that made the pre-fix patterns quadratic: a long run with no
# whitespace, so \S+ spanned the rest of the line at every start position, and
# a long unbroken label run with no dot to end it.
my %attack = (
    'repeated URLs'   => sub { ('http://a.' x $_[0]) . '1' },
    'long label run'  => sub { ('a-' x $_[0]) . '.a1' },
    'no separators'   => sub { ('a' x $_[0]) . '!' },
);

for my $i (0 .. $#pattern) {
    my $re = eval { qr{$pattern[$i]}ix };
    if (!$re) {
        fail("pattern $i compiles");
        next;
    }
    for my $name (sort keys %attack) {
        my $line = $attack{$name}->(20_000);
        my $start = time;
        my $count = 0;
        $count++ while $line =~ /$re/g;
        my $elapsed = time - $start;

        # Generous on purpose: linear is milliseconds, the quadratic forms this
        # replaced took seconds to minutes at this size.
        cmp_ok($elapsed, '<', 2,
            sprintf('pattern %d vs %s (%d bytes): %.3fs', $i, $name, length $line, $elapsed));
    }
}

done_testing();
