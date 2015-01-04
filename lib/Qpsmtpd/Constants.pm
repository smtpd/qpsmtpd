package Qpsmtpd::Constants;
use strict;
require Exporter;

# log levels
my %log_levels = (
                  LOGDEBUG  => 7,
                  LOGINFO   => 6,
                  LOGNOTICE => 5,
                  LOGWARN   => 4,
                  LOGERROR  => 3,
                  LOGCRIT   => 2,
                  LOGALERT  => 1,
                  LOGEMERG  => 0,
                  LOGRADAR  => 0,
                 );

# return codes
my %return_codes = (
         OK                  => 900,
         DENY                => 901,    # 550
         DENYSOFT            => 902,    # 450
         DENYHARD            => 903,    # 550 + disconnect  (deprecated in 0.29)
         DENY_DISCONNECT     => 903,    # 550 + disconnect
         DENYSOFT_DISCONNECT => 904,    # 450 + disconnect
         DECLINED            => 909,
         DONE                => 910,
                   );

use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = (keys(%return_codes), keys(%log_levels), "return_code", "log_level");

foreach (keys %return_codes) {
    eval "use constant $_ => " . $return_codes{$_};
}

foreach (keys %log_levels) {
    eval "use constant $_ => " . $log_levels{$_};
}

sub return_code {
    my $test = shift;
    if ($test =~ /^\d+$/) {    # need to return the textural form
        foreach (keys %return_codes) {
            return $_ if $return_codes{$_} =~ /$test/;
        }
    }
    else {                     # just return the numeric value
        return $return_codes{$test};
    }
}

sub log_level {
    my $test = shift;
    if ($test =~ /^\d+$/) {    # need to return the textural form
        foreach (keys %log_levels) {
            return $_ if $log_levels{$_} =~ /$test/;
        }
    }
    else {                     # just return the numeric value
        return $log_levels{$test};
    }
}

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
