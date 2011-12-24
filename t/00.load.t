#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 3;
BEGIN {
    use FindBin qw( $Bin );
    use lib "$Bin/../lib";
    use_ok( 'Koha::Contrib::Tamil::RecordReader' );
    use_ok( 'Koha::Contrib::Tamil::RecordWriter' );
    use_ok( 'Koha::Contrib::Tamil::RecordWriter::File' );
}
