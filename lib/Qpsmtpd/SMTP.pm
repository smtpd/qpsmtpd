package Qpsmtpd::SMTP;
use Qpsmtpd;
@ISA = qw(Qpsmtpd);
my %auth_mechanisms = ();

package Qpsmtpd::SMTP;
use strict;
use Carp;

use Qpsmtpd::Connection;
use Qpsmtpd::Transaction;
use Qpsmtpd::Plugin;
use Qpsmtpd::Constants;
use Qpsmtpd::Auth;
use Qpsmtpd::Address ();
use Qpsmtpd::Command;

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
  $self->SUPER::_restart(%args) if $args{restart}; # calls Qpsmtpd::_restart()
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
    $self->run_hooks("unrecognized_command", $cmd, @_);
    return 1;
  }
  $cmd = $1;

    my ($result) = eval { $self->$cmd(@_) };
    $self->log(LOGERROR, "XX: $@") if $@;
    return $result if defined $result;
    return $self->fault("command '$cmd' failed unexpectedly");
}

sub unrecognized_command_respond {
    my ($self, $rc, $msg) = @_;
    if ($rc == DENY_DISCONNECT) {
      $self->respond(521, @$msg);
      $self->disconnect;
    }
    elsif ($rc == DENY) {
      $self->respond(500, @$msg);
    }
    elsif ($rc != DONE) {
      $self->respond(500, "Unrecognized command");
    }
}

sub fault {
  my $self = shift;
  my ($msg) = shift || "program fault - command not performed";
  my ($name) = split /\s+/, $0, 2;
  print STDERR $name,"[$$]: $msg ($!)\n";
  return $self->respond(451, "Internal error - try again later - " . $msg);
}


sub start_conversation {
    my $self = shift;
    # this should maybe be called something else than "connect", see
    # lib/Qpsmtpd/TcpServer.pm for more confusion.
    $self->run_hooks("connect");
    return DONE;
}

