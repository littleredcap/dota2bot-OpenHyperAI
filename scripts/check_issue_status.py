#!/usr/bin/env python3
"""Check that issue/requirement register never conflates a minimal fix with AI maturity.

This checks a version-controlled documentation snapshot; it never queries GitHub
or assumes unmerged PRs are shipping. No Dota client is involved.
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import sys

IMPLEMENTATION = {
    "REPORTED", "SCOPED", "MIN_FIX_DRAFT", "EXP_DRAFT",
    "INFRA_DRAFT", "DOC_DRAFT", "DEFERRED", "MERGED", "REVERTED",
}
VERIFICATION = {"NO_RUN", "STATIC_ONLY", "OFFLINE_PASS", "CLIENT_PASS", "MATCH_PASS"}
STRATEGY = {"OLD", "PARTIAL", "TODO", "RESEARCH", "N_A", "STRATEGY_VALIDATED"}
ROW_ID = re.compile(r"(?:GH-\d+|C742-[A-Z0-9-]+|ENG-[A-Z0-9-]+|F-\d{2})\Z")
PR_LINK = re.compile(r"https://github\.com/littleredcap/dota2bot-OpenHyperAI/pull/(\d+)")

REQUIRED_IDS = {
    "GH-155", "GH-159", "GH-170", "GH-176",
    "C742-01", "C742-05", "C742-06", "C742-07", "C742-08",
    "C742-09", "C742-10", "C742-13", "C742-ALL",
    "ENG-DQ1", "ENG-METRICS", "ENG-PATCH-MATRIX",
    "ENG-REGISTER", "ENG-CLIENT",
}
REQUIRED_IDS |= {f"F-{i:02d}" for i in (*range(1, 10), 10, 11)}
# PR coverage check is intentionally a snapshot: bump only after reviewing new
# discovered PRs and their own issue/requirement record.
PR_SNAPSHOT = set(range(1, 18))


def parse_register(source: str) -> tuple[list[dict], list[str]]:
    errors = []
    records = []
    ids = set()
    for number, line in enumerate(source.splitlines(), 1):
        if not line.startswith("| "):
            continue
        pieces = [p.strip() for p in line.split("|")[1:-1]]
        if not pieces or not ROW_ID.fullmatch(pieces[0]):
            continue
        if len(pieces) != 8:
            errors.append(f"line {number}: issue row requires 8 columns, got {len(pieces)}")
            continue
        identifier, title, impl, verification, strategy, minimum, next_step, links = pieces
        if identifier in ids:
            errors.append(f"line {number}: duplicate ID {identifier}")
        ids.add(identifier)
        for name, value, allowed in (
            ("implementation", impl, IMPLEMENTATION),
            ("verification", verification, VERIFICATION),
            ("strategy", strategy, STRATEGY),
        ):
            if value not in allowed:
                errors.append(f"line {number}: unsupported {name}={value}")
        if not all(v and v != "—" for v in (title, minimum, next_step)):
            errors.append(f"line {number}: title, minimum scope and future action required")
        if impl in ("MIN_FIX_DRAFT", "EXP_DRAFT", "DOC_DRAFT", "INFRA_DRAFT", "MERGED") and not PR_LINK.search(links):
            errors.append(f"line {number}: implementation {impl} requires concrete PR link")
        if verification == "OFFLINE_PASS" and not PR_LINK.search(links):
            errors.append(f"line {number}: OFFLINE_PASS requires traceable CI/PR link")
        if strategy == "STRATEGY_VALIDATED" and verification != "MATCH_PASS":
            errors.append(f"line {number}: strategy validation requires actual match evidence")
        if strategy in ("OLD", "PARTIAL", "TODO") and next_step in ("已完成", "完成", "无需进一步工作"):
            errors.append(f"line {number}: incomplete strategy cannot be marked done")
        records.append({
            "id": identifier, "title": title, "implementation": impl, "verification": verification,
            "strategy": strategy, "minimum": minimum, "next": next_step, "links": links,
        })
    missing = REQUIRED_IDS - ids
    if missing:
        errors.append("missing tracked issue/requirement IDs: " + ", ".join(sorted(missing)))
    seen_prs = set()
    for row in records:
        seen_prs.update(int(n) for n in PR_LINK.findall(row["links"]))
    missing_prs = PR_SNAPSHOT - seen_prs
    if missing_prs:
        errors.append("missing PR associations: " + ", ".join(map(str, sorted(missing_prs))))
    if not records:
        errors.append("no issue rows were parsed")
    return records, errors


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, default=Path("docs/ISSUE_AND_REQUIREMENT_STATUS.md"))
    args = parser.parse_args(argv)
    try:
        content = args.file.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"Cannot read register: {exc}", file=sys.stderr)
        return 1
    rows, errors = parse_register(content)
    counts = Counter((row["implementation"], row["verification"]) for row in rows)
    print(f"{len(rows)} tracked issues and requirements, {len(counts)} status combinations")
    for err in errors:
        print("INVALID: " + err, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
