#
# Enhanced Mail System Status Codes - RFC 1893
#
package Qpsmtpd::DSN;
use strict;
use Qpsmtpd::Constants;

=head1 NAME

Qpsmtpd::DSN - Enhanced Mail System Status Codes - RFC 1893

=head1 DESCRIPTION

The B<Qpsmtpd::DSN> implements the I<Enhanced Mail System Status Codes> from
RFC 1893.

=head1 USAGE

Any B<qpsmtpd> plugin can access these status codes. All sub routines are used
the same way:
 use Qpsmtpd::DSN;
 ...;
 return Qpsmtpd::DSN->relaying_denied();

or

 return Qpsmtpd::DSN->relaying_denied("Relaying from $ip denied");

or 

 return Qpsmtpd::DSN->relaying_denied(DENY,"Relaying from $ip denied");

If no status message was given, it will use the predefined one from the 
RFC. If the first argument is numeric, it will use this as a return code, 
else the default return code is used. See below which default return code
is used in the different functions.

The first example will return 
I<(DENY, "Relaying denied");>
the others 
I<(DENY, "Relaying from $ip denied");>
which will be returned to qpsmtpd.

In those sub routines which don't start with I<addr_, sys_, net_, proto_, 
media_, sec_> I've added a default message which describes the status better
than the RFC message.

=cut

my @rfc1893 = (
    [
     "Other or Undefined Status",    # x.0.x
    ],
    [
     "Other address status.",                                    # x.1.0
     "Bad destination mailbox address.",                         # x.1.1
     "Bad destination system address.",                          # x.1.2
     "Bad destination mailbox address syntax.",                  # x.1.3
     "Destination mailbox address ambiguous.",                   # x.1.4
     "Destination address valid.",                               # x.1.5
     "Destination mailbox has moved, No forwarding address.",    # x.1.6
     "Bad sender's mailbox address syntax.",                     # x.1.7
     "Bad sender's system address.",                             # x.1.8
    ],
    [
     "Other or undefined mailbox status.",                       # x.2.0
     "Mailbox disabled, not accepting messages.",                # x.2.1
     "Mailbox full.",                                            # x.2.2
     "Message length exceeds administrative limit.",             # x.2.3
     "Mailing list expansion problem.",                          # x.2.4
    ],
    [
     "Other or undefined mail system status.",                   # x.3.0
     "Mail system full.",                                        # x.3.1
     "System not accepting network messages.",                   # x.3.2
     "System not capable of selected features.",                 # x.3.3
     "Message too big for system.",                              # x.3.4
     "System incorrectly configured.",                           # x.3.5
    ],
    [
     "Other or undefined network or routing status.",            # x.4.0
     "No answer from host.",                                     # x.4.1
     "Bad connection.",                                          # x.4.2
     "Directory server failure.",                                # x.4.3
     "Unable to route.",                                         # x.4.4
     "Mail system congestion.",                                  # x.4.5
     "Routing loop detected.",                                   # x.4.6
     "Delivery time expired.",                                   # x.4.7
    ],
    [
     "Other or undefined protocol status.",                      # x.5.0
     "Invalid command.",                                         # x.5.1
     "Syntax error.",                                            # x.5.2
     "Too many recipients.",                                     # x.5.3
     "Invalid command arguments.",                               # x.5.4
     "Wrong protocol version.",                                  # x.5.5
    ],
    [
     "Other or undefined media error.",                          # x.6.0
     "Media not supported.",                                     # x.6.1
     "Conversion required and prohibited.",                      # x.6.2
     "Conversion required but not supported.",                   # x.6.3
     "Conversion with loss performed.",                          # x.6.4
     "Conversion Failed.",                                       # x.6.5
    ],
    [
     "Other or undefined security status.",                      # x.7.0
     "Delivery not authorized, message refused.",                # x.7.1
     "Mailing list expansion prohibited.",                       # x.7.2
     "Security conversion required but not possible.",           # x.7.3
     "Security features not supported.",                         # x.7.4
     "Cryptographic failure.",                                   # x.7.5
     "Cryptographic algorithm not supported.",                   # x.7.6
     "Message integrity failure.",                               # x.7.7
    ],
);

sub _status {
    my $return = shift;
    my $const  = Qpsmtpd::Constants::return_code($return);
    if ($const =~ /^DENYSOFT/) {
        return 4;
    }
    elsif ($const =~ /^DENY/) {
        return 5;
    }
    elsif ($const eq 'OK' or $const eq 'DONE') {
        return 2;
    }
    else {    # err .... no :)
        return 4;    # just 2,4,5 are allowed.. temp error by default
    }
}

sub _dsn {
    my ($self, $return, $reason, $default, $subject, $detail) = @_;
    if (!defined $return) {
        $return = $default;
    }
    elsif ($return !~ /^\d+$/) {
        $reason = $return;
        $return = $default;
    }
    my $msg = $rfc1893[$subject][$detail];
    unless (defined $msg) {
        $detail = 0;
        $msg    = $rfc1893[$subject][$detail];
        unless (defined $msg) {
            $subject = 0;
            $msg     = $rfc1893[$subject][$detail];
        }
    }
    my $class = &_status($return);
    if (defined $reason) {
        $msg = $reason;
    }
    return $return, "$msg (#$class.$subject.$detail)";
}

