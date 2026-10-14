#!/usr/bin/env perl
# Real selector and CGI action blocks, inert CGI/database boundaries.
use Test::More;
use FindBin;
use File::Spec;
my $Root = $ENV{DOCDB_TEST_ROOT} || File::Spec->rel2abs("$FindBin::Bin/..");
my $Code = "$Root/usr1/www/cgi-bin/private/DocDB";
sub EndPage { die "REJECTED\n" if @ErrorStack; }
sub FormElementTitle { return ''; }
do "$Code/DocTypeHTML.pm" or die $@ || $!;
sub read_source { open my $fh,'<',"$Code/$_[0]" or die $!; local $/; return <$fh>; }
{
  package FakeDB;
  sub prepare { my ($self,$sql)=@_; bless {db=>$self,sql=>$sql},'FakeStatement'; }
  package FakeStatement;
  sub execute { my ($self,@bind)=@_; push @{$self->{db}{writes}},[$self->{sql},@bind]; return 1; }
}
{
  package FakeCGI;
  sub scrolling_list { my ($self,%arg)=@_; $self->{last}=\%arg; return ''; }
}
$query=bless {},'FakeCGI';
%DocumentTypes=(7=>{SHORT=>'T',LONG=>'Technical notes'},3=>{SHORT=>'P',LONG=>'Publications'});
DocTypeSelect({-disabled=>1});
my $widget=$query->{last};
is_deeply($widget->{-values},[3,7],'full selector submits numeric IDs in label order');
is($widget->{-labels}{7},'T [Technical notes]','full label stays readable');
is($widget->{-disabled},'disabled','administration widget starts disabled');
DocTypeSelect({-multiple=>1,-format=>'short'});
is_deeply($query->{last}{-values},[3,7],'custom-list multi-select also submits IDs');
is($query->{last}{-labels}{7},'T','short labels preserved');
is($query->{last}{-multiple},1,'multiple selection preserved');
my $type_source=read_source('DocTypeAdminister');
my ($param_line)=$type_source =~ /(my \$DocTypeID = \$params\{doctype\};)/;
$start=index($type_source,'if      ($Action eq "Delete")');
$end=index($type_source,'# For modify or new fetch institution');
die 'Type action block not found' if !$param_line || $start<0 || $end<0;
my $type_block=$param_line."\n".substr($type_source,$start,$end-$start);
for my $Action ('Modify','Delete') {
  %params=(doctype=>$widget->{-values}[1]);
  my $ShortName='N'; my $LongName='';
  @ErrorStack=(); @ActionStack=();
  $dbh=bless {writes=>[]},'FakeDB';
  eval $type_block;
  is($@,'',"$Action action accepts selected ID");
  is($dbh->{writes}[0][-1],7,"$Action statement binds selected numeric ID");
}
done_testing();
