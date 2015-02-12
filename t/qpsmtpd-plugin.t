use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';
use Test::Qpsmtpd;

use_ok('Qpsmtpd::Plugin');

__db();
__register_hook();

done_testing();

sub __db {
    my $plugin = FakePlugin->new;
    my $db = $plugin->db( class => 'FakeDB', name => 'testfoo' );
    is( ref $db, 'FakeDB', 'Qpsmtpd::Plugin::db(): Returns DB object' );
    is( ref $plugin->{db}, 'FakeDB', 'DB object is cached' );
    is( $db->{name}, 'testfoo', 'accepts name argument' );
    delete $plugin->{db};
    $db = $plugin->db( class => 'FakeDB' );
    is( $db->{name}, '___MockHook___', 'db name defaults to plugin name' );
}

sub __register_hook {
    eval {
        my $plugin = FakePlugin->new;
        $plugin->register_hook('bogus_hook');
    };
    ok( $@ =~ /^___MockHook___: Invalid hook: bogus_hook/,
      'register_hook() validates hook name' );
    my $qp = Test::Qpsmtpd->new;
    my $plugin = FakePlugin->new;
    $plugin->{_qp} = $qp;
    $plugin->register_hook('logging', sub { shift; return "arguments:@_" });
    ok( my $registered = $qp->hooks->{logging}->[-1] );
    is( $registered->{name}, '___MockHook___',
      'register_hook() sets plugin name' );
    my $code = $registered->{code};
    is( ref $code, 'CODE', 'register_hook() sets a coderef' );
    is( join('',$code->(undef,qw[arg1 arg2])), 'arguments:arg1 arg2',
      'register_hook(): coderef set correctly' );
    $qp->unmock_hook('logging');
}

package FakePlugin;
use parent 'Qpsmtpd::Plugin';
sub plugin_name { '___MockHook___' }

package FakeDB;
sub new {
    my $class = shift;
    return bless {@_}, $class;
}
