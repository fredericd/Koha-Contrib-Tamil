package Koha::Contrib::Tamil::RecordWriter::File::Marcxml;
# ABSTRACT: XML MARC record reader
use Moose;

with 'MooseX::RW::Writer::File';


use Carp;
use MARC::Batch;
use MARC::Record;
use MARC::File::XML;


# Is XML Stream a valid marcxml
# By default no => no <collection> </collection>
has valid => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);


sub begin {
    my $self = shift;
    if ( $self->valid ) {
        my $fh = $self->fh;
        print $fh <<EOS;
<collection
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.loc.gov/MARC21/slim
http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd"
  xmlns="http://www.loc.gov/MARC21/slim">
EOS
    }
}


sub end {
    my $self = shift;
    my $fh = $self->fh;
    if ( $self->valid ) {
        print $fh '</collection>', "\n";
    }
    $fh->flush();
}



#
# Sent record is rather a MARC::Record object or an marcxml string
#
sub write {
    my ($self, $record) = @_;

    $self->count( $self->count + 1 );

    my $fh  = $self->fh;
    my $xml = ref($record) eq 'MARC::Record'
              ? $record->as_xml_record() : $record;
    if ( $self->valid ) {
        $xml =~ /<record.+?(<.*)<\/record>/s;
        $xml = "<record>\n$1</record>\n" if $1;
    }
    print $fh $xml;
}

__PACKAGE__->meta->make_immutable;

1;
