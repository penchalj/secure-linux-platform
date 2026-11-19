#!/usr/bin/env bash
# Collect images, SBOMs, CVE reports and license manifests into out/<machine>/
set -euo pipefail
machine="$1"
out="${2:-out}/${machine}"
deploy="build/tmp/deploy"
img="secure-linux-image"

mkdir -p "$out"/{images,sbom,cve,licenses}

# Images (follow the stable symlinks, not the timestamped files)
for ext in ext4 tar.zst wic.zst qemuboot.conf manifest testdata.json; do
    f="${deploy}/images/${machine}/${img}-${machine}.rootfs.${ext}"
    [[ -e "$f" ]] && cp -L "$f" "$out/images/"
done
cp -L "${deploy}/images/${machine}"/*Image* "$out/images/" 2>/dev/null || true

# SBOM (SPDX 3.0 JSON-LD) incl. VEX statements
cp -L "${deploy}/images/${machine}/${img}-${machine}.rootfs.spdx.json" "$out/sbom/" 2>/dev/null || true
cp -L "${deploy}"/spdx/*/*/"${img}"*.spdx.json "$out/sbom/" 2>/dev/null || true

# CVE reports (cve-check JSON + sbom-cve-check output)
cp -L "${deploy}/images/${machine}/${img}-${machine}.rootfs.json" "$out/cve/cve-check.json" 2>/dev/null || true
cp -L "${deploy}/images/${machine}"/*sbom-cve-check* "$out/cve/" 2>/dev/null || true

# License manifest + texts
lic_dir=$(find "${deploy}/licenses" -maxdepth 1 -type d -name "${img}-${machine}*" | sort | tail -1)
if [[ -n "$lic_dir" ]]; then
    cp "$lic_dir/license.manifest" "$out/licenses/"
    cp "$lic_dir/package.manifest" "$out/licenses/" 2>/dev/null || true
fi

(cd "$out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
echo "Collected artifacts:"; find "$out" -type f | sed 's/^/  /'
