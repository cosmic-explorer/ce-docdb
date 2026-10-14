use strict;
use warnings;
no warnings 'once'; # Legacy module globals are deliberately replaced below.
use FindBin;
use File::Spec;
my $Root = $ENV{DOCDB_TEST_ROOT} || File::Spec->rel2abs("$FindBin::Bin/..");
use Test::More;

# Exercise the real legacy SQL routines with an inert database. No application
# configuration, database connection, mail, or service is loaded by this test.
our (@calls, @separator_ids, @session_ids, @deleted_sessions);

{
    package MeetingSQLTest::DB;
    sub prepare {
        return bless { sql => $_[1], mysql_insertid => 77 },
                     'MeetingSQLTest::Statement';
    }

    package MeetingSQLTest::Statement;
    sub execute {
        my $self = shift;
        push @main::calls, [$self->{sql}, [@_]];
        return 1;
    }
}

{
    local $/;
    open my $source, '<', "$Root/usr1/www/cgi-bin/private/DocDB/MeetingSQL.pm"
        or die $!;
    my $code = <$source>;
    eval "package MeetingSQLTest; no strict; no warnings; $code";
    die $@ if $@;
}

$INC{$_} = 1 for qw(SQLUtilities.pm MeetingSecuritySQL.pm RevisionSQL.pm);
{
    no warnings 'redefine';
    *MeetingSQLTest::SQLNow = sub { '2026-10-13 12:00:00' };
    *MeetingSQLTest::FetchConferenceByConferenceID = sub { 1 };
    *MeetingSQLTest::FetchSessionSeparatorsByConferenceID = sub ($) { @separator_ids };
    *MeetingSQLTest::FetchSessionsByConferenceID = sub ($) { @session_ids };
    *MeetingSQLTest::FetchRevisionsByEventID = sub { () };
    *MeetingSQLTest::DeleteSession = sub ($) { push @deleted_sessions, $_[0] };
    *MeetingSQLTest::MeetingSecurityUpdate = sub {};
    *MeetingSQLTest::MeetingTopicUpdate = sub {};
    *MeetingSQLTest::MeetingModeratorUpdate = sub {};
}
$MeetingSQLTest::dbh = bless {}, 'MeetingSQLTest::DB';

@separator_ids = (90, 91);
@session_ids = (40);
is(MeetingSQLTest::DeleteEvent(-eventid => 7), 0,
   'nonempty event requires force');
is(scalar @calls, 0, 'refused deletion performs no writes');
is(MeetingSQLTest::DeleteEvent(-eventid => 7, -force => 1), 1,
   'forced deletion succeeds');
is_deeply(\@deleted_sessions, [40], 'event sessions are deleted');
my @deleted = map { $_->[1][0] }
    grep { $_->[0] =~ /^delete from SessionSeparator / } @calls;
is_deeply(\@deleted, [90, 91], 'delete the event separators by their own IDs');
ok(!grep($_ == 7, @deleted), 'another event separator with ID 7 is untouched');
my @order_deletes = map { $_->[1][0] }
    grep { $_->[0] =~ /^delete from MeetingOrder where SessionSeparatorID=/ } @calls;
is_deeply(\@order_deletes, [90, 91], 'remove the matching separator order rows');


done_testing();
