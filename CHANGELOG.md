# Changelog

## v0.3 – Build acceleration and cache security

* Garage S3 sstate + download mirrors (read-only web endpoint), replacing MinIO (ADR 0001)
* Central hash-equivalence server with access control: anonymous `@read`, authenticated
  reporting from main (`ci-reporter`)
* Central PR service on main, read-through for MRs (ADR 0003)
* Trust boundary: untrusted runner for MRs, protected runner for main (ADR 0002)
* `publish:cache`: write-once, 0-byte guard, environment-scoped credentials, audit trail
* GPG-signed sstate: main signs, every build verifies; tamper demo (ADR 0004)
* Git mirror tarballs + manual `maintenance:fetch-all`
* CI efficiency: warm TMPDIR, no duplicate branch pipelines, docs-only MRs skip the build
* Results: fresh runner 24.5 min (vs ~7 h 45 min cold), warm main ~1.5 min, docs MR 18 s
* Incidents #10–#17 documented in `docs/INCIDENTS.md`

## v0.2 – CI backbone

* GitLab pipeline on a self-hosted Docker runner (`lint:yaml` → `build:qemux86-64`)
* kas container driven as unprivileged `builder`; SBOM, manifest and cache stats as artifacts
* First green pipeline: 17 min 26 s, 99.81 % sstate hit rate

## v0.1 – Foundation

* Layer `meta-secure-linux`, distro `secure-linux`, image `secure-linux-image`,
  demo service `secure-linux-agent`
* Yocto 6.0 LTS (BitBake 2.18), kas lock-pinned layers
* First full build: 5,257 tasks; warm rebuild 13 min 58 s
