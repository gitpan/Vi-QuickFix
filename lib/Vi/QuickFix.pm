#!/usr/bin/perl
package Vi::QuickFix;
use 5.008_000;
use strict; use warnings;
use Carp;

our $VERSION;
BEGIN {
    $VERSION = ('$Revision: 1.129 $' =~ /(\d+.\d+)/)[ 0];
}

unless ( caller ) {
    # process <> if called as an executable
    set_exec_mode(); # signal fact ( to END processing)
    require Getopt::Std;
    Getopt::Std::getopts( 'q:f:v', \ my %opt);
    print "$0 version $VERSION\n" and exit 0 if $opt{ v};
    err_open( $opt{ q} || $opt{ f});
    print && err_print( $_) while <>;
    exit;
}

###########################################################################

# keywords for ->import
use constant KEYWORDS => qw( silent sig tie);

# environment variable(s)
use constant VAR_SOURCEFILE => 'VI_QUICKFIX_SOURCEFILE';

BEGIN {{ # space for private variables

# user parameters:
my $errfile = 'errors.err'; # name of error file
my $silent = 0;             # switch off otherwise obligatory warning
my $relay = '';             # method of transfer to error file: "sig" or "tie"

sub make_silent { $silent = 1 }
sub is_silent { $silent } # should this be a package variable?

sub import {
    my $class = shift;
    my %keywords;
    @keywords{ KEYWORDS()} = ();
    $keywords{ shift()} = 1 while @_ and exists $keywords{ $_[ 0]};

    err_open( shift);
    make_silent if $keywords{ silent};
    my ( $wanted_relay) = grep $keywords{ $_}, qw( sig tie);
    $relay = $wanted_relay || default_relay();
    if ( my $reason = relay_obstacle( $relay) ) {
        croak( "Cannot use '$relay' method: $reason");
    }
    if ( $relay eq 'tie' and not tied *STDERR ) {
        # if tied, it's tied to ourselves (otherwise obstacle)
        tie *STDERR, 'Vi::QuickFix::Tee', '>&STDERR';
    } elsif ( $relay eq 'sig' ) {
        $SIG{ $_} = Vi::QuickFix::SigHandler->new( $_) for
            qw( __WARN__ __DIE__);
    }
}

# internal variables
my $errhandle; # write formatted errors here
my $errcount;  # for END to know if file can be erased. (-s would need flush)
               # otherwise unused
my $exec_mode; # set if lib file is run as a script
sub set_exec_mode { $exec_mode = 1 }

# open the given file (or default), set $errfile and $errhandle
sub err_open {
    $errfile = shift || 'errors.err';
    $errhandle = IO::File->new( "> $errfile") or croak(
        "Can't create error file '$errfile': $!"
    );
}

sub err_close { close $errhandle if $errhandle }

use Carp;
# write to the error file and increase errcount if appropriate,
use constant PERL_MSG => qr/^(.*?) at (.*?) line (\d+)(\.?|,.*)$/;
sub err_print {
    # handle multiple, possibly multi-line messages (though usually
    # there will be only one)
#   Carp::confess( 'err_print');
    for ( map split( /\n+/), @_ ) {
        my ( $message, $file, $line, $rest) = $_ =~ PERL_MSG or next;
        $message .= $rest if $rest =~ s/^,//;
        $file eq '-' and defined and $file = $_ for $ENV{ VAR_SOURCEFILE()};
        print $errhandle "$file:$line:$message\n";
        $errcount ++;
    }
}

# issue warning, erase error file
my $end_entiteled = $$;
END {
    # issue warning (only original process, and not in exec mode)
    carp "QuickFix active" unless
        is_silent or $exec_mode or $$ != $end_entiteled;
    # silently remove objects
    make_silent();
    if ( $relay eq 'tie' ) {
        untie *STDERR;
    } else {
        $SIG{ $_} = 'DEFAULT' for qw( __WARN__ __DIE__);
    }
    # remove file if created by us and empty (only original process)
    err_close(); # so we can unlink under windows
    unlink $errfile if not $errcount and $$ == $end_entiteled;
}

}}

