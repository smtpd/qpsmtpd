package Qpsmtpd::DB::Redis;
use strict;
use warnings;

use parent 'Qpsmtpd::DB';

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {}, $class;
    eval 'use Redis';
    die $@ if $@;
    $self->name( delete $args{name} ) if defined $args{name};
    $self->{redis_args} = {%args};
    $self->init_internal_db() or return;
    return $self;
}

sub redis_zero {
    # Internal redis db
    my ( $self ) = @_;
    my $redis = $self->{redis} ||= $self->new_redis;
    $redis->select(0);
    return $redis;
}

sub new_redis {
    my ( $self ) = @_;
    my $redis = $self->{redis} = MyRedis->new( %{ $self->{args} } );
    $redis->selected(0);
    return $redis;
}

sub init_internal_db {
    my ( $self ) = @_;
    my $redis = $self->redis_zero;
    return 1 if $redis->get('___smtpd_reserved___');
    # Don't try to init a redis db already populated by something else
    return 0 if $redis->dbsize;
    $redis->set( ___smtpd_reserved___ => 1 );
    return 1;
}

sub redis {
    my ( $self ) = @_;
    my $redis = $self->{redis} or die "redis(): redis was not initialized";
    $redis->select( $self->index );
    return $redis;
}

sub index {
    # Get index of database where the current plugin's data should be stored
    my ( $self ) = @_;
    return $self->{index} if $self->{index};
    my $redis   = $self->redis_zero;
    my %stores  = $self->redis_zero->hgetall('smtpd_stores');
    return $self->{index} = $stores{ $self->name } if $stores{ $self->name };
    my %rstores = reverse %stores;
    for my $index ( 1 .. 255 ) {
        $redis->select($index);

        # This index is earmarked for something else
        next if exists $rstores{$index};

        # This index is populated by something else
        next if $redis->dbsize;

        # We can populate this empty store
        $self->redis_zero->hset( 'smtpd_stores', $self->name => $index );
        return $self->{index} = $index;
    }
}

sub get {
    my ( $self, $key ) = @_;
    if ( ! $key ) {
        warn "No key provided, get() failed\n";
        return;
    }
    return $self->redis->get($key);
}

sub set {
    my ( $self, $key, $val ) = @_;
    if ( ! $key ) {
        warn "No key provided, set() failed\n";
        return;
    }
    return $self->redis->set( $key, $val );
}

sub get_keys {
    my ( $self ) = @_;
    return $self->redis->keys('*');
}

sub size {
    my ( $self ) = @_;
    return $self->redis->dbsize;
}

sub delete {
    my ( $self, $key ) = @_;
    if ( ! $key ) {
        warn "No key provided, delete() failed\n";
        return;
    }
    return $self->redis->del($key);
}

package MyRedis;
eval "use parent 'Redis'";

# With all the (necessary) redundant select() going on, let's track the
# currently selected db and avoid the round trip when select() is a noop

sub select {
    my $self  = shift;
    my ( $index ) = @_;
    return if $index == $self->selected;
    my $r = $self->SUPER::select(@_);
    $self->selected( $index );
    return $r;
}

sub selected {
    my ( $self, $index ) = @_;
    $self->{selected} = $index if defined $index;
    return $self->{selected} if defined $self->{selected};
    return -1;
}

1;
