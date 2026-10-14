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
* **L19** Correctness defects that change behaviour: `MeetingSQL.pm:770/786`
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
* **L25** Public `Search:54-66` redirects to Google with `site:dcc.ligo.org`
  and the raw query text: every public search on the Cosmic Explorer site
  searches LIGO's DCC. Use the configured host and URL-encode the text.
* **L26** More LIGO leftovers: `AuthorHTML.pm` mail subjects say `LIGO-`;
  `ListGroups:342` and `DocDBHelp.xml` link to `dcc.ligo.org`;
  `ProjectRoutines.pm:105` hard-codes group ID 14 as the admin group;
  `ListBy:84` forces the Los Angeles time zone; `GeneralInstructions.pm:162`
  links to Fermilab.
* **L27** Runtime defects in this area: `SearchAtoms.pm:327-332` uses the key
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
* **L30** Three scripts cannot compile in the production image because the
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

**Release 3:** M9 (CSRF tokens, touches every form), M2, M3, M5 (data
clean-up plus REST API change in ce-it-infrastructure), the L19 defects, and
the LIGO leftovers.

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
