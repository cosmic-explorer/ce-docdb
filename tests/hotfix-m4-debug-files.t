use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

my $access=source('RemoteUserHasAccess');
unlike($access,qr{/tmp/(?:debug|errlog\.log)},'download authorization no longer opens shared debug files');
unlike($access,qr/keys %ENV/,'download authorization no longer dumps request environment');
my $mail=source_between('Utilities.pm','sub send_email {','sub getUniqueID');
unlike($mail,qr{/tmp/log\.dat},'active mail routine no longer writes shared recipient log');
unlike(source('SignoffHTML.pm'),qr{/tmp/debug\.mca},'signoff rendering no longer opens shared debug file');

done_testing;
