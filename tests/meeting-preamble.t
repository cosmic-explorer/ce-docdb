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

@calls = ();
is(MeetingSQLTest::InsertEvent({
    -preamble => 'Welcome to the meeting', -epilogue => 'Closing remarks',
    -startdate => '2026-10-13', -enddate => '2026-10-13',
}), 77, 'creation returns the inserted event ID');
my ($insert) = grep { $_->[0] =~ /^insert into Conference / } @calls;
is($insert->[1][7], 'Welcome to the meeting', 'persist the supplied preamble');
is($insert->[1][8], 'Closing remarks', 'epilogue remains correctly bound');

@calls = ();
MeetingSQLTest::InsertEvent({});
($insert) = grep { $_->[0] =~ /^insert into Conference / } @calls;
is($insert->[1][7], '', 'an omitted preamble defaults to the empty string');

done_testing();
