use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

use_ok('Qpsmtpd::DB');
use_ok('Qpsmtpd');

__new();
__lock();
__unlock();
__name();

done_testing();

sub __new {
    @Qpsmtpd::DB::child_classes = qw(
        BrokenClassOne
        BrokenClassTwo
    );
    my $db;
    eval { $db = Qpsmtpd::DB->new };
    is( $@, "Couldn't load any storage modules\n"
          . "Couldn't load BrokenClassOne: fool me once, shame on me\n\n"
          . "Couldn't load BrokenClassTwo: fool me can't get fooled again\n",
        'Detect failure to load all child DB classes' );
    eval { $db = Qpsmtpd::DB->new( class => 'BrokenClassOne' ) };
    is( $@, "Couldn't load any storage modules\n"
          . "Couldn't load BrokenClassOne: fool me once, shame on me\n",
        'Failure to load manual class' );
    @Qpsmtpd::DB::child_classes = qw( EmptyClass );
    eval { $db = Qpsmtpd::DB->new };
    is( ref $db, 'EmptyClass',
        'Load object with manual (bogus) class: Qpsmtpd object is returned' );
}

sub __lock {
    @Qpsmtpd::DB::child_classes = qw( EmptyClass );
    is( Qpsmtpd::DB->new->lock, 1, 'Default lock() method just returns true' );
}

sub __unlock {
    @Qpsmtpd::DB::child_classes = qw( EmptyClass );
    is( Qpsmtpd::DB->new->unlock, 1, 'Default lock() method just returns true' );
}

sub __name {
    @Qpsmtpd::DB::child_classes = qw( EmptyClass );
    my $db = Qpsmtpd::DB->new;
    is( $db->name,          undef, 'no name set yet' );
    is( $db->name('test'), 'test', 'set name' );
    is( $db->name,         'test', 'get name' );
}

package BrokenClassOne;
sub new { die "fool me once, shame on me\n" }

package BrokenClassTwo;
sub new { die "fool me can't get fooled again\n" }

package EmptyClass;
use parent 'Qpsmtpd::DB';
sub new {
    my $class = shift;
    return bless {@_}, $class;
}
