package Qpsmtpd::Plugin;
use strict;

my %hooks = map { $_ => 1 } qw(
    config  queue  data  data_post  quit  rcpt  mail  ehlo  helo
    auth auth-plain auth-login auth-cram-md5
    connect  reset_transaction  unrecognized_command  disconnect
);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  bless ({}, $class);
}

sub register_hook {
  my ($plugin, $hook, $method, $unshift) = @_;
  
  die $plugin->plugin_name . " : Invalid hook: $hook" unless $hooks{$hook};

  # I can't quite decide if it's better to parse this code ref or if
  # we should pass the plugin object and method name ... hmn.
  $plugin->qp->_register_hook($hook, { code => sub { local $plugin->{_qp} = shift; $plugin->$method(@_) },
				       name => $plugin->plugin_name,
				     },
				     $unshift,
			     );
}

sub _register {
  my $self = shift;
  my $qp = shift;
  local $self->{_qp} = $qp;
  $self->register($qp, @_);
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

sub connection {
  shift->qp->connection;
}

# plugin inheritance:
# usage:
#  sub register {
#    my $self = shift;
#    $self->isa_plugin("rhsbl");
#    $self->SUPER::register(@_);
#  }
sub isa_plugin {
  my ($self, $parent) = @_;
  my ($currentPackage) = caller;
  my $newPackage = $currentPackage."::_isa_";

  return if defined &{"${newPackage}::register"};

  Qpsmtpd::_compile($self->plugin_name . "_isa",
                    $newPackage,
                    "plugins/$parent"); # assumes Cwd is qpsmtpd root

  no strict 'refs';
  push @{"${currentPackage}::ISA"}, $newPackage;
}

1;
