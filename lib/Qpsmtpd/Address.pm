package Qpsmtpd::Address;
use strict;

sub new {
    my ($class, $address) = @_;
    my $self = [ ];
    if ($address =~ /^<(.*)>$/) {
        $self->[0] = $1;
      } else {
        $self->[0] = $address;
    }
    bless ($self, $class);
    return $self;
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

sub canonify {
    my ($dummy, $path) = @_;
    my $atom = '[a-zA-Z0-9!#\$\%\&\x27\*\+\x2D\/=\?\^_`{\|}~]+';
    my $address_literal = 
'(?:\[(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|IPv6:[0-9A-Fa-f:.]+)\])';
    my $subdomain = '(?:[a-zA-Z0-9](?:[-a-zA-Z0-9]*[a-zA-Z0-9]))';
    my $domain = "(?:$address_literal|$subdomain(?:\.$subdomain)*)";
    my $qtext = '[\x01-\x08\x0B\x0C\x0E-\x1F\x21\x23-\x5B\x5D-\x7F]';
    my $text = '[\x01-\x09\x0B\x0C\x0E-\x7F]';


    # strip delimiters
    return undef unless ($path =~ /^<(.*)>$/);
    $path = $1;

    # strip source route
    $path =~ s/[EMAIL PROTECTED](?:,[EMAIL PROTECTED])*://;

    # empty path is ok
    return "" if $path eq "";

    # 
    my ($localpart, $domainpart) = ($path =~ /^(.*)\@($domain)$/);
    return undef unless (defined $localpart && defined $domainpart);
    if ($localpart =~ /^$atom(\.$atom)*/) {
        # simple case, we are done
        return $path;
      }
    if ($localpart =~ /^"(($qtext|\\$text)*)"$/) {
        $localpart = $1;
        $localpart =~ s/\\($text)/$1/g;
        return "$localpart\@$domainpart";
      }
    return undef;
}



sub parse {
    my ($class, $line) = @_;
    my $a = $class->canonify($line);
    return ($class->new($a)) if (defined $a);
    return undef;
}

sub address {
    my ($self, $val) = @_;
    my $oldval = $self->[0];
    $self->[0] = $val if (defined($val));
    return $oldval;
}

sub format {
    my ($self) = @_;
    my $qchar = '[^a-zA-Z0-9!#\$\%\&\x27\*\+\x2D\/=\?\^_`{\|}~.]';
    my $s = $self->[0];
    return '<>' unless $s;
    my ($user, $host) = $s =~ m/(.*)\@(.*)/;
    if ($user =~ s/($qchar)/\\$1/g) {
        return qq{<"$user"\@$host>};
      }
    return "<$s>";
}

sub user {
    my ($self) = @_;
    my ($user, $host) = $self->[0] =~ m/(.*)\@(.*)/;
    return $user;
}

sub host {
    my ($self) = @_;
    my ($user, $host) = $self->[0] =~ m/(.*)\@(.*)/;
    return $host;
}

1;
