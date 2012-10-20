package Koha::Contrib::Tamil::Koha;
#ABSTRACT: Class exposing info about a Koha instance.

use Moose;

use Carp;
use XML::Simple;
use DBI;
use ZOOM;
use MARC::Record;
use MARC::File::XML;
use YAML;


=attr conf_file

Name of Koha configuration file. If not supplied, the configuration file is
taken in KOHA_CONF environment variable.

=cut

has conf_file => ( is => 'rw', isa => 'Str' );


=attr dbh

Handle to Koha database defined in Koha configuration file.

=cut

has dbh => ( is => 'rw' );


=attr conf

Koha XML configuration file.

=cut

has conf => ( is => 'rw' );


has _zconn => ( is => 'rw', isa => 'HashRef' );


sub BUILD {
    my $self = shift;

    # Use KOHA_CONF environment variable by default
    $self->conf_file( $ENV{KOHA_CONF} )  unless $self->conf_file;

    $self->conf( XMLin( $self->conf_file, 
        keyattr => ['id'], forcearray => ['listen', 'server', 'serverinfo'],
        suppressempty => '     ') );

    # Database Handler
    my $c = $self->conf->{config};
    $self->dbh( DBI->connect(
        "DBI:"     . $c->{db_scheme} .
        ":dbname=" . $c->{database} .
        ";host="   . $c->{hostname} .
        ";port="   . $c->{port},
        $c->{user}, $c->{pass} )
    ) or carp $DBI::errstr;
    if ( $c->{db_scheme} eq 'mysql' ) {
        # Force utf8 communication between MySQL and koha
        $self->dbh->{ mysql_enable_utf8 } = 1;
        $self->dbh->do( "set NAMES 'utf8'" );
        $self->dbh->{ mysql_auto_reconnect } = 1;
        my $tz = $ENV{TZ};
        ($tz) and $self->dbh->do( qq(SET time_zone = "$tz") );
    }

    # Zebra connections 
    $self->_zconn( { biblio => undef, auth => undef } );
}


=method zconn_reset

Reset both Zebra connections, biblio/authority server.

=cut

sub zconn_reset {
    my $self = shift;
    my $zcs = $self->_zconn;
    for my $server ( keys %$zcs ) {
        my $zc = $zcs->{$server};
        $zc->destroy() if $zc;
        undef $zcs->{$server};
    }
}


=method zconn($type)

Return a connection to biblio or authority Zebra server. Example:

  my $zc = $koha->zconn('biblio');
  my $zc = $koha->zconn('authority');

=cut

sub zconn {
    my ($self, $server) = @_;

    my $zc = $self->_zconn->{$server};
    #return $zc  if $zc && $zc->errcode() == 0 && $zc->_check();
    return $zc  if $zc;

    #FIXME: à réactiver pour s'assurer que de nouvelles connexion ne sont
    # créées inutilement.
    #print "zconn: nouvelle connexion\n";
    my $c        = $self->conf;
    my $name     = $server eq 'biblio' ? 'biblioserver' : 'authorityserver';
    my $syntax   = $c->{server}->{$name}->{retrievalinfo}->{retrieval};
    $syntax = [ grep { $_->{name} && $_->{name} eq 'F' && $_->{syntax} ne 'xml' } @$syntax ];
    $syntax = $syntax->[0]->{syntax};
    my $host     = $c->{listen}->{$name}->{content};
    my $user     = $c->{serverinfo}->{$name}->{user};
    my $password = $c->{serverinfo}->{$name}->{password};
    my $auth     = $user && $password;

    # set options
    my $o = new ZOOM::Options();
    if ( $user && $password ) {
        $o->option( user     => $user );
        $o->option( password => $password );
    }
    #$o->option(async => 1) if $async;
    #$o->option(count => $piggyback) if $piggyback;
    $o->option( cqlfile => $c->{server}->{$name}->{cql2rpn} );
    $o->option( cclfile => $c->{serverinfo}->{$name}->{ccl2rpn} );
    $o->option( preferredRecordSyntax => $syntax );
    $o->option( elementSetName => "F"); # F for 'full' as opposed to B for 'brief'
    $o->option( databaseName => $server eq 'biblio' ? "biblios" : "authorities");

    $zc = create ZOOM::Connection( $o );
    $zc->connect($host, 0);
    carp "something wrong with the connection: ". $zc->errmsg()
        if $zc->errcode;

    $self->_zconn->{$server} = $zc;
    return $zc;
}


=method zbiblio

Returns a L<ZOOM::connection> to Koha bibliographic records Zebra server.

=cut

sub zbiblio {
    shift->zconn( 'biblio' );
}


=method zauth

Returns a L<ZOOM::connection> to Koha authority records Zebra server.

=cut

sub zauth {
    shift->zconn( 'auth' );
}


=method get_biblio_marc($biblionumber)

Return a MARC::Record from its biblionumber

=cut

sub get_biblio_marc {
    my ( $self, $id ) = @_; 
    my $sth = $self->dbh->prepare(
        "SELECT marcxml FROM biblioitems WHERE biblionumber=? ");
    $sth->execute( $id );
    my ($marcxml) = $sth->fetchrow;
    return unless $marcxml;
    $marcxml =~
s/[^\x09\x0A\x0D\x{0020}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]//g;
    #MARC::File::XML->default_record_format(
    #C4::Context->preference('marcflavour') );
    my $record = MARC::Record->new();
    if ($marcxml) {
        $record = eval { 
            MARC::Record::new_from_xml( $marcxml, "utf8" ) };
        if ($@) { warn " problem with: $id : $@ \n$marcxml"; }
        return $record;
    }   
    return;
}


__PACKAGE__->meta->make_immutable;

1;

