# L26: LIGO-specific strings left in the Cosmic Explorer instance.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
no strict 'vars'; no warnings;
$ShortProject = 'CE'; $ShowDocument = 'https://dcc.cosmicexplorer.org/cgi-bin/private/DocDB/ShowDocument';
sub SafeHTML { $_[0] }
for my $copy ('Utilities.pm', 'usr1/www/cgi-bin/DocDB/Utilities.pm') {
  run_source(source_between($copy, 'sub URLify {', "\n}\n") . "\n}\n");
  my $out = URLify("See CE-G2600067-v1 and T2500001 today");
  like($out, qr{href="\Q$ShowDocument\E\?docid=G2600067-v1">CE-G2600067-v1</a>}, "$copy: prefixed number links to ShowDocument");
  like($out, qr{href="\Q$ShowDocument\E\?docid=T2500001">T2500001</a>}, "$copy: bare number links to ShowDocument");
  unlike($out, qr/ligo\.org/, "$copy: no LIGO host in generated links");
  unlike(source($copy), qr/Sys::Hostname|\.ligo\.org'/, "$copy: hostname-based LIGO URL removed");
}
for my $f (qw(AuthorHTML.pm SignoffHTML.pm)) {
  my $s = source($f);
  unlike($s, qr/DCC document LIGO/, "$f mail subjects no longer say LIGO");
  like($s, qr/DCC document \$ShortProject/, "$f mail subjects use the configured project");
}
unlike(source('ListBy'), qr/America\/Los_Angeles/, 'ListBy no longer forces the Los Angeles time zone');
unlike(source('GeneralInstructions.pm'), qr/btev\.fnal\.gov|BTeV-doc/, 'Fermilab/BTeV document link removed from the instructions');
unlike(source('ListGroups'), qr/dcc\.ligo\.org/, 'ListGroups help link points at this instance');
done_testing;
