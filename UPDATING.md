# Updating the running DCC from this repository

This is the procedure for getting a change committed in this repository onto
the production DCC at `dcc.cosmicexplorer.org`, in a way that survives
container restarts, Docker restarts and host reboots.

Everything below runs as root on `ce-dcc.phy.syr.edu`, where this repository
is checked out at `/root/ce-docdb` and the infrastructure repository at
`/root/ce-it-infrastructure`.

## How the running instance is put together

The DCC runs as the `dcc_dcc` service of a single-node Docker Swarm stack
named `dcc`, deployed from `ce-it-infrastructure/dcc/dcc.yml`.

| What | Where it lives | How it gets there |
|------|----------------|-------------------|
| DocDB Perl code, Apache config, Shibboleth SP/DS config, entrypoint scripts, cron jobs | **inside the image** | `Dockerfile` in this repo, layered on the frozen base `cosmicexplorer/dcc:3.3.0` |
| Static CSS/JS/images (`usr1/www/html/{DocDB,public}/Static`) | **host directory** `/srv/docker/dcc/usr1/www/html/{DocDB,public}/Static` | bind mount; copy from the repo with `rsync` (see below) |
| `shibboleth2.xml`, `attribute-map.xml`, `inc-md-cert.pem` | **host directory** `/srv/docker/dcc/etc/shibboleth/` | bind mount over the image copies |
| Documents, MariaDB data, GLIMPSE index, Let's Encrypt state | host directories under `/srv/docker/dcc/` | bind mounts; not touched by this procedure |
| DB passwords, SP signing key, shib header secret, authorized ePPN | Docker Swarm secrets | substituted at container start by `usr/local/sbin/start-apache.sh` and `start-shibd.sh` |

**Why reboots matter.** Swarm stores a *service spec* for `dcc_dcc`. Whenever
the container has to be recreated (deploy, crash, Docker restart, host
reboot) Swarm starts a fresh container from the image named in that spec.
Three consequences:

1. Anything edited *inside* the running container is lost at that moment.
   Never fix things with `docker exec` and an editor; fix them here, rebuild
   and deploy. `scripts/check-drift.sh` tells you if someone did.
2. The image the spec names must exist on this host. There is no registry;
   images live only in this machine's Docker store. Never run
   `docker image prune -a` or `docker system prune -a`, and never delete
   `cosmicexplorer/dcc:3.3.0`.
3. Tags must be immutable. `scripts/build-image.sh` tags every build
   `cosmicexplorer/dcc:ce-<git commit>` and refuses dirty trees, so what the
   spec names is always exactly one known commit. Never retag `3.3.0`.

## Procedure

### 1. Commit and push the change

```bash
cd /root/ce-docdb
git status            # must be clean apart from your change
git add -A && git commit -m "..."
git push
```

### 2. Build the image

```bash
scripts/build-image.sh
```

This builds `cosmicexplorer/dcc:ce-<commit>` on top of `cosmicexplorer/dcc:3.3.0`
and prints the tag. It is a COPY-only build and takes well under a minute.

Optional offline checks before touching production:

```bash
TAG=cosmicexplorer/dcc:ce-<commit>
# Apache config parses (secrets are placeholders here, so only syntax is checked)
docker run --rm -e SHIB_HEADER_SECRET=x -e REST_AUTHORIZED_EPPN=x@example.org --entrypoint httpd $TAG -t
# A Perl script compiles
docker run --rm -w /usr1/www/cgi-bin/private/DocDB --entrypoint perl $TAG -c ListBy
```

### 3. Deploy it

```bash
scripts/deploy-image.sh cosmicexplorer/dcc:ce-<commit>
```

The script:

* refuses if `scripts/check-drift.sh` finds hand edits in the running
  container (override with `FORCE=1` only if you have deliberately decided to
  discard them);
* runs `docker service update --image <tag> dcc_dcc`, which rewrites the
  service spec and recreates the container (stop-first, so expect a few
  minutes of downtime while shibd validates InCommon metadata);
* waits until the public DocDB page answers HTTP 200 and prints the image the
  spec now references.

