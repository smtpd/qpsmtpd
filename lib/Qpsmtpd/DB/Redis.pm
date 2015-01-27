package Qpsmtpd::DB::Redis;
use strict;
use warnings;

use parent 'Qpsmtpd::DB';

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {}, $class;
    $self->name( delete $args{name} ) if defined $args{name};
    $self->{redis_args} = {%args};
    $self->init_db();
    return $self;
}

sub init_redis {
    my ( $self ) = @_;
    # Stringy eval needed to allow 'use Qpmstpd::DB::Redis' to succeed
    # even when Redis module is unavailable; mainly for testing
    eval 'use Redis';
    die $@ if $@;
    my $redis = $self->{redis} = MyRedis->new( %{ $self->{redis_args} } );
    $redis->selected(0);
    return $redis;
}

sub init_db {
    my ( $self ) = @_;
    my $redis = $self->init_redis;
    return if $redis->get('___smtpd_reserved___');
    die "Redis DB at index 0 is already populated!" if $redis->dbsize;
    $redis->set( ___smtpd_reserved___ => 1 );
}

sub redis {
    my ( $self, $index ) = @_;
    my $redis = $self->{redis} or die "redis(): redis was not initialized";
    $index = $self->index if ! defined $index;
    $redis->select( $index );
    return $redis;
}

sub index {
    # Get index of database where the current plugin's data should be stored
    my ( $self ) = @_;
    return $self->{index} if $self->{index};
    my $redis   = $self->redis(0);
    my %stores  = $redis->hgetall('smtpd_stores');
    return $self->{index} = $stores{ $self->name } if $stores{ $self->name };
    my %rstores = reverse %stores;
    for my $index ( 1 .. 255 ) {
        $redis->select($index);

        # This index is earmarked for something else
        next if exists $rstores{$index};

        # This index is populated by something else
        next if $redis->dbsize;

        # We can populate this empty store
        $self->redis(0)->hset( 'smtpd_stores', $self->name => $index );
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

sub mget {
    my ( $self, @keys ) = @_;
    if ( ! @keys ) {
        warn "No key provided, mget() failed\n";
        return;
    }
    return $self->redis->mget(@keys);
}

sub set {
    my ( $self, $key, $val ) = @_;
    if ( ! $key ) {
        warn "No key provided, set() failed\n";
        return;
    }
    return $self->redis->set( $key, $val );
}

sub delete {
    my ( $self, @keys ) = @_;
    if ( ! @keys ) {
        warn "No key provided, delete() failed\n";
        return;
    }
    return $self->redis->del(@keys);
}

sub get_keys { shift->redis->keys('*') }
sub size     { shift->redis->dbsize    }
sub flush    { shift->redis->flushdb   }

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
