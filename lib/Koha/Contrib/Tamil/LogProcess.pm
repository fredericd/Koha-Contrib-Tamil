package Koha::Contrib::Tamil::LogProcess;
# ABSTRACT: Base class for process loger
use Moose;

use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::File;


has log => (
    is => 'rw',
    isa => 'Log::Dispatch',
    default => sub { 
        my $log = Log::Dispatch->new();
        $log->add( Log::Dispatch::Screen->new(
            name      => 'screen',
            min_level => 'notice',
        ) );
        $log->add( Log::Dispatch::File->new(
            name      => 'file1',
            min_level => 'debug',
            filename  => "process.log",
            binmode   => ':utf8',
        ) );
        return $log;
    }
);



no Moose;
__PACKAGE__->meta->make_immutable;

1;


=head1 NAME

LogProcess - Logger
    
=head1 COPYRIGHT AND LICENSE

Copyright 2010 by Tamil, s.a.r.l.

L<http://www.tamil.fr>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


