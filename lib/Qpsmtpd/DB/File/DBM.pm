package Qpsmtpd::DB::File::DBM;
use strict;
use warnings;

use parent 'Qpsmtpd::DB::File';

BEGIN { @AnyDBM_File::ISA = qw(DB_File GDBM_File NDBM_File) }
use AnyDBM_File;
use Fcntl qw(:DEFAULT :flock LOCK_EX LOCK_NB);

sub file_extension {
    my ( $self, $extension ) = @_;
    return $self->{file_extension} ||= '.dbm';
}

sub get_lock {
    my ( $self ) = @_;
    my $db_file = $self->path;
    return $self->get_nfs_lock if $self->nfs_locking;
    open(my $lock, '>', "$db_file.lock") or do {
        warn "opening lockfile failed: $!\n";
        return;
    };

    flock($lock, LOCK_EX) or do {
        warn "flock of lockfile failed: $!\n";
        close $lock;
        return;
    };

    return $lock;
}

sub get_nfs_lock {
    my ( $self ) = @_;
    my $db_file = $self->path;

    require File::NFSLock;

    ### set up a lock - lasts until object looses scope
    my $nfslock = new File::NFSLock {
                             file               => "$db_file.lock",
                             lock_type          => LOCK_EX | LOCK_NB,
                             blocking_timeout   => 10,                  # 10 sec
                             stale_lock_timeout => 30 * 60,             # 30 min
                                    }
      or do {
        warn "nfs lockfile failed: $!\n";
        return;
      };

    open(my $lock, '+<', "$db_file.lock") or do {
        warn "opening nfs lockfile failed: $!\n";
        return;
    };

    return $lock;
}

sub nfs_locking {
    my $self = shift;
    return $self->{nfs_locking} if ! @_;
    return $self->{nfs_locking} = shift;
}

1;
