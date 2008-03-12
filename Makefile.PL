#!/usr/bin/perl -w

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME           => 'qpsmtpd',
    VERSION_FROM   => 'lib/Qpsmtpd.pm',
    PREREQ_PM      => {
        'Mail::Header' => 0,
        'MIME::Base64' => 0,
        'Net::DNS'     => 0.39,
        'Data::Dumper' => 0,
        'File::Temp'   => 0,
        'Time::HiRes'  => 0,
    },
    ABSTRACT       => 'Flexible smtpd daemon written in Perl',
    AUTHOR         => 'Ask Bjorn Hansen <ask@develooper.com>',
    EXE_FILES      => [qw(qpsmtpd qpsmtpd-forkserver qpsmtpd-prefork)],
);

sub MY::libscan {
    my $path = $_[1];
    return '' if $path =~ /\B\.svn\b/;
    return $path;
}

