#!/usr/bin/perl
package Vi::QuickFix;
use strict; use warnings;
use Carp;

our $VERSION     = ('$Revision: 1.116 $' =~ /(\d+.\d+)/)[ 0];

unless ( caller ) {
    # process <> if called as an executable
    require Getopt::Std;
    Getopt::Std::getopts( 'q:f:v', \ my %opt);
    print "$0 version $VERSION\n" and exit 0 if $opt{ v};
    my $file = $opt{ q} || $opt{ f} || 'errors.err';

    tie *STDOUT, 'Vi::QuickFix::Tee', '>&STDOUT', $file;
    print while <>; # copy everything to tee'd output
    exit;
}

{{ # switch off otherwise obligatory warning
my $silent;
sub set_silent { $silent = 1 }
sub is_silent { $silent }
}}

###########################################################################

sub import {
    my $class = shift;
    if ( $_[ 0] and $_[ 0] eq 'silent' ) {
        set_silent;
        shift;
    }
    if ( tied *STDERR ) {
        my $tieclass = ref tied *STDERR;
        return if $tieclass->isa( 'Vi::QuickFix::Tee'); # don't tie again
        croak( "STDERR already tied to class '$tieclass'");
    }
    my $file = shift || 'errors.err';
    tie *STDERR, 'Vi::QuickFix::Tee', '>&STDERR', $file;
}

# tie class to tee re-formatted output to an error file
BEGIN {{
package Vi::QuickFix::Tee;

use IO::File;
use Tie::Handle;
use base 'Tie::StdHandle';
use Carp;
# so carp doesn't assign error locations there when called from here
our @CARP_NOT = qw( Vi::QuickFix);

# file globals.
my $errhandle; # write formatted errors here
my $errfile;   # name of that file
my $errcount;  # for END to know if file can be erased. (-s would need flush)

END {
    # don't do any of this in exec mode
    last unless caller;
    # remove file if created by us and empty
    if ( $errhandle ) {
        # issue obligate warning
        carp "Vi::QuickFix is active" unless Vi::QuickFix->is_silent;
        unlink $errfile unless $errcount;
    }
}

sub TIEHANDLE {
    my $class = shift;
    $errfile = pop;
    $errhandle =IO::File->new( "> $errfile") or croak(
        "Can't create error file '$errfile': $!"
    );
    $class->SUPER::TIEHANDLE( @_);
}

# run all output though the tee
use constant PERL_MSG =>
#   qr/^(.*) at (.*) line (\d+)(\.?|, near ".*"|, at .*)$/;
    qr/^(.*?) at (.*?) line (\d+)(\.?|,.*)$/;
sub WRITE {
    my $fh = shift;
    my ( $scalar, $length) = @_;
    for ( split "\n", $scalar ) {
        my ( $message, $file, $line, $rest) = $_ =~ PERL_MSG or next;
        $message .= $rest if ($rest =~ s/^,//);
        print $errhandle "$file:$line:$message\n";
        $errcount ++;
    }
    $fh->SUPER::WRITE( @_);
}
}}

1;

__END__

=head1 NAME

Vi::QuickFix - Support for vim's QuickFix mode

=head1 SYNOPSIS

  use Vi::QuickFix;

  use Vi::QuickFix '/my/errorfile';

  use Vi::QuickFix 'silent';

  use Vi::QuickFix silent => '/my/errorfile';

=head1 DESCRIPTION

When C<Vi::QuickFix> is active, Perl logs errors and warnings to an
I<error file> named, by default, C<errors.err>.  This file is picked
up when vim is called in QuickFix mode as C<vim -q>.  Vim starts editing the
perl source where the first error occured, at the error location.
QuickFix allows you to jump from one error to another, switching files
as necessary.  Type C<:help quickfix> in vim for a description.

To activate QuickFix support, add

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
in a distributed product.  When the program ends, a warning is issued
that C<Vi::QuickFix> is active.  This has the side effect that there
is always an entry in the error file which points to the file where
C<Vi::QuickFix> was invoked, normally the main program.  C<vi -q> will
edit this file when other error entries don't point it elsewhere.  Use the
C<silent> option with C<Vi::QuickFix> to suppress this warning.

It is a fatal error when the error file cannot be opened.  If the error
file is empty (can only happen with C<silent>), it is removed at the end
of the run.

=head1 USAGE

The module file .../Vi/QuickFix.pm can also be called as an executable.
In that mode, it behaves (roughly) like the C<cat> command, but also
moitors the stream and logs Perl warnings and error messages to the
error file.  The error file can be set through the switches C<-f> or C<-q>.
No warning about QuickFix activity is issued in this mode.

Called with -v, it prints the version and exits.

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
