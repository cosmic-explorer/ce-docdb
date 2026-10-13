# Home page, listing and search

Code: `DocumentDatabase`, `ListBy`, `Search`, `SearchForm`, `Search.pm`,
`SearchAtoms.pm`, `SearchModes.pm`, `SearchFormElements.pm`, `XSearch`,
`CustomListForm`, `List*`, `Statistics`, `Sorts.pm`, `ResponseElements.pm`,
`FormElements.pm`, `Scripts.pm`, the `Topic*`, `Keyword*`, `Author*`,
`DocType*` modules, `SelectPrefs`/`SetPrefs`, `SelectGroups`/`SetGroups`,
`ShibLogout`.

## Home page

`DocumentDatabase` (aliased as `/dcc`) prints the welcome text, a quick
search box, links to the list pages, and a table of documents modified in
the last `$HomeLastDays` days (2) up to `$HomeMaxDocs` (500 private, 50
public). The public copy differs only in a few links. Every document row
printed anywhere goes through `DocumentTable`/`PrintDocumentTable` in
`DocumentHTML.pm`, which calls `CanAccess` per document and skips those the
caller may not see; this per-row filtering, not the SQL, is what enforces
access in all listings.

## ListBy

`ListBy` is the general "documents by X" page. It takes exactly one of
`days` (optionally `uncertified`, `latest`, `x0filter`), `topicid`,
`authorid`, `typeid`, `eventid`, `eventgroupid`, `keyword`, `groupid` or
`group`, `allpubs`, `alldocs`, and builds one SELECT for `DocumentID`s with
placeholders for the values; two code paths assemble the query string from
fixed fragments before `prepare`. Results are then rendered by the document
table with access filtering. `maxdocs`, `sortby` and `reverse` control the
table. In production the top of `ListBy` HTML-encodes every incoming
parameter (a hot-fix applied in the container and now in this repository).

## Search

`SearchForm` renders the advanced form; `Search` (and the simple search box)
submits to `Search.pm::SearchDocuments`. The search is a set of independent
"atoms", each producing a list of revision or document IDs, combined with
`innerlogic` (within a field) and `outerlogic` (between fields):

* text fields (`titlesearch`, `abstractsearch`, `keywordsearch`,
  `revisionnotesearch`, `pubinfosearch`, `filesearch`, `filedescsearch`)
  become `LOWER(field) like "%word%"` or `REGEXP` word-boundary atoms built
  by `SearchAtoms.pm::TextSearch` and interpolated into a SELECT (see the
  [security review](security-review.md), H7);
* `numbersearch` matches document numbers and aliases;
* authors (`authors`, `authormanual`), requesters, topics (with
  `includesubtopics`), document types, events and event groups are ID
  searches done with placeholders in `AuthorSearch`, `TopicSearch`,
  `EventSearch`;
* date windows (`beforeday`...`afterday`) restrict revision dates;
* `filecontsearch` with `filecontsearchmode` runs the external GLIMPSE
  full-text engine (`$ContentSearch`, a Tcl wrapper around `glimpse`) and
  parses the matching file paths back into document IDs (review finding C1).

The simple search (`simple=1`, `simpletext`) runs the same atoms over
number, title, abstract, keywords, authors, topics and file names and ranks
documents by `%SearchWeights`. Results pass through `ValidateRevisions`
(drops obsolete revisions) and the access-filtered document table.
`XSearch` is an XML variant used by external tools.

## Other list pages

`ListAuthors`, `ListAuthorGroups`, `ListTopics`, `ListTypes`,
`ListKeywords`, `ListGroups`, `ListGroupUsers`, `ListEmailUsers`,
`ListManagedDocuments` (documents with sign-offs), `ListAllMeetings`,
`ListEventsBy`, `Statistics` (counts). `CustomListForm` lets a user choose
the columns of the document table; the choice is stored in cookies.

## Classification model

* **Topics** form a tree (`Topic`, `TopicHierarchy`); `TopicUtilities.pm`
  provides `TopicAndSubTopics`, `FetchTopicParents`; `TopicHTML.pm` renders
  scroll lists and the topic tree. `$Preferences{Topics}{MinLevel}{Document}`
  controls the minimum depth a document may be filed at.
* **Keywords** are flat with optional groups (`Keyword`, `KeywordGroup`,
  `KeywordGrouping`); revisions store keywords as free text in
  `DocumentRevision.Keywords`.
* **Authors** (`Author`, `Institution`) are linked to revisions through
  `RevisionAuthor`; author *groups* (`AuthorGroupDefinition`,
  `AuthorGroupList`, `RevisionAuthorGroup`) let a whole collaboration be
  listed. Manual author entry (`authormanual`, "Last, First M") is resolved
  by `AuthorSQL.pm::ProcessManualAuthors` with an exact then fuzzy match,
  split into first name and middle initials by the Cosmic Explorer patch.
* **Document types** (`DocumentType`) supply the letter prefix of the alias
  and the serial counter `NextDocNumber`; `DocumentTypeSecurity` can hide
  types from groups.

## Preferences and self-imposed limits

`SelectPrefs`/`SetPrefs` store per-browser cookies for the document form
(default author, upload method and count, topic and author list modes, date
override, default view and modify groups). `SelectGroups`/`SetGroups` store
the `groupids` cookie that restricts which of the user's groups are used
(`Cookies.pm`, `Security.pm::FindUsersGroups`). `ShibLogout` redirects to
the SP's `/Shibboleth.sso/Logout`. `EmailLogin` is the legacy
username/password login for notification accounts and is not used under
Shibboleth.

## Output helpers

`ResponseElements.pm` prints the error, warning and action stacks and
`EndPage`; `FormElements.pm` provides the form controls; `Sorts.pm` holds the
comparison routines used by every table; `Scripts.pm` emits the JavaScript
data for the event chooser. None of these escape HTML themselves; callers
are responsible (see review finding H8).
