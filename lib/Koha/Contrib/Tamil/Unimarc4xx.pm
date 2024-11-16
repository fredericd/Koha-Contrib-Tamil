package Koha::Contrib::Tamil::Unimarc4xx;
# ABSTRACT: Class checking mother/child biblios inconsistencies

use Moose;

extends 'AnyEvent::Processor';

use Modern::Perl;
use utf8;
use MARC::Moose::Record;
use C4::Biblio;


binmode(STDOUT, ':encoding(utf8)');

has action => ( is => 'rw', isa => 'ArrayRef' );

has doit => ( is => 'rw', isa => 'Bool', default => 0 );

has tag => ( is => 'rw', isa => 'Str', default => '461' );

has where => ( is => 'rw', isa => 'Str', default => 'issn' );

has mere_sans_issbn => ( is => 'rw', isa => 'HashRef', default => sub { {} } );


=attr verbose

Verbosity. By default 0 (false).

=cut
has verbose => ( is => 'rw', isa => 'Bool', default => 1 );

has sth => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        my ($biblionumber, $metdata);
        my $tag = $self->tag;
		my $dbh = C4::Context->dbh;
        my $query = "
            SELECT biblionumber
              FROM biblio_metadata
             WHERE ExtractValue(metadata, '//datafield[\@tag=$tag]') <> ''
        ";
        my $sth = $dbh->prepare($query);
        $sth->execute;
        $self->sth($sth);
	},
);


has fh => (
    is => 'rw',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $where = $self->where;
        my $tag = $self->tag;
        my $fh_per_type = {};
        for my $type ( ('fille-sans-mere', "mere-sans-$where", "fille") ) {
            for my $what (qw/ notice biblionumber / ) {
                my $file = "$where-$tag-$type-$what.txt";
                open my $fh, ">encoding(utf8)", $file;
                $fh_per_type->{$type}->{$what} = $fh;
            }
        }
        for my $type (('fille-9-invalide')) {
            my $file = "$where-$tag-$type.txt";
            open my $fh, ">encoding(utf8)", $file;
            $fh_per_type->{$type} = $fh;
        }
        return $fh_per_type;
    },
);


before 'run' => sub {
    my $self = shift;
    for (@{$self->action}) {
        if (/doit/i) {
            $self->doit(1)
        }
        elsif (/^4/) {
            $self->tag($_);
        }
        elsif (/issn|isbn/i) {
            $self->where(lc $_);
        }
    }
    
};


before 'start_process' => sub {
    my $self = shift;

};


override 'process' => sub {
    my $self = shift;

    my ($biblionumber) = $self->sth->fetchrow;
    return unless $biblionumber;

    my $biblio = Koha::Biblios->find($biblionumber);
    my $record = MARC::Moose::Record::new_from($biblio->metadata->record(), 'Legacy');

    my $tag = $self->tag;
    my $fille_sans_mere = 0;
    my $fille_fixed = 0;
    my $newrec = $record->clone();
    my $letter_issbn = $self->where =~ /issn/ ? 'x' : 'y';
    my $dump = sub {
        my $rec = shift;
        my @lines = $rec->field('01.|090|100|101|21.|4..|7..|8..');
        @lines = map {
            $_->tag . '    ' .
            join(' ', map { '$' . $_->[0] . ' ' . $_->[1] } @{$_->subf});
        } @lines;
        return join("\n", @lines);
    };
    for my $field ($newrec->field($self->tag)) {
        if ($field->subfield($letter_issbn)) {
            # On a un ISSN/ISBN => on ne fait rien
            next;
        }
        my $id_mere = $field->subfield('9');
        unless ($id_mere) {
            $fille_sans_mere = 1;
            next;
        }
        my $mere_biblio = Koha::Biblios->find($id_mere);
        my $mere_record;
        $mere_record = MARC::Moose::Record::new_from($mere_biblio->metadata->record(), 'Legacy') if $mere_biblio;
        unless ($mere_record) {
            # Lien invalide
            my $fh = $self->fh->{'fille-9-invalide'};
            say $fh "# $biblionumber\n", $field->tag, " ",
                    join(' ', map { '$' . $_->[0] . ' ' . $_->[1] } @{$field->subf});
            next;
        }
        my $issbn = $mere_record->field($self->where eq 'issn' ? '011' : '010');
        $issbn = $issbn->subfield('a') if $issbn;
        if ($issbn) {
            # ISSN/ISBN trouvé
            my @subf = @{$field->subf};
            push @{$field->subf}, [ $letter_issbn => $issbn ];
            $fille_fixed = 1;
        }
        else {
            # Pas trouvé : mère sans ISSN/ISBN
            $self->mere_sans_issbn->{$id_mere} = $mere_record;
        }
    }
    if ($fille_fixed) {
        my $fh_fille = $self->fh->{fille};
        my $fh = $fh_fille->{biblionumber};
        say $fh $biblionumber;
        $fh = $fh_fille->{notice};
        print $fh $dump->($record), "\n", '-' x 80, "\n", $dump->($newrec), "\n\n";
    }
    if ($fille_sans_mere) {
        my $fh_sans = $self->fh->{'fille-sans-mere'};
        my $fh = $fh_sans->{biblionumber};
        say $fh $biblionumber;
        $fh = $fh_sans->{notice};
        say $fh $dump->($record), "\n";
    }

    return super();
};


before 'end_process' => sub {
    my $self = shift;
    #shift->writer->end();
};


override 'start_message' => sub {
    my $self = shift;
    say "Vérification ", $self->tag, " / présence ", $self->where;
};


override 'process_message' => sub {
    my $self = shift;
    say $self->count;
};


override 'end_message' => sub {
    my $self = shift;
    my $where = $self->where;
    my @bibs = keys %{$self->mere_sans_issbn};
    my $fh = $self->fh->{"mere-sans-$where"}->{biblionumber};
    my $fh_notice = $self->fh->{"mere-sans-$where"}->{notice};
    for my $biblionumber ( sort { $a <=> $b } @bibs) {
        say $fh $biblionumber;
        say $fh_notice $self->mere_sans_issbn->{$biblionumber}->as('Text');
    }
};


no Moose;
__PACKAGE__->meta->make_immutable;

__END__

1;

=pod

=head1 SYNOPSIS

 my $converter = sub {
     # Delete some fields
     $record->fields(
         [ grep { $_->tag !~ /012|014|071|099/ } @{$record->fields} ] );
     return $record;
 };
 my $dumper = Koha::Contrib::Tamil::Biblio::Dumper->new(
     file     => 'biblio.mrc',
     branches => [ qw/ MAIN ANNEX / ],
     query    => "SELECT biblionumber FROM biblio WHERE datecreated LIKE '2014-11%'"
     convert  => $converter,
     formater => 'iso2709',
     verbose  => 1,
 );
 $dumper->run();

=cut

