use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

use CGI; use HTML::Entities;
stub_modules(qw(FSUtilities.pm FileUtilities.pm DocumentSQL.pm));
sub GetURLDir {'/files/'} sub FileSize {' 1 KB'} sub FullFile {''}
load_sub('FileHTML.pm','FileLink');
my $name=q{file" <name>.txt}; my $desc=q{A <b>file</b> & "quote"};
for my $format (qw(short long)) {
    for my $description ('',$desc) {
        my $link=FileLink({-shortname=>$name,-description=>$description,-format=>$format,-maxlength=>0});
        unlike($link,qr/<name>|<b>/,'file metadata cannot add HTML elements');
        like($link,qr/title="\Q@{[HTML::Entities::encode($name)]}\E"/,'filename attribute encoded');
        like($link,qr/\Q@{[CGI::escape($name)]}\E/,'download URL retains encoded filename');
    }
}

done_testing;
