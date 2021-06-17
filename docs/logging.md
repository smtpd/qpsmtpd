# qpsmtpd logging; user documentation

Qpsmtpd has a modular logging system. Here's a few things you need to know:

    * The built-in logging prints log messages to STDERR.
    * A variety of logging plugins is included, each with its own behavior.
    * When a logging plugin is enabled, the built-in logging is disabled.
    * plugins/logging/warn mimics the built-in logging.
    * Multiple logging plugins can be enabled simultaneously.

Read the POD within each logging plugin (perldoc plugins/logging/__NAME__)
to learn if it tickles your fancy.

## enabling plugins

To enable logging plugins, edit the file _config/logging_ and uncomment the
entries for the plugins you wish to use.

## logging level

The 'master switch' for loglevel is _config/loglevel_. Qpsmtpd and active
plugins will output all messages that are less than or equal to the value
specified. The log levels correspond to syslog levels:

    LOGDEBUG   = 7
    LOGINFO    = 6
    LOGNOTICE  = 5
    LOGWARN    = 4
    LOGERROR   = 3
    LOGCRIT    = 2
    LOGALERT   = 1
    LOGEMERG   = 0
    LOGRADAR   = 0

Level 6, LOGINFO, is the level at which most servers should start logging. At
level 6, each plugin should log one and occasionally two entries that
summarize their activity. Here's a few sample lines:

    (connect) ident::geoip: SA, Saudi Arabia
    (connect) ident::p0f: Windows 7 or 8
    (connect) earlytalker: pass: remote host said nothing spontaneous
    (data_post) domainkeys: skip: unsigned
    (data_post) spamassassin: pass, Spam, 21.7 < 100
    (data_post) dspam: fail: agree, Spam, 1.00 c
    552 we agree, no spam please (#5.6.1)

Three plugins fired during the SMTP connection phase and 3 more ran during the
data\_post phase. Each plugin emitted one entry stating their findings.

If you aren't processing the logs, you can save some disk I/O by reducing the
loglevel, so that the only messages logged are ones that indicate a human
should be taking some corrective action.

## log location

If qpsmtpd is started using the distributed run file (cd ~smtpd; ./run), then
you will see the log entries printed to your terminal. This solution works
great for initial setup and testing and is the simplest case.

A typical way to run qpsmtpd is as a supervised process with daemontools. If
daemontools is already set up, setting up qpsmtpd may be as simple as:

`ln -s /usr/home/smtpd /var/service/`

If svcscan is running, the symlink will be detected and tcpserver will
run the 'run' files in the ./ and ./log directories. Any log entries
emitted will get handled per the instructions in log/run. The default
location specified in log/run is log/main/current.

## plugin loglevel

Most plugins support a loglevel argument after their config/plugins entry.
The value can be a whole number (N) or a relative number (+/-N), where
N is a whole number from 0-7. See the descriptions of each below.

`ident/p0f loglevel 5`

`ident/p0f loglevel -1`

ATTN plugin authors: To support loglevel in your plugin, you must store the
loglevel settings from the plugins/config entry $self->{\_args}{loglevel}. A
simple and recommended example is as follows:

    sub register {
      my ( $self, $qp ) = (shift, shift);
      $self->log(LOGERROR, "Bad arguments") if @_ % 2;
      $self->{_args} = { @_ };
    }

### whole number

If loglevel is a whole number, then all log activity in the plugin is logged
at that level, regardless of the level the plugin author selected. This can
be easily understood with a couple examples:

The master loglevel is set at 6 (INFO). The mail admin sets a plugin loglevel
to 7 (DEBUG). No messages from that plugin are emitted because DEBUG log
entries are not <= 6 (INFO).

The master loglevel is 6 (INFO) and the plugin loglevel is set to 5 or 6. All
log entries will be logged because 5 is <= 6.

This behavior is very useful to plugin authors. While testing and monitoring
a plugin, they can set the level of their plugin to log everything. To return
to 'normal' logging, they just update their config/plugins entry.

### relative

Relative loglevel arguments adjust the loglevel of each logging call within
a plugin. A value of _loglevel +1_ would make every logging entry one level
less severe, where a value of _loglevel -1_ would make every logging entry
one level more severe.

For example, if a plugin has a loglevel setting of -1 and that same plugin
logged a LOGDEBUG, it would instead be a LOGINFO message. Relative values
makes it easy to control the verbosity and/or severity of individual plugins.

# qpsmtpd logging system; developer documentation

Qpsmtpd now (as of 0.30-dev) supports a plugable logging architecture, so
that different logging plugins can be supported.  See the example logging
plugins in plugins/logging, specifically the ["logging/warn" in plugins](https://metacpan.org/pod/plugins#logging-warn) and
["logging/adaptive" in plugins](https://metacpan.org/pod/plugins#logging-adaptive) files for examples of how to write your own
logging plugins.

# plugin authors

While plugins can log anything they like, a few logging conventions in use:

- at LOGINFO, log a single entry summarizing their disposition
- log messages are prefixed with keywords: pass, fail, skip, error
    - pass: tests were run and the message passed
    - fail: tests were run and the message failed
    - fail, tolerated: tests run, msg failed, reject disabled
    - skip: tests were not run
    - error: tried to run tests but failure(s) encountered
    - info: additional info, not to be used for plugin summary
- when tests fail and reject is disabled, use the 'fail, tolerated' prefix

When these conventions are adhered to, the logs/summarize tool outputs each
message as a single row, with a small x showing failed tests and a large X
for failed tests that caused message rejection.

# Internal support for pluggable logging

Any code in the core can call `$self-`log()> and those log lines will be
dispatched to each of the registered logging plugins.  When `log()` is
called from a plugin, the plugin and hook names are automatically included
in the parameters passed the logging hooks.  All plugins which register for
the logging hook should expect the following parameters to be passed:

    $self, $transaction, $trace, $hook, $plugin, @log

where those terms are:

- `$self`

    The object which was used to call the log() method; this can be any object
    within the system, since the core code will automatically load logging
    plugins on behalf of any object.

- `$transaction`

    This is the current SMTP transaction (defined as everything that happens
    between HELO/EHLO and QUIT/RSET).  If you want to defer outputting certain
    log lines, you can store them in the transaction object, but you will need
    to bind the `reset_transaction` hook in order to retrieve that information
    before it is discarded when the transaction is closed (see the
    ["adaptive" in logging](https://metacpan.org/pod/logging#adaptive) plugin for an example of doing this).

- `$trace`

    This is the log level (as shown in config.sample/loglevel) that the caller
    asserted when calling log().  If you want to output the textural
    representation (e.g. `LOGERROR`) of this in your log messages, you can use
    the log\_level() function exported by Qpsmtpd::Constants (which is
    automatically available to all plugins).

- `$hook`

    This is the hook that is currently being executed.  If log() is called by
    any core code (i.e. not as part of a hook), this term will be `undef`.

- `$plugin`

    This is the plugin name that executed the log().  Like `$hook`, if part of
    the core code calls log(), this wil be `undef`.  See ["warn" in logging](https://metacpan.org/pod/logging#warn) for a
    way to prevent logging your own plugin's log entries from within that
    plugin (the system will not infinitely recurse in any case).

- `@log`

    The remaining arguments are as passed by the caller, which may be a single
    term or may be a list of values.  It is usually sufficient to call
    `join(" ",@log)` to deal with these terms, but it is possible that some
    plugin might pass additional arguments with signficance.

Note: if you register a handler for certain hooks, e.g. `deny`, there may
be additional terms passed between `$self` and `$transaction`.  See
["adaptive" in logging](https://metacpan.org/pod/logging#adaptive) for and example.
