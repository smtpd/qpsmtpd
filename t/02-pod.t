#!perl

use Test::More;

if ( ! $ENV{'QPSMTPD_DEVELOPER'} ) {
    plan skip_all => "not a developer, skipping POD tests";
    exit;
}

eval "use Test::Pod 1.14";
if ( $@ ) {
    plan skip_all => "Test::Pod 1.14 required for testing POD";
    exit;
};

my @poddirs = qw( lib plugins );
all_pod_files_ok( all_pod_files( @poddirs ) );
done_testing();
