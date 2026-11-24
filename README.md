# Secure Linux Platform

**A hardened Yocto 6.0 LTS ("Wrynose") reference platform with a GitLab DevSecOps pipeline:**
multi-level build cache, cache-poisoning protection, signed build artifacts, SBOM, and a
roadmap to signed OTA updates and EU Cyber Resilience Act evidence.

Source of truth: [gitlab.com/secure-linux/secure-linux-platform](https://gitlab.com/secure-linux/secure-linux-platform) ·
Mirror: [github.com/penchalj/secure-linux-platform](https://github.com/penchalj/secure-linux-platform)

## Results (measured on a 4-vCPU VM without KVM)

| Scenario | Time | Notes |
|---|---|---|
| Cold build, full image | **~7 h 45 min** | 5,257 BitBake tasks |
| Fresh runner, empty local caches | **24 min 34 s** | 2,684 of 2,690 objects from the S3 mirror (99 %) – **~19×** |
| MR build, empty untrusted volume, **signature-verified** | **20 min 4 s** | 2,232 objects GPG-verified, 0 rejected |
| Warm `main` build + publish (excl. gates) | **~1.5 min** | kept TMPDIR, ~2,237 tasks "Current" |
| Warm MR with a small change | **~1.2 min** | |
| Docs-only MR | **18 s** | Yocto build skipped |
| MR pipeline incl. 7 quality gates | **9 min 19 s** | gates run serially on the single VM runner; build itself unchanged |
| Planted secret in an MR | **blocked** | `secrets:gitleaks` fails, build skipped, merge disabled ("Pipelines must succeed") |
| Tamper demo | rejected | manipulated object in the mirror → `Cannot verify signature` → task rebuilt |

## What is in here

| Area | Implementation |
|---|---|
| Build | kas 5.5, Yocto 6.0 LTS (BitBake 2.18), lock-pinned layers, distro `secure-linux`, image `secure-linux-image` |
| Hardening | oe-core security flags, FORTIFY_SOURCE=3 / CET / auto-var-init for own code, read-only rootfs, locked accounts, sysctl, nftables, audit, rootfs audit |
| SBOM | SPDX 3.0.1 for every image, published as CI artifact |
| Build cache | Garage S3 sstate + download mirrors, central hash-equivalence server, central PR server, git mirror tarballs, warm TMPDIR → [docs/CACHING.md](docs/CACHING.md) |
| Quality gates | yamllint + GitLab CI schema, shellcheck, hadolint, oelint-adv, kernel-config policy, gitleaks (every MR commit, full `main` history), GitLab SAST (Semgrep) → [docs/QUALITY-GATES.md](docs/QUALITY-GATES.md) |
| Cache security | trusted/untrusted runner split, write-once publish from protected `main` only, environment-scoped credentials, authenticated hashserv reporting, **GPG-signed sstate** |
| Decisions | [docs/adr/](docs/adr/) · Lessons learned: [docs/INCIDENTS.md](docs/INCIDENTS.md) · History: [CHANGELOG.md](CHANGELOG.md) |

## Architecture

```
        MR / feature branch                       protected main
                 │                                       │
                 │ 7 gates: lint · secrets · SAST        │ same 7 gates
                 │                                       │
    ┌────────────▼────────────┐             ┌────────────▼─────────────┐
    │ runner yocto-untrusted  │             │ runner yocto (Protected) │
    │ own volume, anonymous   │             │ trusted cache volume     │
    └────────────┬────────────┘             └────────────┬─────────────┘
       read-only │ verify sigs               verify+sign │ report │ publish
    ┌────────────▼───────────────────────────────────────▼────────▼─────────┐
    │ Garage S3 (sstate, downloads) · hashserv (@read anon / @report CI)    │
    │ prserv (main writes, MRs read-through) · publish is write-once        │
    └───────────────────────────────────────────────────────────────────────┘
```

## Pipeline (current)

```
lint      lint:yaml (yamllint + CI schema) · lint:shell · lint:dockerfile · lint:recipes
          lint:kernel-hardening · secrets:gitleaks · semgrep-sast
build     build:qemux86-64 (needs all lint jobs) · build:fresh-runner (manual)
          maintenance:fetch-all (manual)
publish   publish:cache   (protected main only, environment cache-publish)
```

Merge requests cannot be merged unless the pipeline succeeds.

The full target pipeline (lint/SAST, CVE + license gates, signing, releases) lives in
`ci/target-pipeline.gitlab-ci.yml` and is enabled milestone by milestone.

## Quick start (local)

```bash
pipx install kas
export DL_DIR=/srv/yocto/cache/downloads SSTATE_DIR=/srv/yocto/cache/sstate-cache
kas-container build kas/machines/qemux86-64.yml:kas/features/local-vm.yml
kas-container shell kas/machines/qemux86-64.yml -c "runqemu nographic slirp"
```

Build host and CI infrastructure: `scripts/setup-build-host.sh` (host, runner),
`infra/cache/bootstrap-cache.sh` (Garage, hashserv, prserv), `infra/cache/seed-cache.sh` (initial seed).

## Roadmap

| Release | Scope | Status |
|---|---|---|
| v0.1 | Foundation: layer, distro, image, agent, kas lock | done |
| v0.2 | CI backbone on a self-hosted runner | done |
| v0.3 | Build acceleration + cache security | done |
| v0.4 | Shift-left quality: oelint-adv, shellcheck, hadolint, gitleaks, SAST | done |
| v0.5 | Supply chain: SBOM, CVE gate, VEX triage, license gate | next |
| v0.6 | Platform hardening: KSPP kernel, systemd sandboxing, oeqa runtime tests | |
| v0.7 | Trusted release: cosign keyless, SLSA provenance, RAUC signed A/B updates | |
| v1.0 | Compliance: CRA Annex I matrix, R155/R156 mapping, nightly release rescan | |

License: MIT
