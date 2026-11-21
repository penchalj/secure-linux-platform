#!/usr/bin/env bash
# =============================================================================
# One-time seeding: copy the existing local caches into Garage over the S3 API
# (credentialed write path). Afterwards protected-ref pipelines keep the mirror
# up to date (publish step, v0.3 step 3).
#
#   /srv/yocto/cache/sstate-cache  -> s3://sstate     (sstate objects + siginfo)
#   /srv/yocto/cache/downloads     -> s3://downloads  (top-level tarballs only)
#
# Usage: infra/cache/seed-cache.sh        (normal user; takes a while)
# =============================================================================
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "run as your normal user, not sudo" >&2; exit 1; }

CACHE="${SLP_CACHE_DIR:-/srv/yocto/cache}"
ENVF="${SLP_SERVICES_DIR:-/srv/yocto/services}/garage/ci-publisher.env"
[[ -r "$ENVF" ]] || { echo "missing $ENVF (run bootstrap-cache.sh first)" >&2; exit 1; }

rclone() {
  docker run --rm --network yocto-cache --env-file "$ENVF" \
    -v "$CACHE:/cache:ro" rclone/rclone:latest "$@" \
    --s3-provider Other --s3-env-auth --s3-endpoint http://garage:3900 \
    --s3-region garage --s3-force-path-style \
    --transfers 8 --checkers 16 --stats 30s --stats-one-line -v
}

echo "== sstate: $(du -sh "$CACHE/sstate-cache" | cut -f1)"
rclone copy /cache/sstate-cache :s3:sstate \
  --include "*.tar.zst" --include "*.siginfo" --include "*.sig" \
  --min-size 1B   # never publish 0-byte objects (crash leftovers break fetches)

echo "== downloads (top-level tarballs): $(du -sh "$CACHE/downloads" | cut -f1)"
rclone copy /cache/downloads :s3:downloads --max-depth 1 \
  --exclude "*.done" --exclude "*.lock" --exclude "*_bad-checksum_*" --exclude "*.tmp"

echo "== bucket sizes"
rclone size :s3:sstate
rclone size :s3:downloads

echo "== read-only check: one sstate object via the web endpoint (expect 200)"
obj="$(cd "$CACHE/sstate-cache" && find . -name '*.tar.zst' -print -quit | sed 's|^\./||')"
docker run --rm --network yocto-cache curlimages/curl:latest -s -o /dev/null -I \
  -w "GET http://sstate.web.garage:3902/<obj>: HTTP %{http_code}\n" \
  "http://sstate.web.garage:3902/${obj}"
echo "== write via web endpoint must be refused (expect 4xx)"
docker run --rm --network yocto-cache curlimages/curl:latest -s -o /dev/null \
  -X PUT --data x -w "PUT on read-only endpoint: HTTP %{http_code}\n" \
  "http://sstate.web.garage:3902/poison-test"