sub unspecified { shift->_dsn(shift, shift, DENYSOFT, 0, 0); }

=head1 ADDRESS STATUS

=over 9

=item addr_unspecified

X.1.0
default: DENYSOFT

=cut

sub addr_unspecified { shift->_dsn(shift, shift, DENYSOFT, 1, 0); }

=item no_such_user, addr_bad_dest_mbox

X.1.1
default: DENY

=cut

sub no_such_user { shift->_dsn(shift, (shift || "No such user"), DENY, 1, 1); }
sub addr_bad_dest_mbox { shift->_dsn(shift, shift, DENY, 1, 1); }

=item addr_bad_dest_system 

X.1.2
default: DENY

=cut

sub addr_bad_dest_system { shift->_dsn(shift, shift, DENY, 1, 2); }

=item addr_bad_dest_syntax

X.1.3
default: DENY

=cut

sub addr_bad_dest_syntax { shift->_dsn(shift, shift, DENY, 1, 3); }

=item addr_dest_ambigous

X.1.4
default: DENYSOFT

=cut

sub addr_dest_ambigous { shift->_dsn(shift, shift, DENYSOFT, 1, 4); }

=item addr_rcpt_ok

X.1.5
default: OK

=cut

# XXX: do we need this? Maybe in all address verifying plugins?
sub addr_rcpt_ok { shift->_dsn(shift, shift, OK, 1, 5); }

=item addr_mbox_moved 

X.1.6
default: DENY

=cut

sub addr_mbox_moved { shift->_dsn(shift, shift, DENY, 1, 6); }

=item addr_bad_from_syntax

X.1.7
default: DENY

=cut 

sub addr_bad_from_syntax { shift->_dsn(shift, shift, DENY, 1, 7); }

=item addr_bad_from_system

X.1.8
default: DENY

=back

=cut

sub addr_bad_from_system { shift->_dsn(shift, shift, DENY, 1, 8); }

=head1 MAILBOX STATUS

=over 5

=item mbox_unspecified

X.2.0
default: DENYSOFT

=cut

sub mbox_unspecified { shift->_dsn(shift, shift, DENYSOFT, 2, 0); }

=item mbox_disabled

X.2.1
default: DENY ...but RFC says:
   The mailbox exists, but is not accepting messages.  This may
   be a permanent error if the mailbox will never be re-enabled
   or a transient error if the mailbox is only temporarily
   disabled.

=cut 

sub mbox_disabled { shift->_dsn(shift, shift, DENY, 2, 1); }

=item mbox_full

X.2.2
default: DENYSOFT

=cut

sub mbox_full { shift->_dsn(shift, shift, DENYSOFT, 2, 2); }

=item mbox_msg_too_long 

X.2.3
default: DENY

=cut

sub mbox_msg_too_long { shift->_dsn(shift, shift, DENY, 2, 3); }

=item mbox_list_expansion_problem   

X.2.4
default: DENYSOFT

=back

=cut

sub mbox_list_expansion_problem { shift->_dsn(shift, shift, DENYSOFT, 2, 4); }

=head1 MAIL SYSTEM STATUS

=over 4

=item sys_unspecified

X.3.0
default: DENYSOFT

=cut

sub sys_unspecified { shift->_dsn(shift, shift, DENYSOFT, 3, 0); }

=item sys_disk_full

X.3.1
default: DENYSOFT

=cut

sub sys_disk_full { shift->_dsn(shift, shift, DENYSOFT, 3, 1); }

=item sys_not_accepting_mail

X.3.2
default: DENYSOFT

=cut

sub sys_not_accepting_mail { shift->_dsn(shift, shift, DENYSOFT, 3, 2); }

=item sys_not_supported

X.3.3
default: DENYSOFT
          Selected features specified for the message are not
          supported by the destination system.  This can occur in
          gateways when features from one domain cannot be mapped onto
          the supported feature in another.

=cut

sub sys_not_supported { shift->_dsn(shift, shift, DENYSOFT, 3, 3); }

=item sys_msg_too_big           

X.3.4
default DENY

=back

=cut

sub sys_msg_too_big { shift->_dsn(shift, shift, DENY, 3, 4); }

=head1 NETWORK AND ROUTING STATUS

=cut

=over 4

=item net_unspecified 

X.4.0
default: DENYSOFT

=cut 

sub net_unspecified { shift->_dsn(shift, shift, DENYSOFT, 4, 0); }

# not useful # sub net_no_answer   { shift->_dsn(shift,shift,4,1); }
# not useful # sub net_bad_connection { shift->_dsn(shift,shift,4,2); }

=item net_directory_server_failed, temp_resolver_failed

X.4.3
default: DENYSOFT

=cut

sub temp_resolver_failed {
    shift->_dsn(shift, (shift || "Temporary address resolution failure"),
                DENYSOFT, 4, 3);
}
sub net_directory_server_failed { shift->_dsn(shift, shift, DENYSOFT, 4, 3); }

