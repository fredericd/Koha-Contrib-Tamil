package Koha::Contrib::Tamil::Overdue;

use Moose;
use Modern::Perl;
use YAML qw/ Dump LoadFile /;
use DateTime;
use List::Util qw/ first /;
use Path::Tiny;
use Text::Xslate;
use C4::Context;
use C4::Letters;
use C4::Letters;


# Is the process effective. If not, output the result.
has doit => ( is => 'rw', isa => 'Bool' );

# Is the process effective. If not, output the result.
has verbose => ( is => 'rw', isa => 'Bool' );


=attr c

Content of <KOHA_CONF directorty>/overdue/config.yaml file.

=cut
has c => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {
        my $file = $ENV{KOHA_CONF};
        $file =~ s/koha-conf\.xml/overdue\/config.yaml/;
        my $c = LoadFile($file);
        return $c;
    },
);

has tx => ( is => 'rw', isa => 'Text::Xslate' );

has now => (
    is => 'rw',
    isa => 'Str',
    default => sub {
        my $self = shift;
        DateTime->DefaultLocale($ENV{LANG});
        my $d = DateTime->now()->strftime("%A %e %B %Y");
        $d =~ s/  / /g;
        return $d;
    }
);


sub BUILD {
    my $self = shift;

    $self->tx( Text::Xslate->new(
        path => $self->c->{dirs}->{template},
        suffix => '.tx',
        type => 'text',
    ) );
}

 
#
# Claim a specific group of issues
#
sub claim {
    my ($self, $borrowernumber, $cycle, $items) = @_;
 
    # On the claim, branch info come from borrower home branch
    my $dbh = C4::Context->dbh();
    my $sth = $dbh->prepare("
        SELECT borrowers.*, branches.*, categories.*
          FROM borrowers, branches, categories
         WHERE borrowers.borrowernumber = ?
           AND categories.categorycode = borrowers.categorycode
           AND branches.branchcode = borrowers.branchcode
        ");
    $sth->execute($borrowernumber);
    my $borr = $sth->fetchrow_hashref;
    $borr->{$_} ||= '' for qw/ firstname surname /;
    my $has_email = $borr->{email} ? 1 : 0;

    # Skip issue from borrower of specific category
    return unless $borr->{overduenoticerequired};

    my $sql = "
        SELECT items.*,
               itemtypes.*,
               branches.branchname AS item_branch,
               biblio.*,
               biblioitems.*,
               issues.date_due,
               issues.issuedate,
               TO_DAYS(NOW())-TO_DAYS(date_due) AS overdue_days
          FROM issues, items, itemtypes, branches, biblio, biblioitems
         WHERE issues.itemnumber IN (" . join(',', @$items) . ")
           AND items.itemnumber = issues.itemnumber
           AND itemtypes.itemtype = items.itype
           AND branches.branchcode = items.holdingbranch
           AND biblio.biblionumber = items.biblionumber
           AND biblioitems.biblionumber = items.biblionumber";
    $sth = $dbh->prepare($sql);
    $sth->execute;
    my $context = { now => $self->now, borrower => $borr };
    my $i = $context->{items} = [];
    while ( my $issue = $sth->fetchrow_hashref ) {
        my $d = $issue->{date_due};
        $d = substr($d, 8, 2) . '-' . substr($d, 5, 2) . '-' . substr($d, 0, 4);
        $issue->{date_due} = $d;
        push @$i, $issue;
    }

    for my $claim ( @{$cycle->{claims}} ) {
        next if $claim->{type} eq 'email' && !$has_email;
        $context->{title} = $cycle->{title};
        my $template = $claim->{template};
        #say "CONTEXT", Dump($context);
        $self->tx->{type} = $has_email ? 'text' : 'html';
        my $content = $self->tx->render($template , $context);
        $content =~ s/&#39;/'/g; #FIXME: why?
        my $letter = {
            title => $cycle->{title},
            content => $content,
            'content-type' => $has_email ? 'text/plain; charset="UTF-8"' : 'text/html; charset="UTF-8"', 
        };
        if ( $self->verbose ) {
            say $letter->{title}, ": borrower #", $borr->{borrowernumber}, " ",
                $borr->{surname}, " ", $borr->{firstname};
        }
        if ( $self->doit ) {
            C4::Letters::EnqueueLetter( {
                 letter                 => $letter,
                 borrowernumber         => $borrowernumber,
                 message_transport_type => $claim->{type},
                 to_address             => $borr->{email} || '',
                 from_address           => $borr->{branchemail},
            } );
        }
        elsif ( $self->verbose ) {
            say '-' x 72, "\n", $content, "\n";
        }
        last;
    }
 
}


sub handle_borrower {
    my ($self, $borrower) = @_;
    return unless $borrower->{borrowernumber};

    while ( my ($icycle, $items) =  each %{$borrower->{cycles}} ) {
        $self->claim(
            $borrower->{borrowernumber},
            $self->c->{cycles}->[$icycle],
            $items 
        );
    }
}
 

=method process 

Process all overdues

=cut
sub process {
    my $self = shift;
    my $dbh = C4::Context->dbh();
    my $sth = $dbh->prepare("
        SELECT borrowers.borrowernumber,
               email,
               issues.itemnumber,
               borrowers.branchcode,
               itype,
               TO_DAYS(NOW())-TO_DAYS(date_due) AS day
          FROM issues, borrowers, items
         WHERE date_due < NOW()
           AND borrowers.borrowernumber = issues.borrowernumber
           AND items.itemnumber = issues.itemnumber
      ORDER BY surname, firstname
    ");
    $sth->execute;
    my $borrower = { borrowernumber => 0 };
    my @cycles = @{$self->c->{cycles}};
    while ( my ($borrowernumber, $email, $itemnumber, $branch, $type, $day)
            = $sth->fetchrow )
    {
        my $icycle = 0;
        while ( $icycle < @cycles ) {
            $_ = $cycles[$icycle];
            last if 
                ($_->{branch} eq $branch || $_->{branch} eq '*') &&
                ($_->{type} eq $type || $_->{type} eq '*')       &&
                ($day >= $_->{from} && $day <= $_->{to});
            $icycle++;
        }
        next if $icycle == @cycles;
        if ( $borrowernumber != $borrower->{borrowernumber} ) {
            $self->handle_borrower( $borrower );
            $borrower = { borrowernumber => $borrowernumber, cycles => {} };
        }
        my $cycles = $borrower->{cycles};
        my $items = $cycles->{$icycle} ||= [];
        push @$items, $itemnumber;
    }
    $self->handle_borrower( $borrower );
}


=method clear

Clear 'email', 'print' messages with 'pending' status from message_queue that
have been added the last hour.

=cut
sub clear {
    my $sql = "DELETE FROM message_queue
                WHERE status = 'pending'
                  AND message_transport_type IN ('email','print')
                  AND time_queued >= DATE_SUB(now(), interval 1 HOUR) ";
    C4::Context->dbh->do($sql)
}


=method print

Print all 'print' type letters from message_queue that have 'pending' status.

=cut
sub print {
    my $self = shift;

    my $messages = C4::Letters::_get_unsent_messages( { message_transport_type => 'print' } );
    my %msg_per_branch;
    for my $message ( @$messages ) {
        my $m = $msg_per_branch{$message->{branchcode}} ||= [];
        push @$m, $message;
    }
    $messages = undef;

    my $dir = $self->c->{dirs}->{print};
    say "Print in directory $dir" if $self->verbose;
    chdir $dir;
    my $now = DateTime->now();
    mkdir $now->year  unless -d $now->year;
    chdir $now->year;
    $now = $now->ymd;
    while ( my ($branch, $messages) = each %msg_per_branch ) {
        if ($self->doit) {
            mkdir $branch unless -d $branch;
            chdir $branch;
        }
        my $file = "$now-$branch.html";
        say "Create file $branch/$file" if $self->verbose;
        if ( $self->doit ) {
            my $fh = IO::File->new($file, ">:encoding(utf8)")
                or die "Enable to create $file";
            print $fh $_->{content} for @$messages;
        }
        chdir ".." if $self->doit;
    }

    return unless $self->doit;
    say "Set all 'print' messages from 'pending' to 'sent'" if $self->doit && $self->verbose;
    C4::Context->dbh->do(
        "UPDATE message_queue SET status='sent' WHERE message_transport_type='print'");
}


sub email {
  my $self = shift;
  return unless $self->doit;
  say "Send 'email' messages" if $self->verbose;
  C4::Letters::SendQueuedMessages({ verbose => $self->verbose });
}


1;