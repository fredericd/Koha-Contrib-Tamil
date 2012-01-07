package Koha::Contrib::Tamil::Authority::LinkBiblioTask;
# ABSTRACT: Task linking biblio records to authorities
use Moose;

extends 'Koha::Contrib::Tamil::Authority::Task';

use Carp;
use Koha::Contrib::Tamil::Koha;
use Koha::Contrib::Tamil::RecordReader;
use C4::Context;
use C4::Biblio;


has reader => ( is => 'rw', isa => 'Koha::Contrib::Tamil::RecordReader' );

has koha => (
    is => 'rw',
    default => sub { Koha::Contrib::Tamil::Koha->new() }
);



sub run {
    my $self = shift;
    $self->reader(
        Koha::Contrib::Tamil::RecordReader->new( koha => $self->koha ) )
            unless $self->reader;
    $self->SUPER::run();
}


sub process {
    my $self = shift;

    my $record = $self->reader->read();

    return 0 unless $record;

    $self->SUPER::process();

    # FIXME Reset de la connexion tous les 100 enregistrements
    $self->koha->zconn_reset()  unless $self->reader->count % 100;
    my $zconn = $self->koha->zauth();
    foreach my $authority ( @{ $self->conf_authorities } ) { # loop on all authority types
        foreach my $tag ( @{ $authority->{bibliotags} } ) { 
            # loop on all biblio tags related to the current authority
            FIELD:
            foreach my $field ( $record->field( $tag ) ) {
                # All field repetitions
                my $concat = '';
                SUBFIELD:
                foreach my $subfield ( $field->subfields() ) {
                    my ($letter, $value) = @$subfield;
                    $value =~ s/^\s+//;
                    $value =~ s/\s+$//;
                    $value =~ /([\w ,.'-_]+)/;
                    $value = $1;
                    $value =~ s/^\s+//;
                    $value =~ s/\s+$//;
                    $value = ucfirst $value;
                    next SUBFIELD if !$value;
                    if ( $authority->{authletters} =~ /$letter/ ) {
                        $concat = '@and ' . $concat if $concat;
                        $concat .= ' @attr 1=Heading @attr 6=3 "' .$value .'"';   
                    }
                }
                next FIELD if !$concat;
                my $query 
                    = '@and @attr 1=authtype ' 
                      . $authority->{ authcode } . ' ' . $concat;
                #print "$query\n";
                eval {
                    my $rs = $zconn->search_pqf( $query );
                    #print "result set size: ", $rs->size(), "\n";
                    if ( $rs->size() >= 1 ) {
                        my $auth = $rs->record(0);
                        my $m = new_from_usmarc MARC::Record( $auth->raw() );
                        my $id = $m->field('001')->data();
                        #print "ID: $id\n";
                        my @ns = ();
                        push( @ns, '9', $id );
                        for ( $field->subfields() ) {
                            my ($letter, $value) = @$_;
                            push( @ns, $letter, $value ) if $letter ne '9';
                        }
                        $field->replace_with( new MARC::Field(
                            $field->tag, $field->indicator(1), $field->indicator(2),
                            @ns ) );
                    }
                    else {
                        binmode( STDOUT, ":utf8");
                        print "ERROR: authority not found -- $query\n";
                    }
                    $rs->destroy();
                };
                print "ERROR: ZOOM ", $@, "\n" if $@;
            }
        }
    }
    ModBiblio( $record, $self->reader->id );

    return 1;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
