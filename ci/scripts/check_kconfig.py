#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify a kernel config fragment against a required-hardening policy."""
import argparse
import re
import sys

import yaml


def parse(path):
    cfg = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            m = re.match(r"^(CONFIG_\w+)=(.*)$", line)
            if m:
                cfg[m.group(1)] = m.group(2)
                continue
            m = re.match(r"^# (CONFIG_\w+) is not set$", line)
            if m:
                cfg[m.group(1)] = "n"
    return cfg


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("fragment")
    ap.add_argument("--policy", required=True)
    args = ap.parse_args()

    cfg = parse(args.fragment)
    with open(args.policy, encoding="utf-8") as fh:
        policy = yaml.safe_load(fh)

    errors = []
    for opt, want in policy.get("required", {}).items():
        have = cfg.get(opt, "<missing>")
        if str(have) != str(want):
            errors.append(f"{opt}: expected {want}, found {have}")
    for line in errors:
        print("FAIL", line)
    print(f"kconfig hardening: {len(policy.get('required', {})) - len(errors)} ok, {len(errors)} failed")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
