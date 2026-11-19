#!/usr/bin/env bash
# Keyless signing with Sigstore cosign using the GitLab OIDC token
# (id_tokens: SIGSTORE_ID_TOKEN). No long-lived signing key exists in CI.
# Each artefact gets <file>.sig + <file>.pem (Fulcio cert bound to this
# project, ref and pipeline) and is recorded in the Rekor transparency log.
set -euo pipefail
root="${1:-out}"
: "${SIGSTORE_ID_TOKEN:?id_tokens SIGSTORE_ID_TOKEN not configured}"

find "$root" -type f \( -name '*.raucb' -o -name '*.spdx.json' -o -name 'SHA256SUMS' \
                       -o -name '*.ext4' -o -name '*.wic.zst' \) | while read -r f; do
    echo "Signing $f"
    cosign sign-blob --yes \
        --identity-token "$SIGSTORE_ID_TOKEN" \
        --output-signature "$f.sig" \
        --output-certificate "$f.pem" \
        "$f"
done
