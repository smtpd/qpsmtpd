package Qpsmtpd::Plugin;
use Qpsmtpd::Constants;
use strict;

our @hooks = qw(
    logging config  queue  data  data_post  quit  rcpt  mail  ehlo  helo
    auth auth-plain auth-login auth-cram-md5
    connect  reset_transaction  unrecognized_command  disconnect
    deny ok pre-connection post-connection
);
our %hooks = map { $_ => 1 } @hooks;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  bless ({}, $class);
}

sub register_hook {
  my ($plugin, $hook, $method, $unshift) = @_;

  die $plugin->plugin_name . " : Invalid hook: $hook" unless $hooks{$hook};

  $plugin->{_qp}->log(LOGDEBUG, $plugin->plugin_name, "hooking", $hook)
      unless $hook =~ /logging/; # can't log during load_logging()

  # I can't quite decide if it's better to parse this code ref or if
  # we should pass the plugin object and method name ... hmn.
  $plugin->qp->_register_hook($hook, { code => sub { local $plugin->{_qp} = shift; local $plugin->{_hook} = $hook; $plugin->$method(@_) },
				       name => $plugin->plugin_name,
				     },
				     $unshift,
			     );
}

sub _register {
  my $self = shift;
  my $qp = shift;
  local $self->{_qp} = $qp;
  $self->init($qp, @_)     if $self->can('init');
  $self->_register_standard_hooks($qp, @_);
  $self->register($qp, @_) if $self->can('register');
}

# Designed to be overloaded
sub init {}
sub register {}

sub qp {
  shift->{_qp};
}

sub log {
  my $self = shift;
  $self->qp->varlog(shift, $self->hook_name, $self->plugin_name, @_)
    unless defined $self->hook_name and $self->hook_name eq 'logging';
}

sub transaction {
  # not sure if this will work in a non-forking or a threaded daemon
  shift->qp->transaction;
}

sub connection {
  shift->qp->connection;
}

sub config {
  shift->qp->config(@_);
}

sub spool_dir {
  shift->qp->spool_dir;
}

sub auth_user {
    shift->qp->auth_user(@_);
}

sub auth_mechanism {
    shift->qp->auth_mechanism(@_);
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
#  sub init {
#    my $self = shift;
#    $self->isa_plugin("rhsbl");
#    $self->SUPER::register(@_);
#  }
sub isa_plugin {
  my ($self, $parent) = @_;
  my ($currentPackage) = caller;

  my $cleanParent = $parent;
  $cleanParent =~ s/\W/_/g;
  my $newPackage = $currentPackage."::_isa_$cleanParent";

  # don't reload plugins if they are already loaded
  return if defined &{"${newPackage}::plugin_name"};

  $self->compile($self->plugin_name . "_isa_$cleanParent",
                    $newPackage,
                    "plugins/$parent"); # assumes Cwd is qpsmtpd root
  warn "---- $newPackage\n";
  no strict 'refs';
  push @{"${currentPackage}::ISA"}, $newPackage;
}

# why isn't compile private?  it's only called from Plugin and Qpsmtpd.
sub compile {
    my ($class, $plugin, $package, $file, $test_mode) = @_;
    
    my $sub;
    open F, $file or die "could not open $file: $!";
    { 
      local $/ = undef;
      $sub = <F>;
    }
    close F;

    my $line = "\n#line 0 $file\n";

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
                    'use strict;',
		    '@ISA = qw(Qpsmtpd::Plugin);',
		    ($test_mode ? 'use Test::More;' : ''),
		    "sub plugin_name { qq[$plugin] }",
		    "sub hook_name { return shift->{_hook}; }",
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

sub _register_standard_hooks {
  my ($plugin, $qp) = @_;

  for my $hook (@hooks) {
    my $hooksub = "hook_$hook";
    $hooksub  =~ s/\W/_/g;
    $plugin->register_hook( $hook, $hooksub )
      if ($plugin->can($hooksub));
  }
}


1;