# not useful # sub net_unable_to_route { shift->_dsn(shift,shift,4,4); }

=item net_system_congested

X.4.5
default: DENYSOFT

=cut

sub net_system_congested { shift->_dsn(shift, shift, DENYSOFT, 4, 5); }

=item net_routing_loop, too_many_hops

X.4.6
default: DENY, but RFC says:
  A routing loop caused the message to be forwarded too many
  times, either because of incorrect routing tables or a user
  forwarding loop. This is useful only as a persistent
  transient error.

Why do we want to DENYSOFT something like this?

=back

=cut

sub net_routing_loop { shift->_dsn(shift, shift, DENY, 4, 6); }
sub too_many_hops {
    shift->_dsn(shift, (shift || "Too many hops"), DENY, 4, 6,);
}

# not useful # sub delivery_time_expired    { shift->_dsn(shift,shift,4,7); }

=head1 MAIL DELIVERY PROTOCOL STATUS

=over 6

=item proto_unspecified

X.5.0
default: DENYSOFT

=cut

sub proto_unspecified { shift->_dsn(shift, shift, DENYSOFT, 5, 0); }

=item proto_invalid_command

X.5.1
default: DENY

=cut

sub proto_invalid_command { shift->_dsn(shift, shift, DENY, 5, 1); }

=item proto_syntax_error

X.5.2
default: DENY

=cut

sub proto_syntax_error { shift->_dsn(shift, shift, DENY, 5, 2); }

=item proto_rcpt_list_too_long, too_many_rcpts

X.5.3
default: DENYSOFT

=cut

sub proto_rcpt_list_too_long { shift->_dsn(shift, shift, DENYSOFT, 5, 3); }
sub too_many_rcpts           { shift->_dsn(shift, shift, DENYSOFT, 5, 3); }

=item proto_invalid_cmd_args 

X.5.4
default: DENY

=cut

sub proto_invalid_cmd_args { shift->_dsn(shift, shift, DENY, 5, 4); }

=item proto_wrong_version 

X.5.5
default: DENYSOFT

=back

=cut

sub proto_wrong_version { shift->_dsn(shift, shift, DENYSOFT, 5, 5); }

=head1 MESSAGE CONTENT OR MESSAGE MEDIA STATUS

=over 5

=item media_unspecified

X.6.0
default: DENYSOFT

=cut

sub media_unspecified { shift->_dsn(shift, shift, DENYSOFT, 6, 0); }

=item media_unsupported

X.6.1
default: DENY

=cut

sub media_unsupported { shift->_dsn(shift, shift, DENY, 6, 1); }

=item media_conv_prohibited

X.6.2
default: DENY

=cut

sub media_conv_prohibited { shift->_dsn(shift, shift, DENY, 6, 2); }

=item media_conv_unsupported

X.6.3
default: DENYSOFT

=cut

sub media_conv_unsupported { shift->_dsn(shift, shift, DENYSOFT, 6, 3); }

=item media_conv_lossy

X.6.4
default: DENYSOFT

=back 

=cut

sub media_conv_lossy { shift->_dsn(shift, shift, DENYSOFT, 6, 4); }

=head1 SECURITY OR POLICY STATUS

=over 8

=item sec_unspecified

X.7.0
default: DENYSOFT

=cut

sub sec_unspecified { shift->_dsn(shift, shift, DENYSOFT, 7, 0); }

=item sec_sender_unauthorized, bad_sender_ip, relaying_denied 

X.7.1
default: DENY

=cut

sub sec_sender_unauthorized { shift->_dsn(shift, shift, DENY, 7, 1); }

sub bad_sender_ip {
    shift->_dsn(shift, (shift || "Bad sender's IP"), DENY, 7, 1,);
}

sub relaying_denied {
    shift->_dsn(shift, (shift || "Relaying denied"), DENY, 7, 1);
}

=item sec_list_dest_prohibited

X.7.2
default: DENY

=cut

sub sec_list_dest_prohibited { shift->_dsn(shift, shift, DENY, 7, 2); }

=item sec_conv_failed 

X.7.3
default: DENY

=cut

sub sec_conv_failed { shift->_dsn(shift, shift, DENY, 7, 3); }

=item sec_feature_unsupported 

X.7.4
default: DENY

=cut

sub sec_feature_unsupported { shift->_dsn(shift, shift, DENY, 7, 4); }

=item sec_crypto_failure

X.7.5
default: DENY

=cut

sub sec_crypto_failure { shift->_dsn(shift, shift, DENY, 7, 5); }

=item sec_crypto_algorithm_unsupported

X.7.6
default: DENYSOFT

=cut

sub sec_crypto_algorithm_unsupported {
    shift->_dsn(shift, shift, DENYSOFT, 7, 6);
}

=item sec_msg_integrity_failure

X.7.7
default: DENY

=back

=cut

sub sec_msg_integrity_failure { shift->_dsn(shift, shift, DENY, 7, 7); }

1;

# vim: st=4 sw=4 expandtab
