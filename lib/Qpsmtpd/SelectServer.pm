package Qpsmtpd::SelectServer;
use Qpsmtpd::SMTP;
use Qpsmtpd::Constants;
use IO::Socket;
use IO::Select;
use POSIX qw(strftime);
use Socket qw(CRLF);
use Fcntl;
use Tie::RefHash;
use Net::DNS;

@ISA = qw(Qpsmtpd::SMTP);
use strict;

our %inbuffer = ();
our %outbuffer = ();
our %ready = ();
our %lookup = ();
our %qp = ();
our %indata = ();

tie %ready, 'Tie::RefHash';
my $server;
my $select;

our $QUIT = 0;

$SIG{INT} = $SIG{TERM} = sub { $QUIT++ };

sub log {
  my ($self, $trace, @log) = @_;
  warn join(" ", fileno($self->client), @log), "\n"
    if $trace <= Qpsmtpd::TRACE_LEVEL();
}

sub main {
    my $class = shift;
    my %opts = (LocalPort => 25, Reuse => 1, Listen => SOMAXCONN, @_);
    $server = IO::Socket::INET->new(%opts) or die "Server: $@";
    print "Listening on $opts{LocalPort}\n";
    
    nonblock($server);
    
    $select = IO::Select->new($server);
    my $res = Net::DNS::Resolver->new;
    
    # TODO - make this more graceful - let all current SMTP sessions finish
    # before quitting!
    while (!$QUIT) {
        foreach my $client ($select->can_read(1)) {
            #print "Reading $client\n";
            if ($client == $server) {
                my $client_addr;
                $client = $server->accept();
                next unless $client;
                my $ip = $client->peerhost;
                my $bgsock  = $res->bgsend($ip);
                $select->add($bgsock);
                $lookup{$bgsock} = $client;
            }
            elsif (my $qpclient = $lookup{$client}) {
                my $packet = $res->bgread($client);
                my $ip = $qpclient->peerhost;
                my $hostname = $ip;
                if ($packet) {
                    foreach my $rr ($packet->answer) {
                        if ($rr->type eq 'PTR') {
                            $hostname = $rr->rdatastr;
                        }
                    }
                }
                # $packet->print;
                $select->remove($client);
                delete($lookup{$client});
                my $qp = Qpsmtpd::SelectServer->new();
                $qp->client($qpclient);
                $qp{$qpclient} = $qp;
                $qp->log(1, "Connection number " . keys(%qp));
                $inbuffer{$qpclient} = '';
                $outbuffer{$qpclient} = '';
                $ready{$qpclient} = [];
                $qp->start_connection($ip, $hostname);
                $qp->load_plugins;
                my $rc = $qp->start_conversation;
                if ($rc != DONE) {
                    close($client);
                    next;
                }
                $select->add($qpclient);
                nonblock($qpclient);
            }
            else {
                my $data = '';
                my $rv = $client->recv($data, POSIX::BUFSIZ(), 0);
                
                unless (defined($rv) && length($data)) {
                    freeclient($client)
                          unless ($! == POSIX::EWOULDBLOCK() ||
                                  $! == POSIX::EINPROGRESS() ||
                                  $! == POSIX::EINTR());
                    next;
                }
                $inbuffer{$client} .= $data;
                
                while ($inbuffer{$client} =~ s/^([^\r\n]*)\r?\n//) {
                    #print "<$1\n";
                    push @{$ready{$client}}, $1;
                }
            }
        }
        
        #print "Processing...\n";
        foreach my $client (keys %ready) {
            my $qp = $qp{$client};
            #print "Processing $client = $qp\n";
            foreach my $req (@{$ready{$client}}) {
                if ($indata{$client}) {
                    $qp->data_line($req . CRLF);
                }
                else {
                    $qp->log(1, "dispatching $req");
                    defined $qp->dispatch(split / +/, $req)
                        or $qp->respond(502, "command unrecognized: '$req'");
                }
            }
            delete $ready{$client};
        }
        
        #print "Writing...\n";
        foreach my $client ($select->can_write(1)) {
            next unless $outbuffer{$client};
            #print "Writing to $client\n";
            
            my $rv = $client->send($outbuffer{$client}, 0);
            unless (defined($rv)) {
                warn("I was told to write, but I can't: $!\n");
                next;
            }
            if ($rv == length($outbuffer{$client}) ||
                $! == POSIX::EWOULDBLOCK())
            {
                #print "Sent all, or EWOULDBLOCK\n";
                if ($qp{$client}->{__quitting}) {
                    freeclient($client);
                    next;
                }
                substr($outbuffer{$client}, 0, $rv, '');
                delete($outbuffer{$client}) unless length($outbuffer{$client});
            }
            else {
                print "Error: $!\n";
                # Couldn't write all the data, and it wasn't because
                # it would have blocked. Shut down and move on.
                freeclient($client);
                next;
            }
        }
    }
}

