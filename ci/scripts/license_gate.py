#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""License gate over a Yocto license.manifest.

Manifest blocks look like:
  PACKAGE NAME: busybox
  PACKAGE VERSION: 1.37.0
  RECIPE NAME: busybox
  LICENSE: GPL-2.0-only & bzip2-1.0.6
"""
import argparse
import fnmatch
import re
import sys
from xml.sax.saxutils import escape

import yaml


def parse_manifest(path):
    pkg = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                if pkg:
                    yield pkg
                pkg = {}
                continue
            key, _, value = line.partition(":")
            pkg[key.strip()] = value.strip()
    if pkg:
        yield pkg


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("manifest")
    ap.add_argument("--policy", required=True)
    ap.add_argument("--junit")
    args = ap.parse_args()

    with open(args.policy, encoding="utf-8") as fh:
        policy = yaml.safe_load(fh)
    denied = policy.get("deny", [])
    exceptions = set(policy.get("exceptions", {}).keys())

    failures, cases = [], []
    for pkg in parse_manifest(args.manifest):
        name = pkg.get("PACKAGE NAME", "?")
        licenses = [l for l in re.split(r"[&|() ]+", pkg.get("LICENSE", "")) if l]
        bad = [l for l in licenses if any(fnmatch.fnmatch(l, d) for d in denied)]
        body = ""
        if bad and name not in exceptions:
            failures.append((name, bad))
            body = f'<failure message="{escape("denied: " + ", ".join(bad))}"/>'
        cases.append(f'<testcase classname="license" name="{escape(name)}">{body}</testcase>')

    if args.junit:
        with open(args.junit, "w", encoding="utf-8") as fh:
            fh.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            fh.write(f'<testsuite name="license-gate" tests="{len(cases)}" failures="{len(failures)}">')
            fh.write("".join(cases) + "</testsuite>\n")

    print(f"License gate: {len(cases)} packages, {len(failures)} violations")
    for name, bad in failures:
        print(f"  DENIED {name}: {', '.join(bad)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
