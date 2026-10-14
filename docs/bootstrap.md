# How the DCC was bootstrapped, and how this repository fits

The step-by-step commands live in
[ce-it-infrastructure/dcc](https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/dcc)
and are not repeated here. This page explains what those steps do, why they
are ordered the way they are, what state each one leaves behind on the host,
and where the code in this repository takes over.

## The problem the bootstrap solves

The LIGO DCC code was never published. What Cosmic Explorer received was a
disk image of a running LIGO DCC virtual machine (`dcc-syr-disk0.qcow2`,
about 5 GB, kept at `/root/ce-it-infrastructure/dcc/` on the host). That
image contains a complete CentOS 7 system: the Perl code, Apache, Shibboleth,
MariaDB with a LIGO-flavoured database, GLIMPSE, cron jobs and LIGO-specific
configuration. The bootstrap turns that VM image into a set of Docker images
and host directories that run as a Swarm stack, with the LIGO-specific parts
replaced by Cosmic Explorer ones and the mutable data pulled out of the image
onto the host. Everything in the infrastructure repo is in service of those
three goals: containerise, rebrand, externalise state.

## Stage 1: a Docker image from the disk image

`bootstrap-dcc.sh` streams the VM's root filesystem out of the qcow2 with
`virt-tar-out` and feeds it to `docker import`, producing
`cosmicexplorer/dcc-base:3.3.0`. This is a raw filesystem snapshot, not a
built image: no entrypoint, systemd units still enabled, LIGO Kerberos and
SSH configuration still present. It is never run directly.

The `Dockerfile` then builds `cosmicexplorer/dcc:3.3.0` on top of it. Read it
as five groups of edits:

1. **Make it a container, not a VM.** Remove `fstab`, lock root, drop the
   LIGO network interface, Kerberos realm, SSH keys, GlusterFS cron job,
   Puppet, Ganglia and the LIGO yum repositories. Install `supervisor` so
   three daemons can run in one container without systemd.
2. **Rebrand.** `sed` edits replace `dcc-dev.ligo.org` with the
   `DCC_INSTANCE` build argument in `httpd.conf`, `SiteConfig.pm` (both
   instances) and the landing page; set `$Project`, `$ShortProject` and the
   admin e-mail in `ProjectGlobals.pm`; rewrite the short-URL rewrite rules
   from `LIGO-` to `CE-`; strip the LIGO wiki links from the home page; point
   `$SecureMainPage` at the Shibboleth login; and swap the LIGO CSS for a
   `CEDocDB.css` symlink.
3. **Rewire Apache for the stack.** The LIGO virtual host had a `/login`
   location and a Shibboleth discovery-service config that are deleted, and a
   block is appended with the reverse proxies to the REST API, Hydra and the
   consent app, the `/login` ePPN allow-list, and the anonymous `/public`
   match. The Shibboleth embedded discovery service is installed from the
   Shibboleth yum repository, its Apache snippet is spliced inside the virtual
   host, and its landing page is replaced by the Cosmic Explorer identity
   chooser text. `$db_host` becomes `docdb-database` (the Swarm service name)
   and mail goes to `smtp-host.syr.edu`.
4. **Prepare state for externalisation.** The MariaDB data directory, the
   GLIMPSE index and the two `Static` asset trees are moved aside to
   `*.orig` or `*__Static` names and empty directories are created in their
   place. This is the trick that lets the next stage copy them onto host bind
   mounts: the image keeps a pristine copy, the mount point is empty.
5. **Apply the Cosmic Explorer code patch and the entrypoint.** The only
   Perl change applied as a real patch is `AuthorSQL.pm.patch` (middle-initial
   author matching). `supervisord.conf`, `start-apache.sh`, `start-shibd.sh`
   and `renew-certs.sh` are copied in and `supervisord` becomes the
   entrypoint.

