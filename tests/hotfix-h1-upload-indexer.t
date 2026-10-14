use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

use File::Temp 'tempdir'; use File::Basename 'basename';
our (@ErrorStack,@WarnStack,@DebugStack,$IncrementalContentSearch);
load_sub('FSUtilities.pm','FileNameSanityCheck'); load_sub('FSUtilities.pm','ProcessUpload');
load_sub('FSUtilities.pm','RunIncrementalIndexer');
my $dir=tempdir(CLEANUP=>1); mkdir "$dir/out";
@ErrorStack=();
is(ProcessUpload("$dir/out",'bad;name.txt'),'','invalid upload rejected before opening stream');
ok(!-e "$dir/out/bad;name.txt",'invalid upload never written');
{ package Upload; use overload '""' => sub { ${*{$_[0]}}{path} }, fallback=>1; }
open my $input,'+>',"$dir/report.txt" or die $!; print $input 'document contents'; seek $input,0,0;
bless $input,'Upload'; ${*$input}{path}="$dir/report.txt";
is(ProcessUpload("$dir/out",$input),'report.txt','valid upload remains usable despite previous errors');
open my $out,'<',"$dir/out/report.txt" or die $!; is(do {local $/; <$out>},'document contents','valid bytes copied');
$IncrementalContentSearch="$dir/index wrapper";
open my $script,'>',$IncrementalContentSearch or die $!;
print $script "#!$^X\n", 'open my $f, ">", $ENV{TEST_INDEX_ARGS} or die $!; print $f join("\n", @ARGV);',"\n";
close $script; chmod 0700,$IncrementalContentSearch;
local $ENV{TEST_INDEX_ARGS}="$dir/args";
my $file="$dir/report with spaces.txt"; open my $target,'>',$file or die $!; close $target;
RunIncrementalIndexer($file); wait();
open my $args,'<',"$dir/args" or die $!; is(do {local $/; <$args>},$file,'indexer receives one literal path argument');

done_testing;
