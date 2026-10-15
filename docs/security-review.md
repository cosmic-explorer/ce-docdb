# Security and correctness review (October 2026)

Scope: the complete DocDB code in `usr1/www/cgi-bin/private/DocDB/` (182
entries, about 43,000 lines of Perl), the public-instance differences, the
static JavaScript, and the Apache/Shibboleth configuration in `etc/`. Method:
code reading and tracing of request parameters to SQL, shell, filesystem and
HTML sinks, cross-checked with read-only queries against the production
database for prevalence. Nothing was exploited against the live service; a
single probe of the Apache PATH_INFO behaviour was not run (see H5), and the
container's debug log was not read.

Each finding gives the file and line in this repository, what is wrong,
why existing checks do not prevent it, who can reach it, and a fix.
**CONFIRMED** means the full path was traced in the code; **POSSIBLE** means
one step could not be verified by reading.

Severity summary:

| Severity | Count | Deploy priority |
|----------|-------|-----------------|
| Critical | 3 | fix and deploy at the first opportunity |
| High | 17 | same release |
| Medium | 15 | next release |
| Low / informational | about 45 | as convenient |

The three Critical findings (C1 to C3) share one root cause: server-side
checks that exist in the UI or in comments but not in the code path that
performs the action. C1 needs only a federated login, not DCC membership.

---

## Critical

### C1. Content search passes an unvalidated request parameter to a shell, reachable anonymously [CONFIRMED]

`usr1/www/cgi-bin/private/DocDB/Search.pm:82,457-465`.
`$FileContSearchMode = $params{filecontsearchmode}` is never validated (the
sanitisation block at lines 117-127 covers the other search fields but not
this one) and is concatenated into a command string that is run through the
shell with `open SEARCH, " $SearchString |"`. The companion value
`$FileContSearch` is character-filtered, so the mode parameter is the
unfiltered one. Reachability, corrected after the second pass: the public
instance's `Search` script redirects every query to Google when `$Public` is
set (`Search:54-75`) and never calls `LocalSearch`, so this is **not**
reachable anonymously. It is reachable by anyone who can obtain a Shibboleth
session at all, before any DocDB group membership is checked, which with
InCommon, eduGAIN and ORCID federation is a very large population. Commands
run as the `apache` user inside the `dcc` container, which can read all
document files, both `SiteConfig.pm` files (hence the read-only and
read-write database passwords after substitution) and the files under
`/run/secrets`.

Fix: accept only the four values the wrapper understands
(`allword`, `anyword`, `allsub`, `anysub`) and reject anything else before
use; replace the shell pipe with the list form of `open` (`open my $fh, '-|',
$ContentSearch, @words, $mode`), which never invokes a shell. Apply the same
list form to the `glimpse-incr.sh` calls in H1.

### C2. `ShowDocument?mode=qacheck` publishes or un-publishes a revision with no authorization check [CONFIRMED]

`usr1/www/cgi-bin/private/DocDB/ShowDocument:143-154`. The block runs before
the `CanAccess` check at line 169 and never calls `CanAdminister()` or
`CanCertify()`. It takes the "current state" from the client-supplied `qastat`
parameter, calls `UpdateRevisionQAState` (which opens its own read-write
connection, `RevisionSQL.pm:211-220`) and `UpdateRevisionPublicSecurity`
(`SecuritySQL.pm:402-453`). With the new state 1 that routine deletes every
`RevisionSecurity` row of a revision carrying `Public_Pending` (250 revisions
today) and symlinks its files into the anonymous `/public` tree; with state 0
it adds `Public_Pending` to a public revision (158 today) and removes the
symlink. The QA button is only *shown* to administrators
(`RevisionHTML.pm:286-300`); the server does not enforce it. Any user with a
Shibboleth session can trigger it with a GET, so it is also forgeable
cross-site.

Fix: move the block after the access check; require
`CanAdminister() || CanCertify()`; read the current state from
`$DocRevisions{$DocRevID}{QAcheck}`; accept only POST.

### C3. Anyone can sign or un-sign any signature slot [CONFIRMED]

`usr1/www/cgi-bin/private/DocDB/SignRevision:102-140`. The authorization
checks push errors onto `@ErrorStack` but the only `EndPage()` that would stop
the script is commented out (line 127), so execution continues to
`update Signature set Signed=?` regardless, then mails signatories. No
`CanSign` or `CanAccess` check exists either. Sign-offs are configured
(`$UseSignoffs = 1`) but the `Signoff` table is empty in production, so the
practical exposure today is nil; the code is still wrong.

Fix: restore `EndPage();`, add `CanSign($EmailUserID)` and
`CanAccess($DocumentID,$Version)`, accept only POST.

## High

### H1. Uploaded file names reach a shell before the file-name check is enforced [CONFIRMED]

`usr1/www/cgi-bin/private/DocDB/FileUtilities.pm:71,95-96` and
`DocumentUtilities.pm:130-134`; `FSUtilities.pm:367-385` (`ProcessUpload`)
and `FileNameSanityCheck`. `FileNameSanityCheck` only pushes to
`@ErrorStack`; `ProcessUpload` writes the file and returns the name anyway,
and `AddFiles` immediately runs
`system(" $IncrementalContentSearch \"$full_file\" > /dev/null &")` with that
name inside a shell string. Nothing between the two tests `@ErrorStack`. The
name is the client-supplied multipart filename (after `basename`). Reachable
by every user allowed to add documents or files (all `CanCreate` groups,
which is essentially the whole consortium).

Fix: make `ProcessUpload` refuse to write and return empty when
`FileNameSanityCheck` reports an error (or die); use the list form of
`system`/`open` for the indexer call so the shell is never involved; run the
indexer synchronously or via a queue rather than `&`.

### H2. SQL injection through the cross-reference field [CONFIRMED]

Source `ProcessDocumentAdd:184` (`xrefs`), also `XMLUpload:337`,
`XMLClone:277`; sink `XRefSQL.pm:89`
`update DocXRef set Project="$ExtProject" where DocXRefID=$DocXRefID`
executed on the read-write connection. `$ExtProject` is any dash-separated
part of an entry that is neither a version nor a number, with only the first
whitespace run removed. DBD::mysql's default disallows multiple statements,
so the damage is bounded to that UPDATE: arbitrary writes to `DocXRef`
(including every row if the WHERE clause is commented out) and subquery-based
reads of any table into `DocXRef.Project`, which is shown on `ShowDocument`.
Reachable by any user who can add or modify documents.

Fix: use placeholders for both values; additionally accept only project
names that exist in `ExternalDocDB`.

### H3. SQL injection through manually entered author names [CONFIRMED]

`AuthorSQL.pm:478-560,580-660` (`ProcessManualAuthors`, `GetAuthorFromNames`,
the patched Cosmic Explorer version). First, middle and last names typed by
the user are interpolated into two SELECTs after a "fairly weak bad
character test" (line 504) that does not block quotes, parentheses, `#`, or
the backslash. Callers: `ProcessDocumentAdd:263` (`authormanual`, read-write
connection), `SessionModify:315`, `XMLUpload:185,195`, `SetPrefs:47`,
`Search.pm:215,222` (read-only connection, also in the public instance).
Impact as H2 plus control over which `AuthorID`s are returned.

Fix: placeholders (`FirstName = ? and MiddleInitials = ? and LastName = ?`,
and `like ?` with the `%` appended in Perl).

### H4. SQL built from the Shibboleth identity [CONFIRMED]

`SecuritySQL.pm:174-215`: `FetchEmailUserIDFromRemoteUser`,
`FetchEmailUserIDFromRemoteUserName`, `FetchEmailUserIDFromEmailAddress`
interpolate the value into `where RemoteUserName like ("...")`. The value is
the eduPersonPrincipalName asserted by whichever federated identity provider
the visitor chose (InCommon, eduGAIN, LIGO, ORCID gateway). Shibboleth's
scope check constrains only the part after `@`; the local part is free text.
Every private-instance request runs this on the read-write connection, and
`RemoteUserHasAccess` runs it for every file download. The attacker must
operate or compromise a federated IdP, which makes this unlikely but not
theoretical given thousands of eduGAIN members.

Fix: `where RemoteUserName = ?`. See also M3.

### H5. Apache grants for static-file suffixes and `/public` may bypass the session requirement on private CGI paths [POSSIBLE, config-traced]

`etc/httpd/conf.d/dcc-dev.conf:84-86` (`<LocationMatch "^/.*\.(gif|jpe?g|png|icoi|js|css)$"> Require all granted`)
and `:119-122` (`<LocationMatch "^/(.+)/public"> AuthType None; Require all granted`).
`<Location "/cgi-bin/private/DocDB">` (lines 51-55) has no `Require` of its
own and relies on `<Location />`. Later matching sections replace the earlier
`Require` set, and with `Require all granted` Apache 2.4 does not run
authentication at all, so a request for a private script with a trailing
path segment such as `/x.css` or `/public` (accepted as `PATH_INFO` by the
CGI handler) would execute the script with an empty `REMOTE_USER`. For most
scripts this behaves like the public instance (no groups, so `$Public` is
set), but it runs with the private `SiteConfig.pm` (read-write credentials
available) and reaches scripts that have no authorization of their own
(H6). A live probe was not performed.

