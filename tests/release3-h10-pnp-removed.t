# H10: the P&P review hook (ProcessPNPReview + button) is gone and the image
# build deletes the base-layer copy of the script.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
ok(! -e "$HotfixTest::root/usr1/www/cgi-bin/private/DocDB/ProcessPNPReview", 'ProcessPNPReview removed from the tree');
for my $f (qw(RevisionHTML.pm FormElements.pm ProjectGlobals.pm DocDBGlobals.pm SiteConfig.pm)) {
  my $src = source($f);
  unlike($src, qr/ReviewButton|PNPReview|pnp_host_name|NCat|InitiatePnP|GotoPnPSite/, "$f has no P&P hook references");
}
like(source('./Dockerfile'), qr{RUN rm -f[^\n]*(\\\n[^\n]*)*ProcessPNPReview}, 'Dockerfile deletes the base-layer ProcessPNPReview');
# The read-only status display of past reviews is intentionally kept.
like(source('FileHTML.pm'), qr/sub PnPLink/, 'read-only P&P status display kept');
done_testing;
