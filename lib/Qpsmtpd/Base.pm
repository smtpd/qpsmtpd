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

# The name a DNS blocklist looks an address up by: 1.2.3.4 is 4.3.2.1, and
# an IPv6 address is its nibbles, reversed (RFC 5782 2.4)
sub dnsbl_name {
    my ($self, $ip) = @_;
    my $ip_obj = Net::IP->new($ip) or return;
    return $ip_obj->reverse_ip =~ s/\.(?:in-addr|ip6)\.arpa\.$//r;
}

# A blocklist lists a name with an A record in 127.0.0.0/8, and may give the
# reason in a TXT record (RFC 5782 2.1). Spamhaus answers a refused query
# with an error code: .252 for a mistyped zone, .254 for a public resolver,
# .255 for a query over its rate limit.
my %dnsbl_error = map { ("127.255.255.$_" => 1) } 252, 254, 255;

sub dnsbl_lookup {
    my ($self, $name) = @_;
    my $res = $self->get_resolver;

    my $packet = $res->query($name, 'A');
    if (!$packet) {
        my $err = $res->errorstring;
        return if $err eq 'NXDOMAIN' || $err eq 'NOERROR';
        return {error => "$name: $err"};
    }

    my @codes  = map { $_->address } grep { $_->type eq 'A' } $packet->answer;
    my @listed = grep { /^127\./ && !$dnsbl_error{$_} } @codes;
    return {error => "$name: refused (@codes)"} if !@listed;

    my $txt = $res->query($name, 'TXT');
    # A TXT record longer than 255 bytes arrives as several strings
    my @reason = $txt
      ? map { join '', $_->txtdata } grep { $_->type eq 'TXT' } $txt->answer
      : ();
    return {codes => \@listed, reason => join(' ', @reason)};
}

sub resolve_ptr {
    my ($self, $name) = @_;
    my $q = $self->get_resolver->query($name, 'PTR') or return;
    return map { $_->ptrdname } grep { $_->type eq 'PTR' } $q->answer;
}

1;
