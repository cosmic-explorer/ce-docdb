use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

my ($declaration)=source('SiteConfig.pm') =~ /^(\@LocalUploadDirectories\s*=.*?;)/m;
my $count=run_source($declaration.'scalar @LocalUploadDirectories;');
is($count,0,'no local filesystem directory is authorized for XML imports');
my $xml=source('XMLUpload');
like($xml,qr/\@LocalUploadDirectories/,'XMLUpload still consults configured allow-list');

done_testing;
