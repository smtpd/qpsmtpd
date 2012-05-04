#!/usr/bin/perl -w
use strict;
use warnings;

use lib 't';
use lib 'lib';

use Data::Dumper;
use Digest::HMAC_MD5 qw(hmac_md5_hex);
use English qw/ -no_match_vars /;
use File::Path;

use Qpsmtpd::Constants;
use Scalar::Util qw( openhandle );
use Test::More qw(no_plan);

use_ok('Test::Qpsmtpd');
use_ok('Qpsmtpd::Auth');

my ($smtpd, $conn) = Test::Qpsmtpd->new_conn();

ok( $smtpd, "get new connection ($smtpd)");
isa_ok( $conn, 'Qpsmtpd::Connection', "get new connection");

#warn Dumper($smtpd) and exit;
#my $hooks = $smtpd->hooks;
#warn Dumper($hooks) and exit;

my $r;
my $user     = 'good@example.com';
my $pass     = 'good_pass';
my $enc_plain= Qpsmtpd::Auth::e64( join("\0", '', $user, $pass ) );

# get_auth_details_plain: plain auth method handles credentials properly
my ($loginas,$ruser,$passClear) = Qpsmtpd::Auth::get_auth_details_plain($smtpd, $enc_plain);
cmp_ok( $user, 'eq', $user, "get_auth_details_plain, user");
cmp_ok( $passClear, 'eq', $pass, "get_auth_details_plain, password");

my $bad_auth = Qpsmtpd::Auth::e64( join("\0", 'loginas', 'user@foo', 'passer') );
($loginas,$ruser,$passClear) = Qpsmtpd::Auth::get_auth_details_plain($smtpd, $bad_auth );
ok( ! $loginas, "get_auth_details_plain, loginas -");
ok( !$ruser, "get_auth_details_plain, user -");
ok( !$passClear, "get_auth_details_plain, pass -");

# these plugins test against whicever loaded plugin provides their selected
# auth type. Right now, they end up testing against auth_flat_file.

# PLAIN
$r = Qpsmtpd::Auth::SASL($smtpd, 'plain', $enc_plain);
cmp_ok( OK, '==', $r, "plain auth");

if ( $ENV{QPSMTPD_DEVELOPER} && is_interactive() ) {
# same thing, but must be entered interactively
    print "answer: $enc_plain\n";
    $r = Qpsmtpd::Auth::SASL($smtpd, 'plain', '');
    cmp_ok( OK, '==', $r, "SASL, plain");
};


# LOGIN

if ( $ENV{QPSMTPD_DEVELOPER} && is_interactive() ) {

    my $enc_user = Qpsmtpd::Auth::e64( $user );
    my $enc_pass = Qpsmtpd::Auth::e64( $pass );

# get_base64_response
    print "answer: $enc_user\n";
    $r = Qpsmtpd::Auth::get_base64_response( $smtpd, 'Username' );
    cmp_ok( $r, 'eq', $user, "get_base64_response +");

# get_auth_details_login
    print "answer: $enc_pass\n";
    ($ruser,$passClear) = Qpsmtpd::Auth::get_auth_details_login( $smtpd, $enc_user );
    cmp_ok( $ruser, 'eq', $user, "get_auth_details_login, user +");
    cmp_ok( $passClear, 'eq', $pass, "get_auth_details_login, pass +");

    print "encoded pass: $enc_pass\n";
    $r = Qpsmtpd::Auth::SASL($smtpd, 'login', $enc_user);
    cmp_ok( OK, '==', $r, "SASL, login"); 
};


# CRAM-MD5

if ( $ENV{QPSMTPD_DEVELOPER} && is_interactive() ) {
    print "starting SASL\n";

# since we don't have bidirection communication here, we pre-generate a ticket
    my $ticket = sprintf( '<%x.%x@%s>', rand(1000000), time(), $smtpd->config('me') );
    my $hash_pass = hmac_md5_hex( $ticket, $pass );
    my $enc_answer = Qpsmtpd::Auth::e64( join(' ', $user, $hash_pass ) );
    print "answer: $enc_answer\n";
    my (@r) = Qpsmtpd::Auth::get_auth_details_cram_md5( $smtpd, $ticket );
    cmp_ok( $r[0], 'eq', $ticket, "get_auth_details_cram_md5, ticket" );
    cmp_ok( $r[1], 'eq', $user,    "get_auth_details_cram_md5, user" );
    cmp_ok( $r[2], 'eq', $hash_pass, "get_auth_details_cram_md5, passHash" );
#warn Data::Dumper::Dumper(\@r);

# this isn't going to work without bidirection communication to get the ticket
    #$r = Qpsmtpd::Auth::SASL($smtpd, 'cram-md5' );
    #cmp_ok( OK, '==', $r, "login auth");
};


sub is_interactive {

## no critic
# borrowed from IO::Interactive
    my ($out_handle) = ( @_, select );    # Default to default output handle

# Not interactive if output is not to terminal...
    return if not -t $out_handle;

# If *ARGV is opened, we're interactive if...
    if ( openhandle * ARGV ) {

# ...it's currently opened to the magic '-' file
        return -t *STDIN if defined $ARGV && $ARGV eq '-';

# ...it's at end-of-file and the next file is the magic '-' file
        return @ARGV > 0 && $ARGV[0] eq '-' && -t *STDIN if eof *ARGV;

# ...it's directly attached to the terminal
        return -t *ARGV;
    };

# If *ARGV isn't opened, it will be interactive if *STDIN is attached
# to a terminal and either there are no files specified on the command line
# or if there are files and the first is the magic '-' file
    return -t *STDIN && ( @ARGV == 0 || $ARGV[0] eq '-' );
}


__END__

if ( ref $r ) {
} else {
    warn $r;
}
#print Data::Dumper::Dumper($conn);
#print Data::Dumper::Dumper($smtpd);

