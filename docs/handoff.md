# Handoff: state of work as of 2026-10-14

For a new maintainer or a fresh Claude Code session. Everything below is
verifiable from the repository, GitHub and the host; nothing is deployed
unless stated.

## Production state

**Deployed 2026-10-14 (afternoon, US Eastern):** `dcc_dcc` now runs
`cosmicexplorer/dcc:ce-cef36b92168d`, which is `main` at the merge of PRs #1,
#2 and #3 (Releases 1 and 2 plus the independent-review fixes). Verified after
the deploy: service spec references the tag, `check-drift.sh` reports no
drift, supervisord shows cron/shibd/apache2 running, the five retired CGIs are
absent, the fixed files in the container match the repository, no `/tmp`
debug files are being created, the public home page answers 200. The private
entry point returns 500 after any restart while shibd verifies the InCommon
IdP aggregate at 100% CPU; on 2026-10-14 that took 30 minutes (14:58 to
15:28 local) before the login redirect returned. Expected; it clears on its
own, and the public instance works throughout.
A real login and a direct file download (through the rewritten
`RemoteUserHasAccess`) were confirmed by the user the same afternoon; the
old 3.3.0 container was then removed. The tag is pinned in ce-it-infrastructure
`dcc.yml` by PR #7.

Previous state, for the record:

- Until 2026-10-14 `dcc_dcc` ran `cosmicexplorer/dcc:3.3.0`, the 2019 image,
  with three hand edits in the container layer (`dcc-dev.conf` login
  allow-list, `ListBy` XSS hot-fix, `inc-md-cert-mdq.pem`), all captured in
  this repository.
- Deploys cause a few minutes of downtime plus the shibd metadata window and
  must be scheduled by the user.

## Branches and pull requests

