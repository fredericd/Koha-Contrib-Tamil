package Koha::Contrib::Tamil::RecordWriter::File::Iso2709;
#ABSTRACT: ISO2709 MARC records writer
use Moose;

extends 'Koha::Contrib::Tamil::RecordWriter::File';

use Carp;
use MARC::Batch;
use MARC::Record;


sub BUILD {
    my $self = shift;

    #FIXME: Encore les joies de l'utf8 et du MARC
    #binmode( $self->fh, ':utf8' );
}


sub write {
    my ( $self, $record ) = @_;

    $self->SUPER::write();

    my $fh = $self->fh;
    print $fh $record->as_usmarc(); 
}

__PACKAGE__->meta->make_immutable;

1
