#!/usr/bin/env python3
"""Dota 7.42 patch-driven source impact checks for curated structural changes.

The manifest was assembled by checking Valve 7.42 and pinned client hero KV.
This script does NOT fetch the full Valve patch feed or certify all 128 heroes.
It checks actual Lua references and explicitly preserves unreviewed coverage.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

from patch742_audit import strip_lua_comments

CLASSIFICATIONS = {
    "DIRECT_CONFLICT",
    "NEW_CAPABILITY_GAP",
    "SEMANTIC_REVIEW",
    "NO_LEGACY_REFERENCE",
}
REQUIRED_IDS = {
    "C742-01", "C742-02A", "C742-02B", "C742-06", "C742-07",
    "C742-08", "C742-10-OLD", "C742-13", "C742-15",
    "C742-16", "C742-09", "C742-10-NEW", "C742-11",
    "C742-17", "C742-18", "C742-19", "C742-20", "C742-21",
    "C742-22", "C742-23", "C742-14",
}
REMOVED_ITEMS = ("item_khanda", "item_javelin", "item_helm_of_the_overlord")


def validate_rule(rule: dict, patch_url: str, kv_commit: str) -> None:
    required = (
        "id", "title", "source_patch", "path", "test", "needle",
        "classification", "reason", "minimum_fix", "future_strategy", "client_gate",
    )
    for key in required:
        if not isinstance(rule.get(key), str) or not rule[key].strip():
            raise ValueError(f"{rule.get('id', '?')}: missing {key}")
    if not re.fullmatch(r"C742-[0-9A-Z-]+", rule["id"]):
        raise ValueError("Invalid patch impact ID: " + rule["id"])
    if rule["test"] not in ("present", "absent"):
        raise ValueError("Invalid test: " + rule["test"])
    if rule["classification"] not in CLASSIFICATIONS:
        raise ValueError("Invalid classification: " + rule["classification"])
    if rule["classification"] == "DIRECT_CONFLICT" and rule["test"] != "present":
        raise ValueError("DIRECT_CONFLICT must have a positive source conflict fingerprint")
    if rule["source_patch"] != patch_url:
        raise ValueError("Rule lacks correct official patch source")
    if rule.get("source_kv") and kv_commit not in rule["source_kv"]:
        raise ValueError("Hero KV evidence must be pinned to the recorded revision")
    if not rule["path"].startswith("bots/") or not rule["path"].endswith(".lua"):
        raise ValueError("Only explicitly named production Lua paths are supported")


def matches(source: str, rule: dict) -> bool:
    code = strip_lua_comments(source)
    if rule["test"] == "present":
        return rule["needle"] in code
    if rule["test"] == "absent":
        return rule["needle"].lower() not in code.lower()
    raise ValueError("Invalid source test")


def audit(root: Path) -> dict:
    path = root / "docs/patch742_change_impacts.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "oha.patch742.impact.v1":
        raise ValueError("Wrong manifest schema")
    if manifest.get("version") != "7.42":
        raise ValueError("Wrong patch")
    patch = manifest["official_patch"]
    if patch != "https://www.dota2.com/patches/7.42":
        raise ValueError("Wrong official patch URL")
    kv_commit = manifest["source_kv_commit"]
    rules = manifest["rules"]
    ids = [x["id"] for x in rules]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicated patch IDs")
    if set(ids) != REQUIRED_IDS:
        raise ValueError("Missing/unexpected patch rule IDs; update scope and tests")
    problems = []
    result_rules = []
    for rule in rules:
        validate_rule(rule, patch, kv_commit)
        f = root / rule["path"]
        if not f.is_file():
            problems.append("Missing source file: " + rule["path"])
            continue
        result = matches(f.read_text(encoding="utf-8"), rule)
        if not result:
            problems.append(f"{rule['id']} source fingerprint changed: {rule['path']}")
        result_rules.append({
            "id": rule["id"],
            "classification": rule["classification"],
            "path": rule["path"],
            "fingerprint_matched": result,
            "note": "fingerprint is evidence, not real-client verification",
        })
    files = sorted((root / "bots/BotLib").glob("hero_*.lua"))
    if len(files) != manifest["expected_hero_file_count"]:
        problems.append(f"Hero file inventory changed: expected {manifest['expected_hero_file_count']}, got {len(files)}")
    exact_removed_counts = Counter()
    for f in files:
        active = strip_lua_comments(f.read_text(encoding="utf-8"))
        for item in REMOVED_ITEMS:
            if re.search(r"\b" + re.escape(item) + r"\b", active):
                exact_removed_counts[item] += 1
    for item in REMOVED_ITEMS:
        expected = manifest["expected_active_removed_item_hero_counts"][item]
        if exact_removed_counts[item] != expected:
            problems.append(f"{item}: active hero files changed {expected} -> {exact_removed_counts[item]}")
    old_matrix = root / "docs/patch742_hero_inventory.json"
    if not old_matrix.is_file():
        problems.append("Parent static hero matrix is missing")
    else:
        data = json.loads(old_matrix.read_text(encoding="utf-8"))
        by_hero = {x["path"].split("/")[-1]: x for x in data["hero_files"]}
        for hero, id_ in (("hero_weaver.lua", "C742-16"),
                          ("hero_chen.lua", "C742-10-OLD"),
                          ("hero_dazzle.lua", "C742-17"),
                          ("hero_undying.lua", "C742-19")):
            entry = by_hero.get(hero, {})
            if id_ not in entry.get("rules", []):
                problems.append(f"Old hero matrix missing {id_} for {hero}")
            if entry.get("status") == "UNREVIEWED":
                problems.append(f"Hero matrix forgot structural review of {hero}")
    md = root / "docs/PATCH742_CHANGE_IMPACT.md"
    if not md.is_file():
        problems.append("Missing human-readable patch-driven impact review")
    else:
        document = md.read_text(encoding="utf-8")
        for identifier in REQUIRED_IDS:
            if identifier not in document:
                problems.append("Change impact document missing " + identifier)
    return {
        "schema": "oha.patch742.impact_scan.v1",
        "target_patch": manifest["version"],
        "baseline_sha": manifest["baseline_sha"],
        "hero_files_scanned": len(files),
        "curated_patch_changes": len(rules),
        "by_classification": dict(sorted(Counter(x["classification"] for x in rules).items())),
        "removed_item_active_hero_files": {name: exact_removed_counts[name] for name in REMOVED_ITEMS},
        "rules": result_rules,
        "problems": problems,
        "coverage_note": (
            "Only curated 7.42 structural changes and exact token patterns were reviewed. "
            "No match is NOT a compatibility certificate; the 128 hero source files "
            "were NOT fully checked for all Valve hero changes or actual game behavior."
        ),
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, default=Path("."))
    p.add_argument("--check", action="store_true", help="return failure on stale evidence")
    p.add_argument("--json", action="store_true", help="print full JSON impact scan")
    args = p.parse_args(argv)
    try:
        report = audit(args.root.resolve())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print("Patch impact audit failed: " + str(exc), file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(f"Patch {report['target_patch']}: {report['hero_files_scanned']} hero files, "
              f"{report['curated_patch_changes']} selected patch changes")
        print("classifications:", report["by_classification"])
        print("remaining evidence problems:", len(report["problems"]))
        for issue in report["problems"]:
            print(" - " + issue)
    return 1 if args.check and report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
