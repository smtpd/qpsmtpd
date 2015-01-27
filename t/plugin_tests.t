#!/usr/bin/perl -w
use strict;
use lib 't';
use Test::Qpsmtpd;

my $qp = Test::Qpsmtpd->new();

$qp->run_plugin_tests($ARGV[0]);

