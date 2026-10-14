use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our (%params,%DocRevisions,$Mode,$documentID,$version,$admin,$certifier,$dbh,$DocRevID,$ResetState);
sub FetchRevisionByDocumentAndVersion { 41 } sub FetchDocRevisionByID {}
sub CanAdminister {$admin} sub CanCertify {$certifier}
my ($init)=source('ProcessDocumentAdd') =~ /^(my \$QAState[^\n]+)/m;
my $policy=source_between('ProcessDocumentAdd','if ($Mode eq "updatedb") { # New Document revision','### Add entry to Document Revision');
my $save=source_between('ProcessDocumentAdd','if ($Mode eq "updatedb" && $ResetState == 0)', '### Add reference');
$Mode='updatedb'; $documentID=8; $version=2; $DocRevID=42; $ResetState=0;
for my $case ([0,0,1,'0',1],[0,0,0,'1',0],[1,0,0,'1',1],[0,1,1,'invalid',0]) {
    ($admin,$certifier,my $stored,my $form,my $expected)=@$case;
    %params=(qastat=>$form); $DocRevisions{41}{QAcheck}=$stored; $dbh=HotfixTest::DB->new;
    run_source($init."\n".$policy.$save);
    my @update=grep {$_->[0] =~ /set QAcheck/} @{$dbh->{executions}};
    is_deeply(\@update,[['update DocumentRevision set QAcheck=? where DocRevID=?',$expected,42]],'non-certifier preserves database QA; certifier input is boolean and bound');
}

done_testing;
