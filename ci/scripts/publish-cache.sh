#!/bin/sh
# =============================================================================
# Publish new build-cache objects from the TRUSTED runner cache to the shared
# Garage mirror (S3 write path). Runs only in `publish:cache`:
#   - protected default branch only (rules + check below)
#   - credentials are CI variables scoped to environment "cache-publish",
#     so no other job (build, lint, MR) ever sees them
#   - serialised by resource_group "cache-publish"
#
# Write-once semantics: objects are content-addressed (sstate: unihash,
# downloads: checksummed tarballs), so an object that already exists in the
# mirror is never overwritten (--ignore-existing). 0-byte files are never
# published (--min-size 1B): crash leftovers broke mirror fetches (incident #11).
#
# POSIX sh: runs in the rclone image (Alpine/busybox).
# =============================================================================
set -eu

: "${AWS_ACCESS_KEY_ID:?publish credentials missing (environment-scoped CI variable)}"
: "${AWS_SECRET_ACCESS_KEY:?publish credentials missing (environment-scoped CI variable)}"
if [ "${CI_COMMIT_REF_PROTECTED:-false}" != "true" ]; then
    echo "refusing to publish from an unprotected ref (${CI_COMMIT_REF_NAME:-?})" >&2
    exit 1
fi

CACHE="${SLP_CACHE:-/cache/yocto}"
ENDPOINT="${S3_ENDPOINT:-http://garage:3900}"

publish() {  # $1 = label, $2 = local dir, $3 = bucket, rest = filters
    label="$1"; src="$2"; bucket="$3"; shift 3
    log="publish-${label}.log"
    echo "== ${label}: ${src} -> s3://${bucket}"
    rclone copy "$src" ":s3:${bucket}" "$@" \
        --ignore-existing --min-size 1B \
        --s3-provider Other --s3-env-auth --s3-endpoint "$ENDPOINT" \
        --s3-region garage --s3-force-path-style \
        --transfers 8 --checkers 16 --fast-list \
        --log-level INFO --log-file "$log" --stats 0
    n=$(grep -c 'Copied (new)' "$log" || true)
    echo "   new objects: ${n}"
    echo "publish_${label}_new_objects ${n}" >> metrics.txt
}

: > metrics.txt
publish sstate "${CACHE}/sstate-cache" sstate \
    --include "*.tar.zst" --include "*.tar.zst.siginfo" --include "*.tar.zst.sig"
publish downloads "${CACHE}/downloads" downloads --max-depth 1 \
    --exclude "*.done" --exclude "*.lock" --exclude "*_bad-checksum_*" --exclude "*.tmp"

echo "== done"
cat metrics.txt
