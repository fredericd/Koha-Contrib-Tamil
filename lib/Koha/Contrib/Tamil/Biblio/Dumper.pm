package Koha::Contrib::Tamil::Biblio::Dumper;
# ABSTRACT: Class dumping a Koha Catalog

use Moose;

extends 'AnyEvent::Processor';

use Modern::Perl;
use Koha::Contrib::Tamil::Koha;
use MARC::Moose::Record;
use MARC::Moose::Writer;
use MARC::Moose::Formater::Iso2709;
use C4::Biblio;
use C4::Items;
use Locale::TextDomain 'Koha-Contrib-Tamil';


has file => ( is => 'rw', isa => 'Str', default => 'dump.mrc' );

has branches => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] }
);

has where => ( is => 'rw', isa => 'Str', default => '' );

has convert => (
    is => 'rw',
    default => sub {
        return shift;
    },
);

has formater => (
    is => 'rw',
    isa => 'Str',
    default => 'marcxml',
);

has koha => (
    is       => 'rw',
    isa      => 'Koha::Contrib::Tamil::Koha',
    required => 0,
);

has verbose => ( is => 'rw', isa => 'Bool', default => 0 );

has sth => ( is => 'rw' );
has sth_marcxml => ( is => 'rw' );
has sth_item => ( is => 'rw' );

has writer => ( is => 'rw', isa => 'MARC::Moose::Writer' );



before 'run' => sub {
    my $self = shift;

    $self->koha( Koha::Contrib::Tamil::Koha->new() ) unless $self->koha;

    my $where = $self->where;
    if ( $where ) {
        $where = " WHERE $where";
    }
    else {
        if ( my $branches = $self->branches ) {
            $where = ' WHERE homebranch IN (' .
                    join(',', map {"'$_'" } @$branches) . ')'
                if @$branches;
        }
    }
    my $sql = "SELECT DISTINCT biblionumber FROM items" . $where;
    say $sql;
    my $sth = $self->koha->dbh->prepare($sql);
    $sth->execute();
    $self->sth( $sth );

    $self->sth_marcxml( $self->koha->dbh->prepare(
        "SELECT marcxml FROM biblioitems WHERE biblionumber=?" ) );

    $where = $where
             ? $where . " AND biblionumber=?"
             : " WHERE biblionumber=?";
    $self->sth_item( $self->koha->dbh->prepare(
        "SELECT * FROM items" . $where ) );

    my $fh = new IO::File '> ' . $self->file;
    binmode($fh, ':encoding(utf8)');
    $self->writer( MARC::Moose::Writer->new(
        formater => $self->formater =~ /marcxml/i
                    ? MARC::Moose::Formater::Marcxml->new()
                    : MARC::Moose::Formater::Iso2709->new(),
        fh => $fh ) );
};


before 'start_process' => sub {
    shift->writer->begin();
};


override 'process' => sub {
    my $self = shift;

    my ($biblionumber) = $self->sth->fetchrow;
    return unless $biblionumber;

    # Get the biblio record
    $self->sth_marcxml->execute($biblionumber);
    my ($marcxml) = $self->sth_marcxml->fetchrow;
    my $record = MARC::Moose::Record::new_from($marcxml, 'marcxml');

    # Construct item fields
    $self->sth_item->execute($biblionumber);
    while ( my $item = $self->sth_item->fetchrow_hashref ) {
        my $imarc = Item2Marc($item, $biblionumber);
        my $field = $imarc->field('952|995');
        my $f = MARC::Moose::Field::Std->new(
            tag => $field->tag,
            subf => [ $field->subfields ]);
        $record->append($f);
    }

    # Specific conversion
    $record = $self->convert->($record);

    $self->writer->write($record);
    return super();
};


before 'end_process' => sub {
    shift->writer->end();
};


override 'start_message' => sub {
    my $self = shift;
    say __x("Dump of Koha Catalog into file: {file}",
            file => $self->file);
};


override 'process_message' => sub {
    my $self = shift;
    say $self->count;
};


override 'end_message' => sub {
    my $self = shift;
    say __x("Number of biblio records exported: {biblios}",
              biblios => $self->count );
};


no Moose;
__PACKAGE__->meta->make_immutable;

__END__

=pod

=HEAD1 SYNOPSIS

=cut

1;

