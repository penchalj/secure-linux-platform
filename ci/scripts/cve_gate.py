#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""CRA vulnerability gate for Yocto cve-check JSON reports.

Policy:
  * Status "Unpatched" with CVSS >= --max-cvss  -> FAIL (in enforce mode)
  * Status "Ignored"/"Patched"                  -> PASS (triaged / fixed; VEX)
  * Everything is written to JUnit (one testcase per CVE) so the GitLab MR
    widget lists new findings, plus a Markdown summary for the MR note.
"""
import argparse
import glob
import json
import sys
from xml.sax.saxutils import escape


def score(issue: dict) -> float:
    vals = []
    for key in ("scorev4", "scorev3", "scorev2"):
        try:
            vals.append(float(issue.get(key) or 0))
        except ValueError:
            pass
    return max(vals) if vals else 0.0


def load(paths):
    for pattern in paths:
        for path in glob.glob(pattern):
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            for pkg in data.get("package", []):
                for issue in pkg.get("issue", []):
                    yield {
                        "package": pkg.get("name", "?"),
                        "version": pkg.get("version", "?"),
                        "id": issue.get("id", "?"),
                        "status": issue.get("status", "?"),
                        "detail": issue.get("detail", ""),
                        "description": issue.get("description", ""),
                        "cvss": score(issue),
                        "link": issue.get("link", ""),
                    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cve-json", nargs="+", required=True)
    ap.add_argument("--max-cvss", type=float, default=7.0)
    ap.add_argument("--mode", choices=("enforce", "report"), default="enforce")
    ap.add_argument("--junit")
    ap.add_argument("--markdown")
    args = ap.parse_args()

    issues = list(load(args.cve_json))
    unpatched = [i for i in issues if i["status"] == "Unpatched"]
    blocking = sorted((i for i in unpatched if i["cvss"] >= args.max_cvss),
                      key=lambda i: -i["cvss"])
    triaged = [i for i in issues if i["status"] == "Ignored"]

    if args.junit:
        cases = []
        for i in unpatched:
            name = escape(f"{i['package']} {i['id']}")
            body = ""
            if i in blocking:
                msg = escape(f"CVSS {i['cvss']} >= {args.max_cvss}: {i['description'][:300]}")
                body = f'<failure message="{msg}">{escape(i["link"])}</failure>'
            cases.append(f'<testcase classname="cve.{escape(i["package"])}" name="{name}">{body}</testcase>')
        with open(args.junit, "w", encoding="utf-8") as fh:
            fh.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            fh.write(f'<testsuite name="cve-gate" tests="{len(cases)}" failures="{len(blocking)}">')
            fh.write("".join(cases))
            fh.write("</testsuite>\n")

    if args.markdown:
        with open(args.markdown, "w", encoding="utf-8") as fh:
            fh.write("### CVE gate\n\n")
            fh.write(f"| Total | Unpatched | Blocking (CVSS >= {args.max_cvss}) | Triaged (VEX) |\n")
            fh.write("|---|---|---|---|\n")
            fh.write(f"| {len(issues)} | {len(unpatched)} | **{len(blocking)}** | {len(triaged)} |\n\n")
            if blocking:
                fh.write("| CVE | Package | CVSS |\n|---|---|---|\n")
                for i in blocking[:25]:
                    fh.write(f"| [{i['id']}]({i['link']}) | {i['package']} {i['version']} | {i['cvss']} |\n")
                fh.write("\nTriage via MR to `meta-secure-linux/conf/secure-linux-cve-triage.inc` "
                         "or upgrade/patch the recipe.\n")

    print(f"CVE gate: {len(issues)} issues, {len(unpatched)} unpatched, "
          f"{len(blocking)} blocking, {len(triaged)} triaged")
    for i in blocking:
        print(f"  BLOCKING {i['id']:<18} {i['package']:<24} CVSS {i['cvss']}")

    if blocking and args.mode == "enforce":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
