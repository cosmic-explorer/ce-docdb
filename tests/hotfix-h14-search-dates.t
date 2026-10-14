use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

require HotfixSearch;
sub DaysInMonth {31}
for my $params ({afteryear=>'2026',aftermonth=>'Jan',afterday=>'7'},
                {beforeyear=>'2026',beforemonth=>'Dec',beforeday=>'12'},
                {afteryear=>'2026" bad',aftermonth=>'Jan',afterday=>'7'},
                {beforeyear=>'2026',beforemonth=>'Dec',beforeday=>'12" bad'},
                {afteryear=>"2026\n",aftermonth=>'Jan',afterday=>'7'}) {
    my $db=test_search(%$params);
    unlike(join('',@{$db->{queries}}),qr/bad|\n/,'invalid date characters never reach SQL');
}
my $db=test_search(afteryear=>'2026',aftermonth=>'Jan',afterday=>'7');
like($db->{queries}[0],qr/2026.*7/,'valid date still constrains search');

done_testing;
