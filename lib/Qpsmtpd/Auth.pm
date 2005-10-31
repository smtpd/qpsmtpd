#!/usr/bin/perl -w

=head1 NAME

Qpsmtpd::Auth - Authentication framework for qpsmtpd

=head1 DESCRIPTION

Provides support for SMTP AUTH within qpsmtpd transactions, see 

L<http://www.faqs.org/rfcs/rfc2222.html>
L<http://www.faqs.org/rfcs/rfc2554.html>

for more details.

=head1 USAGE

This module is automatically loaded by Qpsmtpd::SMTP only if a plugin
providing one of the defined L<Auth Hooks> is loaded.  The only
time this can happen is if the client process employs the EHLO command to
initiate the SMTP session.  If the client uses HELO, the AUTH command is
not available and this module isn't even loaded.

=head2 Plugin Design

An authentication plugin can bind to one or more auth hooks or bind to all
of them at once.  See L<Multiple Hook Behavior> for more details.

All plugins must provide two functions:

=over 4

=item * register()

This is the standard function which is called by qpsmtpd for any plugin 
listed in config/plugins.  Typically, an auth plugin should register at
least one hook, like this:


  sub register {
    my ($self, $qp) = @_;

    $self->register_hook("auth", "authfunction");
  }

where in this case "auth" means this plugin expects to support any of 
the defined authentication methods.

=item * authfunction()

The plugin must provide an authentication function which is part of
the register_hook call.  That function will receive the following
six parameters when called:

=over 4

=item $self

A Qpsmtpd::Plugin object, which can be used, for example, to emit log
entries or to send responses to the remote SMTP client.

=item $transaction

A Qpsmtpd::Transaction object which can be used to examine information
about the current SMTP session like the remote IP address.

=item $mechanism

The lower-case name of the authentication mechanism requested by the
client; either "plain", "login", or "cram-md5".

=item $user

Whatever the remote SMTP client sent to identify the user (may be bare
name or fully qualified e-mail address).

=item $clearPassword

If the particular authentication method supports unencrypted passwords
(currently PLAIN and LOGIN), which will be the plaintext password sent
by the remote SMTP client.

=item $hashPassword

An encrypted form of the remote user's password, using the MD-5 algorithm
(see also the $ticket parameter).

=item $ticket

This is the cryptographic challenge which was sent to the client as part
of a CRAM-MD5 transaction.  Since the MD-5 algorithm is one-way, the same
$ticket value must be used on the backend to compare with the encrypted
password sent in $hashPassword.

=back

=back

Plugins should perform whatever checking they want and then return one
of the following values (taken from Qpsmtpd::Constants):

=over 4

=item OK

If the authentication has succeeded, the plugin can return this value and
all subsequently registered hooks will be skipped.

=item DECLINED

If the authentication has failed, but any additional plugins should be run, 
this value will be returned.  If none of the registered plugins succeed, the
overall authentication will fail.  Normally an auth plugin should return
this value for all cases which do not succeed (so that another auth plugin
can have a chance to authenticate the user).

=item DENY

If the authentication has failed, and the plugin wishes this to short circuit
any further testing, it should return this value.  For example, a plugin could
register the L<auth-plain> hook and immediately fail any connection which is
not trusted (e.g. not in the same network).

Another reason to return DENY over DECLINED would be if the user name matched
an existing account but the password failed to match.  This would make a
dictionary-based attack much harder to accomplish.  See the included
auth_vpopmail_sql plugin for how this might be accomplished.

By returning DENY, no further authentication attempts will be made using the
current method and data.  A remote SMTP client is free to attempt a second
auth method if the first one fails.

=back

Plugins may also return an optional message with the return code, e.g.

  return (DENY, "If you forgot your password, contact your admin");

and this will be appended to whatever response is sent to the remote SMTP
client.  There is no guarantee that the end user will see this information,
though, since some prominent MTA's (produced by M$oft) I<helpfully>
hide this information under the default configuration.  This message will
be logged locally, if appropriate, based on the configured log level.

=head1 Auth Hooks

The currently defined authentication methods are:

=over 4

=item * auth-plain

Any plugin which registers an auth-plain hook will engage in a plaintext
prompted negotiation.  This is the least secure authentication method since
both the user name and password are visible in plaintext.  Most SMTP clients
will preferentially choose a more secure method if it is advertised by the
server.

=item * auth-login

A slightly more secure method where the username and password are Base-64
encoded before sending.  This is still an insecure method, since it is
trivial to decode the Base-64 data.  Again, it will not normally be chosen
by SMTP clients unless a more secure method is not available (or if it fails).

=item * auth-cram-md5

A cryptographically secure authentication method which employs a one-way
hashing function to transmit the secret information without significant
risk between the client and server.  The server provides a challenge key
L<$ticket>, which the client uses to encrypt the user's password.
Then both user name and password are concatenated and Base-64 encoded before
transmission.

