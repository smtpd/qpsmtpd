#!/usr/bin/perl
use strict;
use warnings;

use Test::More;

ok(my $qp_version = get_qp_version(), 'get_qp_version');
ok(my $rpm_version = get_rpm_version(), "get_rpm_version");
cmp_ok($rpm_version, 'eq', $qp_version, "RPM version is up-to-date");

done_testing();

sub get_qp_version {
    my $rvfile = get_file_contents('lib/Qpsmtpd.pm')
        or return;
    my ($ver_line) = grep { $_ =~ /^our \$VERSION/ } @$rvfile;
    my ($ver) = $ver_line =~ /['"]([0-9\.]+)['"]/;
    return $ver;
}

sub get_rpm_version {
    my $rvfile = get_file_contents('packaging/rpm/VERSION')
        or return;
    chomp @$rvfile;
    return $rvfile->[0];
}

sub get_file_contents {
    my $file = shift;
    open my $fh, '<', $file or do {
        warn "failed to open $file";
        return;
    };
    my @r = <$fh>;
    return \@r;
}
