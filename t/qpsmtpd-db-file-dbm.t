use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

use Test::Qpsmtpd;
use_ok('Qpsmtpd::DB::File::DBM');

my $db = Qpsmtpd::DB::File::DBM->new( name => 'testing', dir => 't/tmp' );
__new();
__get();
__mget();
__set();
__delete();
__get_keys();
__size();
__flush();
__qphome();
__candidate_dirs();
__validate_dir();
__dir();
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

sub __mget {
    $db->lock;
    $db->flush;
    $db->set( key1 => 'val1' );
    $db->set( key2 => 'val2' );
    is( join('|',$db->mget(qw( key2 key1 ))), 'val2|val1',
        'mget() retrieves multiple keys' );
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
    $db->set( woof  => 1 );
    $db->set( moo   => 1 );
    is( $db->delete('quack'), 1,
        'delete() return value when removing a single key' );
    is( join( '|', sort $db->get_keys ), 'moo|oink|woof',
        'delete() removes a single key' );
    is( $db->delete(qw( moo oink )), 2,
        'delete() return value when removing a single key' );
    is( join( '|', sort $db->get_keys ), 'woof',
        'delete() removes two keys' );
    is( $db->delete('noop'), 0,
        'delete() return value when removing a non-existent key' );
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

sub __qphome {
    is( $db->qphome, 't', 'qphome()' );
}

sub __candidate_dirs {
    is( join('|', $db->candidate_dirs), 't/var/db|t/config',
      'candidate_dirs() default ' );
    is( join('|', $db->candidate_dirs('foo')), 'foo|t/var/db|t/config',
      'candidate_dirs() passed args plus defaults' );
    is( join('|', $db->candidate_dirs), 'foo|t/var/db|t/config',
      'candidate_dirs() cached values' );
}

sub __validate_dir {
    is( $db->validate_dir(),      0, 'validate_dir(): false on no input' );
    is( $db->validate_dir(undef), 0, 'validate_dir(): false on undef' );
    is( $db->validate_dir('invalid'), 0,
        'validate_dir(): false for non-existent directory' );
    is( $db->validate_dir('t/tmp'), 1,
        'validate_dir(): true for real directory' );
    mkdir 't/tmp/wtest', 0555;
    is( $db->validate_dir('t/tmp/wtest'), 0,
        'validate_dir(): false for non-writeable directory' );
    chmod 0777, 't/tmp/wtest';
    is( $db->validate_dir('t/tmp/wtest'), 1,
        'validate_dir(): true for writeable directory' );
    rmdir 't/tmp/wtest';
}

sub __dir {
    my $db2 = Qpsmtpd::DB::File::DBM->new( name => 'dirtest' );
    is( $db2->dir(), 't/config', 'default directory' );
    is( $db2->dir('_invalid','t/Test'), 't/Test', 'skip invalid candidate dirs' );
    $db2->{dir} = '_cached';
    is( $db2->dir(), '_cached', 'cached directory' );
    is( $db2->dir('t/Test'), 't/Test', 'passing candidate dirs resets cache' );
    is( $db2->dir('_invalid'), 't/config', 'invalid candidate dirs reverts to default' );
}

sub __untie_gotcha {
    # Regression test for 'gotcha' with untying hash that never goes away
    $db->lock;
    $db->flush;
    $db->set( cut => 'itout' );
    $db->unlock;
    my $db2 = Qpsmtpd::DB::File::DBM->new( name => 'testing', dir => 't/tmp' );
    $db2->lock;
    is( $db2->get('cut'), 'itout',
        'get() in second db handle reads key set in first handle' );
    # Get rid of test data
    $db2->flush;
    $db2->unlock;
    $db->lock;
    $db->flush;
    $db->unlock;
}
