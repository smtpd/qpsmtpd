package Qpsmtpd::Auth;
# See the documentation in 'perldoc README.authentication' 

use strict;
use warnings;

use MIME::Base64;
use Qpsmtpd::Constants;

sub e64 {
  my ($arg) = @_;
  my $res = encode_base64($arg);
  chomp($res);
  return($res);
}

sub SASL {

    # $DB::single = 1;
    my ( $session, $mechanism, $prekey ) = @_;
    my ( $user, $passClear, $passHash, $ticket, $loginas );

    if ( $mechanism eq 'plain' ) {
        ($loginas, $user, $passClear) = get_auth_details_plain($session,$prekey);
        return DECLINED if ! $user || ! $passClear;
    }
    elsif ( $mechanism eq 'login' ) {
        ($user, $passClear) = get_auth_details_login($session,$prekey);
        return DECLINED if ! $user || ! $passClear;
    }
    elsif ( $mechanism eq 'cram-md5' ) {
        ( $ticket, $user, $passHash ) = get_auth_details_cram_md5($session);
        return DECLINED if ! $user || ! $passHash;
    }
    else {
        #this error is now caught in SMTP.pm's sub auth
        $session->respond( 500, "Internal server error" );
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
        $session->log( LOGDEBUG, $msg );  # already logged by $session->respond

        $session->{_auth_user} = $user;
        $session->{_auth_mechanism} = $mechanism;
        s/[\r\n].*//s for ($session->{_auth_user}, $session->{_auth_mechanism}); 

        return OK;
    }
    else {
        $msg = "Authentication failed for $user" .
            ( defined $msg ? " - " . $msg : "" );
        $session->respond( 535, $msg );
        $session->log( LOGDEBUG, $msg );  # already logged by $session->respond
        return DENY;
    }
}

sub get_auth_details_plain {
    my ( $session, $prekey ) = @_;

    if ( ! $prekey) {
        $session->respond( 334, ' ' );
        $prekey= <STDIN>;
    }

    my ( $loginas, $user, $passClear ) = split /\x0/, decode_base64($prekey);

    if ( ! $user ) {
        if ( $loginas ) {
            $session->respond(535, "Authentication invalid ($loginas)");
        }
        else {
            $session->respond(535, "Authentication invalid");
        }
        return;
    };

    # Authorization ID must not be different from Authentication ID
    if ( $loginas ne '' && $loginas ne $user ) {
        $session->respond(535, "Authentication invalid for $user");
        return;
    }

    return ($loginas, $user, $passClear);
};

sub get_auth_details_login {
    my ( $session, $prekey ) = @_;

    my $user;

    if ( $prekey ) {
        $user = decode_base64($prekey);
    }
    else {
        $user = get_base64_response($session,'Username:') or return;
    }

    my $passClear = get_base64_response($session,'Password:') or return;

    return ($user, $passClear);
};

sub get_auth_details_cram_md5 {
    my ( $session, $ticket ) = @_;

    if ( ! $ticket ) {  # ticket is only passed in during testing
    # rand() is not cryptographic, but we only need to generate a globally
    # unique number.  The rand() is there in case the user logs in more than
    # once in the same second, or if the clock is skewed.
        $ticket = sprintf( '<%x.%x@%s>',
            rand(1000000), time(), $session->config('me') );
    };

    # send the base64 encoded ticket
    $session->respond( 334, encode_base64( $ticket, '' ) );
    my $line = <STDIN>;

    if ( $line eq '*' ) {
        $session->respond( 501, "Authentication canceled" );
        return;
    };

    my ( $user, $passHash ) = split( ' ', decode_base64($line) );
    unless ( $user && $passHash ) {
        $session->respond(504, "Invalid authentication string");
        return;
    }

    return ($ticket, $user, $passHash);
};

sub get_base64_response {
    my ($session, $question) = @_;

    $session->respond(334, e64($question));
    my $answer = decode_base64( <STDIN> );
    if ($answer eq '*') {
        $session->respond(501, "Authentication canceled");
        return;
    }
    return $answer;
};

# tag: qpsmtpd plugin that sets RELAYCLIENT when the user authentifies

1;
