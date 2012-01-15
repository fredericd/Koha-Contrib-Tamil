package Koha::Contrib::Tamil::Sitemaper::Writer;
#ABSTRACT: Koha sitemaper writer

use Moose;
use XML::Writer;
use IO::File;
use DateTime;


my $MAX = 50000;

has url => ( is => 'rw', isa => 'Str');

has current => ( is => 'rw', isa => 'Int', default => 9999999 );

has count => ( is => 'rw', isa => 'Int', default => 0 );

has writer => ( is => 'rw', isa => 'XML::Writer' );



sub write {
    my ($self, $biblionumber, $timestamp) = @_;

    if ( $self->current >= $MAX ) {
        $self->writer_end();
        $self->count( $self->count + 1 );
        my $name = sprintf("sitemap%04d.xml", $self->count); 
        my $fh = IO::File->new(">$name");
        my $writer = XML::Writer->new(
            OUTPUT => $fh,
            DATA_MODE => 1,
            DATA_INDENT => 2,
        );
        $self->writer($writer);
        $writer->startTag('urlset', 'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9');
        $self->current(0);
    }

    $self->current( $self->current + 1 );
    my $writer = $self->writer;
    $writer->startTag('url');
        $writer->startTag('loc');
            $writer->characters($self->url . "/bib/$biblionumber");
        $writer->endTag();
        $writer->startTag('lastmod');
            $timestamp = substr($timestamp, 0, 10);
            $writer->characters($timestamp);
        $writer->endTag();
    $writer->endTag();
}


sub writer_end {
    my $self = shift;
    return unless $self->writer;
    $self->writer->endTag();
    $self->writer->end();
}


sub end {
    my $self = shift;

    $self->writer_end();

    my $fh = IO::File->new(">sitemapindex.xml");
    my $w = XML::Writer->new(
        OUTPUT => $fh,
        DATA_MODE => 1,
        DATA_INDENT => 2,
    );
    $w->startTag('sitemapindex', 'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9');
    my $now = DateTime->now()->ymd;
    for my $i ( 1..$self->count ) {
        $w->startTag('sitemap');
            $w->startTag('loc');
                my $name = sprintf("sitemap%04d.xml", $i);
                $w->characters($self->url . "/$name");
            $w->endTag();
            $w->startTag('lastmod');
                $w->characters($now);
            $w->endTag();
        $w->endTag();
    }
    $w->endTag();
}


no Moose;
1;

