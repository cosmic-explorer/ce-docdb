use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

require HotfixSearch;
our ($InnerLogic,$OuterLogic);
for my $logic ('OR','or','AND','invalid logic') {
    test_search(innerlogic=>$logic,outerlogic=>$logic,outformat=>'XML');
    my $expected=uc($logic) eq 'OR' ? 'OR' : 'AND';
    is($InnerLogic,$expected,'inner SQL operator allow-listed');
    is($OuterLogic,$expected,'XML output cannot bypass outer operator validation');
}

done_testing;
