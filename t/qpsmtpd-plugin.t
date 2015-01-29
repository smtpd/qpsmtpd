use strict;
use warnings;

use Test::More;

use lib 'lib';    # test lib/Qpsmtpd (vs site_perl)
use lib 't';
use Test::Qpsmtpd;
use Qpsmtpd::Constants;

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
    is( $db->{name}, '___FakeHook___', 'db name defaults to plugin name' );
}

sub __register_hook {
    eval {
        my $plugin = FakePlugin->new;
        $plugin->register_hook('bogus_hook');
    };
    ok( $@ =~ /^___FakeHook___: Invalid hook: bogus_hook/,
      'register_hook() validates hook name' );
    my $qp = Test::Qpsmtpd->new;
    my $plugin = FakePlugin->new;
    $plugin->{_qp} = $qp;
    $plugin->register_hook('logging', sub { shift; return "arguments:@_" });
    ok( my $registered = $qp->hooks->{logging}->[-1] );
    is( $registered->{name}, '___FakeHook___',
      'register_hook() sets plugin name' );
    my $code = $registered->{code};
    is( ref $code, 'CODE', 'register_hook() sets a coderef' );
    is( join('',$code->(undef,qw[arg1 arg2])), 'arguments:arg1 arg2',
      'register_hook(): coderef set correctly' );
    $plugin->register_hook('logging', sub { die "WUT\n" });
    ok( $registered = $qp->hooks->{logging}->[-1] );
    eval { $registered->{code}->(); };
    is( $@, "WUT\n", 'Non-error-handling plugin dies' );
    my $error_handling_plugin = FakePluginWithErrorHandling->new;
    $error_handling_plugin->{_qp} = $qp;
    $error_handling_plugin->register_hook('logging', sub { die "NO\n" });
    ok( $registered = $qp->hooks->{logging}->[-1] );
    my @r;
    eval { @r = $registered->{code}->(); };
    ok( !$@, 'error-handling plugin does not die' );
    $r[0] = return_code($r[0]);
    is( join( '', @{ $error_handling_plugin->{___logged} || [] } ),
      "LOGERROR:PLUGIN ERROR [___FakeHook___ hook_logging]: NO\n",
      'plugin error handler logs the error' );
    is( join( '|', @r ), "DENYSOFT|hook_logging crashed with this error: NO\n",
      'plugin error handler returns expected values' );
    $qp->unfake_hook('logging');
}

package FakePlugin;
use parent 'Qpsmtpd::Plugin';
sub plugin_name { '___FakeHook___' }

package FakePluginWithErrorHandling;
use Qpsmtpd::Constants;
use parent 'Qpsmtpd::Plugin';
sub plugin_name { '___FakeHook___' }
sub error_handler {
    ( undef, my $err, my $hook ) = @_;
    return DENYSOFT, "hook_$hook crashed with this error: $err";
}
sub log {
    my $self = shift;
    my $level = log_level(shift);
    push @{ $self->{___logged} }, "$level:" . join "\n", @_;
}

package FakeDB;
sub new {
    my $class = shift;
    return bless {@_}, $class;
}
