package Qpsmtpd;
use strict;

$Qpsmtpd::VERSION = "0.12";
sub TRACE_LEVEL { 6 }

use Sys::Hostname;
use Qpsmtpd::Constants;

sub version { $Qpsmtpd::VERSION };

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
  my ($self, $c) = @_;

  #warn "SELF->config($c) ", ref $self;

  my %defaults = (
		  me      => hostname,
		  timeout => 1200,
		  );

  if (wantarray) {
      my @config = $self->get_qmail_config($c);
      @config = @{$defaults{$c}} if (!@config and $defaults{$c});
      return @config;
  } 
  else {
      return ($self->get_qmail_config($c) || $defaults{$c});
   }
}


sub get_qmail_config {
  my ($self, $config) = (shift, shift);
  $self->log(8, "trying to get config for $config");
  if ($self->{_config_cache}->{$config}) {
    return wantarray ? @{$self->{_config_cache}->{$config}} : $self->{_config_cache}->{$config}->[0];
  }
  my $configdir = '/var/qmail/control';
  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  $configdir = "$name/config" if (-e "$name/config/$config");
  open CF, "<$configdir/$config" or warn "$$ could not open configfile $config: $!", return;
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
    $plug->register($self);

  }
}

sub run_hooks {
  my ($self, $hook) = (shift, shift);
  if ($self->{_hooks}->{$hook}) {
    my @r;
    for my $code (@{$self->{_hooks}->{$hook}}) {
      $self->log(5, "running plugin ", $code->{name});
      eval { (@r) = &{$code->{code}}($self->transaction, @_); };
      $@ and $self->log(0, "FATAL PLUGIN ERROR: ", $@) and next;
      !defined $r[0] 
	  and $self->log(1, "plugin ".$code->{name}
			 ."running the $hook hook returned undef!")
	  and next;
      last unless $r[0] == DECLINED; 
    }
    return @r;
  }
  warn "Did not run any hooks ...";
  return (0, '');
}

sub _register_hook {
  my $self = shift;
  my ($hook, $code) = @_;

  #my $plugin = shift;  # see comment in Plugin.pm:register_hook

  $self->{_hooks} ||= {};
  my $hooks = $self->{_hooks};
  push @{$hooks->{$hook}}, $code;
}

1;
