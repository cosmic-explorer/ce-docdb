# What the open-DCC (DocDB 3.5.3) code base offers us

Philippe Grassia maintains [opendcc/docdb](https://git.ligo.org/opendcc/docdb)
on git.ligo.org: LIGO's current DocDB (version **3.5.3**, October 2025)
with LIGO-specific parts removed (P&P review, E-Traveler, user
provisioning), a CMake build, a Docker development environment with LDAP and
MailHog, and a Playwright test suite. Our running code is LIGO's **3.3.0**
from 2019. This page records what a comparison found, what is worth taking
without migrating, and what is not.

Compared on 2026-10-13 against this repository's `hotfix-release-1` branch.

## How far apart the two trees are

Same 182-entry layout. Of the files common to both, 61 are byte-identical
and about 100 differ. Files only upstream: `InputValidation.pm`,
`DebugLog.pm`, `SignoffNotifications.pm`, `DocumentTree`,
`CallDocumentTree`, `CheckRevisionSignature`, `XMLUpdate`. Files only here:
`ProcessPNPReview`, `DocumentReviewSQL.pm`, `EmailLogin`, a few LIGO helper
shell scripts, and our Cosmic Explorer `SiteConfig.pm`.

The database schema is the same except for one column upstream added:
`DocumentRevision.ParallelSignoff` (parallel versus serial sign-off chains).
Upstream's `RevisionSQL.pm` writes that column unconditionally, so any
back-port of `RevisionSQL.pm` or the sign-off modules needs
`ALTER TABLE DocumentRevision ADD COLUMN ParallelSignoff ...` first.

The biggest functional changes upstream are in sign-offs (parallel
sign-offs, about 20 new routines in `SignoffSQL.pm` and
`SignoffUtilities.pm`, `SignoffNotifications.pm` for the e-mails,
`CheckRevisionSignature`), the file list rendering (`FileHTML.pm`, 886
changed lines), `ProcessDocumentAdd`, meetings, and administration forms. We
do not use sign-offs, so most of that is of no immediate value.

## Security: what 3.5.3 fixed, and what it did not

3.5.3's headline change is `InputValidation.pm` (1,900 lines, standalone,
depends only on `HTML::Entities`): validators (`validate_id`,
`validate_allowlist`, `validate_date_string`, `validate_document_id`, ...),
sanitisers, `escape_html`/`escape_attr`/`escape_url`, `get_single_param`
(forces scalar context on `$query->param`) and `validate_or_exit` (validate
all parameters up front, abort on failure). It is used in 60 scripts, 444
`get_single_param` and 153 `escape_html` call sites. `DebugLog.pm` is a
small file logger meant to replace ad-hoc `/tmp` debug writes.

Checked against the findings in [security-review.md](security-review.md):

| Our finding | Status in opendcc 3.5.3 |
|-------------|-------------------------|
| C1 content-search mode reaches a shell | **still present** (`Search.pm:459-465`, identical code) |
| C2 `ShowDocument` QA toggle unauthorised | **still present**; `qastat` is now allow-listed to 0/1, but no authorization check |
| C3 `SignRevision` guard commented out | **still present** (`#EndPage();` at line 165) |
| H1 upload names reach a shell | **still present** (`FileUtilities.pm:96`, `DocumentUtilities.pm:135`) |
| H2 cross-reference project SQL | **still present** (`XRefSQL.pm:89`) |
| H3 manual author names in SQL | **still present** (and without our middle-initial patch) |
| H4 identity lookup by interpolated `LIKE` | **still present** (`SecuritySQL.pm:195,210`) |
| H6 `MigrationHelper` | **still present** |
| H7 backslash not escaped in text search | **still present** |
| H8 message stacks printed raw | **fixed**: `ResponseElements.pm` escapes every message |
| H9 meeting/session text unescaped | **still present** (`MeetingHTML.pm`, `CalendarHTML.pm` have no escaping; `SessionModify` has some) |
| H12 `qastat` interpolated into SQL | **still present** (`ProcessDocumentAdd:842`), though the value is now validated |
| H13 title unescaped | **fixed** in `PrintTitle`; `DocumentLink` not checked |
| H17 keywords in links unencoded | **still present** |
| M1 HTML::Defang 1.04 | **still present**, same vendored version, callback still unwired |
| M2 `CanModify` ID-type confusion | **still present** (`Security.pm:216-219`) |
| M4 `/tmp` debug files | **mostly still present**, and `RevisionSQL.pm:322` adds a new unconditional `/tmp/debug` write |
| L1 `URLify` links to `.ligo.org` | **still present** (correct for LIGO) |
| L14 admin forms unescaped | **largely fixed** (`GroupAdminister` 13, `AuthorAdminister` 10, `EmailAdministerForm` 8 escape sites) |
| L30 `CGI::Untaint` missing | module still used by `ListEventsBy`, `BulkCertificateInsert` (their image installs it) |

