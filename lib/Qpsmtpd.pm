package Qpsmtpd;
use strict;
use vars qw($VERSION $LogLevel);

use Sys::Hostname;
use Qpsmtpd::Constants;
use Qpsmtpd::Transaction;
use Qpsmtpd::Connection;

$VERSION = "0.29";
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

our $HOOKS;

sub load_plugins {
  my $self = shift;

  if ($HOOKS) {
      return $self->{hooks} = $HOOKS;
  }

  $self->log(LOGERROR, "Plugins already loaded") if $self->{hooks};
  $self->{hooks} = {};
  
  my @plugins = $self->config('plugins');

  my $dir = $self->plugin_dir;
  $self->log(LOGNOTICE, "loading plugins from $dir");

  @plugins = $self->_load_plugins($dir, @plugins);
  
  $HOOKS = $self->{hooks};
  
  return @plugins;
}

sub _load_plugins {
  my $self = shift;
  my ($dir, @plugins) = @_;

  my @ret;  
  for my $plugin (@plugins) {
    $self->log(LOGDEBUG, "Loading $plugin");
    ($plugin, my @args) = split /\s+/, $plugin;
    
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
    Qpsmtpd::Plugin->compile($plugin_name, $package, "$dir/$plugin", $self->{_test_mode}) unless
        defined &{"${package}::register"};
    
    my $plug = $package->new();
    push @ret, $plug;
    $plug->_register($self, @args);

  }
  
  return @ret;
}

sub run_hooks {
  my ($self, $hook) = (shift, shift);
  if ($self->{_continuation}) {
    die "Continuations in progress from previous hook (this is the $hook hook)";
  }
  my $hooks = $self->{hooks};
  if ($hooks->{$hook}) {
    my @r;
    my @local_hooks = @{$hooks->{$hook}};
    while (@local_hooks) {
      my $code = shift @local_hooks;
      @r = $self->run_hook($hook, $code, @_);
      next unless @r;
      if ($r[0] == CONTINUATION) {
        $self->{_continuation} = [$hook, [@_], @local_hooks];
      }
      last unless $r[0] == DECLINED;
    }
    $r[0] = DECLINED if not defined $r[0];
    return @r;
  }
  return (0, '');
}

sub finish_continuation {
  my ($self) = @_;
  die "No continuation in progress" unless $self->{_continuation};
  my $todo = $self->{_continuation};
  $self->{_continuation} = undef;
  my $hook = shift @$todo || die "No hook in the continuation";
  my $args = shift @$todo || die "No hook args in the continuation";
  my @r;
  while (@$todo) {
    my $code = shift @$todo;
    @r = $self->run_hook($hook, $code, @$args);
    if ($r[0] == CONTINUATION) {
      $self->{_continuation} = [$hook, $args, @$todo];
      return @r;
    }
    last unless $r[0] == DECLINED;
  }
  $r[0] = DECLINED if not defined $r[0];
  my $responder = $hook . "_respond";
  if (my $meth = $self->can($responder)) {
    return $meth->($self, @r, @$args);
  }
  die "No ${hook}_respond method";
}

sub run_hook {
  my ($self, $hook, $code, @args) = @_;
  my @r;
  $self->log(LOGINFO, "running plugin ($hook):", $code->{name});
  eval { (@r) = $code->{code}->($self, $self->transaction, @args); };
  $@ and $self->log(LOGCRIT, "FATAL PLUGIN ERROR: ", $@) and return;

  !defined $r[0]
    and $self->log(LOGERROR, "plugin ".$code->{name}
                   ."running the $hook hook returned undef!")
      and return;

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
    $self->log(LOGDEBUG, "Plugin $code->{name}, hook $hook returned $r[0], $r[1]");
    $self->run_hooks("deny", $code->{name}, $r[0], $r[1]) unless ($hook eq "deny");
  }
  
  return @r;
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

my $spool_dir = "";

sub spool_dir {
  my $self = shift;

  unless ( $spool_dir ) { # first time through
    $self->log(LOGINFO, "Initializing spool_dir");
    $spool_dir = $self->config('spool_dir') 
               || Qpsmtpd::Utils::tildeexp('~/tmp/');

    $spool_dir .= "/" unless ($spool_dir =~ m!/$!);
  
    $spool_dir =~ /^(.+)$/ or die "spool_dir not configured properly";
    $spool_dir = $1; # cleanse the taint

    # Make sure the spool dir has appropriate rights
    if (-e $spool_dir) {
      my $mode = (stat($spool_dir))[2];
      $self->log(LOGWARN, 
          "Permissions on spool_dir $spool_dir are not 0700")
        if $mode & 07077;
    }

    # And finally, create it if it doesn't already exist
    -d $spool_dir or mkdir($spool_dir, 0700) 
      or die "Could not create spool_dir $spool_dir: $!";
    }
    
  return $spool_dir;
}

sub transaction {
    my $self = shift;
    return $self->{_transaction} || $self->reset_transaction();
}

sub reset_transaction {
    my $self = shift;
    $self->run_hooks("reset_transaction") if $self->{_transaction};
    return $self->{_transaction} = Qpsmtpd::Transaction->new();
}

sub connection {
  my $self = shift;
  return $self->{_connection} || ($self->{_connection} = Qpsmtpd::Connection->new());
}

# For unique filenames. We write to a local tmp dir so we don't need
# to make them unpredictable.
my $transaction_counter = 0; 

sub temp_file {
  my $self = shift;
  my $filename = $self->spool_dir() 
    . join(":", time, $$, $transaction_counter++);
  $filename =~ tr!A-Za-z0-9:/_-!!cd;
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