Fix: constrain the two `LocationMatch` blocks to the static trees
(`^/(DocDB|public)/Static/.*\.(gif|jpe?g|png|ico|js|css)$` and `^/public/`),
put an explicit `Require shib-session` inside the private CGI `Location`,
and set `AcceptPathInfo Off` there (the short-URL rewrites use query strings,
not path info).

### H6. `MigrationHelper`: unauthenticated bulk-publish script left in the CGI tree [CONFIRMED]

`usr1/www/cgi-bin/private/DocDB/MigrationHelper:28-45`. A LIGO one-off that
connects read-write, selects every version-0 revision of topic 72 / document
type 2 carrying `Public_Pending`, and calls
`UpdateRevisionPublicSecurity(..., 1)` on each, publishing the files. No
`CanAdminister`, no `remote_user` check, no HTTP header (Apache returns 500
after the work is done). Any logged-in user can run it; with H5 possibly
anyone.

Fix: delete the file (nothing references it).

### H7. Text-search escaping is incomplete, allowing SQL injection on the read-only connection [CONFIRMED]

`Search.pm:117-127` escapes `' " % _ ;` with a backslash but not the
backslash itself, and `SearchAtoms.pm::TextSearch` places the result inside a
double-quoted SQL literal. An input backslash before a quote neutralises the
added escape and ends the literal early, after which the remainder is parsed
as SQL. Fields affected: `simpletext`, `titlesearch`, `abstractsearch`,
`keywordsearch`, `filesearch` (the others use a character allow-list and are
safe). `Search` runs on the read-only account, in both instances, so the
impact is disclosure of restricted metadata (titles, abstracts, notes, file
names, user and group tables) to any visitor.

