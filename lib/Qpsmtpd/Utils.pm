package Qpsmtpd::Utils;
use strict;

use Net::IP;

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

sub is_valid_ip {
    my ($self, $ip) = @_;

    if (Net::IP::ip_is_ipv4($ip)) {
        return if $ip eq '0.0.0.0';
        return if $ip eq '255.255.255.255';
        return if $ip =~ /255/;
        return 1;
    };
    return 1 if Net::IP::ip_is_ipv6($ip);

    return;
}

1;
