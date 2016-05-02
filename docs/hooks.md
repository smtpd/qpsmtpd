# SMTP hooks

This section covers the hooks, which are run in a normal SMTP connection.
The order of these hooks is like you will (probably) see them, while a mail
is received.

Every hook receives a `Qpsmtpd::Plugin` object of the currently
running plugin as the first argument. A `Qpsmtpd::Transaction` object is
the second argument of the current transaction in the most hooks, exceptions
are noted in the description of the hook. If you need examples how the
hook can be used, see the source of the plugins, which are given as
example plugins.

__NOTE__: for some hooks (post-fork, post-connection, disconnect, deny, ok) the
return values are ignored. This does __not__ mean you can return anything you
want. It just means the return value is discarded and you can not disconnect
a client with `DENY_DISCONNECT`. The rule to return `DECLINED` to run the
next plugin for this hook (or return `OK` / `DONE` to stop processing)
still applies.

## hook\_pre\_connection

Called by a controlling process (e.g. forkserver or prefork) after accepting
the remote server, but before beginning a new instance (or handing the
connection to the worker process).

Useful for load-management and rereading large config files at some
frequency less than once per session.

This hook is available in `qpsmtpd-forkserver` and `qpsmtpd-prefork` flavors.

__NOTE:__ You should not use this hook to do major work and / or use lookup
methods which (_may_) take some time, like DNS lookups. This will slow down
__all__ incoming connections, no other connection will be accepted while this
hook is running!

Arguments this hook receives are:

    my ($self,$transaction,%args) = @_;
    # %args is:
    # %args = ( remote_ip    => inet_ntoa($iaddr),
    #           remote_port  => $port,
    #           local_ip     => inet_ntoa($laddr),
    #           local_port   => $lport,
    #           max_conn_ip  => $MAXCONNIP,
    #           child_addrs  => [values %childstatus],
    #         );

__NOTE:__ the `$transaction` is of course `undef` at this time.

Allowed return codes are

- DENY / DENY\_DISCONNECT

    returns a __550__ to the client and ends the connection

- DENYSOFT / DENYSOFT\_DISCONNECT

    returns a __451__ to the client and ends the connection

Anything else is ignored.

Example plugins are `hosts_allow` and `connection_time`.

## hook\_connect

It is called at the start of a connection before the greeting is sent to
the connecting client.

Arguments for this hook are

    my $self = shift;

__NOTE:__ in fact you get passed two more arguments, which are `undef` at this
early stage of the connection, so ignore them.

Allowed return codes are

- OK

    Stop processing plugins, give the default response

- DECLINED

    Process the next plugin

- DONE

    Stop processing plugins and dont give the default response, i.e. the plugin
    gave the response

- DENY

    Return hard failure code and disconnect

- DENYSOFT

    Return soft failure code and disconnect

Example plugin for this hook is the `check_relay` plugin.

## hook\_helo / hook\_ehlo

It is called after the client sent __EHLO__ (hook\_ehlo) or __HELO__ (hook\_helo)
Allowed return codes are

- DENY

    Return a 550 code

- DENYSOFT

    Return a __450__ code

- DENY\_DISCONNECT / DENYSOFT\_DISCONNECT

    as above but with disconnect

- DONE

    Qpsmtpd wont do anything, the plugin sent the message

- DECLINED

    Qpsmtpd will send the standard __EHLO__/__HELO__ answer, of course only
    if all plugins hooking _helo/ehlo_ return _DECLINED_.

Arguments of this hook are

    my ($self, $transaction, $host) = @_;
    # $host: the name the client sent in the
    # (EH|HE)LO line

__NOTE:__ `$transaction` is `undef` at this point.

## hook\_mail\_pre

After the `MAIL FROM:` line sent by the client is broken into
pieces by the `hook_mail_parse()`, this hook recieves the results.
This hook may be used to pre-accept adresses without the surrounding
`<>` (by adding them) or addresses like `<user@example.com.>` or `<user@example.com >` by
removing the trailing "." / " ".

