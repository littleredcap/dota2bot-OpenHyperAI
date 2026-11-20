#!/usr/bin/env python3
"""Verify a conservative, source-backed Dota 7.42 compatibility matrix.

Not a patch parser and not a runtime compatibility certification.
Run from repository root, using only the Python standard library.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def strip_lua_comments(source: str) -> str:
    result, i, quote = [], 0, None
    while i < len(source):
        char = source[i]
        if quote:
            result.append(char)
            if char == "\\" and i + 1 < len(source):
                i += 1
                result.append(source[i])
            elif char == quote:
                quote = None
            i += 1
            continue
        if source.startswith("--[[", i):
            end = source.find("]]", i + 4)
            segment = source[i:end + 2] if end >= 0 else source[i:]
            result.append("\n" * segment.count("\n"))
            i = end + 2 if end >= 0 else len(source)
            continue
        if source.startswith("--", i):
            end = source.find("\n", i)
            if end < 0:
                break
            result.append("\n")
            i = end + 1
            continue
        if char in ("'", '"'):
            quote = char
        result.append(char)
        i += 1
    return "".join(result)


def matching(source: str, rule: dict) -> bool:
    active = strip_lua_comments(source)
    needle = rule["needle"]
    if rule["check"] == "present":
        return needle in active
    if rule["check"] == "absent":
        return needle.lower() not in active.lower()
    raise ValueError("Unknown rule check: " + str(rule["check"]))


def audit(root: Path) -> dict:
    doc = root / "docs/patch742_hero_inventory.json"
    data = json.loads(doc.read_text(encoding="utf-8"))
    if data["schema"] != "oha.patch742.hero_inventory.v1":
        raise ValueError("Unsupported inventory schema")
    paths = [x["path"] for x in data["hero_files"]]
    actual = sorted(x.relative_to(root).as_posix()
                    for x in (root / "bots/BotLib").glob("hero_*.lua"))
    if paths != actual:
        raise ValueError("Hero inventory not in sync: missing/extra Lua files")
    if len(set(paths)) != len(paths):
        raise ValueError("Duplicate hero files in matrix")
    if data["target_patch"] != "7.42":
        raise ValueError("Unexpected patch target")
    by_name = {Path(x["path"]).name: x for x in data["hero_files"]}
    problems = []
    flagged = set()
    for rule in data["findings"]:
        filename = rule["hero"]
        if filename not in by_name:
            problems.append("Rule references missing hero: " + filename)
            continue
        path = root / "bots/BotLib" / filename
        is_matched = matching(path.read_text(encoding="utf-8"), rule)
        if not is_matched:
            problems.append(rule["id"] + ": source fingerprint changed in " + filename + "; update evidence")
        else:
            flagged.add(rule["id"] + ":" + filename)
        if rule["id"] not in by_name[filename]["rules"]:
            problems.append("Matrix missing rule " + rule["id"] + " for " + filename)
    for row in data["hero_files"]:
        expected = [r for r in data["findings"] if r["hero"] == Path(row["path"]).name]
        status = "E2" if any(x["status"] == "E2" for x in expected) else "E1" if expected else "UNREVIEWED"
        if row["status"] != status or row["rules"] != [x["id"] for x in expected]:
            problems.append("Misclassified hero " + row["path"])
        if row["status"] == "PASS":
            problems.append("Unsafe false claim of verified hero")
    for rule in data["common"]:
        path = root / rule["path"]
        if not path.is_file() or not matching(path.read_text(encoding="utf-8"), rule):
            problems.append("Shared-source fingerprint changed " + rule["id"])
    markdown = (root / "docs/PATCH_7_42_HERO_MATRIX.md").read_text(encoding="utf-8")
    for row in data["hero_files"]:
        if ("|" + " " + chr(96) + row["path"] + chr(96) + " |") not in markdown:
            problems.append("Markdown matrix missing " + row["path"])
    counts = {status: sum(x["status"] == status for x in data["hero_files"])
              for status in ("E2", "E1", "UNREVIEWED")}
    if counts["UNREVIEWED"] < 1:
        problems.append("Matrix must not claim all heroes have been fully audited")
    return {
        "schema": "oha.patch742.audit.v1",
        "baseline_sha": data["baseline_sha"],
        "target_patch": "7.42",
        "hero_file_count": len(paths),
        "counts": counts,
        "checked_rules": len(flagged),
        "shared_checks": len(data["common"]),
        "problems": problems,
        "note": "UNREVIEWED != compatible; static evidence != client verification",
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--json", action="store_true", help="print machine-readable result")
    parser.add_argument("--check", action="store_true", help="exit 1 if evidence is stale")
    args = parser.parse_args(argv)
    try:
        result = audit(args.root.resolve())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print("Audit failed: " + str(exc), file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("7.42 hero files:", result["hero_file_count"],
              "status:", result["counts"], "problems:", len(result["problems"]))
        for problem in result["problems"]:
            print(" - " + problem)
    return 1 if args.check and result["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
