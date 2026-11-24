# ADR 0001: Garage instead of MinIO as S3 cache backend

* Status: accepted (v0.3)

## Context
The sstate and download mirrors need an S3-compatible object store on the build host:
credentialed writes for the publish job, anonymous read-only HTTP for every build.
The original design used MinIO plus an nginx read-only proxy. The MinIO community
edition was archived in 2026, its Docker images were discontinued in 2025, and a
published CVE (CVE-2025-62506) remained unpatched in the community edition.

## Decision
Use **Garage** (v2.3.0, single node, `replication_factor = 1`):
* S3 API on `:3900` – write path, key `ci-publisher` with RW on two buckets only
* web endpoint on `:3902` – anonymous **read-only** HTTP per bucket
  (`sstate.web.garage`, `downloads.web.garage`), replacing the nginx proxy
* admin API on `:3903`, bound to localhost

## Consequences
* One maintained, small component instead of MinIO + nginx.
* Read-only access is enforced by the server (PUT on `:3902` → HTTP 400), not by proxy config.
* No lifecycle rules yet; sstate pruning is a planned maintenance job.
