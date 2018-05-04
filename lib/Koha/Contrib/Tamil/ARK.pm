package Koha::Contrib::Tamil::ARK;
# ABSTRACT: ARK Management
use Moose;

use Modern::Perl;
use JSON;
use C4::Context;
use C4::Biblio;
use Try::Tiny;
use Koha::Contrib::Tamil::Koha;


has c => ( is => 'rw', isa => 'HashRef' );

has koha => (
    is => 'rw',
    isa => 'Koha::Contrib::Tamil::Koha',
    default => sub { Koha::Contrib::Tamil::Koha->new },
);

# Is the process effective. If not, output the result.
has doit => ( is => 'rw', isa => 'Bool', default => 0 );

# Verbose mode
has verbose => ( is => 'rw', isa => 'Bool', default => 0 );

has field_query => ( is => 'rw', isa => 'Str' );


sub BUILD {
    my $self = shift;

    my $c = C4::Context->preference("ARK_CONF");
    unless ($c) {
        say "ARK_CONF Koha system preference is missing";
        exit;
    }
    try {
        $c = decode_json($c);
    } catch {
        say "Error while decoding json ARK_CONF preference: $_";
        exit;
    };

    # Check 'field'
    my $field_query;
    if ( my $field = $c->{field} ) {
        if ( length($field) == 3 && $field =~ /^00[0-9]$/ ) { # controlfield
            $field_query = "//controlfield[\@tag=$field]";
        }
        elsif ( length($field) == 4 && $field =~ /^[0-9]{3}[0-9a-z]/ ) { # datafield
            my $tag = substr($field, 0, 3);
            my $letter = substr($field,3);
            $field_query = "//datafield[\@tag=\"$tag\"]/subfield[\@code=\"$letter\"]";
        }
    }
    unless ($field_query) {
        say "Invalid 'field' parameter";
        exit;
    }
    $field_query = "ExtractValue(metadata, '$field_query')";
    $self->field_query( $field_query );

    $self->c($c);
}


sub foreach_biblio {
    my ($self, $param) = @_;

    my $bibs = C4::Context->dbh->selectall_arrayref($param->{query}, {});
    $bibs = [ map { $_->[0] } @$bibs ];

    for my $biblionumber (@$bibs) {
        my $record = $self->koha->get_biblio($biblionumber);
        next unless $record;
        $param->{sub}->($biblionumber, $record);
        next unless $self->doit;
        my $fc = GetFrameworkCode($biblionumber);
        ModBiblio( $record->as('Legacy'), $biblionumber, $fc );
    }
}


sub clear {
    my $self = shift;

    my $query = "
        SELECT biblionumber
        FROM biblio_metadata
        WHERE " . $self->field_query . " <> ''
    ";
    $self->foreach_biblio({
        query => $query,
        sub => sub {
            my ($biblionumber, $record) = @_;
            say $biblionumber;
            print "BEFORE:\n", $record->as('Text') if $self->verbose;
            my ($tag, $letter);
            $tag = $self->c->{field};
            if ( length($tag) == 3 ) {
                $record->delete($tag);
            }
            else {
                $letter = substr($tag, 3);
                $tag = substr($tag, 0, 3);
                for my $field ( $record->field($tag) ) {
                    my @subf = grep { $_->[0] ne $letter; } @{$field->subf};
                    $field->subf( \@subf );
                }
                $record->fields( [ grep {
                    $_->tag eq $tag && @{$_->subf} == 0 ? 0 : 1;
                } @{ $record->fields } ] );
            }
            print "AFTER:\n", $record->as('Text') if $self->verbose;
        },
    });
}


sub update {
    my $self = shift;

    my $query = "
        SELECT biblionumber
        FROM biblio_metadata
        WHERE " . $self->field_query . " = ''
    ";
    $self->foreach_biblio({
        query => $query,
        sub => sub {
            my ($biblionumber, $record) = @_;
            say $biblionumber;
            my $ark = $self->c->{ARK};
            for my $var ( qw/ NMHA NAAN / ) {
                my $value = $self->c->{$var};
                $ark =~ s/{$var}/$value/;
            }
            $ark =~ s/{biblionumber}/$biblionumber/;
            print "BEFORE:\n", $record->as('Text') if $self->verbose;
            my ($tag, $letter);
            $tag = $self->c->{field};
            if ( length($tag) == 3 ) {
                $record->delete($tag);
                $record->append( MARC::Moose::Field::Control->new(
                    tag => $tag,
                    value => $ark ) );
            }
            else {
                $letter = substr($tag, 3);
                $tag = substr($tag, 0, 3);
                for my $field ( $record->field($tag) ) {
                    my @subf = grep { $_->[0] ne $letter; } @{$field->subf};
                    $field->subf( \@subf );
                }
                $record->fields( [ grep {
                    $_->tag eq $tag && @{$_->subf} == 0 ? 0 : 1;
                } @{ $record->fields } ] );
            }
            print "AFTER:\n", $record->as('Text') if $self->verbose;
        },
    });
}


__PACKAGE__->meta->make_immutable;
1;
