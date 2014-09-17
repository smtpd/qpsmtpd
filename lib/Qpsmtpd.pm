package Qpsmtpd;
use strict;
#use warnings;

our $VERSION = '0.96';
use vars qw($TraceLevel $Spool_dir $Size_threshold);

use lib 'lib';
use base 'Qpsmtpd::Base';
use Qpsmtpd::Address;
use Qpsmtpd::Config;
use Qpsmtpd::Constants;

our $hooks = {};
our $LOGGING_LOADED = 0;
my $git = git_version();

sub _restart {
    my $self = shift;
    my %args = @_;
    if ($args{restart}) {

        # reset all global vars to defaults
        $self->conf->clear_cache();
        $hooks          = {};
        $LOGGING_LOADED = 0;
        $TraceLevel     = LOGWARN;
        $Spool_dir      = undef;
        $Size_threshold = undef;
    }
}

sub version { $VERSION . ($git ? "/$git" : "") }

sub git_version {
    return if !-e '.git';
    {
        local $ENV{PATH} = "/usr/bin:/usr/local/bin:/opt/local/bin/";
        $git = `git describe --tags`;
        $git && chomp $git;
    }
    return $git;
}

sub TRACE_LEVEL { $TraceLevel };    # leave for plugin compatibility

sub hooks {
    my ($self, $hook) = @_;
    if ($hook) {
        if (!defined $hooks->{$hook}) { return wantarray ? () : []; };
        return wantarray ? @{$hooks->{$hook}} : $hooks->{$hook};
    };
    return $hooks;
}

sub load_logging {
    my $self = shift;

    # avoid triggering log activity
    return if ($LOGGING_LOADED || $hooks->{'logging'});

    my $configdir  = $self->config_dir("logging");
    my $configfile = "$configdir/logging";
    my @loggers    = $self->conf->from_file($configfile, 'logging');

    $configdir  = $self->config_dir('plugin_dirs');
    $configfile = "$configdir/plugin_dirs";
    my @plugin_dirs = $self->conf->from_file($configfile, 'plugin_dirs');
    unless (@plugin_dirs) {
        my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
        @plugin_dirs = ("$name/plugins");
    }

    my @loaded;
    for my $logger (@loggers) {
        push @loaded, $self->_load_plugin($logger, @plugin_dirs);
    }

    foreach my $logger (@loaded) {
        $self->log(LOGINFO, "Loaded $logger");
    }

    $configdir  = $self->config_dir("loglevel");
    $configfile = "$configdir/loglevel";
    $TraceLevel = $self->conf->from_file($configfile, 'loglevel');

    unless (defined($TraceLevel) and $TraceLevel =~ /^\d+$/) {
        $TraceLevel = LOGWARN;    # Default if no loglevel file found.
    }

    $LOGGING_LOADED = 1;

    return @loggers;
}

sub trace_level { return $TraceLevel; }

sub init_logger {                 # needed for compatibility
    shift->trace_level();
}

sub log {
    my ($self, $trace, @log) = @_;
    $self->varlog($trace, join(" ", @log));
}

