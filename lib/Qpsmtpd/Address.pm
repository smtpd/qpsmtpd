package Qpsmtpd::Address;
use strict;

use Carp qw(croak);

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

If the caller has already split the address from the domain/host, the
localpart and domain are given unquoted. They are held to the same
rules as a parsed path: an object is returned only if the path
L<format> would write for them parses back to the same parts.

=back

Either way, new() returns undef for anything that is not a valid
address, so every object holds one. The resulting objects can be
stored in arrays or used in plugins to test for equality (like in
badmailfrom).

=cut

use overload (
              '""'  => \&format,
              'cmp' => \&_addr_cmp,
             );

sub new {
    my ($class, $user, $host) = @_;
    my $self = bless {_user => undef, _host => undef}, $class;
    return $self if !defined $user;

    # Given a domain, the first argument is a localpart, which may itself be
    # <...> once quoted. Alone, it is a path whether or not it is bracketed.
    my @parts = defined $host        ? $class->_canonical($user, $host)
              : $user =~ /^<.*>\z/s ? $class->canonify($user)
              :                        $class->canonify("<$user>");
    return if !defined $parts[0];
    @$self{qw(_user _host)} = @parts[0, 1];
    return $self;
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

# RFC 5321 4.1.3. A Snum is 1*3DIGIT "representing a decimal integer value in
# the range 0 through 255", so leading zeros are allowed. The "::" stands for
# at least two groups of zeros, so it leaves room for at most six explicit
# groups, or four beside an embedded IPv4 address.
our $address_literal_expr = do {
    my $snum = '(?:25[0-5]|2[0-4][0-9]|[01]?[0-9]?[0-9])';
    my $ipv4 = "$snum(?:\\.$snum){3}";
    my $hex  = '[0-9A-Fa-f]{1,4}';
    my $groups = sub {    # $min to $max hex groups, ':' separated
        my ($min, $max) = @_;
        return '' if !$max;
        my $re = "$hex(?::$hex){" . ($min ? $min - 1 : 0) . ',' . ($max - 1) . '}';
        return $min ? $re : "(?:$re)?";
    };
    my @ipv6 = ("$hex(?::$hex){7}", "(?:$hex:){6}$ipv4");
    for my $left (0 .. 6) {
        push @ipv6, $groups->($left, $left) . '::' . $groups->(0, 6 - $left);
    }
    for my $left (0 .. 4) {
        my $right = 4 - $left ? "(?:$hex:){0," . (4 - $left) . '}' : '';
        push @ipv6, $groups->($left, $left) . "::$right$ipv4";
    }
    '(?:\\[(?>' . $ipv4 . '\\]|(?i:IPv6):(?:' . join('|', @ipv6) . ')\\]))';
};
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
    my ($route, $quoted, $unquoted, $domain) =
      @+{qw(route quoted unquoted domain)};

    # RFC 6531 3.3 holds every domain to U-label rules, the ignored source
    # route's included. The localpart is exempt, so it stays out of this.
    my $domains = ($route // '') . $domain;
    if ($domains =~ /[\x80-\xFF]/) {
        my $decoded = $domains;
        utf8::decode($decoded);
        if ($decoded =~ $domain_disallowed_expr) {
            return undef, undef, 'disallowed in domain'; ## no critic (undef)
        }
    }

    if (defined $quoted) {
        $quoted =~ s/\\($text_expr)/$1/g;
        return $quoted, $domain, 'quoted string';
    }
    if ($unquoted =~ /^${\ _dot_string_re()}\z/) {
        return $unquoted, $domain, 'local matches atom';
    }
    return $unquoted, $domain, 'lenient localpart';
}

# The inverse of canonify(): the path for a localpart and domain. A localpart
# that is not a Dot-string is quoted, escaping only the two octets qtextSMTP
# excludes. format() and every setter go through here, so what qpsmtpd writes
# is exactly what it would accept.
sub _path {
    my ($user, $host) = @_;
    return '<>' if !defined $user || ($user eq '' && !defined $host);
    if ($user !~ /^${\ _dot_string_re()}\z/) {
        (my $escaped = $user) =~ s/(["\\])/\\$1/g;
        $user = qq{"$escaped"};
    }
    return '<' . $user . (defined $host ? "\@$host" : '') . '>';
}

# The parts canonify() gives back for the path _path() writes, or an empty
# list. Every way of setting an address goes through here, so an object never
# holds anything that does not survive that round trip.
sub _canonical {
    my ($class, $user, $host) = @_;
    return if !defined $user;
    my ($canon_user, $canon_host) = $class->canonify(_path($user, $host));
    return if !defined $canon_user;
    return ($canon_user, $canon_host);
}

sub _set {
    my ($self, $user, $host) = @_;
    my @parts = $self->_canonical($user, $host);
    if (!@parts) {
        croak sprintf 'not a valid address: localpart %s, domain %s',
          map { defined $_ ? "'$_'" : 'undef' } $user, $host;
    }
    @$self{qw(_user _host)} = @parts;
    return;
}

sub _dot_string_re {
    return "$atom_expr(?:\\.$atom_expr)*";
}

sub _domain_re {

    # NB: the label separator must survive double-quote interpolation. Written
    # as "\." it collapses to a bare dot and matches any octet.
    return $domain_expr || "$subdomain_expr(?:\\.$subdomain_expr)*";
}

# The unquoted form matches the lenient superset of Dot-string, which canonify
# tells apart after the match. The first octet then picks the only localpart
# alternative that can apply, and the group is atomic, so a domain that fails
# to match is never retried against a shorter localpart: parse time stays
# linear in the length of the path. The pattern string is identical from call
# to call unless a site overrides a component, so perl compiles it only once.
sub _path_re {
    my ($domain_re) = @_;

    # An address literal may only follow the mailbox '@', never a source
    # route's. $address_literal_expr may be empty, if a site doesn't allow them.
    my $destination_re = $domain_re;
    if (!$domain_expr && $address_literal_expr) {
        $destination_re = "(?:$address_literal_expr|$domain_re)";
    }
    my $qcontent = "(?:$qtext_expr|$utf8_expr|\\\\$text_expr)";
    return "(?<route>\@$domain_re(?:,\@$domain_re)*:)?"
      . '(?>'
      . "\"(?<quoted>$qcontent*+)\""
      . "|(?<unquoted>$atom_expr(?:$atom_expr|[. ])*+)"
      . ')'
      . "\@(?<domain>$destination_re)";
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
    return 'syntax error' if $path =~ /^\@/;    # a malformed source route
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
case it takes a parameter with or without the angle brackets. It
croaks if that is not a valid path, leaving the object unchanged.

Returns the stringified representation of the address.  NOTE: does
not escape any of the characters that need escaping, nor does it
include the surrounding angle brackets.  For that purpose, see
L<format>.

=cut

sub address {
    my ($self, $val) = @_;
    if (defined $val) {
        $val = "<$val>" if $val !~ /^<.*>\z/s;
        my ($user, $host) = $self->canonify($val);
        croak "not a valid address: $val" if !defined $user;
        @$self{qw(_user _host)} = ($user, $host);
    }
    return (defined $self->{_user} ? $self->{_user}       : '')
      . (defined $self->{_host}    ? '@' . $self->{_host} : '');
}

=head2 format()

Returns the canonical stringified representation of the address: the
path, angle brackets included, with the localpart quoted only when it
is not a Dot-string (RFC 5321 4.1.2). canonify() parses it back to
the same localpart and domain.  It is also the default
stringification operator, so the following are equivalent:

  print $rcpt->format();
  print $rcpt;

=cut

sub format {
    my ($self) = @_;
    return _path($self->{_user}, $self->{_host});
}

=head2 user([$user])

Returns the "localpart" of the address, per RFC-2821, or the portion
before the '@' sign.

If called with one parameter, the localpart is set and the new value is
returned. It croaks, leaving the address unchanged, if the result would
not be a valid address.

=cut

sub user {
    my ($self, $user) = @_;
    $self->_set($user, $self->{_host}) if defined $user;
    return $self->{_user};
}

=head2 host([$host])

Returns the "domain" part of the address, per RFC-2821, or the portion
after the '@' sign.

If called with one parameter, the domain is set and the new value is
returned. It croaks, leaving the address unchanged, if the result would
not be a valid address.

=cut

sub host {
    my ($self, $host) = @_;
    if (defined $host) {

        # The null path has no localpart: '' only stands in for it, and given
        # a domain it would become the mailbox <""@domain>.
        croak 'not a valid address: the null sender has no domain'
          if !defined $self->{_host} && ($self->{_user} // '') eq '';
        $self->_set($self->{_user}, $host);
    }
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
    my ($left, $right, $swap) = @_;
    my $class = ref($left);

    if (!UNIVERSAL::isa($right, $class)) {

        # new() returns undef for anything that is not a path. Comparing
        # against one must not die; it sorts before every address and equals
        # none of them.
        $right = $class->new($right) // return $swap ? -1 : 1;
    }
    ($left, $right) = ($right, $left) if $swap;

    # By domain, then localpart. Domains follow DNS and are not case
    # sensitive, a localpart MUST be treated as case sensitive (RFC 5321 2.4).
    # tr folds ASCII only, leaving UTF-8 octets alone.
    my ($left_host, $right_host) =
      map { ($_->{_host} // '') =~ tr/A-Z/a-z/r } $left, $right;
    return $left_host cmp $right_host
      || ($left->{_user} // '') cmp ($right->{_user} // '');
}

=head1 COPYRIGHT

Copyright 2004-2005 Peter J. Holzer.  See the LICENSE file for more 
information.

=cut

1;
