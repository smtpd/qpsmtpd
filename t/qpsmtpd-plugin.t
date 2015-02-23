use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';
use Test::Qpsmtpd;

use_ok('Qpsmtpd::Plugin');

__validate_db_args();
__db_args();
__db();
__register_hook();

done_testing();

sub __validate_db_args {
    my $plugin = FakePlugin->new;
    eval { $plugin->validate_db_args($plugin, testkey => 1) };
    is( $@, '', 'validate_db_args() does not die on valid data' );
    eval { $plugin->validate_db_args($plugin, 'bogus') };
    is( $@, "Invalid db arguments\n", 'validate_db_args() dies on invalid data' );
}

sub __db_args {
    my $plugin = FakePlugin->new;
    is( keyvals($plugin->db_args),
      'cnx_timeout=1;name=___MockHook___',
      'default db args populated' );
    is( keyvals($plugin->db_args( arg1 => 1 )),
      'arg1=1;cnx_timeout=1;name=___MockHook___',
      'passed args in addition to defaults' );
    is( keyvals($plugin->db_args( name => 'bob', arg2 => 2 )),
      'arg2=2;cnx_timeout=1;name=bob',
      'passed args override defaults' );
    is( keyvals($plugin->db_args),
      'arg2=2;cnx_timeout=1;name=bob',
      'get previous args' );
}

sub keyvals {
    my ( %h ) = @_;
    return join ";", map { "$_=$h{$_}" } sort keys %h;
}

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
