#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Convert oelint-adv output (path:line:severity:id:msg) to GitLab Code Quality JSON."""
import hashlib
import json
import sys

SEVERITY = {"error": "major", "warning": "minor", "info": "info"}


def main() -> int:
    issues = []
    with open(sys.argv[1], encoding="utf-8") as fh:
        for raw in fh:
            parts = raw.rstrip("\n").split(":", 4)
            if len(parts) != 5:
                continue
            path, line, sev, rule, msg = parts
            issues.append({
                "description": f"{rule}: {msg}",
                "check_name": rule,
                "fingerprint": hashlib.sha1(raw.encode()).hexdigest(),
                "severity": SEVERITY.get(sev, "info"),
                "location": {"path": path, "lines": {"begin": int(line) if line.isdigit() else 1}},
            })
    json.dump(issues, sys.stdout, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
