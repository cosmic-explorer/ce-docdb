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

## Fixing the `UsersGroup` duplication

Cause and details: [rest-api.md](rest-api.md). The fix has three parts and
the order matters; none of it needs DCC downtime.

1. **API**: deploy `cosmicexplorer/rest-dcc:1.2.2` (branch
   `fix-rest-api-pagination` in ce-it-infrastructure: lists are returned
   whole). Build the image on the host from `rest-dcc/`, then
   `docker service update --image cosmicexplorer/rest-dcc:1.2.2 dcc_rest-api`
   and commit the tag change in `dcc.yml`.
2. **Plugin**: deploy the RestDccProvisioner change (branch
   `fix-restdcc-pagination` in the comanage-registry fork: follow pagination,
   skip members without a `DccDocDbID`) on `roster.cosmicexplorer.org`.
3. **Database**: run `scripts/dedupe-usersgroup.sql` as described in its
   header. It keeps a copy of the table, deletes duplicates keeping one row
   per membership, adds `UNIQUE KEY (EmailUserID, GroupID)` and prints the
   before/after counts.
4. **Verify**: in COmanage, reprovision the `CEConsortium` group and confirm
   the row count in step 3 does not change and the API log shows no failed
   inserts.

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

Since 2026-11-05 the service runs `linuxserver/swag:5.9.0-ls497` (the
successor of the retired `linuxserver/letsencrypt` image, which carried PHP
7.3 with no PHP2Shell fix). It does two things only: certbot renewal in
http-01 standalone mode (cron twice daily; the hooks in
`config/etc/letsencrypt/renewal-hooks/` stop and restart nginx around it) and
the port-80 redirect to https. `config/nginx/site-confs/default.conf` is a
redirect-only server block with no PHP handler; swag keeps it as long as it
exists, and warns at start that it differs from the shipped sample, which is
expected. `config/php/php-local.ini` sets `session.upload_progress.enabled = 0`.

- Test renewal end to end without touching the real certificate:
  `docker exec <letsencrypt container> certbot renew --dry-run --config-dir /config/etc/letsencrypt --logs-dir /config/log/letsencrypt --work-dir /tmp/letsencrypt --config /config/etc/letsencrypt/cli.ini`
  (nginx is down for a few seconds; the DCC on 443 is unaffected).
- **Upgrading swag:** Docker 19.03 on this host cannot pull swag's OCI
  manifests (`mediaType in manifest should be ...`). Import with
  `skopeo copy docker://docker.io/linuxserver/swag:<tag> docker-daemon:linuxserver/swag:<tag>`
  (skopeo installed 2026-11-05), then
  `docker service update --no-resolve-image --image linuxserver/swag:<tag> dcc_letsencrypt`
  and pin the tag in ce-it-infrastructure `dcc/dcc.yml`. A plain
  `docker stack deploy` needs `--resolve-image never` for this service.
- **Rollback:** `docker service update --rollback dcc_letsencrypt` (the old
  image is kept locally as `linuxserver/letsencrypt:latest`) and restore
  `/srv/docker/dcc/letsencrypt/config.pre-swag-2026-11-05` over `config`;
  the old image needs the 2019 nginx directory and inline certbot hooks that
  the backup contains.

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

## Outgoing mail

Notification mail (new and updated documents, signoff "ready for signature"
and "approved" notices) goes out through `send_email` in `Utilities.pm`
(Email::Sender over SMTP); access-request mail from `UserAccessApply` goes
through `SendEmail` in `EmailUtilities.pm` (Mail::Mailer). Both use the
relay named by `$MailServer` in `SiteConfig.pm`, `smtp-relay.syr.edu`, port
25, no authentication; the container has no local MTA. The previous name
`smtp-host.syr.edu` disappeared from campus DNS in October 2026 and no mail
was delivered from 2026-10-23 until the fix was deployed (reported by ITS).

