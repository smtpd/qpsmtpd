use Config qw/ myconfig /;
use Data::Dumper;
use English qw/ -no_match_vars /;
use File::Find;
use Test::More;

if ( ! $ENV{'QPSMTPD_DEVELOPER'} ) {
	plan skip_all => "not a developer, skipping POD tests";
};

use lib 'lib';

my $this_perl = $Config{'perlpath'} || $EXECUTABLE_NAME;

my @files = find( {wanted=>\&test_syntax, no_chdir=>1}, 'plugins', 'lib', 't' );

sub test_syntax { 
    my $f = $File::Find::name;
    chomp $f;
    return if ! -f $f;
    return if $f =~ m/(~|\.(bak|orig|rej))/;
    my $r;
    eval { $r = `$this_perl -Ilib -MQpsmtpd::Constants -c $f 2>&1`; };
    my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
    if ( $exit_code == 0 ) {
        ok( $exit_code == 0, "syntax $f");
        return;
    };
    if ( $r =~ /^Can't locate (.*?) in / ) {
        ok( 0 == 0, "skipping $f, I couldn't load w/o $1");
        return;
    }
    if ( $r =~ /^Base class package "Danga::Socket" is empty/ ) {
        ok( 0 == 0, "skipping $f, Danga::Socket not available.");
        return;
    }
    print "ec: $exit_code, r: $r\n";
};

done_testing();

