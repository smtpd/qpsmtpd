package Qpsmtpd::SMTP;
use Qpsmtpd;
@ISA = qw(Qpsmtpd);

package Qpsmtpd::SMTP;
use strict;
use Carp;

use Qpsmtpd::Connection;
use Qpsmtpd::Transaction;
use Qpsmtpd::Plugin;
use Qpsmtpd::Constants;
use Qpsmtpd::Auth;
use Qpsmtpd::Address ();

use Mail::Header ();
#use Data::Dumper;
use POSIX qw(strftime);
use Net::DNS;

# this is only good for forkserver
# can't set these here, cause forkserver resets them
#$SIG{ALRM} = sub { respond(421, "Game over pal, game over. You got a timeout; I just can't wait that long..."); exit };
#$SIG{ALRM} = sub { warn "Connection Timed Out\n"; exit; };

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

sub command_counter {
  my $self = shift;
  $self->{_counter} || 0;
}

sub dispatch {
  my $self = shift;
  my ($cmd) = lc shift;

  $self->{_counter}++; 

  if ($cmd !~ /^(\w{1,12})$/ or !exists $self->{_commands}->{$1}) {
    my ($rc, $msg) = $self->run_hooks("unrecognized_command", $cmd, @_);
    if ($rc == DENY_DISCONNECT) {
      $self->respond(521, $msg);
      $self->disconnect;
    }
    elsif ($rc == DENY) {
      $self->respond(500, $msg);
    }
    elsif ($rc == DONE) {
      1;
    }
    else {
      $self->respond(500, "Unrecognized command");
    }
    return 1
  }
  $cmd = $1;

  if (1 or $self->{_commands}->{$cmd} and $self->can($cmd)) {
    my ($result) = eval { $self->$cmd(@_) };
    $self->log(LOGERROR, "XX: $@") if $@;
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
    # this should maybe be called something else than "connect", see
    # lib/Qpsmtpd/TcpServer.pm for more confusion.
    my ($rc, $msg) = $self->run_hooks("connect");
    if ($rc == DENY) {
      $self->respond(550, ($msg || 'Connection from you denied, bye bye.'));
      return $rc;
    }
    elsif ($rc == DENYSOFT) {
      $self->respond(450, ($msg || 'Connection from you temporarily denied, bye bye.'));
      return $rc;
    }
    elsif ($rc == DONE) {
      return $rc;
    }
    elsif ($rc != DONE) {
      $self->respond(220, $self->config('me') ." ESMTP qpsmtpd "
          . $self->version ." ready; send us your mail, but not your spam.");
      return DONE;
    }
}

sub transaction {
  my $self = shift;
  return $self->{_transaction} || $self->reset_transaction();
}

sub reset_transaction {
  my $self = shift;
  $self->run_hooks("reset_transaction") if $self->{_transaction};
  return $self->{_transaction} = Qpsmtpd::Transaction->new();
}


sub connection {
  my $self = shift;
  @_ and $self->{_connection} = shift;
  return $self->{_connection} || ($self->{_connection} = Qpsmtpd::Connection->new());
}


sub helo {
  my ($self, $hello_host, @stuff) = @_;
  return $self->respond (501,
    "helo requires domain/address - see RFC-2821 4.1.1.1") unless $hello_host;
  my $conn = $self->connection;
  return $self->respond (503, "but you already said HELO ...") if $conn->hello;

  my ($rc, $msg) = $self->run_hooks("helo", $hello_host, @stuff);
  if ($rc == DONE) {
    # do nothing
  } elsif ($rc == DENY) {
    $self->respond(550, $msg);
  } elsif ($rc == DENYSOFT) {
    $self->respond(450, $msg);
  } elsif ($rc == DENY_DISCONNECT) {
      $self->respond(550, $msg);
      $self->disconnect;
  } elsif ($rc == DENYSOFT_DISCONNECT) {
      $self->respond(450, $msg);
      $self->disconnect;
  } else {
    $conn->hello("helo");
    $conn->hello_host($hello_host);
    $self->transaction;
    $self->respond(250, $self->config('me') ." Hi " . $conn->remote_info . " [" . $conn->remote_ip ."]; I am so happy to meet you.");
  }
}

sub ehlo {
  my ($self, $hello_host, @stuff) = @_;
  return $self->respond (501,
    "ehlo requires domain/address - see RFC-2821 4.1.1.1") unless $hello_host;
  my $conn = $self->connection;
  return $self->respond (503, "but you already said HELO ...") if $conn->hello;

  my ($rc, $msg) = $self->run_hooks("ehlo", $hello_host, @stuff);
  if ($rc == DONE) {
    # do nothing
  } elsif ($rc == DENY) {
    $self->respond(550, $msg);
  } elsif ($rc == DENYSOFT) {
    $self->respond(450, $msg);
  } elsif ($rc == DENY_DISCONNECT) {
      $self->respond(550, $msg);
      $self->disconnect;
  } elsif ($rc == DENYSOFT_DISCONNECT) {
      $self->respond(450, $msg);
      $self->disconnect;
  } else {
    $conn->hello("ehlo");
    $conn->hello_host($hello_host);
    $self->transaction;

    my @capabilities = $self->transaction->notes('capabilities')
                        ? @{ $self->transaction->notes('capabilities') }
                        : ();  

    # Check for possible AUTH mechanisms
    my %auth_mechanisms;
HOOK: foreach my $hook ( keys %{$self->{hooks}} ) {
        if ( $hook =~ m/^auth-?(.+)?$/ ) {
            if ( defined $1 ) {
                $auth_mechanisms{uc($1)} = 1;
            }
            else { # at least one polymorphous auth provider
                %auth_mechanisms = map {$_,1} qw(PLAIN CRAM-MD5 LOGIN);
                last HOOK;
            }
        }
    }

    if ( %auth_mechanisms ) {
        push @capabilities, 'AUTH '.join(" ",keys(%auth_mechanisms));    
        $self->{_commands}->{'auth'} = "";
    }

    $self->respond(250,
                 $self->config("me") . " Hi " . $conn->remote_info . " [" . $conn->remote_ip ."]",
                 "PIPELINING",
                 "8BITMIME",
                 ($self->config('databytes') ? "SIZE ". ($self->config('databytes'))[0] : ()),
                 @capabilities,  
                );
  }
}

sub mail {
  my $self = shift;
  return $self->respond(501, "syntax error in parameters") if !$_[0] or $_[0] !~ m/^from:/i;

  # -> from RFC2821
  # The MAIL command (or the obsolete SEND, SOML, or SAML commands)
  # begins a mail transaction.  Once started, a mail transaction
  # consists of a transaction beginning command, one or more RCPT
  # commands, and a DATA command, in that order.  A mail transaction
  # may be aborted by the RSET (or a new EHLO) command.  There may be
  # zero or more transactions in a session.  MAIL (or SEND, SOML, or
  # SAML) MUST NOT be sent if a mail transaction is already open,
  # i.e., it should be sent only if no mail transaction had been
  # started in the session, or it the previous one successfully
  # concluded with a successful DATA command, or if the previous one
  # was aborted with a RSET.

  # sendmail (8.11) rejects a second MAIL command.

  # qmail-smtpd (1.03) accepts it and just starts a new transaction.
  # Since we are a qmail-smtpd thing we will do the same.

  $self->reset_transaction;

  unless ($self->connection->hello) {
    return $self->respond(503, "please say hello first ...");
  }
  else {
    my $from_parameter = join " ", @_;
    $self->log(LOGINFO, "full from_parameter: $from_parameter");

    my ($from) = ($from_parameter =~ m/^from:\s*(<[^>]*>)/i)[0];

    # support addresses without <> ... maybe we shouldn't?
    ($from) = "<" . ($from_parameter =~ m/^from:\s*(\S+)/i)[0] . ">"
      unless $from;

    $self->log(LOGALERT, "from email address : [$from]");

    if ($from eq "<>" or $from =~ m/\[undefined\]/ or $from eq "<#@[]>") {
      $from = Qpsmtpd::Address->new("<>");
    } 
    else {
      $from = (Qpsmtpd::Address->parse($from))[0];
    }
    return $self->respond(501, "could not parse your mail from command") unless $from;

    my ($rc, $msg) = $self->run_hooks("mail", $from);
    if ($rc == DONE) {
      return 1;
    }
    elsif ($rc == DENY) {
      $msg ||= $from->format . ', denied';
      $self->log(LOGINFO, "deny mail from " . $from->format . " ($msg)");
      $self->respond(550, $msg);
    }
    elsif ($rc == DENYSOFT) {
      $msg ||= $from->format . ', temporarily denied';
      $self->log(LOGINFO, "denysoft mail from " . $from->format . " ($msg)");
      $self->respond(450, $msg);
    }
    elsif ($rc == DENY_DISCONNECT) {
      $msg ||= $from->format . ', denied';
      $self->log(LOGINFO, "deny mail from " . $from->format . " ($msg)");
      $self->respond(550, $msg);
      $self->disconnect;
    }
    elsif ($rc == DENYSOFT_DISCONNECT) {
      $msg ||= $from->format . ', temporarily denied';
      $self->log(LOGINFO, "denysoft mail from " . $from->format . " ($msg)");
      $self->respond(421, $msg);
      $self->disconnect;
    }
    else { # includes OK
      $self->log(LOGINFO, "getting mail from ".$from->format);
      $self->respond(250, $from->format . ", sender OK - how exciting to get mail from you!");
      $self->transaction->sender($from);
    }
  }
}

sub rcpt {
  my $self = shift;
  return $self->respond(501, "syntax error in parameters") unless $_[0] and $_[0] =~ m/^to:/i;
  return $self->respond(503, "Use MAIL before RCPT") unless $self->transaction->sender;

  my ($rcpt) = ($_[0] =~ m/to:(.*)/i)[0];
  $rcpt = $_[1] unless $rcpt;
  $self->log(LOGALERT, "to email address : [$rcpt]");
  $rcpt = (Qpsmtpd::Address->parse($rcpt))[0];

  return $self->respond(501, "could not parse recipient") unless $rcpt;

  my ($rc, $msg) = $self->run_hooks("rcpt", $rcpt);
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $msg ||= 'relaying denied';
    $self->respond(550, $msg);
  }
  elsif ($rc == DENYSOFT) {
    $msg ||= 'relaying denied';
    return $self->respond(450, $msg);
  }
  elsif ($rc == DENY_DISCONNECT) {
      $msg ||= 'delivery denied';
      $self->log(LOGINFO, "delivery denied ($msg)");
      $self->respond(550, $msg);
      $self->disconnect;
  }
  elsif ($rc == DENYSOFT_DISCONNECT) {
    $msg ||= 'relaying denied';
    $self->log(LOGINFO, "delivery denied ($msg)");
    $self->respond(421, $msg);
    $self->disconnect;
  }
  elsif ($rc == OK) {
    $self->respond(250, $rcpt->format . ", recipient ok");
    return $self->transaction->add_recipient($rcpt);
  }
  else {
    return $self->respond(450, "No plugin decided if relaying is allowed");
  }
  return 0;
}



