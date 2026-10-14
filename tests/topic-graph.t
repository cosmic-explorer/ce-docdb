#!/usr/bin/env perl
# Offline tests: real topic/selector routines, fake HTML and database boundaries.
use Test::More;
use Time::HiRes qw(alarm);
use FindBin;
use File::Spec;
my $Root = $ENV{DOCDB_TEST_ROOT} || File::Spec->rel2abs("$FindBin::Bin/..");
my $Code = "$Root/usr1/www/cgi-bin/private/DocDB";
$TRUE=1; $FALSE=0;
$INC{'TopicSQL.pm'}=1;
$INC{'Utilities.pm'}=1;
$INC{'MeetingSQL.pm'}=1;
$INC{'MeetingHTML.pm'}=1;
sub GetTopics {}
sub Unique { my %seen; return grep { !$seen{$_}++ } @_; }
sub EndPage { die "REJECTED\n" if @ErrorStack; }
for my $module ('TopicUtilities.pm','TopicHTML.pm') {
  do "$Code/$module" or die "$module: ".($@ || $!);
}
{
  no warnings 'redefine';
  *TopicLink = sub { return "topic-".$_[0]{-topicid}; };
  *FormElementTitle = sub { return ''; };
}
sub bounded (&) {
  my ($code)=@_;
  local $SIG{ALRM}=sub { die "Traversal did not terminate\n"; };
  my ($ok,$error);
  eval { alarm(0.05); $code->(); alarm(0); $ok=1; };
  $error=$@; alarm(0);
  ok($ok,'traversal terminates') or diag($error);
}
sub graph {
  %Topics=map { $_=>{Short=>"T$_"} } 1..5;
  %TopicChildren=(1=>[2,3],2=>[4],3=>[4]);
  %TopicParents=(2=>[1],3=>[1],4=>[2,3]);
}
graph();
is_deeply([TopicAndSubTopics({-topicid=>1})],[1,2,4,3],'diamond descendants visited once');
BuildTopicProvenance();
is_deeply($TopicProvenance{4},[4,3,1],'ordered legacy last-parent provenance retained');
my $html=TopicListWithChildren({-topicids=>[1]});
is(scalar(()=$html =~ /topic-4/g),2,'shared leaf appears under both parents');
$TopicChildren{4}=[1]; $TopicParents{1}=[4];
bounded { BuildTopicProvenance(); };
is_deeply($TopicProvenance{4},[4,3,1],'cycle stops before repeated topic');
bounded { is_deeply([sort {$a<=>$b} TopicAndSubTopics({-topicid=>1})],[1,2,3,4],'cyclic descendant set complete'); };
bounded { $html=TopicListWithChildren({-topicids=>[1]}); };
is(scalar(()=$html =~ /topic-1/g),1,'render omits back edge');
is(scalar(()=$html =~ /topic-4/g),2,'cycle guard retains both diamond branches');
%TopicChildren=(1=>[1]); %TopicParents=(1=>[1]);
bounded { BuildTopicProvenance(); TopicAndSubTopics({-topicid=>1}); TopicListWithChildren({-topicids=>[1]}); };
is_deeply($TopicProvenance{1},[1],'self cycle provenance bounded');
# Extract the real CGI action block so ordering of validation versus name/hierarchy
# writes is tested too, without loading site credentials or CGI startup code.
sub read_source { open my $fh,'<',"$Code/$_[0]" or die $!; local $/; return <$fh>; }
my $admin=read_source('TopicAdminister');
my $start=index($admin,"GetTopics();\n");
my $end=index($admin,'} elsif ($Action eq "New")',$start);
die 'Topic action block not found' if $start<0 || $end<0;
my $action_block=substr($admin,$start,$end-$start)."}\n";
{
  package FakeDB;
  sub prepare { my ($self,$sql)=@_; bless {db=>$self,sql=>$sql},'FakeStatement'; }
  package FakeStatement;
  sub execute { my ($self,@bind)=@_; push @{$self->{db}{writes}},[$self->{sql},@bind]; return 1; }
}
sub run_topic_action {
  my ($TopicID,$ParentTopicID)=@_;
  my $Action='Modify'; my $ShortName='renamed'; my $LongName='';
  @ErrorStack=(); @ActionStack=();
  $dbh=bless {writes=>[]},'FakeDB';
  eval $action_block;
  return ($@,$dbh->{writes});
}
graph();
for my $case ([1,1,'self'],[1,4,'descendant'],[1,3,'second branch'],[0,1,'missing topic'],[1,99,'missing parent']) {
  my ($error,$writes)=run_topic_action(@$case[0,1]);
  like($error,qr/REJECTED/,"$case->[2] rejected by CGI");
  is(scalar @$writes,0,"$case->[2] rejected before ALL writes including rename");
}
my ($error,$writes)=run_topic_action(2,3);
is($error,'','acyclic cross-branch reparent accepted');
is_deeply([map {$_->[0]} @$writes],[
  'update Topic set ShortDescription=? where TopicID=?',
  'delete from TopicHierarchy where TopicID=?',
  'insert into TopicHierarchy (TopicHierarchyID,TopicID,ParentTopicID) values (0,?,?)'
],'valid request retains existing modification behavior');
($error,$writes)=run_topic_action(2,0);
is($error,'','omitted parent allows name-only edit');
is(scalar @$writes,1,'name-only edit leaves parent edges alone');
done_testing();
