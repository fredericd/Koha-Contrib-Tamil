package Koha::Contrib::Tamil::IndexerDaemon;
# ABSTRACT: Class implementing a Koha records indexer daemon

use Moose;

use 5.010;
use utf8;
use warnings;
use strict;
use AnyEvent;
use Koha::Contrib::Tamil::Koha;
use Koha::Contrib::Tamil::Indexer;
use Locale::TextDomain 'fr.tamil.koha-tools';

with 'MooseX::Getopt';


has id => ( is => 'rw', isa => 'Str', );

has name => ( is => 'rw', isa => 'Str' );

has conf => ( is => 'rw', isa => 'Str' );

has directory => (
    is      => 'rw',
    isa     => 'Str',
);

has timeout => (
    is      => 'rw',
    isa     => 'Int',
    default => 60,
);

has verbose => ( is => 'rw', isa => 'Bool', default => 0 );

has koha => (
    is => 'rw',
    isa => 'Koha::Contrib::Tamil::Koha',
);


sub BUILD {
    my $self = shift;

    print __"Starting Koha Indexer Daemon", "\n";

    $self->koha( $self->conf
        ? Koha::Contrib::Tamil::Koha->new(conf_file => $self->conf)
        : Koha::Contrib::Tamil::Koha->new() );
    $self->name( $self->koha->conf->{config}->{database} );

    my $idle = AnyEvent->timer(
        after => $self->timeout,
        interval => $self->timeout,
        cb => sub {
            $self->index_zebraqueue();
        }
    );
    AnyEvent->condvar->recv;
}


sub index_zebraqueue {
    my $self = shift;

    my $sql = " SELECT COUNT(*), server 
                FROM zebraqueue 
                WHERE done = 0
                GROUP BY server ";
    my $sth = $self->koha->dbh->prepare( $sql );
    $sth->execute();
    my ($biblio_count, $auth_count) = (0, 0);
    while ( my ($count, $server) = $sth->fetchrow ) {
        $biblio_count = $count  if $server =~ /biblio/;
        $auth_count   = $count  if $server =~ /authority/;
    }

    print __x (
        "[{name}] Index biblio ({biblio_count}) authority ({auth_count})",
        name => $self->name,
        biblio_count => $biblio_count,
        auth_count => $auth_count ), "\n";

    if ( $biblio_count > 0 ) {
        my $indexer = Koha::Contrib::Tamil::Indexer->new(
            koha        => $self->koha,
            source      => 'biblio',
            select      => 'queue',
            blocking    => 1,
            verbose     => $self->verbose,
        );
        $indexer->directory($self->directory) if $self->directory;
        $indexer->run();
    }
    if ( $auth_count > 0 ) {
        my $indexer = Koha::Contrib::Tamil::Indexer->new(
            koha        => $self->koha,
            source      => 'authority',
            select      => 'queue',
            blocking    => 1,
            verbose     => $self->verbose,
        );
        $indexer->directory($self->directory) if $self->directory;
        $indexer->run();
     }
}

1;

