package Qpsmtpd::DB;
use strict;
use warnings;
use Qpsmtpd::DB::File::DBM;

sub new {
    my ( $class, %arg ) = @_;
    # Qpsmtpd::DB::File::DBM is the only supported class just now
    my @child_classes = qw(
        Qpsmtpd::DB::File::DBM
    );
    my $manual_class = delete $arg{class};
    return $manual_class->new(%arg) if $manual_class;
    my ( $child, @errors );
    for my $child_class ( @child_classes ) {
        eval {
            $child = $child_class->new(%arg);
        };
        last if ! $@;
        push @errors, "Couldn't load $child_class: $@";
    }
    return $child if $child;
    die join( "\n", "Couldn't load any storage modules", @errors );
}

# noop default method for plugins that don't require locking
sub lock { 1 }

sub name {
    my ( $self, $name ) = @_;
    return $self->{name} = $name if $name;
    return $self->{name};
}

1;
