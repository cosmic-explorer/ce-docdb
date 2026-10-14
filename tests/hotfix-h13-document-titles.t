use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

use HTML::Entities;
stub_modules(qw(DocumentSQL.pm RevisionSQL.pm ResponseElements.pm Security.pm));
our (%Documents,%DocRevisions,$UseSignoffs,$UseAliasAsFileName);
sub FetchDocument {} sub FetchRevisionByDocumentAndVersion {31} sub FullDocumentID {'T000007'} sub CanAccess {1}
load_sub('ResponseElements.pm','PrintTitle'); load_sub('HTMLUtilities.pm','DocDBHeader'); load_sub('DocumentHTML.pm','DocumentLink');
my $title=q{A <b>"quoted" & title</b>}; my $encoded=HTML::Entities::encode($title);
is(capture_output {PrintTitle($title)},"<h1>$encoded</h1>\n",'page heading encodes markup');
my $header=capture_output {DocDBHeader($title,'',-scripts=>[],-nobody=>1)};
like($header,qr/\Q<title>$encoded<\/title>\E/,'HTML title encodes markup');
$Documents{7}{NVersions}=1; $DocRevisions{31}{Title}=$title;
my $link=DocumentLink(-docid=>7,-titlelink=>1,-noapprovalstatus=>1);
like($link,qr/\Q$encoded\E/,'document table title link encodes markup');
unlike($link,qr/<b>/,'stored markup is not an HTML element');

done_testing;
