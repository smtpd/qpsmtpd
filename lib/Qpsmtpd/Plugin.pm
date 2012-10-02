package Qpsmtpd::Plugin;

use strict;
use warnings;

use Qpsmtpd::Constants;

# more or less in the order they will fire
our @hooks = qw(
    logging config post-fork pre-connection connect ehlo_parse ehlo
    helo_parse helo auth_parse auth auth-plain auth-login auth-cram-md5
    rcpt_parse rcpt_pre rcpt mail_parse mail mail_pre
    data data_headers_end data_post queue_pre queue queue_post vrfy noop
    quit reset_transaction disconnect post-connection
    unrecognized_command deny ok received_line help
);
our %hooks = map { $_ => 1 } @hooks;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  bless ({}, $class);
}

sub hook_name {
  return shift->{_hook};
}

sub register_hook {
  my ($plugin, $hook, $method, $unshift) = @_;

  die $plugin->plugin_name . " : Invalid hook: $hook" unless $hooks{$hook};

  $plugin->{_qp}->log(LOGDEBUG, $plugin->plugin_name, "hooking", $hook)
      unless $hook =~ /logging/; # can't log during load_logging()

  # I can't quite decide if it's better to parse this code ref or if
  # we should pass the plugin object and method name ... hmn.
  $plugin->qp->_register_hook
    ($hook,
     { code => sub { local $plugin->{_qp} = shift;
                     local $plugin->{_hook} = $hook;
                     $plugin->$method(@_)
                   },
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

sub qp {
  shift->{_qp};
}

sub log {
  my $self = shift;
  return if defined $self->{_hook} && $self->{_hook} eq 'logging';
  my $level = $self->adjust_log_level( shift, $self->plugin_name );
  $self->{_qp}->varlog($level, $self->{_hook}, $self->plugin_name, @_);
}

sub adjust_log_level {
    my ( $self, $cur_level, $plugin_name) = @_;

    my $adj = $self->{_args}{loglevel} or return $cur_level;

    return $adj if $adj =~ m/^[01234567]$/;  # a raw syslog numeral

    if ( $adj !~ /^[\+\-][\d]$/ ) {
        $self->log( LOGERROR, $self-"invalid $plugin_name loglevel setting ($adj)" );
        undef $self->{_args}{loglevel};  # only complain once per plugin
        return $cur_level;
    };

    my $operator = substr($adj, 0, 1);
    my $adjust  = substr($adj, -1, 1);

    my $new_level = $operator eq '+' ? $cur_level + $adjust : $cur_level - $adjust;

    $new_level = 7 if $new_level > 7;
    $new_level = 0 if $new_level < 0;

    return $new_level;
};

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

sub auth_user {
    shift->qp->auth_user;
}

sub auth_mechanism {
    shift->qp->auth_mechanism;
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

  # find $parent in plugin_dirs
  my $parent_dir;
  for ($self->qp->plugin_dirs) {
    if (-e "$_/$parent") {
      $parent_dir = $_;
      last;
    }
  }
  die "cannot find plugin '$parent'" unless $parent_dir;

  $self->compile($self->plugin_name . "_isa_$cleanParent",
                    $newPackage,
                    "$parent_dir/$parent");
  warn "---- $newPackage\n";
  no strict 'refs';
  push @{"${currentPackage}::ISA"}, $newPackage;
}

# why isn't compile private?  it's only called from Plugin and Qpsmtpd.
sub compile {
    my ($class, $plugin, $package, $file, $test_mode, $orig_name) = @_;

    my $sub;
    open F, $file or die "could not open $file: $!";
    {
      local $/ = undef;
      $sub = <F>;
    }
    close F;

    my $line = "\n#line 0 $file\n";

    if ($test_mode) {
        if (open(F, "t/plugin_tests/$orig_name")) {
            local $/ = undef;
            $sub .= "#line 1 t/plugin_tests/$orig_name\n";
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