Fix: build the search atoms with placeholders (collect bind values alongside
the SQL fragments) or at minimum escape `\` too and use `$dbh->quote`.

### H8. Reflected cross-site scripting through unescaped IDs and messages [CONFIRMED]

Message stacks are printed raw (`ResponseElements.pm:50-51,103-104,117-118`),
and many scripts push request values into them. Direct echoes include
`SignRevision:147-149` (`version` and `docid` inside an inline `<script>`),
`MeetingModify:385,587`, `SessionModify:1119,1299`, `MeetingHTML.pm:572`
(`conferenceid` into an href), `ShowCalendar:602-673` (`day`, `year` into the
title and headings), and `DocDBHeader` which prints `$Title` unescaped. For
the meeting scripts MySQL coerces a non-numeric ID to 0, so the authorization
helpers pass and the page renders with the payload.

Fix: validate every ID parameter as an integer (as `ListEventsBy` already
does with `CGI::Untaint`) and HTML-escape everything that is printed from a
message stack or a parameter; replace the inline redirect script in
`SignRevision` with an HTTP redirect.

### H9. Stored cross-site scripting through meeting, session and talk text [CONFIRMED]

Fixed in Release 3 ([PR #7](https://github.com/cosmic-explorer/ce-docdb/pull/7)): every raw output site escaped, external URL linked only when http(s).


`MeetingModify:54-94` and `SessionModify:661-702` store title, long
description, location, preamble, epilogue, session title and description,
talk title and note without any sanitiser; they are rendered raw in
`MeetingHTML.pm` (lines 365, 474-504, 618-642, 724-795, 850-853, 938-942),
`CalendarHTML.pm:655-686`, `ListEventsBy:467,486` and `DocumentHTML.pm:226-228`.
`DisplayMeeting` and `ListAllMeetings` are in the public instance, so a
payload in a public meeting fires for anonymous visitors as well as for every
member in the private instance.

Fix: pass these fields through `SafeHTML()` (and upgrade it, M1) or
`HTML::Entities::encode` at output.

### H10. P&P review hook sends document metadata to a LIGO development host [CONFIRMED]

Fixed in Release 3 ([PR #6](https://github.com/cosmic-explorer/ce-docdb/pull/6)): script, buttons and configuration removed; base-layer copy deleted in the Dockerfile.


`ProcessPNPReview:43-82`, `SiteConfig.pm:57` (`$pnp_host_name =
'pnp-dev.ligo.org'`), `ProjectGlobals.pm:118-120`. For reviewable types the
button in `RevisionHTML.pm:388-417` is live for any user with modify rights.
The script exports the full document XML (title, abstract, authors, file
list) over plaintext `ncat` to port 6666 on that host, calls
`system($NCatXMLCommand)` with a variable that is defined nowhere, appends
the command line to `/tmp/dbg`, and redirects the user to a LIGO Shibboleth
login. Request data does not reach the shell, but Cosmic Explorer metadata is
sent unencrypted to a third-party host.

Fix: remove `ProcessPNPReview`, `DisplayReviewButton` and the
`@ReviewableDocTypes` configuration.

### H11. Document alias accepted unvalidated in "use" mode [CONFIRMED]

`ProcessDocumentAdd:497-525` (`mode=use`, the "use an existing DCC number"
path offered by `ReserveHome`). The `oldnumber` value is upper-cased, checked
against duplicates, required to start with a letter matching the document
type, and otherwise stored as the alias. With `$UseAliasAsFileName` the alias
becomes a directory component (`MakeDirectory`, `GetDirectory`), is placed in
the indexer command string (H1) and in `rm -rf` (L6), and is printed unescaped
in links. Path traversal, command injection and stored XSS follow from a
crafted alias. `DocumentSQL.pm:146` additionally uses the alias as a `sprintf`
format string.

Fix: accept only `^[A-Z]\d{6,8}$` (the form every other script already
requires for aliases) and store the alias verbatim.

### H12. `qastat` interpolated into SQL, and clients can set certification state [CONFIRMED]

`ProcessDocumentAdd:183,600,710-717`. `$QAState = $params{qastat}` is
interpolated into `update DocumentRevision set QAcheck=$QAState` on the
read-write connection (reachable with `mode=updatedb` and `reset=0` by any
user with modify rights on one document), and the same client value is passed
to `UpdateRevisionPublicSecurity`, so a modifier can mark their own
`Public_Pending` revision certified and publish it without `CanCertify`.

Fix: coerce the value to 0/1 and bind it; for non-certifiers carry the stored
QA state of the revision forward instead of the form value.

### H13. Stored cross-site scripting through the document title [CONFIRMED]

Titles are stored as entered (`ProcessDocumentAdd:155`) and rendered raw in
`ResponseElements.pm:36` (`PrintTitle`), `DocumentHTML.pm:449` (title links
in every document table) and the `<title>` element written by
`HTMLUtilities.pm::DocDBHeader`. Abstracts, notes and publication info go
through `SafeHTML`; titles do not. Public documents render in the public
instance too.

Fix: HTML-encode titles at those output sites.

### H14. Search date-range parameters interpolated into SQL [CONFIRMED]

`Search.pm:233-251,318-321,352`. `afterday`, `afteryear`, `beforeday`,
`beforeyear` are concatenated into date strings and placed inside quoted SQL
literals (`RevisionDate < "$SQLEnd"`) executed without binding; only the
month passes through a hash lookup. Read-only connection, results still
access-filtered, but the query shape is caller-controlled.

Fix: accept only digits for day and year and known month abbreviations;
bind the dates.

### H15. `outerlogic` spliced into SQL; the validation does not abort in XML mode [CONFIRMED]

`Search.pm:62-63,272-282,288,348,443`. The AND/OR check pushes an error, but
`EndPage()` runs only when `outformat` is HTML; with XML output the script
continues and `join $OuterLogic, @Phrases` places the raw value between SQL
atoms.

Fix: normalise both logic operators to `AND`/`OR` before use.

### H16. Author names written into a JavaScript array unescaped [CONFIRMED]

`AuthorHTML.pm:510-528` (`AuthorJSList`) emits `"$Authors{$ID}{Formal}"`
inside a `<script>` block with no escaping of quotes, backslashes, newlines
or `<`. Called from the home page of both instances (`DocumentDatabase:193`),
`SearchForm`, `SelectPrefs` and `DocumentAddForm`. Any user with `CanCreate`
can add an author with an arbitrary name through `AuthorAdd`, so this is a
stored script injection on the home page.

Fix: escape each element for a JavaScript string literal (or emit JSON);
restrict author name characters in `AuthorAdd`.

### H17. Document keywords placed in links without encoding [CONFIRMED]

`KeywordHTML.pm:250-259` (`KeywordLink`) builds the href and link text from
each keyword with no URL or HTML encoding; `RevisionHTML.pm::PrintKeywords`
passes `DocumentRevision.Keywords`, stored verbatim from the document form.
Every reader of `ShowDocument` is affected. `KeywordLinkByID` (lines
234-240) and the chooser's `onclick` (line 59) have the same gap with
admin-defined keywords.

Fix: `CGI::escape` for the query string, `HTML::Entities::encode` for the
text, JavaScript-escape the `onclick` value.

## Medium

### M1. Vendored HTML::Defang 1.04 has a known sanitiser bypass [CONFIRMED]

`Defang.pm:127` (`$VERSION = 1.04`), used by `Utilities.pm::SafeHTML` for
abstracts, revision notes and session descriptions. Versions before 1.09
treat the contents of raw-text elements (`noembed`, `noframes`, `title`,
`textarea`) as ordinary markup, which allows comment-smuggling bypasses that
upstream fixed in 1.09. Event handlers and `javascript:` URLs are otherwise
handled correctly; the missing `url_callback` only means external links are
allowed.

Fix: replace `Defang.pm` with HTML::Defang 1.09 or later (or the system
package), and until then add `tags_to_callback` for those elements returning
`DEFANG_ALWAYS`.

### M2. `CanModify` compares an Author ID with an EmailUser ID [CONFIRMED]

Fixed in Release 3 ([PR #8](https://github.com/cosmic-explorer/ce-docdb/pull/8)): both sites convert with `FetchAuthorIDFromEmailUserID` and never match a zero ID.


`Security.pm::CanModify`: `if ($SubmitterID == $EmailUserID)` and
`if ($Documents{$DocumentID}{Requester} == $EmailUserID)`. `SubmitterID` and
`RequesterID` are Author IDs (see `ProtectDirectory`, which converts them
with `FetchEmailUserIDFromAuthorID`); `$EmailUserID` is the caller's
EmailUser ID. `CanAccess` does the conversion; `CanModify` does not. The same
mistake is at `ShowDocument:165-168`. Harmless today only because the
provisioner has kept `EmailUserID == AuthorID` for all 752 users (verified
in production); it grants or denies modify rights to the wrong person the
moment the two sequences diverge (for example after `AuthorAdd`).

Fix: convert with `FetchAuthorIDFromEmailUserID` before comparing.

### M3. Exact user lookups use `LIKE` [CONFIRMED]

`SecuritySQL.pm:174-215` match the identity with `like`, so `_` and `%` in an
ePPN act as wildcards and `fetchrow_array` returns an arbitrary first match.
Two production ePPNs contain `_`. `FetchSecurityGroupByName` and
`SecurityLookup` have the same pattern with placeholders.

Fix: `=` comparisons; add a unique index on `RemoteUser.RemoteUserName`.

### M4. Debug output written to world-readable files in the container [CONFIRMED]

`RemoteUserHasAccess:8-9,30-35` appends the user, the time and **every
environment variable** of each file-download authorization to `/tmp/debug`
(5.6 MB and growing in production); `Utilities.pm:88,101,122` writes mail
recipients to `/tmp/log.dat` on every e-mail; `SignoffHTML.pm:1033` opens
`/tmp/debug.mca` on every document view; `ProcessPNPReview:29`,
`MigrationHelper:41` likewise. Files are 0644 and live in the container's
writable layer.

Fix: delete these lines; use `syslog_err` behind a debug flag.

### M5. `UsersGroup` is massively duplicated [CONFIRMED, data]

35,971 rows for 962 distinct (user, group) pairs; one membership repeated
430 times; no unique key. Root cause (confirmed from the plugin source and
the deployed API library): the API lists 100 rows per page and the COmanage
provisioner only reads the first page, so every `CEConsortium` member beyond
the first 100 is re-inserted on each group sync; see
[rest-api.md](rest-api.md). Every group with fewer than 100 members has
exactly one row per member. `FetchUserGroupIDs` returns thousands of IDs for
active users and `CanAccess`/`CanModify` loop over them against the hierarchy
on every page and every file download. The table (MyISAM) grows without
bound.

Fix: disable pagination for these API resources or make the plugin follow
`Content-Range`; de-duplicate; add `UNIQUE KEY (EmailUserID, GroupID)`. The
host already carries a `remove_duplicates.sql` from a previous manual
clean-up.

### M6. Sessions of access-restricted meetings are listed on the calendar [CONFIRMED]

`CalendarHTML.pm:552-555,622-624,666-691`, `ListEventsBy:461-477`:
`SessionLink` and the day/topic/moderator views print sessions (title, time,
location, event title) without `CanAccessMeeting`, although `DisplayMeeting`
then correctly refuses the follow-through.

Fix: filter sessions by `CanAccessMeeting($Sessions{$SessionID}{ConferenceID})`.

### M7. "Reserve" from a multi-session agenda creates a world-readable document [CONFIRMED]

`SessionModify:1019-1033` passes `-viewids` and `-modifyids` from
`$params{meetingviewgroups}`, a field only present in the single-session
form; from the normal form the lists are empty, so the reserved document has
no view groups and is public.

Fix: derive the groups from `MeetingSecurity`/`MeetingModify` of the event.

### M8. Meeting modifiers can attach any document to a talk [CONFIRMED]

`SessionModify:927-931,996-998`, `EditTalkInfo:966-973`,
`TalkSQL.pm:563-581` (`ConfirmTalk`): a `RevisionEvent` row is inserted for a
document the user may not even view. `ShowTalkNote:1207` tests
`CanModifyMeeting` on an undefined variable, so it always passes.

Fix: require `CanModify($TalkDocID)` (or at least `CanAccess`) before
confirming; fix the variable name.

### M9. No cross-site request forgery protection anywhere [CONFIRMED]

Every state-changing script reads `%params = $query->Vars` regardless of
method and has no token: `ProcessDocumentAdd`, `AddFiles`, `DeleteDocument`,
`SignRevision`, `MeetingModify`, `SessionModify`, `EditTalkInfo`,
`ConfirmTalkHint`, `WatchDocument`, `SelectEmailPrefs`, `SetPrefs`,
`SetGroups`, `ShowDocument?mode=qacheck`. With cookie-based Shibboleth
sessions, a link or image on any page a member visits can perform these
actions. (Admin processing scripts are protected incidentally by requiring
the MySQL password in the POST.)

Fix: reject non-POST for state changes and add a per-session synchroniser
token (for example derived from the Shibboleth session ID) checked in a
shared helper.

### M10. Stored cross-site scripting through file descriptions [CONFIRMED]

`FileHTML.pm:220-228` (`FileLink`) prints the per-file description from the
`filedesc<N>` upload fields, and the file name in a `title` attribute, without
encoding. Rendered wherever a file list appears, including the public instance.

Fix: HTML-encode description and names in `FileLink`.

### M11. XMLUpload can import files from the server's `/tmp` [CONFIRMED]

`XMLUpload:281-293` treats a `<file href>` that exists locally and whose
directory is in `@LocalUploadDirectories` as a file to copy into the new
document. `SiteConfig.pm:42` lists `/tmp` (shared with every process in the
container, including DocDB's own debug files from M4). Any `CanCreate` user can
therefore attach arbitrary world-readable files from `/tmp` to a document.

Fix: empty `@LocalUploadDirectories` (or point it at a dedicated directory).

### M12. `ListBy` hidden inputs use unquoted attribute values [CONFIRMED]

`ListBy:388-394` prints `value=$TopicID` (and `eventgroupid`, `authorid`)
without quotes. The entity-encoding hot-fix leaves spaces and `=` intact, so
a value containing whitespace adds attributes to the element.

Fix: quote the attributes and validate the IDs as integers.

### M13. Event titles written into JavaScript with incomplete escaping [CONFIRMED]

`Scripts.pm:70-72` escapes only the first single quote in `Conference.Full`
and nothing else before `event['$EventID'] = '$label'`. Anyone who may create
events controls the title; the script is included on `SearchForm`.

Fix: full JavaScript string escaping.

### M14. Custom list field names are never validated and are printed raw [CONFIRMED]

`CustomListForm:296-387`, `DocumentUtilities.pm:297-311`
(`CookieToFieldList`), `DocumentHTML.pm:97-104,213-216`. Field names from
`field1..15`, row/column spans and the stored cookie or `ConfigSetting` values
are not checked against `%FieldTitles` and are emitted into `class` and
`title` attributes and action messages unencoded. `CustomListForm` has no
request-forgery protection, so a cross-site POST can plant the cookie.

Fix: accept only known field keys and small integers; encode what is echoed.

### M15. Database-sourced names printed without HTML encoding in link helpers [CONFIRMED]

`AuthorHTML.pm:291-296,322-324,340,349` and the mailto links at 161-162,
201, 248, 265; `DocTypeHTML.pm:137-139`; `TopicHTML.pm:297`;
`SecurityHTML.pm:238-241`; `ListBy` messages at 193-306; `ListAuthorGroups:110`,
`ListGroups:353`, `ListGroupUsers:79-119`, `ListEmailUsers:212-238`,
`ProjectRoutines.pm:94,101`, `AuthorAdd:171`. Author names are the weakest
trust boundary (any `CanCreate` user); the rest require admin roles.

Fix: encode at output, as `TopicLink` already does.

## Low

* **L1** `Utilities.pm::URLify` builds auto-links to `https://<hostname>.ligo.org`
  (a `my $host_name` shadows the global); every auto-linked document number
  points to a dead host. Use the global.
* **L2** `Utilities.pm::DefangUrlCallback` is dead code (never passed to
  Defang) and whitelists `ligo.org`. Wire it up with `cosmicexplorer.org` or
  delete it.
* **L3** `Cookies.pm::GetReadGroupACLsCookie`/`GetWriteGroupACLsCookie` read
  the cookie into `$myGroupPref` but split the unrelated globals
  `$ReadGroupPref`/`$WriteGroupPref`.
* **L4** `Utilities.pm::Union` computes an intersection. Its one caller
  (`FindUsersGroups`, applying the group-limiting cookie) needs exactly that,
  so the behaviour is right and the name is wrong.
