package Qpsmtpd::DB::File;
use strict;
use warnings;
use lib 'lib';
use parent 'Qpsmtpd::DB';

sub dir {
    my ( $self, @candidate_dirs ) = @_;
    return $self->{dir} if $self->{dir} and ! @candidate_dirs;
    push @candidate_dirs, ( $self->qphome . '/var/db', $self->qphome . '/config' );
    for my $d ( @candidate_dirs ) {
        next if ! $self->validate_dir($d);
        return $self->{dir} = $d; # first match wins
    }
}

sub validate_dir {
    my ( $self, $d ) = @_;
    return 0 if ! $d;
    return 0 if ! -d $d;
    return 1;
}

sub qphome {
    my ( $self ) = @_;
    my ($QPHOME) = ($0 =~ m!(.*?)/([^/]+)$!);
    return $QPHOME;
}

sub path {
    my ( $self ) = @_;
    return $self->dir . '/' . $self->name . $self->file_extension;
}

1;
