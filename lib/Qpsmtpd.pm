package Qpsmtpd;
use strict;
use Carp;

use Qpsmtpd::Connection;
use Qpsmtpd::Transaction;
use Qpsmtpd::Constants;

use Mail::Address ();
use Sys::Hostname;
use IPC::Open2;
use Data::Dumper;
BEGIN{$^W=0;}
use Net::DNS;
BEGIN{$^W=1;}

$Qpsmtpd::VERSION = "0.10-dev";

# $SIG{ALRM} = sub { respond(421, "Game over pal, game over. You got a timeout; I just can't wait that long..."); exit };


sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  my %args = @_;

  my $self = bless ({ args => \%args }, $class);

  my (@commands) = qw(ehlo helo rset mail rcpt data help vrfy noop quit);
  my (%commands); @commands{@commands} = ('') x @commands;
  # this list of valid commands should probably be a method or a set of methods
  $self->{_commands} = \%commands;

  $self;
}


#
# method to get the configuration.  It just calls get_qmail_config by
# default, but it could be overwritten to look configuration up in a
# database or whatever.
#
sub config {
  my ($self, $c) = @_;

  my %defaults = (
		  me      => hostname,
		  timeout => 1200,
		  );

  return ($self->get_qmail_config($c) || $defaults{$c} || undef);

};

sub log {
  my ($self, $trace, @log) = @_;
  warn join(" ", $$, @log), "\n"
    if $trace <= 10;
}

sub dispatch {
  my $self = shift;
  my ($cmd) = lc shift;

  warn "command: $cmd";

  #$self->respond(553, $state{dnsbl_blocked}), return 1
  #  if $state{dnsbl_blocked} and ($cmd eq "rcpt");

  $self->respond(500, "Unrecognized command"), return 1
    if ($cmd !~ /^(\w{1,12})$/ or !exists $self->{_commands}->{$1});
  $cmd = $1;

  if (1 or $self->{_commands}->{$cmd} and $self->can($cmd)) {
    my ($result) = eval { $self->$cmd(@_) };
    $self->log(0, "XX: $@") if $@;
    return $result if defined $result;
    return $self->fault("command '$cmd' failed unexpectedly");
  }

  return;
}

sub fault {
  my $self = shift;
  my ($msg) = shift || "program fault - command not performed";
  print STDERR "$0[$$]: $msg ($!)\n";
  return $self->respond(451, "Internal error - try again later - " . $msg);
}


sub start_conversation {
    my $self = shift;
    $self->respond(220, $self->config('me') ." qpsmtpd ". $self->version ." Service ready, send me all your stuff!");
}

sub transaction {
  my $self = shift;
  use Data::Dumper;
  #warn Data::Dumper->Dump([\$self], [qw(self)]);
  return $self->{_transaction} || ($self->{_transaction} = Qpsmtpd::Transaction->new());
}

sub connection {
  my $self = shift;
  return $self->{_connection} || ($self->{_connection} = Qpsmtpd::Connection->new());
}


sub helo {
  my ($self, $hello_host, @stuff) = @_;
  my $conn = $self->connection;
  return $self->respond (503, "but you already said HELO ...") if $conn->hello;

  $conn->hello("helo");
  $conn->hello_host($hello_host);
  $self->transaction;
  $self->respond(250, $self->config('me') ." Hi " . $conn->remote_info . " [" . $conn->remote_ip ."]; I am so happy to meet you.");
}

sub ehlo {
  my ($self, $hello_host, @stuff) = @_;
  my $conn = $self->connection;
  return $self->respond (503, "but you already said HELO ...") if $conn->hello;

  $conn->hello("ehlo");
  $conn->hello_host($hello_host);
  $self->transaction;

  $self->respond(250,
		 $self->config("me") . " Hi " . $conn->remote_info . " [" . $conn->remote_ip ."]",
		 "PIPELINING",
		 "8BITMIME",
		 ($self->config('databytes') ? "SIZE ". ($self->config('databytes'))[0] : ()),
		);
}

