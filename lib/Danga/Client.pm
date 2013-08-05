# $Id: Client.pm,v 1.8 2005/02/14 22:06:38 msergeant Exp $

package Danga::Client;
use base 'Danga::TimeoutSocket';
use fields qw(
  line
  pause_count
  read_bytes
  data_bytes
  callback
  get_chunks
  reader_object
  );
use Time::HiRes ();

use bytes;

# 30 seconds max timeout!
sub max_idle_time    { 30 }
sub max_connect_time { 1200 }

sub new {
    my Danga::Client $self = shift;
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new(@_);

    $self->reset_for_next_message;
    return $self;
}

sub reset_for_next_message {
    my Danga::Client $self = shift;
    $self->{line}          = '';
    $self->{pause_count}   = 0;
    $self->{read_bytes}    = 0;
    $self->{callback}      = undef;
    $self->{reader_object} = undef;
    $self->{data_bytes}    = '';
    $self->{get_chunks}    = 0;
    return $self;
}

sub get_bytes {
    my Danga::Client $self = shift;
    my ($bytes, $callback) = @_;
    if ($self->{callback}) {
        die "get_bytes/get_chunks currently in progress!";
    }
    $self->{read_bytes} = $bytes;
    $self->{data_bytes} = $self->{line};
    $self->{read_bytes} -= length($self->{data_bytes});
    $self->{line} = '';
    if ($self->{read_bytes} <= 0) {
        if ($self->{read_bytes} < 0) {
            $self->{line} = substr(
                                   $self->{data_bytes},
                                   $self->{read_bytes},        # negative offset
                                   0 - $self->{read_bytes},    # to end of str
                                   ""
                                  );        # truncate that substr
        }
        $callback->($self->{data_bytes});
        return;
    }
    $self->{callback} = $callback;
}

sub process_chunk {
    my Danga::Client $self = shift;
    my $callback = shift;

    my $last_crlf = rindex($self->{line}, "\r\n");

    if ($last_crlf != -1) {
        if ($last_crlf + 2 == length($self->{line})) {
            my $data = $self->{line};
            $self->{line} = '';
            $callback->($data);
        }
        else {
            my $data = substr($self->{line}, 0, $last_crlf + 2);
            $self->{line} = substr($self->{line}, $last_crlf + 2);
            $callback->($data);
        }
    }
}

sub get_chunks {
    my Danga::Client $self = shift;
    my ($bytes, $callback) = @_;
    if ($self->{callback}) {
        die "get_bytes/get_chunks currently in progress!";
    }
    $self->{read_bytes} = $bytes;
    $self->process_chunk($callback) if length($self->{line});
    $self->{callback}   = $callback;
    $self->{get_chunks} = 1;
}

sub end_get_chunks {
    my Danga::Client $self = shift;
    my $remaining = shift;
    $self->{callback}   = undef;
    $self->{get_chunks} = 0;
    if (defined($remaining)) {
        $self->process_read_buf(\$remaining);
    }
}

sub set_reader_object {
    my Danga::Client $self = shift;
    $self->{reader_object} = shift;
}

sub event_read {
    my Danga::Client $self = shift;
    if (my $obj = $self->{reader_object}) {
        $self->{reader_object} = undef;
        $obj->event_read($self);
    }
    elsif ($self->{callback}) {
        $self->{alive_time} = time;
        if ($self->{get_chunks}) {
            my $bref = $self->read($self->{read_bytes});
            return $self->close($!) unless defined $bref;
            $self->{line} .= $$bref;
            $self->process_chunk($self->{callback}) if length($self->{line});
            return;
        }
        if ($self->{read_bytes} > 0) {
            my $bref = $self->read($self->{read_bytes});
            return $self->close($!) unless defined $bref;
            $self->{read_bytes} -= length($$bref);
            $self->{data_bytes} .= $$bref;
        }
        if ($self->{read_bytes} <= 0) {

            # print "Erk, read too much!\n" if $self->{read_bytes} < 0;
            my $cb = $self->{callback};
            $self->{callback} = undef;
            $cb->($self->{data_bytes});
        }
    }
    else {
        my $bref = $self->read(8192);
        return $self->close($!) unless defined $bref;
        $self->process_read_buf($bref);
    }
}

sub process_read_buf {
    my Danga::Client $self = shift;
    my $bref = shift;
    $self->{line} .= $$bref;
    return if $self->{pause_count} || $self->{closed};

    if ($self->{line} =~ s/^(.*?\n)//) {
        my $line = $1;
        $self->{alive_time} = time;
        my $resp = $self->process_line($line);
        if ($::DEBUG > 1 and $resp) {
            print "$$:" . ($self + 0) . "S: $_\n" for split(/\n/, $resp);
        }
        $self->write($resp) if $resp;

        # $self->watch_read(0) if $self->{pause_count};
        return if $self->{pause_count} || $self->{closed};

        # read more in a timer, to give other clients a look in
        $self->AddTimer(
            0,
            sub {
                if (length($self->{line}) && !$self->paused) {
                    $self->process_read_buf(\"")
                      ;    # " for bad syntax highlighters
                }
            }
        );
    }
}

sub has_data {
    my Danga::Client $self = shift;
    return length($self->{line}) ? 1 : 0;
}

sub clear_data {
    my Danga::Client $self = shift;
    $self->{line} = '';
}

sub paused {
    my Danga::Client $self = shift;
    return 1 if $self->{pause_count};
    return 1 if $self->{closed};
    return 0;
}

sub pause_read {
    my Danga::Client $self = shift;
    $self->{pause_count}++;

    # $self->watch_read(0);
}

sub continue_read {
    my Danga::Client $self = shift;
    $self->{pause_count}--;
    if ($self->{pause_count} <= 0) {
        $self->{pause_count} = 0;
        $self->AddTimer(
            0,
            sub {
                if (length($self->{line}) && !$self->paused) {
                    $self->process_read_buf(\"")
                      ;    # " for bad syntax highlighters
                }
            }
        );
    }
}

sub process_line {
    my Danga::Client $self = shift;
    return '';
}

sub close {
    my Danga::Client $self = shift;
    print "closing @_\n" if $::DEBUG;
    $self->SUPER::close(@_);
}

sub event_err { my Danga::Client $self = shift; $self->close("Error") }

sub event_hup {
    my Danga::Client $self = shift;
    $self->close("Disconnect (HUP)");
}

1;
