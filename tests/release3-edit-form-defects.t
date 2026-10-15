# Reliability findings D02, D05, D06, D07, D08, D09, MT03 and three L19
# defects in the add/edit path.
use strict; use warnings; use Test::More; use File::Temp qw(tempdir);
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
no strict 'vars'; no warnings;
# --- D02: ProcessUpload is atomic and never reports a failed/empty upload as success
sub FileNameSanityCheck { return "" }
load_sub('FSUtilities.pm', 'ProcessUpload');
my $dir = tempdir(CLEANUP => 1);
# Upload handles stringify to the client file name (CGI.pm's Fh does this),
# and basename() is applied to that string; mimic it with an overloaded glob.
{ package FakeFh; use overload '""' => sub { ${*{$_[0]}}{name} }, fallback => 1; }
sub make_handle { my ($name,$data) = @_; my $fh = \do { local *FH }; open($fh, '<', \$data) or die; ${*$fh}{name} = $name; return bless $fh, 'FakeFh'; }
my $fh = make_handle('report.txt', 'payload bytes'); @ErrorStack = ();
is(ProcessUpload($dir, $fh), 'report.txt', 'successful upload returns the short name');
is(do { local $/; open my $r,'<',"$dir/report.txt"; <$r> }, 'payload bytes', 'bytes written');
ok(!@ErrorStack, 'no errors on success');
my $empty = make_handle('empty.txt', ''); @ErrorStack = ();
is(ProcessUpload($dir, $empty), '', 'empty upload is not a success');
ok(!-e "$dir/empty.txt", 'nothing stored for an empty upload');
like($ErrorStack[0], qr/blank/, 'empty upload reported as an error');
open(my $w,'>',"$dir/keep.txt"); print $w "old contents"; close $w;
my $closed = make_handle('keep.txt', 'new'); close($closed); @ErrorStack = ();
is(ProcessUpload($dir, $closed), '', 'read failure is not a success');
is(do { local $/; open my $r,'<',"$dir/keep.txt"; <$r> }, 'old contents', 'existing file untouched after a failed upload');
ok(!glob("$dir/.upload-*"), 'temporary file cleaned up');
# --- D06: duplicate names detected before writing
%DocFiles = (); stub_modules('MiscSQL.pm');
sub FetchFile { my %n = (31 => 'slides.pdf', 32 => 'notes.txt'); $n{$_[0]} }
load_sub('FileUtilities.pm', 'DuplicateFileNames');
is_deeply([DuplicateFileNames({1 => {File => 'C:\\Users\\x\\slides.pdf'}, 2 => {CopyFileID => 31}})], ['slides.pdf'], 'upload colliding with a copied file');
is_deeply([DuplicateFileNames({1 => {File => '/tmp/a/x.pdf'}, 2 => {File => '/tmp/b/x.pdf'}, 3 => {File => 'x.pdf'}})], ['x.pdf'], 'same basename reported once');
is_deeply([DuplicateFileNames({1 => {File => 'a.pdf'}, 2 => {URL => 'http://h/b.pdf'}, 3 => {FileID => 32}})], [], 'distinct names pass');
like(source('ProcessDocumentAdd'), qr/DuplicateFileNames\(\\%Files\)/, 'ProcessDocumentAdd checks before any write');
# --- D09: "new" behaves like "bump"
$dbh = HotfixTest::DB->new; $TRUE = 1; $FALSE = 0;
%Documents = (0 => {NVersions => 0}, 5 => {NVersions => 2});
sub FetchDocument { 1 }
load_sub('RevisionSQL.pm', 'InsertRevision');
InsertRevision(-docid => 5, -version => 'new', -title => 't');
my @binds = map { @$_ } @{$dbh->{executions}};
ok(!grep({ defined && $_ eq 'new' } @binds), 'the word new is never bound');
ok(!grep({ $_->[0] =~ /Obsolete=1/ } @{$dbh->{executions}}), 'a new revision obsoletes nothing');
ok(grep({ grep { defined && $_ eq 3 } @$_ } @{$dbh->{executions}}), 'version is NVersions+1');
# --- D05: UpdateDBButton falls back to the revision's QA state
stub_modules('RevisionSQL.pm');
sub FetchRevisionByDocumentAndVersion { 9 } sub FetchDocRevisionByID {}
%DocRevisions = (9 => {QAcheck => 1});
{ package Q; sub new { bless {}, shift } sub param {} sub startform {''} sub hidden { my ($s,%a)=@_; qq(<input type="hidden" name="$a{-name}" value="$a{-default}">) } sub submit {''} sub endform {''} }
$query = Q->new; $DocumentAddForm = 'DocumentAddForm';
load_sub('FormElements.pm', 'UpdateDBButton');
like(capture_output { UpdateDBButton(5, 2, undef) }, qr/name="qastat" value="1"/, 'certified state carried when caller passes nothing');
like(capture_output { UpdateDBButton(5, 2, 0) }, qr/name="qastat" value="0"/, 'explicit state respected');
# --- static checks
like(source('DocumentAddForm'), qr/\$Mode eq "add" \|\| !\$DocTypeIDDefault/, 'D07: type selector offered on direct Add');
unlike(source('DocumentAddForm'), qr/my \$Overdate = '';/, 'D08: date override no longer hidden by a lexical');
like(source('MeetingHTML.pm'), qr/name=\\"sessionaltlocation\\" value=\\"\\"/, 'MT03: break rows keep the alternate-location list aligned');
like(source('TalkHintUtilities.pm'), qr/s\/\[\^\\w\\s\]\/\/g/, 'L19: fuzzy match keeps spaces');
like(source('SignoffUtilities.pm'), qr/if \(\$Status eq "Approved"\) \{\s*#/, 'L19: last approved revision uses $Status');
like(source('DisplayMeeting'), qr/\$DisplayMode eq "Event"\)/, 'L19: event display mode compares with a string');
done_testing;
