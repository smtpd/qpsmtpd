package Qpsmtpd::Connection;
use strict;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);
}

sub start {
  my $self = shift;
  $self = $self->new(@_) unless ref $self;

  my %args = @_;

  for my $f (qw(remote_host remote_ip remote_info remote_port
               local_ip local_port)) {
    $self->$f($args{$f}) if $args{$f};
  }

  return $self;
}

sub remote_host {
  my $self = shift;
  @_ and $self->{_remote_host} = shift;
  $self->{_remote_host};
}

sub remote_ip {
  my $self = shift;
  @_ and $self->{_remote_ip} = shift;
  $self->{_remote_ip};
}

sub remote_port {
  my $self = shift;
  @_ and $self->{_remote_port} = shift;
  $self->{_remote_port};
}

sub local_ip {
  my $self = shift;
  @_ and $self->{_local_ip} = shift;
  $self->{_local_ip};
}

sub local_port {
  my $self = shift;
  @_ and $self->{_local_port} = shift;
  $self->{_local_port};
}


sub remote_info {
  my $self = shift;
  @_ and $self->{_remote_info} = shift;
  $self->{_remote_info};
}

sub relay_client {
  my $self = shift;
  @_ and $self->{_relay_client} = shift;
  $self->{_relay_client};
}

sub hello {
  my $self = shift;
  @_ and $self->{_hello} = shift;
  $self->{_hello};
}

sub hello_host {
  my $self = shift;
  @_ and $self->{_hello_host} = shift;
  $self->{_hello_host};
}

sub notes {
  my $self = shift;
  my $key  = shift;
  @_ and $self->{_notes}->{$key} = shift;
  $self->{_notes}->{$key};
}

1;

__END__

=head1 NAME

Qpsmtpd::Connection - A single SMTP connection

=head1 SYNOPSIS

  my $rdns = $qp->connection->remote_host;
  my $ip = $qp->connection->remote_ip;

=head1 DESCRIPTION

This class contains details about an individual SMTP connection. A
connection lasts the lifetime of a TCP connection to the SMTP server.

See also L<Qpsmtpd::Transaction> which is a class containing details
about an individual SMTP transaction. A transaction lasts from
C<MAIL FROM> to the end of the C<DATA> marker, or a C<RSET> command,
whichever comes first, whereas a connection lasts until the client
disconnects.

=head1 API

These API docs assume you already have a connection object. See the
source code if you need to construct one. You can access the connection
object via the C<Qpsmtpd> object's C<< $qp->connection >> method.

=head2 remote_host( )

The remote host connecting to the server as looked up via reverse dns.

=head2 remote_ip( )

The remote IP address of the connecting host.

=head2 remote_info( )

If your server does an ident lookup on the remote host, this is the
identity of the remote client.

=head2 hello( )

Either C<"helo"> or C<"ehlo"> depending on how the remote client
greeted your server.

NOTE: This field is empty during the helo or ehlo hooks, it is only
set after a successful return from those hooks.

=head2 hello_host( )

The host name specified in the C<HELO> or C<EHLO> command.

NOTE: This field is empty during the helo or ehlo hooks, it is only
set after a successful return from those hooks.

=head2 notes($key [, $value])

Connection-wide notes, used for passing data between plugins.

=cut
