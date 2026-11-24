# Engineering incidents and lessons learned

Every non-trivial failure during the build-out, with cause, fix and lesson.

| # | Incident | Cause | Fix / lesson |
|---|---|---|---|
| 1 | Sanity check failed (`bb.utils.is_path_on_nfs`) | BitBake 2.16 (Whinlatter) with oe-core Wrynose | BitBake 2.18; pin with kas lock |
| 2 | Checksum mismatch on zlib | upstream served a bot-challenge page | verified Yocto source mirror (`own-mirrors`), never override checksums |
| 3 | libstdc++ build failure | distro-wide `SECURITY_CFLAGS:append` overrode per-recipe exceptions | strict flags only for own recipes |
| 4 | `tmp/sstate-control` corrupted after VM reset | hard reset during build | delete `build/tmp`; 71 % restored from sstate |
| 5 | Fetch failures under load | host overload dropped VM networking | 3 parallel tasks; lab containers off |
| 6 | kas image vs. GitLab Docker executor | entrypoint built for `docker run` | `entrypoint: [""]`, start as root, drop to `builder` |
| 7 | "yaml invalid" | colon-space in `chown -R builder: /builder` | quote; CI-lint check planned |
| 8 | Permission denied on cache | dirs created root-owned by sudo setup | fixed in `setup-build-host.sh` |
| 9 | First CI job stalled | VM overloaded (browser in the VM) | build VM kept free during builds; see #17 |
| 10 | Fresh runner only 53 % from mirror | empty central hashserv; objects are named by unihash | seed hashserv with the build host's DB → 99 % |
| 11 | 0-byte `.siginfo` broke mirror fetches | crash leftovers copied by the seed | delete + rebuild + re-seed; `--min-size 1B` in publish |
| 12 | prserv restart loop | stale PID file after VM reset | entrypoint removes it |
| 13 | VM paused mid-job | host disk full (VDI growth) | freed space; compaction planned |
| 14 | Enabling the PR server → 3 h rebuild | `PRSERV_ACTIVE` is part of the task signature (r0 → r0.0) | one-time migration; MRs use PR read-through so hashes match main (ADR 0003) |
| 15 | MR after #14 took 3 h 47 min | hashserv reports silently rejected for 3 days: kas isolates `HOME`, `.netrc` never reached BitBake | `NETRC_FILE`; verify write paths on the server side (DB inspection) |
| 16 | Every valid sstate signature rejected | `SSTATE_VALID_SIGS` compares long key IDs, not fingerprints | list the long key ID; caught in the MR before reaching main |
| 17 | Overnight job marked "no activity" | VM lost internet (NetworkManager `CONNECTED_SITE`, DNS timeouts) for ~8 h; runner could not ship the trace | host adapter power saving off, 1-min DNS check (external resolvers are blocked on this network); likely cause of earlier stalls |

Diagnosis toolbox that found most of these: `bb.siggen.compare_sigfiles` on `.siginfo`
files, `sqlite3` on the hashserv DB, per-task setscene logs, `journalctl -b -1`.
