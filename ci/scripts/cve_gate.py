#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""CVE gate over a cve-check style JSON (sbom-cve-check export
"yocto-cve-check-manifest").

Policy:
  * status "Unpatched" with CVSS >= --max-cvss -> blocking (fails in enforce mode)
  * status "Patched" / "Ignored"               -> pass (fixed, or triaged = VEX)
Outputs: JUnit (one testcase per unpatched CVE, failures = blocking), a Markdown
summary for the MR, and GitLab metrics so MRs show the trend.
"""
import argparse
import glob
import json
import sys
from collections import Counter
from xml.sax.saxutils import escape


def score(issue: dict) -> float:
    vals = []
    for key in ("scorev4", "scorev3", "scorev2"):
        try:
            vals.append(float(issue.get(key) or 0))
        except (TypeError, ValueError):
            pass
    return max(vals) if vals else 0.0


def load(patterns):
    for pattern in patterns:
        for path in sorted(glob.glob(pattern)):
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
    ap.add_argument("--metrics")
    args = ap.parse_args()

    issues = list(load(args.cve_json))
    if not issues:
        print("CVE gate: no issues parsed - wrong input?", file=sys.stderr)
        return 2
    status = Counter(i["status"] for i in issues)
    unpatched = [i for i in issues if i["status"] == "Unpatched"]
    blocking = sorted((i for i in unpatched if i["cvss"] >= args.max_cvss),
                      key=lambda i: (-i["cvss"], i["package"], i["id"]))
    by_pkg = Counter(i["package"] for i in blocking)

    if args.junit:
        cases = []
        for i in unpatched:
            name = escape(f"{i['package']} {i['id']}")
            body = ""
            if i["cvss"] >= args.max_cvss:
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
            fh.write(f"### CVE gate ({args.mode})\n\n")
            fh.write(f"| Total | Patched | Ignored (VEX) | Unpatched | Blocking (CVSS >= {args.max_cvss}) |\n")
            fh.write("|---|---|---|---|---|\n")
            fh.write(f"| {len(issues)} | {status['Patched']} | {status['Ignored']} | "
                     f"{len(unpatched)} | **{len(blocking)}** |\n\n")
            if by_pkg:
                fh.write("| Package | Blocking |\n|---|---|\n")
                for pkg, n in by_pkg.most_common():
                    fh.write(f"| {pkg} | {n} |\n")
                fh.write("\nTriage: `CVE_STATUS` with justification in the layer, "
                         "or upgrade/patch the recipe.\n")

    if args.metrics:
        with open(args.metrics, "a", encoding="utf-8") as fh:
            fh.write(f"cve_total {len(issues)}\n")
            fh.write(f"cve_unpatched {len(unpatched)}\n")
            fh.write(f"cve_blocking {len(blocking)}\n")
            fh.write(f"cve_ignored {status['Ignored']}\n")

    print(f"CVE gate ({args.mode}): {len(issues)} issues | patched={status['Patched']} "
          f"ignored={status['Ignored']} unpatched={len(unpatched)} "
          f"blocking(CVSS>={args.max_cvss})={len(blocking)}")
    for pkg, n in by_pkg.most_common():
        print(f"  {n:4d}  {pkg}")

    return 1 if (blocking and args.mode == "enforce") else 0


if __name__ == "__main__":
    sys.exit(main())
