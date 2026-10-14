use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;
require HotfixSearch;
our $ContentSearch = '';
sub ValidateRevisions { return @_ }
for my $mode (qw(anysub allsub anyword allword)) {
    my $input = q{O"Brien\_100%};
    my $db = test_search(titlesearch=>$input,titlesearchmode=>$mode,
                        filesearch=>$input,filesearchmode=>$mode);
    is(scalar @{$db->{executions}},2,'revision and filename query executed');
    for my $execution (@{$db->{executions}}) {
        like($execution->[0],qr/(?:like|REGEXP) \?/,'text represented by placeholder');
        unlike($execution->[0],qr/Brien|100/,'user text cannot change SQL syntax');
        like($execution->[1],qr/brien/,'search term reaches driver as bound data');
    }
}
my @values;
is(TextSearch('DocumentTitle','allsub','100% _x',\@values),'(LOWER(DocumentTitle) like ? AND LOWER(DocumentTitle) like ?)','word structure preserved');
is_deeply(\@values,['%100\\%%','%\\_x%'],'literal LIKE percent and underscore escaped in bound values');
# Simple search fans out to author, type and event lookups before text atoms.
# Exercise those real helpers as well, including the historical no-groups path.
load_sub('AuthorSQL.pm',$_) for qw(MatchAuthor MatchAuthor_NoGroups);
load_sub('MiscSQL.pm','MatchDocType');
load_sub('MeetingSQL.pm','MatchEvent');
for my $groups (0,1) {
    my $db=test_search(simpletext=>q{O"Brien_%},includeauthorgrps=>$groups);
    is(scalar @{$db->{executions}},6,'simple search reaches all six query families');
    for my $execution (@{$db->{executions}}) {
        unlike($execution->[0],qr/brien/i,'simple search value absent from every SQL statement');
        like($execution->[1],qr/brien/i,'simple search value passed through a binding');
        like($execution->[1],qr/\\_\\%/,'literal wildcard characters preserved in every LIKE query');
    }
}
done_testing;
