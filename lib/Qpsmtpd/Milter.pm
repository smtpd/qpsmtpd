package Qpsmtpd::Milter;
use strict;
use warnings;

use IO::Select;
use IO::Socket::IP;
use IO::Socket::UNIX;

use constant VERSION => 6;

# sendmail's libmilter/mfdef.h
use constant {
    SMFIF_ADDHDRS     => 0x01,
    SMFIF_CHGBODY     => 0x02,
    SMFIF_ADDRCPT     => 0x04,
    SMFIF_DELRCPT     => 0x08,
    SMFIF_CHGHDRS     => 0x10,
    SMFIF_QUARANTINE  => 0x20,
    SMFIF_CHGFROM     => 0x40,
    SMFIF_ADDRCPT_PAR => 0x80,

    SMFIP_NOCONNECT   => 0x1,
    SMFIP_NOHELO      => 0x2,
    SMFIP_NOMAIL      => 0x4,
    SMFIP_NORCPT      => 0x8,
    SMFIP_NOBODY      => 0x10,
    SMFIP_NOHDRS      => 0x20,
    SMFIP_NOEOH       => 0x40,
    SMFIP_NR_HDR      => 0x80,
    SMFIP_NOUNKNOWN   => 0x100,
    SMFIP_NODATA      => 0x200,
    SMFIP_SKIP        => 0x400,
    SMFIP_NR_CONN     => 0x1000,
    SMFIP_NR_HELO     => 0x2000,
    SMFIP_NR_MAIL     => 0x4000,
    SMFIP_NR_RCPT     => 0x8000,
    SMFIP_NR_DATA     => 0x10000,
    SMFIP_NR_UNKN     => 0x20000,
    SMFIP_NR_EOH      => 0x40000,
    SMFIP_NR_BODY     => 0x80000,
};

use constant ACTIONS => SMFIF_ADDHDRS | SMFIF_CHGBODY | SMFIF_ADDRCPT
  | SMFIF_DELRCPT | SMFIF_CHGHDRS | SMFIF_QUARANTINE | SMFIF_CHGFROM
  | SMFIF_ADDRCPT_PAR;

# SMFIP_RCPT_REJ and SMFIP_HDR_LEADSPC are left out: we never send rejected
# recipients, and header values go out without their leading space.
use constant PROTOCOL => SMFIP_NOCONNECT | SMFIP_NOHELO | SMFIP_NOMAIL
  | SMFIP_NORCPT | SMFIP_NOBODY | SMFIP_NOHDRS | SMFIP_NOEOH | SMFIP_NR_HDR
  | SMFIP_NOUNKNOWN | SMFIP_NODATA | SMFIP_SKIP | SMFIP_NR_CONN
  | SMFIP_NR_HELO | SMFIP_NR_MAIL | SMFIP_NR_RCPT | SMFIP_NR_DATA
  | SMFIP_NR_UNKN | SMFIP_NR_EOH | SMFIP_NR_BODY;

use constant MAX_BODY_CHUNK => 65535;
use constant MAX_PACKET     => 16 * 1024 * 1024;

# command => [flag that skips it, flag that suppresses its reply]
my %steps = (
    C => [SMFIP_NOCONNECT, SMFIP_NR_CONN],
    H => [SMFIP_NOHELO,    SMFIP_NR_HELO],
    M => [SMFIP_NOMAIL,    SMFIP_NR_MAIL],
    R => [SMFIP_NORCPT,    SMFIP_NR_RCPT],
    T => [SMFIP_NODATA,    SMFIP_NR_DATA],
    L => [SMFIP_NOHDRS,    SMFIP_NR_HDR],
    N => [SMFIP_NOEOH,     SMFIP_NR_EOH],
    B => [SMFIP_NOBODY,    SMFIP_NR_BODY],
    E => [0,               0],
);

my %final = map { $_ => 1 } qw(a c d f r s t y 4);

