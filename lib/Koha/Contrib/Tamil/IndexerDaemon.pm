package Koha::Contrib::Tamil::IndexerDaemon;
# ABSTRACT: Class implementing a Koha records indexer daemon

use Moose;

use 5.010;
use utf8;
use AnyEvent;
use Koha::Contrib::Tamil::Koha;
use Koha::Contrib::Tamil::Indexer;
use Locale::TextDomain ('Koha-Contrib-Tamil');

with 'MooseX::Getopt';


has name => ( is => 'rw', isa => 'Str' );


=attr conf($file_name)

Koha configuration file name. If not supplied, KOHA_CONF environment variable
is used to locate the configuration file.

=cut

has conf => ( is => 'rw', isa => 'Str' );


=attr directory($directory_name)

Location of the directory where to export biblio/authority records before
sending them to Zebra indexer.

=cut

has directory => ( is => 'rw', isa => 'Str' );


=attr timeout($seconds)

Number of seconds between indexing.

=cut

has timeout => (
    is      => 'rw',
    isa     => 'Int',
    default => 60,
);


=attr verbose(0|1)

Task verbosity.

=cut

has verbose => ( is => 'rw', isa => 'Bool', default => 0 );

has koha => ( is => 'rw', isa => 'Koha::Contrib::Tamil::Koha' );


sub BUILD {
    my $self = shift;

    print __"Starting Koha Indexer Daemon", "\n";

    $self->koha( $self->conf
        ? Koha::Contrib::Tamil::Koha->new(conf_file => $self->conf)
        : Koha::Contrib::Tamil::Koha->new() );
    $self->name( $self->koha->conf->{config}->{database} );

    my $idle = AnyEvent->timer(
        after    => $self->timeout,
        interval => $self->timeout,
        cb       => sub { $self->index_zebraqueue(); }
    );
    AnyEvent->condvar->recv;
}


sub index_zebraqueue {
    my $self = shift;

    my $sql = " SELECT COUNT(*), server 
                FROM zebraqueue 
                WHERE done = 0
                GROUP BY server ";
    my $sth = $self->koha->dbh->prepare($sql);
    $sth->execute();
    my %count = ( biblio => 0, authority => 0 );
    while ( my ($count, $server) = $sth->fetchrow ) {
        $server =~ s/server//g;
        $count{$server} = $count;
    }

    print __x (
        "[{name}] Index biblio ({biblio_count}) authority ({auth_count})",
        name => $self->name,
        biblio_count => $count{biblio},
        auth_count => $count{authority} ), "\n";

    for my $source (qw/biblio authority/) {
        next unless $count{$source};
        my $indexer = Koha::Contrib::Tamil::Indexer->new(
            koha        => $self->koha,
            source      => $source,
            select      => 'queue',
            blocking    => 1,
            keep        => 1,
            verbose     => $self->verbose,
        );
        $indexer->directory($self->directory) if $self->directory;
        $indexer->run();
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__
=pod 

=head1 SYNOPSIS

 # Index Koha queued biblio/authority records every minute.
 # KOHA_CONF environment variable is used to find which Koha
 # instance to use.
 # Records are exported from Koha DB into files located in
 # the current directory
 my $daemon = Koha::Contrib::Tamil::IndexerDaemon->new();

 my $daemon = Koha::Contrib::Tamil::IndexerDaemon->new(
    timeout   => 20,
    conf      => '/home/koha/mylib/etc/koha-conf.xml',
    directory => '/home/koha/mylib/tmp',
    verbose   => 1 );

=cut

