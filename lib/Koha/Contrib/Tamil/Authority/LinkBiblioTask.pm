package Koha::Contrib::Tamil::Authority::LinkBiblioTask;
# ABSTRACT: Task linking biblio records to authorities
use Moose;

extends 'Koha::Contrib::Tamil::Authority::Task';

use 5.010;
use utf8;
use Carp;
use Koha::Contrib::Tamil::Koha;
use Koha::Contrib::Tamil::RecordReader;
use C4::Context;
use C4::Biblio qw(ModBiblio);

has reader => ( is => 'rw', isa => 'Koha::Contrib::Tamil::RecordReader' );

has koha => (
    is => 'rw',
    default => sub { Koha::Contrib::Tamil::Koha->new() }
);

=method cached(0|1)

Do we cache matching authority headings found in biblio records. It improves
speed at the price of memory.

=cut
has cached => ( is => 'rw', isa => 'Bool', default => 1 );

=method doit(0|1)

Do modification in Koha biblio records?

=cut
has doit => ( is => 'rw', isa => 'Bool', default => 0 );

has _heading => ( is => 'rw', isa => 'HashRef', default => sub { {} } );


sub run {
    my $self = shift;
    $self->reader(
        Koha::Contrib::Tamil::RecordReader->new( koha => $self->koha ) )
            unless $self->reader;
    $self->koha->dbh->{AutoCommit} = 0;
    $self->SUPER::run();
}


sub process {
    my $self = shift;

    my $record = $self->reader->read();

    return 0 unless $record;

    $self->SUPER::process();

    # FIXME Reset de la connexion tous les 100 enregistrements
    unless ( $self->reader->count % 100 ) {
        $self->koha->zconn_reset();
        $self->koha->dbh->commit();
    }
    my $zconn = $self->koha->zauth();
    my $modified = 0;
    my $biblionumber = $self->reader->id;
    my $cached = $self->cached;
    my $_heading = $self->_heading;
    foreach my $authority ( @{ $self->conf_authorities } ) { # loop on all authority types
        foreach my $tag ( @{ $authority->{bibliotags} } ) { 
            # loop on all biblio tags related to the current authority
            FIELD:
            foreach my $field ( $record->field( $tag ) ) {
                # All field repetitions
                my @values;
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
                    push @values, $value
                        if $authority->{authletters} =~ /$letter/;
                }
                next FIELD unless @values;
                my $heading = join(' ', @values);
                my $id = $_heading->{$heading};
                if ( defined($id) && $id == -1 ) {
                    #print "FOUND IN CACHE AND NOT IN ZEBRA: $heading\n";
                    next;
                }
                unless ( $id ) {
                    # 6=3 Exact matching
                    my $query = '@and @attr 1=authtype ' . $authority->{authcode} .
                                ' @attr 1=Heading @attr 4=1 @attr 6=3 "' . $heading . '"';
                    #print "$query\n";
                    eval {
                        my $rs = $zconn->search_pqf( $query );
                        # FIXME: If there are more than two authorities, the biblio
                        # record is linked to the first one
                        if ( (my $size = $rs->size()) >= 1 ) {
                            print STDERR "[$biblionumber] WARNING: " . $rs->size() . " matching authorities for $heading\n"
                                if $size > 1;
                            my $auth = $rs->record(0);
                            my $m = new_from_usmarc MARC::Record( $auth->raw() );
                            $id = $m->field('001')->data();
                        }
                        else {
                            print STDERR "[$biblionumber] WARNING: authority not found -- $heading\n";
                        }
                        $rs->destroy();
                    };
                    print STDERR "ERROR: ZOOM ", $@, "\n" if $@;
                }
                else {
                    #print "FOUND IN CACHE: $heading\n";
                }
                #print "ID: $id\n";
                if ( defined $id ) {
                    $_heading->{$heading} = $id if $cached;
                    my @ns = ();
                    push @ns, '9', $id;
                    for ( $field->subfields() ) {
                        my ($letter, $value) = @$_;
                        push @ns, $letter, $value  if $letter ne '9';
                    }
                    $field->replace_with( new MARC::Field(
                        $field->tag, $field->indicator(1), $field->indicator(2),
                        @ns ) );
                    $modified = 1;
                }
                else {
                    $_heading->{$heading} = -1 if $cached;
                }
            }
        }
    }
    return 1 if !$self->doit || !$modified;

    my $framework_code = C4::Biblio::GetFrameworkCode( $self->reader->id );
    ModBiblio( $record, $self->reader->id, $framework_code );

    return 1;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