sub new {
    my ($class, %args) = @_;
    my $self = bless {timeout => 30, %args}, $class;
    $self->{sock} ||= $self->_open;
    return $self;
}

sub _open {
    my $self = shift;
    my $sock;
    if (defined $self->{path}) {
        $sock = IO::Socket::UNIX->new(Peer => $self->{path},
                                      Timeout => $self->{timeout})
          or die "milter connect to $self->{path} failed: $!\n";
    }
    else {
        $sock = IO::Socket::IP->new(PeerHost => $self->{host},
                                    PeerPort => $self->{port},
                                    Timeout  => $self->{timeout})
          or die "milter connect to [$self->{host}]:$self->{port} failed: $@\n";
    }
    binmode $sock;
    return $sock;
}

sub version  { $_[0]{version} }
sub actions  { $_[0]{actions} }
sub protocol { $_[0]{protocol} }

sub negotiate {
    my $self = shift;
    $self->_send('O', pack('NNN', VERSION, ACTIONS, PROTOCOL));
    my ($cmd, $data) = $self->_read;
    die "milter sent '$cmd' in reply to option negotiation\n" if $cmd ne 'O';
    die "milter option negotiation reply is truncated\n" if length $data < 12;

    my ($version, $actions, $protocol) = unpack 'NNN', $data;
    die "milter speaks unsupported protocol version $version\n"
      if $version < 2 || $version > VERSION;

    $self->{version}  = $version;
    $self->{actions}  = $actions & ACTIONS;
    $self->{protocol} = $protocol & PROTOCOL;
    return $self;
}

sub wants {
    my ($self, $cmd) = @_;
    return 0 if $cmd eq 'T' && $self->{version} < 4;
    return !($self->{protocol} & $steps{$cmd}[0]);
}

sub macros {
    my ($self, $cmd, %macro) = @_;
    return if !$self->wants($cmd);
    my @defined = grep { defined $macro{$_} } sort keys %macro;
    return if !@defined;
    $self->_send('D', $cmd . join '', map { "$_\0$macro{$_}\0" } @defined);
}

sub connect {
    my ($self, $hostname, $ip, $port) = @_;
    my $family = !defined $ip ? 'U' : $ip =~ /:/ ? '6' : '4';
    my $data = "$hostname\0$family";
    $data .= pack('n', $port || 0) . "$ip\0" if $family ne 'U';
    return $self->_command('C', $data);
}

sub helo { $_[0]->_command('H', "$_[1]\0") }

sub mail { my $self = shift; $self->_command('M', join '', map {"$_\0"} @_) }
sub rcpt { my $self = shift; $self->_command('R', join '', map {"$_\0"} @_) }

sub data { $_[0]->_command('T', '') }

sub header {
    my ($self, $name, $value) = @_;
    return $self->_command('L', "$name\0$value\0");
}

sub end_of_headers { $_[0]->_command('N', '') }

sub body {
    my ($self, $chunk) = @_;
    my @replies;
    while (length $chunk) {
        @replies = $self->_command('B', substr($chunk, 0, MAX_BODY_CHUNK, ''));
        last if @replies && $replies[-1]{cmd} ne 'c';
    }
    return @replies;
}

sub end_of_body { $_[0]->_command('E', '') }

sub abort { $_[0]->_send('A', '') }

sub quit {
    my $self = shift;
    my $sock = delete $self->{sock} or return;
    eval { $self->_write($sock, pack('N', 1) . 'Q') };
    close $sock;
}

sub _command {
    my ($self, $cmd, $data) = @_;
    return if !$self->wants($cmd);
    $self->_send($cmd, $data);
    return if $self->{protocol} & $steps{$cmd}[1];

    my @replies;
    while (1) {
        my ($code, $body) = $self->_read;
        next if $code eq 'p';    # progress: the milter needs more time
        push @replies, _decode($code, $body);
        return @replies if $final{$code};
    }
}

