package Qpsmtpd::Plugin;
use strict;

my %hooks = map { $_ => 1 } qw(
    config  queue  data_post  quit  rcpt  mail  ehlo  helo
    connect  reset_transaction  unrecognized_command  disconnect
);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;
  bless ({ _qp => $args{qpsmtpd} }, $class);
}

sub register_hook {
  my ($plugin, $hook, $method) = @_;
  
  die $plugin->plugin_name . " : Invalid hook: $hook" unless $hooks{$hook};

  # I can't quite decide if it's better to parse this code ref or if
  # we should pass the plugin object and method name ... hmn.
  $plugin->qp->_register_hook($hook, { code => sub { local $plugin->{_qp} = shift; $plugin->$method(@_) },
				       name => $plugin->plugin_name 
				     }
			     );
}

sub qp {
  shift->{_qp};
}

sub log {
  my $self = shift;
  $self->qp->log(shift, $self->plugin_name . " plugin: " . shift, @_);
}

sub transaction {
  # not sure if this will work in a non-forking or a threaded daemon
  shift->qp->transaction;
}

1;
