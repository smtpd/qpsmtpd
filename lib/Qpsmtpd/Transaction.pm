package Qpsmtpd::Transaction;
use strict;
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

#sub body {
#  my $self = shift;
#  @_ and $self->{_body} = shift;
#  $self->{_body};
#}

sub blocked {
  my $self = shift;
  @_ and $self->{_blocked} = shift;
  $self->{_blocked};
}

sub notes {
  my $self = shift;
  my $key  = shift;
  @_ and $self->{_notes}->{$key} = shift;
  $self->{_notes}->{$key};
}

sub add_header_line {
  my $self = shift;
  $self->{_header} .= shift;
}

sub body_write {
  my $self = shift;
  my $data = shift;
  unless ($self->{_body_file}) {
    -d "tmp" or mkdir("tmp", 0700) or die "Could not create dir tmp: $!";
    $self->{_filename} = "/home/smtpd/qpsmtpd/tmp/" . join(":", time, $$, $transaction_counter++);
    $self->{_body_file} = IO::File->new($self->{_filename}, O_RDWR|O_CREAT)    
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
    unlink $self->{_filename} or $self->log(0, "Could not unlink ", $self->{_filename}, ": $!");
  }
}


1;