sub connect_respond {
    my ($self, $rc, $msg) = @_;
    if ($rc == DENY || $rc == DENY_DISCONNECT) {
      $msg->[0] ||= 'Connection from you denied, bye bye.';
      $self->respond(550, @$msg);
      $self->disconnect;
    }
    elsif ($rc == DENYSOFT || $rc == DENYSOFT_DISCONNECT) {
      $msg->[0] ||= 'Connection from you temporarily denied, bye bye.';
      $self->respond(450, @$msg);
      $self->disconnect;
    }
    elsif ($rc != DONE) {
      my $greets = $self->config('smtpgreeting');
      if ( $greets ) {
	  $greets .= " ESMTP" unless $greets =~ /(^|\W)ESMTP(\W|$)/;
      }
      else {
	  $greets = $self->config('me') 
	    . " ESMTP qpsmtpd " 
	    . $self->version 
	    . " ready; send us your mail, but not your spam.";
      }

      $self->respond(220, $greets);
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
  my ($self, $line) = @_;
  my ($rc, @msg) = $self->run_hooks('helo_parse');
  my ($ok, $hello_host, @stuff) = Qpsmtpd::Command->parse('helo', $line, $msg[0]);

  return $self->respond (501,
    "helo requires domain/address - see RFC-2821 4.1.1.1") unless $hello_host;
  my $conn = $self->connection;
  return $self->respond (503, "but you already said HELO ...") if $conn->hello;

  $self->run_hooks("helo", $hello_host, @stuff);
}

sub helo_respond {
  my ($self, $rc, $msg, $args) = @_;
  my ($hello_host) = @$args;
  if ($rc == DONE) {
    # do nothing:
    1;
  } elsif ($rc == DENY) {
    $self->respond(550, @$msg);
  } elsif ($rc == DENYSOFT) {
    $self->respond(450, @$msg);
  } elsif ($rc == DENY_DISCONNECT) {
      $self->respond(550, @$msg);
      $self->disconnect;
  } elsif ($rc == DENYSOFT_DISCONNECT) {
      $self->respond(450, @$msg);
      $self->disconnect;
  } else {
    my $conn = $self->connection;
    $conn->hello("helo");
    $conn->hello_host($hello_host);
    $self->transaction;
    $self->respond(250, $self->config('me') ." Hi " . $conn->remote_info . " [" . $conn->remote_ip ."]; I am so happy to meet you.");
  }
}

sub ehlo {
  my ($self, $line) = @_;
  my ($rc, @msg) = $self->run_hooks('ehlo_parse');
  my ($ok, $hello_host, @stuff) = Qpsmtpd::Command->parse('ehlo', $line, $msg[0]);
  return $self->respond (501,
    "ehlo requires domain/address - see RFC-2821 4.1.1.1") unless $hello_host;
  my $conn = $self->connection;
  return $self->respond (503, "but you already said HELO ...") if $conn->hello;

  $self->run_hooks("ehlo", $hello_host, @stuff);
}

sub ehlo_respond {
  my ($self, $rc, $msg, $args) = @_;
  my ($hello_host) = @$args;
  if ($rc == DONE) {
    # do nothing:
    1; 
  } elsif ($rc == DENY) {
    $self->respond(550, @$msg);
  } elsif ($rc == DENYSOFT) {
    $self->respond(450, @$msg);
  } elsif ($rc == DENY_DISCONNECT) {
      $self->respond(550, @$msg);
      $self->disconnect;
  } elsif ($rc == DENYSOFT_DISCONNECT) {
      $self->respond(450, @$msg);
      $self->disconnect;
  } else {
    my $conn = $self->connection;
    $conn->hello("ehlo");
    $conn->hello_host($hello_host);
    $self->transaction;

    my @capabilities = $self->transaction->notes('capabilities')
                        ? @{ $self->transaction->notes('capabilities') }
                        : ();  

    # Check for possible AUTH mechanisms
HOOK: foreach my $hook ( keys %{$self->hooks} ) {
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

    # Check if we should only offer AUTH after TLS is completed
    my $tls_before_auth = ($self->config('tls_before_auth') ? ($self->config('tls_before_auth'))[0] && $self->transaction->notes('tls_enabled') : 0); 
    if ( %auth_mechanisms && !$tls_before_auth) {
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

sub auth {
    my ($self, $line) = @_;
    $self->run_hooks('auth_parse', $line);
}

sub auth_parse_respond {
    my ($self, $rc, $msg, $args) = @_;
    my ($line) = @$args;

    my ($ok, $mechanism, @stuff) = Qpsmtpd::Command->parse('auth', $line, $msg->[0]);
    return $self->respond(501, $mechanism || "Syntax error in command") 
      unless ($ok == OK);

    $mechanism = lc($mechanism);

    #they AUTH'd once already
    return $self->respond( 503, "but you already said AUTH ..." )
      if ( defined $self->{_auth} && $self->{_auth} == OK );

    return $self->respond( 503, "AUTH not defined for HELO" )
      if ( $self->connection->hello eq "helo" );

    return $self->respond( 503, "SSL/TLS required before AUTH" )
      if ( ($self->config('tls_before_auth'))[0] 
        && $self->transaction->notes('tls_enabled') );

    # we don't have a plugin implementing this auth mechanism, 504
    if( exists $auth_mechanisms{uc($mechanism)} ) {
      return $self->{_auth} = Qpsmtpd::Auth::SASL( $self, $mechanism, @stuff );
    };

    $self->respond( 504, "Unimplemented authentification mechanism: $mechanism" );
    return DENY;
}

sub mail {
  my ($self, $line) = @_;
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
    $self->log(LOGDEBUG, "full from_parameter: $line");
    $self->run_hooks("mail_parse", $line);
  }
}

sub mail_parse_respond {
    my ($self, $rc, $msg, $args) = @_;
    my ($line) = @$args;
    my ($ok, $from, @params) = Qpsmtpd::Command->parse('mail', $line, $msg->[0]);
    return $self->respond(501, $from || "Syntax error in command") 
      unless ($ok == OK); 
    my %param;
    foreach (@params) {
        my ($k,$v) = split /=/, $_, 2;
        $param{lc $k} = $v;
    }
    # to support addresses without <> we now require a plugin
    # hooking "mail_pre" to 
    #   return (OK, "<$from>"); 
    # (...or anything else parseable by Qpsmtpd::Address ;-))
    # see also comment in sub rcpt()
    $self->run_hooks("mail_pre", $from, \%param);
}

sub mail_pre_respond {
    my ($self, $rc, $msg, $args) = @_;
    my ($from, $param) = @$args;
    if ($rc == OK) {
      $from = shift @$msg;
    }

    $self->log(LOGDEBUG, "from email address : [$from]");
    return $self->respond(501, "could not parse your mail from command") 
      unless $from =~ /^<.*>$/;

    if ($from eq "<>" or $from =~ m/\[undefined\]/ or $from eq "<#@[]>") {
      $from = Qpsmtpd::Address->new("<>");
    } 
    else {
      $from = (Qpsmtpd::Address->parse($from))[0];
    }
    return $self->respond(501, "could not parse your mail from command") unless $from;

    $self->run_hooks("mail", $from, %$param);
}

sub mail_respond {
    my ($self, $rc, $msg, $args) = @_;
    my ($from, $param) = @$args;
    if ($rc == DONE) {
      return 1;
    }
    elsif ($rc == DENY) {
      $msg->[0] ||= $from->format . ', denied';
      $self->log(LOGINFO, "deny mail from " . $from->format . " (@$msg)");
      $self->respond(550, @$msg);
    }
    elsif ($rc == DENYSOFT) {
      $msg->[0] ||= $from->format . ', temporarily denied';
      $self->log(LOGINFO, "denysoft mail from " . $from->format . " (@$msg)");
      $self->respond(450, @$msg);
    }
    elsif ($rc == DENY_DISCONNECT) {
      $msg->[0] ||= $from->format . ', denied';
      $self->log(LOGINFO, "deny mail from " . $from->format . " (@$msg)");
      $self->respond(550, @$msg);
      $self->disconnect;
    }
    elsif ($rc == DENYSOFT_DISCONNECT) {
      $msg->[0] ||= $from->format . ', temporarily denied';
      $self->log(LOGINFO, "denysoft mail from " . $from->format . " (@$msg)");
      $self->respond(421, @$msg);
      $self->disconnect;
    }
    else { # includes OK
      $self->log(LOGDEBUG, "getting mail from ".$from->format);
      $self->respond(250, $from->format . ", sender OK - how exciting to get mail from you!");
      $self->transaction->sender($from);
    }
}

sub rcpt {
  my ($self, $line) = @_;
  $self->run_hooks("rcpt_parse", $line);
}

sub rcpt_parse_respond {
  my ($self, $rc, $msg, $args) = @_;
  my ($line) = @$args;
  my ($ok, $rcpt, @param) = Qpsmtpd::Command->parse("rcpt", $line, $msg->[0]);
  return $self->respond(501, $rcpt || "Syntax error in command")
    unless ($ok == OK);
  return $self->respond(503, "Use MAIL before RCPT") unless $self->transaction->sender;

  my %param;
  foreach (@param) {
    my ($k,$v) = split /=/, $_, 2;
    $param{lc $k} = $v;
  }
  # to support addresses without <> we now require a plugin
  # hooking "rcpt_pre" to 
  #   return (OK, "<$rcpt>"); 
  # (... or anything else parseable by Qpsmtpd::Address ;-))
  # this means, a plugin can decide to (pre-)accept
  # addresses like <user@example.com.> or <user@example.com >
  # by removing the trailing "."/" " from this example...
  $self->run_hooks("rcpt_pre", $rcpt, \%param);
}

sub rcpt_pre_respond {
  my ($self, $rc, $msg, $args) = @_;
  my ($rcpt, $param) = @$args;
  if ($rc == OK) {
    $rcpt = shift @$msg;
  }
  $self->log(LOGDEBUG, "to email address : [$rcpt]");
  return $self->respond(501, "could not parse recipient") 
    unless $rcpt =~ /^<.*>$/;

  $rcpt = (Qpsmtpd::Address->parse($rcpt))[0];

  return $self->respond(501, "could not parse recipient") 
    if (!$rcpt or ($rcpt->format eq '<>'));

  $self->run_hooks("rcpt", $rcpt, %$param);
}

sub rcpt_respond {
  my ($self, $rc, $msg, $args) = @_;
  my ($rcpt, $param) = @$args;
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $msg->[0] ||= 'relaying denied';
    $self->respond(550, @$msg);
  }
  elsif ($rc == DENYSOFT) {
    $msg->[0] ||= 'relaying denied';
    return $self->respond(450, @$msg);
  }
  elsif ($rc == DENY_DISCONNECT) {
      $msg->[0] ||= 'delivery denied';
      $self->log(LOGINFO, "delivery denied (@$msg)");
      $self->respond(550, @$msg);
      $self->disconnect;
  }
  elsif ($rc == DENYSOFT_DISCONNECT) {
    $msg->[0] ||= 'relaying denied';
    $self->log(LOGINFO, "delivery denied (@$msg)");
    $self->respond(421, @$msg);
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
  my ($self, @args) = @_;
  $self->run_hooks("help", @args);
}

sub help_respond {
  my ($self, $rc, $msg, $args) = @_;

  return 1 
    if $rc == DONE;

  if ($rc == DENY) {
    $msg->[0] ||= "Syntax error, command not recognized";
    $self->respond(500, @$msg);
  }
  else {
    unless ($msg->[0]) {
      @$msg = (
        "This is qpsmtpd " . ($self->config('smtpgreeting') ? '' : $self->version),
        "See http://smtpd.develooper.com/",
        'To report bugs or send comments, mail to <ask@develooper.com>.');
    }
    $self->respond(214, @$msg);
  }
  return 1;
}

sub noop {
  my $self = shift;
  $self->run_hooks("noop");
}

sub noop_respond {
  my ($self, $rc, $msg, $args) = @_;
  return 1 if $rc == DONE;

  if ($rc == DENY || $rc == DENY_DISCONNECT) {
    $msg->[0] ||= "Stop wasting my time."; # FIXME: better default message?
    $self->respond(500, @$msg);
    $self->disconnect if $rc == DENY_DISCONNECT;
    return 1;
  }

  $self->respond(250, "OK");
  return 1;
}

sub vrfy {
  my $self = shift;

  # Note, this doesn't support the multiple ambiguous results
  # documented in RFC2821#3.5.1
  # I also don't think it provides all the proper result codes.

  $self->run_hooks("vrfy");
}

sub vrfy_respond {
  my ($self, $rc, $msg, $args) = @_;
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $msg->[0] ||= "Access Denied";
    $self->respond(554, @$msg);
    $self->reset_transaction();
    return 1;
  }
  elsif ($rc == OK) {
    $msg->[0] ||= "User OK";
    $self->respond(250, @$msg);
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
  $self->run_hooks("quit");
}

sub quit_respond {
  my ($self, $rc, $msg, $args) = @_;
  if ($rc != DONE) {
    $msg->[0] ||= $self->config('me') . " closing connection. Have a wonderful day.";
    $self->respond(221, @$msg);
  }
  $self->disconnect();
}

sub disconnect {
  my $self = shift;
  $self->run_hooks("disconnect");
  $self->connection->notes(disconnected => 1);
  $self->reset_transaction;
}

sub data {
  my $self = shift;
  $self->run_hooks("data");
}

sub data_respond {
  my ($self, $rc, $msg, $args) = @_;
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $msg->[0] ||= "Message denied";
    $self->respond(554, @$msg);
    $self->reset_transaction();
    return 1;
  }
  elsif ($rc == DENYSOFT) {
    $msg->[0] ||= "Message denied temporarily";
    $self->respond(451, @$msg);
    $self->reset_transaction();
    return 1;
  } 
  elsif ($rc == DENY_DISCONNECT) {
    $msg->[0] ||= "Message denied";
    $self->respond(554, @$msg);
    $self->disconnect;
    return 1;
  }
  elsif ($rc == DENYSOFT_DISCONNECT) {
    $msg->[0] ||= "Message denied temporarily";
    $self->respond(421, @$msg);
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
      if ($in_header and m/^$/) {
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

        $self->transaction->header($header);

        # NOTE: This will not work properly under async.  A
        # data_headers_end_respond needs to be created.
        my ($rc, $msg) = $self->run_hooks('data_headers_end');
        if ($rc == DENY_DISCONNECT) {
          $self->respond(554, $msg || "Message denied");
          $self->disconnect;
          return 1;
        } elsif ($rc == DENYSOFT_DISCONNECT) {
          $self->respond(421, $msg || "Message denied temporarily");
          $self->disconnect;
          return 1;
        }

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

  my $smtp = $self->connection->hello eq "ehlo" ? "ESMTP" : "SMTP";
  my $esmtp = substr($smtp,0,1) eq "E";
  my $authheader = '';
  my $sslheader = '';

  if (defined $self->connection->notes('tls_enabled')
      and $self->connection->notes('tls_enabled')) {
    $smtp .= "S" if $esmtp; # RFC3848
    $sslheader = "(".$self->connection->notes('tls_socket')->get_cipher()." encrypted) ";
  }

  if (defined $self->{_auth} and $self->{_auth} == OK) {
    $smtp .= "A" if $esmtp; # RFC3848
    $authheader = "(smtp-auth username $self->{_auth_user}, mechanism $self->{_auth_mechanism})\n";
  }

  $header->add("Received", $self->received_line($smtp, $authheader, $sslheader), 0);

  # if we get here without seeing a terminator, the connection is
  # probably dead.
  unless ( $complete ) {
      $self->respond(451, "Incomplete DATA");
      $self->reset_transaction; # clean up after ourselves
      return 1;
  }

  #$self->respond(550, $self->transaction->blocked),return 1 if ($self->transaction->blocked);
  if ($max_size and $size > $max_size) {
      $self->log(LOGALERT, "Message too big: size: $size (max size: $max_size)");
      $self->respond(552, "Message too big!"); 
      $self->reset_transaction; # clean up after ourselves
      return 1;
  }

  $self->run_hooks("data_post");
}

sub received_line {
  my ($self, $smtp, $authheader, $sslheader) = @_;
  my ($rc, @received) = $self->run_hooks("received_line", $smtp, $authheader, $sslheader);
  if ($rc == YIELD) {
    die "YIELD not supported for received_line hook";
  }
  elsif ($rc == OK) {
    return join("\n", @received);
  }
  else { # assume $rc == DECLINED
    return  "from ".$self->connection->remote_info
           ." (HELO ".$self->connection->hello_host . ") (".$self->connection->remote_ip
           . ")\n  $authheader  by ".$self->config('me')." (qpsmtpd/".$self->version
           .") with $sslheader$smtp; ". (strftime('%a, %d %b %Y %H:%M:%S %z', localtime))
  }
}

sub data_post_respond {
  my ($self, $rc, $msg, $args) = @_;
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == DENY) {
    $msg->[0] ||= "Message denied";
    $self->respond(552, @$msg);
    # DATA is always the end of a "transaction"
    return $self->reset_transaction;
  }
  elsif ($rc == DENYSOFT) {
    $msg->[0] ||= "Message denied temporarily";
    $self->respond(452, @$msg);
    # DATA is always the end of a "transaction"
    return $self->reset_transaction;
  } 
  elsif ($rc == DENY_DISCONNECT) {
    $msg->[0] ||= "Message denied";
    $self->respond(552, @$msg);
    $self->disconnect;
    return 1;
  }
  elsif ($rc == DENYSOFT_DISCONNECT) {
    $msg->[0] ||= "Message denied temporarily";
    $self->respond(452, @$msg);
    $self->disconnect;
    return 1;
  }
  else {
    $self->queue($self->transaction);
  }
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

  # First fire any queue_pre hooks
  $self->run_hooks("queue_pre");
}

sub queue_pre_respond {
  my ($self, $rc, $msg, $args) = @_;
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc != OK and $rc != DECLINED and $rc != 0 ) {
    return $self->log(LOGERROR, "pre plugin returned illegal value");
    return 0;
  }

  # If we got this far, run the queue hooks
  $self->run_hooks("queue");
}

sub queue_respond {
  my ($self, $rc, $msg, $args) = @_;
  
  # reset transaction if we queued the mail
  $self->reset_transaction;
  
  if ($rc == DONE) {
    return 1;
  }
  elsif ($rc == OK) {
    $msg->[0] ||= 'Queued';
    $self->respond(250, @$msg);
  }
  elsif ($rc == DENY) {
    $msg->[0] ||= 'Message denied';
    $self->respond(552, @$msg);
  }
  elsif ($rc == DENYSOFT) {
    $msg->[0] ||= 'Message denied temporarily';
    $self->respond(452, @$msg);
  } 
  else {
    $msg->[0] ||= 'Queuing declined or disabled; try again later';
    $self->respond(451, @$msg);
  }
  
  # And finally run any queue_post hooks
  $self->run_hooks("queue_post");
}

sub queue_post_respond {
  my ($self, $rc, $msg, $args) = @_;
  $self->log(LOGERROR, @$msg) unless ($rc == OK or $rc == 0);
}


1;
