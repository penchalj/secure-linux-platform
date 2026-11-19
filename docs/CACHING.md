# Caching design

The goal: a clean MR pipeline for a full image should take **minutes, not hours**.
A cold Wrynose `core-image` build runs for 1–3 h on 16 cores. With a warm cache,
the same build replays from sstate in roughly 5–15 min.

## The layers

| Level | What | Where it lives | Key / invalidation | Writers |
|---|---|---|---|---|
| L0 | Build container layers | GitLab registry (`builder:buildcache`, BuildKit `mode=max`) | Dockerfile instruction hash | `build-container` (on `docker/**` changes) |
| L1 | Source downloads (`DL_DIR`) | Runner volume `/cache/yocto/downloads` → S3 `secure-linux-downloads` (via `own-mirrors`) | URL + checksum | Protected refs only |
| L2 | Shared state (`SSTATE_DIR`) | Runner volume `/cache/yocto/sstate-cache` → S3 `secure-linux-sstate` via nginx (`SSTATE_MIRRORS`) | Task signature hash | Protected refs only, **GPG-signed** |
| L3 | Hash equivalence | `bitbake-hashserv` (`BB_HASHSERVE_UPSTREAM`) | Output hash → many input hashes | Protected refs |
| L4 | Package revisions | `bitbake-prserv` (`PRSERV_HOST`) | Recipe + checksum | Protected refs |
| G1 | kas layer checkouts | GitLab `cache:` keyed on `kas/base.lock.yml` | Lock file content | Protected refs (`pull-push`) |
| G2 | NVD CVE database | GitLab `cache:` `cve-db-main` | Nightly refresh | `maintenance:cve-db-refresh` only |
| G3 | pip / Trivy DB | GitLab `cache:` | Requirements file / fixed key | Lint jobs |

## Why sstate is not in GitLab's `cache:` keyword

This is the main design decision. It comes up in interviews.

1. **Size.** sstate grows to 50–300 GB. GitLab cache zips and unzips the whole path on every job, which takes longer than the build it saves.
2. **Granularity.** sstate is content-addressed per *task*. A GitLab cache key is one string per job, so a single changed recipe would invalidate everything or nothing.
3. **Sharing.** An S3/HTTP mirror lets every runner, developer laptop and nightly build share objects. A GitLab cache is scoped per project and per key.

GitLab `cache:` is used where it works well: small, hot data with a clear key (kas repos, the CVE DB, pip).

## Hash equivalence (L3)

When a change doesn't alter a task's *output* (a comment in a recipe, a reordered
variable), the input hash changes but the output hash stays the same. The hash
server maps the new input hash to the existing sstate object, so downstream
tasks are **reused instead of rebuilt**. Since Wrynose, `BB_SIGNATURE_HANDLER`
defaults to `OEEquivHash` and `BB_HASHSERVE = "auto"`. We add
`BB_HASHSERVE_UPSTREAM` so every runner learns from every other runner.

## Cache-poisoning protection (security!)

A shared build cache is a supply-chain attack surface: if a malicious MR could
write a tampered `glibc` sstate object, every later build would ship it.

* MR pipelines get `CACHE_POLICY=pull` (read-only GitLab caches) and no S3 write
  credentials. `cache-env.sh` actively unsets them.
* GitLab separates protected and unprotected cache keys; `unprotect: false` stays explicit.
* The sstate mirror is served **read-only** through nginx (`limit_except GET HEAD`).
* Protected builds sign every sstate object (`SSTATE_SIG_KEY`). All consumers set
  `SSTATE_VERIFY_SIG = "1"` and reject unsigned or foreign-signed objects.
* `resource_group: sstate-publish-$MACHINE` stops two writers from racing on publish.
* Recommended: a separate `yocto-mr` runner that mounts `/cache/yocto` read-only.

## Observability

`ci/scripts/cache_stats.py` parses bitbake's `Sstate summary` line and emits:

* a **GitLab metrics report**. The MR widget shows `sstate_hit_rate_pct` against
  the target branch, so a change that breaks caching shows up in review.
* `cache-stats-<machine>.json` for Grafana / Prometheus.

Typical healthy values: hit rate > 95 % on MRs and missed tasks < 50.

## Maintenance

* `maintenance:sstate-prune` (nightly) deletes local objects with atime > 30 days.
* S3 lifecycle rule expires mirror objects after 60 days (`infra/minio/`).
* `maintenance:cve-db-refresh` updates the NVD DB once per night. Builds run with
  `CVE_DB_UPDATE_INTERVAL = "-1"`, which avoids NVD rate limits and gives
  reproducible CVE results within a day.

## Local developer use

Developers can point at the same mirrors read-only:

```bash
export SSTATE_MIRROR_URL=https://sstate.example.internal
export HASHSERV_URL=hashserv.example.internal:8686
kas build kas/machines/qemux86-64.yml:kas/features/ci-cache.yml
```
