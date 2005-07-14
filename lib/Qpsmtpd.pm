package Qpsmtpd;
use strict;
use vars qw($VERSION $Logger $TraceLevel $Spool_dir);

use Sys::Hostname;
use Qpsmtpd::Constants;

$VERSION = "0.31-dev";

sub version { $VERSION };

sub TRACE_LEVEL { $TraceLevel }; # leave for plugin compatibility

sub load_logging {
  # need to do this differently that other plugins so as to 
  # not trigger logging activity
  my $self = shift;
  return if $self->{hooks}->{"logging"};
  my $configdir = $self->config_dir("logging");
  my $configfile = "$configdir/logging";
  my @loggers = $self->_config_from_file($configfile,'logging');
  my $dir = $self->plugin_dir;

  $self->_load_plugins($dir, @loggers);

  foreach my $logger (@loggers) {
    $self->log(LOGINFO, "Loaded $logger");
  }
  
  return @loggers;
}
  
sub trace_level {
  my $self = shift;
  return $TraceLevel if $TraceLevel;

  my $configdir = $self->config_dir("loglevel");
  my $configfile = "$configdir/loglevel";
  $TraceLevel = $self->_config_from_file($configfile,'loglevel');

  unless (defined($TraceLevel) and $TraceLevel =~ /^\d+$/) {
    $TraceLevel = LOGWARN; # Default if no loglevel file found.
  }

  return $TraceLevel;
}

sub init_logger { # needed for compatibility purposes
  shift->trace_level();
}

sub log {
  my ($self, $trace, @log) = @_;
  $self->varlog($trace,join(" ",@log));
}

