use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

my $config=source('etc/httpd/conf.d/dcc-dev.conf');
my ($private)=$config =~ m{<Location "/cgi-bin/private/DocDB">(.*?)</Location>}s;
my ($public)=$config =~ m{<Location "/cgi-bin/DocDB">(.*?)</Location>}s;
like($private,qr/^\s*AcceptPathInfo Off\s*$/m,'private CGI rejects path info');
like($private,qr/^\s*Require shib-session\s*$/m,'private CGI declares session requirement');
like($private,qr/^\s*ShibRequestSetting requireSession true\s*$/m,'Shibboleth session requested');
like($public,qr/^\s*AcceptPathInfo Off\s*$/m,'public CGI rejects path info');
# Runtime Apache/Shibboleth section merging still requires a staging request.

done_testing;