Conclusion: the upstream work is a systematic output-encoding pass on the
CGI entry points, which is valuable, but it did not touch the authorization
and command/SQL construction defects that make up our Critical and High
findings. Our hot-fix branch is ahead of upstream on those, and they should be
reported upstream (Philippe Grassia; the LIGO DCC team for DOCDB-GIT) so that
the fixes do not have to be re-applied after a future migration.

## Worth taking now (no migration)

In rough order of value against effort:

1. **`ResponseElements.pm` escaping (H8).** Done on branch
   `backport-opendcc`: every error, warning, action and debug message is
   escaped. Thirteen messages that relied on markup were rewritten as plain
   text.
2. **`InputValidation.pm` itself.** Done on the same branch: the module is
   in the tree (with a public-instance symlink) and should be used for new
   fixes (`validate_id`, `validate_allowlist`, `escape_html`, `escape_attr`)
   instead of ad-hoc regexes. Not imported: the per-script `validate_or_exit`
   rewrites, which also carry the 3.4/3.5 functional changes and the
   `ParallelSignoff` dependency. Note that `escape_html` deliberately does not
   encode a bare `&` (to avoid double-encoding entities) and encodes `=`.
3. **`isActiveUser` (`SecuritySQL.pm`).** A clean helper for "is this
   EmailUser's Author active", which our `CanAccess` does inline.
4. **Upstream's Playwright test suite** (`tests/integration/playwright`,
   pytest with page-object models and MailHog). It targets their Docker
   environment with LDAP test users, so it would need a Shibboleth-less
   test instance of ours to run against; it is the only existing end-to-end
   test corpus for DocDB and would make our hot-fix releases far safer to
   deploy.
5. **The GLIMPSE indexing scripts** (`dcc-glimpse-files/bin`). On
   inspection this is mostly a new *pipeline*, not a better prefilter:
   upstream's `glimpse-incr.sh` is a Redis-queue worker that sends PDFs to a
   Tika server and runs under systemd, `glimpse-init.sh` builds partitioned
   indexes, and `glimpse-query.sh` reads them. None of that fits our
   supervisord container without adding Redis and Tika to the stack.
   `prefilter.tcl` itself differs from the 2019 copy in our image by ten
   lines, two of which are real fixes (no report file written to `/root` on
   every run; a PostScript file that crashes `ps2ascii` no longer aborts the
   indexer). Those two are back-ported on branch `backport-opendcc`; the
   pipeline is not. The prefilter also calls `catdoc`, `h5dump` and
   `ps2ascii`, which the image does not have, so Office, HDF5 and PostScript
   content is not indexed today; installing those packages in the image would
   be a cheap improvement.
6. **`XMLUpdate`**: batch metadata update of many documents by uploading
   XML. Useful for administrators; self-contained like `XMLUpload`.
7. **`DocumentTree`/`CallDocumentTree`**: a document-tree view (cross
   reference graph). Self-contained; cosmetic value.
8. **Docker/Apache approach**: upstream templates `SiteConfig.pm` per
   instance and configures Apache per `INSTANCE_TYPE`; its `dcc.conf` uses
   the same external-group trick for `/DocDB` as ours. Nothing there fixes
   our H5; it is a cleaner organisation of the same ideas and a reference for
   when the infrastructure Dockerfile is rewritten to build from this repo
   instead of from the qcow2 image.

## Not worth taking, or take with care

* **Sign-off modules** (`SignoffSQL.pm`, `SignoffUtilities.pm`,
  `SignoffHTML.pm`, `SignRevision`, `SignatureReport`,
  `SignoffNotifications.pm`, `RevisionSQL.pm`): require the `ParallelSignoff`
  column, carry the C3 defect unchanged, and we have no sign-offs in use.
* **`RevisionSQL.pm`** specifically: new unconditional `/tmp/debug` write at
  line 322.
* **`AuthorSQL.pm`**: upstream lacks the Cosmic Explorer middle-initial
  matching patch; taking theirs would regress author matching and reintroduce
  H3.
* **`ListBy`, `Search.pm`, `ShowDocument`, `ProcessDocumentAdd`**: upstream
  versions add escaping but keep C1, C2, H7, H11, H12; our hot-fix versions
  are the safer base. Merge upstream escaping into ours, not the reverse.
* Anything with `DocumentReviewSQL`/P&P references is already gone upstream,
  which matches our plan to remove `ProcessPNPReview`.

## If a full migration is ever considered

The repository documents its own import process
(`docs/MigrateFromDOCDB.md`), has unit tests (`tests/unit/perl`, including a
compile test of every script) and integration tests, and a reproducible
build. A migration would mean: apply the `ParallelSignoff` schema change,
re-apply the Cosmic Explorer customisations recorded in
[code-layout.md](code-layout.md) (project names, host, `$SecureMainPage`,
middle-initial matching, home-page edits, Apache proxies and allow-list),
carry over every Release 1 to 3 fix from our review that upstream still lacks,
and rebuild the image from source rather than from the Caltech qcow2. The
Dockerfile in this repository would then layer on an image built from
upstream instead of on `cosmicexplorer/dcc:3.3.0`.
