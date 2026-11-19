# Architecture

```mermaid
flowchart LR
  subgraph Dev
    D[Developer] -->|pre-commit: gitleaks, oelint| G[(GitLab repo)]
    R[Renovate] -->|kas lock / image bumps| G
  end

  G --> P{{GitLab pipeline}}

  subgraph P1[lint ~2 min]
    L1[oelint-adv] --- L2[yamllint + kas dump] --- L3[shellcheck / hadolint] --- L4[gitleaks + SAST] --- L5[kconfig policy]
  end

  subgraph P2[build matrix]
    B1[qemux86-64] --- B2[qemuarm64] --- B3[test image]
  end

  subgraph Cache[shared cache services]
    S3[(MinIO S3<br/>sstate + downloads)]
    NG[nginx RO mirror]
    HS[bitbake-hashserv]
    PR[bitbake-prserv]
    RC[(GitLab runner cache<br/>kas repos, CVE DB)]
  end

  subgraph P3[test + security]
    T[QEMU testimage → JUnit]
    C[CVE gate → JUnit]
    LG[License gate]
    DT[Dependency-Track]
  end

  subgraph P4[release - tags only]
    RB[signed RAUC bundle]
    SG[cosign keyless + Rekor]
    SL[SLSA provenance]
    GR[GitLab Release + Package Registry]
  end

  P --> P1 --> P2 --> P3 --> P4
  P2 <-->|read| NG
  NG --- S3
  P2 -->|protected only, GPG-signed| S3
  P2 <--> HS
  P2 <--> PR
  P2 <--> RC
```

## Repository layout

```
kas/
  base.yml                 Wrynose layers, distro, QA-as-error
  base.lock.yml            (generated) exact commits - `kas lock kas/base.yml`
  machines/                qemux86-64, qemuarm64 (add real BSPs here)
  features/
    ci-cache.yml           L1-L4 cache wiring, signature verification
    sstate-sign.yml        producer-side sstate signing (protected refs)
    security.yml           SPDX, VEX, cve-check, sbom-cve-check, licenses
    test.yml               test-only image tweaks (never released)
    release.yml            meta-rauc, signed bundle, prod hardening
meta-secure-linux/             custom layer: distro, image, agent, kernel, oeqa tests
ci/templates/              pipeline split by concern (included from .gitlab-ci.yml)
ci/scripts/                gates and converters (Python stdlib + PyYAML only)
ci/policies/               kconfig + license policy (CODEOWNERS-protected)
docker/                    build container
infra/                     cache services (compose), runner config, MinIO policies
docs/                      this documentation
```

## Extending to real hardware

Add `kas/machines/<board>.yml` that includes the BSP layer (e.g. `meta-raspberrypi`
or `meta-freescale` for i.MX8). Then add the machine to the `parallel:matrix` in
`ci/templates/build.yml` and `security.yml`. For on-target tests, use LAVA or
labgrid with a runner tagged `hil`.
