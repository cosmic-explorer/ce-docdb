# Authentication and authorization

This page explains who DocDB thinks you are and what it lets you do. The
code involved is `DocDBGlobals.pm` (identity), `SecuritySQL.pm` (lookups),
`Security.pm` (decisions), `Cookies.pm` (self-imposed group limits),
`FSUtilities.pm::ProtectDirectory` and `RemoteUserHasAccess` (file access),
and the Apache configuration in `etc/httpd/conf.d/dcc-dev.conf`.

## Layer 1: Apache and Shibboleth

Apache is the only authentication point. `<Location />` in `dcc-dev.conf`
sets `AuthType shibboleth` with `ShibRequestSetting RequireSession true` and
`require shib-session`, so anything not explicitly opened needs a valid
Shibboleth session. Exceptions that are anonymous: the public CGI instance
(`/cgi-bin/DocDB`), the public file tree (`/public`), any URL ending in
`/public` (short URLs), static image/CSS/JS files, the Shibboleth handler and
discovery service, and the OAuth2/REST proxies.

A user without a session is redirected by mod_shib to the discovery service
at `/shibboleth-ds/`, chooses an identity provider (InCommon R&S or eduGAIN
institution, LIGO.org, or ORCID via the SUGWG gateway), authenticates there
and returns with SAML attributes. `attribute-map.xml` maps
`eduPersonPrincipalName` to `REMOTE_USER`. mod_shib exports it to CGI
scripts as the environment variable `REMOTE_USER`.

DocDB itself never sees a password. It also never creates an account at
login time: identity is only meaningful if a matching `RemoteUser` row exists
(see below).

## Layer 2: mapping the login to a DocDB user

`DocDBGlobals.pm` defines

```perl
use constant remote_user => &tolower($ENV{REMOTE_USER});
```

so every script has the lower-cased ePPN as `remote_user`. The mapping chain
is then (all in `SecuritySQL.pm`):

1. `FetchEmailUserIDFromRemoteUser()`:
   `select EmailUserID from RemoteUser where RemoteUserName like ("<ePPN>")`.
   The `RemoteUser` table is populated by the COmanage provisioner (REST
   API), one row per enrolled person, keyed by ePPN.
2. `EmailUser` is the DocDB "account" row: display name, e-mail address,
   notification preference, `CanSign`, and `AuthorID`, the link to the
   `Author` row used for authorship and for `SubmitterID`/`RequesterID` on
   revisions and documents. In this deployment the provisioner creates
   `Author`, `EmailUser` and `RemoteUser` together, and every `EmailUser`
   currently has `EmailUserID == AuthorID`. The code does **not** rely on
   that in general (see the review for one place where it accidentally does).
3. `FetchUserGroupIDs($EmailUserID)`:
   `select GroupID from UsersGroup where EmailUserID=?` gives the user's
   security groups.

`ProjectGlobals.pm` sets `$UserValidation = "kerberos"`, which selects this
`RemoteUser`-based path in `Security.pm::FindUsersGroups`. The older DocDB
models (one HTTP Basic user per group, or X.509 certificate mapping in
`CertificateUtilities.pm`) are still in the code but not active. If the user
has no groups at all, `FindUsersGroups` sets `$Public = 1`, turning the
request into a public-instance request even in the private tree.

## Layer 3: security groups

`SecurityGroup` rows carry four capability flags:

| Flag | Meaning |
|------|---------|
| `CanView` | Members may be granted view access to restricted revisions. |
| `CanCreate` | Members may create documents and (if also listed as a modify group) modify them. |
| `CanAdminister` | Members may use the administration pages and bypass view/modify checks. |
| `CanConfig` | Intended for configuration pages (`ConfigSQL.pm`); little used. |

`GroupHierarchy` rows (`ParentID`, `ChildID`) make a parent group inherit the
access of its children: a member of `ProjectDirectorate` can see anything
`CEConsortium` can see, because `CEConsortium` is a child of
`ProjectDirectorate`. The current production hierarchy is (child → parent):

```
Public_Pending, CEConsortium, CO:COU:Project:members:active, ProjectSystems, ProjectManagement → ProjectDirectorate
Public_Pending, CEConsortium, CO:COU:Project:members:active, ProjectSystems, ProjectSiteEval → ProjectManagement
Public_Pending, CEConsortium, CO:COU:Project:members:active → ProjectSystems
Public_Pending, CEConsortium → CO:COU:Project:members:active
```

Groups with special meaning, named in `ProjectGlobals.pm`:

* `Public_Pending` (`$Public_Group`): placed on a revision that has been
  requested public but not yet QA-checked. Nobody is a member; access to such
  a revision comes through the hierarchy (every project group is a parent of
  it).