Everything this stage does to the Perl code is now captured verbatim in this
repository (see [code-layout.md](code-layout.md), "Cosmic Explorer
customisations"). The `sed`-based approach was fragile; it does not need to
be repeated because the result is checked in.

## Stage 2: the one-off bootstrap container

`Dockerfile.bootstrap` builds `cosmicexplorer/dcc-bootstrap:3.3.0` from the
image above. It re-enables **systemd** as PID 1 (hence the privileged
container, cgroup mount and tmpfs in `docker-compose.yml`), disables shibd,
httpd and cron, enables MariaDB, and installs two one-shot units. The point of
this container is to run MariaDB once, against the bind-mounted host
directories, so that the LIGO data can be migrated into them and the Cosmic
Explorer customisations applied with SQL. It is started with Docker Compose,
not Swarm, because Compose can run a privileged container and Swarm cannot.

The two units run in order:

* `docdb-storage.service` (`docdb-storage.sh`), before MariaDB: if the
  bind-mounted `/var/lib/mysql` is empty, move the `.orig` database files
  into it; likewise the GLIMPSE index into `/usr2/GLIMPSE` and the `__Static`
  trees into `/usr1/www/html/{DocDB,public}/Static`; fix ownership. After
  this the host directories under `STORAGE_PATH` hold the live data and the
  image copies are deleted.
* `docdb.service` (`docdb.sh`), after MariaDB: guarded by a marker file
  `/var/lib/mysql/docdb.init` so it runs once. Its SQL replaces the LIGO
  security groups with the Cosmic Explorer ones (`CO:admins`, `CEPIs`,
  `CEProject`, `CEConsortium`, `NSF`), seeds the group hierarchy,
  institutions, author groups and event groups, adds the "N - Funding
  proposals" document type, resets every type's `NextDocNumber`, renames and
  re-parents topics, and then sets the MariaDB account passwords from the
  Docker secrets and grants `docdbrw`/`docdbro` access from any host (they
  previously only worked from `localhost`). It also substitutes the database
  passwords into both `SiteConfig.pm` files, which is redundant because
  `start-apache.sh` does the same at every start.

The instructions then say to wait for systemd to reach `running`, stop
MariaDB cleanly (so the MyISAM files on the host are consistent) and take the
container down. The result is `STORAGE_PATH` populated exactly as the
production stack expects. Note that the group list `docdb.sh` seeds is the
2019 one; the groups in production today also include those created later by
administrators and by the COmanage provisioner (see
[database.md](database.md)).

## Stage 3: the OAuth2 side

Still inside `bootstrap-dcc.sh`, a temporary Docker network runs Postgres,
applies Hydra's schema migrations, starts a throwaway Hydra, and registers
one OAuth2 client, `dcc-rest-api`, whose secret is `DCC_REST_SECRET`. That
client is what COmanage uses to obtain tokens for the REST API. Its callback
URL is `https://<DCC_INSTANCE>/rest-dcc/callback`. The Postgres data
directory is also under `STORAGE_PATH`, so the client registration survives.
`register-client.sh` exists for adding further clients to the running stack
later.

## Stage 4: production as a Swarm stack

`run-dcc.sh` initialises a single-node Swarm, creates the Docker secrets
(SP signing key and certificate from the `apache-shibd` directory,
database passwords, the shib header secret, the authorized ePPN), and deploys
`dcc.yml`. Several design decisions are visible in that file:

* Secrets are **external** and immutable; rotating one means creating a new
  secret under a new name and editing the stack file.
* The `dcc` service is deployed with **`replicas: 0`**. Its Apache
  configuration references the Let's Encrypt certificate, which does not
  exist until the `letsencrypt` service has answered the HTTP-01 challenge on
  port 80. The operator watches that service's log and then scales `dcc` to 1
  by hand. Every later `docker stack deploy` resets `dcc` to zero replicas
  again, which is the single most common way to take the site down by
  accident.
* All inter-service traffic is on the overlay network `dcc-net`
  (`172.30.101.0/24`); only Apache's 443 and Let's Encrypt's 80 are
  published. Hydra is told to trust TLS termination from that subnet.
* The `dcc` service bind-mounts the directories prepared in stage 2 plus
  three Shibboleth files and the Let's Encrypt directory. Everything else
  comes from the image.

On start, `start-apache.sh` substitutes the database passwords into
`SiteConfig.pm`, links the certificate files into `/etc/httpd/x509-certs`,
removes the leftover `.orig`/`__Static` copies, exports the two secrets that
`dcc-dev.conf` reads as Apache variables, and execs `httpd`.
`start-shibd.sh` installs the SP key and certificate from secrets and execs
`shibd`. Shibboleth then spends several minutes validating the InCommon
metadata before logins work. The images are local to the host; there is no
registry.

## What has drifted since the bootstrap

The bootstrap describes the state as of 2019. Three things changed in the
running container afterwards and were never fed back into the infrastructure
repository: the `/login` ePPN allow-list in `dcc-dev.conf` (now folded into
the infrastructure Dockerfile on branch `dcc-login-eppns`), the XSS hot-fix in
`ListBy`, and the InCommon MDQ signing certificate in `/etc/shibboleth`. All
three are captured in this repository. `shibboleth2.xml` and
`attribute-map.xml` were also edited on the host (they are bind mounts, so
that is the intended place).

## Where this repository takes over

The bootstrap only ever needs to run once. Its durable outputs are the local
image `cosmicexplorer/dcc:3.3.0` and the populated `STORAGE_PATH`. From here
on:

* Code and configuration changes are made in this repository and built as a
  thin layer **on top of** `cosmicexplorer/dcc:3.3.0` by the `Dockerfile`
  here ([UPDATING.md](../UPDATING.md)). The `sed` edits of stage 1 are never
  re-run; their results are the files checked in.
* Data changes are made on the host directories or in MariaDB directly
  ([operations.md](operations.md)).
* Stack-level changes (services, secrets, ports, which image tag runs) are
  made in `ce-it-infrastructure/dcc/dcc.yml` and `dcc-environment.sh`, whose
  real copy with real passwords lives at `/root/ce-it-infrastructure/dcc/`
  on the host.

## If you ever have to bootstrap again

You would need: the qcow2 image, the `apache-shibd` directory with the SP key
and certificate registered with InCommon (`/root/ce-dcc/apache-shibd/`), the
real `dcc-environment.sh`, and either the existing `STORAGE_PATH` (keep it;
the bootstrap script offers to) or a database dump plus the document tree to
restore into it. Re-running the bootstrap against an existing `STORAGE_PATH`
is safe because both one-shot units check for existing data before moving
anything and `docdb.sh` checks its marker file. The Hydra steps would
recreate the OAuth2 client with the same ID and secret. After that, build
from this repository and deploy as usual; do not deploy the raw
`cosmicexplorer/dcc:3.3.0`, which lacks every fix made since.
