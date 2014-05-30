package Qpsmtpd::PollServer;

use base ('Danga::Client', 'Qpsmtpd::SMTP');

# use fields required to be a subclass of Danga::Client. Have to include
# all fields used by Qpsmtpd.pm here too.
use fields qw(
  input_sock
  mode
  header_lines
  in_header
  data_size
  max_size
  hooks
  start_time
  cmd_timeout
  conn
  _auth
  _auth_mechanism
  _auth_state
  _auth_ticket
  _auth_user
  _commands
  _config_cache
  _connection
  _continuation
  _extras
  _test_mode
  _transaction
  );
use Qpsmtpd::Constants;
use Qpsmtpd::Address;
use ParaDNS;
use Mail::Header;
use POSIX qw(strftime);
use Socket qw(inet_aton AF_INET CRLF);
use Time::HiRes qw(time);
use strict;

sub max_idle_time    { 60 }
sub max_connect_time { 1200 }

sub input_sock {
    my $self = shift;
    @_ and $self->{input_sock} = shift;
    $self->{input_sock} || $self;
}

sub new {
    my Qpsmtpd::PollServer $self = shift;

    $self = fields::new($self) unless ref $self;
    $self->SUPER::new(@_);
    $self->{cmd_timeout} = 5;
    $self->{start_time}  = time;
    $self->{mode}        = 'connect';
    $self->load_plugins;
    $self->load_logging;

    my ($rc, @msg) = $self->run_hooks_no_respond("pre-connection");
    if ($rc == DENYSOFT || $rc == DENYSOFT_DISCONNECT) {
        @msg = ("Sorry, try again later")
          unless @msg;
        $self->respond(451, @msg);
        $self->disconnect;
    }
    elsif ($rc == DENY || $rc == DENY_DISCONNECT) {
        @msg = ("Sorry, service not available for you")
          unless @msg;
        $self->respond(550, @msg);
        $self->disconnect;
    }

    return $self;
}

sub uptime {
    my Qpsmtpd::PollServer $self = shift;

    return (time() - $self->{start_time});
}

sub reset_for_next_message {
    my Qpsmtpd::PollServer $self = shift;
    $self->SUPER::reset_for_next_message(@_);

    $self->{_commands} = {
                          proxy => 1,
                          ehlo => 1,
                          helo => 1,
                          rset => 1,
                          mail => 1,
                          rcpt => 1,
                          data => 1,
                          help => 1,
                          vrfy => 1,
                          noop => 1,
                          quit => 1,
                          auth => 0,    # disabled by default
                         };
    $self->{mode}    = 'cmd';
    $self->{_extras} = {};
}

sub respond {
    my Qpsmtpd::PollServer $self = shift;
    my ($code, @messages) = @_;
    while (my $msg = shift @messages) {
        my $line = $code . (@messages ? "-" : " ") . $msg;
        $self->write("$line\r\n");
    }
    return 1;
}

sub fault {
    my Qpsmtpd::PollServer $self = shift;
    $self->SUPER::fault(@_);
    return;
}

my %cmd_cache;

sub process_line {
    my Qpsmtpd::PollServer $self = shift;
    my $line = shift || return;
    if ($::DEBUG > 1) { print "$$:" . ($self + 0) . "C($self->{mode}): $line"; }
    if ($self->{mode} eq 'cmd') {
        $line =~ s/\r?\n$//s;
        $self->connection->notes('original_string', $line);
        my ($cmd, @params) = split(/ +/, $line, 2);
        my $meth = lc($cmd);
        if (my $lookup =
               $cmd_cache{$meth}
            || $self->{_commands}->{$meth} && $self->can($meth))
        {
            $cmd_cache{$meth} = $lookup;
            eval { $lookup->($self, @params); };
            if ($@) {
                my $error = $@;
                chomp($error);
                $self->log(LOGERROR, "Command Error: $error");
                $self->fault("command '$cmd' failed unexpectedly");
            }
        }
        else {
            # No such method - i.e. unrecognized command
            my ($rc, $msg) =
              $self->run_hooks("unrecognized_command", $meth, @params);
        }
    }
    elsif ($self->{mode} eq 'connect') {
        $self->{mode} = 'cmd';

        # I've removed an eval{} from around this. It shouldn't ever die()
        # but if it does we're a bit screwed... Ah well :-)
        $self->start_conversation;
    }
    else {
        die "Unknown mode";
    }
    return;
}

sub disconnect {
    my Qpsmtpd::PollServer $self = shift;
    $self->SUPER::disconnect(@_);
    $self->close;
}

sub close {
    my Qpsmtpd::PollServer $self = shift;
    $self->run_hooks_no_respond("post-connection");
    $self->connection->reset;
    $self->SUPER::close;
}

sub start_conversation {
    my Qpsmtpd::PollServer $self = shift;

    my $conn = $self->connection;

    # set remote_host, remote_ip and remote_port
    my ($ip, $port) = split(/:/, $self->peer_addr_string);
    return $self->close() unless $ip;
    $conn->remote_ip($ip);
    $conn->remote_port($port);
    $conn->remote_info("[$ip]");
    my ($lip, $lport) = split(/:/, $self->local_addr_string);
    $conn->local_ip($lip);
    $conn->local_port($lport);

    ParaDNS->new(
        finished => sub { $self->continue_read(); $self->run_hooks("connect") },

        # NB: Setting remote_info to the same as remote_host
        callback => sub { $conn->remote_info($conn->remote_host($_[0])) },
        host     => $ip,
                );

    return;
}

