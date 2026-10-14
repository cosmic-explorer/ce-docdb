use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

ok(!-e "$HotfixTest::root/usr1/www/cgi-bin/private/DocDB/MigrationHelper",'bulk-publishing migration endpoint absent from source');

done_testing;
