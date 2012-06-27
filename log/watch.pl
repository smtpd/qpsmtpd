#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use File::Tail;

my $dir = find_qp_log_dir() or die "unable to find QP home dir";
my $file = "$dir/main/current";
my $fh = File::Tail->new(name=>$file, interval=>1, maxinterval=>1, debug =>1, tail =>100 );

while ( defined (my $line = $fh->read) ) {
    my (undef, $line) = split /\s/, $line, 2; # strip off tai timestamps
    print $line;
};

sub find_qp_log_dir {
    foreach my $user ( qw/ qpsmtpd smtpd / ) {

        my ($homedir) = (getpwnam( $user ))[7] or next;

        if ( -d "$homedir/log" ) {
            return "$homedir/log";
        };
        if ( -d "$homedir/smtpd/log" ) {
            return "$homedir/smtpd/log";
        };
    };
};
