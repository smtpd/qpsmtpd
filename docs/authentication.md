# NAME

Authentication framework for qpsmtpd

# DESCRIPTION

Provides support for SMTP AUTH within qpsmtpd transactions, see

[http://www.faqs.org/rfcs/rfc2222.html](http://www.faqs.org/rfcs/rfc2222.html)
[http://www.faqs.org/rfcs/rfc2554.html](http://www.faqs.org/rfcs/rfc2554.html)

for more details.

# USAGE

This code is automatically loaded by Qpsmtpd::SMTP only if a plugin
providing one of the defined ["Auth Hooks"](#auth-hooks) is loaded.  The only
time this can happen is if the client process employs the EHLO command to
initiate the SMTP session.  If the client uses HELO, the AUTH command is
not available and this module isn't even loaded.

## Plugin Design

An authentication plugin can bind to one or more auth hooks or bind to all
of them at once.  See ["Multiple Hook Behavior"](#multiple-hook-behavior) for more details.

All plugins must provide two functions:

- init()

    This is the standard function which is called by qpsmtpd for any plugin
    listed in config/plugins.  Typically, an auth plugin should register at
    least one hook, like this:

        sub init {
          my ($self, $qp) = @_;

          $self->register_hook("auth", "authfunction");
        }

    where in this case "auth" means this plugin expects to support any of
    the defined authentication methods.

- authfunction()

    The plugin must provide an authentication function which is part of
    the register\_hook call.  That function will receive the following
    six parameters when called:

    - $self

        A Qpsmtpd::Plugin object, which can be used, for example, to emit log
        entries or to send responses to the remote SMTP client.

    - $transaction

        A Qpsmtpd::Transaction object which can be used to examine information
        about the current SMTP session like the remote IP address.

    - $mechanism

        The lower-case name of the authentication mechanism requested by the
        client; either "plain", "login", or "cram-md5".

    - $user

        Whatever the remote SMTP client sent to identify the user (may be bare
        name or fully qualified e-mail address).

    - $clearPassword

        If the particular authentication method supports unencrypted passwords
        (currently PLAIN and LOGIN), which will be the plaintext password sent
        by the remote SMTP client.

    - $hashPassword

        An encrypted form of the remote user's password, using the MD-5 algorithm
        (see also the $ticket parameter).

    - $ticket

        This is the cryptographic challenge which was sent to the client as part
        of a CRAM-MD5 transaction.  Since the MD-5 algorithm is one-way, the same
        $ticket value must be used on the backend to compare with the encrypted
        password sent in $hashPassword.

Plugins should perform whatever checking they want and then return one
of the following values (taken from Qpsmtpd::Constants):

- OK

    If the authentication has succeeded, the plugin can return this value and
    all subsequently registered hooks will be skipped.

- DECLINED

    If the authentication has failed, but any additional plugins should be run,
    this value will be returned.  If none of the registered plugins succeed, the
    overall authentication will fail.  Normally an auth plugin should return
    this value for all cases which do not succeed (so that another auth plugin
    can have a chance to authenticate the user).

- DENY

    If the authentication has failed, and the plugin wishes this to short circuit
    any further testing, it should return this value.  For example, a plugin could
    register the [auth-plain](https://metacpan.org/pod/auth-plain) hook and immediately fail any connection which is
    not trusted (e.g. not in the same network).

    Another reason to return DENY over DECLINED would be if the user name matched
    an existing account but the password failed to match.  This would make a
    dictionary-based attack much harder to accomplish.  See the included
    auth\_vpopmail\_sql plugin for how this might be accomplished.

    By returning DENY, no further authentication attempts will be made using the
    current method and data.  A remote SMTP client is free to attempt a second
    auth method if the first one fails.

Plugins may also return an optional message with the return code, e.g.

    return (DENY, "If you forgot your password, contact your admin");

and this will be appended to whatever response is sent to the remote SMTP
client.  There is no guarantee that the end user will see this information,
though, since some prominent MTA's (produced by M$oft) _helpfully_
hide this information under the default configuration.  This message will
be logged locally, if appropriate, based on the configured log level.

# Auth Hooks

The currently defined authentication methods are:

- auth-plain

    Any plugin which registers an auth-plain hook will engage in a plaintext
    prompted negotiation.  This is the least secure authentication method since
    both the user name and password are visible in plaintext.  Most SMTP clients
    will preferentially choose a more secure method if it is advertised by the
    server.

- auth-login

    A slightly more secure method where the username and password are Base-64
    encoded before sending.  This is still an insecure method, since it is
    trivial to decode the Base-64 data.  Again, it will not normally be chosen
    by SMTP clients unless a more secure method is not available (or if it fails).

- auth-cram-md5

    A cryptographically secure authentication method which employs a one-way
    hashing function to transmit the secret information without significant
    risk between the client and server.  The server provides a challenge key
    [$ticket](https://metacpan.org/pod/$ticket), which the client uses to encrypt the user's password.
    Then both user name and password are concatenated and Base-64 encoded before
    transmission.

    This hook must normally have access to the user's plaintext password,
    since there is no way to extract that information from the transmitted data.
    Since the CRAM-MD5 scheme requires that the server send the challenge
    [$ticket](https://metacpan.org/pod/$ticket) before knowing what user is attempting to log in, there is no way
    to use any existing MD5-encrypted password (like is frequently used with MySQL).

- auth

    A catch-all hook which requires that the plugin support all three preceeding
    authentication methods.  Any plugins registering the auth hook will be run
    only after all other plugins registered for the specific authentication
    method which was requested.  This allows you to move from more specific
    plugins to more general plugins (e.g. local accounts first vs replicated
    accounts with expensive network access later).

## Multiple Hook Behavior

If more than one hook is registered for a given authentication method, then
they will be tried in the order that they appear in the config/plugins file
unless one of the plugins returns DENY, which will immediately cease all
authentication attempts for this transaction.

In addition, all plugins that are registered for a specific auth hook will
be tried before any plugins which are registered for the general auth hook.

# VPOPMAIL

There are 4 authentication (smtp-auth) plugins that can be used with
vpopmail.

- auth\_vpopmaild

    If you aren't sure which one to use, then use auth\_vpopmaild. It
    supports the PLAIN and LOGIN authentication methods,
    doesn't require the qpsmtpd process to run with special permissions, and
    can authenticate against vpopmail running on another host. It does require
    the vpopmaild server to be running.

- auth\_vpopmail

    The next best solution is auth\_vpopmail. It requires the p5-vpopmail perl
    module and it compiles against libvpopmail.a. There are two catches. The
    qpsmtpd daemon must run as the vpopmail user, and you must be running v0.09
    or higher for CRAM-MD5 support. The released version is 0.08 but my
    CRAM-MD5 patch has been added to the developers repo:
       http://github.com/sscanlon/vpopmail

- auth\_vpopmail\_sql

    If you are using the MySQL backend for vpopmail, then this module can be
    used for smtp-auth. It supports LOGIN, PLAIN, and CRAM-MD5. However, it
    does not work with some vpopmail features such as alias domains, service
    restrictions, nor does it update vpopmail's last\_auth information.

- auth\_checkpassword

    The auth\_checkpassword is a generic authentication module that will work
    with any DJB style checkpassword program, including ~vpopmail/bin/vchkpw.
    It only supports PLAIN and LOGIN auth methods.

# AUTHOR

John Peacock <jpeacock@cpan.org>

Matt Simerson <msimerson@cpan.org> (added VPOPMAIL)

# COPYRIGHT AND LICENSE

Copyright (c) 2004-2006 John Peacock

Portions based on original code by Ask Bjoern Hansen and Guillaume Filion

This plugin is licensed under the same terms as the qpsmtpd package itself.
Please see the LICENSE file included with qpsmtpd for details.
