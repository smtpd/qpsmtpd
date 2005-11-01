package Qpsmtpd::Address;
use strict;

use overload (
    '""'   => \&format,
    'cmp'  => \&addr_cmp,
);

sub new {
    my ($class, $user, $host) = @_;
    my $self = {};
    if ($user =~ /^<(.*)>$/ ) {
	($user, $host) = $class->canonify($user)
    }
    elsif ( not defined $host ) {
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

sub canonify {
    my ($dummy, $path) = @_;
    my $atom = '[a-zA-Z0-9!#\$\%\&\x27\*\+\x2D\/=\?\^_`{\|}~]+';
    my $address_literal = 
'(?:\[(?:\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|IPv6:[0-9A-Fa-f:.]+)\])';
    my $subdomain = '(?:[a-zA-Z0-9](?:[-a-zA-Z0-9]*[a-zA-Z0-9])?)';
    my $domain = "(?:$address_literal|$subdomain(?:\.$subdomain)*)";
    my $qtext = '[\x01-\x08\x0B\x0C\x0E-\x1F\x21\x23-\x5B\x5D-\x7F]';
    my $text = '[\x01-\x09\x0B\x0C\x0E-\x7F]';


    # strip delimiters
    return undef unless ($path =~ /^<(.*)>$/);
    $path = $1;

    # strip source route
    $path =~ s/^\@$domain(?:,\@$domain)*://;

    # empty path is ok
    return "" if $path eq "";

    # 
    my ($localpart, $domainpart) = ($path =~ /^(.*)\@($domain)$/);
    return (undef) unless defined $localpart;

    if ($localpart =~ /^$atom(\.$atom)*/) {
        # simple case, we are done
        return ($localpart, $domainpart);
      }
    if ($localpart =~ /^"(($qtext|\\$text)*)"$/) {
        $localpart = $1;
        $localpart =~ s/\\($text)/$1/g;
        return ($localpart, $domainpart);
      }
    return (undef);
}

sub parse { # retain for compatibility only
    return shift->new(shift);
}

sub address {
    my ($self, $val) = @_;
    if ( defined($val) ) {
	$val = "<$val>" unless $val =~ /^<.+>$/;
	my ($user, $host) = $self->canonify($val);
	$self->{_user} = $user;
	$self->{_host} = $host;
    }
    return ( defined $self->{_user} ?     $self->{_user} : '' )
         . ( defined $self->{_host} ? '@'.$self->{_host} : '' );
}

sub format {
    my ($self) = @_;
    my $qchar = '[^a-zA-Z0-9!#\$\%\&\x27\*\+\x2D\/=\?\^_`{\|}~.]';
    return '<>' unless defined $self->{_user};
    if ( ( my $user = $self->{_user}) =~ s/($qchar)/\\$1/g) {
        return qq(<"$user")
	. ( defined $self->{_host} ? '@'.$self->{_host} : '' ). ">";
      }
    return "<".$self->address().">";
}

sub user {
    my ($self) = @_;
    return $self->{_user};
}

sub host {
    my ($self) = @_;
    return $self->{_host};
}

sub addr_cmp {
    require UNIVERSAL;
    my ($left, $right, $swap) = @_;
    my $class = ref($left);

    unless ( UNIVERSAL::isa($right, $class) ) {
	$right = $class->new($right);
    }

    #invert the address so we can sort by domain then user    
    $left = lc($left->host.'='.$left->user);
    $right = lc($right->host.'='.$right->user);

    if ( $swap ) {
	($right, $left) = ($left, $right);
    }

    return ($left cmp $right);
}
	
1;
