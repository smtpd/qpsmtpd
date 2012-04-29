use Config qw/ myconfig /;
use Data::Dumper;
use English qw/ -no_match_vars /;
use File::Find;
use Test::More;

if ( $ENV{'QPSMTPD_DEVELOPER'} ) {
	'no_plan';
}
else {
	plan skip_all => "not a developer, skipping POD tests";
};

use lib 'lib';

my $this_perl = $Config{'perlpath'} || $EXECUTABLE_NAME;
#ok( $Config{'perlpath'}, "config: $Config{'perlpath'}" );
#ok( $EXECUTABLE_NAME, "var: $EXECUTABLE_NAME" );
#ok( $this_perl, "this_perl: $this_perl" );

my @skip_syntax = qw(
  plugins/milter
  plugins/auth/auth_ldap_bind
  plugins/ident/geoip
  plugins/logging/apache
  plugins/auth/auth_vpopmail
  plugins/virus/clamdscan
  plugins/sender_permitted_from
  plugins/domainkeys
  lib/Apache/Qpsmtpd.pm
  lib/Danga/Client.pm
  lib/Danga/TimeoutSocket.pm
  lib/Qpsmtpd/ConfigServer.pm
  lib/Qpsmtpd/PollServer.pm
  lib/Qpsmtpd/Plugin/Async/DNSBLBase.pm
);
my %skip_syntax = map { $_ => 1 } @skip_syntax;
#print Dumper(\@skip_syntax);

my @files = find( {wanted=>\&test_syntax, no_chdir=>1}, 'plugins', 'lib' );

sub test_syntax { 
  my $f = $File::Find::name;
  chomp $f;
  return if ! -f $f;
  return if $skip_syntax{$f};
  return if $f =~ m/(~|\.(bak|orig|rej))/;
  return if $f =~ /async/;   # requires ParaDNS
  my $r = `$this_perl -Ilib -MQpsmtpd::Constants -c $f 2>&1`;
  my $exit_code = sprintf ("%d", $CHILD_ERROR >> 8);
  ok( $exit_code == 0, "syntax $f");
};

done_testing();

