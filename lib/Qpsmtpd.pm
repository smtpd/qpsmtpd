package Qpsmtpd;
use strict;
use vars qw($VERSION $LogLevel);

use Sys::Hostname;
use Qpsmtpd::Constants;

$VERSION = "0.28";
sub TRACE_LEVEL { $LogLevel }

sub version { $VERSION };

sub init_logger {
    my $self = shift;
    # Get the loglevel - we localise loglevel to zero while we do this
    my $loglevel = do {
        local $LogLevel = 0;
        $self->config("loglevel");
    };
    if (defined($loglevel) and $loglevel =~ /^\d+$/) {
        $LogLevel = $loglevel;
    }
    else {
        $LogLevel = LOGWARN; # Default if no loglevel file found.
    }
    return $LogLevel;
}

sub log {
  my ($self, $trace, @log) = @_;
  my $level = TRACE_LEVEL();
  $level = $self->init_logger unless defined $level;
  warn join(" ", $$, @log), "\n"
    if $trace <= $level;
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
      @config = $defaults{$c} if (!@config and $defaults{$c});
      return @config;
  } 
  else {
      return ($config[0] || $self->get_qmail_config($c, $type) || $defaults{$c});
   }
}


sub get_qmail_config {
  my ($self, $config, $type) = @_;
  $self->log(LOGDEBUG, "trying to get config for $config");
  if ($self->{_config_cache}->{$config}) {
    return wantarray ? @{$self->{_config_cache}->{$config}} : $self->{_config_cache}->{$config}->[0];
  }
  my $configdir = ($ENV{QMAIL} || '/var/qmail') . '/control';
  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  $configdir = "$name/config" if (-e "$name/config/$config");

  my $configfile = "$configdir/$config";

  if ($type and $type eq "map")  {
    return +{} unless -e $configfile . ".cdb";
    eval { require CDB_File };

    if ($@) {
      $self->log(LOGERROR, "No CDB Support! Did NOT read $configfile.cdb, could not load CDB_File module: $@");
      return +{};
    }

    my %h;
    unless (tie(%h, 'CDB_File', "$configfile.cdb")) {
      $self->log(LOGERROR, "tie of $configfile.cdb failed: $!");
      return +{};
    }
    #warn Data::Dumper->Dump([\%h], [qw(h)]);
    # should we cache this?
    return \%h;
  }

  return $self->_config_from_file($configfile, $config);
}

sub _config_from_file {
  my ($self, $configfile, $config) = @_;
  return unless -e $configfile;
  open CF, "<$configfile" or warn "$$ could not open configfile $configfile: $!" and return;
  my @config = <CF>;
  chomp @config;
  @config = grep { length($_) and $_ !~ m/^\s*#/ and $_ =~ m/\S/} @config;
  close CF;
  #$self->log(10, "returning get_config for $config ",Data::Dumper->Dump([\@config], [qw(config)]));
  $self->{_config_cache}->{$config} = \@config;
  return wantarray ? @config : $config[0];
}


sub load_plugins {
  my $self = shift;
  
  $self->{hooks} ||= {};
  
  my @plugins = $self->config('plugins');

  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  my $dir = "$name/plugins";
  $self->log(LOGNOTICE, "loading plugins from $dir");

  $self->_load_plugins($dir, @plugins);
}

sub _load_plugins {
  my $self = shift;
  my ($dir, @plugins) = @_;
  
  for my $plugin (@plugins) {
    $self->log(LOGINFO, "Loading $plugin");
    ($plugin, my @args) = split /\s+/, $plugin;
    
    if (lc($plugin) eq '$include') {
      my $inc = shift @args;
      my $config_dir = ($ENV{QMAIL} || '/var/qmail') . '/control';
      my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
      $config_dir = "$name/config" if (-e "$name/config/$inc");
      if (-d "$config_dir/$inc") {
        $self->log(LOGDEBUG, "Loading include dir: $config_dir/$inc");
        opendir(DIR, "$config_dir/$inc") || die "opendir($config_dir/$inc): $!";
        my @plugconf = sort grep { -f $_ } map { "$config_dir/$inc/$_" } grep { !/^\./ } readdir(DIR);
        closedir(DIR);
        foreach my $f (@plugconf) {
            $self->_load_plugins($dir, $self->_config_from_file($f, "plugins"));
        }
      }
      elsif (-f "$config_dir/$inc") {
        $self->log(LOGDEBUG, "Loading include file: $config_dir/$inc");
        $self->_load_plugins($dir, $self->_config_from_file("$config_dir/$inc", "plugins"));
      }
      else {
        $self->log(LOGCRIT, "CRITICAL PLUGIN CONFIG ERROR: Include $config_dir/$inc not found");
      }
      next;
    }
    
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

    my $package = "Qpsmtpd::Plugin::$plugin_name";

    # don't reload plugins if they are already loaded
    next if defined &{"${package}::register"};
    
    my $sub;
    open F, "$dir/$plugin" or die "could not open $dir/$plugin: $!";
    { 
      local $/ = undef;
      $sub = <F>;
    }
    close F;

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

    my $plug = $package->new();
    $plug->_register($self, @args);

  }
}

sub transaction {
    return {}; # base class implements empty transaction
}

sub run_hooks {
  my ($self, $hook) = (shift, shift);
  my $hooks = $self->{hooks};
  if ($hooks->{$hook}) {
    my @r;
    for my $code (@{$hooks->{$hook}}) {
      $self->log(LOGINFO, "running plugin ", $code->{name});
      eval { (@r) = $code->{code}->($self, $self->transaction, @_); };
      $@ and $self->log(LOGCRIT, "FATAL PLUGIN ERROR: ", $@) and next;

      !defined $r[0]
        and $self->log(LOGERROR, "plugin ".$code->{name}
                       ."running the $hook hook returned undef!")
          and next;

      if ($self->transaction) {
        my $tnotes = $self->transaction->notes( $code->{name} );
        $tnotes->{"hook_$hook"}->{'return'} = $r[0]
          if (!defined $tnotes || ref $tnotes eq "HASH");
      } else {
        my $cnotes = $self->connection->notes( $code->{name} );
        $cnotes->{"hook_$hook"}->{'return'} = $r[0]
          if (!defined $cnotes || $cnotes eq "HASH");
      }

      # should we have a hook for "OK" too?
      if ($r[0] == DENY or $r[0] == DENYSOFT) {
        $r[1] = "" if not defined $r[1];
        $self->log(LOGDEBUG, "Plugin $code->{name}, hook $hook returned $r[0], $r[1]");
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
  my ($hook, $code, $unshift) = @_;

  my $hooks = $self->{hooks};
  if ($unshift) {
    unshift @{$hooks->{$hook}}, $code;
  }
  else {
    push @{$hooks->{$hook}}, $code;
  }
}

1;
