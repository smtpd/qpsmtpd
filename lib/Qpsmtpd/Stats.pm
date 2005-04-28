# $Id$

package Qpsmtpd::Stats;

use strict;
use Qpsmtpd;
use Qpsmtpd::Constants;
use Time::HiRes qw(time);

my $START_TIME = time;
our $MAILS_RECEIVED = 0;
our $MAILS_REJECTED = 0;
our $MAILS_TEMPFAIL = 0;

sub uptime {
    return (time() - $START_TIME);
}

sub mails_received {
    return $MAILS_RECEIVED;
}

sub mails_rejected {
    return $MAILS_REJECTED;
}

sub mails_tempfailed {
    return $MAILS_TEMPFAIL;
}

sub mails_per_sec {
    return ($MAILS_RECEIVED / uptime());
}

1;