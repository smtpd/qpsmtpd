#!/usr/bin/perl -w

use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'qpsmtpd',
    VERSION_FROM     => 'lib/Qpsmtpd.pm',
    MIN_PERL_VERSION => '5.026000',
    CONFIGURE_REQUIRES => { 'ExtUtils::MakeMaker' => 6.64 },

    # What lib/ and the daemons load. A plugin's dependency does not belong
    # here: `cpanm --installdeps .` treats every entry as mandatory, so one
    # upstream author raising their perl floor would block installing qpsmtpd
    # itself. Those live under recommends, below.
    PREREQ_PM      => {
        'Data::Dumper'    => 0,
        'File::NFSLock'   => 0,    # Qpsmtpd::DB::File::DBM locking
        'File::Temp'      => 0,
        'IO::Socket::SSL' => 0,    # plugins/tls; kept required, as silently
                                   # losing STARTTLS is worse than a build stop
        'Mail::Header'    => 0,
        'MIME::Base64'    => 0,
        'Net::DNS'        => 0.79,
        'Net::IP'         => 1.26,
        'Time::HiRes'     => 0,
    },
    TEST_REQUIRES  => {
        'Test::More'      => 0,
        'Test::Output'    => 0,
    },
    META_MERGE     => {
        'meta-spec' => { version => 2 },
        prereqs     => {
            runtime => {
                recommends => {
                    'CDB_File'       => 0,      # cdb config maps
                    'ClamAV::Client' => 0,      # virus/clamdscan
                    'Date::Parse'    => 0,      # plugins/headers
                    'File::Tail'     => 0,      # log/summarize, log/watch
                    'GeoIP2'         => 2,      # plugins/geoip
                    'Mail::DKIM'     => 0.40,   # plugins/dkim
                    'Mail::DMARC'    => 0,      # plugins/dmarc
                    'Mail::SPF'      => 1,      # plugins/sender_permitted_from
                    'Redis'          => 0,      # Qpsmtpd::DB::Redis
                    'Time::TAI64'    => 0,      # log2sql
#                   'DBI'            => 0,      # auth_vpopmail_sql and
#                   'DBD::mysql'     => 0,      # log2sql
#                   'DBIx::Simple'   => 0,      # log2sql
                },
            },
        },
    },
    ABSTRACT       => 'Flexible smtpd daemon written in Perl',
    AUTHOR         => 'Ask Bjoern Hansen <ask@develooper.com>',
    EXE_FILES      => [qw(qpsmtpd qpsmtpd-forkserver qpsmtpd-prefork)],
    clean          => { FILES => [ '*.bak', 't/tmp' ], },
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
