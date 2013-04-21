#
# Qpsmtpd::Postfix::Constants
#
# This is a generated file, do not edit
#
# created by pf2qp.pl v0.1 @ Sun Oct 29 09:10:18 2006
# postfix version 2.4
#
package Qpsmtpd::Postfix::Constants;

use Qpsmtpd::Constants;

require Exporter;

use vars qw(@ISA @EXPORT %cleanup_soft %cleanup_hard $postfix_version);
use strict;

@ISA    = qw(Exporter);
@EXPORT = qw(
  %cleanup_soft
  %cleanup_hard
  $postfix_version
  CLEANUP_FLAG_NONE
  CLEANUP_FLAG_BOUNCE
  CLEANUP_FLAG_FILTER
  CLEANUP_FLAG_HOLD
  CLEANUP_FLAG_DISCARD
  CLEANUP_FLAG_BCC_OK
  CLEANUP_FLAG_MAP_OK
  CLEANUP_FLAG_MILTER
  CLEANUP_FLAG_FILTER_ALL
  CLEANUP_FLAG_MASK_EXTERNAL
  CLEANUP_FLAG_MASK_INTERNAL
  CLEANUP_FLAG_MASK_EXTRA
  CLEANUP_STAT_OK
  CLEANUP_STAT_BAD
  CLEANUP_STAT_WRITE
  CLEANUP_STAT_SIZE
  CLEANUP_STAT_CONT
  CLEANUP_STAT_HOPS
  CLEANUP_STAT_RCPT
  CLEANUP_STAT_PROXY
  CLEANUP_STAT_DEFER
  CLEANUP_STAT_MASK_CANT_BOUNCE
  CLEANUP_STAT_MASK_INCOMPLETE
  );

$postfix_version = "2.4";
use constant CLEANUP_FLAG_NONE    => 0;        # /* No special features */
use constant CLEANUP_FLAG_BOUNCE  => (1 << 0); # /* Bounce bad messages */
use constant CLEANUP_FLAG_FILTER  => (1 << 1); # /* Enable header/body checks */
use constant CLEANUP_FLAG_HOLD    => (1 << 2); # /* Place message on hold */
use constant CLEANUP_FLAG_DISCARD => (1 << 3); # /* Discard message silently */
use constant CLEANUP_FLAG_BCC_OK  => (1 << 4)
  ;    # /* Ok to add auto-BCC addresses */
use constant CLEANUP_FLAG_MAP_OK => (1 << 5); # /* Ok to map addresses */
use constant CLEANUP_FLAG_MILTER => (1 << 6); # /* Enable Milter applications */
use constant CLEANUP_FLAG_FILTER_ALL =>
  (CLEANUP_FLAG_FILTER | CLEANUP_FLAG_MILTER);
use constant CLEANUP_FLAG_MASK_EXTERNAL =>
  (CLEANUP_FLAG_FILTER_ALL | CLEANUP_FLAG_BCC_OK | CLEANUP_FLAG_MAP_OK);
use constant CLEANUP_FLAG_MASK_INTERNAL => CLEANUP_FLAG_MAP_OK;
use constant CLEANUP_FLAG_MASK_EXTRA =>
  (CLEANUP_FLAG_HOLD | CLEANUP_FLAG_DISCARD);

use constant CLEANUP_STAT_OK    => 0;         # /* Success. */
use constant CLEANUP_STAT_BAD   => (1 << 0);  # /* Internal protocol error */
use constant CLEANUP_STAT_WRITE => (1 << 1);  # /* Error writing message file */
use constant CLEANUP_STAT_SIZE  => (1 << 2);  # /* Message file too big */
use constant CLEANUP_STAT_CONT  => (1 << 3);  # /* Message content rejected */
use constant CLEANUP_STAT_HOPS  => (1 << 4);  # /* Too many hops */
use constant CLEANUP_STAT_RCPT  => (1 << 6);  # /* No recipients found */
use constant CLEANUP_STAT_PROXY => (1 << 7);  # /* Proxy reject */
use constant CLEANUP_STAT_DEFER => (1 << 8);  # /* Temporary reject */
use constant CLEANUP_STAT_MASK_CANT_BOUNCE =>
  (CLEANUP_STAT_BAD | CLEANUP_STAT_WRITE | CLEANUP_STAT_DEFER);
use constant CLEANUP_STAT_MASK_INCOMPLETE =>
  (CLEANUP_STAT_BAD | CLEANUP_STAT_WRITE | CLEANUP_STAT_SIZE |
    CLEANUP_STAT_DEFER);

%cleanup_soft = (
                 CLEANUP_STAT_DEFER => "service unavailable (#4.7.1)",
                 CLEANUP_STAT_PROXY => "queue file write error (#4.3.0)",
                 CLEANUP_STAT_BAD   => "internal protocol error (#4.3.0)",
                 CLEANUP_STAT_WRITE => "queue file write error (#4.3.0)",
                );
%cleanup_hard = (
                 CLEANUP_STAT_RCPT => "no recipients specified (#5.1.0)",
                 CLEANUP_STAT_HOPS => "too many hops (#5.4.0)",
                 CLEANUP_STAT_SIZE => "message file too big (#5.3.4)",
                 CLEANUP_STAT_CONT => "message content rejected (#5.7.1)",
                );
1;
