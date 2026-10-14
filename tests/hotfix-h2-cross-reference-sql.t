use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($dbh,$ShortProject); $dbh=HotfixTest::DB->new; $ShortProject='CE';
stub_modules(qw(DocumentSQL.pm RevisionSQL.pm));
load_sub('XRefSQL.pm','InsertXRefs');
InsertXRefs(-docrevid=>8,-documents=>['Project"Name-123']);
my @project=grep { $_->[0] =~ /set Project/ } @{$dbh->{executions}};
is_deeply(\@project,[['update DocXRef set Project=? where DocXRefID=?','Project"Name',41]],'project and row id are separate bound values');

done_testing;
