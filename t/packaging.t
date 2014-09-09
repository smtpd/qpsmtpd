use Test::More tests => 1;
use strict;
use File::Compare;

my $file1 = 'LICENSE';
my $file2 = 'debian/copyright';

ok( !compare($file1, $file2), "$file1 matches $file2");
