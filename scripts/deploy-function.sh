#!/usr/bin/env bash
# Build, push and deploy the function image. Same script on the VM and in CI.
#   usage: scripts/deploy-function.sh <function-ocid> [image-tag]
# Needs: docker logged in to OCIR, oci CLI authenticated.
# The tag defaults to the last commit that touched function/ (the image's source).
set -euo pipefail
FUNCTION_ID=$1
cd "$(dirname "$0")/.."
TAG=${2:-$(git log -1 --format=%h -- function)}
REPO=${IMAGE_REPO:-fra.ocir.io/frjpwvcxyneb/antonime/function}
IMAGE=$REPO:$TAG
export SUPPRESS_LABEL_WARNING=True

# --provenance=false: one plain arm64 manifest, not an index with an
# "unknown/unknown" attestation entry.
docker build -q --provenance=false --build-arg GIT_SHA="$TAG" -t "$IMAGE" function >/dev/null
docker push -q "$IMAGE" >/dev/null
digest=$(docker inspect --format '{{index .RepoDigests 0}}' "$IMAGE")
echo "pushed $digest"

# Deploy by digest: the function runs exactly the bytes we just pushed.
oci fn function update container-function --function-id "$FUNCTION_ID" \
  --image "$IMAGE" --image-digest "${digest#*@}" --force >/dev/null
# The update call is synchronous (no work request); still, verify what OCI
# reports as deployed before calling it done.
for _ in $(seq 1 30); do
  deployed=$(oci fn function get --function-id "$FUNCTION_ID" \
    --query 'data."source-details"."image-digest"' --raw-output)
  if [ "$deployed" = "${digest#*@}" ]; then
    echo "deployed $IMAGE (${deployed})"
    exit 0
  fi
  sleep 2
done
echo "deployed digest is '$deployed', expected '${digest#*@}'" >&2
exit 1
