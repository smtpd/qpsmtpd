package Qpsmtpd::Plugin;
use strict;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;
  bless ({ _qp => $args{qpsmtpd} }, $class);
}

sub register_hook {
  my ($plugin, $hook, $method) = @_;
  # I can't quite decide if it's better to parse this code ref or if
  # we should pass the plugin object and method name ... hmn.
  $plugin->qp->_register_hook($hook, sub { $plugin->$method(@_) });
}

sub qp {
  shift->{_qp};
}

sub log {
    shift->qp->log(@_);
}

sub transaction {
  # not sure if this will work in a non-forking or a threaded daemon
  shift->qp->transaction;
}

1;
