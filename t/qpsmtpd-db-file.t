use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

use_ok('Qpsmtpd::DB::File');

__qphome();
__validate_dir();
__dir();

done_testing();

sub __qphome {
    my $db = FakeDB->new;
    is( $db->qphome, 't', 'qphome()' );
}

sub __validate_dir {
    my $db = FakeDB->new;
    is( $db->validate_dir(),      0, 'validate_dir(): false on no input' );
    is( $db->validate_dir(undef), 0, 'validate_dir(): false on undef' );
    is( $db->validate_dir('invalid'), 0,
        'validate_dir(): false for non-existent directory' );
    is( $db->validate_dir('t/config'), 1,
        'validate_dir(): true for real directory' );
}

sub __dir {
    my $db = FakeDB->new;
    is( $db->dir(), 't/config', 'default directory' );
    is( $db->dir('_invalid','t/Test'), 't/Test', 'skip invalid candidate dirs' );
    $db->{dir} = '_cached';
    is( $db->dir(), '_cached', 'cached directory' );
    is( $db->dir('t/Test'), 't/Test', 'passing candidate dirs resets cache' );
    is( $db->dir('_invalid'), 't/config', 'invalid candidate dirs reverts to default' );
}

package FakeDB;
use parent 'Qpsmtpd::DB::File';
sub new {
    my $class = shift;
    return bless {@_}, $class;
}
