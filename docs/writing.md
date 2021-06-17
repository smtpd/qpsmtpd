# Writing your own plugins

This is a walk through a new queue plugin, which queues the mail to a (remote)
QMQP-Server.

First step is to pull in the necessary modules

    use IO::Socket;
    use Text::Netstring qw( netstring_encode
                            netstring_decode
                            netstring_verify
                            netstring_read );

We know, we need a server to send the mails to. This will be the same
for every mail, so we can use arguments to the plugin to configure this
server (and port).

Inserting this static config is done in `register()`:

    sub register {
      my ($self, $qp, @args) = @_;

      die "No QMQP server specified in qmqp-forward config"
        unless @args;

      $self->{_qmqp_timeout} = 120;

      if ($args[0] =~ /^([\.\w_-]+)$/) {
        $self->{_qmqp_server} = $1;
      }
      else {
        die "Bad data in qmqp server: $args[0]";
      }

      $self->{_qmqp_port} = 628;
      if (@args > 1 and $args[1] =~ /^(\d+)$/) {
        $self->{_qmqp_port} = $1;
      }

      $self->log(LOGWARN, "WARNING: Ignoring additional arguments.")
        if (@args > 2);
    }

We're going to write a queue plugin, so we need to hook to the _queue_
hook.

    sub hook_queue {
      my ($self, $transaction) = @_;

      $self->log(LOGINFO, "forwarding to $self->{_qmqp_server}:"
                         ."$self->{_qmqp_port}");

The first step is to open a connection to the remote server.

    my $sock = IO::Socket::INET->new(
                  PeerAddr => $self->{_qmqp_server},
                  PeerPort => $self->{_qmqp_port},
                  Timeout  => $self->{_qmqp_timeout},
                  Proto    => 'tcp')
       or $self->log(LOGERROR, "Failed to connect to "
                       ."$self->{_qmqp_server}:"
                       ."$self->{_qmqp_port}: $!"),
         return(DECLINED);
     $sock->autoflush(1);

- The client starts with a safe 8-bit text message. It encodes the message
as the byte string `firstline\012secondline\012 ... \012lastline`. (The
last line is usually, but not necessarily, empty.) The client then encodes
this byte string as a netstring. The client also encodes the envelope
sender address as a netstring, and encodes each envelope recipient address
as a netstring.

    The client concatenates all these netstrings, encodes the concatenation
    as a netstring, and sends the result.

    (from [http://cr.yp.to/proto/qmqp.html](http://cr.yp.to/proto/qmqp.html))

The first idea is to build the package we send, in the order described
in the paragraph above:

    my $message = $transaction->header->as_string;
    $transaction->body_resetpos;
    while (my $line = $transaction->body_getline) {
      $message .= $line;
    }
    $message  = netstring_encode($message);
    $message .= netstring_encode($transaction->sender->address);
    for ($transaction->recipients) {
      push @rcpt, $_->address;
    }
    $message .= join "", netstring_encode(@rcpt);
    print $sock netstring_encode($message)
      or do {
        my $err = $!;
        $self->_disconnect($sock);
        return(DECLINED, "Failed to print to socket: $err");
      };

This would mean, we have to hold the full message in memory... Not good
for large messages, and probably even slower (for large messages).

Luckily it's easy to build a netstring without the help of the
`Text::Netstring` module if you know the size of the string (for more
info about netstrings see [http://cr.yp.to/proto/netstrings.txt](http://cr.yp.to/proto/netstrings.txt)).

We start with the sender and recipient addresses:

    my ($addrs, $headers, @rcpt);
    $addrs = netstring_encode($transaction->sender->address);
    for ($transaction->recipients) {
      push @rcpt, $_->address;
    }
    $addrs .= join "", netstring_encode(@rcpt);

Ok, we got the sender and the recipients, now let's see what size the
message is.

    $headers   = $transaction->header->as_string;
    my $msglen = length($headers) + $transaction->body_length;

We've got everything we need. Now build the netstrings for the full package
and the message.

First the beginning of the netstring of the full package

    # (+ 2: the ":" and "," of the message's netstring)
    print $sock ($msglen + length($msglen) + 2 + length($addrs))
                 .":"
                 ."$msglen:$headers" ### beginning of messages netstring
      or do {
        my $err = $!;
        $self->_disconnect($sock);
        return(DECLINED, "Failed to print to socket: $err");
      };

Go to beginning of the body

    $transaction->body_resetpos;

If the message is spooled to disk, read the message in
blocks and write them to the server

    if ($transaction->body_fh) {
      my $buff;
      my $size = read $transaction->body_fh, $buff, 4096;
      unless (defined $size) {
        my $err = $!;
        $self->_disconnect($sock);
        return(DECLINED, "Failed to read from body_fh: $err");
      }
      while ($size) {
        print $sock $buff
          or do {
            my $err = $!;
            $self->_disconnect($sock);
            return(DECLINED, "Failed to print to socket: $err");
          };

        $size = read $transaction->body_fh, $buff, 4096;
        unless (defined $size) {
          my $err = $!;
          $self->_disconnect($sock);
          return(DECLINED, "Failed to read from body_fh: $err");
        }
      }
    }

Else we have to read it line by line ...

    else {
      while (my $line = $transaction->body_getline) {
        print $sock $line
          or do {
            my $err = $!;
            $self->_disconnect($sock);
            return(DECLINED, "Failed to print to socket: $err");
          };
      }
    }

Message is at the server, now finish the package.

    print $sock ","    # end of messages netstring
               .$addrs # sender + recpients
               .","    # end of netstring of
                       #   the full package
      or do {
        my $err = $!;
        $self->_disconnect($sock);
        return(DECLINED, "Failed to print to socket: $err");
      };

We're done. Now let's see what the remote qmqpd says...

- (continued from [http://cr.yp.to/proto/qmqp.html](http://cr.yp.to/proto/qmqp.html):)

    The server's response is a nonempty string of 8-bit bytes, encoded as a
    netstring.

    The first byte of the string is either K, Z, or D. K means that the
    message has been accepted for delivery to all envelope recipients. This
    is morally equivalent to the 250 response to DATA in SMTP; it is subject
    to the reliability requirements of RFC 1123, section 5.3.3. Z means
    temporary failure; the client should try again later. D means permanent
    failure.

    Note that there is only one response for the entire message; the server
    cannot accept some recipients while rejecting others.

    my $answer = netstring_read($sock);
    $self->_disconnect($sock);

    if (defined $answer and netstring_verify($answer)) {
      $answer = netstring_decode($answer);

      $answer =~ s/^K// and return(OK, "Queued! $answer");
      $answer =~ s/^Z// and return(DENYSOFT, "Deferred: $answer");
      $answer =~ s/^D// and return(DENY, "Denied: $answer");
    }

If this is the only `queue/*` plugin, the client will get a 451 temp error:

      return(DECLINED, "Protocol error");
    }

    sub _disconnect {
      my ($self,$sock) = @_;
      if (defined $sock) {
        eval { close $sock; };
        undef $sock;
      }
    }
