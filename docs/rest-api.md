# The REST API (`dcc_rest-api`) and COmanage provisioning

The DCC does not create accounts when someone logs in. People, their
Shibboleth identities and their group memberships are written into the DocDB
database by the Cosmic Explorer COmanage registry, through a small REST API
on the DCC protected by OAuth2. This page explains both ends: the API and
its OAuth2 services on the DCC side, and the COmanage plugin that calls it.

Sources: the API is
[ce-it-infrastructure/rest-dcc](https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/rest-dcc)
(image `cosmicexplorer/rest-dcc:1.2.1`); the client is the
[RestDccProvisioner plugin](https://github.com/cosmic-explorer/comanage-registry/tree/master/app/AvailablePlugin/RestDccProvisioner)
in the Cosmic Explorer fork of COmanage Registry; the Hydra login/consent app
is the `dcc` branch of
[cosmic-explorer/hydra-login-consent-node](https://github.com/cosmic-explorer/hydra-login-consent-node/tree/dcc).

## The pieces

| Component | What it is | Reached at |
|-----------|------------|------------|
| `dcc_rest-api` | Node 12 + Express + Sequelize 5 + finale-rest. Generic CRUD over six DocDB tables. Connects to MariaDB as `docdbrw` with the password from the `mysql_docdbrw_passwd` secret. | `https://dcc.cosmicexplorer.org/rest-dcc/` (Apache reverse proxy to `rest-api:8443`) |
| `dcc_oauth-server` | ORY Hydra v1.0.8. Issues and introspects OAuth2 tokens. Public API on 4444, admin API on 4445. | public API at `/oauth/` (proxy to `oauth-server:4444`); admin API only on the stack network |
| `dcc_oauth-consent` | The login/consent app Hydra calls back to. Does no authentication itself: it trusts Apache. | `/login` and `/consent` (proxy to `oauth-consent:3000`) |
| `dcc_oauth-database` | Postgres 9.6 for Hydra (clients, consent sessions, tokens). Data under `/srv/docker/dcc/var/lib/postgresql/data`. | internal |
| RestDccProvisioner plugin | A COmanage *provisioner* plugin (CakePHP, Guzzle, league/oauth2-client). One "provisioning target" per CO holds the DCC URL, client ID and secret, and the current access and refresh tokens in COmanage's own database. | runs inside `roster.cosmicexplorer.org` |

## How COmanage gets and keeps a token

1. **Registration.** On the DCC host, `register-client.sh` (infrastructure
   repo) creates a Hydra client with a chosen client ID, a generated secret,
   grant types `authorization_code` and `refresh_token`, scope `offline`,
   and the callback URL shown on the plugin's configuration page in COmanage:
   `https://roster.cosmicexplorer.org/registry/rest_dcc_provisioner/co_rest_dcc_provisioner_targets/callback/<target id>`.
   (The `dcc-rest-api` client created during bootstrap, with callback
   `/rest-dcc/callback`, is for manual testing with a REST tool; the DCC
   itself serves nothing at that path.)
2. **Authorization.** A COmanage administrator enters the DCC URL, client ID
   and secret in the plugin's target form and clicks Save. The plugin's
   `performRedirect` builds an authorization request (`/oauth/oauth2/auth`,
   scope `offline`, a random `state` kept in the admin's COmanage session)
   and redirects the administrator's browser to the DCC.
3. **Login and consent on the DCC.** Hydra sends the browser to `/login`.
   Apache requires a Shibboleth session **and** an eduPersonPrincipalName on
   the fixed allow-list in `dcc-dev.conf` (`REST_AUTHORIZED_EPPN` plus three
   Syracuse accounts). So the COmanage administrator performing this step
   must personally be on that list; nobody else can authorize the
   provisioner. Apache forwards to the consent app with `X-Shib-Remote-User`
   and the shared `X-Shib-Secret`; the app accepts the login and consent
   challenges without a form and returns to Hydra.
4. **Callback.** Hydra redirects to the COmanage callback URL with a code.
   The plugin's `callback` action checks the `state`, exchanges the code at
   `/oauth/oauth2/token` (client ID and secret, HTTP Basic), and stores the
   access token, refresh token and callback URL on the target record.
5. **Every provisioning operation** starts by calling `dccConnect`, which
   performs a `refresh_token` grant, saves the **new** access and refresh
   tokens, and then uses the access token as a Bearer header on a Guzzle
   client with base URL `<DCC URL>/rest-dcc/` and a 5-second timeout. Hydra
   rotates refresh tokens, so the stored one is single-use: if a save fails
   or two provisioning runs interleave, the stored refresh token becomes
   invalid, later operations fail with "Access token not received", and an
   allow-listed administrator has to open the target and click Save again.

## How a request is authorized on the DCC

`auth.js` is the API's only middleware. It requires
`Authorization: Bearer <token>`, posts the token to Hydra's introspection
endpoint on the admin API (`oauth-server:4445/oauth2/introspect`), and lets
the request through if the token is `active` and an `access_token`. It does
not check client, scope or subject, and there is no per-resource or
per-method authorization. The `/login` allow-list is therefore the only
thing standing between "can get a token" and "can rewrite the user tables".

## What the API exposes

finale-rest turns each Sequelize model into a full resource: `GET` list
with equality filters from the query string (`?GroupID=6`), `GET` by primary
key, `POST` (the client may supply the primary key), `PUT`/`PATCH`, `DELETE`.
The models are `sequelize-auto` dumps of the DocDB tables, so JSON field
names are the column names in [database.md](database.md). **Lists are
paginated: 100 rows per page by default** (`count` and `offset` query
parameters, `Content-Range` header), which matters below.

| Endpoint | Table | How the plugin uses it |
|----------|-------|------------------------|
| `/SecurityGroup` | `SecurityGroup` | read once per operation to map group names to IDs. Never written by the plugin. |
| `/Author`, `/Author/:id` | `Author` | `GET` to see if the person exists, then `POST` or `PUT` |
| `/EmailUser`, `/EmailUser/:id` | `EmailUser` | `POST` or `PUT` alongside Author |
| `/RemoteUser`, `/RemoteUser/:id` | `RemoteUser` | `POST` or `PUT`; this row is what makes a Shibboleth login resolve to a DocDB user |
| `/UsersGroup`, `/UsersGroup/:id` | `UsersGroup` | `GET ?EmailUserID=` or `?GroupID=`, then `POST` to add and `DELETE` to remove memberships |
| `/Institution` | `Institution` | `GET ?LongName=` to find the person's institution. Never written by the plugin. |

Nothing else in DocDB is reachable through the API.

## What the plugin does

**Identifiers.** Each CO Person has a COmanage Identifier of extended type
`DccDocDbID` (created by an identifier-assignment rule in COmanage; values
start at 1,000,000). The plugin uses that one number as `AuthorID`,
`EmailUserID`, `RemoteUserID` and `EmployeeNumber`, which is why those IDs
are identical for every provisioned person. `EmailUser.Username` is the
person's `cosid` identifier; `RemoteUser.RemoteUserName` is the `eppn`
identifier of their (last non-deleted) organizational identity;
`EmailAddress` is the `official` e-mail; names come from the primary name,
with middle names reduced to initials. If a person has no `DccDocDbID` yet
the plugin returns silently (a race with identifier assignment), so the
person is provisioned on the next change.

**Institution.** The person's institution is found by an exact match of the
`Institution.LongName` column against the organization (`o`) of their first
CO Person Role, after `htmlentities()`. If no institution matches, the
`Author` insert fails and provisioning of that person aborts with "Failed to
create Author". Adding a new institution to the DCC (through
`InstitutionAdminister`) with a `LongName` exactly equal to the COmanage
organization string is therefore a prerequisite for provisioning people from
a new institution; organization names containing `&` or quotes will not
match because of the entity encoding.

**Person events.** On a person being added, updated, unexpired or
reprovisioned the plugin writes the three rows (`PUT` if `GET /Author/<id>`
returns 200, `POST` if 404) with `Active = 1`, `Verified = 1`, `CanSign = 0`.
On delete or expiry it does the same with `Active = 0`: DocDB authors are
never deleted, only deactivated, which is what makes `CanAccess` deny them.
It then synchronises the person's memberships (below). Grace-period events
are ignored.

**Group events.** Only COmanage groups whose **name is exactly a DocDB
`SecurityGroup.Name`** are synchronised; all other COmanage groups are
ignored, and DocDB groups that do not correspond to a COmanage group
(`Public_Pending`, `Authors`, `NSF`, ...) are never touched. This is why
groups such as `CO:admins` and `CO:COU:Project:members:active` exist in DocDB
under those exact names: they were created in DocDB to mirror COmanage group
names. On a group being added, updated or reprovisioned, the plugin lists the
DocDB memberships of that group, adds every current COmanage member (valid
`valid_from`/`valid_through`) that is missing, and deletes every DocDB
membership whose person is not a current COmanage member, recording each
change in the person's COmanage history.

**Membership sync for a person** works the same way from the other side:
list the person's DocDB memberships, delete those whose group is a mirrored
group but no longer a COmanage membership, add missing ones.

## The duplication bug, explained

Both membership syncs start from a `GET` of existing memberships and only add
what is missing, so they are *meant* to be idempotent. They are not, because
the API returns only the first 100 rows of a list and the plugin never
requests further pages. `CEConsortium` has 739 members: a group sync sees
100 of them, decides the other 639 are missing, and inserts a membership row
for each of them, every time the group is reprovisioned. Once a person has
more than 100 membership rows (65 people do today), the per-person sync pages
as well and starts duplicating too. The result is the 35,748 `UsersGroup`
rows for 739 real `CEConsortium` memberships described in the
[security review](security-review.md) (M5), while every group with fewer than
100 members has exactly one row per member.

Fix on either side: have the API disable pagination for these resources
(finale's `pagination: false`) or the plugin request `?count=` large enough
and follow `Content-Range`; then de-duplicate the table and add
`UNIQUE KEY (EmailUserID, GroupID)` so the mistake cannot recur.

## Operating it

* **Logs**: `docker service logs dcc_rest-api`. A healthy start prints
  `Executing (default): SELECT 1+1 AS result` and `Listening on port 8443`;
  each authorized request logs `Authorized connection from <subject>`.
  Hydra: `docker service logs dcc_oauth-server`, started with two
  `Setting up http server` lines; it runs at `LOG_LEVEL=debug`.
* **A person is not appearing in DocDB**: check in COmanage that they have a
  `DccDocDbID` identifier, an `eppn` on an organizational identity, an
  official e-mail, and a role whose organization matches an `Institution`
  `LongName` exactly; then look at the provisioning status on their COmanage
  record and at the API log.
* **"No access token" / provisioning failures across the board**: the stored
  refresh token was lost or rotated out from under COmanage. An allow-listed
  administrator opens the provisioner target in COmanage and clicks Save to
  re-authorize.
* **Changing the allow-list** is an Apache configuration change in
  `etc/httpd/conf.d/dcc-dev.conf` (and the infrastructure Dockerfile),
  deployed per [UPDATING.md](../UPDATING.md). The `REST_AUTHORIZED_EPPN`
  secret is its first entry.
* **Rotating the client secret or `shib_header_secret`**: create or update
  the Hydra client (`register-client.sh` or the admin API from inside the
  stack network), update the Swarm secret, update the plugin target in
  COmanage and re-authorize.
* **Adding an institution**: create it in DocDB first, with the exact
  COmanage organization string as `LongName`.

## Things to be aware of

Summarised in the [security review](security-review.md) under "Adjacent
component".

* `auth.js` logs every bearer token in clear text to the container log;
  anyone who can read `docker service logs dcc_rest-api` can replay a live
  token.
* Any active Hydra access token is accepted, regardless of client, scope or
  subject, and every endpoint allows create, update and delete, including
  `SecurityGroup.CanAdminister`. The plugin only needs read access to
  `SecurityGroup` and `Institution`.
* The list pagination mismatch above; the plugin also does not validate or
  encode the names and e-mail addresses it stores, several of which DocDB
  renders without encoding (review L14, M15).
* The stack runs Node 12, Express 4.16, Sequelize 5, node-fetch 2 and Hydra
  v1.0.8, all end-of-life; Dependabot flags the Node dependencies. Hydra's
  admin API is unauthenticated and relies on network isolation within the
  Swarm overlay.
