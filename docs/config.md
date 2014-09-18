# Qpsmtpd configuration

The default way of setting config values is placing files with the
name of the config variable in the config directory `config/`, like
qmail's `/var/qmail/control/` directory. NB: `/var/qmail/control` (or
`$ENV{QMAIL}/control`) is used if a file does not exist in `config/`.
The location of the `config/` directory can be set via the
`QPSMTPD_CONFIG` environment variable and defaults to the current
working directory.

Any empty line or lines starting with `#` are ignored. You may use a
plugin which hooks the `config` hook to store the settings in some other
way. See ["plugins.pod" in docs](https://metacpan.org/pod/docs#plugins.pod) and ["hooks.pod" in docs](https://metacpan.org/pod/docs#hooks.pod) for more info on this.
Some settings still have to go in files, because they are loaded before
any plugin can return something via the `config` hook: `me`, `logging`,
`plugin_dirs` and of course `plugins`.

## Core settings

These settings are used by the qpsmtpd core. Any other setting is (hopefully)
documented by the corresponding plugin. Some settings of important plugins
are shown below in ["Plugin settings"](#plugin-settings).

- plugins

    The main config file, where all used plugins and their arguments are listed.

- me

    Sets the hostname which is used all over the place: in the greeting message,
    the _Received: _header, ...
    Default is whatever Sys::Hostname's hostname() returns.

- plugin\_dirs

    Where to search for plugins (one directory per line), defaults to `./plugins`.

- logging

    Sets the primary logging destination, see `plugins/logging/*`. Format
    is the same as it's used for the `plugins` config file. __NOTE:__ only
    the first non empty line is used (lines starting with `#` are counted
    as empty).

- loglevel

    This is not used anymore, _only_ if no `logging/` plugin is in use. Use a
    logging plugin.

- databytes

    Maximum size a message may be. Without this setting, there is no limit on the
    size. Should be something less than the backend MTA has set as it's maximum
    message size (if there is one).

- size\_threshold

    When a message is greater than the size given in this config file, it will be
    spooled to disk. You probably want to enable spooling to disk for most virus
    scanner plugins and `spamassassin`.

- smtpgreeting

    Override the default SMTP greeting with this string.

- spool\_dir

    Where temporary files are stored, defaults to `~/tmp/`.

- spool\_perms

    Permissions of the _spool\_dir_, default is `0700`. You probably have to
    change the defaults for some scanners (e.g. the `clamdscan` plugin).

- timeout
- timeoutsmtpd

    Set the timeout for the clients, `timeoutsmtpd` is the qmail smtpd control
    file, `timeout` the qpsmtpd file. Default is 1200 seconds.

- tls\_before\_auth

    If set to a true value, clients will have to initiate an SSL secured
    connection before any auth succeeds, defaults to `0`.

## Plugin settings files

- rcpthosts, morercpthosts

    Plugin: `rcpt_ok`

    Domains listed in these files will be accepted as valid local domains,
    anything else is rejected with a `Relaying denied` message. If an entry
    in the `rcpthosts` file starts with a `.`, mails to anything ending with
    this string will be accepted, e.g.:

        example.com
        .example.com

    will accept mails for `user@example.com` and `user@something.example.com`.
    The `morercpthosts` file is just checked for exact (case insensitive)
    matches.

- `hosts_allow`

    Plugin: `hosts_allow`.

    Don't use this config file. The plugin itself is required to set the
    maximum number of concurrent connections. This config setting should
    only be used for some extremly rude clients: if list is too big it will
    slow down accepting new connections.

- relayclients
- morerelayclients

    Plugin: `check_relay`

    Allow relaying for hosts listed in this file. The `relayclients` file accepts
    IPs and CIDR entries. The `morercpthosts` file accepts IPs and `prefixes`
    like `192.168.2.` (note the trailing dot!). With the given example any host
    which IP starts with `192.168.2.` may relay via us.

- `dnsbl_zones`

    Plugin: `dnsbl`

    This file specifies the RBL zones list, used by the dnsbl plugin. Ihe IP
    address of each connecting host will be checked against each zone given.
    A few sample DNSBLs are listed in the sample config file, but you should
    evaluate the efficacy and listing policies of a DNSBL before using it.

    See also `dnsbl_allow` and `dnsbl_rejectmsg` in the documentation of the
    `dnsbl` plugin

- `resolvable_fromhost`

    Plugin: `resolvable_fromhost`

    Reject sender addresses where the MX is unresolvable, i.e. a boolean value
    is the only value in this file. If the MX resolves to something, reject the
    sender address if it resolves to something listed in the
    `invalid_resolvable_fromhost` config file. The _invalid\_resolvable\_fromhost_
    expects IP addresses or CIDR (i.e. `network/mask` values) one per line, IPv4
    only currenlty.

## Plugin settings arguments

These are arguments that can be set on the config/plugins line, after the name
of the plugin. These config options are available to all plugins.

- loglevel

    Adjust the quantity of logging for the plugin. See docs/logging.pod

- reject

        plugin reject [ 0 | 1 | naughty ]

    Should the plugin reject mail?

    The special 'naughty' case will mark the connection as a naughty. Most plugins
    skip processing naughty connections. Filtering plugins can learn from them.
    Naughty connections are terminated up by the __naughty__ plugin.

    Plugins that use $self->get\_reject() or $self->get\_reject\_type() will
    automatically honor this setting.

- `reject_type`

        plugin reject_type [ perm | temp | disconnect | temp_disconnect ]

    Default: perm

    Values with temp in the name return a 4xx code and the others return a 5xx
    code.

    The `reject_type` argument and the corresponding `get_reject_type()` method
    provides a standard way for plugins to automatically return the selected
    rejection type, as chosen by the config setting, the plugin author, or the
    `get_reject_type()` method.

    Plugins that are updated to use the `$self->get_reject()` or
    `$self->get_reject_type()` methods will automatically honor this setting.
