#!/usr/bin/env bash
# Sourced by every Yocto job. Decides cache mode and prepares the cache dirs.
#
#   protected ref  -> READ-WRITE: import GPG key, may publish sstate/downloads
#   anything else  -> READ-ONLY : mirrors are consumed, nothing is published
#
# shellcheck disable=SC2034  # variables are consumed by kas/bitbake
set -euo pipefail

: "${SLP_CACHE_DIR:=/cache/yocto}"
: "${SLP_CVE_DB_DIR:=${SLP_CACHE_DIR}/cve-db}"
export SLP_CACHE_DIR SLP_CVE_DB_DIR

mkdir -p "${SLP_CACHE_DIR}/sstate-cache" \
         "${SLP_CACHE_DIR}/downloads" \
         "${SLP_CVE_DB_DIR}" \
         "${KAS_REPO_REF_DIR:-.cache/kas-repos}"

if [[ "${CI_COMMIT_REF_PROTECTED:-false}" == "true" ]]; then
    export SLP_CACHE_MODE="rw"
    if [[ -n "${SLP_SSTATE_GPG_KEY_FILE:-}" ]]; then
        gpg --batch --import "${SLP_SSTATE_GPG_KEY_FILE}"
    fi
else
    export SLP_CACHE_MODE="ro"
    # Untrusted pipelines must never see write credentials, even by accident
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY SLP_SSTATE_GPG_PASSPHRASE || true
fi

# Public key is needed by everyone to verify signed sstate objects
if [[ -n "${SLP_SSTATE_GPG_PUBKEY_FILE:-}" ]]; then
    gpg --batch --import "${SLP_SSTATE_GPG_PUBKEY_FILE}" 2>/dev/null || true
fi

echo "== Secure Linux cache =="
echo "mode=${SLP_CACHE_MODE} dir=${SLP_CACHE_DIR}"
echo "sstate local: $(du -sh "${SLP_CACHE_DIR}/sstate-cache" 2>/dev/null | cut -f1)"
echo "downloads   : $(du -sh "${SLP_CACHE_DIR}/downloads" 2>/dev/null | cut -f1)"
echo "hashserv=${HASHSERV_URL:-none} prserv=${PRSERV_URL:-none}"
