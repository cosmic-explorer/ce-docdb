# L27 / C07 / C09: search weighting, group cookie, keyword deletion, topic
# table, footer, and ListBy filter retention / truncation.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
no strict 'vars'; no warnings;
# --- AddSearchWeights uses the Number weight for number matches
%SearchWeights = (Number => 4, Revision => 3, Topic => 3, Event => 3, EventGroup => 2, Author => 4, DocType => 2, File => 3, FileContent => 1);
%Documents = ();
load_sub('SearchAtoms.pm', 'AddSearchWeights');
AddSearchWeights({-numbers => [11], -revisions => [12]});
is($Documents{11}{Relevance}, 4, 'document-number match gets the Number weight');
is($Documents{12}{Relevance}, 3, 'revision match gets only the Revision weight');
# --- DeleteKeyword executes the grouping delete too
$dbh = HotfixTest::DB->new;
load_sub('KeywordSQL.pm', 'DeleteKeyword');
DeleteKeyword(5);
is(scalar(grep { $_->[0] =~ /KeywordGrouping/ } @{$dbh->{executions}}), 1, 'KeywordGrouping rows are deleted');
# --- static checks
like(source('SetGroups'), qr/\$params\{security\}/, 'SetGroups reads the security parameter that SelectGroups posts');
unlike(source('TopicHTML.pm'), qr/my %Lists = \(\);/, 'TopicsTable declares the hash it uses');
my $pr = source('ProjectRoutines.pm');
unlike($pr, qr/\$find = "14"/, 'admin group is no longer hard-coded as 14');
like($pr, qr/\$ShibLogout\\">Logout</, 'logout link is labelled Logout');
unlike($pr, qr/CanAdminister\(\)\) \{\s*print "<li><a href=\\"\$ShibLogout/, 'logout link not restricted to administrators');
my $lb = source('ListBy');
like($lb, qr/VersionNumber = \(SELECT MAX\(Latest\.VersionNumber\)/, 'latest=1 uses a correlated max per document');
like($lb, qr/DocTypeID=\? and DocumentRevision\.Obsolete=0/, 'type listing excludes obsolete revisions');
is(scalar(() = $lb =~ /push \@WarnStack,"The listing was cut off/g), 3, 'all three capped loops report truncation');
unlike($lb, qr/\$i = 0;\n\s*last;/, 'counter reset before last removed');
like($lb, qr/order by DocRevID desc/, 'recent-days list fetches newest first');
# --- ListByHiddenFilters carries everything except maxdocs/days
%params = (topicid => 7, maxdocs => 50, days => 30, eventid => 3, 'mode' => 'conference', x0filter => 1, 'bad key' => 1, empty => '');
load_sub('ListBy', 'ListByHiddenFilters');
my $hidden = ListByHiddenFilters();
like($hidden, qr/name="topicid" value="7"/, 'topic filter carried');
like($hidden, qr/name="eventid" value="3"/, 'event filter carried');
like($hidden, qr/name="mode" value="conference"/, 'mode carried');
unlike($hidden, qr/maxdocs|name="days"/, 'maxdocs and days left to the forms');
unlike($hidden, qr/bad key|name="empty"/, 'odd keys and empty values skipped');
done_testing;
