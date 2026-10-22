# PHP removal (2026-10-22): the image must carry no PHP interpreter, module
# or PHP application, and Apache must not advertise component versions.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
my $df = source('./Dockerfile');
like($df, qr/rpm -e \$\(rpm -qa 'php72u\*' 'mod_php72u\*'\)/, 'Dockerfile removes the IUS PHP packages');
like($df, qr{rm -rf /usr1/www/html/mediawiki-1\.29\.1 /usr1/www/html/wiki}, 'Dockerfile removes MediaWiki');
like($df, qr{phpMyAdmin-2\.11\.9\.2 /usr1/www/html/phpMyAdmin-4\.0\.10\.20-english}, 'Dockerfile removes both phpMyAdmin trees');
like($df, qr{/usr1/www/html/php___myadmin}, 'Dockerfile removes the symlink from the web root into /usr1/www');
like($df, qr{! test -e /usr/bin/php && ! test -e /usr/lib64/httpd/modules/libphp7\.so}, 'build fails if PHP survives');
ok(! -e "$HotfixTest::root/etc/httpd/conf.d/php.conf", 'php.conf no longer shipped');
ok(! -e "$HotfixTest::root/etc/httpd/conf.modules.d/15-php.conf", '15-php.conf no longer shipped');
unlike(source('etc/httpd/conf.d/dcc-dev.conf'), qr/index\.php/, 'DirectoryIndex no longer tries index.php');
my $hc = source('etc/httpd/conf/httpd.conf');
like($hc, qr/^ServerTokens Prod$/m, 'ServerTokens Prod');
like($hc, qr/^ServerSignature Off$/m, 'ServerSignature Off');
done_testing;
