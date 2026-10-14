# Handoff: state of work as of 2026-10-14

For a new maintainer or a fresh Claude Code session. Everything below is
verifiable from the repository, GitHub and the host; nothing is deployed
unless stated.

## Production state

- `dcc_dcc` runs `cosmicexplorer/dcc:3.3.0`, the 2019 image, with three
  hand edits in the container layer (`dcc-dev.conf` login allow-list,
  `ListBy` XSS hot-fix, `inc-md-cert-mdq.pem`). All three are captured in
  this repository; `scripts/check-drift.sh` lists them until the first deploy.
- **None of the fixes below have been deployed.** Deploys cause a few minutes
  of downtime and must be scheduled by the user.

## Branches and pull requests

| Repository | Branch | PR | Content | Built image |
|------------|--------|----|---------|-------------|
| ce-docdb | `main` | | snapshot + docs, no code fixes | `cosmicexplorer/dcc:ce-6859fde355eb` (pre-review build of the snapshot) |
| ce-docdb | `hotfix-release-1` | [#1](https://github.com/cosmic-explorer/ce-docdb/pull/1) | Release 1 security fixes (C1-C3, H1-H4, H6, H7, H11-H17, M4, M10-M13, L11, L17, H5 partial) | `cosmicexplorer/dcc:ce-ff378a22bb8e` |
| ce-docdb | `backport-opendcc` (on hotfix) | [#2](https://github.com/cosmic-explorer/ce-docdb/pull/2) | `InputValidation.pm`, escaped message stacks (H8), `prefilter.tcl` fixes | `cosmicexplorer/dcc:ce-0ff3193cf099` |
| ce-it-infrastructure | `dcc-login-eppns` | none yet | folds the live `/login` ePPN allow-list into the Dockerfile | |
| ce-it-infrastructure | `fix-rest-api-pagination` | [#6](https://github.com/cosmic-explorer/ce-it-infrastructure/pull/6) | API returns whole lists; `rest-dcc` 1.2.2 | image must be built on the host |
| ce-docdb | `codex/ce-docdb-unified-review-2026-10-14` (Geoffrey Lovelace, GPT Codex) | none | re-implementation of Release 1 with per-finding tests, 9 extra fixes, 1.2 MB review archive; see `docs/assessment-codex-branch-2026-10-14.md`. **Do not merge wholesale: its `RemoteUserHasAccess` rewrite would deny all private downloads.** | |
| comanage-registry | `fix-restdcc-pagination` | [#1](https://github.com/cosmic-explorer/comanage-registry/pull/1) | provisioner follows pagination; per-member id fix | n/a (PHP, not linted: no PHP on this host) |

The docs commits are cherry-picked onto both ce-docdb branches so they stay
docs-identical to `main`; merging in order (`#1`, then `#2`) is clean.

## Recommended order of operations

1. Merge and deploy `#1`, then `#2` (or merge both and deploy the `#2` image):
   `scripts/deploy-image.sh <tag>` from the merged branch, then set the tag in
   `ce-it-infrastructure/dcc/dcc.yml` (`UPDATING.md`).
2. Merge ce-it-infrastructure `#6`, build `rest-dcc:1.2.2` on the host,
   `docker service update --image cosmicexplorer/rest-dcc:1.2.2 dcc_rest-api`.
3. Deploy comanage-registry `#1` on `roster.cosmicexplorer.org`.
4. Run `scripts/dedupe-usersgroup.sql` (`docs/operations.md`), then
   reprovision `CEConsortium` and confirm the row count holds.
5. Open a PR for `dcc-login-eppns` (or fold it into `#6`).

## Open items for the user

- Decide on the Codex branch: cherry-pick the commits listed in the
  assessment onto a `release-2` branch, have S1 rewritten to read stdin, and
  drop the `review/` archive.

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
