# $Id: Client.pm,v 1.8 2005/02/14 22:06:38 msergeant Exp $

package Danga::Client;
use base 'Danga::TimeoutSocket';
use fields qw(line pause_count);
use Time::HiRes ();

# 30 seconds max timeout!
sub max_idle_time       { 30 }
sub max_connect_time    { 1200 }

sub new {
    my Danga::Client $self = shift;
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new( @_ );

    $self->reset_for_next_message;
    return $self;
}

sub reset_for_next_message {
    my Danga::Client $self = shift;
    $self->{line} = '';
    $self->{pause_count} = 0;
    return $self;
}

sub event_read {
    my Danga::Client $self = shift;
    my $bref = $self->read(8192);
    return $self->close($!) unless defined $bref;
    $self->process_read_buf($bref);
}

sub process_read_buf {
    my Danga::Client $self = shift;
    my $bref = shift;
    $self->{line} .= $$bref;
    return if $self->paused();
    
    while ($self->{line} =~ s/^(.*?\n)//) {
        my $line = $1;
        $self->{alive_time} = time;
        my $resp = $self->process_line($line);
        if ($::DEBUG > 1 and $resp) { print "$$:".($self+0)."S: $_\n" for split(/\n/, $resp) }
        $self->write($resp) if $resp;
        # $self->watch_read(0) if $self->{pause_count};
        last if $self->paused();
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
        # $self->watch_read(1);
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
sub event_hup { my Danga::Client $self = shift; $self->close("Disconnect (HUP)") }

1;
