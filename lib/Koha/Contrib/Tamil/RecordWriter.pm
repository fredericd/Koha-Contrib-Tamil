package Koha::Contrib::Tamil::RecordWriter;
#ABSTRACT: RecordWriter - Class for writing whatever records into whatever

use Moose;


has count => (
    is => 'rw',
    isa => 'Int',
    default => 0
);


sub begin { }

sub end { }

sub write {
    my $self = shift;

    $self->count( $self->count + 1 );
    
    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

