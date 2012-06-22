package Qpsmtpd::Utils;
use strict;

sub tildeexp {
    my $path = shift;
    $path =~ s{^~([^/]*)} {  
	  $1 
	      ? (getpwnam($1))[7] 
	      : ( $ENV{HOME} || $ENV{LOGDIR} || (getpwuid($>))[7])
	  }ex;
    return $path;
}


1;
