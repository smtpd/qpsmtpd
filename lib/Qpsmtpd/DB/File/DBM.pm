package Qpsmtpd::DB::File::DBM;
use strict;
use warnings;

use parent 'Qpsmtpd::DB';

BEGIN { @AnyDBM_File::ISA = qw(DB_File GDBM_File NDBM_File) }
use AnyDBM_File;
use Fcntl qw(:DEFAULT :flock LOCK_EX LOCK_NB);

sub new {
    my ( $class, %arg ) = @_;
    return bless {%arg}, $class;
}

sub lock {
    my ( $self ) = @_;
    if ( $self->nfs_locking ) {
        $self->nfs_file_lock or return;
    } else {
        $self->file_lock or return;
    }
    return $self->tie_dbm;
}

sub file_lock {
    my ( $self ) = @_;
    my $path = $self->path;
    open(my $lock, '>', "$path.lock") or do {
        warn "opening lockfile failed: $!\n";
        return;
    };

    flock($lock, LOCK_EX) or do {
        warn "flock of lockfile failed: $!\n";
        close $lock;
        return;
    };
    $self->{lock} = $lock;
}

sub nfs_file_lock {
    my ( $self ) = @_;
    my $path = $self->path;

    require File::NFSLock;

    ### set up a lock - lasts until object looses scope
    my $nfslock = new File::NFSLock {
                             file               => "$path.lock",
                             lock_type          => LOCK_EX | LOCK_NB,
                             blocking_timeout   => 10,                  # 10 sec
                             stale_lock_timeout => 30 * 60,             # 30 min
                                    }
      or do {
        warn "nfs lockfile failed: $!\n";
        return;
      };

    open(my $lock, '+<', "$path.lock") or do {
        warn "opening nfs lockfile failed: $!\n";
        return;
    };

    $self->{lock} = $lock;
}

sub tie_dbm {
    my ( $self ) = @_;
    my $path = $self->path;

    tie(my %db, 'AnyDBM_File', $path, O_CREAT | O_RDWR, oct('0640')) or do {
        warn "tie to database $path failed: $!\n";
        $self->unlock;
        return;
    };
    $self->{tied} = \%db;
    return 1;
}

sub nfs_locking {
    my $self = shift;
    return $self->{nfs_locking} if ! @_;
    return $self->{nfs_locking} = shift;
}

sub unlock {
    my ( $self ) = @_;
    close $self->{lock};
    untie $self->{tied};
    delete $self->{tied};
}

sub get {
    my ( $self, $key ) = @_;
    if ( ! $key ) {
        warn "No key provided, get() failed\n";
        return;
    }
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, get() failed\n";
        return;
    }
    return $tied->{$key};
}

sub mget {
    my ( $self, @keys ) = @_;
    if ( ! @keys ) {
        warn "No key provided, mget() failed\n";
        return;
    }
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, mget() failed\n";
        return;
    }
    return @$tied{ @keys }
}

sub set {
    my ( $self, $key, $val ) = @_;
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, set() failed\n";
        return;
    }
    if ( ! $key ) {
        warn "No key provided, set() failed\n";
        return;
    }
    return $tied->{$key} = $val;
}

sub get_keys {
    my ( $self ) = @_;
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, keys() failed\n";
        return;
    }
    return keys %$tied;
}

sub size {
    my ( $self ) = @_;
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, size() failed\n";
        return;
    }
    return scalar keys %$tied;
}

sub delete {
    my ( $self, @keys ) = @_;
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, delete() failed\n";
        return;
    }
    if ( ! @keys ) {
        warn "No key provided, delete() failed\n";
        return;
    }
    @keys = grep { exists $tied->{$_} } @keys;
    delete @$tied{@keys};
    return scalar @keys;
}

sub flush {
    my ( $self ) = @_;
    my $tied = $self->{tied};
    if ( ! $tied ) {
        warn "DBM db not yet set up, flush() failed\n";
        return;
    }
    delete $tied->{$_} for keys %$tied;
}

sub dir {
    my ( $self, $dir ) = @_;
    if ( $dir ) {
        $self->validate_dir($dir);
        return $self->{dir} = $dir;
    }
    return $self->{dir} if $self->{dir};
    my @err;
    for my $d ( $self->candidate_dirs ) {
        # Ignore invalid directories for static default directories
        my $is_valid;
        eval { $is_valid = $self->validate_dir($d); };
        if ($@) {
            push @err, $@;
            next;
        }
        else {
            $self->{dir} = $d; # first match wins
            last;
        }
    }
    if ( !$self->{dir} ) {
        my $err = join "\n",
          "Unable to find a useable database directory!",
          "",
          @err;
        die $err;
    }
    if (@err) {
        my $err = join "\n",
          "Encountered errors while selecting database directory:",
          "",
          @err,
          "Selected database directory: $self->{dir}. Data is now stored in:",
          "",
          $self->path,
          "",
          "It is recommended to manually specify a useable database directory",
          "and move any important data into this directory.\n";
        warn $err;
    }
    return $self->{dir};
}

sub candidate_dirs {
    my ( $self, @arg ) = @_;
    return @{ $self->{candidate_dirs} } if $self->{candidate_dirs} && ! @arg;
    $self->{candidate_dirs} = \@arg if @arg;
    push @{ $self->{candidate_dirs} },
      $self->qphome . '/var/db', $self->qphome . '/config';
    return @{ $self->{candidate_dirs} };
}

sub validate_dir {
    my ( $self, $d ) = @_;
    die "Empty DB directory supplied\n"        if ! $d;
    die "DB directory '$d' does not exist\n"   if ! -d $d;
    die "DB directory '$d' is not writeable\n" if ! -w $d;
    return 1;
}

sub qphome {
    my ( $self ) = @_;
    my ($QPHOME) = ($0 =~ m!(.*?)/([^/]+)$!);
    return $QPHOME;
}

sub path {
    my ( $self ) = @_;
    return $self->dir . '/' . $self->name . '.dbm';
}

1;
