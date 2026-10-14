#!/bin/bash
# Roll the dcc_dcc swarm service to a new image and verify it came up.
#
# Usage: scripts/deploy-image.sh cosmicexplorer/dcc:ce-<commit>
#
# This updates the *service spec* stored by Docker Swarm. Swarm recreates the
# container from that spec after a reboot or crash, so once this succeeds the
# new image is what runs until the next deploy. Expect a few minutes of
# downtime: the service uses stop-first updates and shibd takes time to
# validate InCommon metadata on start.

set -euo pipefail
cd "$(dirname "$0")/.."

TAG=${1:?usage: $0 cosmicexplorer/dcc:ce-<commit>}
SERVICE=dcc_dcc
URL=${DCC_URL:-https://dcc.cosmicexplorer.org/cgi-bin/DocDB/DocumentDatabase}
WAIT_SECONDS=${WAIT_SECONDS:-900}

if ! docker image inspect "${TAG}" >/dev/null 2>&1; then
    echo "error: image ${TAG} is not present on this host. Build it with scripts/build-image.sh" >&2
    exit 1
fi

# Refuse to throw away hand edits in the running container.
set +e
scripts/check-drift.sh
rc=$?
set -e
case "${rc}" in
    0) ;;
    1)
        if [ "${FORCE:-0}" != "1" ]; then
            echo >&2
            echo "error: the running container has edits that are not in its image (listed above)." >&2
            echo "Fold them into this repository and rebuild, or rerun with FORCE=1 to discard them." >&2
            exit 1
        fi
        echo "warning: FORCE=1 set; the edits listed above will be lost" >&2 ;;
    *)
        # A missing container or a failed inspection must never read as "no drift".
        echo "error: drift inspection failed (exit ${rc}); not deploying, even with FORCE=1" >&2
        exit 1 ;;
esac

PREVIOUS=$(docker service inspect "${SERVICE}" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
echo "current image:  ${PREVIOUS}"
echo "new image:      ${TAG}"
echo

# The image exists only on this host, so Docker warns that it cannot record a
# registry digest. That warning is expected on this single-node swarm.
docker service update --image "${TAG}" --detach=false "${SERVICE}"

echo
echo "waiting up to ${WAIT_SECONDS}s for ${URL} to answer 200 ..."
deadline=$((SECONDS + WAIT_SECONDS))
while [ ${SECONDS} -lt ${deadline} ]; do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "${URL}" || true)
    if [ "${code}" = "200" ]; then
        echo "DCC is answering (HTTP 200)."
        break
    fi
    sleep 15
done
if [ "${code:-}" != "200" ]; then
    echo "error: DCC did not answer 200 within ${WAIT_SECONDS}s (last code: ${code:-none})." >&2
    echo "Inspect with: docker service logs --tail 200 ${SERVICE}" >&2
    echo "Roll back with: docker service update --image ${PREVIOUS} --detach=false ${SERVICE}" >&2
    exit 1
fi

echo
echo "service spec now references: $(docker service inspect "${SERVICE}" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')"
docker service ps --filter desired-state=running --format '{{.Name}}  {{.Image}}  {{.CurrentState}}' "${SERVICE}"
echo
echo "NEXT: set 'image: ${TAG}' for the dcc service in ce-it-infrastructure/dcc/dcc.yml"
echo "      and commit it, so a future 'docker stack deploy' does not roll back to ${PREVIOUS}."
echo "Roll back if needed with: docker service update --image ${PREVIOUS} --detach=false ${SERVICE}"
