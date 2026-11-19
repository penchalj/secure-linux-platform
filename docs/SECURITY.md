# DevSecOps controls

| # | Control | Where | Tooling | Fails pipeline? |
|---|---|---|---|---|
| 1 | Secret scanning | `lint:gitleaks`, GitLab Secret Detection, pre-commit | gitleaks | yes |
| 2 | Recipe static analysis | `lint:recipes` → Code Quality widget | oelint-adv | on errors |
| 3 | Shell / Dockerfile lint | `lint:shell`, `lint:dockerfile` | shellcheck, hadolint | yes |
| 4 | SAST on own sources | GitLab SAST template | Semgrep (C, Python) | report |
| 5 | Kernel hardening policy | `lint:kernel-hardening` | `check_kconfig.py` + KSPP subset | yes |
| 6 | Compiler hardening | `secure-linux.conf` | `security_flags.inc`, FORTIFY=3, RELRO/NOW, CET | build-time |
| 7 | Build QA as errors | `kas/base.yml` `WARN_TO_ERROR_QA` | insane.bbclass | yes |
| 8 | Rootfs audit | `secure_linux_rootfs_audit` | world-writable, empty passwords, setuid inventory | yes |
| 9 | Runtime hardening tests | `test:qemu` | oeqa + `systemd-analyze security` | yes |
| 10 | SBOM | every build | `create-spdx` (SPDX 3.0, incl. VEX) | – |
| 11 | CVE gate | `security:cve-gate` | `cve-check` + `sbom-cve-check` → `cve_gate.py` | CVSS ≥ 7 untriaged |
| 12 | VEX / triage trail | `secure-linux-cve-triage.inc` + CODEOWNERS | `CVE_STATUS` | review-enforced |
| 13 | License compliance | `INCOMPATIBLE_LICENSE` + `security:license-gate` + archiver | Yocto + `license_gate.py` | yes |
| 14 | Container scanning | `container:scan` | Trivy | CRITICAL |
| 15 | Build container signing | `container:sign` | cosign keyless (GitLab OIDC) | – |
| 16 | sstate integrity | `sstate-sign.yml` / `SSTATE_VERIFY_SIG` | GPG | yes (verify) |
| 17 | Artefact signing | `release:sign` | cosign keyless + Rekor | – |
| 18 | Update signing | `release.yml` | RAUC verity bundles, X.509 | – |
| 19 | Provenance | all jobs | GitLab SLSA provenance (`RUNNER_GENERATE_ARTIFACTS_METADATA`) | – |
| 20 | Reproducible builds | `secure-linux.conf` | `reproducible_build` | – |
| 21 | Dependency updates | Renovate (weekly, grouped kas lock bump) | Renovate | – |
| 22 | Post-release monitoring | `maintenance:release-rescan`, Dependency-Track | sbom-cve-check, DT | report |

## Verifying a release

```bash
cosign verify-blob \
  --certificate secure-linux-image-qemux86-64.rootfs.spdx.json.pem \
  --signature   secure-linux-image-qemux86-64.rootfs.spdx.json.sig \
  --certificate-identity-regexp "^https://gitlab.example.com/secure-linux/secure-linux-platform//.gitlab-ci.yml@refs/tags/v" \
  --certificate-oidc-issuer https://gitlab.example.com \
  secure-linux-image-qemux86-64.rootfs.spdx.json
```

## Secrets inventory (GitLab CI/CD variables)

| Variable | Type | Protected | Masked | Used by |
|---|---|---|---|---|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | var | ✅ | ✅ | sstate publish |
| `SLP_SSTATE_GPG_KEY_FILE` | file | ✅ | – | sstate signing |
| `SLP_SSTATE_GPG_PASSPHRASE` | var | ✅ | ✅ | sstate signing |
| `SLP_SSTATE_GPG_PUBKEY_FILE` | file | – | – | sstate verify (all) |
| `SLP_SSTATE_GPG_KEYID` | var | – | – | sstate verify (all) |
| `SLP_RAUC_KEY` / `_CERT` / `_KEYRING` | file | ✅ | – | release bundle |
| `DTRACK_URL` / `DTRACK_API_KEY` | var | ✅ | ✅ | SBOM upload |
| `SLP_BOT_TOKEN` | var | – | ✅ | MR comments (project access token, `api` scope, Reporter role) |

For production, move the RAUC key to an HSM or PKCS#11 (`RAUC_KEY_FILE = "pkcs11:..."`)
or to a Vault-backed signing service using GitLab `id_tokens` + `secrets:vault`.
