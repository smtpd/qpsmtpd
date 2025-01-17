# Introduction

Plugins are the heart of qpsmtpd. The core implements only basic SMTP protocol
functionality. No useful function can be done by qpsmtpd without loading
plugins.

Plugins are loaded on startup where each of them register their interest in
various _hooks_ provided by the qpsmtpd core engine.

At least one plugin __must__ allow or deny the __RCPT__ command to enable
receiving mail. The `check_relay` plugin is the standard plugin for this.
Other plugins provide extra functionality related to this; for example the
`resolvable_fromhost` plugin.

## Loading Plugins

The list of plugins to load are configured in the _config/plugins_
configuration file. One plugin per line, empty lines and lines starting
with _#_ are ignored. The order they are loaded is the same as given
in this config file. This is also the order the registered _hooks_
are run. The plugins are loaded from the `plugins/` directory or
from a subdirectory of it. If a plugin should be loaded from such a
subdirectory, the directory must also be given, like the
`virus/clamdscan` in the example below. Alternate plugin directories
may be given in the `config/plugin_dirs` config file, one directory
per line, these will be searched first before using the builtin fallback
of `plugins/` relative to the qpsmtpd root directory.

Some plugins may be configured by passing arguments in the `plugins`
config file.

A plugin can be loaded two or more times with different arguments by adding
_:N_ to the plugin filename, with _N_ being a number, usually starting at
_0_.

Another method to load a plugin is to create a valid perl module, drop this
module in perl's `@INC` path and give the name of this module as
plugin name. The only restriction to this is, that the module name __must__
contain _::_, e.g. `My::Plugin` would be ok, `MyPlugin` not. Appending of
_:0_, _:1_, ... does not work with module plugins.

    check_relay
    virus/clamdscan
    spamassassin reject_threshold 7
    my_rcpt_check example.com
    my_rcpt_check:0 example.org
    My::Plugin

# Anatomy of a plugin

A plugin has at least one method, which inherits from the
`Qpsmtpd::Plugin` object. The first argument for this method is always the
plugin object itself (and usually called `$self`). The most simple plugin
has one method with a predefined name which just returns one constant.

    # plugin temp_disable_connection
    sub hook_connect {
       return(DENYSOFT, "Sorry, server is temporarily unavailable.");
    }

While this is a valid plugin, it is not very useful except for rare
circumstances. So let us see what happens when a plugin is loaded.

## Initialisation

After the plugin is loaded the `init()` method of the plugin is called,
if present. The arguments passed to `init()` are

- $self

    the current plugin object, usually called `$self`

- $qp

    the Qpsmtpd object, usually called `$qp`.

- @args

    the values following the plugin name in the `plugins` config, split by
    white space. These arguments can be used to configure the plugin with
    default and/or static config settings, like database paths,
    timeouts, ...

This is mainly used for inheriting from other plugins, but may be used to do
the same as in `register()`.

The next step is to register the hooks the plugin provides. Any method which
is named `hook_$hookname` is automagically added.

Plugins should be written using standard named hook subroutines. This
allows them to be overloaded and extended easily. Because some of the
callback names have characters invalid in subroutine names , they must be
translated. The current translation routine is `s/\W/_/g;`, see
["Hook - Subroutine translations"](#hook-subroutine-translations) for more info. If you choose
not to use the default naming convention, you need to register the hooks in
your plugin in the `register()` method (see below) with the
`register_hook()` call on the plugin object.

    sub register {
      my ($self, $qp, @args) = @_;
      $self->register_hook("mail", "mail_handler");
      $self->register_hook("rcpt", "rcpt_handler");
    }
    sub mail_handler { ... }
    sub rcpt_handler { ... }

The `register()` method is called last. It receives the same arguments as
`init()`. There is no restriction, what you can do in `register()`, but
creating database connections and reuse them later in the process may not be
a good idea. This initialisation happens before any `fork()` is done.
Therefore the file handle will be shared by all qpsmtpd processes and the
database will probably be confused if several different queries arrive on
the same file handle at the same time (and you may get the wrong answer, if
any). This is also true for the pperl flavor but
not for `qpsmtpd` started by (x)inetd or tcpserver.

In short: don't do it if you want to write portable plugins.

## Hook - Subroutine translations

As mentioned above, the hook name needs to be translated to a valid perl
`sub` name. This is done like

    ($sub = $hook) =~ s/\W/_/g;
    $sub = "hook_$sub";

Some examples follow, for a complete list of available (documented ;-))
hooks (method names), use something like

    $ perl -lne 'print if s/^=head2\s+(hook_\S+)/$1/' docs/plugins.pod

All valid hooks are defined in `lib/Qpsmtpd/Plugins.pm`, `our @hooks`.

