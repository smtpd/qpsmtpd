package Qpsmtpd;
use strict;

$Qpsmtpd::VERSION = "0.26-dev";
sub TRACE_LEVEL { 6 }

use Sys::Hostname;
use Qpsmtpd::Constants;

sub version { $Qpsmtpd::VERSION };

$Qpsmtpd::_hooks = {};

sub log {
  my ($self, $trace, @log) = @_;
  warn join(" ", $$, @log), "\n"
    if $trace <= TRACE_LEVEL;
}


#
# method to get the configuration.  It just calls get_qmail_config by
# default, but it could be overwritten to look configuration up in a
# database or whatever.
#
sub config {
  my ($self, $c, $type) = @_;

  #warn "SELF->config($c) ", ref $self;

  my %defaults = (
		  me      => hostname,
		  timeout => 1200,
		  );

  my ($rc, @config) = $self->run_hooks("config", $c);
  @config = () unless $rc == OK;

  if (wantarray) {
      @config = $self->get_qmail_config($c, $type) unless @config;
      @config = @{$defaults{$c}} if (!@config and $defaults{$c});
      return @config;
  } 
  else {
      return ($config[0] || $self->get_qmail_config($c, $type) || $defaults{$c});
   }
}


sub get_qmail_config {
  my ($self, $config, $type) = @_;
  $self->log(8, "trying to get config for $config");
  if ($self->{_config_cache}->{$config}) {
    return wantarray ? @{$self->{_config_cache}->{$config}} : $self->{_config_cache}->{$config}->[0];
  }
  my $configdir = '/var/qmail/control';
  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  $configdir = "$name/config" if (-e "$name/config/$config");

  my $configfile = "$configdir/$config";

  if ($type and $type eq "map")  {
    warn "MAP!";
    return +{} unless -e $configfile;
    eval { require CDB_File };

    if ($@) {
      $self->log(0, "No $configfile.cdb support, could not load CDB_File module: $@");
    }
    my %h;
    unless (tie(%h, 'CDB_File', "$configfile.cdb")) {
      $self->log(0, "tie of $configfile.cdb failed: $!");
      return DECLINED;
    }
    #warn Data::Dumper->Dump([\%h], [qw(h)]);
    # should we cache this?
    return \%h;
  }

  open CF, "<$configfile" or warn "$$ could not open configfile $configfile: $!", return;
  my @config = <CF>;
  chomp @config;
  @config = grep { $_ and $_ !~ m/^\s*#/ and $_ =~ m/\S/} @config;
  close CF;
  $self->log(10, "returning get_config for $config ",Data::Dumper->Dump([\@config], [qw(config)]));
  $self->{_config_cache}->{$config} = \@config;
  return wantarray ? @config : $config[0];
}



sub load_plugins {
  my $self = shift;
  my @plugins = $self->config('plugins');

  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  my $dir = "$name/plugins";
  $self->log(2, "loading plugins from $dir");

  for my $plugin (@plugins) {
    $self->log(7, "Loading $plugin");
    ($plugin, my @args) = split /\s+/, $plugin;

    my $plugin_name = $plugin;

    # Escape everything into valid perl identifiers
    $plugin_name =~ s/([^A-Za-z0-9_\/])/sprintf("_%2x",unpack("C",$1))/eg;

    # second pass cares for slashes and words starting with a digit
    $plugin_name =~ s{
		      (/+)       # directory
		      (\d?)      # package's first character
		     }[
		       "::" . (length $2 ? sprintf("_%2x",unpack("C",$2)) : "")
		      ]egx;


    my $sub;
    open F, "$dir/$plugin" or die "could not open $dir/$plugin: $!";
    { 
      local $/ = undef;
      $sub = <F>;
    }
    close F;

    my $package = "Qpsmtpd::Plugin::$plugin_name";

    my $line = "\n#line 1 $dir/$plugin\n";

    my $eval = join(
		    "\n",
		    "package $package;",
		    'use Qpsmtpd::Constants;',
		    "require Qpsmtpd::Plugin;",
		    'use vars qw(@ISA);',
		    '@ISA = qw(Qpsmtpd::Plugin);',
		    "sub plugin_name { qq[$plugin_name] }",
		    $line,
		    $sub,
		    "\n", # last line comment without newline?
		   );

    #warn "eval: $eval";

    $eval =~ m/(.*)/s;
    $eval = $1;

    eval $eval;
    die "eval $@" if $@;

    my $plug = $package->new(qpsmtpd => $self);
    $plug->register($self, @args);

  }
}

sub run_hooks {
  my ($self, $hook) = (shift, shift);
  $self->{_hooks} = $Qpsmtpd::_hooks;
  if ($self->{_hooks}->{$hook}) {
    my @r;
    for my $code (@{$self->{_hooks}->{$hook}}) {
      $self->log(5, "running plugin ", $code->{name});
      eval { (@r) = &{$code->{code}}($self->can('transaction') ? $self->transaction : {}, @_); };
      $@ and $self->log(0, "FATAL PLUGIN ERROR: ", $@) and next;
      !defined $r[0] 
	  and $self->log(1, "plugin ".$code->{name}
			 ."running the $hook hook returned undef!")
	  and next;

      # should we have a hook for "OK" too? 
      if ($r[0] == DENY or $r[0] == DENYSOFT) {
	  $r[1] = "" if not defined $r[1];
	  $self->log(10, "Plugin $code->{name}, hook $hook returned $r[0], $r[1]");
	  $self->run_hooks("deny", $code->{name}, $r[0], $r[1]) unless ($hook eq "deny");
      }

      last unless $r[0] == DECLINED; 
    }
    $r[0] = DECLINED if not defined $r[0];
    return @r;
  }
  return (0, '');
}

sub _register_hook {
  my $self = shift;
  my ($hook, $code) = @_;

  #my $plugin = shift;  # see comment in Plugin.pm:register_hook

  $self->{_hooks} = $Qpsmtpd::_hooks;
  my $hooks = $self->{_hooks};
  push @{$hooks->{$hook}}, $code;
}

1;
