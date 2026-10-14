# Code layout and conventions

## Directory layout (mirrors the container filesystem)

```
usr1/www/cgi-bin/private/DocDB/   the DocDB application (182 entries)
usr1/www/cgi-bin/DocDB/           public instance: 79 symlinks + 7 regular files
usr1/www/html/{DocDB,public}/Static/{css,js,img,images}
etc/httpd/conf.d/dcc-dev.conf     the virtual host; short_urls.*.conf; dcc.public.conf
etc/shibboleth/                   SP config (shibboleth2.xml, attribute-map.xml, certs)
etc/shibboleth-ds/                embedded discovery service + landing page
usr/local/etc/supervisord.conf    container process supervisor
usr/local/sbin/start-apache.sh    entrypoint wrapper for httpd
usr/local/sbin/start-shibd.sh     entrypoint wrapper for shibd
etc/cron.daily/{dcc-glimpse,renew-certs.sh}
```

## Kinds of files in the application directory

| Kind | Naming | Example |
|------|--------|---------|
| CGI entry point | capitalised, no extension, `#!/usr/bin/env perl` | `ShowDocument`, `ProcessDocumentAdd` |
| Database module | `<Area>SQL.pm` | `DocumentSQL.pm`, `MeetingSQL.pm` |
| HTML rendering module | `<Area>HTML.pm` | `RevisionHTML.pm` |
| General helpers | `<Area>Utilities.pm` | `FSUtilities.pm`, `TalkHintUtilities.pm` |
| Help text | `*Instructions.pm`, `DocDBHelp.xml`, `ProjectHelp.xml` | `GeneralInstructions.pm` |
| Configuration | `DocDBGlobals.pm`, `ProjectGlobals.pm`, `SiteConfig.pm` | |
| Vendored library | `Defang.pm` (HTML::Defang), `Params/Validate*.pm` | |
| Templates from upstream | `*.template` | `ProjectGlobals.pm.template` |

Application files are in `package main` (the vendored `HTML::Defang` and
`Params::Validate` use their own packages and `use strict`). Modules are
loaded with `require "X.pm";`
(string form, resolved through `use lib "/usr1/www/cgi-bin/private/DocDB/"`
in `CGIInclude.pm` or the current directory) and simply define subroutines
and globals; there are no `package` declarations, no `use strict`, and no
exported symbols. Redefinition warnings are avoided by each module being
required once per process.

## Configuration precedence

```
DocDBGlobals.pm   defaults for everything (do not edit)
   └─ requires ProjectGlobals.pm   Cosmic Explorer settings; overrides globals
         └─ requires SiteConfig.pm   host-specific: DB, paths, URLs, feature flags
```

`ProjectGlobals.pm` sets `$Project`, `$ShortProject = "CE"`, the admin
e-mail, `$EnhancedSecurity`, `$UserValidation = "kerberos"`,
`$UseAliasAsFileName`, the special group names, review states and document
types used by the P&P review hook. `SiteConfig.pm` sets `$db_*`,
`$file_root`, `$script_root`, `$public_root`, `$host_name`, `$cgi_root`,
`$web_root`, and `$Public` in the public copy. After these, `DocDBGlobals.pm`
derives the full URL of every script (`$ShowDocument = $cgi_root."ShowDocument"`
and so on); scripts link to each other through those variables.

Database passwords in `SiteConfig.pm` are the placeholder `Change.Me.too!`
in the repository and the image; `start-apache.sh` substitutes the real
values from Docker secrets when the container starts.

## Anatomy of a CGI script

```perl
#! /usr/bin/env perl
use CGI;
use DBI;
require "DocDBGlobals.pm";          # pulls in Utilities, ProjectGlobals, SiteConfig
require "ResponseElements.pm";      # EndPage, error/warn rendering
require "HTMLUtilities.pm";         # DocDBHeader/DocDBFooter/navigation
require "Security.pm";              # CanAccess, CanModify, ...
require "DocumentSQL.pm"; ...       # whatever the script needs

$query = new CGI;                   # global, used by helpers
%params = $query -> Vars;           # all parameters as a flat hash
my $DocumentID = $params{docid};    # read inputs

$dbh = DBI->connect('DBI:mysql:'.$db_name.':'.$db_host, $db_rwuser, $db_rwpass);
GetSecurityGroups();                # fills %SecurityGroups, %GroupsHierarchy

unless (CanModify($DocumentID)) { push @ErrorStack, "..."; }
if (@ErrorStack) {                  # validation failed
  print $query->header(-charset => $HTTP_ENCODING);
  DocDBHeader("Title"); EndPage(); # EndPage prints errors and exits
}
...                                 # do the work, push @ActionStack, @WarnStack
print $query->header(-charset => $HTTP_ENCODING);
DocDBHeader("Title", "Page title", -scripts => ["PopUps"]);
EndPage();                          # prints warnings/errors if any, exits on error
...                                 # print the page body
DocDBNavBar();
DocDBFooter($DBWebMasterEmail, $DBWebMasterName);
```

