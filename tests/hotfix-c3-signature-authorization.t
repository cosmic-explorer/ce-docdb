use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($SignatureID,$EmailUserID,$Action,$dbh,%Signatures,@ErrorStack);
sub FetchSignature {} sub EndPage { die "denied\n" if @ErrorStack }
my $block=source_between('SignRevision','# Check Signature Status','#print "<b>You have');
for my $case ([7,7,'sign',1],[7,9,'sign',0],[0,0,'sign',0],[7,7,'invalid',0]) {
    my ($owner,$caller,$action,$allowed)=@$case;
    $SignatureID=12; $EmailUserID=$caller; $Action=$action;
    %Signatures=(12=>{EmailUserID=>$owner,Signed=>0}); @ErrorStack=();
    push @ErrorStack,'invalid user' unless $caller; # preceding identity check
    $dbh=HotfixTest::DB->new;
    my $ok=eval { run_source($block); 1 };
    is(!!$ok,!!$allowed,'invalid users, other signers and actions are rejected');
    is(scalar @{$dbh->{executions}},$allowed,'only the designated signer reaches UPDATE');
}

done_testing;
