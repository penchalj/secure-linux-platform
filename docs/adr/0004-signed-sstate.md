# ADR 0004: GPG-signed sstate, verified by every build

* Status: accepted (v0.3)

## Context
The trust boundary protects the write path, but the mirror itself (or its storage) could
still be manipulated. Builds should not trust an object just because it is in the mirror.

## Decision
* Dedicated ed25519 signing key; private key only as the protected, masked,
  environment-scoped variable `SSTATE_SIGNING_KEY_B64` (main build) and offline in
  `/srv/yocto/services/sstate-signing` with a revocation certificate.
* Protected `main` signs every new object (`SSTATE_SIG_KEY`).
* **Every** CI build verifies (`SSTATE_VERIFY_SIG = "1"`, `SSTATE_VALID_SIGS` = long key ID);
  invalid or missing signatures → object rejected, task rebuilt.
* The existing trusted cache (3,298 objects) was signed once and the signatures published;
  the untrusted cache was reset.

## Consequences
* Proven: 2,232 objects verified in an MR build with 0 rejections; a manipulated object
  was rejected by a fresh runner.
* Fail closed has a cost: rejecting one object on a fresh runner pulls in its build
  environment.
* Key rotation = new key in the variable + `SSTATE_VALID_SIGS` listing old and new key
  during the transition.
