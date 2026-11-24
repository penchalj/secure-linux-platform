#!/usr/bin/env bash
# Yocto build step for GitLab CI. Runs as the unprivileged user "builder"
# (bitbake refuses root). Called by .gitlab-ci.yml via runuser.
#
# Env: MACHINE, KAS_WORK_DIR, KAS_BUILD_DIR, DL_DIR, SSTATE_DIR,
#      KAS_FEATURES (colon-separated overlays, relative to the repo)
#      FRESH_RUNNER=1  -> start with EMPTY local DL_DIR/SSTATE_DIR
#                         (simulates a brand-new runner: everything must come
#                          from the shared read-only mirror)
set -euo pipefail

: "${MACHINE:?}" "${KAS_WORK_DIR:?}" "${KAS_BUILD_DIR:?}" "${CI_PROJECT_DIR:?}"
: "${KAS_FEATURES:=kas/features/local-vm.yml:kas/features/ci-mirror.yml}"
cd "$CI_PROJECT_DIR"

if [[ "${FRESH_RUNNER:-0}" == "1" ]]; then
    echo "FRESH_RUNNER=1: wiping local DL_DIR and SSTATE_DIR ($DL_DIR, $SSTATE_DIR)"
    rm -rf "$DL_DIR" "$SSTATE_DIR"
fi
mkdir -p "$KAS_WORK_DIR" "$DL_DIR" "$SSTATE_DIR"
# Keep TMPDIR between jobs on the same runner volume: the parse cache and the
# sstate-control state survive, so unchanged tasks are "Current" (no setscene
# unpack) and only what a commit really changes is rebuilt. Each runner has its
# own volume, so untrusted MR leftovers never reach the trusted build dir.
# CLEAN_TMP=1 (nightly / benchmarks / after a crash) restores the old
# "everything from sstate" behaviour.
if [[ "${CLEAN_TMP:-0}" == "1" ]]; then
    echo "CLEAN_TMP=1: removing $KAS_BUILD_DIR/tmp"
    rm -rf "$KAS_BUILD_DIR/tmp"
fi
# A kept TMPDIR accumulates one timestamped rootfs set (~110 MB) per build:
# keep only the last two days of deploy images
find "$KAS_BUILD_DIR/tmp/deploy/images" -type f -name '*.rootfs-2*' -mtime +2 -delete 2>/dev/null || true

# Protected main only: report hash equivalences to the central hashserv as
# "ci-reporter". The token comes from a CI variable scoped to environment
# "cache-report" (protected, masked) and goes to ~/.netrc - never to local.conf
# or the log. Without the token (MRs, branches) builds stay anonymous/read-only.
if [[ -n "${HASHSERV_REPORT_TOKEN:-}" ]]; then
    ( umask 077
      printf 'machine %s login %s password %s\n' "${HASHSERV_ADDRESS:-hashserv:8686}" \
          "${HASHSERV_REPORT_USER:-ci-reporter}" "$HASHSERV_REPORT_TOKEN" > "$HOME/.netrc" )
    # kas runs bitbake with an isolated, temporary HOME: a plain ~/.netrc is
    # never seen. NETRC_FILE makes kas copy it into that home (incident #15).
    export NETRC_FILE="$HOME/.netrc"
    KAS_FEATURES+=":kas/features/ci-report.yml"
    echo "hashserv: reporting as ${HASHSERV_REPORT_USER:-ci-reporter}"
else
    echo "hashserv: anonymous (read-only)"
fi

# Protected refs only: package revisions from the central PR service
if [[ "${CI_COMMIT_REF_PROTECTED:-false}" == "true" ]]; then
    KAS_FEATURES+=":kas/features/ci-prserv.yml"
    echo "prserv: central (prserv:8585)"
else
    KAS_FEATURES+=":kas/features/ci-prserv-ro.yml"
    echo "prserv: local, upstream prserv:8585 (read-only)"
fi

config="$CI_PROJECT_DIR/kas/machines/${MACHINE}.yml"
IFS=':' read -ra overlays <<< "$KAS_FEATURES"
for o in "${overlays[@]}"; do config+=":$CI_PROJECT_DIR/$o"; done
echo "kas config: $config"

# Maintenance mode (manual job on main): re-run do_fetch for every recipe of
# the image so existing git clones get their mirror tarballs; the next
# publish:cache uploads them. Removing the git done-stamps forces the fetcher
# to revisit each clone (incremental git fetch, then tarball creation).
if [[ "${FETCH_ALL:-0}" == "1" ]]; then
    before=$(ls -1 "$DL_DIR"/git2_*.tar.gz 2>/dev/null | wc -l)
    rm -f "$DL_DIR"/git2/*.done
    kas shell "$config" -c "bitbake --runall=fetch secure-linux-image" 2>&1 | tee build.log
    after=$(ls -1 "$DL_DIR"/git2_*.tar.gz 2>/dev/null | wc -l)
    echo "git mirror tarballs: before=${before} after=${after}" | tee fetch-all.txt
    exit 0
fi

kas build "$config" 2>&1 | tee build.log

python3 ci/scripts/cache_stats.py build.log --machine "$MACHINE" \
    --metrics metrics.txt --json "cache-stats-${MACHINE}.json"

DEPLOY="$KAS_BUILD_DIR/tmp/deploy/images/$MACHINE"
ls -lh "$DEPLOY" | tee "images-${MACHINE}.txt"
cp -L "$DEPLOY/secure-linux-image-${MACHINE}.rootfs.spdx.json" .
cp -L "$DEPLOY/secure-linux-image-${MACHINE}.rootfs.manifest" . || true

if [[ "${FRESH_RUNNER:-0}" == "1" ]]; then
    echo "FRESH_RUNNER=1: removing throw-away local caches"
    rm -rf "$DL_DIR" "$SSTATE_DIR" "$KAS_BUILD_DIR/tmp"
fi