* **L5** `RetrieveFile`: the `extension` parameter is interpolated into a
  regex (`grep /$Extension$/i`); use `\Q...\E`.
* **L6** `DeleteDocument` (admin only) leaves orphans in `RevisionModify`,
  `RevisionEvent`, `RevisionAuthorGroup`, `RevisionReference`, `DocXRef`,
  `SessionTalk`, `Signoff*`, `Notification`, builds the directory from an
  undefined version and chops four characters, and shells out
  `rm -rf $Directory/*`. Delete dependents, use `File::Path::remove_tree`,
  require POST.
* **L7** `Security.pm::CanAccess` in the public instance: with an anonymous
  caller `$AuthorID` is undefined, so a revision whose `SubmitterID` is 0
  would compare equal and become world-readable. No such revision exists
  today (verified). Guard with `$AuthorID &&`.
* **L8** `DocumentSQL.pm:83` interpolates a (database-sourced) `DocRevID`
  into SQL; parameterise for consistency.
* **L9** `UserAccessApply`, `CertificateApplyForm`, `BulkCertificateInsert`
  and `CertificateUtilities.pm` are the Fermilab certificate flow; dead under
  `kerberos` validation (client certificates are not enabled in `ssl.conf`),
  but `UserAccessApply` would insert `EmailUser` and arbitrary `UsersGroup`
  rows with no review if certificates were ever enabled, and accounts created
  by `BulkCertificateInsert` never get a `RemoteUser` row so they cannot log
  in. `UserAccessApply:67` tests `@GroupIDS` (wrong case). Remove the four
  scripts.
* **L10** `SelectEmailPrefs:204-224` and `WatchDocument:733-747` never set
  `$EmailUserID` under kerberos: preference changes silently do nothing and
  WatchDocument always errors. `SelectEmailPrefs:70` compares strings with
  `==`.
* **L11** E-mail header injection through the document title is POSSIBLE:
  `MailNotification.pm:117-160` builds `Subject` from the stored title, which
  `ProcessDocumentAdd:155` takes from `$params{title}` without stripping
  CR/LF, and the vendored Email::Simple does not filter them. Strip `[\r\n]`
  in `send_email`.
* **L12** `ListBy` production hot-fix HTML-encodes every parameter on entry
  (block pasted twice). Adequate for `ListBy`'s numeric parameters; the
  proper fix is output escaping (H8). Remove the duplicate block.
* **L13** `DocTypeAdminister:53-61` prints the error page before the HTTP
  header on a failed admin login (malformed-header 500).
* **L14** Admin pages render provisioner-controlled strings
  (`EmailUser.Name`, `Username`, group names) unescaped
  (`EmailAdministerForm:239-259`, `GroupAdministerForm:134`,
  `GroupHTML.pm:28-57`). Escape them; have the REST API validate names.
* **L15** `SessionModify:985-1006` lets talks be moved into sessions of
  meetings the user may not modify.
* **L16** Client-side leftovers: `ICSLink.js` emits a link to a LIGO JIRA
  host on every D-type document page (`FileHTML.pm:73-93`);
  `ScrollListSelector.js` and `AdministerHome:101` hard-code group IDs 1 and
  43; `Signatures.js` validates `@LIGO.ORG` addresses and calls endpoints
  that do not exist; `MathJaxToggle.js` hard-codes the private help URL;
  `SearchForm.js` strips the stop word `ligo`.
* **L17** `usr1/www/cgi-bin/test.pl` is a broken Sentry smoke test embedding
  a sentry.io DSN (project key). Not web-reachable, but shipped in the image
  and now in this repository's history. Delete it and revoke the key.
* **L18** Apache: `/DocDB` and `/public` have `Options +Indexes` (directory
  listings of document folders); `/public` also has `+ExecCGI` and
  `+IncludesNoExec` which are unnecessary; `AuthName` strings still mention
  LIGO/Virgo; `e-traveler.conf` configures an application that is not
  installed; `authnz_external.conf` defines an unused `pwauth`
  authenticator; `LogLevel alert rewrite:trace4` is left on in both short-URL
  configurations. Remove `+Indexes` from `/DocDB`, drop the extra options,
  delete `e-traveler.conf`, lower the log level.
