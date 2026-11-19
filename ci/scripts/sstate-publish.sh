#!/usr/bin/env bash
# Publish new sstate objects and source tarballs to the shared S3 mirrors.
# Runs in after_script of build jobs; no-op on unprotected refs.
set -euo pipefail

if [[ "${CI_COMMIT_REF_PROTECTED:-false}" != "true" ]]; then
    echo "Read-only pipeline: skipping sstate publish (cache-poisoning protection)"
    exit 0
fi
if [[ "${CI_JOB_STATUS:-success}" == "canceled" ]]; then
    echo "Job canceled: skipping publish"; exit 0
fi

: "${SLP_CACHE_DIR:=/cache/yocto}"
: "${SSTATE_BUCKET:?}" "${DL_BUCKET:?}"

# Only objects that have a signature are published (unsigned = untrusted)
echo "Publishing sstate -> ${SSTATE_BUCKET}"
aws s3 sync "${SLP_CACHE_DIR}/sstate-cache" "${SSTATE_BUCKET}" \
    --size-only --no-progress \
    --exclude "*" --include "*.tar.zst" --include "*.tar.zst.sig" \
    --include "*.siginfo"

echo "Publishing download mirror tarballs -> ${DL_BUCKET}"
aws s3 sync "${SLP_CACHE_DIR}/downloads" "${DL_BUCKET}" \
    --size-only --no-progress \
    --exclude "*" --include "*.tar.gz" --include "*.tar.bz2" --include "*.tar.xz" \
    --include "*.zip" --include "git2_*.tar.gz" --exclude "*.lock" --exclude "*.done"
