#!/usr/bin/env python3
"""Offline VScript/decision-log abnormality screening, without Dota.

Produces leads only. Missing action logs do not establish missed ability use.
No account IDs or player names are required.
"""
from __future__ import annotations
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

CATEGORIES = {
    "VScript_error": re.compile(r"\bScript Runtime Error\b|Lua Runtime Error|VScript.*Error", re.I),
    "nil_call_or_index": re.compile(r"attempt to (?:index|call) .*nil", re.I),
    "missing_script": re.compile(r"Script not found|Failed to find scripts/vscripts|module .* not found", re.I),
}
MARKER = "[OHA_DECISION]"


def analyze(lines):
    counts, decisions = Counter(), Counter()
    error_line_numbers = []
    processed = 0
    for number, line in enumerate(lines, 1):
        found = []
        for category, pattern in CATEGORIES.items():
            if pattern.search(line):
                counts[category] += 1
                found.append(category)
        if found and len(error_line_numbers) < 50:
            error_line_numbers.append({"line": number, "categories": found})
        if MARKER not in line:
            continue
        processed += 1
        parts = {}
        for field in line.split(MARKER, 1)[1].strip().split():
            if "=" in field:
                k, v = field.split("=", 1)
                parts[k] = v
        if parts.get("reason"):
            key = (parts.get("system", "UNKNOWN"), parts.get("verdict", "UNKNOWN"),
                   parts["reason"])
            decisions[key] += 1
    return {
        "schema": "oha.patch742.log_triage.v1",
        "errors": dict(sorted(counts.items())),
        "error_line_numbers": error_line_numbers,
        "decision_events": processed,
        "decision_reasons": [
            {"system": k[0], "verdict": k[1], "reason": k[2], "observations": v}
            for k, v in sorted(decisions.items())
        ],
        "limitations": "READY alone is not evidence of missed casts; ALLOW does not guarantee action success; no logs is not proof of healthy gameplay.",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    try:
        with args.log.open(encoding="utf-8", errors="replace") as lines:
            result = analyze(lines)
        payload = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(payload, encoding="utf-8")
        else:
            print(payload)
        return 0
    except OSError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