This hook must normally have access to the user's plaintext password,
since there is no way to extract that information from the transmitted data.
Since the CRAM-MD5 scheme requires that the server send the challenge
L<$ticket> before knowing what user is attempting to log in, there is no way
to use any existing MD5-encrypted password (like is frequently used with MySQL).

=item * auth

A catch-all hook which requires that the plugin support all three preceeding
authentication methods.  Any plugins registering the auth hook will be run
only after all other plugins registered for the specific authentication 
method which was requested.  This allows you to move from more specific
plugins to more general plugins (e.g. local accounts first vs replicated
accounts with expensive network access later).

=back

=head2 Multiple Hook Behavior

If more than one hook is registered for a given authentication method, then
they will be tried in the order that they appear in the config/plugins file
unless one of the plugins returns DENY, which will immediately cease all
authentication attempts for this transaction.

In addition, all plugins that are registered for a specific auth hook will
be tried before any plugins which are registered for the general auth hook.

=head1 AUTHOR

John Peacock <jpeacock@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2004 John Peacock

Portions based on original code by Ask Bjoern Hansen and Guillaume Filion

This plugin is licensed under the same terms as the qpsmtpd package itself.
Please see the LICENSE file included with qpsmtpd for details.

=cut

package Qpsmtpd::Auth;
use Qpsmtpd::Constants;
use MIME::Base64;

sub e64
{
  my ($arg) = @_;
  my $res = encode_base64($arg);
  chomp($res);
  return($res);
}

sub SASL {

    # $DB::single = 1;
    my ( $session, $mechanism, $prekey ) = @_;
    my ( $user, $passClear, $passHash, $ticket );
    $mechanism = lc($mechanism);

    if ( $mechanism eq "plain" ) {
        if (!$prekey) {
          $session->respond( 334, "Please continue" );
          $prekey= <>;
        }
        ( $passHash, $user, $passClear ) = split /\x0/,
          decode_base64($prekey);

    }
    elsif ($mechanism eq "login") {

        if ( $prekey ) {
          ($passHash, $user, $passClear) = split /\x0/, decode_base64($prekey);
        }
        else {
    
          $session->respond(334, e64("Username:"));
          $user = decode_base64(<>);
          #warn("Debug: User: '$user'");
          if ($user eq '*') {
            $session->respond(501, "Authentification canceled");
            return DECLINED;
          }
    
          $session->respond(334, e64("Password:"));
          $passClear = <>;
          $passClear = decode_base64($passClear);
          #warn("Debug: Pass: '$pass'");
          if ($passClear eq '*') {
            $session->respond(501, "Authentification canceled");
            return DECLINED;
          }
        }
    }
    elsif ( $mechanism eq "cram-md5" ) {

        # rand() is not cryptographic, but we only need to generate a globally
        # unique number.  The rand() is there in case the user logs in more than
        # once in the same second, of if the clock is skewed.
        $ticket = sprintf( "<%x.%x\@" . $session->config("me") . ">",
            rand(1000000), time() );

        # We send the ticket encoded in Base64
        $session->respond( 334, encode_base64( $ticket, "" ) );
        my $line = <>;
        chop($line);
        chop($line);

        if ( $line eq '*' ) {
            $session->respond( 501, "Authentification canceled" );
            return DECLINED;
        }

        ( $user, $passHash ) = split( ' ', decode_base64($line) );

    }
    else {
        $session->respond( 500, "Unrecognized authentification mechanism" );
        return DECLINED;
    }

    # try running the specific hooks first
    my ( $rc, $msg ) =
      $session->run_hooks( "auth-$mechanism", $mechanism, $user, $passClear,
        $passHash, $ticket );

    # try running the polymorphous hooks next
    if ( !$rc || $rc == DECLINED ) {    
        ( $rc, $msg ) =
          $session->run_hooks( "auth", $mechanism, $user, $passClear,
            $passHash, $ticket );
    }

    if ( $rc == OK ) {
        $msg = "Authentication successful for $user" .
            ( defined $msg ? " - " . $msg : "" );
        $session->respond( 235, $msg );
        $session->connection->relay_client(1);
        $session->log( LOGINFO, $msg );

        $session->{_auth_user} = $user;
        $session->{_auth_mechanism} = $mechanism;
        s/[\r\n].*//s for ($session->{_auth_user}, $session->{_auth_mechanism}); 

        return OK;
    }
    else {
        $msg = "Authentication failed for $user" .
            ( defined $msg ? " - " . $msg : "" );
        $session->respond( 535, $msg );
        $session->log( LOGERROR, $msg );
        return DENY;
    }
}

# tag: qpsmtpd plugin that sets RELAYCLIENT when the user authentifies

1;