sub mail {
  my $self = shift;
  return $self->respond(501, "syntax error in parameters") if $_[0] !~ m/^from:/i;
  unless ($self->connection->hello) {
    return $self->respond(503, "please say hello first ...");
  }
  else {
    my $from_parameter = join " ", @_;
    $self->log(2, "full from_parameter: $from_parameter");
    my ($from) = ($from_parameter =~ m/^from:\s*(\S+)/i)[0];
    #warn "$$ from email address : $from\n" if $TRACE;
    if ($from eq "<>" or $from =~ m/\[undefined\]/) {
      $from = Mail::Address->new("<>");
    } 
    else {
      $from = (Mail::Address->parse($from))[0];
    }
    return $self->respond(501, "could not parse your mail from command") unless $from;

    # this needs to be moved to a plugin --- FIXME
    0 and $from->format ne "<>"
      and $self->config("require_resolvable_fromhost")
      and !check_dns($from->host)
      and return $self->respond(450, $from->host ? "Could not resolve ". $from->host : "FQDN required in the envelope sender");

    $self->log(2, "getting mail from ".$from->format);
    $self->respond(250, $from->format . ", sender OK - I always like getting mail from you!");

    $self->transaction->sender($from);
  }
}

sub rcpt {
  my $self = shift;
  return $self->respond(501, "syntax error in parameters") unless $_[0] =~ m/^to:/i;
  return(503, "Use MAIL before RCPT") unless $self->transaction->sender;

  my $from = $self->transaction->sender;

  # Move to a plugin -- FIXME
  if (0 and $from->format ne "<>" and $self->config('rhsbl_zones')) {
    my %rhsbl_zones = map { (split /\s+/, $_, 2)[0,1] } $self->config('rhsbl_zones');
    my $host = $from->host;
    for my $rhsbl (keys %rhsbl_zones) {
      $self->respond("550", "Mail from $host rejected because it $rhsbl_zones{$rhsbl}"), return 1
	if check_rhsbl($rhsbl, $host);
    }
  }

  my ($rcpt) = ($_[0] =~ m/to:(.*)/i)[0];
  $rcpt = $_[1] unless $rcpt;
  $rcpt = (Mail::Address->parse($rcpt))[0];
  return $self->respond(501, "could not parse recipient") unless $rcpt;
  return $self->respond(550, "will not relay for ". $rcpt->host) unless $self->check_relay($rcpt->host);
  $self->transaction->add_recipient($rcpt);
  $self->respond(250, $rcpt->format . ", recipient OK");
}

 
sub check_relay {
  my $self = shift;
  my $host = lc shift;
  my @rcpt_hosts = $self->config("rcpthosts");
  return 1 if exists $ENV{RELAYCLIENT};
  for my $allowed (@rcpt_hosts) {
    $allowed =~ s/^\s*(\S+)/$1/;
    return 1 if $host eq lc $allowed;
    return 1 if substr($allowed,0,1) eq "." and $host =~ m/\Q$allowed\E$/i;
  }
  return 0;
}

