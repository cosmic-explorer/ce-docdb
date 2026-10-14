# Assessment of the Codex review branch (2026-10-14)

Branch: `codex/ce-docdb-unified-review-2026-10-14` (41 commits by Geoffrey
Lovelace, produced with GPT Codex, briefly pushed to `main` and then moved to
a branch). Assessed by checking out the branch, reading the complete code
diff against `main`, compiling every changed Perl file with the production
image's Perl, running its test suite, and testing its one contested claim in
an isolated container. Nothing was deployed.

## Summary

The branch has three distinct parts of very different quality.

1. **A re-implementation of Release 1** (`hotfix-release-1`) as 24
   per-finding commits, each with an offline regression test. The code is
   byte-for-byte the hotfix branch's code in almost every file. Net value:
   the tests (284 assertions, all passing under the production Perl) and one
   genuinely better fix (H7).
2. **Nine new fixes and findings** of its own. Seven are correct and worth
   taking; one is debatable; **one would take down private file downloads
   in production** and must not be merged as written.
3. **1.2 MB of review archive** (55 files under `review/`, plus an 855-line
   unified report and verbatim copies of earlier reviews), produced for the
   model's own bookkeeping. Most of it should not live in this repository.

## The dangerous change: S1, `RemoteUserHasAccess`

Commit `9b7ac69` rewrites the file-download authorizer to read the
authenticated username from the `USER` environment variable instead of
standard input, exiting 1 (deny) if `USER` is empty. The rationale, from
`docs/auth-identity-hotfix.md`, is that mod_authnz_external's `environment`
method "does not write the username to this program's stdin", citing the
Debian 3.3.2 source. The validation was a stubbed harness on a Mac; the
document itself says the frozen image and Docker were unavailable.

That reasoning is wrong for the module we run. Tested in an isolated
container from `cosmicexplorer/dcc:3.3.0` (mod_authnz_external 3.3.1,
Apache 2.4.6) with a probe script recording both channels:

| Call | `USER` env | stdin |
|------|-----------|-------|
| authentication (`DefineExternalAuth ... environment`) | set | empty |
| **group check** (`DefineExternalGroup ... environment`) | **empty** | `username⏎groupname⏎` |
| group check (`pipe`) | empty | `username⏎groupname⏎` |

For group checks, which is how `dcc-dev.conf` wires `RemoteUserHasAccess`,
the module ignores the method keyword and always uses stdin. This matches
the production evidence: the container's debug log shows thousands of
invocations with a non-empty stdin username and none empty. With the Codex
version deployed, `USER` is empty on every call, the script exits before
querying anything, and **every direct document download by every logged-in
user is denied**.

The commit also adds things that are good and should be kept in a corrected
version: fail closed on a failed database connection, require a positive
integer revision and user ID, bind the username with `=` (already in
Release 1), and refuse an ambiguous identity if two `RemoteUser` rows share a
name. The corrected script should read stdin as before (optionally accepting
`USER` when present) and keep those checks. `tests/test-authorizer.py`
encodes the wrong assumption and would need the same correction.

## New findings that are correct