sub varlog {
    my ($self, $trace) = (shift, shift);
    my ($hook, $plugin, @log);
    if    ($#_ == 0) { (@log) = @_; }                 # log itself
    elsif ($#_ == 1) { ($hook, @log) = @_; }          # plus the hook
    else             { ($hook, $plugin, @log) = @_; } # from a plugin

    $self->load_logging;

    my ($rc) =
      $self->run_hooks_no_respond("logging", $trace, $hook, $plugin, @log)
      or return;

    return if $rc == DECLINED || $rc == OK;              # plugin success
    return if $trace > $TraceLevel;

    # no logging plugins registered, fall back to STDERR
    my $prefix =
        defined $plugin && defined $hook ? " ($hook) $plugin:"
      : defined $plugin ? " $plugin:"
      : defined $hook   ? " ($hook) running plugin:"
      :                   '';

    warn join(' ', $$ . $prefix, @log), "\n";
}

sub conf {
    my $self = shift;
    if (!$self->{_config}) {
        $self->{_config} = Qpsmtpd::Config->new();
    }
    return $self->{_config};
}

sub config {
    my $self = shift;
    return $self->conf->config($self, @_);
}

sub config_dir {
    my $self = shift;
    return $self->conf->config_dir(@_);
}

sub plugin_dirs {
    my $self        = shift;
    my @plugin_dirs = $self->config('plugin_dirs');

    unless (@plugin_dirs) {
        my ($path) = ($ENV{PROCESS} ? $ENV{PROCESS} : $0) =~ m!(.*?)/([^/]+)$!;
        @plugin_dirs = ("$path/plugins");
    }
    return @plugin_dirs;
}

sub load_plugins {
    my $self = shift;

    my @plugins = $self->config('plugins');
    my @loaded;

    if ($hooks->{queue}) {

        #$self->log(LOGWARN, "Plugins already loaded");
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

    # untaint the config data before passing it to plugins
    my ($safe_line) = $plugin_line =~ /^([ -~]+)$/    # all ascii printable
      or die "unsafe characters in config line: $plugin_line\n";
    my ($plugin, @args) = split /\s+/, $safe_line;

    if ($plugin =~ m/::/) {
        return $self->_load_package_plugin($plugin, $safe_line, \@args);
    }

    # regular plugins/$plugin plugin
    my $plugin_name = $plugin;
    $plugin =~ s/:\d+$//;    # after this point, only used for filename

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
    if (!defined &{"${package}::plugin_name"}) {
        for my $dir (@plugin_dirs) {
            next if !-e "$dir/$plugin";
            Qpsmtpd::Plugin->compile($plugin_name, $package,
                                     "$dir/$plugin", $self->{_test_mode},
                                     $plugin);
            if ($safe_line !~ /logging/) {
                $self->log(LOGDEBUG, "Loading $safe_line from $dir/$plugin");
            }
            last;
        }
        if (!defined &{"${package}::plugin_name"}) {
            die "Plugin $plugin_name not found in our plugin dirs (",
              join(', ', @plugin_dirs), ")";
        }
    }

    my $plug = $package->new();
    $plug->_register($self, @args);

    return $plug;
}

sub _load_package_plugin {
    my ($self, $plugin, $plugin_line, $args) = @_;

    # "full" package plugin (My::Plugin)
    my $package = $plugin;
    $package =~ s/[^_a-z0-9:]+//gi;
    my $eval =
      qq[require $package;\n] . qq[sub ${plugin}::plugin_name { '$plugin' }];
    $eval =~ m/(.*)/s;
    $eval = $1;
    eval $eval;    ## no critic (Eval)
    die "Failed loading $package - eval $@" if $@;

    if ($plugin_line !~ /logging/) {
        $self->log(LOGDEBUG, "Loading $package ($plugin_line)");
    }

    my $plug = $package->new();
    $plug->_register($self, @$args);

    return $plug;
}

sub transaction { return {}; }    # base class implements empty transaction

sub run_hooks {
    my ($self, $hook) = (shift, shift);
    if (my @local_hooks = $self->hooks($hook)) {
        $self->{_continuation} = [$hook, [@_], @local_hooks];
        return $self->run_continuation();
    }
    return $self->hook_responder($hook, [0, ''], [@_]);
}

sub run_hooks_no_respond {
    my ($self, $hook) = (shift, shift);
    if ($hooks->{$hook}) {
        my @r;
        for my $code ($self->hooks($hook)) {
            eval { (@r) = $code->{code}->($self, $self->transaction, @_); };
            if ($@) {
                warn("FATAL PLUGIN ERROR [" . $code->{name} . "]: ", $@);
                next;
            }
            last unless $r[0] == DECLINED;
        }
        $r[0] = DECLINED if not defined $r[0];
        return @r;
    }
    return (0, '');
}

sub run_continuation {
    my $self = shift;

    die "No continuation in progress" unless $self->{_continuation};
    my $todo = $self->{_continuation};
    $self->{_continuation} = undef;
    my $hook = shift @$todo || die "No hook in the continuation";
    my $args = shift @$todo || die "No hook args in the continuation";
    my @r;

    while (@$todo) {
        my $code = shift @$todo;

        $self->varlog(LOGDEBUG, $hook, $code->{name});
        my $tran = $self->transaction;
        eval { (@r) = $code->{code}->($self, $tran, @$args); };
        if ($@) {
            $self->log(LOGCRIT, "FATAL PLUGIN ERROR [" . $code->{name} . "]: ",
                       $@);
            next;
        }

        !defined $r[0]
          and $self->log(LOGERROR,
                             "plugin "
                           . $code->{name}
                           . " running the $hook hook returned undef!"
                        )
          and next;

        # note this is wrong as $tran is always true in the
        # current code...
        if ($tran) {
            my $tnotes = $tran->notes($code->{name});
            $tnotes->{"hook_$hook"}->{'return'} = $r[0]
              if (!defined $tnotes || ref $tnotes eq "HASH");
        }
        else {
            my $cnotes = $self->connection->notes($code->{name});
            $cnotes->{"hook_$hook"}->{'return'} = $r[0]
              if (!defined $cnotes || ref $cnotes eq "HASH");
        }

        if (   $r[0] == DENY
               or $r[0] == DENYSOFT
               or $r[0] == DENY_DISCONNECT
               or $r[0] == DENYSOFT_DISCONNECT)
        {
            $r[1] = "" if not defined $r[1];
            $self->log(LOGDEBUG,
                           "Plugin "
                         . $code->{name}
                         . ", hook $hook returned "
                         . return_code($r[0])
                         . ", $r[1]"
                      );
            $self->run_hooks_no_respond("deny", $code->{name}, $r[0], $r[1])
              unless ($hook eq "deny");
        }
        else {
            $r[1] = "" if not defined $r[1];
            $self->log(LOGDEBUG,
                           "Plugin "
                         . $code->{name}
                         . ", hook $hook returned "
                         . return_code($r[0])
                         . ", $r[1]"
                      );
            $self->run_hooks_no_respond("ok", $code->{name}, $r[0], $r[1])
              unless ($hook eq "ok");
        }

        last unless $r[0] == DECLINED;
    }
    $r[0] = DECLINED if not defined $r[0];

    # hook_*_parse() may return a CODE ref..
    # ... which breaks when splitting as string:
    @r = map { split /\n/ } @r unless (ref($r[1]) eq "CODE");
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
    my ($self, $hook, $code, $unshift) = @_;

    if ($unshift) {
        unshift @{$hooks->{$hook}}, $code;
        return;
    }

    push @{$hooks->{$hook}}, $code;
}

sub spool_dir {
    my $self = shift;

    return $Spool_dir if $Spool_dir;    # already set

    $self->log(LOGDEBUG, "Initializing spool_dir");
    $Spool_dir = $self->config('spool_dir') || $self->tildeexp('~/tmp/');

    $Spool_dir .= "/" if $Spool_dir !~ m!/$!;

    $Spool_dir =~ /^(.+)$/ or die "spool_dir not configured properly";
    $Spool_dir = $1;                    # cleanse the taint

    my $Spool_perms = $self->config('spool_perms') || '0700';

    if (!-d $Spool_dir) {               # create if it doesn't exist
        mkdir($Spool_dir, oct($Spool_perms))
          or die "Could not create spool_dir $Spool_dir: $!";
    }

    # Make sure the spool dir has appropriate rights
    if (((stat $Spool_dir)[2] & oct('07777')) != oct($Spool_perms)) {
        $self->log(LOGWARN,
                   "Permissions on spool_dir $Spool_dir are not $Spool_perms");
    }

    return $Spool_dir;
}

# For unique filenames. We write to a local tmp dir so we don't need
# to make them unpredictable.
my $transaction_counter = 0;

sub temp_file {
    my $self = shift;
    my $filename =
      $self->spool_dir() . join(":", time, $$, $transaction_counter++);
    return $filename;
}

sub temp_dir {
    my ($self, $mask) = @_;
    $mask ||= '0700';
    my $dirname = $self->temp_file();
    if (!-d $dirname) {
        mkdir($dirname, $mask)
            or die "Could not create temporary directory $dirname: $!";
    }
    return $dirname;
}

sub size_threshold {
    my $self = shift;
    return $Size_threshold if defined $Size_threshold;

    $Size_threshold = $self->config('size_threshold') || 0;
    $self->log(LOGDEBUG, "size_threshold set to $Size_threshold");
    return $Size_threshold;
}

sub authenticated {
    my $self = shift;
    return (defined $self->{_auth} ? $self->{_auth} : "");
}

sub auth_user {
    my $self = shift;
    return (defined $self->{_auth_user} ? $self->{_auth_user} : "");
}

sub auth_mechanism {
    my $self = shift;
    return (defined $self->{_auth_mechanism} ? $self->{_auth_mechanism} : "");
}

sub address {
    my $self = shift;
    my $addr = Qpsmtpd::Address->new(@_);
    $addr->qp($self);
    return $addr;
}

1;

__END__

=head1 NAME

Qpsmtpd - base class for the qpsmtpd mail server

=head1 DESCRIPTION

This is the base class for the qpsmtpd mail server.  See
L<http://smtpd.develooper.com/> and the I<README> file for more information.

=encoding UTF8

=head1 COPYRIGHT

Copyright 2001-2012 Ask Bjørn Hansen, Develooper LLC.  See the
LICENSE file for more information.

=cut

