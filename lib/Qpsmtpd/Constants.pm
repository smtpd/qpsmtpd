package Qpsmtpd::Constants;
use strict;
require Exporter;

my (@common) = qw(OK DECLINED DONE DENY DENYSOFT DENYHARD
                  DENY_DISCONNECT DENYSOFT_DISCONNECT
                 );
my (@loglevels) = qw(LOGDEBUG LOGINFO LOGNOTICE LOGWARN LOGERROR LOGCRIT LOGALERT LOGEMERG LOGRADAR);

use vars qw($VERSION @ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = (@common, @loglevels);

use constant OK       => 900;
use constant DENY     => 901;   # 550
use constant DENYSOFT => 902;   # 450
use constant DENYHARD => 903;   # 550 + disconnect  (deprecated in 0.29)
use constant DENY_DISCONNECT     => 903; # 550 + disconnect
use constant DENYSOFT_DISCONNECT => 904; # 450 + disconnect
use constant DECLINED => 909;
use constant DONE     => 910;


# log levels
use constant LOGDEBUG   => 8;
use constant LOGINFO    => 7;
use constant LOGNOTICE  => 6;
use constant LOGWARN    => 5;
use constant LOGERROR   => 4;
use constant LOGCRIT    => 3;
use constant LOGALERT   => 2;
use constant LOGEMERG   => 1;
use constant LOGRADAR   => 0;

1;


=head1 NAME

Qpsmtpd::Constants - Constants for plugins to use

=head1 CONSTANTS

See L<README.plugins> for hook specific information on applicable
constants.

Constants available:

=over 4

=item C<OK>

Return this only from the queue phase to indicate the mail was queued
successfully.

=item C<DENY>

Returning this from a hook causes a 5xx error (hard failure) to be
returned to the connecting client.

=item C<DENYSOFT>

Returning this from a hook causes a 4xx error (temporary failure - try
again later) to be returned to the connecting client.

=item C<DECLINED>

Returning this from a hook implies success, but tells qpsmtpd to go
on to the next plugin.

=item C<DONE>

Returning this from a hook implies success, but tells qpsmtpd to
skip any remaining plugins for this phase.

=back

=cut