sub varlog {
  my ($self, $trace) = (shift,shift);
  my ($hook, $plugin, @log);
  if ( $#_ == 0 ) { # log itself
    (@log) = @_;
  }
  elsif ( $#_ == 1 ) { # plus the hook
    ($hook, @log) = @_;
  }
  else { # called from plugin
    ($hook, $plugin, @log) = @_;
  }

  $self->load_logging; # in case we already don't have this loaded yet

  my ($rc) = $self->run_hooks("logging", $trace, $hook, $plugin, @log);

  unless ( $rc and $rc == DECLINED or $rc == OK ) {
    # no logging plugins registered so fall back to STDERR
    warn join(" ", $$ .
      (defined $plugin ? " $plugin plugin:" : 
       defined $hook   ? " running plugin ($hook):"  : ""),
      @log), "\n"
    if $trace <= $self->trace_level();
  }
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

sub config_dir {
  my ($self, $config) = @_;
  my $configdir = ($ENV{QMAIL} || '/var/qmail') . '/control';
  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  $configdir = "$name/config" if (-e "$name/config/$config");
  return $configdir;
}

sub plugin_dir {
    my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
    my $dir = "$name/plugins";
}

sub get_qmail_config {
  my ($self, $config, $type) = @_;
  $self->log(LOGDEBUG, "trying to get config for $config");
  if ($self->{_config_cache}->{$config}) {
    return wantarray ? @{$self->{_config_cache}->{$config}} : $self->{_config_cache}->{$config}->[0];
  }
  my $configdir = $self->config_dir($config);

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
  
  $self->log(LOGWARN, "Plugins already loaded") if $self->{hooks};
  $self->{hooks} = {};
  
  my @plugins = $self->config('plugins');

  my $dir = $self->plugin_dir;
  $self->log(LOGNOTICE, "loading plugins from $dir");

  @plugins = $self->_load_plugins($dir, @plugins);
  
  return @plugins;
}

sub _load_plugins {
  my $self = shift;
  my ($dir, @plugins) = @_;

  my @ret;  
  for my $plugin_line (@plugins) {
    my ($plugin, @args) = split ' ', $plugin_line;
    
    if (lc($plugin) eq '$include') {
      my $inc = shift @args;
      my $config_dir = $self->config_dir($inc);
      if (-d "$config_dir/$inc") {
        $self->log(LOGDEBUG, "Loading include dir: $config_dir/$inc");
        opendir(DIR, "$config_dir/$inc") || die "opendir($config_dir/$inc): $!";
        my @plugconf = sort grep { -f $_ } map { "$config_dir/$inc/$_" } grep { !/^\./ } readdir(DIR);
        closedir(DIR);
        foreach my $f (@plugconf) {
            push @ret, $self->_load_plugins($dir, $self->_config_from_file($f, "plugins"));
        }
      }
      elsif (-f "$config_dir/$inc") {
        $self->log(LOGDEBUG, "Loading include file: $config_dir/$inc");
        push @ret, $self->_load_plugins($dir, $self->_config_from_file("$config_dir/$inc", "plugins"));
      }
      else {
        $self->log(LOGCRIT, "CRITICAL PLUGIN CONFIG ERROR: Include $config_dir/$inc not found");
      }
      next;
    }

    my $plugin_name = $plugin;
    $plugin =~ s/:\d+$//;       # after this point, only used for filename

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
    unless ( defined &{"${package}::plugin_name"} ) {
      Qpsmtpd::Plugin->compile($plugin_name,
        $package, "$dir/$plugin", $self->{_test_mode});
      $self->log(LOGDEBUG, "Loading $plugin_line") 
        unless $plugin_line =~ /logging/;
    }
    
    my $plug = $package->new();
    push @ret, $plug;
    $plug->_register($self, @args);

  }
  
  return @ret;
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
      if ( $hook eq 'logging' ) { # without calling $self->log()
        eval { (@r) = $code->{code}->($self, $self->transaction, @_); };
        $@ and warn("FATAL LOGGING PLUGIN ERROR: ", $@) and next;
      }
      else {
        $self->varlog(LOGINFO, $hook, $code->{name});
        eval { (@r) = $code->{code}->($self, $self->transaction, @_); };
        $@ and $self->log(LOGCRIT, "FATAL PLUGIN ERROR: ", $@) and next;

        !defined $r[0]
          and $self->log(LOGERROR, "plugin ".$code->{name}
                         ." running the $hook hook returned undef!")
          and next;

        if ($self->transaction) {
          my $tnotes = $self->transaction->notes( $code->{name} );
          $tnotes->{"hook_$hook"}->{'return'} = $r[0]
            if (!defined $tnotes || ref $tnotes eq "HASH");
        } else {
          my $cnotes = $self->connection->notes( $code->{name} );
          $cnotes->{"hook_$hook"}->{'return'} = $r[0]
            if (!defined $cnotes || ref $cnotes eq "HASH");
        }

        # should we have a hook for "OK" too?
        if ($r[0] == DENY or $r[0] == DENYSOFT or
            $r[0] == DENY_DISCONNECT or $r[0] == DENYSOFT_DISCONNECT)
        {
          $r[1] = "" if not defined $r[1];
          $self->log(LOGDEBUG, "Plugin ".$code->{name}.
	    ", hook $hook returned ".return_code($r[0]).", $r[1]");
          $self->run_hooks("deny", $code->{name}, $r[0], $r[1]) unless ($hook eq "deny");
        } else {
          $r[1] = "" if not defined $r[1];
          $self->log(LOGDEBUG, "Plugin ".$code->{name}.
	    ", hook $hook returned ".return_code($r[0]).", $r[1]");
          $self->run_hooks("ok", $code->{name}, $r[0], $r[1]) unless ($hook eq "ok");
	}

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

sub spool_dir {
  my $self = shift;

  unless ( $Spool_dir ) { # first time through
    $self->log(LOGINFO, "Initializing spool_dir");
    $Spool_dir = $self->config('spool_dir') 
               || Qpsmtpd::Utils::tildeexp('~/tmp/');

    $Spool_dir .= "/" unless ($Spool_dir =~ m!/$!);
  
    $Spool_dir =~ /^(.+)$/ or die "spool_dir not configured properly";
    $Spool_dir = $1; # cleanse the taint

    # Make sure the spool dir has appropriate rights
    if (-e $Spool_dir) {
      my $mode = (stat($Spool_dir))[2];
      $self->log(LOGWARN, 
          "Permissions on spool_dir $Spool_dir are not 0700")
        if $mode & 07077;
    }

    # And finally, create it if it doesn't already exist
    -d $Spool_dir or mkdir($Spool_dir, 0700) 
      or die "Could not create spool_dir $Spool_dir: $!";
  }
    
  return $Spool_dir;
}

# For unique filenames. We write to a local tmp dir so we don't need
# to make them unpredictable.
my $transaction_counter = 0; 

sub temp_file {
  my $self = shift;
  my $filename = $self->spool_dir() 
    . join(":", time, $$, $transaction_counter++);
  return $filename;
} 

sub temp_dir {
  my $self = shift;
  my $mask = shift || 0700;
  my $dirname = $self->temp_file();
  -d $dirname or mkdir($dirname, $mask)
    or die "Could not create temporary directory $dirname: $!";
  return $dirname;
}

1;

__END__

=head1 NAME

Qpsmtpd

=head1 DESCRIPTION

This is the base class for the qpsmtpd mail server.  See
L<http://smtpd.develooper.com/> and the I<README> file for more information.

=head1 COPYRIGHT

Copyright 2001-2005 Ask Bjoern Hansen, Develooper LLC.  See the
LICENSE file for more information.



