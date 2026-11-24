# ADR 0003: The PR service belongs to the build baseline

* Status: accepted (v0.3)

## Context
Package feeds and OTA updates need monotonic package revisions, provided by a central
PR server. Enabling it later turned `PRSERV_ACTIVE` from False to True; that variable is
part of every packaging task's signature, so all package revisions moved from `r0` to
`r0.0` and main needed a one-time 3 h 9 min rebuild (67 % sstate match).

## Decision
* Protected `main` uses the central `prserv:8585` (writes revisions).
* MR builds use `PRSERV_HOST = "localhost:0"` with `PRSERV_UPSTREAM = "prserv:8585"`:
  same revisions and same task signatures as main, nothing written centrally.
* New platforms enable the PR service **before** the first cache seed.

## Consequences
* MR and main share sstate objects again (verified with `bb.siggen.compare_sigfiles`).
* Signature-relevant settings are checked before rollout (`grep` in the OE classes,
  MR build as safety net).
