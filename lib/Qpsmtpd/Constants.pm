package Qpsmtpd::Constants;
use strict;
require Exporter;

my (@common) = qw(OK DECLINED DONE DENY DENYSOFT TRACE);

use vars qw($VERSION @ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = @common;

use constant TRACE => 10;

use constant OK       => 900;
use constant DENY     => 901;
use constant DENYSOFT => 902;
use constant DECLINED => 909;
use constant DONE     => 910;


1;


=head1 NAME

Qpsmtpd::Constants - Constants should be defined here

=head1 SYNOPSIS

Not sure if we are going to use this...