use constant MINVERS => 5.008001; # minimum perl version for tie method
sub relay_obstacle {
    my $relay = shift || '';
    return '' unless $relay eq 'tie';
    if ( $] < MINVERS ) {
        return "perl version is $], must be >= @{[ MINVERS]}";
    }
    if ( my $tie_ob = tied *STDERR ) {
        my $tieclass = ref $tie_ob;
        return "STDERR already tied to '$tieclass'" unless
            $tieclass eq 'Vi::QuickFix::Tee';
    }
    return '';
}

sub default_relay { relay_obstacle( 'tie') ? 'sig' : 'tie' }

# common destructor method
package Vi::QuickFix::Destructor;

use Carp qw( shortmess);
BEGIN { our @CARP_NOT = qw( Vi::QuickFix) }
sub DESTROY {
    my $ob = shift;
    return if Vi::QuickFix::is_silent or $^C; # it's a mess under -c
    my $id = $ob->id;
    my $msg = shortmess( "QuickFix $id processing interrupted");
    # simulate intact QuickFix processing
    Vi::QuickFix::err_print( $msg);
    warn "$msg";
}

# Class to associate a DESTROY method with sig handlers
package Vi::QuickFix::SigHandler;
use base qw( Vi::QuickFix::Destructor);

# return a chaining handler for __WARN__ or __DIE__
sub new {
    my $class = shift;
    my $sig = shift;
    my $prev_handler = $SIG{ $sig};
    my $sub = sub {
        return $sig unless @_; # backdoor
        Vi::QuickFix::err_print( @_);
        my $code;
        # resolve string at call time
        if ( $prev_handler ) {
            $code = ref $prev_handler ?
                $prev_handler :
                \ &{ 'main::' . $prev_handler};
        }
        goto &$code if $code;
        die @_ if $sig eq '__DIE__';
        warn @_;
    };
    bless $sub, $class; # so we can have a destructor
}

sub id {
    my $handler = shift;
    $handler->(); # call without args returns __WARN__ or __DIE__
}

# tie class to tee re-formatted output to an error file
package Vi::QuickFix::Tee;

use IO::File;
use Tie::Handle;
use base qw( Tie::StdHandle Vi::QuickFix::Destructor);

sub WRITE {
    my $fh = shift;
    my ( $scalar, $length) = @_;
    Vi::QuickFix::err_print( $scalar);
    $fh->SUPER::WRITE( @_);
}

sub id { 'STDERR' }

1;

__END__

=head1 NAME

Vi::QuickFix - Support for vim's QuickFix mode

=head1 SYNOPSIS

  use Vi::QuickFix;
  use Vi::QuickFix <errorfile>;
  use Vi::QuickFix <options>;
  use Vi::QuickFix <options> <errorfile>;

where C<E<lt>optionsE<gt>> is one or more of C<silent>, C<sig>, and C<tie>.

=head1 DESCRIPTION

When C<Vi::QuickFix> is active, Perl logs errors and warnings to an
I<error file> named, by default, C<errors.err>.  This file is picked
up when you type C<:cf> in a running vim editor.  Vim will jump to the
location of the first error recorded in the error file.  C<:cn> takes
you to the next error, switching files if necessary.  There are more
QuickFix commands in vim.  Type C<:help quickfix> for a description.

To activate QuickFix support for a Perl source, add

    use Vi::QuickFix;

or, specifying an error file

    use Vi::QuickFix '/my/errorfile';

early in the main program, before other C<use> statements.

To leave the program file unaltered, Vi::QuickFix can be invoked
from the command line as

    perl -MVi::QuickFix program
or
    perl -MVi::QuickFix=/my/errorfile program

C<Vi::QuickFix> is meant to be used as a development tool, not to remain
in a distributed product.  When the program ends, a warning is issued,
indicating that C<Vi::QuickFix> was active.
This has the side effect that there is always an entry in the error file
which points to the source file where C<Vi::QuickFix> was invoked, normally
the main program. C<:cf> will take you there when other error entries
don't point it elsewhere.  Use the C<silent> option with C<Vi::QuickFix> to
suppress this warning.

It is a fatal error when the error file cannot be opened.  If the error
file is empty (can only happen with C<silent>), it is removed at the end
of the run.

=head1 ENVIRONMENT

