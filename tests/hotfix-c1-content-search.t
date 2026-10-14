use strict;
use warnings;
use Test::More;
use File::Temp 'tempdir';
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;
require HotfixSearch;
our ($ContentSearch, $ContentSearchReturns);
my $dir = tempdir(CLEANUP => 1);
$ContentSearch = "$dir/search wrapper";
$ContentSearchReturns = 'no-results';
open my $script, '>', $ContentSearch or die $!;
print $script "#!$^X\n", 'open my $fh, ">", $ENV{TEST_SEARCH_ARGS} or die $!; print $fh join("\n", @ARGV);', "\n";
close $script; chmod 0700, $ContentSearch;
local $ENV{TEST_SEARCH_ARGS} = "$dir/args";
for my $mode ('allword', 'anyword', 'allsub', 'anysub', 'invalid mode', "allword\n") {
    test_search(filecontsearch => 'two words', filecontsearchmode => $mode);
    open my $args, '<', "$dir/args" or die $!;
    local $/; my $seen = <$args>;
    my $expected = $mode =~ /\A(?:allword|anyword|allsub|anysub)\z/ ? $mode : 'anysub';
    is($seen, "two words\n$expected", 'wrapper receives exactly two arguments and an allowed mode');
}
done_testing;
