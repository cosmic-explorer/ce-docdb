use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($Alias,@ErrorStack); sub EndPage { die "invalid alias\n" }
my $block=source_between('ProcessDocumentAdd','# Change lower case to upper.','$ExistingDocID = GetDocumentIDByAlias');
for my $value ('T123456','t12345678','T12345','T123456789','T123456/other',"T123456\n") {
    $Alias=$value; @ErrorStack=(); my $ok=eval {run_source($block);1};
    my $valid=$value =~ /\A[Tt][0-9]{6,8}\z/;
    is(!!$ok,!!$valid,'only the documented alias grammar is accepted');
    is($Alias,uc $value,'lower-case prefix normalized');
}
my $aliasblock=source_between('DocumentSQL.pm','  if ($DocAlias) {','  unless ($DateTime)');
is(run_source('my $DocAlias="T123456"; my ($DocNextNumber,$DocNumberStr);'.$aliasblock.'$DocNumberStr;'),'T123456','alias stored verbatim');
unlike($aliasblock,qr/sprintf/,'alias cannot be interpreted as a format string');

done_testing;
