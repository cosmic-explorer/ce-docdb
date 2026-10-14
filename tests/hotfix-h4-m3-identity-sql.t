use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($dbh,$GLOBAL_EMAILUSER,$identity); stub_modules('Utilities.pm');
sub remote_user { $identity }
load_sub('SecuritySQL.pm',$_) for qw(FetchEmailUserIDFromEmailAddress FetchEmailUserIDFromRemoteUser FetchEmailUserIDFromRemoteUserName);
$identity='user_%"@example.test'; $GLOBAL_EMAILUSER=0;
for my $call (sub { FetchEmailUserIDFromEmailAddress($identity) },sub { FetchEmailUserIDFromRemoteUser() },sub { FetchEmailUserIDFromRemoteUserName($identity) }) {
    $dbh=HotfixTest::DB->new; is($call->(),23,'lookup returns matched identity');
    like($dbh->{queries}[0],qr/ = \?/,'identity comparison uses equality placeholder');
    unlike($dbh->{queries}[0],qr/like/i,'identity wildcard characters cannot broaden match');
    is($dbh->{executions}[0][1],$identity,'identity bound literally');
}

done_testing;
