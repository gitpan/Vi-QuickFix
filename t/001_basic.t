# -*- perl -*-

use Test::More;
my $n_tests;

use constant ERR_TXT => ( 'boo', 'bah');
use constant ERRFILE => {
    mine => 'my_errors',
    std  => 'errors.err',
};
use constant REDIRECT => ">/dev/null 2>&1";
use constant Q_REDIRECT => "'" . REDIRECT;
use constant PER_CALL => 1 + ERR_TXT; # n of tests per call of run_tests()

BEGIN { $n_tests += 2 * PER_CALL }
{{
my $command = qq(perl -Ilib -MVi::QuickFix -e');
$command .= qq(warn "$_"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_switch', 'std', $command);

$command = qq(perl -Ilib -e');
$command .= qq(use Vi::QuickFix; );
$command .= qq(warn "$_"; print STDERR "# something else\n"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_use', 'std', $command);
}}

BEGIN { $n_tests += 2 * PER_CALL }
{{
my $command = qq(perl -Ilib -MVi::QuickFix=*ERRFILE* -e');
$command .= qq(warn "$_"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_switch', 'mine', $command);

$command = qq(perl -Ilib -e');
$command .= qq(use Vi::QuickFix "*ERRFILE*"; );
$command .= qq(warn "$_"; print STDERR "something else\n"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_use', 'mine', $command);
}}

# prepare input file for executable
open my $errtxt, '>', 'errtxt' or die;
print $errtxt "$_ at some_file line 12.\nsomething_else\n" for ERR_TXT;
close $errtxt;

BEGIN { $n_tests += 2 * PER_CALL }
{{
my $command = qq(perl lib/Vi/QuickFix.pm errtxt) . REDIRECT;
run_tests( 'command_file', 'std', $command);

$command = qq(perl ./lib/Vi/QuickFix.pm <errtxt) . REDIRECT;
run_tests( 'command_stdin', 'std', $command);
}}

BEGIN { $n_tests += 2 + 2 * PER_CALL }
{{

# check -v key (version)
my $command = qq(perl lib/Vi/QuickFix.pm -v);
open my $f, "$command |";
ok( defined $f, "Got a handle");
like( scalar <$f>, qr/version *\d+\.\d+/, "-v returns version");

my $command = qq(perl lib/Vi/QuickFix.pm -f *ERRFILE* errtxt) . REDIRECT;
run_tests( 'command_file', 'mine', $command);

$command = qq(perl ./lib/Vi/QuickFix.pm -q *ERRFILE* <errtxt) . REDIRECT;
run_tests( 'command_stdin', 'mine', $command);
}}
unlink 'errtxt';

# do we catch all types of STDERR output?
use constant CASES => (
    [ runtime_warning =>     '"a" + 0',           'Argument "a"' ],
    [ runtime_error =>       'chomp ${ []}',      'Not a SCALAR' ],
    [ compiletime_warning => 'my @y; @y = @y[0]', 'Scalar value' ],
    [ compiletime_error =>   '%',                 'syntax error' ],
    [ explicit_warning =>    'warn "xxx"',        'xxx'          ],
    [ explicit_error =>      'die "yyy"',         'yyy'          ],
);
BEGIN { $n_tests += 2 * CASES }
{{
for ( CASES ) {
    my ( $case, $prog, $msg) = @$_;
    unlink 'errors.err';
    system "perl -Ilib -MVi::QuickFix -we '$prog' >/dev/null 2>&1";
    ok( open( my $e, 'errors.err'), "$case open");
    like( scalar <$e>, qr/^.*:\d+:$msg/, "$case message");
}
unlink 'errors.err';
}}

BEGIN { plan tests => $n_tests }

#####################################################################

sub  run_tests {
    my ( $call, $errf, $command) = @_;
    my $errfile = ERRFILE->{ $errf};
    $command =~ s/\*ERRFILE\*/$errfile/g;
    unlink $errfile;
    system( $command) == 0 or die "command in error: '$command'";
#   don't forget PER_CALL when uncommenting
#   ok( -s $errfile, "$call $errf size");
    ok( open( my $e, $errfile), "$call $errf open");
    my $i;
    for ( ERR_TXT ) {
        $i ++;
        like( scalar <$e>, qr/^(.*?):\d+:$_$/, "$call $errf $i");
    }
}