### Translation table

    hook                          method
    ----------                    ------------
    config                        hook_config
    queue                         hook_queue
    data                          hook_data
    data_post                     hook_data_post
    quit                          hook_quit
    rcpt                          hook_rcpt
    mail                          hook_mail
    ehlo                          hook_ehlo
    helo                          hook_helo
    auth                          hook_auth
    auth-plain                    hook_auth_plain
    auth-login                    hook_auth_login
    auth-cram-md5                 hook_auth_cram_md5
    connect                       hook_connect
    reset_transaction             hook_reset_transaction
    unrecognized_command          hook_unrecognized_command

## Inheritance

Inheriting methods from other plugins is an advanced topic. You can alter
arguments for the underlying plugin, prepare something for the _real_
plugin or skip a hook with this. Instead of modifying `@ISA`
directly in your plugin, use the `isa_plugin()` method from the
`init()` subroutine.

    # rcpt_ok_child
    sub init {
      my ($self, $qp, @args) = @_;
      $self->isa_plugin("rcpt_ok");
    }

    sub hook_rcpt {
      my ($self, $transaction, $recipient) = @_;
      # do something special here...
      $self->SUPER::hook_rcpt($transaction, $recipient);
    }

See also chapter `Changing return values` and
`contrib/vetinari/rcpt_ok_maxrelay` in SVN.

## Config files

Most of the existing plugins fetch their configuration data from files in the
`config/` sub directory. This data is read at runtime and may be changed
without restarting qpsmtpd.
__(FIXME: caching?!)__
The contents of the files can be fetched via

    @lines = $self->qp->config("my_config");

All empty lines and lines starting with `#` are ignored.

If you don't want to read your data from files, but from a database you can
still use this syntax and write another plugin hooking the `config`
hook.

## Logging

Log messages can be written to the log file (or STDERR if you use the
`logging/warn` plugin) with

    $self->log($loglevel, $logmessage);

The log level is one of (from low to high priority)

- LOGDEBUG
- LOGINFO
- LOGNOTICE
- LOGWARN
- LOGERROR
- LOGCRIT
- LOGALERT
- LOGEMERG

While debugging your plugins, set your plugins loglevel to LOGDEBUG. This
will log every logging statement within your plugin.

For more information about logging, see `docs/logging.pod`.

## Information about the current plugin

Each plugin inherits the public methods from `Qpsmtpd::Plugin`.

- plugin\_name()

    Returns the name of the currently running plugin

- hook\_name()

    Returns the name of the running hook

- auth\_user()

    Returns the name of the user the client is authed as (if authentication is
    used, of course)

- auth\_mechanism()

    Returns the auth mechanism if authentication is used

- connection()

    Returns the `Qpsmtpd::Connection` object associated with the current
    connection

- transaction()

    Returns the `Qpsmtpd::Transaction` object associated with the current
    transaction

## Temporary Files

The temporary file and directory functions can be used for plugin specific
workfiles and will automatically be deleted at the end of the current
transaction.

- temp\_file()

    Returns a unique name of a file located in the default spool directory,
    but does not open that file (i.e. it is the name not a file handle).

- temp\_dir()

    Returns the name of a unique directory located in the default spool
    directory, after creating the directory with 0700 rights. If you need a
    directory with different rights (say for an antivirus daemon), you will
    need to use the base function `$self->qp->temp_dir()`, which takes a
    single parameter for the permissions requested (see [mkdir](https://metacpan.org/pod/mkdir) for details).
    A directory created like this will not be deleted when the transaction
    is ended.

- spool\_dir()

    Returns the configured system-wide spool directory.

## Connection and Transaction Notes

Both may be used to share notes across plugins and/or hooks. The only real
difference is their life time. The connection notes start when a new
connection is made and end, when the connection ends. This can, for example,
be used to count the number of none SMTP commands. The plugin which uses
this is the `count_unrecognized_commands` plugin from the qpsmtpd core
distribution.

The transaction note starts after the __MAIL FROM:__ command and are just
valid for the current transaction, see below in the `reset_transaction`
hook when the transaction ends.

# Return codes

Each plugin must return an allowed constant for the hook and (usually)
optionally a \`\`message'' for the client.
Generally all plugins for a hook are processed until one returns
something other than _DECLINED_.

Plugins are run in the order they are listed in the `plugins`
configuration file.

The return constants are defined in `Qpsmtpd::Constants` and have
the following meanings:

- DECLINED

    Plugin declined work; proceed as usual. This return code is _always allowed_
    unless noted otherwise.

- OK

    Action allowed.

- DENY

    Action denied.

- DENYSOFT

    Action denied; return a temporary rejection code (say __450__ instead
    of __550__).

- DENY\_DISCONNECT

    Action denied; return a permanent rejection code and disconnect the client.
    Use this for "rude" clients. Note that you're not supposed to do this
    according to the SMTP specs, but bad clients don't listen sometimes.

- DENYSOFT\_DISCONNECT

    Action denied; return a temporary rejection code and disconnect the client.
    See note above about SMTP specs.

- DONE

    Finishing processing of the request. Usually used when the plugin sent the
    response to the client.
