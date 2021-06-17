package Test::Qpsmtpd;
use strict;

use Carp qw(croak);
use Test::More;

use lib 't';
use lib 'lib';
use parent 'Qpsmtpd::SMTP';

use Qpsmtpd::Constants;
use Test::Qpsmtpd::Plugin;

if ( ! -d 't/tmp' ) {
    mkdir 't/tmp' or warn "Could not create temporary testing directory:$!";
}

sub new_conn {
    ok(my $smtpd = __PACKAGE__->new(), "new");
    ok(
        my $conn =
          $smtpd->start_connection(
                                   remote_host => 'localhost',
                                   remote_ip   => '127.0.0.1'
                                  ),
        "start_connection"
      );
    is(($smtpd->response)[0], "220", "greetings");
    ($smtpd, $conn);
}

sub start_connection {
    my $self = shift;
    my %args = @_;

    my $remote_host = $args{remote_host} or croak "no remote_host parameter";
    my $remote_info = "test\@$remote_host";
    my $remote_ip   = $args{remote_ip} or croak "no remote_ip parameter";

    my $conn =
      $self->SUPER::connection->start(
                                      remote_info => $remote_info,
                                      remote_ip   => $remote_ip,
                                      remote_host => $remote_host,
                                      @_
                                     );

    $self->load_plugins;

    my $rc = $self->start_conversation;
    return if $rc != DONE;

    $conn;
}

sub respond {
    my $self = shift;
    $self->{_response} = [@_];
}

sub response {
    my $self = shift;
    $self->{_response} ? (@{delete $self->{_response}}) : ();
}

sub command {
    my ($self, $command) = @_;
    $self->input($command);
    $self->response;
}

sub input {
    my ($self, $command) = @_;

    my $timeout = $self->config('timeout');
    alarm $timeout;

    $command =~ s/\r?\n$//s;    # advanced chomp
    $self->log(LOGDEBUG, "dispatching $command");
    if (!defined $self->dispatch(split / +/, $command, 2)) {
        $self->respond(502, "command unrecognized: '$command'");
    }
    alarm $timeout;
}

sub config_dir {
    return './t/config' if $ENV{QPSMTPD_DEVELOPER};
    return './config.sample';
}

sub plugin_dirs {
    ('./plugins', './plugins/ident');
}

sub log {
    my ($self, $trace, $hook, $plugin, @log) = @_;
    my $level = Qpsmtpd::TRACE_LEVEL() || 5;
    $level = $self->init_logger if !defined $level;
    return if $trace > $level;
    print("# " . join(' ', $$, @log) . "\n");
    ( undef, undef, my @record_args ) = @_;
    push @{ $self->{_logged} }, log_level($trace) . ":"
      . join '', grep { defined } @record_args;
}

sub varlog {
    shift->log(@_);
}

# sub run
# sub disconnect

sub run_plugin_tests {
    my ($self, $only_plugin) = @_;
    $self->{_test_mode} = 1;
    my @plugins = $self->load_plugins();

    require Test::Builder;
    my $Test = Test::Builder->new();

    foreach my $plugin (@plugins) {
        next if ($only_plugin && $plugin !~ /$only_plugin/);
        $plugin->register_tests();
        $plugin->run_tests($self);
    }
    $Test->done_testing();
}

sub mock_hook {
    ###########################################################################
    # Inserts a given subroutine into the beginning of the set of hooks already
    # in place. Used to test code against different potential plugins it will
    # interact with. For example, to test behavior against various results of
    # the data_post hook:
    #
    # $self->mock_hook('data_post',sub { return DECLINED };
    # ok(...);
    # $self->mock_hook('data_post',sub { return DENYSOFT };
    # ok(...);
    # $self->mock_hook('data_post',sub { return DENY };
    # ok(...);
    # $self->mock_hook('data_post',sub { return DENY_DISCONNECT };
    # ok(...);
    # $self->unmock_hook('data_post');
    ###########################################################################
    my ( $self, $hook, $sub ) = @_;
    unshift @{ $self->hooks->{$hook} ||= [] },
        {
            name => '___MockHook___',
            code => $sub,
        };
}

sub unmock_hook {
    my ( $self, $hook ) = @_;
    $self->hooks->{$hook} = [
        grep { $_->{name} ne '___MockHook___' }
        @{ $self->hooks->{$hook} || [] }
    ];
}

sub mock_config {
    ####################################################################
    # Used to test code against various possible configurations
    # For example, to test against various possible config('me') values:
    #
    # $self->mock_config( me => '***invalid***' );
    # ok(...);
    # $self->mock_config( me => 'valid-nonfqdn' );
    # ok(...);
    # $self->mock_config( me => 'valid-fqdn.com');
    # ok(...);
    # $self->unmock_config();
    ####################################################################
    my $self = shift;
    my $mock_config = {@_};
    $self->mock_hook( 'config',
        sub {
            my ( $self, $txn, $conf ) = @_;
            return DECLINED if ! exists $mock_config->{$conf};
            return OK, $mock_config->{$conf};
    } );
}

sub unmock_config {
    my ( $self ) = @_;
    $self->unmock_hook('config');
}

1;
