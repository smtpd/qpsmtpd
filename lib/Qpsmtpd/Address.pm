package Qpsmtpd::Address;
use strict;

=head1 NAME

Qpsmtpd::Address - Lightweight E-Mail address objects

=head1 DESCRIPTION

Based originally on cut and paste from Mail::Address and including 
every jot and tittle from RFC-2821/2822 on what is a legal e-mail 
address for use during the SMTP transaction.

=head1 USAGE

  my $rcpt = Qpsmtpd::Address->new('<email.address@example.com>');

The objects created can be used as is, since they automatically 
stringify to a standard form, and they have an overloaded comparison 
for easy testing of values.

=head1 METHODS

=head2 new()

Can be called two ways:

=over 4 

=item * Qpsmtpd::Address->new('<full_address@example.com>')

The normal mode of operation is to pass the entire contents of the 
RCPT TO: command from the SMTP transaction.  The value will be fully 
parsed via the L<canonify> method, using the full RFC 2821 rules.

=item * Qpsmtpd::Address->new("user", "host")

If the caller has already split the address from the domain/host,
this mode will not L<canonify> the input values.  This is not 
recommended in cases of user-generated input for that reason.  This 
can be used to generate Qpsmtpd::Address objects for accounts like 
"<postmaster>" or indeed for the bounce address "<>".

=back

The resulting objects can be stored in arrays or used in plugins to 
test for equality (like in badmailfrom).

=cut

use overload (
              '""'  => \&format,
              'cmp' => \&_addr_cmp,
             );

sub new {
    my ($class, $user, $host) = @_;
    my $self = {};
    if (! defined $user) {
        # Do nothing
    }
    elsif ($user =~ /^<(.*)>$/s) {    # /s: a newline must not dodge canonify
        ($user, $host) = $class->canonify($user);
        return if !defined $user;
    }
    elsif (!defined $host) {
        my $address = $user;
        ($user, $host) = $address =~ m/(.*)(?:\@(.*))/;
    }
    $self->{_user} = $user;
    $self->{_host} = $host;
    return bless $self, $class;
}

# The path grammar, RFC 5321 4.1.2 with the RFC 6531 3.3 extensions:
#
#   Path            = "<" [ A-d-l ":" ] Mailbox ">"
#   A-d-l           = At-domain *( "," At-domain )   ; source route, ignored
#   At-domain       = "@" Domain
#   Mailbox         = Local-part "@" ( Domain / address-literal )
#   Local-part      = Dot-string / Quoted-string
#   Dot-string      = Atom *( "." Atom )
#   Atom            = 1*atext                        ; 6531: / UTF8-non-ascii
#   Quoted-string   = DQUOTE *QcontentSMTP DQUOTE
#   QcontentSMTP    = qtextSMTP / quoted-pairSMTP
#   qtextSMTP       = %d32-33 / %d35-91 / %d93-126   ; 6531: / UTF8-non-ascii
#   quoted-pairSMTP = %d92 %d32-126
#   Domain          = sub-domain *( "." sub-domain )
#   sub-domain      = Let-dig [ Ldh-str ]            ; 6531: / U-label
#
# Beyond the grammar, an unquoted localpart may also hold empty atoms and
# spaces: <a..b@example>, <a.@example>, <ask @example>. Japanese mobile
# carriers issued addresses of the first two forms for years, and broken
# clients send the third. They are accepted as if quoted, and format()
# quotes them on the way out.

=head2 canonify()

Primarily an internal method, it is used only on the path portion of
an e-mail message, as defined in RFC 5321 (this is the part inside the
angle brackets and does not include the "human readable" portion of an
address).  It returns a list of (local-part, domain, reason).

=cut

# address components are defined as package variables so that they can
# be overriden (in hook_pre_connection, for example) if people have
# different needs.

# UTF8-non-ascii, per RFC 6531/6532. Addresses are handled as raw octets
# throughout qpsmtpd, so this matches the encoded form: well-formed UTF-8
# only, i.e. no overlong encodings, no surrogates and nothing beyond
# U+10FFFF.
our $utf8_expr =
    '(?:[\xC2-\xDF][\x80-\xBF]'
  . '|\xE0[\xA0-\xBF][\x80-\xBF]'
  . '|[\xE1-\xEC][\x80-\xBF]{2}'
  . '|\xED[\x80-\x9F][\x80-\xBF]'
  . '|[\xEE-\xEF][\x80-\xBF]{2}'
  . '|\xF0[\x90-\xBF][\x80-\xBF]{2}'
  . '|[\xF1-\xF3][\x80-\xBF]{3}'
  . '|\xF4[\x80-\x8F][\x80-\xBF]{2})';
our $atom_expr =
  '(?:[a-zA-Z0-9!#%&*+=?^_`{|}~\$\x27\x2D\/]|' . $utf8_expr . ')+';
