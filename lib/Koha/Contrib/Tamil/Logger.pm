package Koha::Contrib::Tamil::Logger;
# ABSTRACT: Base class pour logger


use Moose;
use Modern::Perl;
use utf8;
use FindBin qw( $Bin );
use Log::Dispatch;
use Log::Dispatch::Screen;
use Log::Dispatch::File;



has log_filename => (
    is => 'rw',
    isa => 'Str',
    default => "./koha-contri-tamil.log",
);

has log => (
    is => 'rw',
    isa => 'Log::Dispatch',
    lazy => 1,
    default => sub { 
        my $self = shift;
        my $log = Log::Dispatch->new();
        $log->add( Log::Dispatch::Screen->new(
            name      => 'screen',
            min_level => 'notice',
        ) );
        $log->add( Log::Dispatch::File->new(
            name      => 'file1',
            min_level => 'debug',
            filename  => $self->log_filename, 
            binmode   => ':encoding(UTF-8)',
        ) );
        return $log;
    }
);



no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=encoding UTF-8

=head1 SYNOPSYS

 package MonModule
 use Moose;

 extends qw/ Koha::Contrib::Tamil::Logger /;

 sub foo {
    my $self = shift;
    $self->info("Sera écrit dans le fichier uniquement");
    $self->warning("Sera écrit dans le fichier ET envoyé à l'écran");
 }
 1;

 package Main;

 use MonModule;

 my $mon_module = MonModule->new( filename => 'mon_module.log');
 $mon_module->foo();

=cut

