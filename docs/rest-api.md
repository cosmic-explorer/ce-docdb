# The REST API (`dcc_rest-api`) and OAuth2 provisioning path

The DCC does not create accounts when someone logs in. People, their
Shibboleth identities and their group memberships are written into the DocDB
database by the Cosmic Explorer COmanage registry through a small REST API.
This page explains that path: what the API is, how it is protected, how a
client obtains a token, what it can change, and what to watch for. The source
is in
[ce-it-infrastructure/rest-dcc](https://github.com/cosmic-explorer/ce-it-infrastructure/tree/master/rest-dcc)
(image `cosmicexplorer/rest-dcc:1.2.1`); the Hydra login/consent app is the
`dcc` branch of
[cosmic-explorer/hydra-login-consent-node](https://github.com/cosmic-explorer/hydra-login-consent-node/tree/dcc).

## The pieces

| Service | What it is | Reached at |
|---------|------------|------------|
| `dcc_rest-api` | Node 12 + Express + Sequelize 5 + finale-rest. Generic CRUD over six DocDB tables. Connects to MariaDB as `docdbrw` with the password from the `mysql_docdbrw_passwd` secret. | `https://dcc.cosmicexplorer.org/rest-dcc/` (Apache reverse proxy to `rest-api:8443`) |
| `dcc_oauth-server` | ORY Hydra v1.0.8. Issues and introspects OAuth2 tokens. Public API on 4444, admin API on 4445. | public API at `/oauth/` (proxy to `oauth-server:4444`); admin API only on the stack network |
| `dcc_oauth-consent` | The login/consent app Hydra calls back to. Does no authentication itself: it trusts Apache. | `/login` and `/consent` (proxy to `oauth-consent:3000`) |
| `dcc_oauth-database` | Postgres 9.6 for Hydra (clients, consent sessions, tokens). Data under `/srv/docker/dcc/var/lib/postgresql/data`. | internal |
| COmanage (`roster.cosmicexplorer.org`) | The client. Its DCC provisioner plugin holds the `dcc-rest-api` client credentials and a refresh token and calls the API when a person or membership changes. | external |

## How a token is obtained

Hydra is configured with issuer `https://dcc.cosmicexplorer.org/oauth/`,
login URL `/login` and consent URL `/consent`. The single registered client
`dcc-rest-api` (created during bootstrap, secret `DCC_REST_SECRET`) uses the
authorization-code grant with scopes `openid offline`, so it receives a
refresh token and can keep working unattended.

1. The client sends the browser to `/oauth/oauth2/auth` with its client ID,
   redirect URI `https://dcc.cosmicexplorer.org/rest-dcc/callback`, and the
   scopes.
2. Hydra redirects to `/login`. Apache guards that location: it requires a
   Shibboleth session **and** an eduPersonPrincipalName on a fixed allow-list
   (`REST_AUTHORIZED_EPPN` plus three Syracuse accounts in `dcc-dev.conf`).
   Nobody else can get past this step, which is the real access control for
   the whole provisioning path.
3. Apache forwards the request to the consent app with two headers:
   `X-Shib-Remote-User` (the ePPN) and `X-Shib-Secret` (the
   `shib_header_secret`). The consent app accepts the login challenge for
   that user if the secret matches, then accepts the consent challenge for
   the requested scopes without showing a form, and redirects back to Hydra.
4. Hydra redirects to the callback URI with an authorization code. The API
   container has no route for `/rest-dcc/callback`; the code is read off that
   redirect by the client (COmanage's plugin, or a person using a REST tool
   as the infrastructure README describes).
5. The client exchanges the code at `/oauth/oauth2/token` (HTTP Basic client
   authentication) for an access token and a refresh token, and later
   refreshes without any human involvement.

The three people on the allow-list are therefore the only ones who can mint
or re-authorize the provisioner's credentials. Adding a client is done with
`register-client.sh` in the infrastructure repo (it talks to the admin API
over the stack network).

## How a request is authorized

`auth.js` is the only middleware. For every request it requires an
`Authorization: Bearer <token>` header, posts the token to Hydra's
introspection endpoint on the admin API (`oauth-server:4445/oauth2/introspect`),
and accepts the request if the token is `active` and of type `access_token`.
It does not check which client the token belongs to, which scopes it carries,
or which user approved it, and there is no per-resource or per-method
authorization. In practice this is fine only because the `/login` allow-list
makes tokens hard to obtain; any valid token has full read and write access to
everything below.

## What the API exposes

finale-rest turns each Sequelize model into a full resource: `GET` list (with
query-string filtering, `count`/`offset`/`sort` as finale defines them), `GET`
by primary key, `POST` to create, `PUT`/`PATCH` to update, `DELETE`. The
models are `sequelize-auto` dumps of the DocDB tables, so the JSON field names
are exactly the column names in [database.md](database.md).

| Endpoint | Table | Used by the provisioner for |
|----------|-------|----------------------------|
| `/Author`, `/Author/:AuthorID` | `Author` | one row per person (name, institution, `Active`) |
| `/EmailUser`, `/EmailUser/:EmailUserID` | `EmailUser` | the DocDB account row; links to the Author via `AuthorID` |
| `/RemoteUser`, `/RemoteUser/:RemoteUserID` | `RemoteUser` | maps the person's ePPN (`RemoteUserName`) to the `EmailUserID`; this is what makes a Shibboleth login resolve to a DocDB user |
| `/UsersGroup`, `/UsersGroup/:UsersGroupID` | `UsersGroup` | group memberships (`EmailUserID`, `GroupID`) |
| `/SecurityGroup`, `/SecurityGroup/:GroupID` | `SecurityGroup` | groups themselves, including the `CO:...` groups named after COmanage COUs and the `CanCreate`/`CanAdminister`/`CanView` flags |
| `/Institution`, `/Institution/:InstitutionID` | `Institution` | institutions referenced by authors |

Nothing else in DocDB is reachable through the API: no documents, revisions,
files or meetings.

Observed provisioning behaviour (from the data, not from the plugin source,
which is in the `cosmic-explorer/comanage-registry` fork): the plugin creates
`Author`, `EmailUser` and `RemoteUser` for a person with the **same numeric
ID** in all three tables (the `AUTO_INCREMENT` values of the three tables
move in lockstep from 1,000,000), which is why `EmailUserID == AuthorID`
holds for every user today. The DocDB code does not require that, and one
place (`CanModify`) accidentally depends on it (review M2). Membership
changes are applied by inserting `UsersGroup` rows without checking for an
existing identical row, which is the source of the duplication described in
review M5.

## Operating it

* **Logs**: `docker service logs dcc_rest-api`. A healthy start prints
  `Executing (default): SELECT 1+1 AS result` and `Listening on port 8443`.
  Each authorized request logs `Authorized connection from <subject>`.
* **Hydra**: `docker service logs dcc_oauth-server`; healthy start shows the
  two `Setting up http server` lines. Hydra runs with `LOG_LEVEL=debug`.
* **If provisioning stops working**: check in order that the API container is
  up and connected to MariaDB, that Hydra is up, that the refresh token has
  not been revoked or expired (re-run the authorization flow as one of the
  allow-listed people), and that COmanage can reach
  `https://dcc.cosmicexplorer.org/rest-dcc/` and `/oauth/`.
* **Changing the allow-list** is an Apache configuration change in
  `etc/httpd/conf.d/dcc-dev.conf` in this repository (and in the
  infrastructure Dockerfile for consistency), deployed per
  [UPDATING.md](../UPDATING.md). The `REST_AUTHORIZED_EPPN` secret is the
  first entry.
* **Rotating the client secret or `shib_header_secret`** means recreating the
  Hydra client (or updating it through the admin API) and the Swarm secret,
  then updating COmanage's plugin configuration.

## Things to be aware of

These are outside this repository's code but affect the DCC's security; they
are summarised in the [security review](security-review.md) under "Adjacent
component".

* `auth.js` logs every bearer token in clear text to the container log
  (`console.log(authType + ' ' + token)`). Anyone who can read
  `docker service logs dcc_rest-api` can replay a live token.
* Any active Hydra access token is accepted, regardless of client, scope or
  subject; there is no authorization below "has a token".
* The API can create or modify `SecurityGroup` rows including
  `CanAdminister`, and `UsersGroup` rows for any group, so a token holder can
  make anyone a DocDB administrator.
* No validation of values: names and e-mail addresses are stored as sent, and
  several DocDB pages render them without encoding (review L14, M15).
* The membership inserts are not idempotent (review M5).
* The stack runs Node 12 and 2019-era dependencies (Express 4.16, Sequelize 5,
  node-fetch 2); Dependabot reports vulnerabilities on the default branch of
  the infrastructure repository.
* Hydra v1.0.8 is also several years old. Its admin API is unauthenticated
  and relies entirely on network isolation within the Swarm overlay; the
  disabled URL-upload feature in DocDB would have been able to reach it
  (review I1).
