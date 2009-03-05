package Qpsmtpd::Postfix;

=head1 NAME

Qpsmtpd::Postfix - postfix queueing support for qpsmtpd

=head2 DESCRIPTION

This package implements the protocol Postfix servers use to communicate
with each other. See src/global/rec_type.h in the postfix source for
details.

=cut

use strict;
use IO::Socket::UNIX;
use IO::Socket::INET;
use vars qw(@ISA);
@ISA = qw(IO::Socket::UNIX);

my %rec_types;

sub init {
  my ($self) = @_;

  %rec_types = (
    REC_TYPE_SIZE    => 'C',	# first record, created by cleanup
    REC_TYPE_TIME    => 'T',	# time stamp, required
    REC_TYPE_FULL    => 'F',	# full name, optional
    REC_TYPE_INSP    => 'I',	# inspector transport
    REC_TYPE_FILT    => 'L',	# loop filter transport
    REC_TYPE_FROM    => 'S',	# sender, required
    REC_TYPE_DONE    => 'D',	# delivered recipient, optional
    REC_TYPE_RCPT    => 'R',	# todo recipient, optional
    REC_TYPE_ORCP    => 'O',	# original recipient, optional
    REC_TYPE_WARN    => 'W',	# warning message time
    REC_TYPE_ATTR    => 'A',	# named attribute for extensions

    REC_TYPE_MESG    => 'M',	# start message records

    REC_TYPE_CONT    => 'L',	# long data record
    REC_TYPE_NORM    => 'N',	# normal data record

    REC_TYPE_XTRA    => 'X',	# start extracted records

    REC_TYPE_RRTO    => 'r',	# return-receipt, from headers
    REC_TYPE_ERTO    => 'e',	# errors-to, from headers
    REC_TYPE_PRIO    => 'P',	# priority
    REC_TYPE_VERP    => 'V',	# VERP delimiters

    REC_TYPE_END     => 'E',	# terminator, required

  );

}

sub print_rec {
  my ($self, $type, @list) = @_;

  die "unknown record type" unless ($rec_types{$type});
  $self->print($rec_types{$type});

  # the length is a little endian base-128 number where each 
  # byte except the last has the high bit set:
  my $s = "@list";
  my $ln = length($s);
  while ($ln >= 0x80) {
    my $lnl = $ln & 0x7F;
    $ln >>= 7;
    $self->print(chr($lnl | 0x80));
  }
  $self->print(chr($ln));

  $self->print($s);
}

sub print_rec_size {
  my ($self, $content_size, $data_offset, $rcpt_count) = @_;

  my $s = sprintf("%15ld %15ld %15ld", $content_size, $data_offset, $rcpt_count);
  $self->print_rec('REC_TYPE_SIZE', $s);
}

sub print_rec_time {
  my ($self, $time) = @_;

  $time = time() unless (defined($time));

  my $s = sprintf("%d", $time);
  $self->print_rec('REC_TYPE_TIME', $s);
}

sub open_cleanup {
  my ($class, $socket) = @_;

  my $self;
  if ($socket =~ m#^(/.+)#) {
    $socket = $1; # un-taint socket path
    $self = IO::Socket::UNIX->new(Type => SOCK_STREAM,
                                  Peer => $socket) if $socket;
    
  } elsif ($socket =~ /(.*):(\d+)/) {
    my ($host,$port) = ($1,$2); # un-taint address and port
    $self = IO::Socket::INET->new(Proto => 'tcp',
                                  PeerAddr => $host,PeerPort => $port)
      if $host and $port;
  }
  unless (ref $self) {
    warn "Couldn't open \"$socket\": $!";
    return;
  }
  # allow buffered writes
  $self->autoflush(0);
  bless ($self, $class);
  $self->init();
  return $self;
}

sub print_attr {
  my ($self, @kv) = @_;
  for (@kv) {
    $self->print("$_\0");
  }
  $self->print("\0");
}

sub get_attr {
  my ($self) = @_;
  local $/ = "\0";
  my %kv;
  for(;;) {
    my $k = $self->getline;
    chomp($k);
    last unless ($k);
    my $v = $self->getline;
    chomp($v);
    $kv{$k} = $v;
  }
  return %kv;
}


=head2 print_msg_line($line)

print one line of a message to cleanup.

This removes any linefeed characters from the end of the line
and splits the line across several records if it is longer than
1024 chars. 

=cut

sub print_msg_line {
  my ($self, $line) = @_;

  $line =~ s/\r?\n$//s;

  # split into 1k chunks. 
  while (length($line) > 1024) {
    my $s = substr($line, 0, 1024);
    $line = substr($line, 1024);
    $self->print_rec('REC_TYPE_CONT', $s);
  }
  $self->print_rec('REC_TYPE_NORM', $line);
}

=head2 inject_mail($transaction)

(class method) inject mail in $transaction into postfix queue via cleanup.
$transaction is supposed to be a Qpsmtpd::Transaction object.

=cut

sub inject_mail {
  my ($class, $transaction) = @_;

  my @sockets = @{$transaction->notes('postfix-queue-sockets')
                  // ['/var/spool/postfix/public/cleanup']};
  my $strm;
  $strm = $class->open_cleanup($_) and last for @sockets;
  die "Unable to open any cleanup sockets!" unless $strm;

  my %at = $strm->get_attr;
  my $qid = $at{queue_id};
  print STDERR "qid=$qid\n";
  $strm->print_attr('flags' => $transaction->notes('postfix-queue-flags'));
  $strm->print_rec_time();
  $strm->print_rec('REC_TYPE_FROM', $transaction->sender->address|| "");
  for (map { $_->address } $transaction->recipients) {
    $strm->print_rec('REC_TYPE_RCPT', $_);
  }
  # add an empty message length record.
  # cleanup is supposed to understand that.
  # see src/pickup/pickup.c
  $strm->print_rec('REC_TYPE_MESG', "");

  # a received header has already been added in SMTP.pm
  # so we can just copy the message:

  my $hdr = $transaction->header->as_string;
  for (split(/\r?\n/, $hdr)) {
    print STDERR "hdr: $_\n";
    $strm->print_msg_line($_);
  }
  $transaction->body_resetpos;
  while (my $line = $transaction->body_getline) {
    # print STDERR "body: $line\n";
    $strm->print_msg_line($line);
  }

  # finish it.
  $strm->print_rec('REC_TYPE_XTRA', "");
  $strm->print_rec('REC_TYPE_END', "");
  $strm->flush();
  %at = $strm->get_attr;
  my $status = $at{status};
  my $reason = $at{reason};
  $strm->close();
  return wantarray ? ($status, $qid, $reason || "") : $status;
}

1;
# vim:sw=2
