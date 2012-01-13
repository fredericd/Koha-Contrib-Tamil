#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 22;
BEGIN {
    use FindBin qw( $Bin );
    use lib "$Bin/../lib";
    use_ok( 'Koha::Contrib::Tamil' );
    use_ok( 'Koha::Contrib::Tamil::AuthoritiesLoader' );
    use_ok( 'Koha::Contrib::Tamil::Authority::FromBiblioTask' );
    use_ok( 'Koha::Contrib::Tamil::Authority::LinkBiblioTask' );
    use_ok( 'Koha::Contrib::Tamil::Authority::LoadFileTask' );
    use_ok( 'Koha::Contrib::Tamil::Authority::Task' );
    use_ok( 'Koha::Contrib::Tamil::Conversion' );
    use_ok( 'Koha::Contrib::Tamil::Converter' );
    use_ok( 'Koha::Contrib::Tamil::EchoWatcher' );
    use_ok( 'Koha::Contrib::Tamil::FileProcess' );
    use_ok( 'Koha::Contrib::Tamil::IndexerDaemon' );
    use_ok( 'Koha::Contrib::Tamil::Indexer' );
    use_ok( 'Koha::Contrib::Tamil::Koha' );
    use_ok( 'Koha::Contrib::Tamil::LogProcess' );
    use_ok( 'Koha::Contrib::Tamil::RecordReaderBase' );
    use_ok( 'Koha::Contrib::Tamil::RecordReader' );
    use_ok( 'Koha::Contrib::Tamil::RecordWriter' );
    use_ok( 'Koha::Contrib::Tamil::RecordWriter::File' );
    use_ok( 'Koha::Contrib::Tamil::RecordWriter::File::Iso2709' );
    use_ok( 'Koha::Contrib::Tamil::RecordWriter::File::Marcxml' );
    use_ok( 'Koha::Contrib::Tamil::WatchableTask' );
    use_ok( 'Koha::Contrib::Tamil::Zebra::Clouder' );
}
