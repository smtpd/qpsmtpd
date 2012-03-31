#!/usr/bin/perl -w
use strict;
use lib 't';
use lib 'lib';
use Test::Qpsmtpd;

my $qp = Test::Qpsmtpd->new();

$qp->run_plugin_tests();

