package Qpsmtpd::DB;
use strict;
use warnings;

our @child_classes = qw(
    Qpsmtpd::DB::Redis
    Qpsmtpd::DB::File::DBM
);

sub new {
    my ( $class, %arg ) = @_;
    my @try_classes = @child_classes;
    if ( my $manual_class = delete $arg{class} ) {
        @try_classes = ( $manual_class );
    }
    my ( $child, @errors );
    for my $child_class ( @try_classes ) {
        eval "use $child_class";
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
sub lock   { 1 }
sub unlock { 1 }

sub name {
    my ( $self, $name ) = @_;
    return $self->{name} = $name if $name;
    return $self->{name};
}

1;
