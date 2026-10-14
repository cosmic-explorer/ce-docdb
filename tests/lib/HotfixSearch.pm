package main;
use HotfixTest;
stub_modules(qw(FSUtilities.pm WebUtilities.pm Utilities.pm ResponseElements.pm
    Security.pm XMLOutput.pm SearchAtoms.pm AuthorSQL.pm DocumentSQL.pm
    MeetingSQL.pm MiscSQL.pm RevisionSQL.pm SecuritySQL.pm TopicSQL.pm
    DocumentHTML.pm DocumentUtilities.pm));
sub GetTopics {} sub GetSecurityGroups {} sub NewXMLOutput {} sub AddSearchWeights {}
sub Unique { my %seen; grep { !$seen{$_}++ } @_ }
sub EndPage { die "request rejected\n" if @ErrorStack }
sub DateToSQL { return join('-', @_) }
sub LastDayInMonth { return 31 }
sub CanAccessRevision { return 1 }
load_sub('SearchAtoms.pm', 'TextSearch');
load_sub('SearchAtoms.pm', 'IDSearch');
load_sub('Search.pm', 'LocalSearch');
$TRUE = 1; $FALSE = 0;
%ReverseAbrvMonth = (Jan => 1, Dec => 12);
sub test_search {
    my (%params) = @_;
    @ErrorStack = (); @WarnStack = (); $dbh = HotfixTest::DB->new;
    $SQLBegin = ''; $SQLEnd = '';
    LocalSearch({ -cgiparams => { outformat => 'XML', %params }, -noxmlhead => 1 });
    return $dbh;
}
1;
