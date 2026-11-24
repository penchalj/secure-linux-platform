# Quality gates (v0.4)

Every merge request and every push to `main` runs seven gates in the `lint` stage.
`build:qemux86-64` declares `needs` on all of them, so a failing gate stops the pipeline
before any build time is spent. The project setting **Pipelines must succeed** turns a red
pipeline into a disabled merge button.

| Job | Tool (pinned) | Checks | Fails on |
|---|---|---|---|
| `lint:yaml` | yamllint 1.x, check-jsonschema 0.39.0 | YAML style; `.gitlab-ci.yml` against the GitLab CI schema | any error |
| `lint:shell` | shellcheck 0.11.0 | `ci/scripts`, `infra/cache`, `scripts` | warning and above |
| `lint:dockerfile` | hadolint 2.15.1 | `docker/Dockerfile` (Code Quality report in the MR) | warning and above |
| `lint:recipes` | oelint-adv 8.2.2 | own recipes and bbappends (Code Quality report in the MR) | any `error` finding |
| `lint:kernel-hardening` | `check_kconfig.py` | kernel config fragments against the hardening policy | policy violation |
| `secrets:gitleaks` | gitleaks 8.30.1 | MR: exactly the MR's commits (diff base..head); `main`: full history of `main`; SARIF artifact | any finding |
| `semgrep-sast` | GitLab SAST template (Semgrep) | Python sources | job failure (findings reviewed per release) |

Most of these tools also run locally as pre-commit hooks (`.pre-commit-config.yaml`), so most findings
never reach CI.

## Exceptions

Exceptions are narrow, written down next to the code and justified:

* `.gitleaks.toml`: only the exact `SSTATE_SIG_KEY` / `SSTATE_VALID_SIGS` assignment lines
  (public key ID, not a secret). A counter-test confirmed a real private key is still detected.
* `.hadolint.yaml`: DL3008 (apt version pinning). Reproducibility comes from the pinned base image.
* `secure-linux-bundle_1.0.bb`: inline `nooelint` for the missing `SRC_URI`. The bundle class
  packs the built image, so the recipe has no sources.

## Evidence

* **Secret blocked:** a demo MR with a planted, randomly generated token. `secrets:gitleaks`
  reported `leaks found: 1` (redacted), `build:qemux86-64` did not run, and the MR showed
  "Merge blocked: Pipeline must succeed". The MR was closed and the branch deleted. Because
  gitleaks scans every commit of the MR, removing the file in a later commit would not have unblocked it:
  a leaked secret must be rotated, not only deleted.
* **SAST finding fixed:** Semgrep reported "risky cryptographic algorithm" (SHA-1 for Code Quality
  fingerprints). Not security-relevant, but fixed (SHA-256) instead of suppressed.

## Known limitation

The gates currently run one after another on the single VM runner (~8 min per pipeline).
Allowing light lint jobs to run in parallel is a runner configuration change, planned with v0.5.
