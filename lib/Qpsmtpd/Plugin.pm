package Qpsmtpd::Plugin;
use strict;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  bless ({}, $class);
}



sub register_hook {
  warn "REGISTER HOOK!";
}


1;