- Failures are logged as `DCC ERROR: sendmail failed` / `DCC ERROR:
  SendEmail failed` in the Apache error log and via syslog inside the
  container; a signoff that is waiting on a notification can be nudged by
  the next signer directly from the document page.
- Quick connectivity check from inside the DCC container:
  `docker exec <dcc container> perl -MIO::Socket::INET -e '$s=IO::Socket::INET->new(PeerAddr=>"smtp-relay.syr.edu",PeerPort=>25,Timeout=>5) or die $@; print scalar <$s>'`
  should print a `220 smtp-relay.syr.edu ESMTP` banner.
- If ITS renames the relay again: change `$MailServer` in both copies of
  `SiteConfig.pm`, rebuild, deploy. `tests/smtp-relay.t` checks both mail
  paths honour it.

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

### SSH daemon (OpenSSH 10.6p1 from source)

Since 2026-10-26 port 22 is served by OpenSSH 10.6p1 built from the
signature-verified upstream tarball, not by the distro `openssh-server-7.8p1`
package. A Nessus scan (2026-10-24) flagged the 7.8 banner against the
OpenSSH 10.3/10.4 advisories and the vault repositories only offer 8.0p1.

- Install prefix `/usr/local/openssh-10.6p1`; configuration in
  `/usr/local/openssh-10.6p1/etc/sshd_config` (derived from the distro file:
  key-only logins, root permitted with keys only, PAM, GSSAPI, X11, internal
  sftp; 10.6 default ciphers rather than the EL8 crypto-policy string).
- Host keys are copies of `/etc/ssh/ssh_host_*_key` with mode 0600 (upstream
  sshd rejects Red Hat's 0640 group-readable keys), so fingerprints and client
  `known_hosts` entries are unchanged.
- The stock `sshd.service` is redirected by the drop-in
  `/etc/systemd/system/sshd.service.d/openssh-10.6p1.conf` (`Type=simple`;
  upstream sshd has no sd_notify). Check config with
  `/usr/local/openssh-10.6p1/sbin/sshd -t -f /usr/local/openssh-10.6p1/etc/sshd_config`.
- **Rollback:** delete the drop-in, `systemctl daemon-reload`,
  `systemctl restart sshd`; the distro binary and `/etc/ssh` are untouched.
  Restarting sshd does not drop existing sessions (`KillMode=process`).
- The build tree is not kept; rebuild from a verified tarball with
  `./configure --prefix=/usr/local/openssh-<ver> --sysconfdir=/usr/local/openssh-<ver>/etc --with-pam --with-privsep-path=/var/empty/sshd --with-privsep-user=sshd --with-kerberos5 --with-md5-passwords --with-pid-dir=/run`
  (needs `pam-devel`, `openssl-devel`, `krb5-devel`, `zlib-devel`, `gcc`).
  Upgrade by installing a new prefix, copying `etc/`, and editing the two
  paths in the drop-in.

### SSH firewall

Port 22 accepts new connections only from 128.230.0.0/16 (SU campus) and
10.57.0.0/16 (SU VPN); every recorded login came from these ranges. The rule
is the nftables table `inet ce_dcc_ssh` in `/etc/nftables/ce-dcc-ssh.nft`,
loaded at boot by `ce-dcc-ssh-firewall.service` (enabled). Blocked attempts
are counted and logged to the kernel log as `ce-dcc ssh blocked:` (rate
limited). Established sessions are never filtered.

- Edit the `ssh_allowed_v4` set in the file, then
  `nft delete table inet ce_dcc_ssh; nft -f /etc/nftables/ce-dcc-ssh.nft`.
- Inspect: `nft list table inet ce_dcc_ssh`.
- **Never `systemctl stop|restart nftables`** (the distro unit, which is not
  enabled): its `ExecStop`/`ExecReload` run `nft flush ruleset`, which also
  removes Docker's `ip filter`/`ip nat` tables and breaks Swarm networking.
  Our table coexists with Docker's and never flushes anything.