our $address_literal_expr =
  '(?:\[(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|IPv6:[0-9A-Fa-f:.]+)\])';
our $subdomain_expr =
    '(?:(?:[a-zA-Z0-9]|' . $utf8_expr . ')'
  . '(?:(?:[-a-zA-Z0-9]|' . $utf8_expr . ')*'
  . '(?:[a-zA-Z0-9]|' . $utf8_expr . '))?)';
our $domain_expr;
our $qtext_expr = '[\x20\x21\x23-\x5B\x5D-\x7E]';
our $text_expr  = '[\x20-\x7E]';

# RFC 6531 3.3 allows a U-label in a domain, not an arbitrary run of UTF-8.
# These categories are DISALLOWED by IDNA2008 (RFC 5892) yet are well-formed
# UTF-8, so $utf8_expr passes them: NBSP, ideographic space, zero-width
# joiners, the BOM, soft hyphen. A localpart may hold any of them.
#
# The membership of every category here is frozen except Cf, which grows as
# Unicode assigns new format characters, so an perls rejects slightly
# fewer code points. The union only grows, so the drift is always toward
# leniency. At the 5.32 floor (Unicode 13.0) the gap is 9 code points, all of
# them Arabic or Egyptian hieroglyph format marks; the bidi controls arrived in
# Unicode 6.3 and so are covered.
our $domain_disallowed_expr = qr/[\p{Zs}\p{Zl}\p{Zp}\p{Cc}\p{Cf}\p{Co}]/;

sub canonify {
    my ($dummy, $path) = @_;

    if ($path !~ /^<(.*)>\z/s) {
        return undef, undef, 'missing delimiters'; ## no critic (undef)
    }
    $path = $1;

    return '', undef, 'empty path' if $path eq '';

    # RFC 5321 4.5.1
    return 'postmaster', undef, 'bare postmaster' if $path =~ /^postmaster\z/i;

    my $domain_re = _domain_re();
    if ($path !~ /^${\ _path_re($domain_re)}\z/) {
        return undef, undef, _why_invalid($path, $domain_re); ## no critic (undef)
    }
    my ($quoted, $unquoted, $domain) = @+{qw(quoted unquoted domain)};

    if ($domain =~ /[\x80-\xFF]/) {
        my $decoded = $domain;
        utf8::decode($decoded);
        if ($decoded =~ $domain_disallowed_expr) {
            return undef, undef, 'disallowed in domain'; ## no critic (undef)
        }
    }

    if (defined $quoted) {
        $quoted =~ s/\\($text_expr)/$1/g;
        return $quoted, $domain, 'quoted string';
    }
    if ($unquoted =~ / |\.\.|\.\z/) {
        return $unquoted, $domain, 'lenient localpart';
    }
    return $unquoted, $domain, 'local matches atom';
}

sub _domain_re {

    # NB: the label separator must survive double-quote interpolation. Written
    # as "\." it collapses to a bare dot and matches any octet.
    my $domain_re = $domain_expr || "$subdomain_expr(?:\\.$subdomain_expr)*";

    # $address_literal_expr may be empty, if a site doesn't allow them
    if (!$domain_expr && $address_literal_expr) {
        $domain_re = "(?:$address_literal_expr|$domain_re)";
    }
    return $domain_re;
}

# The unquoted form matches the lenient superset of Dot-string, which canonify
# tells apart after the match. The first octet then picks the only localpart
# alternative that can apply, and the group is atomic, so a domain that fails
# to match is never retried against a shorter localpart: parse time stays
# linear in the length of the path. The pattern string is identical from call
# to call unless a site overrides a component, so perl compiles it only once.
sub _path_re {
    my ($domain_re) = @_;
    my $qcontent = "(?:$qtext_expr|$utf8_expr|\\\\$text_expr)";
    return "(?:\@$domain_re(?:,\@$domain_re)*:)?"
      . '(?>'
      . "\"(?<quoted>$qcontent*+)\""
      . "|(?<unquoted>$atom_expr(?:$atom_expr|[. ])*+)"
      . ')'
      . "\@(?<domain>$domain_re)";
}

# Only reached once the grammar has already rejected the path, to say why.
sub _why_invalid {
    my ($path, $domain_re) = @_;

    return 'control character in path' if $path =~ /[\x00-\x1F\x7F]/;

    if ($path =~ /[\x80-\xFF]/ && $path !~ /^(?:[\x00-\x7F]|$utf8_expr)*+\z/) {
        return 'malformed UTF-8';
    }

    # '@' is a special, not atext: only a quoted localpart may carry one. The
    # domain cannot hold an '@' either, so the separator is the last one.
    $path =~ s/^\@$domain_re(?:,\@$domain_re)*://;
    my $localpart = substr $path, 0, rindex($path, '@');
    return 'unquoted @ in localpart' if $localpart =~ /\@/ && $localpart !~ /^"/;

    return 'syntax error';
}

