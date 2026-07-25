#!/usr/bin/env python3
"""Fail when a link-scanner report contains broken internal links.

scripts/utils/link-scanner.py reports its findings and exits 0 whatever it
finds, so a gate that only invokes it can never fail.  This reads the JSON
report the scanner writes and turns the broken-link count into an exit status.
"""

import json
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <link-scan.json>", file=sys.stderr)
        return 2

    with open(sys.argv[1], encoding="utf-8") as report_file:
        report = json.load(report_file)

    summary = report["summary"]
    total = summary["total_links"]
    broken = summary["broken_links"]
    print(f"{total} internal links, {broken} broken")

    if broken:
        for entry in report.get("broken_links", []):
            print(f"  {entry}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
