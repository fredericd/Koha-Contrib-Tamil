package Koha::Contrib::Tamil::Authority::EditorsUpdater;
use Moose;

extends 'AnyEvent::Processor';

use C4::AuthoritiesMarc qw(AddAuthority);

has verbose => ( is => 'rw', isa => 'Bool' );

has doit => ( is => 'rw', isa => 'Bool' );

has koha => ( is => 'rw', isa => 'Koha::Contrib::Tamil::Koha' );

has editor_from_isbn => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

has isbns => ( is => 'rw', isa => 'ArrayRef' );


before 'run' => sub {
    my ($self, $delete) = @_;

    if ( $delete && $self->doit ) {
        print "Deleting EDITORS\n";
        $self->koha->dbh->do("delete from auth_header where authtypecode='EDITORS'");
    }
    my @isbns = sort keys %{$self->editor_from_isbn};
    $self->isbns( \@isbns );

    $self->SUPER::run();
};


override 'process' => sub {
    my $self = shift;

    return 0  if $self->count == @{$self->isbns};

    my $isbn = $self->isbns->[$self->count];
    $self->count( $self->count + 1 );
    my ($name, $collections) = @{ $self->editor_from_isbn->{$isbn} };
    my @sf = ();
    push @sf, 'a', $isbn, 'b', $name;
    foreach my $collection (sort keys %$collections) {
        push @sf, 'c', $collection;
    }
    my $authority = MARC::Record->new();
    $authority->append_fields( MARC::Field->new( 200, '', '', @sf ) );
    AddAuthority( $authority, 0, 'EDITORS' ) if $self->doit;
    #print $authority->as_formatted(), "\n" if $self->verbose;
    return 1;
};


no Moose;
__PACKAGE__->meta->make_immutable;
1;

