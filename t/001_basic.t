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


### If $] >= 5.008001, the above has tested "tie" mode, and we now
# want to check "sig" mode.  If $] < 5.008001, the above has tested
# "sig" mode.  Since "tie" mode can't be run, we just skip the "sig"-
# specific tests

use constant LOW_VERSION => $] < 5.008001;
use constant REASON_LOW => "already done with perl $]";

BEGIN { $n_tests += 2 * PER_CALL }
SKIP: {{
skip REASON_LOW, 2 * PER_CALL if LOW_VERSION;

my $command = qq(perl -Ilib -MVi::QuickFix=sig -e');
$command .= qq(warn "$_"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_switch(sig)', 'std', $command);

$command = qq(perl -Ilib -e');
$command .= qq(use Vi::QuickFix qw( sig); );
$command .= qq(warn "$_"; print STDERR "# something else\n"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_use(sig)', 'std', $command);
}}

BEGIN { $n_tests += 2 * PER_CALL }
SKIP: {{
skip REASON_LOW, 2 * PER_CALL if LOW_VERSION;

my $command = qq(perl -Ilib -MVi::QuickFix=sig,*ERRFILE* -e');
$command .= qq(warn "$_"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_switch(sig)', 'mine', $command);

$command = qq(perl -Ilib -e');
$command .= qq(use Vi::QuickFix "sig", "*ERRFILE*"; );
$command .= qq(warn "$_"; print STDERR "something else\n"; ) for ERR_TXT;
$command .= Q_REDIRECT;
run_tests( 'module_use(sig)', 'mine', $command);
}}

### more non-specific tests (as to sig/warn)

# prepare input file for executable
open my $infile, '>', 'infile' or die;
print $infile "$_ at some_file line 12.\nsomething_else\n" for ERR_TXT;
close $infile;

BEGIN { $n_tests += 2 * ( PER_CALL + 1) }
{{
my $command = qq(perl lib/Vi/QuickFix.pm infile) . '>outfile 2>/dev/null';
run_tests( 'command_file', 'std', $command);
is( -s 'outfile', -s 'infile', 'input written to stdout');

$command = qq(perl ./lib/Vi/QuickFix.pm <infile) . '>outfile 2>/dev/null';
run_tests( 'command_stdin', 'std', $command);
is( -s 'outfile', -s 'infile', 'file written to stdout');
}}


BEGIN { $n_tests += 2 + 2 * PER_CALL }
{{

# check -v key (version)
my $command = qq(perl lib/Vi/QuickFix.pm -v);
open my $f, "$command |";
ok( defined $f, "Got a handle");
like( scalar <$f>, qr/version *\d+\.\d+/, "-v returns version");

$command = qq(perl lib/Vi/QuickFix.pm -f *ERRFILE* infile) . REDIRECT;
run_tests( 'command_file', 'mine', $command);

$command = qq(perl lib/Vi/QuickFix.pm -q *ERRFILE* <infile) . REDIRECT;
run_tests( 'command_stdin', 'mine', $command);
}}
unlink 'infile', 'outfile';

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
    like( <$e>, qr/^.*:\d+:$msg/, "$case message");
}
}}

# repeat these in "sig" mode, if both modes possible
BEGIN { $n_tests += 2 * CASES }
SKIP: {{
skip REASON_LOW, 2 * CASES if LOW_VERSION;
for ( CASES ) {
    my ( $case, $prog, $msg) = @$_;
    unlink 'errors.err';
    system "perl -Ilib -MVi::QuickFix=sig -we '$prog' >/dev/null 2>&1";
    ok( open( my $e, 'errors.err'), "$case(sig) open");
    like( <$e>, qr/^.*:\d+:$msg/, "$case(sig) message");
}
}}

BEGIN { $n_tests += 7 }
{{
# do we get the obligatory warning?
unlink 'errors.err';
system qq(perl -Ilib -MVi::QuickFix -we 'warn "abc"' >/dev/null 2>&1);
ok( open( my $e, 'errors.err'), "obligatory message open");
my $last;
$last = $_ while <$e>;
like( $last, qr/QuickFix.*ended/, "obligatory message found");

# does silent mode work?
unlink 'errors.err';
system qq(perl -Ilib -MVi::QuickFix=silent -we 'warn "abc"' >/dev/null 2>&1);
ok( open( $e, 'errors.err'), "silent mode open");
$last = $_ while <$e>;
unlike( $last, qr/Vi::QuickFix/, "silent mode message not found");

# do we not get it in exec mode?
unlink 'errors.err';
system 'perl lib/Vi/QuickFix.pm </dev/null >/dev/null 2>&1';
ok( not( -e 'errors.err'), "no message in exec mode");

# is an empty error file removed (needs silent mode)?
system "perl -Ilib -MVi::QuickFix -we ';' >/dev/null 2>&1"; # create error file
ok( -e 'errors.err', "Error file exists");
system( "perl -Ilib -MVi::QuickFix=silent -we';'");
ok( not( -e 'errors.err'), "Empty error file erased");
}}

# error behavior
BEGIN { $n_tests += 5 }
{{
# unable to create error file
require Vi::QuickFix;
eval { Vi::QuickFix->import( 'gibsnich/wirdnix') };
like( $@, qr/Can't create error file/, "Died without error file");

SKIP: {
    skip "Can't be tested with perl $]", 3 if LOW_VERSION;

    # refuse to re-tie STDERR
    require Tie::Handle;
    tie *STDERR, 'Tie::StdHandle', '>&STDERR';
    require Vi::QuickFix;
    eval { Vi::QuickFix->import( 'tie') };
    like( $@, qr/STDERR already tied/, "Refused to re-tie");
    untie *STDERR;

    # accept second use (no action then)
    Vi::QuickFix->import( 'silent');
    ok( tied *STDERR, 'Second use: STDERR is tied');
    eval { Vi::QuickFix->import };
    like( $@, qr/^$/, 'Second use no error');
    untie *STDERR;
}

# reject "tie" mode on low version
SKIP: {
    skip "irrelevant with perl $]", 1 unless LOW_VERSION;

    # make silent, so test doesn't warn
    eval { Vi::QuickFix->import( 'tie', 'silent') };
    like( $@, qr/^Cannot use 'tie'/, 'Reject tie mode');
}

}}

BEGIN { plan tests => $n_tests }

#####################################################################

sub  run_tests {
    my ( $call, $errf, $command) = @_;
    my $errfile = ERRFILE->{ $errf};
    $command =~ s/\*ERRFILE\*/$errfile/g;
    unlink $errfile;
    system( $command);
#   don't forget PER_CALL when uncommenting
#   ok( -s $errfile, "$call $errf size");
    ok( open( my $e, $errfile), "$call $errf open");
    my $i;
    for ( ERR_TXT ) {
        $i ++;
        like( scalar <$e>, qr/^(.*?):\d+:$_$/, "$call $errf $i");
    }
    unlink $errfile;
}
