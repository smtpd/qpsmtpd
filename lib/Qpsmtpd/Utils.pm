package Qpsmtpd::Utils;
use strict;

sub tildeexp {
    my ($self, $path) = @_;
    $path =~ s{^~([^/]*)} {  
	  $1
	      ? (getpwnam($1))[7] 
	      : ( $ENV{HOME} || $ENV{LOGDIR} || (getpwuid($>))[7])
	  }ex;
    return $path;
}

sub is_localhost {
    my ($self, $ip) = @_;
    return if ! $ip;
    return 1 if $ip =~ /^127\./;  # IPv4
    return 1 if $ip =~ /:127\./;  # IPv4 mapped IPv6
    return 1 if $ip eq '::1';     # IPv6
    return;
}

1;