sub help {
  my $self = shift;
  $self->respond(214, 
          "This is qpsmtpd " . $self->version,
          "See http://smtpd.develooper.com/",
          'To report bugs or send comments, mail to <ask@develooper.com>.');
}

sub noop {
  my $self = shift;
  $self->respond(250, "OK");
}

sub vrfy {
  my $self = shift;

  # Note, this doesn't support the multiple ambiguous results
  # documented in RFC2821#3.5.1
  # I also don't think it provides all the proper result codes.

  my ($rc, $msg) = $self->run_hooks("vrfy");
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $self->respond(554, $msg || "Access Denied");
    $self->reset_transaction();
    return 1;
  }
  elsif ($rc == OK) {
    $self->respond(250, $msg || "User OK");
    return 1;
  }
  else { # $rc == DECLINED or anything else
    $self->respond(252, "Just try sending a mail and we'll see how it turns out ...");
    return 1;
  }
}

sub rset {
  my $self = shift;
  $self->reset_transaction;
  $self->respond(250, "OK");
}

sub quit {
  my $self = shift;
  my ($rc, $msg) = $self->run_hooks("quit");
  if ($rc != DONE) {
    $self->respond(221, $self->config('me') . " closing connection. Have a wonderful day.");
  }
  $self->disconnect();
}

