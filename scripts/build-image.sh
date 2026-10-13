#!/bin/bash
# Build a DCC image from the committed state of this repository.
#
# The image is tagged cosmicexplorer/dcc:ce-<git commit>, so every image can be
# traced back to the exact source it was built from and tags are never reused.
# Refuses to build from a dirty working tree for the same reason.
#
# Usage: scripts/build-image.sh            (uses cosmicexplorer/dcc:3.3.0 as base)
#        BASE_IMAGE=... scripts/build-image.sh

set -euo pipefail
cd "$(dirname "$0")/.."

BASE_IMAGE=${BASE_IMAGE:-cosmicexplorer/dcc:3.3.0}

if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree has uncommitted changes. Commit (and push) first so the image tag identifies the code." >&2
    git status --short >&2
    exit 1
fi

if ! docker image inspect "${BASE_IMAGE}" >/dev/null 2>&1; then
    echo "error: base image ${BASE_IMAGE} is not present on this host." >&2
    echo "It is built by ce-it-infrastructure/dcc/bootstrap-dcc.sh from dcc-syr-disk0.qcow2." >&2
    exit 1
fi

COMMIT=$(git rev-parse HEAD)
TAG="cosmicexplorer/dcc:ce-$(git rev-parse --short=12 HEAD)"

if docker image inspect "${TAG}" >/dev/null 2>&1; then
    echo "image ${TAG} already exists for this commit; nothing to build."
    exit 0
fi

docker build \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --label "org.opencontainers.image.revision=${COMMIT}" \
    --label "org.opencontainers.image.source=https://github.com/cosmic-explorer/ce-docdb" \
    --label "org.opencontainers.image.base.name=${BASE_IMAGE}" \
    -t "${TAG}" .

echo
echo "Built ${TAG}"
echo "Deploy it with: scripts/deploy-image.sh ${TAG}"
