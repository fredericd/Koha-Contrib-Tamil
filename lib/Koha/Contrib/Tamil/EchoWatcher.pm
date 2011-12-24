package Koha::Contrib::Tamil::EchoWatcher;
# ABSTRACT: A watch echoing a process messages

use Moose;
use AnyEvent;

has delay   => ( is => 'rw', isa => 'Int', default => 1 );
has action  => ( is => 'rw', does => 'Koha::Contrib::Tamil::WatchableTask' );
has stopped => ( is => 'rw', isa => 'Int', default => 0 );

has wait => ( is => 'rw' );


sub start {
    my $self = shift;

    $self->action->start_message(),
    $self->wait( AnyEvent->timer(
        after => $self->delay,
        interval => $self->delay,
        cb    => sub {
            $self->action()->process_message(),
        },
    ) );
}


sub stop {
    my $self = shift;
    $self->action->end_message();
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

