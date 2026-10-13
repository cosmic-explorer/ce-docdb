# Cosmic Explorer DCC — DocDB source snapshot

This repository holds the application code and service configuration of the
Cosmic Explorer Document Control Center (DCC), a customised fork of the LIGO
DocDB. The code was never under version control before: it was cloned from a
running LIGO DCC instance at Caltech (`dcc-syr-disk0.qcow2`), customised by the
Dockerfile in
[ce-it-infrastructure/dcc](https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/dcc),
and runs as the `dcc_dcc` service of a Docker Swarm stack on
`ce-dcc.phy.syr.edu` (`dcc.cosmicexplorer.org`).

The initial commit is a verbatim extraction from the running
`cosmicexplorer/dcc:3.3.0` container on 2026-10-13, except for the scrubbing
described below. Paths mirror the container filesystem so a file at
`usr1/www/cgi-bin/private/DocDB/Foo.pm` here is `/usr1/www/cgi-bin/private/DocDB/Foo.pm`
in the container.

## Layout

| Path | Contents |
|------|----------|
| `usr1/www/cgi-bin/private/DocDB/` | Full DocDB Perl CGI application (authenticated, read-write instance served at `/cgi-bin/private/DocDB/`). |
| `usr1/www/cgi-bin/DocDB/` | Public read-only instance. Most entries are **absolute symlinks** into `private/DocDB`; only a few files (e.g. `SiteConfig.pm`, `DocumentDatabase`, `.htaccess`, `CGIInclude.pm`) are real files that differ. |
| `usr1/www/html/{DocDB,public}/Static/` | CSS, JavaScript and images served alongside each instance. Copied from the host bind mount `/srv/docker/dcc/usr1/www/html/*/Static`. |
| `usr1/www/html/{index.html,.htaccess,403.html,includes,js}` | Top-level web root pieces. Document files, mediawiki and phpMyAdmin are **not** included. |
| `etc/httpd/conf`, `conf.d`, `conf.modules.d` | Apache configuration. `conf.d/dcc-dev.conf` is the main virtual host including the OAuth2/REST reverse proxies and the embedded discovery service. |
| `etc/shibboleth/` | Shibboleth SP configuration (`shibboleth2.xml`, `attribute-map.xml`, public InCommon metadata signing certs, templates). |
| `etc/shibboleth-ds/` | Shibboleth embedded discovery service and the Cosmic Explorer identity-selector landing page. |
| `usr/local/etc/supervisord.conf`, `usr/local/sbin/*.sh` | Container entrypoint: supervisord runs httpd, shibd and crond. |
| `etc/cron.daily/` | `renew-certs.sh` (graceful httpd reload for Let's Encrypt renewals) and `dcc-glimpse` (nightly GLIMPSE full-text index rebuild). |

## What was changed or omitted during extraction

* **Database passwords** in both `SiteConfig.pm` files were reset to the
  placeholder `Change.Me.too!`. This is the state inside the image;
  `usr/local/sbin/start-apache.sh` substitutes the real values from Docker
  secrets at container start.
* **Private keys and host certificates** were not extracted: the Shibboleth SP
  signing key (`sp-signing-key.pem`), its symlinks, and `/etc/httpd/x509-certs`
  (Let's Encrypt certs mounted at run time). Public certificates
  (`sp-signing-cert.pem`, `inc-md-cert*.pem`) are included.
* Vendor `*.dist` reference copies in `etc/shibboleth` were dropped.
* The symlinks in `usr1/www/cgi-bin/DocDB` keep their absolute targets
  (`/usr1/www/cgi-bin/private/DocDB/...`) for fidelity, so they appear
  dangling in a checkout that is not rooted at `/`.

## Live edit found in the running container

`docker diff` showed one code/config change in the container layer that is
**not in the image**: `etc/httpd/conf.d/dcc-dev.conf` was hand-edited to allow
additional eduPersonPrincipalNames (Syracuse accounts) to reach the `/login`
OAuth2 consent endpoint, wrapped in a `<RequireAny>`. This repository contains
the live version. If the `dcc_dcc` service is recreated from the image, that
edit is lost unless it is folded into the Dockerfile.

## Related

* Build and deployment: https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/dcc
* REST API used by COmanage provisioning: https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/rest-dcc
