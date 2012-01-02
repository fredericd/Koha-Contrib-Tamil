package Koha::Contrib::Tamil::RecordReader;
#ABSTRACT: Koha biblio/authority records reader

use Moose;

extends 'Koha::Contrib::Tamil::RecordReaderBase';

use Moose::Util::TypeConstraints;

use MARC::Record;
use MARC::File::XML;
use C4::Context;
use C4::Biblio;
use C4::Items;


subtype 'Koha::RecordType'
    => as 'Str',
    => where { /biblio|authority/i },
    => message { "$_ is not a valid Koha::RecordType (biblio or authority" };

subtype 'Koha::RecordSelect'
    => as 'Str',
    => where { /all|queue|queue_update|queue_delete/ },
    => message {
        "$_ is not a valide Koha::RecordSelect " .
        "(all or queue or queue_update or queue_delete)"
    };

has koha => ( is => 'rw', isa => 'Koha::Contrib::Tamil::Koha', required => 1 );

has source => (
    is       => 'rw',
    isa      => 'Koha::RecordType',
    required => 1,
    default  => 'biblio',
);

has select => (
    is       => 'rw',
    isa      => 'Koha::RecordSelect',
    required => 1,
    default  => 'all',
);

has xml => ( is => 'rw', isa => 'Bool', default => '0' );

has sth => ( is => 'rw' );

# Last returned record biblionumber;
has id => ( is => 'rw' );

# Items extraction required
has itemsextraction => ( is => 'rw', isa => 'Bool', default => 0 );

# Items tag
has itemtag => ( is => 'rw' );

# Las returned record frameworkcode
# FIXME: a KohaRecord class should contain this information 
has frameworkcode => ( is => 'rw', isa => 'Str' );

sub BUILD {
    my $self = shift;
    my $dbh  = $self->koha->dbh;

    # Récupération du tag contenant les exemplaires
    my ( $itemtag, $itemsubfield ) = GetMarcFromKohaField("items.itemnumber",'');
    $self->itemtag($itemtag);

    # Koha version => items extraction if >= 3.4
    my $version = C4::Context::KOHAVERSION();
    $self->itemsextraction( $version ge '3.04' );

    my $operation = $self->select =~ /update/i
                    ? 'specialUpdate'
                    : 'recordDelete';
    my $sql =
        $self->source =~ /biblio/i
            ? $self->select =~ /all/i
                ? "SELECT biblionumber FROM biblio"
                : "SELECT biblio_auth_number FROM zebraqueue
                   WHERE server = 'biblioserver'
                     AND operation = '$operation' AND done = 0"
            : $self->select =~ /all/i
                ? "SELECT authid FROM auth_header"
                : "SELECT biblio_auth_number FROM zebraqueue
                   WHERE server = 'authorityserver'
                     AND operation = '$operation' AND done = 0";
    my $sth = $self->koha->dbh->prepare( $sql );
    $sth->execute();
    $self->sth( $sth );
}



sub read {
    my $self = shift;

    while ( my ($id) = $self->sth->fetchrow ) {
        if ( my $record = $self->get( $id ) ) {
            $self->SUPER::read();
            $self->id( $id );
            return $record;
        }
    }
    return 0;
}


sub get {
    my ( $self, $id ) = @_;

    $self->source =~ /biblio/i
        ? $self->xml 
          ? $self->get_biblio_xml( $id )
          : $self->koha->get_biblio_marc( $id )
        : $self->xml
          ? $self->get_auth_xml( $id )
          : $self->get_auth_marc( $id );
}


sub get_biblio_xml {
    my ( $self, $id ) = @_;
    my $sth = $self->koha->dbh->prepare(
        "SELECT marcxml FROM biblioitems WHERE biblionumber=? ");
    $sth->execute( $id );
    my ($marcxml) = $sth->fetchrow;

    # If biblio isn't found in biblioitems, it is searched in
    # deletedbilioitems. Usefull for delete Zebra requests
    unless ( $marcxml ) {
        $sth = $self->koha->dbh->prepare(
            "SELECT marcxml FROM deletedbiblioitems WHERE biblionumber=? ");
        $sth->execute( $id );
        ($marcxml) = $sth->fetchrow;
    }

    # Items extraction if Koha v3.4 and above
    # FIXME: It slows down drastically biblio records export
    if ( $self->itemsextraction ) {
        my @items = @{ $self->koha->dbh->selectall_arrayref(
            "SELECT * FROM items WHERE biblionumber=$id",
            {Slice => {} } ) };
        if (@items){
            my $record = MARC::Record->new;
            $record->encoding('UTF-8');
            my @itemsrecord;
            foreach my $item (@items) {
                my $record = Item2Marc($item, $id);
                push @itemsrecord, $record->field($self->itemtag);
            }
            $record->insert_fields_ordered(@itemsrecord);
            my $itemsxml = $record->as_xml_record();
            $marcxml =
                substr($marcxml, 0, length($marcxml)-10) .
                substr($itemsxml, index($itemsxml, "</leader>\n", 0) + 10);
        }
    }
    return $marcxml;
}


sub get_biblio_marc {
    my ( $self, $id ) = @_;

    my $sth = $self->koha->dbh->prepare(
        "SELECT marcxml FROM biblioitems WHERE biblionumber=? ");
    $sth->execute( $id );
    my ($marcxml) = $sth->fetchrow;

    unless ( $marcxml ) {
        $sth = $self->koha->dbh->prepare(
            "SELECT marcxml FROM deletedbiblioitems WHERE biblionumber=? ");
        $sth->execute( $id );
        ($marcxml) = $sth->fetchrow;
    }

    $marcxml =~ s/[^\x09\x0A\x0D\x{0020}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
    #MARC::File::XML->default_record_format( C4::Context->preference('marcflavour') );
    my $record = MARC::Record->new();
    if ($marcxml) {
        $record = eval { 
            MARC::Record::new_from_xml( $marcxml, "utf8" ) };
        if ($@) { warn " problem with: $id : $@ \n$marcxml"; }
        return $record;
    }
    return undef;
}


sub get_auth_xml {
    my ( $self, $id ) = @_;
    my $sth = $self->koha->dbh->prepare(
        "select marcxml from auth_header where authid=? "  );
    $sth->execute( $id );
    my ($xml) = $sth->fetchrow;

    # If authority isn't found we build a mimimalist record
    # Usefull for delete Zebra requests
    unless ( $xml ) {
        return "<record><controlfield tag=\"001\">$id</controlfield></record>\n";
    }

    my $new_xml = '';
    foreach ( split /\n/, $xml ) {
        next if /^<collection|^<\/collection/;
        $new_xml .= "$_\n";
    }
    return $new_xml;
}


no Moose;
__PACKAGE__->meta->make_immutable;
1;

   
=head1 SYNOPSYS

  # Read all biblio records and returns MARC::Record objects
  # Do it for a default Koha instace.
  my $reader = Koha::Contrib::Tamil::RecordReader->new( koha => Koha->new() );
  while ( $record = $reader->read() ) {
      print $record->as_formatted(), "\n";
  }

  my $reader = Koha::Contrib::RecordReader->new(
    koha => k$, source => 'biblio', select => 'all' );

  my $reader = Koha::Contrib::Tamil::RecordReader->new(
    koha => k$, source => 'biblio', select => 'queue' );

  my $k = Koha::Contrib::Tamil::Koha->new(
    '/usr/local/koha-world/etc/koha-conf.xml' );
  # Return XML records.
  my $reader = Koha::Contrib::Tamil::RecordReader->new(
    koha => k$, source => authority, select => 'queue', xml => 1 );

