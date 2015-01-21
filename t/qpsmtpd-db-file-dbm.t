use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

use_ok('Qpsmtpd::DB::File::DBM');

my $db = Qpsmtpd::DB::File::DBM->new( name => 'testing' );
__new();
__get();
__set();
__delete();
__get_keys();
__size();
__flush();
__untie_gotcha();

done_testing();

sub __new {
    is( ref $db, 'Qpsmtpd::DB::File::DBM', 'Qpsmtpd::DB::File::DBM object created' );
}

sub __get {
    $db->lock;
    $db->flush;
    $db->set( moo => 'oooo' );
    is( $db->get('moo'), 'oooo', 'get() retrieves key' );
    $db->unlock;
}

sub __set {
    $db->lock;
    $db->flush;
    $db->set( mee => 'ow' );
    is( $db->get('mee'), 'ow', 'set() stores key' );
    $db->unlock;
}

sub __delete {
    $db->lock;
    $db->flush;
    $db->set( oink  => 1 );
    $db->set( quack => 1 );
    $db->delete('quack');
    is( join( '|', $db->get_keys ), 'oink', 'delete() removes key' );
    $db->unlock;
}

sub __get_keys {
    $db->lock;
    $db->flush;
    $db->set( asdf   => 1 );
    $db->set( qwerty => 1 );
    is( join( '|', sort $db->get_keys ), 'asdf|qwerty',
        'get_keys() lists all keys in the db' );
    $db->unlock;
}

sub __size {
    $db->lock;
    $db->flush;
    $db->set( baz  => 1 );
    $db->set( blah => 1 );
    is( $db->size, 2, 'size() shows key count for db' );
    $db->unlock;
}

sub __flush {
    $db->lock;
    $db->flush;
    $db->set( bogus => 1 );
    is( join( '|', $db->get_keys ), 'bogus', 'DBM db populated' );
    $db->flush;
    is( join( '|', $db->get_keys ), '', 'flush() empties db' );
    $db->unlock;
}

sub __untie_gotcha {
    # Regression test for 'gotcha' with untying hash that never goes away
    $db->lock;
    $db->flush;
    $db->set( cut => 'itout' );
    $db->unlock;
    my $db2 = Qpsmtpd::DB::File::DBM->new( name => 'testing' );
    $db2->lock;
    is( $db2->get('cut'), 'itout',
        'get() in second db handle reads key set in first handle' );
    $db2->unlock;
    $db->flush;
    $db2->flush;
}
