package Koha::Contrib::Tamil::WatchableTask;
#ABSTRACT: Role for tasks which are watchable

use Moose::Role;

requires 'run';
requires 'process';
requires 'process_message';
requires 'start_message';
requires 'end_message';

1;

