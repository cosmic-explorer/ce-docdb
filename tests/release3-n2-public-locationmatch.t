# N2: the anonymous /public LocationMatch must only match public-document
# short URLs, never arbitrary paths that happen to contain "/public".
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
my %re;
for my $f ('etc/httpd/conf.d/dcc-dev.conf', 'etc/httpd/conf.d/short_urls.public.conf') {
  my ($pat) = source($f) =~ /<LocationMatch "([^"]*public[^"]*)">/ or die "no public LocationMatch in $f";
  $re{$f} = qr/$pat/;
  unlike($pat, qr/\(\.\+\)/, "$f: no unanchored (.+)");
}
my @allowed = qw(/CE-P2100003/public /ce-p2100003/public/ /P2100003/public /CE-P2100003-v7/public /CE-G2600067-v1/main/public /CE-P2100003/public/of=xml /1234/public /CE-P2100003/public/main);
my @denied  = qw(/wiki/index.php/public /DocDB/0001/publiczz.pdf /DocDB/0001/public/x.pdf /cgi-bin/private/DocDB/ShowDocument/public /public /x/CE-P2100003/public /CE-P2100003/publicity /CE-P2100003/Private/public);
for my $f (sort keys %re) {
  ok($_ =~ $re{$f}, "$f allows $_") for @allowed;
  ok($_ !~ $re{$f}, "$f denies $_") for @denied;
}
for my $f ('etc/httpd/conf.d/short_urls.public.conf', 'etc/httpd/conf.d/short_urls.private.conf') {
  like(source($f), qr/\|\\d\+\)/, "$f: numeric document pattern uses \\d+");
  unlike(source($f), qr/\|d\+\)/, "$f: '|d+' typo gone");
}
done_testing;