sub data {
    my Qpsmtpd::PollServer $self = shift;

    my ($rc, $msg) = $self->run_hooks("data");
    return 1;
}

sub data_respond {
    my Qpsmtpd::PollServer $self = shift;
    my ($rc, $msg) = @_;
    if ($rc == DONE) {
        return;
    }
    elsif ($rc == DENY) {
        $msg->[0] ||= "Message denied";
        $self->respond(554, @$msg);
        $self->reset_transaction();
        return;
    }
    elsif ($rc == DENYSOFT) {
        $msg->[0] ||= "Message denied temporarily";
        $self->respond(451, @$msg);
        $self->reset_transaction();
        return;
    }
    elsif ($rc == DENY_DISCONNECT) {
        $msg->[0] ||= "Message denied";
        $self->respond(554, @$msg);
        $self->disconnect;
        return;
    }
    elsif ($rc == DENYSOFT_DISCONNECT) {
        $msg->[0] ||= "Message denied temporarily";
        $self->respond(451, @$msg);
        $self->disconnect;
        return;
    }
    return $self->respond(503, "MAIL first") unless $self->transaction->sender;
    return $self->respond(503, "RCPT first")
      unless $self->transaction->recipients;

    $self->{header_lines} = '';
    $self->{data_size}    = 0;
    $self->{in_header}    = 1;
    $self->{max_size}     = ($self->config('databytes'))[0] || 0;

    $self->log(LOGDEBUG,
               "max_size: $self->{max_size} / size: $self->{data_size}");

    $self->respond(354, "go ahead");

    my $max_get = $self->{max_size} || 1048576;
    $self->get_chunks($max_get, sub { $self->got_data($_[0]) });
    return 1;
}

sub got_data {
    my Qpsmtpd::PollServer $self = shift;
    my $data = shift;

    my $done = 0;
    my $remainder;
    if ($data =~ s/^\.\r\n(.*)\z//ms) {
        $remainder = $1;
        $done      = 1;
    }

# add a transaction->blocked check back here when we have line by line plugin access...
    unless (($self->{max_size} and $self->{data_size} > $self->{max_size})) {
        $data =~ s/\r\n/\n/mg;
        $data =~ s/^\.\./\./mg;

        if ($self->{in_header}) {
            $self->{header_lines} .= $data;

            if ($self->{header_lines} =~ s/\n(\n.*)\z/\n/ms) {
                $data = $1;

                # end of headers
                $self->{in_header} = 0;

        # ... need to check that we don't reformat any of the received lines.
        #
        # 3.8.2 Received Lines in Gatewaying
        #   When forwarding a message into or out of the Internet environment, a
        #   gateway MUST prepend a Received: line, but it MUST NOT alter in any
        #   way a Received: line that is already in the header.
                my @header_lines = split(/^/m, $self->{header_lines});

                my $header =
                  Mail::Header->new(
                                    \@header_lines,
                                    Modify   => 0,
                                    MailFrom => "COERCE"
                                   );
                $self->transaction->header($header);
                $self->transaction->body_write($self->{header_lines});
                $self->{header_lines} = '';

#$header->add("X-SMTPD", "qpsmtpd/".$self->version.", http://smtpd.develooper.com/");

                # FIXME - call plugins to work on just the header here; can
                # save us buffering the mail content.

                # Save the start of just the body itself
                $self->transaction->set_body_start();
            }
        }

        $self->transaction->body_write(\$data);
        $self->{data_size} += length $data;
    }

    if ($done) {
        $self->end_of_data;
        $self->end_get_chunks($remainder);
    }

}

sub end_of_data {
    my Qpsmtpd::PollServer $self = shift;

    #$self->log(LOGDEBUG, "size is at $size\n") unless ($i % 300);

    $self->log(LOGDEBUG,
               "max_size: $self->{max_size} / size: $self->{data_size}");

    my $header = $self->transaction->header;
    if (!$header) {
        $header = Mail::Header->new(Modify => 0, MailFrom => "COERCE");
        $self->transaction->header($header);
    }

    my $smtp = $self->connection->hello eq "ehlo" ? "ESMTP" : "SMTP";
    my $esmtp = substr($smtp, 0, 1) eq "E";
    my $authheader;
    my $sslheader;

    if (defined $self->connection->notes('tls_enabled')
        and $self->connection->notes('tls_enabled'))
    {
        $smtp .= "S" if $esmtp;    # RFC3848
        $sslheader = "("
          . $self->connection->notes('tls_socket')->get_cipher()
          . " encrypted) ";
    }

    if (defined $self->{_auth} and $self->{_auth} == OK) {
        $smtp .= "A" if $esmtp;    # RFC3848
        $authheader =
"(smtp-auth username $self->{_auth_user}, mechanism $self->{_auth_mechanism})\n";
    }

    $header->add("Received",
                 $self->received_line($smtp, $authheader, $sslheader), 0);

    return $self->respond(552, "Message too big!")
      if $self->{max_size} and $self->{data_size} > $self->{max_size};

    my ($rc, $msg) = $self->run_hooks("data_post");
    return 1;
}

1;

