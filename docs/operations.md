# Operations runbook

Day-to-day tasks on `ce-dcc.phy.syr.edu`. Everything here is run as root on
the host. For code or configuration changes see [UPDATING.md](../UPDATING.md);
for what the pieces are see [architecture.md](architecture.md).

## Is it up?

```bash
docker stack ps --no-trunc dcc | grep -v Shutdown      # one Running task per service
docker service logs --tail 100 dcc_dcc                 # apache/shibd/cron via supervisord
curl -s -o /dev/null -w '%{http_code}\n' https://dcc.cosmicexplorer.org/cgi-bin/DocDB/DocumentDatabase   # public home page, expect 200
```

The private instance cannot be probed without a Shibboleth session; a 302 to
`/Shibboleth.sso/Login` from `https://dcc.cosmicexplorer.org/dcc` is the
healthy response for an anonymous client.

Startup takes several minutes because shibd downloads and verifies the
InCommon/eduGAIN metadata aggregate before Apache will authenticate anyone.
During that window logins fail with a Shibboleth error page while the public
instance already works.

## Logs

| What | Where |
|------|-------|
| Apache access/error, shibd, supervisord | `docker service logs dcc_dcc` (container stdout/stderr) |
| MariaDB | `docker service logs dcc_docdb-database` |
| REST API, Hydra, consent app, Let's Encrypt | `docker service logs dcc_rest-api` / `dcc_oauth-server` / `dcc_oauth-consent` / `dcc_letsencrypt` |
| DocDB debug files | inside the `dcc_dcc` container: `/tmp/debug`, `/tmp/log.dat`, `/tmp/errlog.log`, `/tmp/dbg` (see the security review; these should be removed from the code) |
| Short-URL rewrite tracing | `LogLevel alert rewrite:trace4` in `short_urls.*.conf` makes every rewrite verbose in the Apache error log |

Logs in the container's writable layer are lost when the container is
recreated.

## Database access

Read-only poking is safe at any time. The root password is a Swarm secret
mounted in the database container:

```bash
DB=$(docker ps -q -f name=dcc_docdb-database)
PW=$(docker exec $DB cat /run/secrets/mariadb_root_password)
docker exec -e MYSQL_PWD="$PW" -it $DB mysql -uroot dcc_docdb
```

Use the `docdbro` account (password in secret `mysql_docdbro_passwd`) when a
read-only guarantee matters. Tables are MyISAM: there are no transactions,
so never run multi-statement changes against the live database without a
dump first.

### Backup

```bash
docker exec -e MYSQL_PWD="$PW" $DB mysqldump --single-transaction --routines dcc_docdb | gzip > /root/dcc_docdb-$(date +%F).sql.gz
```

`--single-transaction` is a no-op for MyISAM but harmless; for a strictly
consistent dump use `--lock-tables` during a quiet period. Document files are
plain files under `/srv/docker/dcc/usr1/www/html/DocDB/` (about 52 GB) and
must be backed up separately, together with `/srv/docker/dcc/etc/shibboleth/`
and `/srv/docker/dcc/letsencrypt/`. The database alone is useless without the
files and vice versa. Existing ad-hoc dumps live in `/root/` on the host.

### Restore

Stop the DCC web service first so nothing writes: ask before doing this, it
is downtime. Then `mysql dcc_docdb < dump.sql` inside the database container
(copy the file in with `docker cp`), restore the files, start the service.

## Users and groups

DocDB does **not** create accounts at login. People appear in `Author`,
`EmailUser`, `RemoteUser` and `UsersGroup` only when the COmanage registry
pushes them through the REST API. Symptoms and causes:

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| User logs in but sees only public documents | no `RemoteUser` row matching their ePPN (lower-cased), or no `UsersGroup` rows | `select * from RemoteUser where RemoteUserName like '%<name>%'` |
| User cannot upload | none of their groups has `CanCreate` | `UsersGroup` join `SecurityGroup` |
| ePPN changed (new institution) | old `RemoteUser` row; add a second row for the new ePPN pointing at the same `EmailUserID` | |
| Many duplicate `UsersGroup` rows | provisioner re-inserts on every sync (known issue, see security review) | `select EmailUserID,GroupID,count(*) from UsersGroup group by 1,2 having count(*)>1` |