| ID | What | Verdict | Action taken |
|----|------|---------|--------------|
| S7 | Deleting a file from the repository does not remove it from the image; Docker COPY merges with the base layer. `MigrationHelper` and `test.pl` were still present in the hotfix image. | **Correct and important.** My image comparison compared files present in both images and so could not notice a file that should have been absent. | Explicit `RUN rm` added to the hotfix Dockerfile; verified absent in the rebuilt image. |
| S2 | `auth.sh`, `test.sh`, `remote_user.sh` are LIGO-era diagnostics that write the request environment and stdin to `/tmp` or echo the identity to the browser; `403.html` includes one via SSI. | Correct. | Removed in the hotfix branch and in the image. |
| S4 | `renew-certs.sh` runs with `set -x`, so the two exported secrets are printed into the cron job's output. | Correct. | Removed in the hotfix branch. |
| S6 | The public instance's `Utilities.pm` is a real file, not a symlink, and did not receive the Release 1 mail and debug-file fixes. | Correct. | Public copy synchronised in the hotfix branch. |
| C01 | `TopicAdminister` lets a topic become its own ancestor; `TopicAndSubTopics` then recurses forever. The fix adds cycle-safe traversal, a parent validation (`TopicParentError`) and path tracking in the topic tree renderer. | Correct and well done. | Recommend cherry-picking `248175c`. |
| C02 | `DocTypeHTML::DocTypeSelect` submitted labels where IDs were expected (my L27). Fixed with `-values`/`-labels`. | Correct. | Recommend cherry-picking `9b8f81a`. |
| MT01/MT02 | `MeetingSQL.pm` preamble typo and wrong separator deletion (my L19). | Correct. | Recommend cherry-picking `26ae73a`, `ac3b5f3`. |
| D12 | `XMLOutput::XRefByXMLOut` deduplicated incoming references across all exported documents instead of per document. | Plausible; the fix is minimal and the test passes. | Recommend cherry-picking `2125a0a`. |
| O07 | The discovery landing page's recent-documents link had `<body>` where `&amp;` belonged (an artefact of the infrastructure Dockerfile's `sed`). | Correct. | Recommend cherry-picking `91f0dfa`. |
| H7 | Replaces my backslash-escaping with proper bind values through `TextSearch` (adds a `$BindValues` array, escapes LIKE metacharacters, binds REGEXP patterns). Also escapes LIKE metacharacters in `MatchAuthor`, `MatchEvent`, `MatchDocType`. | **Better than my fix**; this is the right design. | Recommend adopting `e9ab5c7` in place of my H7 change. |

## Changes I would not take as written

* **R1, deploy guard** (`a2b057b`): `check-drift.sh` now reports
  `SiteConfig.pm` on every run because its startup password substitution
  "cannot be distinguished from a hand edit". In practice that makes every
  deploy exit 1 and require `FORCE=1`, which trains operators to type
  `FORCE=1` reflexively and defeats the guard. Keep the exclusion, or
  compare the file against the committed version with the two password
  lines masked. The other parts of R1 (fail on inspection errors, `exit 3`,
  nested webroot matching) are good and worth keeping.
* **Dedupe SQL header** (`c0628c4`): adds a "maintenance window required"
  warning. The DELETE and ALTER on a 36k-row MyISAM table take seconds and
  block only `UsersGroup`; pausing the provisioner during the run is sensible,
  a maintenance window is overstated. Harmless either way.
* **The `review/` archive and the unified report.** Byte-identical copies of
  my review, JSON coverage files, probe scripts and three layers of
  "peer review" of its own output. Keep `docs/review-unified-2026-10-14.md`
  if its finding tables are wanted, but the archive belongs in a separate
  branch or a wiki, not alongside the application code.
* **Python tests** require Python 3.8+ and fail on this host (3.6). The Perl
  tests and the shell test run cleanly.

## Quality observations

* Every changed Perl file compiles under the production image's Perl (the
  only failure is the pre-existing `CGI::Untaint` module absence).
* The per-finding commit structure and tests are a real improvement over
  the two-commit hotfix branch and would make a good template for Releases
  2 and 3.
* The work is thorough and mostly careful, but it treats source reading of
  a different module version as proof and ships a change that was never
  exercised against the real module. That is the one pattern to watch for
  in machine-generated patches: confident, well-documented, and untested
  against the thing that actually runs.

## Recommendation

Do not merge the branch wholesale. Instead:

1. Merge PR #1 and PR #2 (already updated with S7, S2, S4, S6).
2. Cherry-pick onto a `release-2` branch: `248175c` (C01), `9b8f81a` (C02),
   `26ae73a` and `ac3b5f3` (meetings), `2125a0a` (D12), `91f0dfa` (O07),
   `e9ab5c7` (H7 binding), and the `check-drift.sh` error-handling half of
   `a2b057b`, each with its test.
3. Rewrite S1 to read stdin (keeping the fail-closed checks) and test it
   against the real module as above before it goes anywhere near production.
4. Ask Geoffrey to drop `review/` from the branch or move it elsewhere.
