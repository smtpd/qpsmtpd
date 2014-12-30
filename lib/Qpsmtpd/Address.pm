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
    elsif ($user =~ /^<(.*)>$/) {
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

# Definition of an address ("path") from RFC 2821:
#
#   Path = "<" [ A-d-l ":" ] Mailbox ">"
#
#   A-d-l = At-domain *( "," A-d-l )
#       ; Note that this form, the so-called "source route",
#       ; MUST BE accepted, SHOULD NOT be generated, and SHOULD be
#       ; ignored.
#
#   At-domain = "@" domain
#
#   Mailbox = Local-part "@" Domain
#
#   Local-part = Dot-string / Quoted-string
#       ; MAY be case-sensitive
#
#   Dot-string = Atom *("." Atom)
#
#   Atom = 1*atext
#
#   Quoted-string = DQUOTE *qcontent DQUOTE
#
#   Domain = (sub-domain 1*("." sub-domain)) / address-literal
#   sub-domain = Let-dig [Ldh-str]
#
#   address-literal = "[" IPv4-address-literal /
#                     IPv6-address-literal /
#                     General-address-literal "]"
#
#   IPv4-address-literal = Snum 3("." Snum)
#   IPv6-address-literal = "IPv6:" IPv6-addr
#   General-address-literal = Standardized-tag ":" 1*dcontent
#   Standardized-tag = Ldh-str
#         ; MUST be specified in a standards-track RFC
#         ; and registered with IANA
#
#   Snum = 1*3DIGIT  ; representing a decimal integer
#         ; value in the range 0 through 255
#   Let-dig = ALPHA / DIGIT
#   Ldh-str = *( ALPHA / DIGIT / "-" ) Let-dig
#
#   IPv6-addr = IPv6-full / IPv6-comp / IPv6v4-full / IPv6v4-comp
#   IPv6-hex  = 1*4HEXDIG
#   IPv6-full = IPv6-hex 7(":" IPv6-hex)
#   IPv6-comp = [IPv6-hex *5(":" IPv6-hex)] "::" [IPv6-hex *5(":"
#          IPv6-hex)]
#         ; The "::" represents at least 2 16-bit groups of zeros
#         ; No more than 6 groups in addition to the "::" may be
#         ; present
#   IPv6v4-full = IPv6-hex 5(":" IPv6-hex) ":" IPv4-address-literal
#   IPv6v4-comp = [IPv6-hex *3(":" IPv6-hex)] "::"
#            [IPv6-hex *3(":" IPv6-hex) ":"] IPv4-address-literal
#         ; The "::" represents at least 2 16-bit groups of zeros
#         ; No more than 4 groups in addition to the "::" and
#         ; IPv4-address-literal may be present
#
#
#
# atext and qcontent are not defined in RFC 2821.
# From RFC 2822:
#
# atext           =       ALPHA / DIGIT / ; Any character except controls,
#                         "!" / "#" /     ;  SP, and specials.
#                         "$" / "%" /     ;  Used for atoms
#                         "&" / "'" /
#                         "*" / "+" /
#                         "-" / "/" /
#                         "=" / "?" /
#                         "^" / "_" /
#                         "`" / "{" /
#                         "|" / "}" /
#                         "~"
# qtext           =       NO-WS-CTL /     ; Non white space controls
#
#                         %d33 /          ; The rest of the US-ASCII
#                         %d35-91 /       ;  characters not including "\"
#                         %d93-126        ;  or the quote character
#
# qcontent        =       qtext / quoted-pair
#
# NO-WS-CTL       =       %d1-8 /         ; US-ASCII control characters
#                         %d11 /          ;  that do not include the
#                         %d12 /          ;  carriage return, line feed,
#                         %d14-31 /       ;  and white space characters
#                         %d127
#
# quoted-pair     =       ("\" text) / obs-qp
#
# text            =       %d1-9 /         ; Characters excluding CR and LF
#                         %d11 /
#                         %d12 /
#                         %d14-127 /
#                         obs-text
#
#
# (We ignore all obs forms)

=head2 canonify()

Primarily an internal method, it is used only on the path portion of
an e-mail message, as defined in RFC-2821 (this is the part inside the
angle brackets and does not include the "human readable" portion of an
address).  It returns a list of (local-part, domain).

=cut

# address components are defined as package variables so that they can
# be overriden (in hook_pre_connection, for example) if people have
# different needs.
our $atom_expr = '[a-zA-Z0-9!#%&*+=?^_`{|}~\$\x27\x2D\/]+';
our $address_literal_expr =
  '(?:\[(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|IPv6:[0-9A-Fa-f:.]+)\])';
our $subdomain_expr = '(?:[a-zA-Z0-9](?:[-a-zA-Z0-9]*[a-zA-Z0-9])?)';
our $domain_expr;
our $qtext_expr = '[\x01-\x08\x0B\x0C\x0E-\x1F\x21\x23-\x5B\x5D-\x7F]';
our $text_expr  = '[\x01-\x09\x0B\x0C\x0E-\x7F]';

sub canonify {
    my ($dummy, $path) = @_;

    # strip delimiters
    if ($path !~ /^<(.*)>$/) {
        return undef, undef, 'missing delimiters'; ## no critic (undef)
    };
    $path = $1;

    my $domain_re = $domain_expr || "$subdomain_expr(?:\.$subdomain_expr)*";

    # $address_literal_expr may be empty, if a site doesn't allow them
    if (!$domain_expr && $address_literal_expr) {
        $domain_re = "(?:$address_literal_expr|$domain_re)";
    };

    # strip source route
    $path =~ s/^\@$domain_re(?:,\@$domain_re)*://;

    # empty path is ok
    if ($path eq '') {
        return '', undef, 'empty path';
    };

    # bare postmaster is permissible, per RFC-2821 (4.5.1)
    if ( $path =~ m/^postmaster$/i ) {
        return 'postmaster', undef, 'bare postmaster';
    }

    my ($localpart, $domainpart) = $path =~ /^(.*)\@($domain_re)$/;
    if (!defined $localpart) {
        return;
    };

    if ($localpart =~ /^$atom_expr(\.$atom_expr)*/) {
        return $localpart, $domainpart, 'local matches atom';  # simple case, we are done
    }

    if ($localpart =~ /^"(($qtext_expr|\\$text_expr)*)"$/) {
        $localpart = $1;
        $localpart =~ s/\\($text_expr)/$1/g;
        return $localpart, $domainpart;
    }
    return undef, undef, 'fall through';  ## no critic (undef)
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
    my $qchar = '[^a-zA-Z0-9!#\$\%\&\x27\*\+\x2D\/=\?\^_`{\|}~.]';
    return '<>' if !defined $self->{_user};
    if ((my $user = $self->{_user}) =~ s/($qchar)/\\$1/g) {
        return
          qq(<"$user")
          . (defined $self->{_host} ? '@' . $self->{_host} : '') . ">";
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