C<Vi::QuickFix> recognizes the environment variable C<VI_QUICKFIX_SOURCEFILE>

When Perl reads its source from C<STDIN>, error messages and warnings
will contain the string "-" where the source file name would otherwise
appear.  The environment variable C<VI_QUICKFIX_SOURCEFILE> can be set
to a filename, which will replace "-" in those messages. If no "-" appears
as a file name, setting the variable has no effect.

This somewhat peculiar behavior can be useful if you call perl (with
C<Vi::QuickFix>) from within a vim run, as in C<:w !perl -MVi::QickFix>.
When you set the environment variable C<VI_QUICKFIX_SOURCEFILE> to the
name of the file you are editing, this fools vim into doing the right
thing when it encounters the modified messages.

This is an experimental feature, the behavior may change in future
releases.

=head1 USAGE

The module file .../Vi/QuickFix.pm can also be called as an executable.
In that mode, it behaves basically like the C<cat> command, but also
monitors the stream and logs Perl warnings and error messages to the
error file.  The error file can be set through the switches C<-f> or C<-q>.
No warning about QuickFix activity is issued in this mode.

Called with -v, it prints the version and exits.

=head1 IMPLEMENTATION

For a debugging tool, an implementation note is in order.

Perl offers to obvious ways to watch and capture its error output.
One is through the (pseudo-) signal handlers C<$SIG{__WARN__}> and
C<$SIG{__DIE__}>.  The other is through C<tie>-ing the C<STDERR> file
handle.

C<Vi::QuickFix> can use either method to create the error file.
As it turns out, the ability to tie C<STDERR> is relatively new with
Perl, as of version 5.8.1.  With Versions 5.8.0 and earlier, a number
of internal errors and warnings don't respect tie, so this method
cannot be used.  With Perl versions ealier than 5.8.1, C<Vi::QuickFix>
uses %SIG handlers to catch messages.  With newer versions, C<Vi::Quickfix>
ties C<STDERR> so that it (additionally) writes to the error file.

A specific method can be requested through the options C<sig> and
C<tie>, as in

    use Vi::QuickFix qw( sig);

Requesting C<tie> with a Perl version that can't handle it is a
fatal error, so the only option that does anything useful is C<sig>
with a new-ish Perl.  It can be useful when C<tie>-ing C<STDERR> conflicts
with the surrounding code.

=head1 CONFLICTS

Such a conflict can occur with the C<sig> method as well, and it can
happen in two ways.  Either C<Vi::QuickFix> already finds a resource
(a C<%SIG> handler or a tie on C<STDERR>) occupied at C<use> time, or the
surrounding code commandeers the resource after the fact.

All such conflicts can be avoided by using C<Vi::QuickFix> in a
separate process, as noted under L</"USAGE>.

However, if C<STDERR> is already tied when C<Vi::QuickFix> is C<use>d, 
it cannot employ the C<tie> method, and by default reverts to C<sig>.
If the C<tie> method is specifically requested, a fatal error results.

If the C<sig> method finds one of the handlers (C<__WARN__> and C<__DIE__>)
already occupied, it chains to the previous handler after doing its
thing, so that is not considered an obstacle.  "Chaining" file ties is
harder, and has not been attempted.

If C<Vi::QuickFix> is already active, the surrounding code may later
occupy a resource it is using.  There is little that can be done
when that happens, except issue a warning which is also logged to
the error file.  This can help in finding the source of the conflict.
In C<silent> mode, no such warning is given.

The warning is triggered when the corresponding resource is overwritten,
except when the overwriting program keeps a copy of it.  It is then
assumed that the program will keep it functioning.  Since we're
still talking implementation -- it is actually triggered through
a DESTROY method when the corresponding object goes out of scope.
C<%SIG> handlers are code objects just for this reason.

=head1 VERSION

This document pertains to C<Vi::Quickfix> version 1.129

=head1 BUGS

C<no Vi::QuickFix> has no effect

=head1 AUTHOR

	Anno Siegel
	CPAN ID: ANNO
	siegel@zrz.tu-berlin.de
	http://www.tu-berlin.de/~siegel

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=head1 SEE ALSO

perl(1),  vim(1).
