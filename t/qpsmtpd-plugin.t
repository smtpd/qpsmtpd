use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';

use_ok('Qpsmtpd::Plugin');

__db();

done_testing();

sub __db {
    my $plugin = FakePlugin->new;
    my $db = $plugin->db( class => 'FakeDB', name => 'testfoo' );
    is( ref $db, 'FakeDB', 'Qpsmtpd::Plugin::db(): Returns DB object' );
    is( ref $plugin->{db}, 'FakeDB', 'DB object is cached' );
    is( $db->{name}, 'testfoo', 'accepts name argument' );
    delete $plugin->{db};
    $db = $plugin->db( class => 'FakeDB' );
    is( $db->{name}, 'testbar', 'name argument defaults to plugin name' );
}

package FakePlugin;
use parent 'Qpsmtpd::Plugin';
sub plugin_name { 'testbar' }

package FakeDB;
sub new {
    my $class = shift;
    return bless {@_}, $class;
}
