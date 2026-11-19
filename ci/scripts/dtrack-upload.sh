#!/usr/bin/env bash
# Upload the image SBOM to OWASP Dependency-Track (continuous CVE monitoring).
# Needs: DTRACK_URL, DTRACK_API_KEY (masked+protected CI variables).
set -euo pipefail
sbom_dir="$1"; project="$2"; version="$3"
: "${DTRACK_URL:?}" "${DTRACK_API_KEY:?}"

sbom=$(find "$sbom_dir" -name '*.spdx.json' | head -1)
[[ -n "$sbom" ]] || { echo "No SBOM found in $sbom_dir"; exit 1; }

curl --fail -sS -X POST "${DTRACK_URL}/api/v1/bom" \
    -H "X-Api-Key: ${DTRACK_API_KEY}" \
    -F "autoCreate=true" \
    -F "projectName=${project}" \
    -F "projectVersion=${version}" \
    -F "bom=@${sbom}"
echo "Uploaded ${sbom} to Dependency-Track as ${project}@${version}"
