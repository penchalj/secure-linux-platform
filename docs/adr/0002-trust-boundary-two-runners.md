# ADR 0002: Trust boundary – separate runners for untrusted and protected builds

* Status: accepted (v0.3)

## Context
Merge-request code runs arbitrary build steps. With one runner and one cache volume,
an MR build could write objects into the same sstate directory that `main` later
publishes to the shared mirror (cache poisoning).

## Decision
* Runner `vm-yocto-untrusted` (tag `yocto-untrusted`) for MRs and feature branches,
  with its **own volume**; it has no access to the trusted cache.
* Runner `vm-yocto-builder` (tag `yocto`) is marked **Protected** in GitLab and runs only
  protected refs.
* `workflow:rules` set `RUNNER_TAG` by trust level; feature branches build only via MR.
* Untrusted builds read the mirror over HTTP, query hashserv anonymously (`@read`), and
  use a local PR server with central upstream.
* All write credentials are environment-scoped CI variables on protected refs.

## Consequences
* An MR can never write shared state; the worst case is its own disposable volume.
* MR builds start from the mirror (first run ~20–23 min, warm ~1.2 min).
* Known limitation: prserv has no authentication; a separate network for the untrusted
  runner is planned.
