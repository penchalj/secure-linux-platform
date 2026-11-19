#!/usr/bin/env bash
# Nightly: download the SBOM of the latest release from the package registry
# and re-run the CVE gate in report mode against the refreshed CVE data.
set -euo pipefail
mkdir -p rescan
tag=$(curl -sS --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/releases?per_page=1" | jq -r '.[0].tag_name // empty')
[[ -n "$tag" ]] || { echo "No release yet"; exit 0; }

echo "Re-scanning release ${tag}"
for machine in qemux86-64 qemuarm64; do
    curl -sS --fail --header "JOB-TOKEN: ${CI_JOB_TOKEN}" -o "rescan/${machine}.spdx.json" \
        "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/secure-linux-os/${tag}/secure-linux-image-${machine}.rootfs.spdx.json" \
        || { echo "SBOM for ${machine} missing"; continue; }
    # VERIFY: CLI flags against `sbom-cve-check --help` of the Wrynose recipe version
    sbom-cve-check --sbom-path "rescan/${machine}.spdx.json" \
        --export-type cve-check --export-path "rescan/${machine}-cve.json" || true
    python3 ci/scripts/cve_gate.py --cve-json "rescan/${machine}-cve.json" \
        --max-cvss "${CVE_GATE_MAX_CVSS:-7.0}" --mode report \
        --markdown "rescan/${machine}-summary.md"
done
