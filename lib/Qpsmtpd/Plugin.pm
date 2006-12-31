package Qpsmtpd::Plugin;
use Qpsmtpd::Constants;
use strict;
use vars qw(%symbols);

# more or less in the order they will fire
our @hooks = qw(
    logging config pre-connection connect ehlo_parse ehlo
    helo_parse helo auth_parse auth auth-plain auth-login auth-cram-md5
    rcpt_parse rcpt_pre rcpt mail_parse mail mail_pre 
    data data_post queue_pre queue queue_post
    quit reset_transaction disconnect post-connection
    unrecognized_command deny ok
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
  ### someone test this please:
  # return if $self->plugin_is_loaded($newPackage);

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

=head1 SKIP PLUGINS API

These functions allow to disable and re-enable loaded plugins. Loading 
plugins after the initial loading phase is not possible. The earliest 
place to disable a plugin is in C<hook_connect()>. 

If you want to run a plugin just for some clients, load it like a usual 
plugin and either hook it to the C<hook_connect()> (or any later hook) 
and disable it there, use the C<skip_plugins> plugin or write your own 
disabling plugin.

These modifications of disabling/re-enabling a plugin are valid for the
full connection, not transaction! For transaction based disabling of plugins,
use the C<reset_transaction> hook to reset the list of disabled plugins. 

A small warning: the C<reset_transaction> hook is called at least three
times: after the client sent the C<(HE|EH)LO>, every time the client
issues a C<MAIL FROM:> and after the mail was queued (or rejected by a 
C<data_post> hook). Don't forget it is also called after C<RSET> and 
connection closing (e.g. after C<QUIT>).

=over 7

=item plugin_is_loaded( $plugin )

Returns true, if the given (escaped) plugin name is a loaded plugin

=cut

sub plugin_is_loaded {
    my ($self, $plugin) = @_;
    $plugin =~ s/^Qpsmtpd::Plugin:://; # for _loaded();
    # each plugin has a sub called "plugin_name()", see compile() above...
    # ... this restricts qpsmtpd a bit: No module named 
    # Qpsmtpd::Plugin(|::Something) must have a sub "plugin_name()", or 
    # it will be returned as a loaded plugin...
    return defined &{"Qpsmtpd::Plugin::${plugin}::plugin_name"}; 
}

=item plugin_status( $plugin )

Shows the status of the given plugin. It returns undef if no plugin name 
given or the plugin is not loaded, "0" if plugin is loaded, but disabled 
and "1" if the plugin is loaded and active. The plugin name must be escaped
by B<escape_plugin()>.

=cut

sub plugin_status {
    my ($self, $plugin) = @_;
    return undef unless $plugin;
    return undef unless $self->plugin_is_loaded($plugin);
    my $skip = $self->qp->connection->notes('_skip_plugins') || {};
    return 0 if (exists $skip->{$plugin} and $skip->{$plugin});
    return 1;
}

=item loaded_plugins( )

This returns a hash. Keys are (escaped, see below) plugin names of loaded 
plugins. The value tells you if the plugin is currently active (1) or 
disabled (0).

=cut

sub loaded_plugins {
    my $self = shift;
    # all plugins are in their own class "below" Qpsmtpd::Plugin,
    # so we start searching the symbol table at this point
    my %plugins = map { 
                        s/^Qpsmtpd::Plugin:://; 
                        ($_, 1) 
                      } $self->_loaded("Qpsmtpd::Plugin");
    foreach ($self->disabled_plugins) {
        $plugins{$_} = 0;
    }
    return %plugins;
}

sub _loaded {
    my $self   = shift;
    my $base   = shift;
    my @loaded = ();
    my (@sub, $symbol);
    # let's see what's in this name space
    no strict 'refs';
    local (*symbols) = *{"${base}::"};
    use strict 'refs';
    foreach my $name (values %symbols) { 
        # $name is read only while walking the stash

        # not a class name? ok, next 
        ($symbol = $name) =~ s/^\*(.*)::$/$1/ || next; 
        next if $symbol eq "Qpsmtpd::Plugin";

        # in qpsmtpd we have no way of loading a plugin with the same
        # name as a sub directory inside the ./plugins dir, so we can safely
        # use either the list of sub classes or the class itself we're 
        # looking at (unlike perl, e.g. Qpsmtpd.pm <-> Qpsmtpd/Plugin.pm).
        @sub = $self->_loaded($symbol);

        if (@sub) {
            push @loaded, @sub;
        }
        else {
            # is this really a plugin?
            next unless $self->plugin_is_loaded($symbol);
            push @loaded, $symbol;
        }
    }
    return @loaded;
}

=item escape_plugin( $plugin_name )

Turns a plugin filename into the way it is used inside qpsmtpd. This needs to
be done before you B<plugin_disable()> or B<plugin_enable()> a plugin. To 
see if a plugin is loaded, use something like

 my %loaded = $self->loaded_plugins;
 my $wanted = $self->escape_plugin("virus/clamav");
 if (exists $loaded{$wanted}) {
   ...
 }
... or shorter:

 if ($self->plugin_is_loaded($self->escape_plugin("virus/clamav"))) {
   ...
 }

=cut

sub escape_plugin {
    my $self        = shift;
    my $plugin_name = shift;
    # "stolen" from Qpsmtpd.pm
    # Escape everything into valid perl identifiers
    $plugin_name =~ s/([^A-Za-z0-9_\/])/sprintf("_%2x",unpack("C",$1))/eg;

    # second pass cares for slashes and words starting with a digit
    $plugin_name =~ s{
            (/+)       # directory
            (\d?)      # package's first character
           }[
             "::" . (length $2 ? sprintf("_%2x",unpack("C",$2)) : "")
            ]egx;
    return $plugin_name;
}

=item disabled_plugins( )

This returns a list of all plugins which are disabled for the current 
connection. 

=cut

sub disabled_plugins {
    my $self    = shift;
    my @skipped = ();
    my $skip    = $self->qp->connection->notes('_skip_plugins') || {};
    foreach my $s (keys %{$skip}) {
        push @skipped, $s if $skip->{$s};
    }
    return @skipped;
}

=item plugin_disable( $plugin )

B<plugin_disable()> disables a (loaded) plugin, it requires the plugin name
to be escaped by B<escape_plugin()>. It returns true, if the given plugin
name is a loaded plugin (and disables it of course).

=cut

sub plugin_disable {
    my ($self, $plugin) = @_;
    # do a basic check if the supplied plugin name is really a plugin
    return 0 unless $self->plugin_is_loaded($plugin);

    my $skip = $self->qp->connection->notes('_skip_plugins') || {};
    $skip->{$plugin} = 1;
    $self->qp->connection->notes('_skip_plugins', $skip);
    return 1;
}

=item plugin_enable( $plugin )

B<plugin_enable()> re-enables a (loaded) plugin, it requires the plugin name
to be escaped by B<escape_plugin()>. It returns "0", if the given plugin
name is not a loaded plugin. Else it returns "1" after enabling.

=cut

sub plugin_enable {
    my ($self, $plugin) = @_;
    return 0 unless $self->plugin_is_loaded($plugin);

    my $skip = $self->qp->connection->notes('_skip_plugins') || {};
    $skip->{$plugin} = 0;
    $self->qp->connection->notes('_skip_plugins', $skip);
    return 1;
}

=back

=cut

1;
