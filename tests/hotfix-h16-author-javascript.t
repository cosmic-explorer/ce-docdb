use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our %Authors; stub_modules(qw(AuthorSQL.pm Sorts.pm Cookies.pm)); sub GetAuthors {} sub GetPrefsCookie {} sub byLastName {0}
load_sub('AuthorHTML.pm','AuthorJSList');
$Authors{1}={ACTIVE=>1,Formal=>qq{A" \\ Name\n</script><b>}};
my $output=capture_output {AuthorJSList()};
like($output,qr/A\\" \\\\ Name /,'quotes, backslash and newline escaped');
unlike($output,qr{</script><b>},'name cannot close script element');
like($output,qr/\\x3c\/script\\x3e/,'script delimiter becomes JavaScript string data');

done_testing;
