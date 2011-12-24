package Koha::Contrib::Tamil::RecordWriter::File;
#ABSTRACT: Records writer into a file base class

use Moose;

use Carp;
use IO::File;

extends 'Koha::Contrib::Tamil::RecordWriter';

has file => (
    is => 'rw',
    isa => 'Str',
    trigger => sub {
        my ($self, $file) = @_;
        # FIXME: On ne teste pas si le fichier existe déjà.
        # S'il existe, on l'écrase
        #if ( -e $file ) {
        #    croak "File already exist: " . $file;
        #}
        $self->{file} = $file;
        my $fh        = IO::File->new( "> $file" );
        $self->{fh}   = $fh;
        binmode( $fh, $self->binmode ) if $self->binmode;
    }

);

has binmode => (
    is => 'rw',
    isa => 'Str',
);

has fh => ( is => 'rw', isa => 'IO::Handle' );


__PACKAGE__->meta->make_immutable;

1;
