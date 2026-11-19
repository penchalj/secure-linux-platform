# EU Cyber Resilience Act – traceability

Regulation (EU) 2024/2847. Vulnerability **reporting** obligations apply from
**11 Sep 2026**, and the full requirements apply from **11 Dec 2027**. German
OEMs and Tier-1s are hiring for exactly this evidence chain now.

> This mapping shows engineering evidence. It is not a legal conformity assessment.

| CRA requirement (Annex I) | Secure Linux evidence | Artefact |
|---|---|---|
| Part I (2)(a): no known exploitable vulnerabilities | `security:cve-gate` blocks untriaged CVSS ≥ 7 | `junit-cve-*.xml`, `cve-summary-*.md` |
| Part I (2)(b): secure by default configuration | Locked root, no debug-tweaks, read-only rootfs, rootfs audit | `secure-linux-image.bb` |
| Part I (2)(c): security updates | Signed RAUC A/B bundles, Renovate weekly bumps | `*.raucb` + `.sig` |
| Part I (2)(d): protection from unauthorised access | systemd sandboxing, nftables, SSH only | `secure-linux-agent.service`, oeqa tests |
| Part I (2)(f): integrity of data and software | Signed sstate, signed artefacts, verity bundles | `.sig`, `.pem`, Rekor entries |
| Part I (2)(h)/(j): limit attack surface, reduce impact | Minimal distro features, kernel KSPP fragment, sysctls | `secure-linux.conf`, `hardening.cfg` |
| Part I (2)(l): security monitoring/logging | `audit` package, journald | image manifest |
| Part II (1): identify and document components (SBOM) | SPDX 3.0 SBOM per image, shipped with every release | `*.spdx.json` |
| Part II (2): address vulnerabilities without delay | Nightly rescan of last release against fresh NVD data | `maintenance:release-rescan` |
| Part II (4): publicly disclose fixed vulnerabilities | VEX statements in SBOM (`SPDX_INCLUDE_VEX`) | SBOM |
| Part II (7): secure distribution of updates | cosign + RAUC signature chain, protected release env | GitLab Release |
| Annex VII: technical documentation | This repo: docs, pipeline logs, SLSA provenance | GitLab |