sub freeclient {
    my $client = shift;
    #print "Freeing client: $client\n";
    delete $inbuffer{$client};
    delete $outbuffer{$client};
    delete $ready{$client};
    delete $qp{$client};
    $select->remove($client);
    close($client);
}

sub start_connection {
    my $self = shift;
    my $remote_ip = shift;
    my $remote_host = shift;

    $self->log(1, "Connection from $remote_host [$remote_ip]");
    my $remote_info = 'NOINFO';

    # if the local dns resolver doesn't filter it out we might get
    # ansi escape characters that could make a ps axw do "funny"
    # things. So to be safe, cut them out.  
    $remote_host =~ tr/a-zA-Z\.\-0-9//cd;

    $self->SUPER::connection->start(remote_info => $remote_info,
                                    remote_ip   => $remote_ip,
                                    remote_host => $remote_host,
                                    @_);
}

sub client {
    my $self = shift;
    @_ and $self->{_client} = shift;
    $self->{_client};
}

sub nonblock {
    my $socket = shift;
    my $flags = fcntl($socket, F_GETFL, 0)
        or die "Can't get flags for socket: $!";
    fcntl($socket, F_SETFL, $flags | O_NONBLOCK)
        or die "Can't set flags for socket: $!";
}

sub read_input {
  my $self = shift;
  die "read_input is disabled in SelectServer";
}

sub respond {
  my ($self, $code, @messages) = @_;
  my $client = $self->client || die "No client!";
  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(1, ">$line");
    $outbuffer{$client} .= "$line\r\n";
  }
  return 1;
}

sub disconnect {
  my $self = shift;
  #print "Disconnecting\n";
  $self->{__quitting} = 1;
  $self->SUPER::disconnect(@_);
}

sub data {
  my $self = shift;
  $self->respond(503, "MAIL first"), return 1 unless $self->transaction->sender;
  $self->respond(503, "RCPT first"), return 1 unless $self->transaction->recipients;
  $self->respond(354, "go ahead");
  $indata{$self->client()} = 1;
  $self->{__buffer} = '';
  $self->{__size} = 0;
  $self->{__blocked} = "";
  $self->{__in_header} = 1;
  $self->{__complete} = 0;
  $self->{__max_size} = $self->config('databytes') || 0;
}

sub data_line {
  my $self = shift;
  local $_ = shift;
  
  if ($_ eq ".\r\n") {
      $self->log(6, "max_size: $self->{__max_size} / size: $self->{__size}");
      delete $indata{$self->client()};
    
      my $smtp = $self->connection->hello eq "ehlo" ? "ESMTP" : "SMTP";
    
      if (!$self->transaction->header) {
        $self->transaction->header(Mail::Header->new(Modify => 0, MailFrom => "COERCE"));
      }
      $self->transaction->header->add("Received", "from ".$self->connection->remote_info 
               ." (HELO ".$self->connection->hello_host . ") (".$self->connection->remote_ip 
               . ") by ".$self->config('me')." (qpsmtpd/".$self->version
               .") with $smtp; ". (strftime('%a, %d %b %Y %H:%M:%S %z', localtime)),
               0);
      
      #$self->respond(550, $self->transaction->blocked),return 1 if ($self->transaction->blocked);
      $self->respond(552, "Message too big!"),return 1 if $self->{__max_size} and $self->{__size} > $self->{__max_size};
      
      my ($rc, $msg) = $self->run_hooks("data_post");
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
  elsif ($_ eq ".\n") {
    $self->respond(451, "See http://develooper.com/code/qpsmtpd/barelf.html");
    $self->{__quitting} = 1;
    return;
  }
  
  # add a transaction->blocked check back here when we have line by line plugin access...
  unless (($self->{__max_size} and $self->{__size} > $self->{__max_size})) {
      s/\r\n$/\n/;
      s/^\.\./\./;
      if ($self->{__in_header} and m/^\s*$/) {
        $self->{__in_header} = 0;
        my @header = split /\n/, $self->{__buffer};

        # ... need to check that we don't reformat any of the received lines.
        #
        # 3.8.2 Received Lines in Gatewaying
        #   When forwarding a message into or out of the Internet environment, a
        #   gateway MUST prepend a Received: line, but it MUST NOT alter in any
        #   way a Received: line that is already in the header.

        my $header = Mail::Header->new(Modify => 0, MailFrom => "COERCE");
        $header->extract(\@header);
        $self->transaction->header($header);
        $self->{__buffer} = "";
    }

    if ($self->{__in_header}) {
      $self->{__buffer} .= $_;
    }
    else {
      $self->transaction->body_write($_);
    }
    $self->{__size} += length $_;
  }
}

1;