Conventions worth knowing:

* **Caches as globals.** `Fetch*` routines fill global hashes
  (`%Documents`, `%DocRevisions`, `%Authors`, `%SecurityGroups`, ...) keyed
  by ID and return early if the entry exists. Routines that need fresh data
  call `Clear*` first. Because each request is a new process this is safe,
  but within one request stale entries are possible after an update.
* **Message stacks.** `@ErrorStack` (fatal, page ends), `@WarnStack`,
  `@ActionStack` (what was done) and `@DebugStack` are printed by
  `ResponseElements.pm`. `$UseDeadlyWarning` makes some warnings fatal.
* **Multi-value parameters.** `$query->Vars` joins repeated parameters with
  `\0`; code splits on `\0` or uses `$query->param('name')` in list context.
* **Form element builders.** `FormElements.pm`, `*HTML.pm` provide
  `AuthorScroll`, `TopicScroll`, `SecurityScroll` and friends taking a hash
  ref of options (`-name`, `-default`, `-multiple`, `-helplink`, ...), as
  described in the in-tree `README`.
* **Output escaping.** `SafeHTML()` (HTML::Defang) is the sanitizer for
  rich-text fields (abstracts, notes); `HTML::Entities::encode` is used in
  a few places for plain values. Many outputs are not escaped at all; see
  the [security review](security-review.md).
* **SQL.** Most queries use `prepare` with `?` placeholders. A minority
  interpolate values; the review lists them.
* **Dates.** Dates travel as `YYYY-MM-DD` strings checked by
  `SQLChecks.pm::CheckSQLDate`; times are MySQL `datetime` values converted
  with `Time::Local` in a few places.
* **Public awareness.** Code that must behave differently when anonymous
  tests `$Public`. The public `SiteConfig.pm` sets it; `FindUsersGroups`
  also sets it for a logged-in user with no groups.

## Cosmic Explorer customisations relative to the LIGO code

Applied by the `ce-it-infrastructure` Dockerfile when the image was first
built and now simply part of this snapshot:

* Project name and short code (`Cosmic Explorer` / `CE`), admin e-mail,
  `dcc.cosmicexplorer.org` host name in `SiteConfig.pm`, `ProjectGlobals.pm`
  and `httpd.conf`.
* `$SecureMainPage` points at the Shibboleth login with the home page as
  target; `Utilities.pm::urlencode` was added for that.
* Home page (`DocumentDatabase`): LIGO wiki and "Other DCC Projects" blocks
  removed.
* `AuthorSQL.pm`: author matching splits first name and middle initials
  (`AuthorSQL.pm.patch` in the infrastructure repo).
* `SiteConfig.pm`: `$db_host = docdb-database` (the swarm service), mail via
  `smtp-host.syr.edu`.
* `ListBy`: all query parameters HTML-encoded on entry (production hot-fix).
* Apache: embedded discovery service and the Cosmic Explorer landing page,
  reverse proxies for Hydra and the REST API, `/login` ePPN allow-list.

Leftovers from LIGO that are still in the code and should be treated as
dead or wrong for Cosmic Explorer: `Utilities.pm::URLify` builds links to
`https://<hostname>.ligo.org`; `$GroupSuffix = "@ligo.org"`; `pnp-dev.ligo.org`
and the `ProcessPNPReview` / `ncat` hook; Apache `AuthName` strings mention
LIGO/Virgo; `e-traveler.conf` references a LIGO E-Traveler application that
is not installed; `DefangUrlCallback` whitelists `ligo.org` but is not wired
in; `test.pl` in `cgi-bin/` is a Sentry test stub with an embedded DSN.

## Static assets

`usr1/www/html/DocDB/Static/` and `usr1/www/html/public/Static/` are served
from host directories, not from the image. `css/` holds per-script style
sheets (`DocDB<Script>.css`), a project sheet (`CEDocDB.css`, a symlink to
`LIGODocDB.css.dcc-dev-private`) and an `_IE` variant mechanism;
`HTMLUtilities.pm::DocDBHeader` includes whichever of these exist. `js/`
holds Prototype.js-era scripts: author list handling, signature widgets
(`getRemoteUser`, `observeSigDivs`), the server-status poller
(`startServerStatus` hitting `serverstatus.sh`), and `PopUps`. MathJax is
loaded from cdnjs for LaTeX in abstracts.