Docker prints a warning that the image "could not be accessed on a registry
to record its digest". That is expected on this single-node swarm.

### 4. Make the infrastructure repo agree

`docker stack deploy --compose-file dcc.yml dcc` (used after a full stack
teardown, see the ce-it-infrastructure README) would otherwise reset the
service back to whatever image `dcc.yml` names.

```bash
cd /root/ce-it-infrastructure
sed -i 's#^\(\s*image:\s*\)cosmicexplorer/dcc:.*#\1cosmicexplorer/dcc:ce-<commit>#' dcc/dcc.yml
git diff dcc/dcc.yml      # exactly one line, the dcc service image
git commit -am "dcc: run cosmicexplorer/dcc:ce-<commit>" && git push
```

Note that `dcc.yml` deploys the `dcc` service with `replicas: 0`; after any
`docker stack deploy` you still need `docker service scale dcc_dcc=1`.

### 5. Confirm it will come back after a reboot

```bash
# the spec names your tag ...
docker service inspect dcc_dcc --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'
# ... the image exists locally ...
docker image inspect cosmicexplorer/dcc:ce-<commit> --format '{{.Id}}'
# ... Docker starts at boot ...
systemctl is-enabled docker
# ... and nothing has been edited inside the container
scripts/check-drift.sh
```

If all four are good, a reboot brings up exactly this code. Optionally keep a
tarball of the image somewhere off the Docker store:

```bash
docker save cosmicexplorer/dcc:ce-<commit> | gzip > /srv/docker/dcc/images/dcc-ce-<commit>.tar.gz
```

## Rolling back

Every previous image is still on the host, so rolling back is another deploy:

```bash
scripts/deploy-image.sh cosmicexplorer/dcc:ce-<previous commit>
```

`docker service rollback dcc_dcc` also works for the immediately previous
spec. Remember to update `dcc.yml` again either way.

## Static assets (not in the image)

Files under `usr1/www/html/DocDB/Static` and `usr1/www/html/public/Static`
are served from host directories, so a change there is applied with rsync,
not a rebuild. The host files are owned by uid 7000 (`dcc` inside the
container) and must stay that way, so do not pass `-o`/`-g`/`-a`:

```bash
cd /root/ce-docdb
for d in DocDB public; do
  rsync -rlpt --delete -n usr1/www/html/$d/Static/ /srv/docker/dcc/usr1/www/html/$d/Static/   # dry run
  rsync -rlpt --delete    usr1/www/html/$d/Static/ /srv/docker/dcc/usr1/www/html/$d/Static/
done
```

No restart is needed; Apache serves the files directly.

## Shibboleth SP configuration (bind-mounted)

`etc/shibboleth/shibboleth2.xml`, `attribute-map.xml` and `inc-md-cert.pem`
in this repository are copies of the live files for reference; the live
copies are in `/srv/docker/dcc/etc/shibboleth/`. To change them, edit and
commit here, copy to the host directory, then restart the container so shibd
re-reads them:

```bash
cp etc/shibboleth/shibboleth2.xml etc/shibboleth/attribute-map.xml /srv/docker/dcc/etc/shibboleth/
docker service update --force --detach=false dcc_dcc
```

Everything else under `etc/shibboleth/` (including `inc-md-cert-mdq.pem`,
which `shibboleth2.xml` references) is baked into the image by the normal
procedure. The SP signing key and certificate are installed from Swarm
secrets at start-up and are deliberately not in this repository or the image.

## Checking for drift at any time

```bash
scripts/check-drift.sh
```

Lists files under the managed paths that differ between the running
container and its image. An empty result means the container is running
exactly the image, which is the only state in which a reboot is guaranteed
to be a no-op.

## If the base image is ever lost

`cosmicexplorer/dcc:3.3.0` is produced by `ce-it-infrastructure/dcc/bootstrap-dcc.sh`
from `dcc-syr-disk0.qcow2` (kept at `/root/ce-it-infrastructure/dcc/`). Rebuild
it with that script, then rebuild and redeploy from this repository as above.
Because this repository overwrites every managed file, the result does not
depend on the `sed` edits in the infrastructure Dockerfile being exactly
reproducible.
