# Build cache and cache security

Yocto rebuilds are only fast if build results can be reused safely. This platform
combines five cache levels with a trust model that keeps untrusted code (merge
requests) from ever writing to shared state.

## Cache levels

| Level | What | Where | Who writes |
|---|---|---|---|
| L1 | TMPDIR (parse cache, stamps → tasks stay "Current") | runner volume, per runner | the runner itself |
| L2 | local sstate + downloads | runner volume, per runner | the runner itself |
| L3 | **sstate mirror** (`SSTATE_MIRRORS`) and **download mirror** (`PREMIRRORS`, incl. git mirror tarballs) | Garage S3, read-only HTTP endpoint `:3902` | `publish:cache` on protected `main` only (S3 API `:3900`) |
| L4 | **hash equivalence** (unihash mapping) | `bitbake-hashserv` `:8686` | authenticated user `ci-reporter` (main) |
| L5 | **package revisions** (PR service) | `bitbake-prserv` `:8585` | main; MRs use a local server with central upstream |

sstate objects are named by **unihash**: the mirror (L3) and the hash-equivalence
server (L4) only work together. A mirror without hashserv data reached 53 %; with
it, 99 % (see INCIDENTS #10).

## Trust model

| Identity | Can | Used by |
|---|---|---|
| runner `vm-yocto-untrusted` | own volume only; mirror read-only; hashserv anonymous `@read`; PR read-through | MR and feature-branch builds |
| runner `vm-yocto-builder` (Protected) | trusted cache volume | protected `main` and tags |
| `ci-reporter` (hashserv) | `@read @report` | main build; token via environment `cache-report`, given to kas with `NETRC_FILE` |
| `ci-publisher` (Garage key) | write `sstate` + `downloads` | `publish:cache` only; environment `cache-publish` |
| sstate signing key | sign sstate objects | main build; `SSTATE_SIGNING_KEY_B64` in environment `cache-report` |
| `slp-admin` (hashserv) | `@all` | operator on the build host only |

All CI secrets are **Protected + Masked & hidden + environment-scoped**: each one is
visible to exactly one job type on protected refs.

## Signed sstate

* Every CI build sets `SSTATE_VERIFY_SIG = "1"` and accepts only the platform key
  (`SSTATE_VALID_SIGS` = long key ID `E17F42F0B73B02DB`). An object without a valid
  signature is rejected and its task is rebuilt (fail closed).
* Only protected `main` signs (`SSTATE_SIG_KEY`); the public key is in
  `keys/sstate-signing.pub.asc`.
* `SSTATE_SIG_KEY` and `SSTATE_VALID_SIGS` are excluded from task signatures, so signing
  does not split main and MR hashes.
* Tamper demo: one object in the mirror was overwritten with modified content.
  A fresh runner logged `Cannot verify signature … will run full task instead`
  for exactly that object and installed none of its content.
* Cost of fail-closed: on a fresh runner, rebuilding one rejected package pulls in its
  whole build environment (compiler, sysroots) – a partial rebuild instead of a 1-s fetch.

## Write path

`publish:cache` (protected `main`, `resource_group: cache-publish`) copies new objects
from the trusted cache to Garage with `rclone copy --ignore-existing --min-size 1B`:

* **write-once** – content-addressed objects are never overwritten
* **no 0-byte objects** – crash leftovers once poisoned the mirror (INCIDENTS #11)
* every run is a deployment in *Operate → Environments → cache-publish* (audit trail)

## Efficiency

* TMPDIR is kept between jobs; `CLEAN_TMP=1` restores the "everything from sstate" mode
  (fresh-runner benchmark, after crashes). Old deploy images are pruned after 2 days.
* Feature branches build only through their MR (no duplicate branch pipelines).
* MRs without build-relevant changes skip the Yocto build.
* `BB_GENERATE_MIRROR_TARBALLS = "1"` plus the manual `maintenance:fetch-all` job keep
  git sources in the download mirror.

## Benchmarks

| Scenario | Time | sstate |
|---|---|---|
| Cold build | ~7 h 45 min | – |
| Fresh runner (mirror only) | 24 min 34 s | Mirrors 2,684 · Missed 6 |
| MR, empty untrusted volume, verified | 20 min 4 s | Mirrors 2,685 · 2,232 verified · 0 rejected |
| Warm main (lint+build+publish) | 1 min 19 s – 1 min 33 s | Current ~2,237 |
| Warm MR, small change | 1 min 14 s | Current 2,236 |
| Docs-only MR | 18 s | build skipped |
| One-time PR-server migration | 3 h 9 min | 67 % (see ADR 0003) |

## Operations

* Services: `infra/cache/docker-compose.yml` (Garage v2.3.0, hashserv, prserv), started by
  `infra/cache/bootstrap-cache.sh`; secrets under `/srv/yocto/services` (0600), never in git.
* Restore a manipulated or broken object: delete it locally and in Garage, let `main` rebuild,
  publish (see INCIDENTS #11).
* Host networking: host adapter power saving off plus a 1-minute reachability check
  (`journalctl -t slp-dnscheck`), see INCIDENTS #17.
