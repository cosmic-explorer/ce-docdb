# Administration, user access and the client side

Code: `AdministerHome`, `AdministerForm`, `AdministerElements.pm`,
`*Administer`, `*AdministerForm`, `GroupHTML.pm`, `SecurityHTML.pm`,
`ConfigSQL.pm`, `MiscSQL.pm`, `Certificate*`, `BulkCertificateInsert`,
`UserAccessApply`, `MigrationHelper`, the public-instance files and
`usr1/www/html/DocDB/Static/js/`.

## Two factors for administration

Every admin *processing* script (`AuthorAdminister`, `InstitutionAdminister`,
`DocTypeAdminister`, `JournalAdminister`, `KeywordListAdminister`,
`KeywordGroupAdminister`, `GroupAdminister`, `EmailAdminister`,
`TopicAdminister`, `EventAdministerForm`, `ExternalDocDBAdministerForm`,
`BulkCertificateInsert`) opens its own DBI connection with the `admuser` and
`password` fields submitted in the form (`AdministratorPassword()` in
`AdministerElements.pm`) rather than the configured account; if MySQL refuses
the login the page aborts. Only then does it call `CanAdminister()`. So an
administrator must both be in a group with `CanAdminister` and know a MySQL
account password that has write access to `dcc_docdb`. The *form* pages
(`AdministerHome`, `AdministerForm`, `KeywordAdministerForm`,
`GroupAdministerForm`, `EmailAdministerForm`) connect read-only and refuse
to render for non-admins. All SQL in these scripts uses placeholders, and
because the password travels in the POST, cross-site request forgery
against them is impractical. Small `*AdminDisable.js` scripts enable and
disable form fields depending on the New/Modify/Delete radio button.

## What can be administered

| Area | Script | Notes |
|------|--------|-------|
| Authors | `AuthorAdminister` | name, institution; delete cascades `RevisionAuthor` |
| Institutions | `InstitutionAdminister` | delete refused while authors remain |
| Document types | `DocTypeAdminister` | `ShortType`/`LongType`; `NextDocNumber` handled in `MiscSQL.pm` |
| Journals | `JournalAdminister` | |
| Keywords, keyword groups | `KeywordListAdminister`, `KeywordGroupAdminister` | `KeywordGrouping` link table; `-1` means "remove all groups" |
| Topics | `TopicAdminister` | form and processor in one; maintains `TopicHierarchy`; `admforce` to delete topics with children |
| Events, event groups | `EventAdministerForm` | delete events, edit group descriptions |
| External DocDBs | `ExternalDocDBAdministerForm` | cross-reference targets: project, description, public/private URLs |
| Security groups | `GroupAdminister` | create with CanView/CanCreate/CanAdminister (CanConfig is always written as 0); maintain the one-level `GroupHierarchy`; delete counts and removes `RevisionSecurity`, `RevisionModify`, `MeetingSecurity`, `MeetingModify` and `UsersGroup` references unless forced |
| Personal accounts | `EmailAdminister` | delete a user and their notifications, reset the legacy password, toggle `Verified`/`CanSign`, add or clear `UsersGroup` memberships. This is how an admin grants a group, including an admin group, by hand |

`GroupHTML.pm` prints parent/child/permission summaries. `SecurityHTML.pm`'s
`SecurityScroll` renders the group pickers; with `-hierarchy` it lists
groups with `DisplayInList = 1`, otherwise `DisplayInList = 2` groups plus,
in kerberos mode, the groups the current user belongs to.

## User access applications (legacy)

`CertificateApplyForm`, `CertificateUtilities.pm`, `UserAccessApply` and
`BulkCertificateInsert` are a certificate-era flow from Fermilab: read the
client certificate's CN, look it up in `EmailUser.Name`, let the person
request groups, insert an unverified `EmailUser` plus `UsersGroup` rows, and
e-mail the webmaster for approval. `CertificateInstructions.pm` is
Fermilab-specific help text. Under Cosmic Explorer's
`$UserValidation = "kerberos"` none of this produces a usable login: identity
is `RemoteUser.RemoteUserName`, and those rows are written by the external
REST API, not by these scripts. Client certificates are not even enabled in
`ssl.conf`. The review recommends removing these scripts.

`MigrationHelper` is a LIGO one-off that force-publishes `Public_Pending`
documents of a hard-coded topic and document type. It has no authorization
check and should be deleted (see the review).

`ConfigSQL.pm` stores per-project settings in `ConfigSetting`, used today
only for custom-field layouts keyed by event, topic or document type.
`MiscSQL.pm` holds journal, document-type (including the per-year
`NextDocNumber` reset) and `DocumentFile` lookups; files whose `Description`
contains "delete", "remove" or "ignore" are treated as deleted.

## The public instance

`/usr1/www/cgi-bin/DocDB` holds 79 symlinks into the private directory for
read-only scripts and modules only (no admin, certificate or migration
scripts), plus its own `SiteConfig.pm` (`$Public = 1`, empty read-write
credentials, public `$cgi_root`), `ProjectGlobals.pm` (no P&P review or
review states, `HomeMaxDocs` 50), `CGIInclude.pm` (searches the public
directory first) and a slightly different `DocumentDatabase` home page.
`Params/Validate*.pm` is a vendored Params::Validate 0.89 that nothing uses.

## Client-side JavaScript

`usr1/www/html/DocDB/Static/js/`: `serverstatus.js` polls `$ServerStatusUrl`
(`serverstatus.sh`, a ksh CGI returning `serverstatus.html`) and writes the
response into `#serverstatus`; `PopUps.js` opens help windows; `Throttle.js`
reads `maxdocs` from the URL; `TopicChooser.js`/`EventChooser.js` filter
dependent selects (the event data is emitted by `Scripts.pm`); `auto.js` and
`Autocompleters.js` give jQuery autocomplete over author and signer lists;
`ValidateForm.js` diff-checks the document form and warns when changes will
reset sign-off or public state; `Signatures.js` is the LIGO signature editor
whose AJAX endpoints no longer exist (dormant); `ICSLink.js` adds a LIGO JIRA
link to every D-type document page; `MathJaxToggle.js` toggles MathJax;
`ScrollListSelector.js` hard-codes group IDs 1 and 43 as Public_Pending and
Obsolete. Prototype 1.7, script.aculo.us, jQuery 1.8 and jQuery UI are
bundled. MathJax itself is loaded from cdnjs.
