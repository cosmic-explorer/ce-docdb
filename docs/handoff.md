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
| ce-it-infrastructure | `dcc-login-eppns` | none yet | folds the live `/login` ePPN allow-list into the Dockerfile | |
| ce-it-infrastructure | `fix-rest-api-pagination` | [#6](https://github.com/cosmic-explorer/ce-it-infrastructure/pull/6), merged | API returns whole lists; `rest-dcc` 1.2.2 | **deployed 2026-10-14**: `dcc_rest-api` runs `cosmicexplorer/rest-dcc:1.2.2`, built on the host from master `71c30a0`; `dcc.yml` pins it and the DCC tag (#7, merged) |
| ce-docdb | `release-2` (on backport-opendcc) | [#3](https://github.com/cosmic-explorer/ce-docdb/pull/3) | the correct fixes from the Codex review (topic cycles, doctype IDs, meeting bugs, XML dedupe, landing-page link, H7 bind values), fail-closed authorizer on stdin, drift-guard error handling, his Perl regression suite (285 assertions), doc corrections, and his 250-row findings inventory in the review | `cosmicexplorer/dcc:ce-cef36b92168d` |
| ce-docdb | `codex/ce-docdb-unified-review-2026-10-14` (Geoffrey Lovelace, GPT Codex; to be deleted) | none | re-implementation of Release 1 with per-finding tests, 9 extra fixes, 1.2 MB review archive; see `docs/assessment-codex-branch-2026-10-14.md`. **Do not merge wholesale: its `RemoteUserHasAccess` rewrite would deny all private downloads.** | |
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
3. Deploy comanage-registry `#1` on `roster.cosmicexplorer.org`.
4. Run `scripts/dedupe-usersgroup.sql` (`docs/operations.md`), then
   reprovision `CEConsortium` and confirm the row count holds.
5. Open a PR for `dcc-login-eppns` (or fold it into `#6`).

## Open items for the user

- The Codex branch's useful content is now in `release-2` (PR #3) and in the
  review's appendix; the branch can be deleted. A local backup of it is on
  this host as branch `geoffrey-review` (not pushed).

- Revoke the Sentry project key that was in `cgi-bin/test.pl`; it is in git
  history from the initial commit (`ee5fb2b`) even though the file is now
  deleted on every branch. Rewriting history is possible but is the user's
  call.
- Rotate the fine-grained GitHub token used by `gh` when this round of work
  is done; it appeared in a conversation transcript.
- Decide on Release 2 and 3 of `docs/security-review.md` (Defang upgrade,
  CSRF tokens, P&P removal, Apache `LocationMatch` tightening, the remaining
  unescaped outputs, `CanModify` ID fix, LIGO leftovers).
- Consider installing `perl-CGI-Untaint` (L30), `catdoc`, `h5dump`,
  `ghostscript` in the image so broken scripts work and Office/HDF5/PostScript
  content gets indexed.
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
