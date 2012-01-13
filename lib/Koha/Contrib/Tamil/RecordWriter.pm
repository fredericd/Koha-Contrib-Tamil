package Koha::Contrib::Tamil::RecordWriter;
#ABSTRACT: RecordWriter - Base class for writing whatever records into whatever

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

__END__

=pod

=head1 DESCRIPTION

=method begin

=method end

=method write

=head1 SEE ALSO

=for :list
* L<Koha::Contrib::Tamil::RecordWriter>
* L<Koha::Contrib::Tamil::RecordReader>

=cut

