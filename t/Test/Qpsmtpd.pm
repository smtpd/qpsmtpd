package Test::Qpsmtpd;
use strict;
use lib 't';
use lib 'lib';
use Carp qw(croak);
use base qw(Qpsmtpd::SMTP);
use Test::More;
use Qpsmtpd::Constants;
use Test::Qpsmtpd::Plugin;

sub new_conn {
  ok(my $smtpd = __PACKAGE__->new(), "new");
  ok(my $conn  = $smtpd->start_connection(remote_host => 'localhost',
                                          remote_ip => '127.0.0.1'), "start_connection");
  is(($smtpd->response)[0], "220", "greetings");
  ($smtpd, $conn);
}

sub start_connection {
    my $self = shift;
    my %args = @_;

    my $remote_host = $args{remote_host} or croak "no remote_host parameter";
    my $remote_info = "test\@$remote_host";
    my $remote_ip   = $args{remote_ip} or croak "no remote_ip parameter";
    
    my $conn = $self->SUPER::connection->start(remote_info => $remote_info,
                                               remote_ip   => $remote_ip,
                                               remote_host => $remote_host,
                                               @_);


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
  $self->{_response} ? (@{ delete $self->{_response} }) : ();
}

sub command {
  my ($self, $command) = @_;
  $self->input($command);
  $self->response;
}

sub input {
  my $self    = shift;
  my $command = shift;

  my $timeout = $self->config('timeout');
  alarm $timeout;

  $command =~ s/\r?\n$//s; # advanced chomp
  $self->log(LOGDEBUG, "dispatching $command");
  defined $self->dispatch(split / +/, $command, 2)
      or $self->respond(502, "command unrecognized: '$command'");
  alarm $timeout;
}

sub config_dir {
    './config.sample';
}

sub plugin_dirs {
    ('./plugins', './plugins/ident', './plugins/async');
}

sub log {
    my ($self, $trace, $hook, $plugin, @log) = @_;
    my $level = Qpsmtpd::TRACE_LEVEL() || 5;
    $level = $self->init_logger unless defined $level;
    print("# " . join(" ", $$, @log) . "\n") if $trace <= $level;
}

sub varlog {
    shift->log(@_);
}

# sub run
# sub disconnect

sub run_plugin_tests {
    my $self = shift;
    $self->{_test_mode} = 1;
    my @plugins = $self->load_plugins();
    # First count test number
    my $num_tests = 0;
    foreach my $plugin (@plugins) {
        $plugin->register_tests();
        $num_tests += $plugin->total_tests();
    }
    
    require Test::Builder;
    my $Test = Test::Builder->new();

    $Test->plan( tests => $num_tests );
    
    # Now run them
    
    foreach my $plugin (@plugins) {
        $plugin->run_tests($self);
    }
}

1;

