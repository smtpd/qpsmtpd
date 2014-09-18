#!/usr/bin/perl -w
use strict;
use lib 't';
use Test::Qpsmtpd;
use Test::More::Diagnostic;

my $qp = Test::Qpsmtpd->new();

$qp->run_plugin_tests();

foreach my $file ("./t/config/greylist.dbm", "./t/config/greylist.dbm.lock") {
    next if !-f $file;
    unlink $file;
}