* `Authors` (`$AuthorsOnly_Group`): a pseudo-group. When it appears in a
  revision's view or modify list, access is granted to anyone whose
  `EmailUser.AuthorID` is one of the revision's authors or is in one of its
  author groups (`isEmailUserAnAuthor`). Nobody is a direct member.
* `Public_Certify` (`$Certify_Group`): members (or parents) may certify
  documents public (`CanCertify`). It does not currently exist in the
  database, so `CanCertify` is false for everyone; the QA-check path relies
  on `CanAdminister` instead.
* `Obsolete` (`$Obsolete_Group`): referenced in configuration but not present.
* `CO:admins`: the administrators group provisioned from COmanage
  (`CanAdminister = 1`).

## Layer 4: per-revision access lists

Every `DocumentRevision` has zero or more rows in `RevisionSecurity` (groups
that may **view**) and, because `$EnhancedSecurity` is on, zero or more rows
in `RevisionModify` (groups that may **modify**). A revision with no
`RevisionSecurity` rows is public: `CanAccess` returns true for everyone,
including anonymous users of the public instance, and the file directory is
symlinked into `/public`.

### `CanAccess($DocumentID, $Version [, $EmailUserID])`

In order:

1. Resolve the caller to an `EmailUserID` and `AuthorID`. In the private
   instance, if the author is inactive (`Author.Active = 0`) or the revision
   has no submitter or the document no requester, deny.
2. If the caller is the revision's submitter or the document's requester,
   allow.
3. If the revision has no view groups, allow (public).
4. If the view list contains `Authors` and the caller is an author of the
   revision, allow.
5. If the caller `CanAdminister`, allow.
6. If any of the caller's groups with `CanView` is in the view list, allow.
7. If any child (via `GroupHierarchy`) of one of the caller's `CanView`
   groups is in the view list, allow.
8. Otherwise deny.

`LastAccess($DocumentID)` walks versions downward to find the newest one the
caller may see; `RetrieveFile` and `ShowDocument` use it when no version is
given.

### `CanModify($DocumentID [, $Version])`

Deny in the public instance or if the caller cannot create. Allow if the
caller `CanAdminister`. Otherwise, with enhanced security: allow if the
caller is the submitter or requester (see the review: this comparison mixes
ID types), or an author when `Authors` is in the modify list, or a member of
a `CanCreate` group in the modify list, or (`$SuperiorsCanModify`) a member
of a parent of such a group. If the revision has **no** modify groups, modify
rights fall back to view rights (`CanAccess`).

### `CanCreate()`, `CanAdminister()`, `CanCertify()`

`CanCreate` is true if any of the caller's groups has both `CanCreate` and
`CanView`. `CanAdminister` is true if any group has `CanAdminister`.
`CanCertify` checks membership of (or parenthood over) `Public_Certify`.

### Self-imposed limits (cookies)

`SelectGroups` / `SetGroups` let a user store a `groupids` cookie listing a
subset of their groups. `FindUsersGroups` intersects the real group list with
the cookie, so the user can preview what a less-privileged colleague sees.
The cookie can only remove groups, never add them.

## Layer 5: file downloads

Perl never streams files. `RetrieveFile` checks `CanAccess`, then redirects
to `/DocDB/NNNN/<alias>/VVV/<file>`. That location requires a Shibboleth
session and passes an external-group check: Apache runs
`RemoteUserHasAccess` for each request, which derives the alias and version
from the URI, looks the revision up, and calls `CanAccessRevision` for the
user. A non-zero exit denies the download. For public revisions, the
`/public/...` symlink serves the same file anonymously, so a user with the
public URL never hits this check.

Historically DocDB wrote per-directory `.htaccess` files
(`ProtectDirectory`); that code still runs but its `.htaccess` writing is
commented out, and the external authorizer replaces it.

## Making a revision public

The intended flow (`SecuritySQL.pm::UpdateRevisionPublicSecurity`, driven by
the `QAcheck` flag on `DocumentRevision`):

1. A submitter marks a revision for publication; it gets the
   `Public_Pending` view group and `QAcheck = 0`. Only project groups (as
   parents of `Public_Pending`) can see it.
2. An administrator performs the QA check (`QAcheck = 1`). The code deletes
   all `RevisionSecurity` rows for the revision and creates the `/public`
   symlink. From then on it is visible anonymously.
3. Reverting (`QAcheck = 0`) re-adds `Public_Pending` and removes the
   symlink.

## Administrative access to the OAuth2 login

Unrelated to DocDB groups: Apache's `<LocationMatch "^/login">` allows only
Shibboleth sessions whose ePPN is in a fixed list (the `REST_AUTHORIZED_EPPN`
secret plus three Syracuse accounts) to complete the Hydra login/consent
flow that authorizes the REST API client. Those people are, in effect, the
only ones who can mint tokens for the provisioning API.
