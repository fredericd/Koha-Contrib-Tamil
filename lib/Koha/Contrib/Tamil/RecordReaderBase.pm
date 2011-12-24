package Koha::Contrib::Tamil::RecordReaderBase;
# ABSTRACT: Records reader base class
use Moose;


has count => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);


sub read {
    my $self = shift;
    $self->count($self->count + 1);
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