Expected return values are `OK` and an address which must be parseable
by `Qpsmtpd::Address->parse()` on success or any other constant to
indicate failure.

Arguments are

    my ($self, $transaction, $addr) = @_;

## hook\_mail

Called right after the envelope sender line is parsed (the `MAIL FROM:`
command). The plugin gets passed a `Qpsmtpd::Address` object, which means
the parsing and verifying the syntax of the address (and just the syntax,
no other checks) is already done. Default is to allow the sender address.
The remaining arguments are the extensions defined in RFC 1869 (if sent by
the client).

__NOTE:__ According to the SMTP protocol, you can not reject an invalid
sender until after the __RCPT__ stage (except for protocol errors, i.e.
syntax errors in address). So store it in an `$transaction->note()` and
process it later in an rcpt hook.

Allowed return codes are

- OK

    sender allowed

- DENY

    Return a hard failure code

- DENYSOFT

    Return a soft failure code

- DENY\_DISCONNECT / DENYSOFT\_DISCONNECT

    as above but with disconnect

- DECLINED

    next plugin (if any)

- DONE

    skip further processing, plugin sent response

Arguments for this hook are

    my ($self,$transaction, $sender, %args) = @_;
    # $sender: an Qpsmtpd::Address object for
    # sender of the message

Example plugins for the `hook_mail` are `resolvable_fromhost`
and `badmailfrom`.

## hook\_rcpt\_pre

See `hook_mail_pre`, s/MAIL FROM:/RCPT TO:/.

## hook\_rcpt

This hook is called after the client sent an `RCPT TO:` command (after
parsing the line). The given argument is parsed by *Qpsmtpd::Address*,
then this hook is called. Default is to deny the mail with a soft error
code. The remaining arguments are the extensions defined in RFC 1869
(if sent by the client).

Allowed return codes

- OK

    recipient allowed

- DENY

    Return a hard failure code, for example for an _User does not exist here_
    message.

- DENYSOFT

    Return a soft failure code, for example if the connect to a user lookup
    database failed

- DENY\_DISCONNECT / DENYSOFT\_DISCONNECT

    as above but with disconnect

- DONE

    skip further processing, plugin sent response

Arguments are

    my ($self, $transaction, $recipient, %args) = @_;
    # $rcpt = Qpsmtpd::Address object with
    # the given recipient address

Example plugin is `rcpt_ok`.

## hook\_data

After the client sent the __DATA__ command, before any data of the message
was sent, this hook is called.

