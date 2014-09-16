#!/usr/bin/perl -w

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME           => 'qpsmtpd',
    VERSION_FROM   => 'lib/Qpsmtpd.pm',
    PREREQ_PM      => {
        'CDB_File'        => 0,
        'Data::Dumper'    => 0,
        'Date::Parse'     => 0,
        'File::Temp'      => 0,
        'Mail::Header'    => 0,
        'MIME::Base64'    => 0,
        'Net::DNS'        => 0.39,
        'Net::IP'         => 0,
        'Time::HiRes'     => 0,
        'IO::Socket::SSL' => 0,
# Dev/Test modules
	    'Test::More'      => 0,
	    'Test::Output'    => 0,
# modules for specific features
        'Mail::DKIM'         => 0,
        'File::Tail'         => 0,   # log/summarize, log/watch
        'Time::TAI64'        => 0,   # log2sql
#       'DBI'                => 0,   # auth_vpopmail_sql and
#       'DBD::mysql'         => 0,   # log2sql
#       'DBIx::Simple'       => 0,   # log2sql
# modules that cause Travis build tests to fail
#       'Mail::SpamAssassin' => 0,
#       'Geo::IP'            => 0,
#       'Math::Complex'      => 0,   # geodesic distance in Geo::IP
#       'Mail::SPF'          => 0,
    },
    ABSTRACT       => 'Flexible smtpd daemon written in Perl',
    AUTHOR         => 'Ask Bjoern Hansen <ask@develooper.com>',
    EXE_FILES      => [qw(qpsmtpd qpsmtpd-forkserver qpsmtpd-prefork qpsmtpd-async)],
    clean          => { FILES => [ '*.bak' ], },
);

sub MY::libscan {
    my $path = $_[1];
    return '' if $path =~ /\B\.svn\b/;
    return $path;
}

sub MY::postamble {
    qq[
testcover :
\t cover -delete && \\
	HARNESS_PERL_SWITCHES=-MDevel::Cover \$(MAKE) test && \\
	cover
]

}
