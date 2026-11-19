#!/usr/bin/env bash
# Create buckets, least-privilege users and lifecycle rules in MinIO.
#   ci-publisher : write sstate/downloads  (protected CI variables only)
#   runner-cache : read/write GitLab runner cache bucket
set -euo pipefail
: "${MINIO_ALIAS:=secure-linux}" "${MINIO_URL:=http://localhost:9000}"
: "${MINIO_ROOT_USER:?}" "${MINIO_ROOT_PASSWORD:?}"
: "${PUBLISHER_SECRET:?}" "${RUNNER_CACHE_SECRET:?}"

here="$(cd "$(dirname "$0")/.." && pwd)"
mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

for b in secure-linux-sstate secure-linux-downloads gitlab-runner-cache; do
    mc mb --ignore-existing "$MINIO_ALIAS/$b"
done

# Expire sstate objects not re-uploaded/accessed for 60 days, runner cache after 14
mc ilm import "$MINIO_ALIAS/secure-linux-sstate" < "$here/minio/lifecycle-sstate.json"
mc ilm rule add --expire-days 14 "$MINIO_ALIAS/gitlab-runner-cache"

mc admin policy create "$MINIO_ALIAS" sstate-publish "$here/minio/policy-publish.json"
mc admin user add "$MINIO_ALIAS" ci-publisher "$PUBLISHER_SECRET"
mc admin policy attach "$MINIO_ALIAS" sstate-publish --user ci-publisher

mc admin user add "$MINIO_ALIAS" runner-cache "$RUNNER_CACHE_SECRET"
mc admin policy attach "$MINIO_ALIAS" readwrite --user runner-cache
echo "MinIO bootstrap complete"
