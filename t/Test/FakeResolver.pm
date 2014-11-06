package Test::FakeResolver;
use strict;
use warnings;
use base 'Net::DNS::Resolver';
use Net::IP;

sub new {
    my ( $class, %args ) = @_;
    my $static_data = delete $args{static_data};
    my $static_file = delete $args{static_file};

    my $self = $class->SUPER::new( %args );

    my $package = __PACKAGE__;

    if ( $static_file ) {
        open my $F, '<', $static_file
            or die "$package: FATAL: Unable to open '$static_file': $!\n";
        local $/;
        my $data = <$F>;
        close $F;
        eval { $self->_populate_static_cache($data) };
        if ( $@ ) {
            die "$package: FATAL: Error reading '$static_file': $@";
        }
    }
    if ( $static_data ) {
        eval { $self->_populate_static_cache($static_data) };
        if ( $@ ) {
            die "$package: FATAL: $@";
        }
    }
    if ( ! $self->{static_dns} ) {
        die "$package: FATAL: No static cache provided";
    }
    return $self;
}

sub _populate_static_cache {
    my ( $self, $data ) = @_;
    my $line_num = 0;
    for my $line (split /\n/,$data) {
        $line_num++;
        $line =~ s/;.*//;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if $line =~ /^$/;
        my ( $host, $class, $type, $value )
            = $line =~ /^\s*([\/_a-z\.0-9-]+)\s+(?:\d+\s+)?([A-Z]+)\s+([A-Z]+)\b\s*([^\s].*)?/;
        if ( ! $host ) {
            die "Cache syntax error, $line_num: $line\n";
        }
        $line = $value if defined $value and $value =~ /^error\s/;
        if ( $host !~ /\.$/ ) {
            $host .= '.';
        }
        push @{ $self->{static_dns}{"$host $class $type"} ||= [] }, ( $value ? $line : undef );
    }
}

sub send {
    my ( $self, $host, $type, $class ) = @_;
    $class ||= 'IN';
    if ( ! $type ) {
        if ( Net::IP::ip_is_ipv4($host) ) {
            $type = 'PTR';
            $host = Net::IP::ip_reverse($host,32,4);
            # Starting with Net::IP 1.26, ip_reverse trims leading 0s from the result
            # but we want to add them back on
            my $zeros = () = $host =~ /\./g;
            $host = '0.' x (6-$zeros) . $host;
        } elsif ( Net::IP::ip_is_ipv6($host) ) {
            $type = 'PTR';
            $host = Net::IP::ip_reverse($host,128,6);
        } else {
            $type = 'A';
        }
    }
    if ( $host !~ /\.$/ ) {
        $host .= '.';
    }

    my $cached_record;
    if ( exists $self->{static_dns}{"$host $class $type"} ) {
        # If we have an exact match, use it
        $cached_record = $self->{static_dns}{"$host $class $type"};
    } elsif ( exists $self->{static_dns}{"$host $class CNAME"} ) {
        # If there's no exact match, look for a CNAME match
        $cached_record = $self->{static_dns}{"$host $class CNAME"};
    } else {
        # Finally, issue an error and die
        $self->_cache_miss($host,$class,$type);
    }
    if ( defined $cached_record->[0] and $cached_record->[0] =~ /^error\s+"(.*)"$/ ) {
        $self->{errorstring} = $1;
        return;
    }
    my $packet = Net::DNS::Packet->new($host,$type,$class);
    if ( defined $cached_record ) {
        $packet->push( answer =>
            map { Net::DNS::RR->new( $_ ) }
            grep { $_ }
            @$cached_record );
    }
    for my $rr ( $packet->answer ) {
        if ( $rr->type eq 'CNAME' ) {
            my $subpacket = $self->send($rr->cname,$type,$class);
            for my $subrr ( $subpacket->answer ) {
                $packet->push( answer => $subrr );
            }
        }
    }
    return $packet;
}

sub _cache_miss {
    my ( $self, $host, $class, $type ) = @_;
    my $package = __PACKAGE__;
    warn <<EOF;
!!!! $package !!!!
No cached answer available for '$host $class $type'
EOF
    die "Dying\n";  # Net::DNS::Async captures $@, so we don't see the 'die' output
                    # in some caess, so we display all the useful info in the warning
                    # instead
}

1;
