#!/usr/bin/perl -w
use Test::More qw(no_plan);
use File::Path;
use strict;
use lib 't';
use_ok('Test::Qpsmtpd');

BEGIN { # need this to happen before anything else
    my $cwd = `pwd`;
    chomp($cwd);
    open my $spooldir, '>', "./config.sample/spool_dir";
    print $spooldir "$cwd/t/tmp";
    close $spooldir;
}

ok(my ($smtpd, $conn) = Test::Qpsmtpd->new_conn(), "get new connection");

my ($spool_dir,$tempfile,$tempdir) = ( $smtpd->spool_dir,
$smtpd->temp_file(), $smtpd->temp_dir() );

ok( $spool_dir =~ m!t/tmp/$!, "Located the spool directory");
ok( $tempfile =~ /^$spool_dir/, "Temporary filename" );
ok( $tempdir =~ /^$spool_dir/, "Temporary directory" );
ok( -d $tempdir, "And that directory exists" );

unlink "./config.sample/spool_dir";
rmtree($spool_dir);
