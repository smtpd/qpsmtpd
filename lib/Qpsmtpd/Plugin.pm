package Qpsmtpd::Plugin;
use strict;

our %hooks = map { $_ => 1 } qw(
    config  queue  data  data_post  quit  rcpt  mail  ehlo  helo
    auth auth-plain auth-login auth-cram-md5
    connect  reset_transaction  unrecognized_command  disconnect
    deny
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

sub spool_dir {
  shift->qp->spool_dir;
}

sub temp_file {
  my $self = shift;
  my $tempfile = $self->qp->temp_file;
  push @{$self->qp->transaction->{_temp_files}}, $tempfile;
  return $tempfile;
}

sub temp_dir {
  my $self = shift;
  my $tempdir = $self->qp->temp_dir();
  push @{$self->qp->transaction->{_temp_dirs}}, $tempdir;
  return $tempdir;
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

sub compile {
    my ($class, $plugin, $package, $file, $test_mode) = @_;
    
    my $sub;
    open F, $file or die "could not open $file: $!";
    { 
      local $/ = undef;
      $sub = <F>;
    }
    close F;

    my $line = "\n#line 1 $file\n";

    if ($test_mode) {
        if (open(F, "t/plugin_tests/$plugin")) {
            local $/ = undef;
            $sub .= "#line 1 t/plugin_tests/$plugin\n";
            $sub .= <F>;
            close F;
        }
    }

    my $eval = join(
		    "\n",
		    "package $package;",
		    'use Qpsmtpd::Constants;',
		    "require Qpsmtpd::Plugin;",
		    'use vars qw(@ISA);',
		    '@ISA = qw(Qpsmtpd::Plugin);',
		    ($test_mode ? 'use Test::More;' : ''),
		    "sub plugin_name { qq[$plugin] }",
		    $line,
		    $sub,
		    "\n", # last line comment without newline?
		   );

    #warn "eval: $eval";

    $eval =~ m/(.*)/s;
    $eval = $1;

    eval $eval;
    die "eval $@" if $@;
}

1;
