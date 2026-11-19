#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Convert oeqa testresults.json (testimage) into JUnit XML for GitLab."""
import argparse
import json
import sys
from xml.sax.saxutils import escape


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("results")
    ap.add_argument("--out", default="junit-oeqa.xml")
    args = ap.parse_args()

    with open(args.results, encoding="utf-8") as fh:
        data = json.load(fh)

    cases, failures, skipped = [], 0, 0
    for run_name, run in data.items():
        for test, res in sorted(run.get("result", {}).items()):
            if test.startswith("ptestresult."):
                continue
            status = res.get("status", "UNKNOWN")
            cls, _, name = test.rpartition(".")
            body = ""
            if status in ("FAILED", "ERROR"):
                failures += 1
                body = f'<failure message="{escape(status)}">{escape(res.get("log", ""))}</failure>'
            elif status == "SKIPPED":
                skipped += 1
                body = "<skipped/>"
            dur = res.get("duration", 0)
            cases.append(f'<testcase classname="{escape(cls)}" name="{escape(name)}" '
                         f'time="{dur}">{body}</testcase>')

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        fh.write(f'<testsuite name="oeqa-runtime" tests="{len(cases)}" '
                 f'failures="{failures}" skipped="{skipped}">')
        fh.write("".join(cases) + "</testsuite>\n")
    print(f"{len(cases)} tests, {failures} failed, {skipped} skipped -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
