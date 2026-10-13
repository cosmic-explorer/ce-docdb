# Meetings, sign-offs and e-mail notifications

Code: `Meeting*.pm`, `MeetingModify`, `SessionModify`, `DisplayMeeting`,
`ListAllMeetings`, `ListEventsBy`, `ShowCalendar`, `CalendarHTML.pm`,
`Talk*.pm`, `ConfirmTalkHint`, `EditTalkInfo`, `ShowTalkNote`,
`Signoff*.pm`, `SignRevision`, `SignatureReport`, `SignoffChooser`,
`ProcessPNPReview`, `DocumentReviewSQL.pm`, `MailNotification.pm`,
`NotificationSQL.pm`, `Email*.pm`, `SelectEmailPrefs`, `EmailCreate`,
`WatchDocument`. Tables are described in [database.md](database.md).

## Events and meetings

An **EventGroup** (for example "Consortium Meetings") contains
**Conferences**, which is the table name for an event: title, long
description, dates, location, URL, preamble/epilogue text and a
`ShowAllTalks` flag. An event has an ordered agenda made of **Sessions**
(title, description, start time, location, moderators, topics) and
**SessionSeparators** (breaks); their order lives in `MeetingOrder`. Each
session's agenda is in turn made of **SessionTalks** (hint title, note, time,
`DocumentID`, `Confirmed`) and **TalkSeparators**, ordered by `SessionOrder`.
Moderators and topics are stored in `Moderator` and `EventTopic`, keyed by
event or session. Documents are tied to events either explicitly through
`RevisionEvent` (chosen on the document form) or through a confirmed
SessionTalk.

### Creating and editing

* `MeetingModify` creates or edits the event shell and its list of sessions
  and breaks. It posts to itself; `mode=copy` with `offsetdays` clones an
  event to a later date.
* `SessionModify` edits one session and its talks. In `singlesession` mode it
  creates an event and its only session in one form; the "+" links on the
  calendar use this.
* `EditTalkInfo` and `ShowTalkNote` are pop-ups for a single agenda entry.
* `DisplayMeeting` renders an event (session list or all talks), a session,
  or a break. `ListAllMeetings`, `ListEventsBy` (by topic or moderator) and
  `ShowCalendar` (year/month/day, via `CalendarHTML.pm`) are the index pages.
  `DisplayMeeting` and `ListAllMeetings` are also linked into the public
  instance.

### Meeting security

Document security does not apply to meetings. `MeetingSecurity` (view) and
`MeetingModify` (modify) hold group IDs per conference; an empty list means
viewable or modifiable by everyone. `CanAccessMeeting` and
`CanModifyMeeting` in `MeetingSecurityUtilities.pm` compare the user's
groups (including parents in the group hierarchy) against them;
`CanCreateMeeting` is `CanCreate()` in the private instance. New meetings
default to the creator's groups. Access is checked at the top of
`DisplayMeeting` and inside `EventLink`, but not in `SessionLink` (see the
[security review](security-review.md)).

### Talk hints

An agenda entry entered before its document exists carries hints: a title,
author hints (`AuthorHint`) and topic hints (`TopicHint`). Whenever a session
is displayed or edited, `ReHintTalksBySessionID` collects candidate documents
(revisions dated within `$TalkHintWindow` days of the event, or explicitly
tied to it), scores each with `TalkMatches` (authors, topics and a fuzzy
title match) against `$TalkMatchThreshold`, and writes the best `DocumentID`
into the SessionTalk as an unconfirmed match. A meeting modifier confirms a
match (`ConfirmTalkHint`, or the Confirm checkbox), which sets `Confirmed=1`
and adds a `RevisionEvent` row. "Reserve" creates a placeholder document for
the talk.

## Sign-offs

A document revision can carry a **Signoff** chain: each Signoff has one or
more **Signatures** (`EmailUserID`, `Signed` flag) and `SignoffDependency`
rows forming a sequential list (the first Signoff has `PreSignoffID` 0).
`SignoffStatus` is Signed, Ready (all prerequisites signed) or NotReady;
`RevisionStatus` recurses from the root signoffs to Approved, Unapproved,
Unmanaged (no signoffs) or Demanaged. Signers are `EmailUser` accounts with
`CanSign = 1`, resolved from the Shibboleth identity through `RemoteUser`.

`SignoffHTML.pm` prints the signature block on the document page with a
"Sign Document" form (a GET to `SignRevision`) for the slot matching the
current user. `SignRevision` flips `Signed` and calls `NotifySignees`. Adding
files to a revision unsigns it (`UnsignRevision`); new revisions copy the
sign-off list (`CopyRevisionSignoffs`). Approval status feeds the QA and
public-release buttons in `RevisionHTML.pm`.

`$UseSignoffs` is on in the private `SiteConfig.pm`, but the `Signoff` table
is empty in production, so the feature is configured but unused.

### Publication & Presentation (P&P) review hook

`ProcessPNPReview` and `DocumentReviewSQL.pm` are a LIGO add-on. For
"reviewable" document types (presentations with an abstract, publications
with files; `@ReviewableDocTypes` in `ProjectGlobals.pm`) a button exports
the document's XML with `ncat` to the P&P host and redirects the user there;
`DocumentReview` stores the returned state. The host is still
`pnp-dev.ligo.org`, so for Cosmic Explorer this feature is both non-functional
and undesirable; the review recommends removing it.

## E-mail notifications

Users opt in via `SelectEmailPrefs` (rows in `Notification`: Immediate, Daily
or Weekly, per Topic, Author, Event, EventGroup, DocType, Keyword, individual
Document, or AllDocuments) or `WatchDocument` (an Immediate per-document
row). On add, update or reserve, `MailNotices` in `MailNotification.pm` calls
`UsersToNotify`, which collects matching `EmailUserID`s, drops anyone who
fails `CanAccess`, and sends one plain-text message (title, ID, URL, authors,
topics, events, abstract) through `send_email` in `Utilities.pm` (SMTP to
`smtp-host.syr.edu`, From `Cosmic Explorer Document Database
<dcc-help@cosmicexplorer.org>`). Signature events mail the signatories whose
slot just became Ready and, on full approval, the Immediate subscribers,
signers, authors, updaters and the submitter. Daily and Weekly digests are
intended to be produced by a separate cron job, which is not present in the
image; only Immediate notifications are actually delivered.

Known gap: under the `kerberos` validation mode `SelectEmailPrefs` and
`WatchDocument` do not resolve the Shibboleth user to an `EmailUserID`, so
preference changes silently do nothing and WatchDocument errors. See the
[security review](security-review.md) for details and other defects in this
area.
