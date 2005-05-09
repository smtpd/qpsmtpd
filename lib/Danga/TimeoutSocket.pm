# $Id: TimeoutSocket.pm,v 1.2 2005/02/02 20:44:35 msergeant Exp $

package Danga::TimeoutSocket;

use base 'Danga::Socket';
use fields qw(alive_time create_time);

our $last_cleanup = 0;

sub new {
    my Danga::TimeoutSocket $self = shift;
    my $sock = shift;
    $self = fields::new($self) unless ref($self);
    $self->SUPER::new($sock);

    my $now = time;
    $self->{alive_time} = $self->{create_time} = $now;

    if ($now - 15 > $last_cleanup) {
        $last_cleanup = $now;
        _do_cleanup($now);
    }

    return $self;
}

sub ticker {
    my Danga::TimeoutSocket $self = shift;
    
    my $now = time;
    
    if ($now - 15 > $last_cleanup) {
        $last_cleanup = $now;
        _do_cleanup($now);
    }
}

# overload these in a subclass
sub max_idle_time       { 0 }
sub max_connect_time    { 0 }

sub _do_cleanup {
    my $now = shift;
    my $sf = __PACKAGE__->get_sock_ref;

    my %max_age;  # classname -> max age (0 means forever)
    my %max_connect; # classname -> max connect time
    my @to_close;
    while (my $k = each %$sf) {
        my Danga::TimeoutSocket $v = $sf->{$k};
        my $ref = ref $v;
        next unless $v->isa('Danga::TimeoutSocket');
        unless (defined $max_age{$ref}) {
            $max_age{$ref}      = $ref->max_idle_time || 0;
            $max_connect{$ref}  = $ref->max_connect_time || 0;
        }
        if (my $t = $max_connect{$ref}) {
            if ($v->{create_time} < $now - $t) {
                push @to_close, $v;
                next;
            }
        }
        if (my $t = $max_age{$ref}) {
            if ($v->{alive_time} < $now - $t) {
                push @to_close, $v;
            }
        }
    }

    $_->close("Timeout") foreach @to_close;
}

1;
