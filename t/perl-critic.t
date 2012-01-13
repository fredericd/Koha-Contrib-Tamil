#!/usr/bin/perl

use strict;
use warnings;
use File::Spec;
use Test::More;

if ( not $ENV{TEST_AUTHOR} ) {
    plan( skip_all =>
        'Set $ENV{TEST_AUTHOR} to a true value to run.' );
}
eval "use Test::Perl::Critic";
if ( $@ ) {
    plan( skip_all =>
        'Test::Perl::Critic required to criticise code' );
}
#my $rcfile = File::Spec->catfile( 't', 'perlcriticrc' );
#Test::Perl::Critic->import( -profile => $rcfile );
all_critic_ok();

