use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our (%params,$DocumentID); $DocumentID=7;
sub FetchDocumentAlias { my ($id)=@_; return $id == 7 ? 'T000007' : 'T000008' }
my $block=source_between('SignRevision','# Only numeric identifiers','my $otherscript');
for my $version ('2','2" invalid',"2\n") {
    %params=(docid=>'7" invalid',version=>$version);
    my $script=run_source($block.'$magicscript;');
    my $expected=$version eq '2' ? 2 : 0;
    like($script,qr{T000007-v$expected"},'redirect substitutes only numeric version');
    unlike($script,qr/invalid/,'untrusted identifier text cannot enter JavaScript');
}

done_testing;
