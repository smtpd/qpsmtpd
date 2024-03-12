package Qpsmtpd::Base;
use strict;

use Net::DNS;
use Net::IP;

sub new {
    return bless {}, shift;
}

sub tildeexp {
    my ($self, $path) = @_;
    $path =~ s{^~([^/]*)} {
        $1  ? (getpwnam($1))[7]
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

sub is_ipv6 {
    my ($self, $ip) = @_;
    return if !$ip;
    return Net::IP::ip_is_ipv6($ip);
}

sub get_resolver {
    my ($self, %args) = @_;
    return $self->{_resolver} if $self->{_resolver};
    my $timeout = 5;
    if (defined $args{timeout}) {
        $timeout = delete $args{timeout};
    }
    $self->{_resolver} = Net::DNS::Resolver->new(dnsrch => 0);
    $self->{_resolver}->tcp_timeout($timeout);
    $self->{_resolver}->udp_timeout($timeout);
    return $self->{_resolver};
}

sub resolve_a {
    my ($self, $name) = @_;
    my $q = $self->get_resolver->query($name, 'A') or return;
    return map { $_->address } grep { $_->type eq 'A' } $q->answer;
}

sub resolve_aaaa {
    my ($self, $name) = @_;
    my $q = $self->get_resolver->query($name, 'AAAA') or return;
    return map { $_->address } grep { $_->type eq 'AAAA' } $q->answer;
}

sub resolve_mx {
    my ($self, $name) = @_;
    my $q = $self->get_resolver->query($name, 'MX') or return;
    return map { $_->exchange } grep { $_->type eq 'MX' } $q->answer;
}

sub resolve_ns {
    my ($self, $name) = @_;
    my $q = $self->get_resolver->query($name, 'NS') or return;
    return map { $_->nsdname } grep { $_->type eq 'NS' } $q->answer;
}

sub resolve_ptr {
    my ($self, $name) = @_;
    my $q = $self->get_resolver->query($name, 'PTR') or return;
    return map { $_->ptrdname } grep { $_->type eq 'PTR' } $q->answer;
}

1;
