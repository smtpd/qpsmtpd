package Test::FakeResolver;
use strict;
use warnings;
use base 'Net::DNS::Resolver';
use Net::IP;
use Socket;
use Storable qw(freeze thaw);

our ($file,%_dns);
sub import {
    my $class = shift;
    $file = shift;
    die "Must provide path!  i.e.: use Test::FakeResolver '/tmp/file.txt'\n" unless $file;
    open my $FH, $file or die "Unable to open '$file': $!\n";
    my $line;
    while (local $_ = <$FH>) {
        $line++;
        s/;.*//;
        s/^\s+//;
        s/\s+$//;
        next if /^$/;
        my ( $host, $type, $value )
            = /^\s*([\/_a-z\.0-9-]+)\s+(?:\d+\s+)?IN\s+([A-Z]+)\b\s*([^\s].*)?/;
        if ( $host ) {
            $_ = $value if defined $value and $value =~ /^error\s/;
            if ( ! $host =~ /\.$/ ) {
                $host .= '.';
            }
            push @{ $_dns{"$host $type"} ||= [] }, ( $value ? $_ : undef );
        } else {
            die "Error in '$file', line $line:\n\t>> $_\n";
        }
    }
    unless ( $ENV{FAKERESOLVER_APPEND} ) {
        unlink "/tmp/FakeResolver.log";
    }
    $class->SUPER::import;
}

sub send {
    my ( $self, $host, $type ) = @_;
    if ( ! $type ) {
        if ( Net::IP::ip_is_ipv4($host) or Net::IP::ip_is_ipv6($host) ) {
            $type = 'PTR';
            $host = Net::IP::ip_reverse($host);
        } else {
            $type = 'A';
        }
    }
    if ( $host !~ /\.$/ ) {
        $host .= '.';
    }
    if ( ! exists $Test::FakeResolver::_dns{"$host $type"} ) {
        if ( $type eq 'CNAME' or ! exists $Test::FakeResolver::_dns{"$host CNAME"} ) {
            open my $L, ">> /tmp/FakeResolver.log";
            print $L "$host. $type\n";
            warn "\n *\n *\n * No answer available for '$host $type' !!!\n"
                . " * Please add the output of the following command to $Test::FakeResolver::file:\n"
                . " *\tdump_dns_lookup.pl $host $type\n *   -or-\n"
                . " *\tdump_dns_lookup.pl < /tmp/FakeResolver.log\n *\n *\n";
            die "Dying\n"; # Net::DNS::Async captures $@, so we don't see the 'die' output
                           # in some caess, so we display all the useful info in the warning
                           # instead
        }
        $type = 'CNAME';
    }
    my $cache = $Test::FakeResolver::_dns{"$host $type"};
    if ( defined $cache->[0] and $cache->[0] =~ /^error\s+"(.*)"$/ ) {
        $self->{errorstring} = $1;
        return;
    }
    my $answer = Net::DNS::Packet->new($host,$type);
    $answer->push( answer => map { Net::DNS::RR->new( $_ ) }
                    grep { $_ }
                    @$cache )
        if defined $cache;
    return $answer;
}

sub bgsend {
    my $answer = shift->send( @_ ) or return;
    socketpair(my $in, my $out, AF_UNIX, SOCK_STREAM, PF_UNSPEC )
        or return;
    print $in freeze($answer);
    close $in;
    return $out;
}

sub bgread {
    my ( $self, $socket ) = @_;
    my $answer;
    my $buf;
    while ( read($socket,$buf,1024) ) {
        $answer .= $buf;
    }
    return thaw($answer);
}

1;
