# Cosmic Explorer DCC documentation

Start with [handoff.md](handoff.md) for the current state of work, then
[architecture.md](architecture.md) for the big picture. `CLAUDE.md` at the
repository root holds the working rules for Claude Code sessions.

| Page | What it covers |
|------|----------------|
| [bootstrap.md](bootstrap.md) | How the LIGO disk image was turned into the images, host directories and Swarm stack (what the ce-it-infrastructure steps do and why), and where this repository takes over |
| [handoff.md](handoff.md) | Current state: branches, pull requests, built images, recommended order of operations, open items |
| [architecture.md](architecture.md) | Deployment (swarm services, image vs host), the two instances, request flow, URL map, file storage, external integrations |
| [code-layout.md](code-layout.md) | Directory layout, file naming, configuration precedence, anatomy of a CGI script, conventions, Cosmic Explorer customisations and LIGO leftovers |
| [authentication-and-authorization.md](authentication-and-authorization.md) | Shibboleth, RemoteUser/EmailUser/UsersGroup mapping, security groups and hierarchy, CanAccess/CanModify/CanAdminister, file download authorization, making documents public |
| [database.md](database.md) | Schema reference for all 51 tables, relationships, Cosmic Explorer seed data |
| [documents-and-files.md](documents-and-files.md) | Document/revision/file model; add, modify, add-files, delete, retrieve, XML import/export |
| [search-and-listing.md](search-and-listing.md) | Home page, ListBy, Search, List* scripts, topics/keywords/authors/types, preferences |
| [meetings-and-signoffs.md](meetings-and-signoffs.md) | Events, meetings, sessions, talks, talk hints, sign-off workflow, e-mail notifications |
| [administration.md](administration.md) | Administration pages, user access applications, public instance differences, client-side JavaScript |
| [rest-api.md](rest-api.md) | The REST API and OAuth2 path COmanage uses to provision users and groups: components, token flow, endpoints, operating notes |
| [security-review.md](security-review.md) | Findings of the October 2026 code review with severity, evidence and fixes |
| [assessment-codex-branch-2026-10-14.md](assessment-codex-branch-2026-10-14.md) | Assessment of the independent GPT Codex review branch: what to take, what not to merge (one change would break downloads), and why |
| [upstream-opendcc.md](upstream-opendcc.md) | Comparison with LIGO's current DocDB 3.5.3 (opendcc/docdb): what it fixed, what it did not, what is worth back-porting |
| [operations.md](operations.md) | Runbook: health, logs, database access and backup, users, GLIMPSE, TLS, Shibboleth, secrets |
| [../UPDATING.md](../UPDATING.md) | How to build and deploy a code change so it survives reboots |