sub disconnect {
  my $self = shift;
  $self->run_hooks("disconnect");
  $self->reset_transaction;
}

sub data {
  my $self = shift;
  my ($rc, $msg) = $self->run_hooks("data");
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $self->respond(554, $msg || "Message denied");
    $self->reset_transaction();
    return 1;
  }
  elsif ($rc == DENYSOFT) {
    $self->respond(451, $msg || "Message denied temporarily");
    $self->reset_transaction();
    return 1;
  } 
  elsif ($rc == DENY_DISCONNECT) {
    $self->respond(554, $msg || "Message denied");
    $self->disconnect;
    return 1;
  }
  elsif ($rc == DENYSOFT_DISCONNECT) {
    $self->respond(421, $msg || "Message denied temporarily");
    $self->disconnect;
    return 1;
  }
  $self->respond(503, "MAIL first"), return 1 unless $self->transaction->sender;
  $self->respond(503, "RCPT first"), return 1 unless $self->transaction->recipients;
  $self->respond(354, "go ahead");
  
  my $buffer = '';
  my $size = 0;
  my $i = 0;
  my $max_size = ($self->config('databytes'))[0] || 0;  # this should work in scalar context
  my $blocked = "";
  my %matches;
  my $in_header = 1;
  my $complete = 0;

  $self->log(LOGDEBUG, "max_size: $max_size / size: $size");

  my $header = Mail::Header->new(Modify => 0, MailFrom => "COERCE");

  my $timeout = $self->config('timeout');
  while (defined($_ = $self->getline($timeout))) {
    $complete++, last if $_ eq ".\r\n";
    $i++;

    # should probably use \012 and \015 in these checks instead of \r and \n ...

    # Reject messages that have either bare LF or CR. rjkaes noticed a
    # lot of spam that is malformed in the header.

    ($_ eq ".\n" or $_ eq ".\r")
        and $self->respond(421, "See http://smtpd.develooper.com/barelf.html")
        and return $self->disconnect;

    # add a transaction->blocked check back here when we have line by line plugin access...
    unless (($max_size and $size > $max_size)) {
      s/\r\n$/\n/;
      s/^\.\./\./;
      if ($in_header and m/^\s*$/) {
        $in_header = 0;
        my @headers = split /^/m, $buffer;

        # ... need to check that we don't reformat any of the received lines.
        #
        # 3.8.2 Received Lines in Gatewaying
        #   When forwarding a message into or out of the Internet environment, a
        #   gateway MUST prepend a Received: line, but it MUST NOT alter in any
        #   way a Received: line that is already in the header.

        $header->extract(\@headers);
        #$header->add("X-SMTPD", "qpsmtpd/".$self->version.", http://smtpd.develooper.com/");

        $buffer = "";

        # FIXME - call plugins to work on just the header here; can
        # save us buffering the mail content.

	# Save the start of just the body itself	
	$self->transaction->set_body_start();

      }

      # grab a copy of all of the header lines
      if ($in_header) {
        $buffer .= $_;  
      }

      # copy all lines into the spool file, including the headers
      # we will create a new header later before sending onwards
      $self->transaction->body_write($_);
      $size += length $_;
    }
    #$self->log(LOGDEBUG, "size is at $size\n") unless ($i % 300);
  }

  $self->log(LOGDEBUG, "max_size: $max_size / size: $size");

  $self->transaction->header($header);

  my $smtp = $self->connection->hello eq "ehlo" ? "ESMTP" : "SMTP";
  my $authheader = (defined $self->{_auth} and $self->{_auth} == OK) ?
    "(smtp-auth username $self->{_auth_user}, mechanism $self->{_auth_mechanism})\n" : "";

  $header->add("Received", "from ".$self->connection->remote_info
               ." (HELO ".$self->connection->hello_host . ") (".$self->connection->remote_ip
               . ")\n  $authheader  by ".$self->config('me')." (qpsmtpd/".$self->version
               .") with $smtp; ". (strftime('%a, %d %b %Y %H:%M:%S %z', localtime)),
               0);

  # if we get here without seeing a terminator, the connection is
  # probably dead.
  $self->respond(451, "Incomplete DATA"), return 1 unless $complete;

  #$self->respond(550, $self->transaction->blocked),return 1 if ($self->transaction->blocked);
  $self->respond(552, "Message too big!"),return 1 if $max_size and $size > $max_size;

  ($rc, $msg) = $self->run_hooks("data_post");
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $self->respond(552, $msg || "Message denied");
  }
  elsif ($rc == DENYSOFT) {
    $self->respond(452, $msg || "Message denied temporarily");
  } 
  else {
    $self->queue($self->transaction);    
  }

  # DATA is always the end of a "transaction"
  return $self->reset_transaction;

}

sub getline {
  my ($self, $timeout) = @_;
  
  alarm $timeout;
  my $line = <STDIN>; # default implementation
  alarm 0;
  return $line;
}

sub queue {
  my ($self, $transaction) = @_;

  my ($rc, $msg) = $self->run_hooks("queue");
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == OK) {
    $self->respond(250, ($msg || 'Queued'));
  }
  elsif ($rc == DENY) {
    $self->respond(552, $msg || "Message denied");
  }
  elsif ($rc == DENYSOFT) {
    $self->respond(452, $msg || "Message denied temporarily");
  } 
  else {
    $self->respond(451, $msg || "Queuing declined or disabled; try again later" );
  }


}


1;