Administrators can also edit these through the DocDB administration pages
(`AdministerHome` in the private instance) if they are in a group with
`CanAdminister`.

## Full-text search index (GLIMPSE)

`etc/cron.daily/dcc-glimpse` rebuilds the index under `/usr2/GLIMPSE` nightly;
`DocumentUtilities.pm` / `FileUtilities.pm` call `glimpse-incr.sh` after each
upload for incremental updates. If content search returns nothing for recent
uploads, run the daily script by hand inside the container:

```bash
docker exec $(docker ps -q -f name=dcc_dcc) /etc/cron.daily/dcc-glimpse
```

Reports from the indexer accumulate in the container's `/root/glimpse-*.REPORT.*`.

## TLS certificate

`dcc_letsencrypt` renews the certificate automatically and writes it to
`/srv/docker/dcc/letsencrypt/config/etc/letsencrypt/live/dcc.cosmicexplorer.org/`.
The `dcc` container mounts that directory and `etc/cron.daily/renew-certs.sh`
does `httpd -k graceful` daily so Apache reloads it. If the certificate on
the site is stale, check the letsencrypt service log, then run the graceful
reload by hand with `docker exec <dcc container> /etc/cron.daily/renew-certs.sh`.

## Shibboleth

* SP configuration is bind-mounted from `/srv/docker/dcc/etc/shibboleth/`
  (`shibboleth2.xml`, `attribute-map.xml`, `inc-md-cert.pem`). The SP
  signing key/cert come from Swarm secrets.
* Metadata: InCommon MDQ (per-entity lookups, signed with
  `inc-md-cert-mdq.pem`), plus the LIGO and SUGWG ORCID-gateway IdPs. If an
  institution's IdP stops working, check `docker service logs dcc_dcc` for
  shibd metadata or signature errors first.
* The embedded discovery service at `/shibboleth-ds/` is configured by
  `etc/shibboleth-ds/idpselect_config.js`; the landing text is in
  `etc/shibboleth-ds/index.html`.
* The SP metadata for registering with InCommon is at
  `https://dcc.cosmicexplorer.org/Shibboleth.sso/Metadata`.

## REST API and OAuth2

The REST API (`/rest-dcc/`) is used by COmanage to provision users. Tokens are
issued by Hydra (`/oauth/`); the login/consent step requires a Shibboleth
session whose ePPN is on the allow-list in `dcc-dev.conf` (`/login`). To
register a new OAuth2 client use `register-client.sh` in the
ce-it-infrastructure repository. Hydra's admin API (port 4445) is reachable
only from containers on the `dcc_dcc-net` network.

## Secrets

Swarm secrets are immutable. To rotate one: create a new secret with a new
name, update `dcc.yml` to reference it (both the `secrets:` block and the
service), and redeploy (downtime). The DocDB code reads
`/run/secrets/{mysql_root_passwd,mysql_docdbrw_passwd,mysql_docdbro_passwd,shib_header_secret,rest_authorized_eppn}`
at container start only. Database passwords must be changed in MariaDB at
the same time (`SET PASSWORD FOR 'docdbrw'@'%' = PASSWORD('...')`).

## Host

CentOS Linux 8.0, end-of-life; yum points at `vault.centos.org`. Install
single packages only; do not run `yum update` on this production host.
Docker 19.03 starts at boot and Swarm restores all services from their stored
specs, so after a reboot the stack returns by itself (verify with
`docker stack ps dcc`). Never prune images with `-a`; the DCC images exist
only on this host.