* **L19** (`MeetingSQL.pm`, `TopicSQL.pm` fixed in Release 2; `TalkHintUtilities.pm`, `SignoffUtilities.pm`, `DisplayMeeting` fixed in Release 3, PR #10; `SignoffSQL.pm:334-350` dead code left) Correctness defects that change behaviour: `MeetingSQL.pm:770/786`
  (`-preample` typo loses the event preamble on create), `MeetingSQL.pm:957`
  (deletes the wrong separator), `MeetingSQL.pm:554` (cache check on the
  wrong hash), `DisplayMeeting:128` (compares with an undefined variable),
  `SignoffUtilities.pm:644` (tests the wrong variable so `$LastDocRevID` is
  never set), `SignoffSQL.pm:334-350` (undeclared variables; dead),
  `TalkHintUtilities.pm:65-72` (`s/\W//g` removes the spaces it then splits
  on, so fuzzy title matching only works on whole-title substrings),
  `CalendarHTML.pm:686` (stale `$EventID`), `ListEventsBy:407` (wrong array
  name), `DocumentReviewSQL.pm` (keys results by a global), `AuthorSQL.pm`
  manual-author error message builds an unused `$xxx`.
* **L21** Document-flow defects: `ModifyHome:118-127` "Reserve" button posts
  `mode=update`; `ProcessDocumentAdd:485` tests `$DocumentID` (never set; the
  variable is `$documentID`) so the branch is dead; `FileUtilities.pm:145`
  uses an undefined `$main_file` in a warning that `$UseDeadlyWarning` turns
  fatal; `RetrieveArchive:68` prints the literal text `&remote_user`;
  `XRefHTML.pm:117` fetches with a not-yet-set `$RefDocID`; `XMLClone:93-98`
  patches XML with hard-coded offsets and corrupts it when the text lacks
  `amp;`; `RevisionSQL.pm::FetchRevisionAuthorEmailUserIDs` returns an
  unrelated global (dead); `RevisionHTML.pm:423-451` (`DontPrintRevisionInfo`)
  places `docid`/`version` into an `onClick` attribute unescaped (reflected
  XSS on the AddFiles error path).
* **L22** `DocumentHTML.pm:62` computes the "First N of M documents" total
  from the unfiltered ID list (and off by one); `ListBy:447-449` and
  `Search.pm:634-636` print it, revealing how many matching documents exist
  that the caller cannot see. `ListManagedDocuments:320-325` calls
  `DocumentTable` in scalar context and gets the wrong count.
* **L23** `XSearch:177-188` prints URL, title and author from remote DocDB
  XML without encoding; `XSearch.pm:47` appends the search text to the remote
  URL without URL-encoding. Not present in the public instance.
* **L24** `SearchAtoms.pm:60`: in word modes each word becomes part of a
  MySQL `REGEXP`; metacharacters are not escaped, so callers control the
  pattern (expensive or invalid expressions fail silently). POSSIBLE impact
  only.
* **L25** (fixed in Release 3, PR #5) Public `Search:54-66` redirects to Google with `site:dcc.ligo.org`
  and the raw query text: every public search on the Cosmic Explorer site
  searches LIGO's DCC. Use the configured host and URL-encode the text.
* **L26** (fixed in Release 3, PRs #9 and #11, except `DocDBHelp.xml`, which is LIGO help text throughout and needs a rewrite) More LIGO leftovers: `AuthorHTML.pm` mail subjects say `LIGO-`;
  `ListGroups:342` and `DocDBHelp.xml` link to `dcc.ligo.org`;
  `ProjectRoutines.pm:105` hard-codes group ID 14 as the admin group;
  `ListBy:84` forces the Los Angeles time zone; `GeneralInstructions.pm:162`
  links to Fermilab.
* **L27** (fixed in Release 3, PR #9, except `InstitutionAddForm`, `FormElements.pm:634-695` dead code and the `local $SIG{__WARN__}` scoping, which is left alone deliberately because `$UseDeadlyWarning` is 1 and making the handler effective would turn every warning in those scripts into a server error) Runtime defects in this area: `SearchAtoms.pm:327-332` uses the key
  `Numbers` (hash key is `Number`) so number matches get no relevance weight;
  `SetGroups:495` reads `groups` while `SelectGroups` posts `security`, so the
  limiting cookie is always `-1` (unreachable under kerberos validation);
  `InstitutionAddForm` is a mislabelled copy of `AuthorAddForm`;
  `DocTypeHTML.pm:54-55` uses labels as option values so per-type custom
  lists never apply; `TopicSQL.pm:296-298` reads a non-existent hash key;
  `KeywordSQL.pm:150` prepares a delete it never executes; `ListBy:312`
  `latest=1` subquery is a no-op and the type listing lacks `Obsolete=0`;
  `local $SIG{__WARN__}` inside an `if` block in `Search`, `SearchForm`,
  `SelectPrefs` is undone immediately so `$UseDeadlyWarning` has no effect
  there; `TopicHTML.pm:131-139` declares `%Lists` but uses `%List`;
  `FormElements.pm:634-695` dead code clobbers `%params`;
  `ProjectRoutines.pm:161-163` labels the logout link "Login" and shows it
  only to administrators.
* **L28** `Statistics` is in the public instance and reports counts over all
  documents including restricted ones (and divides by zero on an empty
  database); `ListGroupUsers` and `ListEmailUsers` show every account's name
  and e-mail to any logged-in user. Confirm these are intended.
* **L29** `SetPrefs` stores `numfile` and `overdate` from the request in
  cookies without bounds; `Cookies.pm` reads them back unchecked.
* **L30** (fixed in Release 3, PR #4, with a local `UntaintParams.pm` instead of installing the module) Three scripts cannot compile in the production image because the
  Perl module `CGI::Untaint` is not installed: `ListEventsBy` (events by topic
  or moderator), `TopicAdminister` (topic administration) and
  `BulkCertificateInsert`. They return a server error whenever invoked and
  have done so since the image was built; the `ListEventsBy` links on event
  pages are therefore dead. Fix: install `perl-CGI-Untaint` in the image (or
  replace the three `CGI::Untaint` uses with explicit integer checks).
* **L20** LIGO leftovers in text: `SignoffHTML.pm:981,1133` mailto subjects
  say `LIGO-`; `$GroupSuffix = "@ligo.org"`; `CertificateInstructions.pm` is
  Fermilab text; `AuthName` strings; `pnp-dev.ligo.org`.

## Informational

* **I1** URL-based upload (`FSUtilities.pm::DownloadURLs`) would fetch
  arbitrary URLs with `wget`, including hosts on the swarm network such as
  the unauthenticated Hydra admin API on `oauth-server:4445`. `$Wget` is
  empty in `DocDBGlobals.pm` and not overridden, so the feature fails closed.
  Keep it disabled; if ever enabled, allow only http(s) to public hosts.
* **I2** Archive extraction (`ExtractArchive`) and archive download
  (`RetrieveArchive`) build shell strings, but `$Tar`, `$GTar`, `$Unzip`,
  `$Zip` are all empty, so both are disabled. The comment in `ExtractArchive`
  acknowledges it does not protect against `..` in archive members.
* **I3** `MakeDirectory` creates directories with mode 0777 (umask-limited).
* **I4** `HTMLUtilities.pm` loads MathJax from cdnjs without subresource
  integrity; `$HTTP_ENCODING` is ISO-8859-1 while Apache sets
  `AddDefaultCharset UTF-8`, so non-ASCII titles can render incorrectly.
* **I5** 34 `RemoteUser` rows have an empty `RemoteUserName` and so can never
  match a login; `RemoteUser.EmailAddress` and `EmailUser.Password` are
  unused.
* **I6** `Params/Validate*.pm` (Params::Validate 0.89) is vendored and
  unused.

## Adjacent component: the REST API and OAuth2 services

Not part of this repository (source in `ce-it-infrastructure/rest-dcc`), but
reviewed because they write the user and group tables; details in
[rest-api.md](rest-api.md).

* **A1 [Medium, CONFIRMED]** `auth.js` logs every bearer token in clear text
  to the container log; anyone who can read `docker service logs dcc_rest-api`
  can replay a live token. Remove the `console.log` of the token.
* **A2 [Medium, CONFIRMED]** Any active Hydra access token is accepted
  regardless of client, scope or subject, and every endpoint allows create,
  update and delete, including `SecurityGroup.CanAdminister` and `UsersGroup`
  for any group. Acceptable only while the `/login` allow-list is the sole way
  to obtain a token; add client-ID and scope checks in the introspection
  handler.
* **A3 [Medium, CONFIRMED]** The API paginates lists at 100 rows and the
  COmanage plugin reads only the first page, so membership syncs for groups
  with more than 100 members are not idempotent (M5). No values are validated
  before storage.
* **A4 [Low]** Node 12, Express 4.16, Sequelize 5, node-fetch 2 and Hydra
  v1.0.8 are all end-of-life; Dependabot flags the Node dependencies.


## Additional findings from the independent review (14 October 2026)

Geoffrey Lovelace ran a second, independent review with GPT Codex (branch
`codex/ce-docdb-unified-review-2026-10-14`, since removed; assessed in
[assessment-codex-branch-2026-10-14.md](assessment-codex-branch-2026-10-14.md)).
Its security findings overlapped ours almost completely; its distinct
contribution is a long list of **reliability and correctness defects** in the
document, search, meeting and administration flows, plus a few operational
and documentation corrections. The table reproduces its plain-language
inventory so that the content survives the branch. IDs are his: `R` =
reliability review, `F` = follow-up review, `H` = cross-reference to this
document. Rows marked fixed point at the branch that carries the fix; the
rest are open and belong in Release 3.

Three of his items changed our own work: S7 (Docker `COPY` cannot delete
base-layer files, so retired scripts must be removed with `RUN rm`), S4
(`renew-certs.sh` traced the secret values) and S6 (the public `Utilities.pm`
is a separate copy). One item, S1, proposed reading the authorizer identity
from `USER`; that would have denied every private download with the module we
run and was replaced by a stdin-based version with his fail-closed checks.

| Finding | Problem in plain language | Status |
|---|---|---|
| R C01 | A topic could become its own ancestor, making topic browsing loop forever. | fixed in release-2 |
| R C02 / H L27d | Choosing a document type sent its name where the program expected its number. | fixed in release-2 |
| R MT01 / H L19b | Deleting an event could delete the wrong agenda break. | fixed in release-2 |
| R MT02 / F R3c / H L19a | A new event silently lost its introductory text. | fixed in release-2 |
| R D12 | Exporting several documents could omit incoming links from later documents. | fixed in release-2 |
| R O07 | The login page's recent-documents link was malformed. | fixed in release-2 |
| R O01 | A failed database dump could look like a good backup, and the recovery instructions did not ensure that files and database agreed. | docs corrected |
| R O02 / F R2 | Recovery instructions made a disruptive rebuild sound safe to repeat and described saved search indexes incorrectly. | docs corrected |
| R O03 / F R7 | A build error wrongly said a local commit also had to be pushed. | docs corrected |
| F S1 / R RP01 | Private-file authorization read the login identity from the wrong place and could choose a blank or wrong account. | fixed in release-2 |
| F S2 / R RP02 | Old diagnostic URLs exposed request/login details and shared temporary data. | fixed in hotfix-release-1 (PR #1) |
| F S7 / R RP07 | Removing a file from Git did not remove an inherited copy from the container image. | fixed in hotfix-release-1 (PR #1) |
| F S4 / R RP04 | Certificate-renewal command tracing could print service-secret values. | fixed in hotfix-release-1 (PR #1) |
| F R1 / R O03a | A failed or incomplete inspection could wrongly report that deploying would overwrite no local changes. | fixed in release-2 |
| F S6c / R RP08 | The public site had a separate copy of a helper and missed fixes applied to the private copy. | fixed in hotfix-release-1 (PR #1) |
| R D01 | A metadata-only edit can start from reserved version 0, then save over the latest version, replacing its metadata or file selection. | open |
| R D02 | A failed upload can truncate the existing file and still be reported as successful. | fixed in release-3 (PR #10) |
| R D03 | A revision is marked obsolete before its replacement is known to have saved; an insertion failure can leave no active revision. | open |
| R D04 | Two concurrent uploads can choose the same version number and overwrite or hide each other's work. | open |
| R D05 | A typo sends the wrong certification state with a minor-edit form, so an administrator or certifier can accidentally clear certification. | fixed in release-3 (PR #10) |
| R D06 | Two files with the same final filename in one request can overwrite one another while creating duplicate database rows. | fixed in release-3 (PR #10) |
| R D07 | The direct Add form can omit the document type that its save handler requires. | fixed in release-3 (PR #10) |
| R D08 | The date-override choice can be ignored because the form reads a different variable from the one the preference handler sets. | fixed in release-3 (PR #10) |
| R D09 | Reservation creation sends the word “new” where the database expects a numeric version, giving different results under different database settings. | fixed in release-3 (PR #10) |
| R D10a | Cloning or importing a document loses its group authors; even supplied group-author IDs are not saved. | open |
| R D10b | XML import omits journal references that the export contains. | open |
| R D11a | Editing a cross-reference can turn an explicitly pinned latest version into a moving “latest” link. | open |
| R D11b | XML clone/import loses a cross-reference's version and external project, and mishandles an explicit version 0. | open |
| R D13 | A failed database connection can be treated as a successful connection object, causing later failures instead of a clean error. | open |
| R D14 | An explicit request for version 0 can select the latest version instead. | open |
| R D15, R DX16 | XML file links are escaped twice, while cloning attempts to repair text by cutting/replacing strings; ordinary links or metadata can be damaged. | open |
| R DX01 | The file-add handler turns a “do not reset signatures” request into a reset, but the normal browser warning promises that reset; the request contract and interface disagree. | open |
| R DX02 | A revision lookup identifies different kinds of record depending on whether it has already fetched the result. | open |
| R DX03 | A meeting lookup can return obsolete revision IDs when the cache is empty. | open |
| R DX04 | The displayed result count can be one larger than the number of rows actually shown. | open |
| R DX05 | Editing a document type in January can prevent the annual document-number counter from resetting. | fixed in release-2 |
| R DX06 | A missing-file warning is immediately replaced by a redirect to a storage 404 page. | open |
| R DX09 | Deleting a document does not clean up all its related records and can fail partway through file removal. | open |
| R DX10 | Concurrent document-number allocation can race on the shared alias counter. | open |
| R DX11 | The Reserve control submits the update action instead of reservation. | open |
| R DX12 | One document-ID handling step never runs because its variable name is capitalized inconsistently. | open |
| R DX13 | File handling reads an unset main-file variable, generating a warning that can abort execution when warnings are fatal. | open |
| R DX14 | An archive error prints the literal text “remote_user” instead of the intended user information. | open |
| R DX15 | Cross-reference display tries to fetch the referenced document before setting its ID. | open |
| R DX17 | An author-email lookup returns the wrong global result list. | open |
| R DX18 | XML-search links do not correctly encode all query characters. | open |
| R DX19a | Downloading a file from a supplied HTTP URL is disabled by configuration. | open |
| R DX19b | Archive download/extraction is disabled because its executables are not configured. | open |
| R C01a | Force-deleting a topic can delete a shared child that still belongs under another parent. | open |
| R C02 | Document-type controls submit a name where the server expects a numeric ID. | fixed in release-2 |
| R C03 | “All selected authors” searches count repeated relationships rather than distinct selected authors, producing wrong matches. | open |
| R C04 | Author lists can ignore the requested author order and compare the wrong cached data or row IDs. | open |
| R C05 | Public search goes to the LIGO site and drops most advanced search choices. | fixed in release-3 (PR #5) |
| R C06 | Generic public lists skip fetching their documents, so otherwise valid event/type/all-document views can be empty. | open |
| R C07 | Changing a result limit or date range drops other search filters. | fixed in release-3 (PR #9) |
| R C08 | A supposedly latest-version-only group search can match older versions too. | open |
| R C09 | Large searches stop before sorting all candidates, so newer or better matches can be omitted. | fixed in release-3 (PR #9) |
| R C10 | Document-number matches receive the wrong relevance score because the code uses the wrong result list and weight name. | open |
| R C11 | A dotted first initial, such as “J.”, can prevent a manual author match. | open |
| R C12a | Invalid author preferences can still change browser cookies before the error is reported. | open |
| R C12b | An unbounded upload-count preference can make the page generate an excessive number of file controls. | open |
| R C13 | Statistics can divide by zero on an empty database or a populated database with no events. | open |
| R C14a | Deleting an author leaves references from submitters, requesters, groups, moderators, hints and accounts. | open |
| R C14b | Deleting a journal leaves document-publication references pointing to it. | open |
| R C14c | Deleting a document type leaves existing revisions without their type. | open |
| R C14d | Deleting an external document database leaves cross-references pointing to it; the advertised force option is unused. | open |
| R C15 | Deleting a keyword never runs the prepared cleanup of its group memberships. | open |
| R C16a, R C16b | Immediately after editing an institution or keyword group, the confirmation page can show old cached values. | open |
| R C17a, R C17b | Type and publication searches can match obsolete revision metadata. | open |
| R C18 | The author-group block contains unclosed markup and repeated element IDs, which can confuse layout or browser scripts. | open |
| R C19 | Passive institution discovery reads an undeclared variable and can fail. | open |
| R C20a | Hovering an institution's icon can deselect the option instead of selecting it. | open |
| R C20b, R C20c | Institution-choice accessibility attributes point to a nonexistent list ID and can leave several options marked selected. | open |
| R C21 | Institution metadata may use the wrong language because the language variable is unset and plain language codes are mishandled. | open |
| R CX01a | MathJax help links point to a LIGO test site. | open |
| R CX01b | Deletion help names LIGO support instead of the confirmed CE contact. | open |
| R CX01c | Advanced-search help uses a retired topic-list link. | open |
| R CX02a | Help incorrectly says AND topic searches cannot expand descendants. | open |
| R CX02b | Help incorrectly says manual middle initials are ignored. | open |
| R CX02c | Help disagrees about whether document numbers have six or eight digits. | open |
| R CX03 | Upload help advertises the disabled HTTP-download option. | open |
| R CX04a | An old event's year menu may not extend far enough to choose the current year. | open |
| R CX04b | A separate-minute control uses inconsistent padded/unpadded defaults. | open |
| R CX04c | Rounding a late-hour minute can produce minute 60 without advancing the hour. | open |
| R CX05 | An invalid month 0 can be displayed as December. | open |
| R CX06 | An unused author lookup confuses an author's identity with the identity of the author-document link. | open |
| R CX07 | Access-preference helpers fail to update the values their callers expect. | open |
| R CX08a | A stored FullList template ends after its header. | open |
| R CX08b | Generated lists and BTeV templates contain stale historical content. | open |
| R CX09a | A project stylesheet contains invalid arithmetic and an extra closing brace. | open |
| R CX09b | A test private stylesheet points at a public logo. | open |
| R CX11 | Leaving an external-database URL blank cannot clear its existing value. | open |
| R CX12 | Editing an external database can report success without checking whether the database write succeeded or matched a row. | open |
| R OX01 | Legacy bulk certificate-account creation does not update its cache after each insertion and may create duplicates within the same batch. | open |
| R OX02 | A typo prevents the legacy certificate application status page from showing the user's groups. | open |
| R OX05 | Certificate help describes old Fermilab/DOEGrid/LIGO/BTeV processes, not CE onboarding. | open |
| R MT01 | Deleting an event used its event ID when deleting breaks, risking the wrong break being removed. | fixed in release-2 |
| R MT02 | Creating an event lost the submitted introductory text. | fixed in release-2 |
| R MT03 | A break has no alternate-location field, but saving advances the location list for every row; later sessions receive the wrong locations. | fixed in release-3 (PR #10) |
| R MT04a | Copying an event changes row IDs but leaves moderator, topic and display controls attached to the old IDs. | open |
| R MT04b | Copying a break can turn it into an ordinary session; copied and new rows can also collide in identity. | open |
| R MT05 | Conflict detection can miss another edit in the same year and is not enforced atomically when saving. | open |
| R MT06 | Editing a talk note drops its existing topic hints because the caller uses the topic selector incorrectly. | open |
| R MT07 | Repeating an explicit sign or unsign request can reverse the requested state instead of leaving it unchanged. | open |
| R MT08 | A stale break cache can show the old value after a successful edit and allow an unchanged resubmit to restore it. | open |
| R MT09 | Selecting an invalid date such as February 31 can throw an exception before the form can show a normal error. | open |
| R MT10 | Creating a talk can silently choose document type 1 when the configured presentation type is absent or mismatched. | open |
| R MT11 | A misspelled event-mode comparison skips refresh of event hint data. | open |
| R MT12 | Suggested talk matches lose word boundaries, causing titles with common words to score incorrectly. | open |
| R MT13 | A session's calendar link can use another event's URL. | open |
| R MT14 | An event with only one break is treated as an event with one real session. | open |
| R MT15 | Repeated event-hint searches in one request can retain candidates from an earlier event. | open |
| R MT16 | The conference lookup fails to reuse results it already fetched, causing unnecessary repeat database requests. | open |
| R MT17a | Recipient selection ignores daily/weekly document-type subscriptions. | open |
| R MT17b | Digest preferences are offered, but no digest sender or scheduler exists in the tracked repository. | open |
| R MT18 | Comma-separated keyword subscriptions can fail to match when there are no spaces. | open |
| R MT19 | A legacy “all documents” subscription can disappear when preferences are read and saved. | open |
| R MT20 | A legacy review lookup puts fetched review details into the wrong revision's temporary cache entry, so later display/status checks can be wrong. | open |
| R MT21 | A signoff with alternative signers can be made dependent on itself, preventing the workflow from progressing. | open |
| R MT22a | A latest-approved lookup tests the wrong status field. | open |
| R MT22b | An unused pre-signatures lookup uses the wrong query and result variables. | open |
| R MT22c | A legacy review-submission helper does not wait for or check its child process, so it cannot know whether delivery worked. | open |
| R AJ01 | Disabled membership controls can be omitted when an administrator saves a user, while the server deletes the old memberships first. | open |
| R AJ02 | The first author/requester selection is ignored; only a second change copies it into the submitted field. | open |
| R AJ03a | After a cancelled/failed submit, validation can retain fields that the user has since removed. | open |
| R AJ03b | After removing a file and retrying, validation can still think a file is selected. | open |
| R AJ04 | A perfectly valid title containing the word “undefined” is rejected as missing. | open |
| R AJ05 | The first event-group selection may not filter the event list. | open |
| R AJ06a | Different events with the same displayed name can be merged into one choice; list merging also assumes incompatible sort orders. | open |
| R AJ06b | Clearing a single-group event selection can access a nonexistent list and fail. | open |
| R AJ06c | An old topic chooser repeats the event chooser's name-based merging error. | open |
| R AJ07 | Page initialization may run before MathJax loads, causing an exception with no retry. | open |
| R AJ08 | Searching with only whitespace causes a browser exception. | open |
| R AJ09 | Overlapping status requests can read each other's response object, losing a completion update. | open |
| R AJ10a | The old hierarchical signoff widget recognizes only a narrow lowercase LIGO identity format. | open |
| R AJ10b | That old widget's sign action logs an action but does not save it. | open |
| R AJ10c | That old widget throws when its signoff tree is empty. | open |
| R AJ10d | That old widget fetches and clears a comment before its asynchronous save is known to have succeeded. | open |
| R AJ10e | The first oversized comment paste may restore an unset old value. | open |
| R AJ10f | Manually toggling the first row can address row -1. | open |
| R AJ11 | An unused trim helper removes whitespace from only one end of a string. | open |
| R AJ12a, R RJ07 | D-type document pages can generate links to the old LIGO JIRA service. The original claim that this widget has no active template was incorrect. | open |
| R AJ12b | The same widget misses an assembly title when “Assembly” is the first word. | open |
| R V01 | Author autocomplete can leave the old final character behind when replacing text from the middle of the last line. | open |
| R V02 | Literal parentheses or brackets in author-search text can break autocomplete highlighting. | open |
| R V03a | The table sorter treats a second header row as document data. | open |
| R V03b | Sorting physical rows separately can split a document's multiple rows or mis-handle merged cells. | open |
| R VL01 | An unused positioning helper subtracts top and left margins from the wrong coordinates. | open |
| R VL02 | An unused drag-position helper does not restore the element's original positioning mode. | open |
| R VL03 | An unused inline editor assumes a blur event came from a mouse, so keyboard focus changes can fail. | open |
| R VL04 | An unused collection editor treats a two-character text option as a value/label pair. | open |
| R VL05 | An unused drag animation uses the wrong arithmetic operator for its duration. | open |
| R VL06a | An unused slider discards explicitly supplied zero bounds. | open |
| R VL06b | Updating the first handle on that slider can change another active handle. | open |
| R VL06c | That slider enforces the displayed range rather than its separately configured limits. | open |
| R UI01 | Two unused jQuery UI autocomplete widgets can cancel each other's result updates. | open |
| R UI02 | The unused jQuery UI datepicker can handle one Enter-key selection twice. | open |
| R UI03 | An unused drag helper can leave iframe-blocking overlays behind after the drag ends. | open |
| R UI04 | Cancelling an unused drag operation before or after its helper exists can throw. | open |
| R UI05 | An unused sortable widget divides by zero when one grid dimension is zero. | open |
| R UI06 | An unused animation option cannot start the requested effect because it passes its settings incorrectly. | open |
| R UI07 | Finishing one unused “explode” animation removes another animation's pieces too. | open |
| R UI08 | Closing an unused modal dialog removes a different key event from the one it installed, leaving handlers behind. | open |
| R UI09 | The unused datepicker rejects digits for two numeric date formats. | open |
| R UI10a, R UI10b | An unused slider with equal bounds and a progress bar with maximum 0 divide by zero when calculating their display. | open |
| R UI10c | Changing only an unused progress bar's maximum leaves its displayed width and accessibility value stale. | open |
| R UI11 | Destroying an unused accordion can leave a forced height behind. | open |
| R UI12a | An unused named-color table displays violet as purple. | open |
| R JQ1, R RJ08 | An unused jQuery helper searches for the wrong element name. Ordinary element-selection code does not use this helper. | open |
| R JQ2 | An unused jQuery form-submission helper includes controls inside a disabled group, even though they should be omitted. | open |
| R JQ3 | An unused loader for scripts from other sites can fail without telling the calling page. | open |
| R OX03a | An unused duplicate-removal helper skips adjacent repeated entries. | open |
| R OX03b | An unused list-comparison helper reads its inputs incorrectly. | open |
| R OX06 | HTML-cleanup debug output can report the wrong unclosed tags. | open |
| R O01a | A live “single transaction” backup cannot give a coherent snapshot of MyISAM tables, files and concurrent writers. | open |
| R O01b | Compression can succeed after the database dump fails, publishing an incomplete backup as if it succeeded. | open |
| R O01c | Membership cleanup can reuse an old backup, fail when rerun, or race another writer; MyISAM locks need care. | open |
| R O02a | Rerunning bootstrap/recovery forcibly leaves the existing Swarm cluster. | open |
| R O02b | Redeploying the stack with zero web replicas can undo a manual scale-up. | open |
| R O02c | Bootstrap can overwrite mounted configuration and rebuild a supposedly frozen image tag. | open |
| R O02d | Fresh bootstrap can discard the staged content-search index when the destination directory already exists. | open |
| R O03a | Deployment could treat a failed/incomplete drift check as clean and miss nested files or symlink changes. | open |
| R O03b | Two builds with the same source commit but different base images can reuse the same tag without checking what is actually inside. | open |
| R O03c | One HTTP 200 response with certificate verification disabled does not demonstrate working private login, REST access or valid TLS. | open |
| R O03d | Building the application image does not deliver changes to separately mounted static assets. | open |
| R O04 | Short links can choose the wrong action or lose document version/format information because rewrite rules overlap or use incorrect captures. | open |
| R O05a | The permission-rebuild script does not recognize its own dry-run setting at the point where it should stop writes. | open |
| R O05b | The recertification dry run deliberately changes the first eligible document's public security and certification. | open |
| R O05c | The permission-rebuild script subtracts timestamp numbers rather than elapsed time, selecting the wrong revisions across date boundaries. | open |
| R O06 | Startup inserts passwords into sed/Perl text without safe quoting, so legitimate punctuation can corrupt configuration and prevent startup. | open |
| R RP01 | The download authorizer reads the wrong input channel for identity, risking a denied request or the wrong account being used. | open |
| R RP02 | Diagnostic pages expose or reflect request/identity information and shared temporary content. | open |
| R RP03 | Debug writers put identity/session information and mail/signoff data into files. | open |
| R RP04 | Cron shell tracing prints expanded secret values. | open |
| R RP05 | A diagnostic source file contained a Sentry DSN; copies may remain in Git history, old images or logs. | open |
| R RP06 | The adjacent infrastructure repository contains apparent nonplaceholder credentials. | open |
| R RP07, R RJ15 | Deleting a web script from source does not delete an older copy inherited from the base image. | open |
| R RP08 | The public utilities file is an independent copy, so private-side mail fixes did not automatically reach it. | open |
| R DX07 | The review claimed XML::Twig could not find the XML-search root. | open |
| R DX08 | Broad concerns about invalid dates, missing values and result handling lacked a specific demonstrated failure. | open |
| R CX09c | A jQuery UI theme/version mismatch was suggested to cause layout problems. | open |
| R CX10 | The review claimed an author-group query was missing its FROM clause. | open |
| R AJ12c | A legacy web-analytics tracker was suspected without a current caller or a specific substantial defect. | open |
| R UI12b | The old color parser accepts only a limited set of rgba forms. | open |
| R OX04a | Broad concerns about vendor key/service-wrapper errors lacked a specific active supervisor failure. | open |
| R OX04b | A sealer-history edge case was suggested without a reproducible deployed failure. | open |
| R RJ01 | Notification/watch pages were said to lack a way to identify the user. | open |
| R RJ02 | Uppercase version/date names were said to be incompatible with mail-cache fields. | open |
| R RJ03 | The review claimed the topic lookup received its options in the wrong form. | open |
| R RJ04 | The current unsign path was said to notify using stale signature data. | open |
| R RJ05 | Stale browser validation state was taken to prove successful empty uploads or unexpected signature retention. | open |
| R RJ06 | Disabled New/Modify controls on the event-deletion subform were called broken. | open |
| R RJ09 | Dormant jQuery UI bugs were treated as bugs in the active author completer. | open |
| R RJ10 | An event-list footer was suspected to break sorting under truncation. | open |
| R RJ11 | Old-browser code was considered defective without a supported-browser requirement. | open |
| R RJ12 | Prototype's handling of network status 0 was called unreliable without a relevant active caller or failure test. | open |
| R RJ13 | Broad unchecked database writes or mail errors were treated as if each were a proven incident. | open |
| R RJ14 | The content-search shell flaw was described as anonymous access. | open |
| R RJ16 | Source review was treated as proof of a production outage cause, valid secrets, current row counts, exact image compatibility or restored data consistency. | open |
| F S1 | A private file download could be checked as a blank or different account because Apache and the helper used different ways to pass the username. | fixed in release-2 |
| F S2 | Old diagnostic pages exposed request information and could display one user’s submitted markup to another user. | fixed in hotfix-release-1 (PR #1) |
| F S3 | Private-download authorization wrote browser cookies and other request environment values into a temporary log. | open |
| F S4 | Certificate reload traced expanded service-secret values into cron output. | fixed in hotfix-release-1 (PR #1) |
| F S5a | A checked-in Sentry diagnostic contained credential-bearing connection information that remains in repository history. | open |
| F S5b | The adjacent infrastructure repository tracks apparent service credentials instead of only safe example configuration. | open |
| F S5c | The scan found no additional matching secrets, and the inspected PEM files were public certificates; this cannot prove the repository has no secrets. | open |
| F S6a | A database password containing ordinary punctuation can be inserted incorrectly into generated Perl configuration and stop the application starting. | open |
| F S6b | The Apache configuration permits older TLS versions when the installed TLS library supports them. | open |
| F S6c | The public copy of the shared utility file could miss fixes made to the private copy. | fixed in hotfix-release-1 (PR #1) |
| F S7 | Deleting a CGI from Git did not remove an older copy inherited from the base image, so a new build could still ship retired endpoints. | fixed in hotfix-release-1 (PR #1) |
| F R1 | Deployment could treat a failed inspection or changed web/configuration file as clean and discard live edits. | fixed in release-2 |
| F R2a | Running the bootstrap or stack procedure against the live node can dismantle the running service or scale the web service to zero. | open |
| F R2b | The infrastructure stack still names the API release whose incomplete membership lists can cause repeated duplicate memberships during synchronization. | open |
| F R3a | Copying an agenda can lose moderators, topics or display settings and turn copied breaks into ordinary sessions because the form uses mismatched row identifiers. | open |
| F R3b | Saving an agenda containing a break can shift later sessions’ alternate locations onto the wrong rows. | open |
| F R3c | Creating an event discarded its submitted preamble text. | open |
| F R4a | Deleting a user removes some account data before touching legacy tables that may not exist, leaving a partially deleted account and dangling references. | open |
| F R4b | Deleting an author leaves other records pointing to that missing author. | open |
| F R5 | An HTTP file addition can fail, then still report success and change revision, certification and approval state. | open |
| F R6a | Replacing, removing or moving a talk can leave its document linked to the wrong event, including the old event after a move. | open |
| F R6b | Moving a talk into another session can give it the same position as an existing talk and produce an ambiguous order. | open |
| F R6c | The author-and-institution display can omit an author entered only as a talk hint because it reads the wrong variable. | open |
| F R6d | Requesting a missing file shows a warning and then redirects anyway, ending at a storage error instead of a useful application error. | open |
| F R6e | Copying an approval chain with multiple alternative signers can make one approval depend on itself. | open |
| F R7a | Two builds from the same source but different base images share a tag, and an existing image can be reused without checking which base it contains. | open |
| F R7b | Deployment declares success after one public page returns 200 while ignoring TLS verification, so login or private downloads may still be broken. | open |
| F DOC1 | A fresh bootstrap can discard the staged full-text index because it first creates an empty destination directory. | open |
| F DOC2 | Older documentation mixed historical counts with present facts, misstated public-file copies and overstated anonymous reachability of the content-search flaw. | open |
| R `codex/ce-dcc-reliability-review` | `f9d8655e3f39ff8bfcdd72bf26b670f3952e038c` | open |
| F `codex/ce-docdb-review-2026-10-13` | `381aef967a76870afe5b82874d34b4250521d223` | open |
| F `codex/ce-docdb-auth-identity` | `157bb0b123ab17f9f3de674bc5176ac3f98cdc09` | open |
| F `codex/ce-docdb-deploy-guard` | `bae8295c48dcc47e79495632cf96e30413fa7791` | open |

## Upstream status

LIGO's current DocDB 3.5.3 (opendcc/docdb) was compared against these
findings; most Critical and High items are still present there, while H8, H13
and much of L14 are fixed. See [upstream-opendcc.md](upstream-opendcc.md) for
the table and for what is worth back-porting.

## Remediation plan

**Release 1 (hot-fix, same day it can be scheduled):** C1, C2, C3, H1, H2,
H3, H4, H6, H7, H11, H12, H13, H14, H15, H16, H17, M4, M10, M11, M12, M13,
L11, L17 plus the `AcceptPathInfo Off` / `Require shib-session` part of H5. All are small, local code changes with no schema impact. Build
and deploy per [UPDATING.md](../UPDATING.md); expect a few minutes of
downtime for the container restart.

**Release 2:** H8, H9, M1 (Defang upgrade), M6, M7, M8, M14, M15, H10 (remove P&P), L25,
L9 (remove certificate scripts), L17, L18, and the `LocationMatch`
tightening in H5 after a test deploy.

**Release 3 (pull requests #4 to #11, opened 2026-10-14):** L30, L25, H10,
H9, M2, the L27/C07/C09 search-and-listing defects, the D02/D05/D06/D07/D08/
D09/MT03 add-and-edit defects with the remaining L19 items, and the L26 LIGO
leftovers. M5 was closed by the data clean-up and the REST API / provisioner
fixes on 2026-10-14. Still open after Release 3: M9 (CSRF tokens, touches
every form), M1 (Defang upgrade), M3, the `LocationMatch` tightening in H5,
D01/D03/D04 (version choice and ordering of writes; need design work),
DX09 (incomplete delete), `DocDBHelp.xml`, and the appendix rows still
marked open.

**Outside this repository:** the REST API items A1 to A4 (stop logging tokens,
check client and scope, make membership inserts idempotent, validate names,
update dependencies); the Sentry key in L17 should be revoked; Dependabot reports 8 vulnerabilities in the
ce-it-infrastructure Node dependencies.

## Coverage notes

Four areas were reviewed in parallel; the search-and-listing reviewer was
terminated mid-task by the model provider's safeguards after reporting C1.
That area was first re-reviewed directly and then given a complete second
pass by a fresh reviewer that read every file in the area in full
(`FormElements.pm`, `SearchFormElements.pm`, the topic/keyword/author/doctype
HTML modules, `Sorts.pm`, `Scripts.pm`, `Search.pm`, `SearchAtoms.pm`,
`ListBy`, all `List*` scripts, `CustomListForm`, `XSearch`, preference and
cookie scripts, `AuthorAdd`), producing H14 to H17, M12 to M15 and L22 to L29
and the correction to C1's reachability. The documents-and-files reviewer's
full report was received after an initial truncation; its findings are H1,
H2, H11, H12, H13, M10, M11, L6, L8, L21 and I1/I2 above.

## Status of fixes

Release 3 is eight independent pull requests against `main`, each with its
own regression test and verified to merge together (local integration build
`cosmicexplorer/dcc:ce-a73343327d3a`, 413 assertions passing, every script
compiling in the image): #4 L30 `UntaintParams.pm`; #5 L25 public search;
#6 H10 P&P hook removal; #7 H9 meeting-text escaping; #8 M2 `CanModify`
IDs; #9 search and listing (L27, C07, C09, footer); #10 add/edit path (D02,
D05, D06, D07, D08, D09, MT03, L19); #11 L26 LIGO leftovers.

Branch `release-2` (on top of `backport-opendcc`, PR #3) carries the fixes
taken from the independent review (see the appendix): C01 topic-hierarchy
cycles, C02 document-type IDs, the two `MeetingSQL.pm` defects (L19), D12 XML
reference deduplication, O07 landing-page link, a proper bind-value version of
**H7**, LIKE-metacharacter escaping in author/event/type matching, stricter
`\A...\z` anchors on every validator, the fail-closed `RemoteUserHasAccess`
(reading stdin, as the module requires), the drift-guard error handling, and
an offline Perl regression suite of 285 assertions runnable with the
production image's Perl.

Branch `backport-opendcc` (on top of `hotfix-release-1`) adds, from open-DCC
3.5.3: `InputValidation.pm`; escaping of every message stack and the debug
page in `ResponseElements.pm` (closes **H8**'s message-stack vector; the
direct echoes listed under H8 in individual scripts remain for Release 2);
the thirteen messages that contained markup rewritten as plain text; the two
`prefilter.tcl` robustness fixes (no more report files in `/root`, survives
`ps2ascii` failures). It also fixes the `TopicSQL.pm` hash-key defect noted in
L19. Image for that branch head is listed in the pull request.


Branch `hotfix-release-1` in this repository implements Release 1: C1, C2,
C3, H1, H2, H3, H4, H6 (file deleted), H7, H11, H12, H13, H14, H15, H16, H17,
M4, M10, M11, M12, M13, L11, L17 (file deleted), and `AcceptPathInfo Off`
plus an explicit `Require shib-session` on the private CGI location (H5,
partial). Every
modified Perl file passes `perl -c` under the production image's Perl and the
Apache configuration passes `httpd -t`; a compile check of every script in
the image found only the three pre-existing `CGI::Untaint` failures (L30).
The built images are `cosmicexplorer/dcc:ce-1658d4c7b121` (hotfix) and `cosmicexplorer/dcc:ce-58b5fb4f2582` (back-port, on top of it); each corresponds to its branch head before the final docs-only commits. The branch has **not** been deployed;
see [UPDATING.md](../UPDATING.md) for the procedure, and test the Apache
change on a staging container first if possible. Behavioural notes for the
deployer:

* Content search (`Search.pm`) now rejects unknown `filecontsearchmode` values
  by falling back to `anysub`.
* The QA-check toggle on `ShowDocument` requires administrator or certifier
  rights and derives the current state from the database.
* Non-certifiers editing a revision with `updatedb` keep its stored QA state.
* Uploaded files with names that fail the sanity check are no longer written.
* `XMLUpload` can no longer import files from server directories.
* Titles, file descriptions and file names are HTML-encoded on output. A
  title that intentionally contained HTML will now show the markup literally.
* `MigrationHelper` and `cgi-bin/test.pl` are removed from the image.
* Search date fields that are not digits are ignored; `innerlogic`/`outerlogic`
  values other than OR are treated as AND.
* Author names and event titles are escaped in the JavaScript lists; keywords
  are encoded in links.