__NOTE:__ This hook, like __EHLO__, __VRFY__, __QUIT__, __NOOP__, is an
endpoint of a pipelined command group (see RFC 1854) and may be used to
detect \`\`early talkers''. Since svn revision 758 the `earlytalker`
plugin may be configured to check at this hook for \`\`early talkers''.

Allowed return codes are

- DENY

    Return a hard failure code

- DENYSOFT

    Return a soft failure code

- DENY\_DISCONNECT / DENYSOFT\_DISCONNECT

    as above but with disconnect

- DONE

    Plugin took care of receiving data and calling the queue (not recommended)

    __NOTE:__ The only real use for _DONE_ is implementing other ways of
    receiving the message, than the default... for example the CHUNKING SMTP
    extension (RFC 1869, 1830/3030) ... a plugin for this exists at
    http://svn.perl.org/qpsmtpd/contrib/vetinari/experimental/chunking, but it
    was never tested \`\`in the wild''.

Arguments:

    my ($self, $transaction) = @_;

Example plugin is `greylisting`.

## hook\_received\_line

If you wish to provide your own Received header line, do it here. You can use
or discard any of the given arguments (see below).

Allowed return codes:

- OK, $string

    use this string for the Received header.

- anything else

    use the default Received header

Arguments are

    my ($self, $transaction, $smtp, $auth, $sslinfo) = @_;
    # $smtp - the SMTP type used (e.g. "SMTP" or "ESMTP").
    # $auth - the Auth header additionals.
    # $sslinfo - information about SSL for the header.

## data\_headers\_end

This hook fires after all header lines of the message data has been received.
Defaults to doing nothing, just continue processing. At this step,
the sender is not waiting for a reply, but we can try and prevent him from
sending the entire message by disconnecting immediately. (Although it is
likely the packets are already in flight due to buffering and pipelining).

__NOTE:__ BE CAREFUL! If you drop the connection legal MTAs will retry again
and again, spammers will probably not. This is not RFC compliant and can lead
to an unpredictable mess. Use with caution.

Why this hook may be useful for you, see
[http://www.nntp.perl.org/group/perl.qpsmtpd/2009/02/msg8502.html](http://www.nntp.perl.org/group/perl.qpsmtpd/2009/02/msg8502.html), ff.

Allowed return codes:

- DENY\_DISCONNECT

    Return __554 Message denied__ and disconnect

- DENYSOFT\_DISCONNECT

    Return __421 Message denied temporarily__ and disconnect

- DECLINED

    Do nothing

Arguments:

    my ($self, $transaction) = @_;

__FIXME:__ check arguments

## hook\_data\_post\_headers

The `data_post_headers` hook is called after the client sends the final .\r\n of
a message and before the message is processed by `data_post`. This hook is
used by plugins that insert new headers (ex: Received-SPF) and/or
modify headers such as appending to Authentication-Results (SPF, DKIM, DMARC).

When it is desirable to have these header modifications evaluated by filtering
software (spamassassin, dspam, etc.) running on `data_post`, this hook should be
used instead of `data_post`.

Note that you cannot reject in this hook, use the data_post hook instead

Allowed return codes are

- DECLINED

    Do nothing

## hook\_data\_post

The `data_post` hook is called after all headers has been added in
`data_post_headers` above. This is meant for plugins that expect complete
messages, such as content analyzing spam filters. Plugins can still add
headers in this hook, however it is recommended only informational headers
are added here.

Allowed return codes are

- DENY

    Return a hard failure code

- DENYSOFT

    Return a soft failure code

- DENY\_DISCONNECT / DENYSOFT\_DISCONNECT

    as above but with disconnect

- DONE

    skip further processing (message will not be queued), plugin gave the response.

    __NOTE:__ just returning _OK_ from a special queue plugin does (nearly)
    the same (i.e. dropping the mail to `/dev/null`) and you don't have to
    send the response on your own.

    If you want the mail to be queued, you have to queue it manually!

Arguments:

    my ($self, $transaction) = @_;

Example plugins: `spamassassin`, `virus/clamdscan`, `dspam`

## hook\_queue\_pre

This hook is run, just before the mail is queued to the \`\`backend''. You
may modify the in-process transaction object (e.g. adding headers) or add
something like a footer to the mail (the latter is not recommended).

Allowed return codes are

- DONE

    no queuing is done

- OK / DECLINED

    queue the mail

## hook\_queue

When all `data_post` hooks accepted the message, this hook is called. It
is used to queue the message to the \`\`backend''.

Allowed return codes:

- DONE

    skip further processing (plugin gave response code)

- OK

    Return success message, i.e. tell the client the message was queued (this
    may be used to drop the message silently).

- DENY

    Return hard failure code

- DENYSOFT

    Return soft failure code, i.e. if disk full or other temporary queuing
    problems

Arguments:

    my ($self, $transaction) = @_;

Example plugins: all `queue/*` plugins

## hook\_queue\_post

This hook is called always after `hook_queue`. If the return code is
__not__ _OK_, a message (all remaining return values) with level _LOGERROR_
is written to the log.
Arguments are

    my $self = shift;

__NOTE:__ `$transaction` is not valid at this point, therefore not mentioned.

## hook\_reset\_transaction

This hook will be called several times. At the beginning of a transaction
(i.e. when the client sends a __MAIL FROM:__ command the first time),
after queueing the mail and every time a client sends a __RSET__ command.
Arguments are

    my ($self, $transaction) = @_;

__NOTE:__ don't rely on `$transaction` being valid at this point.

## hook\_quit

After the client sent a __QUIT__ command, this hook is called (before the
`hook_disconnect`).

Allowed return codes

- DONE

    plugin sent response

- DECLINED

    next plugin and / or qpsmtpd sends response

Arguments: the only argument is `$self`

Expample plugin is the `quit_fortune` plugin.

## hook\_disconnect

This hook will be called from several places: After a plugin returned
`DENY(|SOFT)_DISCONNECT`, before connection is disconnected or after the
client sent the `QUIT` command, AFTER the quit hook and ONLY if no plugin
hooking `hook_quit` returned `DONE`.

All return values are ignored, arguments are just `$self`

Example plugin is `logging/file`

## hook\_post\_connection

This is the counter part of the `pre-connection` hook, it is called
directly before the connection is finished, for example, just before the
qpsmtpd-forkserver instance exits or if the client drops the connection
without notice (without a __QUIT__). This hook is not called if the qpsmtpd
instance is killed.

The only argument is `$self` and all return codes are ignored, it would
be too late anyway :-).

Example: `connection_time`

# Parsing Hooks

Before the line from the client is parsed by
`Qpsmtpd::Command->parse()` with the built in parser, these hooks
are called. They can be used to supply a parsing function for the line,
which will be used instead of the built in parser.

The hook must return two arguments, the first is (currently) ignored,
the second argument must be a (CODE) reference to a sub routine. This sub
routine receives three arguments:

- $self

    the plugin object

- $cmd

    the command (i.e. the first word of the line) sent by the client

- $line

    the line sent by the client without the first word

Expected return values from this sub are _DENY_ and a reason which is
sent to the client or _OK_ and the `$line` broken into pieces according
to the syntax rules for the command.

__NOTE: ignore the example from `Qpsmtpd::Command`, the `unrecognized_command_parse` hook was never implemented,...__

## `hook_helo_parse` / `hook_ehlo_parse`

The provided sub routine must return two or more values. The first is
discarded, the second is the hostname (sent by the client as argument
to the __HELO__ / __EHLO__ command). All other values are passed to the
helo / ehlo hook. This hook may be used to change the hostname the client
sent... not recommended, but if your local policy says only to accept
_HELO_ hosts with FQDNs and you have a legal client which can not be
changed to send his FQDN, this is the right place.

## hook\_mail\_parse / hook\_rcpt\_parse

The provided sub routine must return two or more values. The first is
either _OK_ to indicate that parsing of the line was successfull
or anything else to bail out with _501 Syntax error in command_. In
case of failure the second argument is used as the error message for the
client.

If parsing was successfull, the second argument is the sender's /
recipient's address (this may be without the surrounding _<_ and
_>_, don't add them here, use the `hook_mail_pre()` /
`hook_rcpt_pre()` methods for this). All other arguments are
sent to the `mail / rcpt` hook as __MAIL__ / __RCPT__ parameters (see
RFC 1869 _SMTP Service Extensions_ for more info). Note that
the mail and rcpt hooks expect a list of key/value pairs as the
last arguments.

## hook\_auth\_parse

__FIXME...__

# Special hooks

Now some special hooks follow. Some of these hooks are some internal hooks,
which may be used to alter the logging or retrieving config values from
other sources (other than flat files) like SQL databases.

## hook\_logging

This hook is called when a log message is written, for example in a plugin
it fires if someone calls `$self->log($level, $msg);`. Allowed
return codes are

- DECLINED

    next logging plugin

- OK

    (not _DONE_, as some might expect!) ok, plugin logged the message

Arguments are

    my ($self, $transaction, $trace, $hook, $plugin, @log) = @_;
    # $trace: level of message, for example
    #          LOGWARN, LOGDEBUG, ...
    # $hook:  the hook in/for which this logging
    #          was called
    # $plugin: the plugin calling this hook
    # @log:   the log message

__NOTE:__ `$transaction` may be `undef`, depending when / where this hook
is called. It's probably best not to try acessing it.

All `logging/*` plugins can be used as example plugins.

## hook\_deny

This hook is called after a plugin returned _DENY_, _DENYSOFT_,
_DENY\_DISCONNECT_ or _DENYSOFT\_DISCONNECT_. All return codes are ignored,
arguments are

    my ($self, $transaction, $prev_plugin, $return, $return_text) = @_;

__NOTE:__ `$transaction` may be `undef`, depending when / where this hook
is called. It's probably best not to try acessing it.

Example plugin for this hook is `logging/adaptive`.

## hook\_ok

The counter part of `hook_deny`, it is called after a plugin __did not__
return _DENY_, _DENYSOFT_, _DENY\_DISCONNECT_ or _DENYSOFT\_DISCONNECT_.
All return codes are ignored, arguments are

    my ( $self, $transaction, $prev_plugin, $return, $return_text ) = @_;

__NOTE:__ `$transaction` may be `undef`, depending when / where this hook
is called. It's probably best not to try acessing it.

## hook\_config

Called when a config file is requested, for example in a plugin it fires
if someone calls `my @cfg = $self->qp->config($cfg_name);`.
Allowed return codes are

- DECLINED

    plugin didn't find the requested value

- OK, @values

    requested values as `@list`, example:

        return (OK, @{$config{$key}})
          if exists $config{$key};
        return (DECLINED);

Arguments:

    my ($self,$transaction,@keys) = @_;
    # @keys: the requested config item(s)

__NOTE:__ `$transaction` may be `undef`, depending when / where this hook
is called. It's probably best not to try acessing it.

Example plugin is `http_config` from the qpsmtpd distribution.

## hook\_user\_config

Called when a per-user configuration directive is requested, for example
if someone calls `my @cfg = $rcpt->config($cfg_name);`.
Allowed return codes are

- DECLINED

    plugin didn't find the requested value

- OK, @values

    requested values as `@list`, example:

        return (OK, @{$config{$key}})
          if exists $config{$key};
        return (DECLINED);

Arguments:

    my ($self,$transaction,$user,@keys) = @_;
    # @keys: the requested config item(s)

Example plugin is `user_config` from the qpsmtpd distribution.

## hook\_unrecognized\_command

This is called if the client sent a command unknown to the core of qpsmtpd.
This can be used to implement new SMTP commands or just count the number
of unknown commands from the client, see below for examples.
Allowed return codes:

- DENY\_DISCONNECT

    Return __521__ and disconnect the client

- DENY

    Return __500__

- DONE

    Qpsmtpd wont do anything; the plugin responded, this is what you want to
    return, if you are implementing new commands

- Anything else...

    Return __500 Unrecognized command__

Arguments:

    my ($self, $transaction, $cmd, @args) = @_;
    # $cmd  = the first "word" of the line
    #         sent by the client
    # @args = all the other "words" of the
    #         line sent by the client
    #         "word(s)": white space split() line

__NOTE:__ `$transaction` may be `undef`, depending when / where this hook
is called. It's probably best not to try acessing it.

Example plugin is `tls`.

## hook\_help

This hook triggers if a client sends the __HELP__ command, allowed return
codes are:

- DONE

    Plugin gave the answer.

- DENY

    The client will get a `syntax error` message, probably not what you want,
    better use

        $self->qp->respond(502, "Not implemented.");
        return DONE;

Anything else will be send as help answer.

Arguments are
   my ($self, $transaction, @args) = @\_;

with `@args` being the arguments from the client's command.

## hook\_vrfy

If the client sents the __VRFY__ command, this hook is called. Default is to
return a message telling the user to just try sending the message.
Allowed return codes:

- OK

    Recipient Exists

- DENY

    Return a hard failure code

- DONE

    Return nothing and move on

- Anything Else...

    Return a __252__

Arguments are:

    my ($self) = shift;

## hook\_noop

If the client sents the __NOOP__ command, this hook is called. Default is to
return `250 OK`.

Allowed return codes are:

- DONE

    Plugin gave the answer

- DENY\_DISCONNECT

    Return error code and disconnect client

- DENY

    Return error code.

- Anything Else...

    Give the default answer of __250 OK__.

Arguments are

    my ($self,$transaction,@args) = @_;

# Authentication hooks

See `docs/authentication.pod`.