sub get_qmail_config {
  my ($self, $config) = (shift, shift);
  $self->log(5, "trying to get config for $config");
  if ($self->{_config_cache}->{$config}) {
    return wantarray ? @{$self->{_config_cache}->{$config}} : $self->{_config_cache}->{$config}->[0];
  }
  my $configdir = '/var/qmail/control';
  my ($name) = ($0 =~ m!(.*?)/([^/]+)$!);
  $configdir = "$name/config" if (-e "$name/config/$config");
  open CF, "<$configdir/$config" or warn "$$ could not open configfile $config: $!", return;
  my @config = <CF>;
  chomp @config;
  @config = grep { $_ and $_ !~ m/^\s*#/ and $_ =~ m/\S/} @config;
  close CF;
  $self->log(5, "returning get_config for $config ",Data::Dumper->Dump([\@config], [qw(config)]));
  $self->{_config_cache}->{$config} = \@config;
  return wantarray ? @config : $config[0];
}


sub help {
  my $self = shift;
  $self->respond(214, 
	  "This is qpsmtpd " . $self->version,
	  "See http://develooper.com/code/qpsmtpd/",
	  'To report bugs or send comments, mail to <ask@perl.org>.');
}

sub version {
  $Qpsmtpd::VERSION;
}

sub noop {
  my $self = shift;
  warn Data::Dumper->Dump([\$self], [qw(self)]);
  $self->respond(250, "OK");

}

sub vrfy {
  shift->respond(252, "Just try sending a mail and we'll see how it turns out ...");
}

sub rset {
  my $self = shift;
  $self->{_transaction} = undef;
  $self->transaction->start();
  $self->respond(250, "OK");
}

sub quit {
  my $self = shift;
  $self->respond(221, $self->config('me') . " closing connection. Have a wonderful day");
  exit;
}

sub data {
  my $self = shift;
  $self->respond(503, "MAIL first"), return 1 unless $self->transaction->sender;
  $self->respond(503, "RCPT first"), return 1 unless $self->transaction->recipients;
  $self->respond(354, "go ahead");
  my $buffer = '';
  my $size = 0;
  my $i = 0;
  my $max_size = ($self->config('databytes'))[0] || 0;  # this should work in scalar context
  my $blocked = "";
  my %matches;
  my $header = 1;
  my $complete = 0;

  $self->log(6, "max_size: $max_size / size: $size");

  while (<STDIN>) {
    $complete++, last if $_ eq ".\r\n";
    $i++;
    $self->respond(451, "See http://develooper.com/code/qpsmtpd/barelf.html"), exit
      if $_ eq ".\n";
    unless ($max_size and $size > $max_size) {
      s/\r\n$/\n/;
      $header = 0 if $header and m/^\s*$/;

      if ($header) {

	$matches{"aol.com"} = 1 if m/aol\.com/;

	$blocked = "Your mail looks too much like that SirCam nonsense, please go away"
	  if $self->transaction->sender->format eq "<>"
	     and $_ eq "Content-Disposition: Multipart message\n";
	   
	$blocked = "No List Builder spam for us, thank you."
	  if m/^From: List Builder <notifications\@bcentral.com>/;

	$blocked = q[Don't send W32.Badtrans.B@mm virus to us, please]
	  if $matches{"aol.com"} and m/^From: .* <_/;
      }
      

      # Might be klez
      m/^Content-type:.*(?:audio|application)/i
          and $matches{"klez"}=1;

      # we've seen the Klez signature, we're probably infected
      $blocked = q[Take your Klez virus and stuff it!  HAND.]
         if $matches{"klez"} and m!^TVqQAAMAAAAEAAAA//8AALgAAAAAAAAAQA!;

      $buffer .= $_;
      $size += length $_;
    }
    warn "$$ size is at $size\n" unless ($i % 300);

    alarm $self->config('timeout');
  }

  $self->log(6, "max_size: $max_size / size: $size");

  # if we get here without seeing a terminator, the connection is
  # probably dead.
  $self->respond(451, "Incomplete DATA"), return 1 unless $complete;
 
  $self->respond(550, $blocked),return 1 if $blocked;
  $self->respond(552, "Message too big!"),return 1 if $max_size and $size > $max_size;

  

  # these bits inspired by Peter Samuels "qmail-queue wrapper"
  pipe(MESSAGE_READER, MESSAGE_WRITER) or fault("Could not create message pipe"), exit;
  pipe(ENVELOPE_READER, ENVELOPE_WRITER) or fault("Could not create envelope pipe"), exit;

  my $child = fork();
  
  not defined $child and fault(451, "Could not fork"), exit;

  if ($child) {
    # Parent
    my $oldfh = select(MESSAGE_WRITER); $| = 1; 
                select(ENVELOPE_WRITER); $| = 1;
    select($oldfh);

    close MESSAGE_READER  or fault("close msg reader fault"),exit;
    close ENVELOPE_READER or fault("close envelope reader fault"), exit;
    print MESSAGE_WRITER "Received: from ".$self->connection->remote_info." (HELO ".$self->connection->hello_host . ") [".$self->connection->remote_ip . "]\n";
    print MESSAGE_WRITER "  by ".$self->config('me')." (qpsmtpd/".$self->version.") with SMTP; ", scalar gmtime, "Z\n";
    print MESSAGE_WRITER $buffer;
    close MESSAGE_WRITER;

    my @rcpt = map { "T" . $_->address } $self->transaction->recipients;
    my $from = "F".($self->transaction->sender->address|| "" );
    print ENVELOPE_WRITER "$from\0", join("\0",@rcpt), "\0\0"
      or respond(451,"Could not print addresses to queue"),exit;
    
    close ENVELOPE_WRITER;
    waitpid($child, 0);
    my $exit_code = $? >> 8;
    $exit_code and respond(451, "Unable to queue message ($exit_code)"), exit;
    $self->respond(250, "Message queued; it better be worth it.");
  }
  elsif (defined $child) {
    # Child
    close MESSAGE_WRITER or die "could not close message writer in parent";
    close ENVELOPE_WRITER or die "could not close envelope writer in parent";
    
    open(STDIN, "<&MESSAGE_READER") or die "b1";
    open(STDOUT, "<&ENVELOPE_READER") or die "b2";
    
    unless (exec '/var/qmail/bin/qmail-queue') {
      die "should never be here!";
    }
  }
  
  return 1;
}


1;