sub _decode {
    my ($cmd, $data) = @_;
    my %r = (cmd => $cmd);

    if ($cmd eq 'y') {
        ($r{reply} = $data) =~ s/\0\z//;
    }
    elsif ($cmd eq 'h') {
        @r{qw(name value)} = split /\0/, $data, -1;
    }
    elsif ($cmd eq 'i' || $cmd eq 'm') {
        $r{index} = unpack 'N', $data;
        @r{qw(name value)} = split /\0/, substr($data, 4), -1;
    }
    elsif ($cmd eq '+' || $cmd eq '-' || $cmd eq '2' || $cmd eq 'e') {
        @r{qw(address args)} = split /\0/, $data, -1;
    }
    elsif ($cmd eq 'b') {
        $r{body} = $data;
    }
    elsif ($cmd eq 'q') {
        ($r{reason} = $data) =~ s/\0\z//;
    }
    elsif (!$final{$cmd}) {
        die "milter sent unknown reply '$cmd'\n";
    }
    defined $r{$_} or $r{$_} = '' for keys %r;
    return \%r;
}

sub _send {
    my ($self, $cmd, $data) = @_;
    my $sock = $self->{sock} or die "milter connection is closed\n";
    $self->_write($sock, pack('N', 1 + length $data) . $cmd . $data);
}

sub _write {
    my ($self, $sock, $buf) = @_;
    my $sel = IO::Select->new($sock);
    while (length $buf) {
        $sel->can_write($self->{timeout}) or die "milter write timed out\n";
        my $n = syswrite($sock, $buf);
        die "milter write failed: $!\n" if !defined $n;
        substr($buf, 0, $n, '');
    }
}

sub _read {
    my $self = shift;
    my $len = unpack 'N', $self->_read_bytes(4);
    die "milter sent an invalid packet length ($len)\n"
      if $len < 1 || $len > MAX_PACKET;
    my $packet = $self->_read_bytes($len);
    return (substr($packet, 0, 1), substr($packet, 1));
}

sub _read_bytes {
    my ($self, $want) = @_;
    my $sock = $self->{sock} or die "milter connection is closed\n";
    my $sel  = IO::Select->new($sock);
    my $buf  = '';
    while (length $buf < $want) {
        $sel->can_read($self->{timeout}) or die "milter read timed out\n";
        my $n = sysread($sock, $buf, $want - length $buf, length $buf);
        die "milter read failed: $!\n" if !defined $n;
        die "milter closed the connection\n" if !$n;
    }
    return $buf;
}

1;

__END__

=head1 NAME

Qpsmtpd::Milter - the MTA side of the sendmail milter protocol, version 6

=head1 SYNOPSIS

  my $milter = Qpsmtpd::Milter->new(host => '127.0.0.1', port => 11332);
  $milter->negotiate;
  my @replies = $milter->connect('mx.example.com', '192.0.2.1', 25);
  my $verdict = $replies[-1];    # { cmd => 'c' } for continue, etc.

=head1 DESCRIPTION

Each command method sends one milter command and returns the milter's
replies as hashrefs with a C<cmd> key holding the reply code. The last reply
is the verdict (C<c>ontinue, C<a>ccept, C<r>eject, C<t>empfail, C<d>iscard,
repl(C<y>), C<s>kip, C<f> connection failure or C<4> shutdown). Message
modifications that the milter sends at end of body precede the verdict:

  h  add header       name, value
  i  insert header    index, name, value
  m  change header    index, name, value (empty value deletes)
  +  add recipient    address
  2  add recipient    address, args
  -  delete recipient address
  e  change sender    address, args
  b  replace body     body (one chunk; there may be several)
  q  quarantine       reason

A command returns an empty list when the milter asked, during
negotiation, to skip that step or to not reply to it. Errors and timeouts
die.

The milter may negotiate any protocol version from 2 to 6.

=cut
