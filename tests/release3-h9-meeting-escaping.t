# H9: meeting, session, break and talk text is escaped wherever it is printed
# raw. These checks load the real subroutines with stubbed data.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
no strict 'vars'; no warnings;
require InputValidation;
my $X = '<script>alert(1)</script>&"';
my $Enc = InputValidation::escape_html($X);
# --- SessionLink / SessionSeparatorLink / EventLink
stub_modules(qw(ResponseElements.pm SQLUtilities.pm MeetingSQL.pm MeetingSecurityUtilities.pm EventUtilities.pm));
sub FetchSessionByID {} sub FetchConferenceByConferenceID {} sub EuroTimeHM {'10:00'} sub EuroDate {'1 Jan'}
sub CanAccessMeeting {1} sub SessionCountByEventID {1}
$DisplayMeeting = 'DisplayMeeting';
%Sessions = (7 => {ConferenceID => 3, Title => $X, Location => $X, StartTime => '2026-01-01 10:00:00'});
%Conferences = (3 => {Title => "Event $X", LongDescription => $X, Full => "Grp:$X", StartDate => '2026-01-01', EndDate => '2026-01-01', Location => $X, AltLocation => $X, URL => 'javascript:alert(1)', Preamble => '', Epilogue => ''});
%SessionSeparators = (9 => {ConferenceID => 3, Title => $X, Location => $X, Description => $X, StartTime => '2026-01-01 11:00:00'});
load_sub('MeetingHTML.pm', $_) for qw(SessionLink SessionSeparatorLink EventLink PrintSessionSeparator);
for my $html (SessionLink(-sessionid => 7), SessionLink(-sessionid => 7, -format => 'full'),
              SessionSeparatorLink({-sessionseparatorid => 9}), EventLink(-eventid => 3), EventLink(-eventid => 3, -format => 'long')) {
  unlike($html, qr/<script>/, 'link text has no raw markup');
  like($html, qr/\Q$Enc\E/, 'link text is entity-encoded');
  unlike($html, qr/title="[^"]*<script>/, 'tooltip attribute has no raw markup');
}
# --- separator header prints title/location escaped and description through SafeHTML
sub URLify { "URLIFIED(".shift().")" } sub AddLineBreaks { shift }
my $out = capture_output { PrintSessionSeparator(9) };
unlike($out, qr/<b>\Q$X\E<\/b>/, 'separator title escaped');
like($out, qr/URLIFIED\(/, 'separator description goes through the sanitising path');
unlike($out, qr/<dd>\Q$X\E<\/dd>/, 'separator location escaped');
# --- EventHeader fields (External URL)
my $src = source('MeetingHTML.pm');
like($src, qr/m\{\\Ahttps\?:\/\/\}i/, 'external URL is only linked when it is http(s)');
# --- static checks on the other files
for my $f (qw(CalendarHTML.pm RevisionHTML.pm DocumentHTML.pm ListEventsBy ListBy)) {
  my $s = source($f);
  like($s, qr/^require "InputValidation\.pm"/m, "$f loads InputValidation at file scope");
}
unlike(source('CalendarHTML.pm'), qr/<td>\$(Conferences|Sessions)\{[^}]+\}\{(Location|URL)\}<\/td>/, 'calendar cells escaped');
unlike(source('DocumentHTML.pm'), qr/print "\$(SessionTalks|TalkSeparators)\{[^}]+\}\{(HintTitle|Title)\}"/, 'talk titles escaped');
unlike(source('ListEventsBy'), qr/join '<br\/>',\$(Sessions|Conferences)/, 'event listing locations escaped');
unlike(source('RevisionHTML.pm'), qr/print " in \$Conferences/, 'revision event location escaped');
unlike(source('ListBy'), qr/\{LongDescription\}<\/span>/, 'ListBy event description escaped');
done_testing;
