package Qpsmtpd::DB;
use strict;
use warnings;
use Qpsmtpd::DB::File::DBM;

sub new {
    my ( $class, %arg ) = @_;
    # The only supported class just now
    return bless { %arg }, 'Qpsmtpd::DB::File::DBM';
}

# noop default method for plugins that don't require locking
sub get_lock { 1 }

sub name {
    my ( $self, $name ) = @_;
    return $self->{name} = $name if $name;
    return $self->{name};
}

1;
