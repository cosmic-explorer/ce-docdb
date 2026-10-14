use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($Mode,$DocRevID,$DocumentID,$Version,$QACheck,$query,$dbh,$admin,$certifier,$access);
our (@ErrorStack,@changes,%DocRevisions);
sub CanAdminister { $admin } sub CanCertify { $certifier } sub CanAccess { $access }
sub FetchDocRevisionByID {} sub bailOutOfShowDocument { die "denied\n" }
sub UpdateRevisionQAState { push @changes, ['qa',@_] }
sub UpdateRevisionPublicSecurity { push @changes, ['public',@_] }
{ package DBI; sub connect { return bless {}, 'TestQuery' } }
{ package TestQuery; sub delete {} }
$query=bless {}, 'TestQuery'; $Mode='qacheck'; $DocumentID=7; $Version=2;
my $block=source_between('ShowDocument',"if (\$Mode eq 'qacheck')",'my $DocumentNumber');
for my $case ([0,0,1,31,0,0], [1,0,0,31,0,0], [1,0,1,0,0,0], [1,0,1,31,0,1], [0,1,1,31,1,1]) {
    ($admin,$certifier,$access,$DocRevID,my $stored,my $allowed)=@$case;
    $QACheck=1-$stored; $DocRevisions{$DocRevID}{QAcheck}=$stored; @changes=(); @ErrorStack=();
    my $ok=eval { run_source($block); 1 };
    is(!!$ok,!!$allowed,'role, visibility and revision presence gate mutation');
    if ($allowed) { is_deeply(\@changes,[['qa',$DocRevID,1-$stored],['public',7,2,1-$stored]],'toggle derives from stored state, not qastat'); }
    else { is(scalar @changes,0,'denied request makes no state changes') }
}

done_testing;
