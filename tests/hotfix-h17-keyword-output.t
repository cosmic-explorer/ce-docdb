use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

use CGI; use HTML::Entities;
our ($Search,%Keywords); $Search='/Search';
stub_modules(qw(KeywordSQL.pm)); sub FetchKeyword {}
load_sub('KeywordHTML.pm',$_) for qw(KeywordLink KeywordLinkByID JSAttrEscape);
my $keyword=q{A ' " & <keyword>}; $Keywords{1}={Short=>$keyword,Long=>$keyword};
for my $link (KeywordLink($keyword),KeywordLinkByID(1,-format=>'short'),KeywordLinkByID(1,-format=>'long')) {
    like($link,qr/\Q@{[CGI::escape($keyword)]}\E/,'keyword URL-encoded in query value');
    like($link,qr/\Q@{[HTML::Entities::encode($keyword)]}\E/,'keyword HTML-encoded as link text');
    unlike($link,qr/<keyword>/,'keyword cannot introduce markup');
}
is(HTML::Entities::decode(JSAttrEscape("a'b\\c\n")),"a\\'b\\\\c ",'chooser protects both JavaScript and HTML attribute contexts');

done_testing;
