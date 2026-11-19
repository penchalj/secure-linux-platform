#!/usr/bin/env bash
# Post (or update) a CVE summary note on the merge request.
set -euo pipefail
: "${SLP_BOT_TOKEN:?}" "${CI_MERGE_REQUEST_IID:?}"

body=$(printf '<!-- secure-linux-cve-summary -->\n'; cat "$@")
api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/notes"

existing=$(curl -sS --header "PRIVATE-TOKEN: ${SLP_BOT_TOKEN}" "${api}?per_page=100" \
    | jq -r '.[] | select(.body | startswith("<!-- secure-linux-cve-summary -->")) | .id' | head -1)

if [[ -n "$existing" ]]; then
    curl --fail -sS -X PUT --header "PRIVATE-TOKEN: ${SLP_BOT_TOKEN}" \
        --data-urlencode "body=${body}" "${api}/${existing}" > /dev/null
else
    curl --fail -sS -X POST --header "PRIVATE-TOKEN: ${SLP_BOT_TOKEN}" \
        --data-urlencode "body=${body}" "${api}" > /dev/null
fi
echo "MR note updated"
