#!/bin/bash
# Report files in the running dcc_dcc container that differ from its image
# under the paths this repository manages. Anything listed here is a hand edit
# that will be lost when the container is recreated (deploy, reboot, crash)
# and must be folded into the repository first.
#
# Exit status: 0 = no drift, 1 = drift found, 2 = container not running,
#              3 = Docker inspection failed (never treat as "no drift").

set -uo pipefail

if ! containers=$(docker ps -q --filter name=dcc_dcc.); then
    echo "error: could not list dcc_dcc containers" >&2
    exit 3
fi
CID=${containers%%$'\n'*}
if [ -z "${CID}" ]; then
    echo "dcc_dcc container is not running" >&2
    exit 2
fi

MANAGED='^[ACD] /(usr1/www/cgi-bin|usr1/www/html|etc/httpd/conf|etc/httpd/conf\.d|etc/httpd/conf\.modules\.d|etc/shibboleth|etc/shibboleth-ds|usr/local|etc/cron\.daily)(/|$)'
# Expected run-time changes: passwords substituted into SiteConfig.pm by
# start-apache.sh, SP cert/key installed from secrets, bind-mounted files,
# and the *__Static staging directories start-apache.sh removes at boot.
RUNTIME='/(DocDB__Static|public__Static|SiteConfig\.pm|sp-(signing|encrypt)-(cert|key)\.pem|inc-md-cert\.pem|shibboleth2\.xml|attribute-map\.xml|x509-certs(/.*)?)$'

if ! changes=$(docker diff "${CID}"); then
    echo "error: could not inspect filesystem changes in ${CID}" >&2
    exit 3
fi

drift=0
while IFS= read -r change; do
    [ -n "${change}" ] || continue
    [[ "${change}" =~ ${MANAGED} ]] || continue
    kind=${change%% *}
    path=${change#* }
    [[ "${path}" =~ ${RUNTIME} ]] && continue
    case "${kind}" in
        D) echo "deleted:  ${path}"; drift=1 ;;
        A|C)
            # directories show up as C whenever a child changed; skip them,
            # but a symlink to a directory is a file change and is reported
            if ! kind_in_container=$(docker exec "${CID}" sh -c 'if test -L "$1"; then echo file; elif test -d "$1"; then echo directory; else echo file; fi' sh "${path}"); then
                echo "error: could not inspect ${path} in ${CID}" >&2
                exit 3
            fi
            [ "${kind_in_container}" = "directory" ] && continue
            echo "changed:  ${path}"; drift=1 ;;
    esac
done <<< "${changes}"

if [ ${drift} -eq 0 ]; then
    echo "no drift: running container matches its image under managed paths (expected runtime files excluded)"
fi
exit ${drift}
