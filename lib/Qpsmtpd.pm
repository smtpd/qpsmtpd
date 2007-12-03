package Qpsmtpd;
use strict;
use vars qw($VERSION $Logger $TraceLevel $Spool_dir $Size_threshold);

use Sys::Hostname;
use Qpsmtpd::Constants;

$VERSION = "0.40-dev";

my $hooks = {};
my %defaults = (
		  me      => hostname,
		  timeout => 1200,
		  );
my $_config_cache = {};
clear_config_cache();

sub version { $VERSION };

sub TRACE_LEVEL { $TraceLevel }; # leave for plugin compatibility

sub load_logging {
  # need to do this differently that other plugins so as to 
  # not trigger logging activity
  my $self = shift;
  return if $hooks->{"logging"};
  my $configdir = $self->config_dir("logging");
  my $configfile = "$configdir/logging";
  my @loggers = $self->_config_from_file($configfile,'logging');

  $configdir = $self->config_dir('plugin_dirs');
  $configfile = "$configdir/plugin_dirs";
  my @plugin_dirs = $self->_config_from_file($configfile,'plugin_dirs');
  unless (@plugin_dirs) {
    my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
    @plugin_dirs = ( "$name/plugins" );
  }
  
  my @loaded;
  for my $logger (@loggers) {
    push @loaded, $self->_load_plugin($logger, @plugin_dirs);
  }

  foreach my $logger (@loaded) {
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

sub clear_config_cache {
    $_config_cache = {};
    for (keys %defaults) {
        $_config_cache->{$_} = [$defaults{$_}];
    }
}

#
# method to get the configuration.  It just calls get_qmail_config by
# default, but it could be overwritten to look configuration up in a
# database or whatever.
#
sub config {
  my ($self, $c, $type) = @_;

  if ($_config_cache->{$c}) {
      return wantarray ? @{$_config_cache->{$c}} : $_config_cache->{$c}->[0];
  }
  
  #warn "SELF->config($c) ", ref $self;

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

my %config_dir_memo;
sub config_dir {
  my ($self, $config) = @_;
  if (exists $config_dir_memo{$config}) {
      return $config_dir_memo{$config};
  }
  my $configdir = ($ENV{QMAIL} || '/var/qmail') . '/control';
  my ($path) = ($ENV{PROCESS} ? $ENV{PROCESS} : $0) =~ m!(.*?)/([^/]+)$!;
  $configdir = "$path/config" if (-e "$path/config/$config");
  if (exists $ENV{QPSMTPD_CONFIG}) {
    $ENV{QPSMTPD_CONFIG} =~ /^(.*)$/; # detaint
    $configdir = $1 if -e "$1/$config";
  }
  return $config_dir_memo{$config} = $configdir;
}

sub plugin_dirs {
    my $self = shift;
    my @plugin_dirs = $self->config('plugin_dirs');
    
    unless (@plugin_dirs) {
        my ($path) = ($ENV{PROCESS} ? $ENV{PROCESS} : $0) =~ m!(.*?)/([^/]+)$!;
        @plugin_dirs = ( "$path/plugins" );
    }
    return @plugin_dirs;
}

sub get_qmail_config {
  my ($self, $config, $type) = @_;
  $self->log(LOGDEBUG, "trying to get config for $config");
  my $configdir = $self->config_dir($config);

  my $configfile = "$configdir/$config";

  if ($type and $type eq "map")  {
    unless (-e $configfile . ".cdb") {
        $_config_cache->{$config} = [];
        return +{};
    }
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
  my ($self, $configfile, $config, $visited) = @_;
  unless (-e $configfile) {
      $_config_cache->{$config} = [];
      return;
  }

  $visited ||= [];
  push @{$visited}, $configfile;

  open CF, "<$configfile" or warn "$$ could not open configfile $configfile: $!" and return;
  my @config = <CF>;
  chomp @config;
  @config = grep { length($_) and $_ !~ m/^\s*#/ and $_ =~ m/\S/} @config;
  close CF;

  my $pos = 0;
  while ($pos < @config) {
    # recursively pursue an $include reference, if found.  An inclusion which
    # begins with a leading slash is interpreted as a path to a file and will
    # supercede the usual config path resolution.  Otherwise, the normal
    # config_dir() lookup is employed (the location in which the inclusion
    # appeared receives no special precedence; possibly it should, but it'd
    # be complicated beyond justifiability for so simple a config system.
    if ($config[$pos] =~ /^\s*\$include\s+(\S+)\s*$/) {
      my ($includedir, $inclusion) = ('', $1);

      splice @config, $pos, 1; # remove the $include line
      if ($inclusion !~ /^\//) {
        $includedir = $self->config_dir($inclusion);
        $inclusion = "$includedir/$inclusion";
      }

      if (grep($_ eq $inclusion, @{$visited})) {
        $self->log(LOGERROR, "Circular \$include reference in config $config:");
        $self->log(LOGERROR, "From $visited->[0]:");
        $self->log(LOGERROR, "  includes $_")
          for (@{$visited}[1..$#{$visited}], $inclusion);
        return wantarray ? () : undef;
      }
      push @{$visited}, $inclusion;

      for my $inc ($self->expand_inclusion_($inclusion, $configfile)) {
        my @insertion = $self->_config_from_file($inc, $config, $visited);
        splice @config, $pos, 0, @insertion;   # insert the inclusion
        $pos += @insertion;
      }
    } else {
      $pos++;
    }
  }

  $_config_cache->{$config} = \@config;

  return wantarray ? @config : $config[0];
}

sub expand_inclusion_ {
  my $self = shift;
  my $inclusion = shift;
  my $context = shift;
  my @includes;

  if (-d $inclusion) {
    $self->log(LOGDEBUG, "inclusion of directory $inclusion from $context");

    if (opendir(INCD, $inclusion)) {
      @includes = map { "$inclusion/$_" }
        (grep { -f "$inclusion/$_" and !/^\./ } sort readdir INCD);
      closedir INCD;
    } else {
      $self->log(LOGERROR, "Couldn't open directory $inclusion,".
                           " referenced from $context ($!)");
    }
  } else {
    $self->log(LOGDEBUG, "inclusion of file $inclusion from $context");
    @includes = ( $inclusion );
  }
  return @includes;
}


sub load_plugins {
  my $self = shift;
  
  my @plugins = $self->config('plugins');
  my @loaded;

  if ($hooks->{queue}) {
    $self->log(LOGWARN, "Plugins already loaded");
    return @plugins;
  }
  
  for my $plugin_line (@plugins) {
    my $this_plugin = $self->_load_plugin($plugin_line, $self->plugin_dirs);
    push @loaded, $this_plugin if $this_plugin;
  }

  return @loaded;
}

sub _load_plugin {
  my $self = shift;
  my ($plugin_line, @plugin_dirs) = @_;

  my ($plugin, @args) = split ' ', $plugin_line;

  my $package;

  if ($plugin =~ m/::/) {
    # "full" package plugin (My::Plugin)
    $package = $plugin;
    $package =~ s/[^_a-z0-9:]+//gi;
    my $eval = qq[require $package;\n] 
              .qq[sub ${plugin}::plugin_name { '$plugin' }];
    $eval =~ m/(.*)/s;
    $eval = $1;
    eval $eval;
    die "Failed loading $package - eval $@" if $@;
    $self->log(LOGDEBUG, "Loading $package ($plugin_line)") 
      unless $plugin_line =~ /logging/;
  }
  else {
    # regular plugins/$plugin plugin
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
    
    $package = "Qpsmtpd::Plugin::$plugin_name";
    
    # don't reload plugins if they are already loaded
    unless ( defined &{"${package}::plugin_name"} ) {
      PLUGIN_DIR: for my $dir (@plugin_dirs) {
        if (-e "$dir/$plugin") {
          Qpsmtpd::Plugin->compile($plugin_name, $package,
            "$dir/$plugin", $self->{_test_mode}, $plugin);
          $self->log(LOGDEBUG, "Loading $plugin_line from $dir/$plugin") 
            unless $plugin_line =~ /logging/;
          last PLUGIN_DIR;
        }
      }
      die "Plugin $plugin_name not found in our plugin dirs (",
      	  join(", ", @plugin_dirs),")"
        unless defined &{"${package}::plugin_name"};
    }
  }

  my $plug = $package->new();
  $plug->_register($self, @args);
  
  return $plug;
}

sub transaction {
    return {}; # base class implements empty transaction
}

sub run_hooks {
  my ($self, $hook) = (shift, shift);
  if ($hooks->{$hook}) {
    my @r;
    my @local_hooks = @{$hooks->{$hook}};
    $self->{_continuation} = [$hook, [@_], @local_hooks];
    return $self->run_continuation();
  }
  return $self->hook_responder($hook, [0, ''], [@_]);
}

sub run_continuation {
  my $self = shift;
  die "No continuation in progress" unless $self->{_continuation};
  $self->continue_read() if $self->isa('Danga::Client');
  my $todo = $self->{_continuation};
  $self->{_continuation} = undef;
  my $hook = shift @$todo || die "No hook in the continuation";
  my $args = shift @$todo || die "No hook args in the continuation";
  my @r;
  while (@$todo) {
    my $code = shift @$todo;
    if ( $hook eq 'logging' ) { # without calling $self->log()
      eval { (@r) = $code->{code}->($self, $self->transaction, @$args); };
      $@ and warn("FATAL LOGGING PLUGIN ERROR: ", $@) and next;
    }
    else {
      $self->varlog(LOGDEBUG, $hook, $code->{name});
      eval { (@r) = $code->{code}->($self, $self->transaction, @$args); };
      $@ and $self->log(LOGCRIT, "FATAL PLUGIN ERROR: ", $@) and next;

      !defined $r[0]
        and $self->log(LOGERROR, "plugin ".$code->{name}
                       ." running the $hook hook returned undef!")
        and next;

      if ($self->transaction) {
        my $tnotes = $self->transaction->notes( $code->{name} );
        $tnotes->{"hook_$hook"}->{'return'} = $r[0]
          if (!defined $tnotes || ref $tnotes eq "HASH");
      }
      else {
        my $cnotes = $self->connection->notes( $code->{name} );
        $cnotes->{"hook_$hook"}->{'return'} = $r[0]
          if (!defined $cnotes || ref $cnotes eq "HASH");
      }
      
      if ($r[0] == YIELD) {
        $self->pause_read() if $self->isa('Danga::Client');
        $self->{_continuation} = [$hook, $args, @$todo];
        return @r;
      }
      elsif ($r[0] == DENY or $r[0] == DENYSOFT or
          $r[0] == DENY_DISCONNECT or $r[0] == DENYSOFT_DISCONNECT)
      {
        $r[1] = "" if not defined $r[1];
        $self->log(LOGDEBUG, "Plugin ".$code->{name}.
	    ", hook $hook returned ".return_code($r[0]).", $r[1]");
        $self->run_hooks("deny", $code->{name}, $r[0], $r[1]) unless ($hook eq "deny");
      }
      else {
        $r[1] = "" if not defined $r[1];
        $self->log(LOGDEBUG, "Plugin ".$code->{name}.
	    ", hook $hook returned ".return_code($r[0]).", $r[1]");
        $self->run_hooks("ok", $code->{name}, $r[0], $r[1]) unless ($hook eq "ok");
      }

    }

    last unless $r[0] == DECLINED;
  }
  $r[0] = DECLINED if not defined $r[0];
  @r = map { split /\n/ } @r;
  return $self->hook_responder($hook, \@r, $args);
}

sub hook_responder {
  my ($self, $hook, $msg, $args) = @_;
  
  my $code = shift @$msg;
  
  my $responder = $hook . '_respond';
  if (my $meth = $self->can($responder)) {
    return $meth->($self, $code, $msg, $args);
  }
  return $code, @$msg;
}

sub _register_hook {
  my $self = shift;
  my ($hook, $code, $unshift) = @_;

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

sub size_threshold {
  my $self = shift;
  unless ( defined $Size_threshold ) {
    $Size_threshold = $self->config('size_threshold') || 0;
    $self->log(LOGNOTICE, "size_threshold set to $Size_threshold");
  }
  return $Size_threshold;
}

sub authenticated {
  my $self = shift;
  return (defined $self->{_auth} ? $self->{_auth} : "" );
}

sub auth_user {
  my $self = shift;
  return (defined $self->{_auth_user} ? $self->{_auth_user} : "" );
}

sub auth_mechanism {
  my $self = shift;
  return (defined $self->{_auth_mechanism} ? $self->{_auth_mechanism} : "" );
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



