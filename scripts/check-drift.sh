#!/bin/bash
# Report files in the running dcc_dcc container that differ from its image
# under the paths this repository manages. Anything listed here is a hand edit
# that will be lost when the container is recreated (deploy, reboot, crash)
# and must be folded into the repository first.
#
# Exit status: 0 = no drift, 1 = drift found, 2 = container not running.

set -uo pipefail

CID=$(docker ps -q --filter name=dcc_dcc. | head -n1)
if [ -z "${CID}" ]; then
    echo "dcc_dcc container is not running" >&2
    exit 2
fi

MANAGED='^[ACD] /(usr1/www/cgi-bin|usr1/www/html/[^/]+$|etc/httpd/conf|etc/httpd/conf\.d|etc/httpd/conf\.modules\.d|etc/shibboleth|etc/shibboleth-ds|usr/local|etc/cron\.daily)'
# Expected run-time changes: passwords substituted into SiteConfig.pm by
# start-apache.sh, SP cert/key installed from secrets, bind-mounted files,
# and the *__Static staging directories start-apache.sh removes at boot.
RUNTIME='/(DocDB__Static|public__Static|SiteConfig\.pm|sp-(signing|encrypt)-(cert|key)\.pem|inc-md-cert\.pem|shibboleth2\.xml|attribute-map\.xml|x509-certs(/.*)?)$'

drift=0
while read -r kind path; do
    case "${kind}" in
        D) echo "deleted:  ${path}"; drift=1 ;;
        A|C)
            # directories show up as C whenever a child changed; skip them
            if docker exec "${CID}" test -d "${path}"; then continue; fi
            echo "changed:  ${path}"; drift=1 ;;
    esac
done < <(docker diff "${CID}" | grep -E "${MANAGED}" | grep -vE "${RUNTIME}")

if [ ${drift} -eq 0 ]; then
    echo "no drift: running container matches its image under managed paths"
fi
exit ${drift}
