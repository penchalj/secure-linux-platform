#!/usr/bin/env bash
# Remove sstate objects not accessed for N days from the local runner cache.
# The Garage mirror is write-once; pruning it is a planned maintenance job.
set -euo pipefail
days="${1:-30}"
: "${SLP_CACHE_DIR:=/cache/yocto}"
dir="${SLP_CACHE_DIR}/sstate-cache"

before=$(du -sb "$dir" | cut -f1)
find "$dir" -type f -atime "+${days}" \( -name '*.tar.zst' -o -name '*.siginfo' -o -name '*.sig' \) -delete
find "$dir" -type d -empty -delete
after=$(du -sb "$dir" | cut -f1)
echo "Pruned $(( (before - after) / 1024 / 1024 )) MiB from local sstate (atime > ${days}d)"
