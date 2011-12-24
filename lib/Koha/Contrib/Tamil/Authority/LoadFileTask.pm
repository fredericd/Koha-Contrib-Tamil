package Koha::Contrib::Tamil::Authority::LoadFileTask;
# ABSTRACT: Task loading authorities into a Koha instance

use Moose;

extends 'Koha::Contrib::Tamil::Authority::Task', 'Koha::Contrib::Tamil::LogProcess';
 
use Locale::TextDomain 'fr.tamil.koha-tools';



has file => ( is => 'rw', isa => 'Str' );

has fh => ( is => 'rw' );

has truncate => ( is => 'rw', isa => 'Bool' );

has dbh => ( is => 'rw' );

# Le chargement est-il effectivement fait ?
has doit => (is=> 'rw', isa => 'Bool', default => 0);

use Carp;
use C4::Context;
use C4::AuthoritiesMarc;
use List::Util qw( first );




sub run {
    my $self = shift;

    my $file = $self->file;
    open my $fh, "<:utf8", $file 
        or croak "Can't open authorities file: $file"; 
    $self->fh( $fh );

    my $dbh = C4::Context->dbh;
    $self->dbh( $dbh );

    if ( $self->truncate ) {
        $self->log->info( __"Truncate table: auth_header\n" );
        $dbh->do( "truncate auth_header" );
    }

    $self->SUPER::run();
}


sub start_message {
    my $self = shift;
    my $test = $self->doit ? "" : __"** TEST **";
    my $file = $self->file;
    $self->log->notice(
        __x("Load authorities into Koha from a file {test_flag}\n" .
            "  source: {source_file}\n" .
            "  target: Koha DB\n",
            source_file => $file) );
}


sub process {
    my $self = shift;
    my $fh = $self->fh;

    if ( defined($_ = <$fh>) ) {
        $self->SUPER::process();
        chop;
        my ($authcode, $sub) = /(\w+)\t(.*)/;
        my (@subfields) = split /\t|\|/, $sub; 
        #print "auth_code => $sub\n";
        #print "tbl : ", @subfields, "\n";
        #print "size: ", $#subfields, "\n";
        my $authority = 
            first { $_->{authcode} eq $authcode } @{ $self->conf_authorities };
        return 1 if !$authority;
        #print "<$authcode>:", "0:",$subfields[0], " - 1:",$subfields[1], " => $tag\n";
      	if ( $#subfields > 0 ) {
            my $record = MARC::Record->new();
            my $leader = $record->leader();
            substr($leader, 5, 3) = 'naa';
            substr($leader, 9, 1) = 'a';    # encodage utf8
            $record->encoding( 'UTF-8' );
            $record->leader($leader);
            my $field = MARC::Field->new(
                $authority->{authtag}, '', '', @subfields);
            $record->append_fields($field);
            $self->log->info( "$authcode: " . $field->as_formatted() . "\n" );
            my ($authid) = AddAuthority($record, 0, $authcode)
                if ($self->doit);
    	}
        return 1;
    }
    return 0;
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;
