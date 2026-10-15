# M2: CanModify compared the caller's EmailUser ID with Author IDs
# (Submitter, Requester). It must convert first, and never match on 0/undef.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
no strict 'vars'; no warnings;
stub_modules(qw(DocumentSQL.pm RevisionSQL.pm SecuritySQL.pm));
sub GetSecurityGroups {} sub CanCreate {1} sub CanAdminister {0} sub FetchDocument {}
sub FetchRevisionByDocumentAndVersion {77} sub FetchDocRevisionByID {}
sub CanAccess {0} sub FindUsersGroups {()} sub GetRevisionModifyGroups {(42)} sub isAuthorshipAccess {0} sub isEmailUserAnAuthor {0}
my %AuthorOf = (500 => 1000, 501 => 2000);         # EmailUserID => AuthorID
sub FetchAuthorIDFromEmailUserID { $AuthorOf{$_[0]} }
$Public = 0; $EnhancedSecurity = 1;
# A modify list exists (group 42, which the caller is not in) so that only the
# submitter/requester shortcuts can grant.
%Documents    = (1 => {NVersions => 1, Requester => 2000});
%DocRevisions = (77 => {Submitter => 1000});
load_sub('Security.pm', 'CanModify');
$EmailUserID = 500; ok(CanModify(1,1), 'submitter (by Author ID) can modify');
$EmailUserID = 501; ok(CanModify(1,1), 'requester (by Author ID) can modify');
$EmailUserID = 1000; ok(!CanModify(1,1), 'an EmailUser whose ID merely equals the submitter Author ID cannot modify');
$EmailUserID = 2000; ok(!CanModify(1,1), 'an EmailUser whose ID merely equals the requester Author ID cannot modify');
%DocRevisions = (77 => {Submitter => 0}); %Documents = (1 => {NVersions => 1, Requester => 0});
$EmailUserID = 999; ok(!CanModify(1,1), 'unknown caller (no Author row) never matches a zero submitter/requester');
my $src = source('ShowDocument');
like($src, qr/\$CallerAuthorID\s*=.*FetchAuthorIDFromEmailUserID\(\$EmailUserID\)/, 'ShowDocument converts the caller ID');
unlike($src, qr/\{Requester\} == \$EmailUserID/, 'ShowDocument no longer compares Requester with an EmailUser ID');
done_testing;