| Repository | Branch | PR | Content | Built image |
|------------|--------|----|---------|-------------|
| ce-docdb | `main` | | snapshot + docs, no code fixes | none kept |
| ce-docdb | `hotfix-release-1` | [#1](https://github.com/cosmic-explorer/ce-docdb/pull/1) | Release 1 security fixes (C1-C3, H1-H4, H6, H7, H11-H17, M4, M10-M13, L11, L17, H5 partial) | `cosmicexplorer/dcc:ce-1658d4c7b121` |
| ce-docdb | `backport-opendcc` (on hotfix) | [#2](https://github.com/cosmic-explorer/ce-docdb/pull/2) | `InputValidation.pm`, escaped message stacks (H8), `prefilter.tcl` fixes | `cosmicexplorer/dcc:ce-58b5fb4f2582` |
| ce-it-infrastructure | `dcc-login-eppns` | [#8](https://github.com/cosmic-explorer/ce-it-infrastructure/pull/8) | folds the live `/login` ePPN allow-list into the Dockerfile; no deploy needed | merged 2026-10-14 |
| ce-it-infrastructure | `fix-rest-api-pagination` | [#6](https://github.com/cosmic-explorer/ce-it-infrastructure/pull/6), merged | API returns whole lists; `rest-dcc` 1.2.2 | **deployed 2026-10-14**: `dcc_rest-api` runs `cosmicexplorer/rest-dcc:1.2.2`, built on the host from master `71c30a0`; `dcc.yml` pins it and the DCC tag (#7, merged) |
| ce-docdb | `release-2` (on backport-opendcc) | [#3](https://github.com/cosmic-explorer/ce-docdb/pull/3) | the correct fixes from the Codex review (topic cycles, doctype IDs, meeting bugs, XML dedupe, landing-page link, H7 bind values), fail-closed authorizer on stdin, drift-guard error handling, his Perl regression suite (285 assertions), doc corrections, and his 250-row findings inventory in the review | `cosmicexplorer/dcc:ce-cef36b92168d` |
| ce-docdb | `codex/ce-docdb-unified-review-2026-10-14` (Geoffrey Lovelace, GPT Codex; to be deleted) | none | re-implementation of Release 1 with per-finding tests, 9 extra fixes, 1.2 MB review archive; see `docs/assessment-codex-branch-2026-10-14.md`. **Do not merge wholesale: its `RemoteUserHasAccess` rewrite would deny all private downloads.** | |
| ce-docdb | `fix-l30-untaint` | [#4](https://github.com/cosmic-explorer/ce-docdb/pull/4) | L30: `UntaintParams.pm` replaces the missing `CGI::Untaint`; `ListEventsBy`, `TopicAdminister`, `BulkCertificateInsert` compile again | Release 3 integration build `cosmicexplorer/dcc:ce-a73343327d3a` (local merge of #4-#11; rebuild from `main` after merging) |
| ce-docdb | `fix-l25-public-search` | [#5](https://github.com/cosmic-explorer/ce-docdb/pull/5) | L25: public search scoped to this host, query URL-encoded | (same) |
| ce-docdb | `fix-h10-remove-pnp` | [#6](https://github.com/cosmic-explorer/ce-docdb/pull/6) | H10: P&P review hook removed, Dockerfile deletes the base-layer script | (same) |
| ce-docdb | `fix-h9-meeting-escaping` | [#7](https://github.com/cosmic-explorer/ce-docdb/pull/7) | H9: meeting/session/break/talk text escaped at output | (same) |
| ce-docdb | `fix-m2-canmodify-ids` | [#8](https://github.com/cosmic-explorer/ce-docdb/pull/8) | M2: `CanModify` and `ShowDocument` compare Author IDs correctly | (same) |
| ce-docdb | `fix-search-listing-defects` | [#9](https://github.com/cosmic-explorer/ce-docdb/pull/9) | L27/C07/C09: search weighting, group cookie, keyword delete, topic table, footer, `ListBy` latest/type queries, filter retention, truncation warnings | (same) |
| ce-docdb | `fix-edit-form-defects` | [#10](https://github.com/cosmic-explorer/ce-docdb/pull/10) | D02 atomic uploads, D05 QA state, D06 duplicate names, D07 type selector, D08 date override, D09 version word, MT03 break rows, L19 leftovers | (same) |
| ce-docdb | `fix-ligo-leftovers` | [#11](https://github.com/cosmic-explorer/ce-docdb/pull/11) | L26: mail subjects, document-number links, time zone, help links | (same) |
| ce-docdb | `docs-release-3` | this PR | review statuses and this handoff; merge last | |
| comanage-registry | `fix-restdcc-pagination` | [#1](https://github.com/cosmic-explorer/comanage-registry/pull/1) | provisioner follows pagination; per-member id fix | n/a (PHP, not linted: no PHP on this host) |

Lesson from merging the stack: GitHub merges each PR into its *base*
branch, so after the first PR of a stack merges, retarget the next one to
`main` before clicking merge (or merge the final branch into `main` by hand,
which is what was done on 2026-10-14). Also, `docker service update` to a
local-only image works but prints a registry warning; that is expected.

## Recommended order of operations

1. ~~Merge and deploy `#1`, `#2`, `#3`~~ Done 2026-10-14. For future releases:
   `scripts/deploy-image.sh <tag>` from the merged branch, then set the tag in
   `ce-it-infrastructure/dcc/dcc.yml` (`UPDATING.md`).
2. ~~Merge ce-it-infrastructure `#6`, build and roll `rest-dcc:1.2.2`~~ Done 2026-10-14.
3. ~~Deploy comanage-registry `#1`~~ Done 2026-10-14 22:45 UTC (merged master `990759f5` on the roster host).
4. ~~Run `scripts/dedupe-usersgroup.sql`~~ Done 2026-10-14 22:50 UTC: 35,971 rows reduced to 962 (one per membership), `UNIQUE KEY EmailUserGroup (EmailUserID, GroupID)` added, duplicate inserts verified rejected, backup kept as `UsersGroup_before_dedupe` (drop it once the next few syncs are clean). The CEConsortium reprovision (CO Group 16, DCC target 2) at 22:53 UTC made 0 inserts and 2 deletes (two people no longer in the COmanage group, one of them already an inactive author); `UsersGroup` is at 960 rows = 960 memberships, CEConsortium 737. The duplication bug is closed end to end. Drop `UsersGroup_before_dedupe` after a week of clean syncs.
5. ~~Merge ce-it-infrastructure PR #8~~ merged 2026-10-14; branch can be deleted.
6. **Release 3** (needs a short downtime window for the container restart,
   plus the usual ~30 minutes of shibd start-up during which private URLs
   return 500): merge ce-docdb #4 to #11 in any order (they are independent
   and were verified to merge together), then the docs PR; `git pull` on
   `main`; `scripts/build-image.sh`; `scripts/deploy-image.sh <tag>`; set the
   tag in `ce-it-infrastructure/dcc/dcc.yml`. Afterwards check that
   `ListEventsBy` and `TopicAdminister` load, that a public search lands on
   Google scoped to dcc.cosmicexplorer.org, and that an event page shows no
   "Initiate P&P Review" button.

## Open items for the user

- The Codex branch's useful content is now in `release-2` (merged) and in the
  review's appendix; the branch can be deleted. A local backup of it is on
  this host as branch `geoffrey-review` (not pushed).
- COmanage side, all merged 2026-10-14 evening: comanage-registry #2 (history
  attribution of removals, refresh tokens only on demand), #3 (Mailman
  provisioner back-ports), #4 (`dccAddMembership` treats finale-rest's
  HTTP 400 "must be unique" on a duplicate `UsersGroup` POST as already
  present). #4 was checked against the API's actual error shape and against
  the vendored Guzzle 6.4.1, which still maps the plugin's `exceptions =>
  false` to `http_errors`, so a 400 reaches the status check instead of
  throwing. The mail cert-renewal cron fix (infra #3) was relayed to the
  ce-services maintainer as well.
- Drop `UsersGroup_before_dedupe` in the DCC database after a week of clean
  provisioning.
- ce-it-infrastructure's two old PRs from Alex Nitz were resolved 2026-10-14:
  #3 (`apachectl` in the mail cert-renewal cron) merged; #5 (sed on the
  public `Search` at container start) closed; its intent is ce-docdb PR #5.

- Revoke the Sentry project key that was in `cgi-bin/test.pl`; it is in git
  history from the initial commit (`ee5fb2b`) even though the file is now
  deleted on every branch. Rewriting history is possible but is the user's
  call.
- Rotate the fine-grained GitHub token used by `gh` when this round of work
  is done; it appeared in a conversation transcript.
- Merge and deploy Release 3 (step 6 above). Open after it: M9 CSRF tokens,
  M1 Defang upgrade, M3, the Apache `LocationMatch` tightening in H5,
  D01/D03/D04 (edit version choice and write ordering; need design work),
  DX09 (incomplete delete), `DocDBHelp.xml` (LIGO help text, needs a
  rewrite), `Statistics` on the public instance (aggregate counts only;
  product decision), and the appendix rows still marked open.
- Consider installing `catdoc`, `h5dump`, `ghostscript` in the image so
  Office/HDF5/PostScript content gets indexed (the `CGI::Untaint` part of
  L30 is fixed in code by PR #4).
- Report the still-present upstream defects to the open-DCC maintainers
  (`docs/upstream-opendcc.md`).

## Things that were tried and blocked

- A live probe of the Apache PATH_INFO bypass (H5) and reading the
  container's `/tmp/debug` were declined by the permission classifier; H5 is
  config-traced only, and `AcceptPathInfo Off` in the hotfix closes it
  regardless.
- A sub-agent reviewing the search area was terminated by the model
  provider's safeguards while writing up a command-injection finding; the
  area was re-reviewed twice afterwards (see the review's coverage notes).
  Describe such findings in defensive language.

## Where things live on the host

See `docs/architecture.md` ("What is in the image and what is on the host")
and `docs/bootstrap.md`. In short: code in the image, documents and database
under `/srv/docker/dcc/`, real secrets in `/root/ce-it-infrastructure/dcc/dcc-environment.sh`
and Swarm secrets, infrastructure checkout at `/root/ce-it-infrastructure`,
qcow2 base image at `/root/ce-it-infrastructure/dcc/dcc-syr-disk0.qcow2`.