sub parse {
# Retained for compatibility
    return shift->new(shift);
}

=head2 address()

Can be used to reset the value of an existing Q::A object, in which
case it takes a parameter with or without the angle brackets.

Returns the stringified representation of the address.  NOTE: does
not escape any of the characters that need escaping, nor does it
include the surrounding angle brackets.  For that purpose, see
L<format>.

=cut

sub address {
    my ($self, $val) = @_;
    if (defined($val)) {
        $val = "<$val>" unless $val =~ /^<.+>$/;
        my ($user, $host) = $self->canonify($val);
        $self->{_user} = $user;
        $self->{_host} = $host;
    }
    return (defined $self->{_user} ? $self->{_user}       : '')
      . (defined $self->{_host}    ? '@' . $self->{_host} : '');
}

=head2 format()

Returns the canonical stringified representation of the address.  It
does escape any characters requiring it (per RFC-2821/2822) and it
does include the surrounding angle brackets.  It is also the default
stringification operator, so the following are equivalent:

  print $rcpt->format();
  print $rcpt;

=cut

sub format {
    my ($self) = @_;

    # UTF-8 octets are legal unquoted in an internationalized mailbox
    # (RFC 6531), so they must not be escaped one byte at a time.
    my $qchar = '[^a-zA-Z0-9!#\$\%\&\x27\*\+\x2D\/=\?\^_`{\|}~.\x80-\xFF]';
    return '<>' if !defined $self->{_user};
    my $user = $self->{_user};
    my $at_host = defined $self->{_host} ? '@' . $self->{_host} : '';

    # A Dot-string has no empty atom, so a localpart canonify accepted
    # leniently (a..b, a.) or from an empty quoted string must be quoted too.
    my $not_dot_string = $user =~ /^\.|\.\.|\.\z/ || ($user eq '' && $at_host);
    if ($user =~ s/($qchar)/\\$1/g || $not_dot_string) {
        return qq(<"$user"$at_host>);
    }
    return "<" . $self->address() . ">";
}

=head2 user([$user])

Returns the "localpart" of the address, per RFC-2821, or the portion
before the '@' sign.

If called with one parameter, the localpart is set and the new value is
returned.

=cut

sub user {
    my ($self, $user) = @_;
    $self->{_user} = $user if defined $user;
    return $self->{_user};
}

=head2 host([$host])

Returns the "domain" part of the address, per RFC-2821, or the portion
after the '@' sign.

If called with one parameter, the domain is set and the new value is
returned.

=cut

sub host {
    my ($self, $host) = @_;
    $self->{_host} = $host if defined $host;
    return $self->{_host};
}

=head2 has_utf8()

Returns true if the address contains non-ASCII octets in either the
localpart or the domain, i.e. if it needs the SMTPUTF8 extension
(RFC 6531) to be transported.

Note that this reports on the I<content> of the address, which qpsmtpd
keeps as raw octets; it is unrelated to perl's C<utf8::is_utf8()>.

=cut

sub has_utf8 {
    my ($self) = @_;
    for my $part ($self->{_user}, $self->{_host}) {
        return 1 if defined $part && $part =~ /[\x80-\xFF]/;
    }
    return 0;
}

=head2 notes($key[,$value])

Get or set a note on the address. This is a piece of data that you wish
to attach to the address and read somewhere else. For example you can
use this to pass data between plugins.

=cut

sub notes {
    my ($self, $key) = (shift, shift);

    # Check for any additional arguments passed by the caller -- including undef
    return $self->{_notes}->{$key} unless @_;
    return $self->{_notes}->{$key} = shift;
}

=head2 config($value)

Looks up a configuration directive based on this recipient, using any plugins that utilize
hook_user_config

=cut

sub qp {
    my $self = shift;
    $self->{qp} = $_[0] if @_;
    return $self->{qp};
}

sub config {
    my ($self, $key) = @_;
    my $qp = $self->qp or return;
    return $qp->config($key, $self);
}

sub _addr_cmp {
    require UNIVERSAL;
    my ($left, $right, $swap) = @_;
    my $class = ref($left);

    unless (UNIVERSAL::isa($right, $class)) {
        $right = $class->new($right);
    }

    #invert the address so we can sort by domain then user
    ($left  = join('=', reverse(split(/@/, $left->format)))) =~ tr/[<>]//d;
    ($right = join('=', reverse(split(/@/, $right->format)))) =~ tr/[<>]//d;

    if ($swap) {
        ($right, $left) = ($left, $right);
    }

    return $left cmp $right;
}

=head1 COPYRIGHT

Copyright 2004-2005 Peter J. Holzer.  See the LICENSE file for more 
information.

=cut

1;
