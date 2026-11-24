# Secure Linux Platform: Yocto DevSecOps reference platform on GitLab

A hardened embedded Linux distribution built with **Yocto 6.0 "Wrynose" LTS**
(supported until April 2030). It ships with a production-grade **GitLab CI/CD**
pipeline covering shift-left security, a multi-level build cache, SBOM and CVE
gates, signed OTA updates, SLSA provenance and EU **Cyber Resilience Act** evidence.

| | |
|---|---|
| Build | kas, Yocto Wrynose, `qemux86-64` + `qemuarm64` matrix |
| Cache | Runner volume + S3/MinIO sstate & download mirrors, hash equivalence, PR server, GitLab `cache:` for kas/CVE DB, BuildKit registry cache → [docs/CACHING.md](docs/CACHING.md) |
| Security | gitleaks, oelint-adv, SAST, Trivy, KSPP kernel policy, compiler hardening, rootfs audit, runtime oeqa hardening tests → [docs/SECURITY.md](docs/SECURITY.md) |
| Supply chain | SPDX 3.0 SBOM + VEX, CVE gate, license gate, GPG-signed sstate, cosign keyless signing, SLSA provenance, Renovate |
| Updates | RAUC A/B verity bundles signed with X.509 |
| Compliance | CRA Annex I traceability → [docs/CRA-COMPLIANCE.md](docs/CRA-COMPLIANCE.md) |

## Quick start (local)

```bash
pip install kas
kas build kas/machines/qemux86-64.yml:kas/features/security.yml
kas shell kas/machines/qemux86-64.yml -c "runqemu nographic slirp"
```

## GitLab setup

1. **Cache services:** `cp infra/.env.example infra/.env && docker compose -f infra/docker-compose.yml up -d`,
   then `infra/scripts/bootstrap-minio.sh`.
2. **Runners:** register with tags `yocto` (and `kvm` where `/dev/kvm` exists),
   using [infra/runner/config.toml](infra/runner/config.toml).
3. **CI/CD variables:** see the secrets table in [docs/SECURITY.md](docs/SECURITY.md).
   Override `SSTATE_MIRROR_URL`, `HASHSERV_URL` and the other endpoints in `ci/templates/variables.yml`.
4. **Protect** `main` and tags `v*`. Add a protected environment `production` with approval.
5. **Pin layers:** `kas lock kas/base.yml` and commit `kas/base.lock.yml`.
6. **Schedule:** nightly pipeline (e.g. 02:00 Europe/Berlin) for CVE DB refresh, sstate prune and release rescan.
7. **Dev keys:** `scripts/gen-dev-keys.sh` (git-ignored `keys/`).

## Pipeline

```
.pre      build-container ─ container:scan ─ container:sign      (+ nightly maintenance)
lint      recipes · yaml-kas · shell · dockerfile · kernel-hardening · gitleaks · SAST · secrets
build     build [qemux86-64, qemuarm64] · build:test-image
test      test:qemu  (oeqa → JUnit)
security  cve-gate · license-gate · sbom-upload · mr-comment
publish   release:build · release:sign                            (tags only)
release   release:publish → GitLab Release + Package Registry    (tags only, approval)
```

## Before the first real run, verify these

These items are marked `VERIFY` in the code. They depend on exact upstream versions:

- [ ] BitBake branch for Wrynose in `kas/base.yml` (Poky is split into bitbake / oe-core / meta-yocto since 6.0). Pin it with `kas lock`.
- [ ] `meta-rauc` and `meta-security` have `wrynose` branches.
- [ ] `sbom-cve-check` CLI flags in `ci/scripts/rescan-last-release.sh`.
- [ ] Real SHA256 values in `docker/checksums.txt`, and the kas image tag.
- [ ] `oelint-adv --release wrynose` is supported by the pinned oelint version.

## Roadmap ideas

- Secure boot chain (U-Boot FIT signing / UEFI + `systemd-ukify`, also new in Wrynose)
- dm-verity rootfs + TPM2 measured boot (meta-security `meta-tpm`)
- Hardware-in-the-loop with labgrid/LAVA on a real i.MX8 or Raspberry Pi 4
- Grafana dashboard for `cache-stats-*.json` and DORA metrics
- Merge trains + Premium "Security policies" (scan execution / MR approval policies)

