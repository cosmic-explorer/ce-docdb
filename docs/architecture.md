# Architecture of the Cosmic Explorer DCC

The Cosmic Explorer Document Control Center (DCC) is a customised fork of
[DocDB](https://docdb-v.sourceforge.net/) as modified by the LIGO Laboratory
for the LIGO DCC. It is a classic Perl CGI application (no mod_perl, no
framework) in front of a MariaDB database, with documents stored as plain
files on disk and Apache doing authentication through Shibboleth. This page
describes how the pieces fit together on `dcc.cosmicexplorer.org`.

Related pages: [code layout](code-layout.md), [authentication and
authorization](authentication-and-authorization.md), [database](database.md),
[documents and files](documents-and-files.md), [search and
listing](search-and-listing.md), [meetings, sign-offs and
mail](meetings-and-signoffs.md), [administration](administration.md),
[security review](security-review.md), and [UPDATING.md](../UPDATING.md) for
how to deploy a change.

## Deployment overview

Everything runs on one host, `ce-dcc.phy.syr.edu` (128.230.146.13, DNS alias
`dcc.cosmicexplorer.org`), as a single-node Docker Swarm stack named `dcc`
defined in
[ce-it-infrastructure/dcc/dcc.yml](https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/dcc).

| Swarm service | Image | Role |
|---------------|-------|------|
| `dcc_dcc` | `cosmicexplorer/dcc:<tag>` (built from this repo on top of the frozen `cosmicexplorer/dcc:3.3.0`) | Apache 2.4 + mod_shib + the DocDB CGI code. The only service with a published port (443). |
| `dcc_docdb-database` | `mariadb:10.4.8` | The `dcc_docdb` database. Data in `/srv/docker/dcc/var/lib/mysql`. |
| `dcc_rest-api` | `cosmicexplorer/rest-dcc` | Node.js REST API over a subset of DocDB tables, used by COmanage to provision users and groups. Reached only via Apache's reverse proxy at `/rest-dcc/`. |
| `dcc_oauth-server` | `oryd/hydra:v1.0.8` | OAuth2 server protecting the REST API. Public endpoints proxied at `/oauth/`; admin API on port 4445 reachable only on the stack network. |
| `dcc_oauth-consent` | `cosmicexplorer/hydra-login-consent-node` | Hydra login/consent app. Proxied at `/login` and `/consent`; `/login` is restricted by Apache to a Shibboleth session with an allow-listed eduPersonPrincipalName. |
| `dcc_oauth-database` | `postgres:9.6` | Hydra's database. |
| `dcc_letsencrypt` | `linuxserver/letsencrypt` | Obtains and renews the TLS certificate (HTTP-01 on port 80). The `dcc` container mounts the resulting certificate directory. |

Inside `dcc_dcc`, `supervisord` runs three programs (`usr/local/etc/supervisord.conf`):
`httpd` in the foreground, `shibd` (the Shibboleth SP daemon) and `crond`.
`usr/local/sbin/start-apache.sh` runs first: it substitutes the database
passwords from Docker secrets into both `SiteConfig.pm` files, links the Let's
Encrypt certificate into `/etc/httpd/x509-certs/`, and exports the secrets
that `dcc-dev.conf` references as Apache variables (`${SHIB_HEADER_SECRET}`,
`${REST_AUTHORIZED_EPPN}`). `start-shibd.sh` installs the SP signing key and
certificate from secrets.

Cron (`etc/cron.daily/`): `dcc-glimpse` rebuilds the GLIMPSE full-text index
of document files nightly; `renew-certs.sh` gracefully reloads Apache so a
renewed certificate is picked up.

### What is in the image and what is on the host

| Content | Location | Notes |
|---------|----------|-------|
| DocDB Perl code | image, `/usr1/www/cgi-bin/{private/DocDB,DocDB}` | from `usr1/www/cgi-bin/` in this repo |
| Apache, Shibboleth SP and DS config | image, `/etc/httpd`, `/etc/shibboleth`, `/etc/shibboleth-ds` | from `etc/` in this repo; three Shibboleth files are overridden by bind mounts (below) |
| Document files | host `/srv/docker/dcc/usr1/www/html/DocDB/` → `/usr1/www/html/DocDB` | about 52 GB; see layout below |
| Public symlink tree | host `/srv/docker/dcc/usr1/www/html/public/` → `/usr1/www/html/public` | symlinks into the DocDB tree for public revisions |
| Static CSS/JS/images | host, `.../html/DocDB/Static` and `.../html/public/Static` | tracked in this repo under `usr1/www/html/*/Static` |
| `shibboleth2.xml`, `attribute-map.xml`, `inc-md-cert.pem` | host `/srv/docker/dcc/etc/shibboleth/` → `/etc/shibboleth/` | tracked here for reference; edits are applied on the host |
| MariaDB data | host `/srv/docker/dcc/var/lib/mysql` | mounted into the database container |
| GLIMPSE index | host `/srv/docker/dcc/usr2/GLIMPSE` → `/usr2/GLIMPSE` | rebuilt nightly |
| Secrets | Docker Swarm secrets → `/run/secrets/*` | DB passwords, SP key/cert, shib header secret, authorized ePPN |

## Two instances of the same code

DocDB is deployed twice from one code base:

* **Private instance**, `/usr1/www/cgi-bin/private/DocDB/`, URL prefix
  `/cgi-bin/private/DocDB/`. Requires a Shibboleth session. Uses the
  read-write database account. All editing, administration, meetings and
  sign-off functionality lives here.
* **Public instance**, `/usr1/www/cgi-bin/DocDB/`, URL prefix
  `/cgi-bin/DocDB/`. No authentication. Almost every file is a symlink to the
  private copy; only `SiteConfig.pm` (sets `$Public = 1`, points `$file_root`
  at the public tree, uses the read-only account and blanks the read-write
  credentials), `DocumentDatabase`, `CGIInclude.pm` and `.htaccess` differ.
  With `$Public` set, `Security.pm` denies every modify/create/administer
  check and the access check only passes for revisions with no view groups.

Only the subset of scripts needed for browsing exists in the public directory
(about 85 entries versus 182 in private). Because the symlinks are absolute
(`/usr1/www/cgi-bin/private/DocDB/...`), the public instance always runs
exactly the private code.

## Request flow

1. The browser connects to Apache on 443. `etc/httpd/conf.d/dcc-dev.conf` is
   the single `_default_:443` virtual host. `<Location />` requires a
   Shibboleth session for everything not explicitly opened up.
2. Paths under `/cgi-bin/private/DocDB/` and `/cgi-bin/DocDB/` are
   `Alias`ed to the two code directories with `SetHandler cgi-script`, so each
   request forks a Perl process running the named script. `/dcc` is a
   `ScriptAlias` for the private home page.
3. A script does, in order: `use CGI; use DBI;`, `require "DocDBGlobals.pm"`
   (which pulls in `Utilities.pm`, `ProjectGlobals.pm` and `SiteConfig.pm`),
   `require`s the modules it needs, creates `$query = new CGI`, reads
   `%params = $query->Vars`, connects `$dbh`, calls `GetSecurityGroups()`,
   validates input (errors go to `@ErrorStack`), performs the action, and
   prints HTML through `DocDBHeader()` / `DocDBFooter()` from
   `HTMLUtilities.pm`. There is no template engine; HTML is assembled in Perl
   strings.
4. Identity arrives as the `REMOTE_USER` environment variable set by
   mod_shib (the user's eduPersonPrincipalName). `DocDBGlobals.pm` freezes it,
   lower-cased, as the constant `remote_user`. See
   [authentication and authorization](authentication-and-authorization.md).
5. Document files are not served by Perl. `RetrieveFile` resolves which file
   to serve, checks access, then issues an HTTP redirect to the file's URL
   under `/DocDB/...`. Apache serves that path directly, but first consults
   the external authorizer `RemoteUserHasAccess` (below).

## URL map

From `dcc-dev.conf`, `short_urls.private.conf` and `short_urls.public.conf`:

| URL | Handled by | Access |
|-----|------------|--------|
| `/` | redirect from `index.html` to `/dcc` | Shibboleth session |
| `/dcc` | private `DocumentDatabase` (home page) | Shibboleth session |
| `/cgi-bin/private/DocDB/<Script>` | private CGI scripts | Shibboleth session; DocDB group checks inside |
| `/cgi-bin/DocDB/<Script>`, `/pub/<Script>` | public CGI scripts | anonymous |
| `/DocDB/NNNN/<alias>/VVV/<file>` | document files on disk | Shibboleth session **and** `RemoteUserHasAccess` external group check |
| `/public/...` | public symlink tree | anonymous (`Options +Indexes`, so directories list) |
| `/CE-X000000-vN`, `/X000000`, `/X000000-vN.pdf`, `/X000000/main`, `.../of=xml` | mod_rewrite short URLs → `ShowDocument` / `RetrieveFile` in the private instance | Shibboleth session |
| `<same>/public` | short URLs → public instance | anonymous |
| `/Shibboleth.sso/*` | mod_shib handler | anonymous |
| `/shibboleth-ds/` | embedded discovery service (IdP chooser landing page) | anonymous |
| `/rest-dcc/` | proxy to `rest-api:8443` | anonymous at Apache; OAuth2 bearer token required by the API |
| `/oauth/` | proxy to Hydra public API | anonymous |
| `/login`, `/consent` | proxy to the consent app | `/login` needs a Shibboleth session with an allow-listed ePPN |
| `*.gif|jpg|png|js|css` anywhere | static assets | anonymous |

Document identifiers in URLs are the *alias* (for example `T2500123`), a
letter for the document type followed by a serial number, optionally with a
`-vN` version suffix. `CE-` may be prefixed. The letter is the first character
of `DocumentType.ShortType`.

## Document storage layout

`FSUtilities.pm::GetDirectory` maps a document to
`$file_root/<DocumentID div 1000 as 4 digits>/<Alias>/<version as 3 digits>/`.
Because `$UseAliasAsFileName` is set in `ProjectGlobals.pm`, the middle
component is the alias rather than the numeric DocumentID (the numeric form
is used only when a document has no alias). Example:
`/usr1/www/html/DocDB/0163/T2500123/001/T2500123-v1.pdf`.

When a revision is made public (`UpdateRevisionPublicSecurity` in
`SecuritySQL.pm`, triggered through the QA-check flow) the code removes its
`RevisionSecurity` rows and creates a symlink
`/usr1/www/html/public/<same path>` → `/usr1/www/html/DocDB/<same path>`,
so the anonymous `/public/` tree exposes exactly the public revisions.
Making a revision non-public again removes the symlink.

## File download authorization (`RemoteUserHasAccess`)

Direct requests to `/DocDB/...` are authorized by mod_authnz_external:
`DefineExternalGroup dccauth environment /usr1/www/cgi-bin/private/DocDB/RemoteUserHasAccess`
and `Require external-group foobar` inside `<Location /DocDB>`. For every file
request Apache runs that Perl script, which parses the document alias and
version out of the request URI, resolves the revision, and returns exit
status 0 (allow) or 1 (deny) based on `CanAccessRevision`. The group name
`foobar` is a placeholder; the script ignores it. See the
[security review](security-review.md) for problems found in this hook.

## External integrations

* **Shibboleth / InCommon**: the SP (`etc/shibboleth/shibboleth2.xml`) is
  federated with InCommon and eduGAIN via the MDQ service, plus a LIGO.org
  and an ORCID gateway IdP. Attributes consumed are listed in
  `attribute-map.xml` (ePPN, mail, displayName, givenName, sn, affiliation).
  The embedded discovery service at `/shibboleth-ds/` is the landing page.
* **COmanage → REST API**: membership changes in the Cosmic Explorer COmanage
  registry are pushed through the `rest-dcc` API into the `Author`,
  `EmailUser`, `RemoteUser`, `UsersGroup`, `SecurityGroup` and `Institution`
  tables. DocDB itself never creates users for Shibboleth logins; an ePPN that
  has no `RemoteUser` row is treated as having no groups.
* **Mail**: `Utilities.pm::send_email` sends through `smtp-host.syr.edu:25`
  using Email::Sender; `MailNotification.pm` composes change notifications.
* **GLIMPSE**: full-text search over file contents uses an external index
  (`$ContentSearch` in `ProjectGlobals.pm` points at `glimpse-query.sh`).
* **Publication & Presentation review**: `ProcessPNPReview` still points at
  LIGO's `pnp-dev.ligo.org` and is effectively unused for Cosmic Explorer.

## Logging and debugging

Apache logs go to the container's stdout/stderr via supervisord
(`docker service logs dcc_dcc`). Several scripts also append debug output to
files in the container's `/tmp` (`/tmp/debug`, `/tmp/log.dat`,
`/tmp/errlog.log`); these grow without bound and are lost when the container
is recreated. The review recommends removing them.
