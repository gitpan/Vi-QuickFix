#!/usr/bin/perl
package Vi::QuickFix;
use strict; use warnings;

our $VERSION     = ('$Revision: 1.110 $' =~ /(\d+.\d+)/)[ 0];

goto end if caller; # standard call as a module

# process <> if called as an executable
require Getopt::Std;
Getopt::Std::getopts( 'q:f:v', \ my %opt);
print "$0 version $VERSION\n" and exit 0 if $opt{ v};
my $file = $opt{ q} || $opt{ f} || 'errors.err';
tie *STDOUT, 'Vi::QuickFix::Tee', '>&STDOUT', $file;
print while <>; # copy everything to tee'd output
exit;

###########################################################################

sub import {
    my $class = shift;
    my $file = shift || 'errors.err';
    tie *STDERR, 'Vi::QuickFix::Tee', '>&STDERR', $file;
}

# tie class to tee re-formatted output to an error file
BEGIN {{
package Vi::QuickFix::Tee;

use Tie::Handle;
use base 'Tie::StdHandle';
our @CARP_NOT = qw( Vi::QuickFix); # so carp remains user-relative


# class global, the file to write transformed messages to.
# this is set in TIEHANDLE from a user parameter.  this looks as if
# the tee'd file could be set per-handle, but there is only one for all
my $errhandle;

sub TIEHANDLE {
    my $class = shift;
    my $errfile = pop;
    open $errhandle, '>', $errfile or do {
        require Carp;
        Carp::croak( "Can't create error file '$errfile': $!");
    };
    $class->SUPER::TIEHANDLE( @_);
}

# run all output though the tee
use constant PERL_MSG => qr/^(.*) at (.*) line (\d+)(\.|, near ".*"|, at .*)$/;
sub WRITE {
    my $fh = shift;
    my ( $scalar, $length) = @_;
    for ( split "\n", $scalar ) {
        my ( $message, $file, $line, $rest) = $_ =~ PERL_MSG or next;
        $message .= $rest if ($rest =~ s/^,//);
        print $errhandle "$file:$line:$message\n";
    }
    $fh->SUPER::WRITE( @_);

}
}}

end: 1;

__END__

=head1 NAME

Vi::QuickFix - Support for vim's QuickFix mode

=head1 SYNOPSIS

  #!/usr/bin/perl
  use Vi::QuickFix;

  #!/usr/bin/perl
  use Vi::QuickFix '/my/errorfile';

  perl -MVi::QuickFix program
  
  perl -MVi::QuickFix=/my/errorfile program

=head1 DESCRIPTION

With QuickFix support, Perl logs errors and warnings to an I<error file>
named, by default, C<errors.err>.  This file is picked up when
vim is called in QuickFix mode as C<vim -q>.  Vim starts editing the
perl source where the first error occured, at the error location.
QuickFix allows you to jump from one error to another, switching files
as necessary.  Type C<:help quickfix> in vim for a description.

To activate QuickFix support in Perl, add

    use Vi::QuickFix;

or, specifying an error file

    use Vi::QuickFix '/my/errorfile';

to your main program, before other C<use> statements.

To leave the program file unaltered, Vi::QuickFix can be invoked
from the command line as

    perl -MVi::QuickFix program
or
    perl -MVi::QuickFix=/my/errorfile program

It is a fatal error when the error file cannot be opened.  C<Vi::QuickFix>
is a development tool and is not meant to be remain in a distributed product.

=head1 USAGE

The module file .../Vi/QuickFix.pm can also be called as an executable.
In that mode, it behaves (roughly) like the C<cat> command, but also
logs Perl warnings and error messages it encounters to the
error file.  The error file can be set through the switches C<-f> or C<-q>.
Called with -v, it prints the version and exits.

You may want to use C<Vi::QuickFix> this way to keep everything
C<Vi::QuickFix>-related away from your program in a different process.
In that case you should copy or link C<.../Vi/QuickFix.pm> to a file
C<tee_quickfix> or similar in a directory along your command path.

Used as

    ./program |& tee_quickfix
or
    ./program |& tee_quickfix -f /my/errorfile

it will create an error file and still show the program output and
error messages on the screen.

This mode is not particularly supported.  A more versatile tool
with similar functionality comes with vim.  It is located in
C<$VIMRUNTIME/tools/efm_perl.pl>.  C<$VIMRUNTIME> is
C</usr/share/vim/vim62/> on my machine, for what it's worth.

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
