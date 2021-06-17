use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

use_ok('Qpsmtpd::DB::Redis');

my $db;
eval 'use Redis; Redis->new';
if ( $@ ) {
    warn "Could not connect to redis to test; using mock redis";
    $db = bless { name => 'testing', redis => FakeRedis->new }, 'Qpsmtpd::DB::Redis';
}
else {
    Redis->new->flushall;
    $db = Qpsmtpd::DB::Redis->new( name => 'testing' );

    __new();

}

__index();
__redis();
__get();
__mget();
__set();
__delete();
__get_keys();
__size();
__flush();

done_testing();

sub __new {
    is( ref $db->{redis}, 'MyRedis', 'Redis object populated' );
    my $redis = $db->{redis};
    $redis->select(0);
    is( $redis->get('___smtpd_reserved___'), 1, 'DB properly initialized' );
    is( join( '|', $redis->keys('*') ), '___smtpd_reserved___',
        'Nothing else has happened to DB yet' );
}

sub __redis {
    $db->{redis}->flushall;
    $db->{redis}->select(0);
    delete $db->{index};
    my $redis = $db->redis;
    is( $redis->selected, 1, 'redis() selects the correct index' );
}

sub __index {
    my $redis = $db->{redis};
    $redis->flushall;
    is( stores($db),  '',          'stores unpopulated initially' );
    is( $db->{index}, undef,       'index cache unpopulated initially' );
    is( $db->index,   1,           'get first index given an empty db' );
    is( stores($db), 'testing=1',  'stores populated correctly for index=1' );
    is( $db->{index}, 1,           'index is cached' );
    $db->{index} = 999;
    is( $db->index,   999,         'index cache is honored' );
    delete $db->{index};
    $redis->flushall;
    $redis->select(0);
    $redis->hset( 'smtpd_stores', testing => 99 );
    is( $db->index,   99,          'redis zero table is honored' );
    delete $db->{index};
    $redis->flushall;
    $redis->select(1);
    $redis->set( bugus => 1 );
    is( $db->index,   2,           'index() skips already-populated db' );
    is( stores($db),  'testing=2', 'stores populated correclty for index=2' );
    delete $db->{index};
    $redis->flushall;
    $redis->select(0);
    $redis->hset( 'smtpd_stores', foo => 1 );
    $redis->hset( 'smtpd_stores', bar => 2 );
    is( $db->index,   3,           'index() skips already-earmarked db' );
}

sub stores {
    my $redis = $db->{redis};
    $redis->select(0);
    my %store = $redis->hgetall('smtpd_stores');
    return join ';', map { "$_=$store{$_}" } keys %store;
}

sub __get {
    my $redis = $db->redis;
    $redis->flushdb;
    $redis->set( moo => 'oooo' );
    is( $db->get('moo'), 'oooo', 'get() retrieves key' );
}

sub __mget {
    my $redis = $db->redis;
    $redis->flushdb;
    $redis->set( key1 => 'val1' );
    $redis->set( key2 => 'val2' );
    is( join('|',$db->mget(qw( key2 key1 ))), 'val2|val1',
        'mget() retrieves multiple keys' );
}

sub __set {
    my $redis = $db->redis;
    $redis->flushdb;
    $db->set( mee => 'ow' );
    is( $redis->get('mee'), 'ow', 'set() stores key' );
}

sub __delete {
    my $redis = $db->redis;
    $redis->flushdb;
    $redis->set( oink  => 1 );
    $redis->set( quack => 1 );
    $redis->set( woof  => 1 );
    $redis->set( moo   => 1 );

    is( $db->delete('quack'), 1,
        'delete() return value when removing a single key' );
    is( join( '|', sort $redis->keys('*') ), 'moo|oink|woof',
        'delete() removes a single key' );
    is( $db->delete(qw( moo oink )), 2,
        'delete() return value when removing a single key' );
    is( join( '|', sort $redis->keys('*') ), 'woof',
        'delete() removes two keys' );
    is( $db->delete('noop'), 0,
        'delete() return value when removing a non-existent key' );
}

sub __get_keys {
    my $redis = $db->redis;
    $redis->flushdb;
    $redis->set( asdf   => 1 );
    $redis->set( qwerty => 1 );
    is( join( '|', sort $db->get_keys ), 'asdf|qwerty',
        'get_keys() lists all keys in the db' );
}

sub __size {
    my $redis = $db->redis;
    $redis->flushdb;
    $redis->set( baz  => 1 );
    $redis->set( blah => 1 );
    is( $db->size, 2, 'size() shows key count for db' );
}

sub __flush {
    $db->redis->flushall;
    my $redis = $db->redis;
    $redis->flushdb;
    $redis->set( bogus => 1 );
    is( join( '|', $redis->keys('*') ), 'bogus', 'redis db populated' );
    $db->flush;
    is( join( '|', $redis->keys('*') ), '', 'flush() empties db' );
}

package FakeRedis;
sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub flushall { delete $_[0]->{fakestore} }
sub selected { $_[0]->{selected}         }
sub select   { $_[0]->{selected} = $_[1] }
sub dbsize   { scalar keys %{ $_[0]->fakestore }   }
sub get      { $_[0]->fakestore->{ $_[1] }         }
sub set      { $_[0]->fakestore->{ $_[1] } = $_[2] }

sub del {
    my ($self,@keys) = @_;
    my $f = $self->fakestore;
    @keys = grep { exists $f->{$_} } @keys;
    delete @$f{ @keys };
    return scalar @keys;
}

sub mget {
    my ($self,@keys) = @_;
    my $f = $self->fakestore;
    return @$f{ @keys };
}

sub hgetall  {
    my ( $self, $h ) = @_;
    return %{ $self->fakestore->{ $h } || {} };
}

sub hset {
    my ( $self, $h, $key, $value ) = @_;
    $self->fakestore->{ $h }{ $key } = $value;
}

sub keys {
    my ( $self, $pattern ) = @_;
    die "invalid pattern '$pattern': Mock Redis only understands '*'"
        if $pattern ne '*';
    return keys %{ $self->fakestore };
}

sub flushdb {
    my ( $self ) = @_;
    delete $self->{fakestore}{ $self->selected };
}

sub fakestore {
    my ( $self ) = @_;
    return $self->{fakestore}{ $self->selected } ||= {};
}

