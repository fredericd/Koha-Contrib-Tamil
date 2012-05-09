package Koha::Contrib::Tamil::Authority::Task;
# ABSTRACT: Base class for managing authorities manipulations
use Moose;

extends 'AnyEvent::Processor';

use 5.010;
use utf8;
use Carp;
use YAML qw( LoadFile );

has conf_authorities => ( is => 'rw', isa => 'ArrayRef' );

has conf_file => (
    is => 'rw',
    isa => 'Str',
    trigger => sub {
        my ($self, $file) = @_;
        unless ( -e $file ) {
            croak "File doesn't exist: " . $file;
        }
        my @authorities = LoadFile( $file ) or croak "Load conf auth impossible";
        $self->conf_authorities( \@authorities );
    }
);


no Moose;
__PACKAGE__->meta->make_immutable;
1;
