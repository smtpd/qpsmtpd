#!/usr/bin/perl -w

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME           => 'qpsmtpd',
    VERSION_FROM   => 'lib/Qpsmtpd.pm',
    PREREQ_PM      => { },
    ABSTRACT_FROM  => 'README',
    AUTHOR         => 'Ask Bjorn Hansen <ask@develooper.com>',
    EXE_FILES      => [qw(qpsmtpd qpsmtpd-forkserver)],
);

sub MY::libscan {
    my $path = $_[1];
    return '' if $path =~ /\B\.svn\b/;
    return $path;
}

