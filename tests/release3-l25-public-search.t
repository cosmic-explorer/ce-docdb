# L25: the public Search redirect must target this site's host, not LIGO's,
# and must URL-encode the query text.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
my $src = source('Search');
unlike($src, qr/dcc\.ligo\.org/, 'no hard-coded LIGO host left in Search');
run_source(source_between('Search', 'sub GoogleSearch {', "\n}\n") . "\n}\n");
{
  package FakeQuery; sub new { bless {}, shift }
  sub redirect { my ($self, %a) = @_; $main::Redirected = $a{-uri}; return "Status: 302\n" }
}
no strict 'vars';
$host_name = 'https://dcc.cosmicexplorer.org/';
$query = FakeQuery->new;
capture_output { GoogleSearch('black holes & "R&D" <b>') };
like($Redirected, qr{^https://www\.google\.com/search\?q=}, 'redirects to Google search');
like($Redirected, qr/site%3Adcc\.cosmicexplorer\.org/, 'scoped to the configured Cosmic Explorer host');
unlike($Redirected, qr/[ <>"]/, 'query text is URL-encoded');
like($Redirected, qr/black%20holes%20%26%20%22R%26D%22%20%3Cb%3E/, 'encoded text preserved verbatim');
$host_name = 'bogus';
capture_output { GoogleSearch('x') };
like($Redirected, qr/site%3Adcc\.cosmicexplorer\.org/, 'falls back to the production host when host_name is unparsable');
capture_output { GoogleSearch(undef) };
like($Redirected, qr/site%3Adcc\.cosmicexplorer\.org$/, 'undefined query handled');
done_testing;
