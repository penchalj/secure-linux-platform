#!/usr/bin/env bash
# Yocto build step for GitLab CI. Runs as the unprivileged user "builder"
# (bitbake refuses root). Called by .gitlab-ci.yml via runuser.
set -euo pipefail

: "${MACHINE:?}" "${KAS_WORK_DIR:?}" "${KAS_BUILD_DIR:?}" "${CI_PROJECT_DIR:?}"
cd "$CI_PROJECT_DIR"

mkdir -p "$KAS_WORK_DIR"
# Fresh tmp every run: the image is always assembled from sstate, never from
# leftovers of a previous job (reproducible, measurable)
rm -rf "$KAS_BUILD_DIR/tmp"

kas build "$CI_PROJECT_DIR/kas/machines/${MACHINE}.yml:$CI_PROJECT_DIR/kas/features/local-vm.yml" 2>&1 | tee build.log

python3 ci/scripts/cache_stats.py build.log --machine "$MACHINE" \
    --metrics metrics.txt --json "cache-stats-${MACHINE}.json"

DEPLOY="$KAS_BUILD_DIR/tmp/deploy/images/$MACHINE"
ls -lh "$DEPLOY" | tee "images-${MACHINE}.txt"
cp -L "$DEPLOY/secure-linux-image-${MACHINE}.rootfs.spdx.json" .
cp -L "$DEPLOY/secure-linux-image-${MACHINE}.rootfs.manifest" . || true
