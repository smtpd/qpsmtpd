# See the documentation in 'perldoc README.authentication' 

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
    my ( $user, $passClear, $passHash, $ticket, $loginas );
    $mechanism = lc($mechanism);

    if ( $mechanism eq "plain" ) {
        if (!$prekey) {
          $session->respond( 334, "Please continue" );
          $prekey= <STDIN>;
        }
        ( $loginas, $user, $passClear ) = split /\x0/,
          decode_base64($prekey);
          
        # Authorization ID must not be different from
        # Authentication ID
        if ( $loginas ne '' && $loginas ne $user ) {
          $session->respond(535, "Authentication invalid");
          return DECLINED;
        }
    }
    elsif ($mechanism eq "login") {

        if ( $prekey ) {
          $user = decode_base64($prekey);
        }
        else {
          $session->respond(334, e64("Username:"));
          $user = decode_base64(<STDIN>);
          if ($user eq '*') {
            $session->respond(501, "Authentification canceled");
            return DECLINED;
          }
        }
    
        $session->respond(334, e64("Password:"));
        $passClear = <STDIN>;
        $passClear = decode_base64($passClear);
        if ($passClear eq '*') {
          $session->respond(501, "Authentification canceled");
          return DECLINED;
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
        my $line = <STDIN>;

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

    # Make sure that we have enough information to proceed
    unless ( $user && ($passClear || $passHash) ) {
      $session->respond(504, "Invalid authentification string");
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
