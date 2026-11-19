#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Extract sstate cache efficiency from a bitbake log.

bitbake prints e.g.:
  Sstate summary: Wanted 2814 Local 2310 Mirrors 402 Missed 102 Current 0 (96% match, 0% complete)

Outputs:
  * GitLab metrics report (metrics.txt) -> shown in the MR widget as a diff
    against the target branch, so cache regressions are visible in review
  * JSON for dashboards (Grafana/Prometheus pushgateway etc.)
"""
import argparse
import json
import re
import sys

SUMMARY = re.compile(
    r"Sstate summary: Wanted (?P<wanted>\d+) Local (?P<local>\d+) "
    r"Mirrors (?P<mirrors>\d+) Missed (?P<missed>\d+) Current (?P<current>\d+)")
TASKS = re.compile(r"Tasks Summary: Attempted (?P<attempted>\d+) tasks of which "
                   r"(?P<didnt_need>\d+) didn't need to be rerun")


def parse(text: str) -> dict:
    stats = {}
    m = None
    for m in SUMMARY.finditer(text):
        pass  # keep the last summary (the real build, not a parse-only pass)
    if m:
        stats.update({k: int(v) for k, v in m.groupdict().items()})
        wanted = stats["wanted"] or 1
        stats["hit_rate_pct"] = round(100.0 * (stats["local"] + stats["mirrors"]) / wanted, 2)
        stats["mirror_share_pct"] = round(100.0 * stats["mirrors"] / wanted, 2)
    t = None
    for t in TASKS.finditer(text):
        pass
    if t:
        stats.update({k: int(v) for k, v in t.groupdict().items()})
        stats["tasks_executed"] = stats["attempted"] - stats["didnt_need"]
    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("log")
    ap.add_argument("--machine", required=True)
    ap.add_argument("--metrics", default="metrics.txt")
    ap.add_argument("--json", dest="json_out", default="cache-stats.json")
    args = ap.parse_args()

    with open(args.log, encoding="utf-8", errors="replace") as fh:
        stats = parse(fh.read())
    stats["machine"] = args.machine

    with open(args.json_out, "w", encoding="utf-8") as fh:
        json.dump(stats, fh, indent=2)

    with open(args.metrics, "a", encoding="utf-8") as fh:
        for key in ("hit_rate_pct", "mirror_share_pct", "missed", "tasks_executed"):
            if key in stats:
                fh.write(f"sstate_{key}{{machine=\"{args.machine}\"}} {stats[key]}\n")

    if "hit_rate_pct" in stats:
        print(f"[{args.machine}] sstate hit rate {stats['hit_rate_pct']}% "
              f"(local {stats['local']}, mirror {stats['mirrors']}, missed {stats['missed']})")
    else:
        print("No sstate summary found in log", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
