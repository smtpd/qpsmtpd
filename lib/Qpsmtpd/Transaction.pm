package Qpsmtpd::Transaction;
use Qpsmtpd;
@ISA = qw(Qpsmtpd);
use strict;
use Qpsmtpd::Utils;
use Qpsmtpd::Constants;

use IO::File qw(O_RDWR O_CREAT);

# For unique filenames. We write to a local tmp dir so we don't need
# to make them unpredictable.
my $transaction_counter = 0; 

sub new { start(@_) }

sub start {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my %args = @_;
  my $self = { _rcpt => [], started => time };
  bless ($self, $class);
}

sub add_recipient {
  my $self = shift;
  @_ and push @{$self->{_recipients}}, shift;
}

sub recipients {
  my $self = shift;
  @_ and $self->{_recipients} = [@_];
  ($self->{_recipients} ? @{$self->{_recipients}} : ());
}

sub sender {
  my $self = shift;
  @_ and $self->{_sender} = shift;
  $self->{_sender};
}

sub header {
  my $self = shift;
  @_ and $self->{_header} = shift;
  $self->{_header};
}

# blocked() will return when we actually can do something useful with it...
#sub blocked {
#  my $self = shift;
#  carp 'Use of transaction->blocked is deprecated;'
#       . 'tell ask@develooper.com if you have a reason to use it';
#  @_ and $self->{_blocked} = shift;
#  $self->{_blocked};
#}

sub notes {
  my $self = shift;
  my $key  = shift;
  @_ and $self->{_notes}->{$key} = shift;
  #warn Data::Dumper->Dump([\$self->{_notes}], [qw(notes)]);
  $self->{_notes}->{$key};
}

sub body_filename {
  my $self = shift;
  return unless $self->{_body_file};
  return $self->{_filename};
}

sub body_write {
  my $self = shift;
  my $data = shift;
  unless ($self->{_body_file}) {
     my $spool_dir = $self->config('spool_dir') ? $self->config('spool_dir') 
                                                : Qpsmtpd::Utils::tildeexp('~/tmp/');

     $spool_dir .= "/" unless ($spool_dir =~ m!/$!);
     
     $spool_dir =~ /^(.+)$/ or die "spool_dir not configured properly";
     $spool_dir = $1;

     if (-e $spool_dir) {
       my $mode = (stat($spool_dir))[2];
       die "Permissions on spool_dir $spool_dir are not 0700" if $mode & 07077;
     }

     -d $spool_dir or mkdir($spool_dir, 0700) or die "Could not create spool_dir $spool_dir: $!";
     $self->{_filename} = $spool_dir . join(":", time, $$, $transaction_counter++);
     $self->{_filename} =~ tr!A-Za-z0-9:/_-!!cd;
    $self->{_body_file} = IO::File->new($self->{_filename}, O_RDWR|O_CREAT, 0600)
      or die "Could not open file $self->{_filename} - $! "; # . $self->{_body_file}->error;
  }
  # go to the end of the file
  seek($self->{_body_file},0,2)
    unless $self->{_body_file_writing};
  $self->{_body_file_writing} = 1;
  $self->{_body_file}->print(ref $data eq "SCALAR" ? $$data : $data)
    and $self->{_body_size} += length (ref $data eq "SCALAR" ? $$data : $data); 
}

sub body_size {
  shift->{_body_size} || 0;
}

sub body_resetpos {
  my $self = shift;
  return unless $self->{_body_file};
  seek($self->{_body_file}, 0,0);
  $self->{_body_file_writing} = 0;
  1;
}

sub body_getline {
  my $self = shift;
  return unless $self->{_body_file};
  seek($self->{_body_file}, 0,0)
    if $self->{_body_file_writing};
  $self->{_body_file_writing} = 0;
  my $line = $self->{_body_file}->getline;
  return $line;
}

sub DESTROY {
  my $self = shift;
  # would we save some disk flushing if we unlinked the file before
  # closing it?

  undef $self->{_body_file} if $self->{_body_file};
  if ($self->{_filename} and -e $self->{_filename}) {
    unlink $self->{_filename} or $self->log(LOGERROR, "Could not unlink ", $self->{_filename}, ": $!");
  }
}


1;
__END__

=head1 NAME

Qpsmtpd::Transaction - single SMTP session transaction data

=head1 SYNOPSIS

  foreach my $recip ($transaction->recipients) {
    print "T", $recip->address, "\0";
  }

=head1 DESCRIPTION

Qpsmtpd::Transaction maintains a single SMTP session's data, including
the envelope details and the mail header and body.

The docs below cover using the C<$transaction> object from within plugins
rather than constructing a C<Qpsmtpd::Transaction> object, because the
latter is done for you by qpsmtpd.

=head1 API

=head2 add_recipient($recipient)

This adds a new recipient (as in RCPT TO) to the envelope of the mail.

The C<$recipient> is a C<Qpsmtpd::Address> object. See L<Qpsmtpd::Address>
for more details.

=head2 recipients( )

This returns a list of the current recipients in the envelope.

Each recipient returned is a C<Qpsmtpd::Address> object.

This method is also a setter. Pass in a list of recipients to change
the recipient list to an entirely new list. Note that the recipients
you pass in B<MUST> be C<Qpsmtpd::Address> objects.

=head2 sender( [ ADDRESS ] )

Get or set the sender (MAIL FROM) address in the envelope.

The sender is a C<Qpsmtpd::Address> object.

=head2 header( [ HEADER ] )

Get or set the header of the email.

The header is a <Mail::Header> object, which gives you access to all
the individual headers using a simple API. e.g.:

  my $headers = $transaction->header();
  my $msgid = $headers->get('Message-Id');
  my $subject = $headers->get('Subject');

=head2 notes( $key [, $value ] )

Get or set a note on the transaction. This is a piece of data that you wish
to attach to the transaction and read somewhere else. For example you can
use this to pass data between plugins.

Note though that these notes will be lost when a transaction ends, for
example on a C<RSET> or after C<DATA> completes, so you might want to
use the notes field in the C<Qpsmtpd::Connection> object instead.

=head2 body_filename ( )

Returns the temporary filename used to store the message contents; useful for
virus scanners so that an additional copy doesn't need to be made.

=head2 body_write( $data )

Write data to the end of the email.

C<$data> can be either a plain scalar, or a reference to a scalar.

=head2 body_size( )

Get the current size of the email.

=head2 body_resetpos( )

Resets the body filehandle to the start of the file (via C<seek()>).

Use this function before every time you wish to process the entire
body of the email to ensure that some other plugin has not moved the
file pointer.

=head2 body_getline( )

Returns a single line of data from the body of the email.

=head1 SEE ALSO

L<Mail::Header>, L<Qpsmtpd::Address>, L<Qpsmtpd::Connection>

=cut
