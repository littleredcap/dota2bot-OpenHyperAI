#!/usr/bin/env python3
"""Summarize opt-in [OHA_DECISION] lines from a captured Dota console log.

This does NOT infer whether a cast *should* have happened. Readiness and
policy decisions are separate, and only explicitly instrumented Consider()
sites can reveal why a candidate was rejected.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path

MARKER = "[OHA_DECISION]"
ALIAS = {
    "astral_imprisonment": ("ABILITY", "obsidian_destroyer_astral_imprisonment"),
    "disruption": ("ABILITY", "shadow_demon_disruption"),
    "eul_combo": ("ITEM", "item_cyclone"),
    "eul_escape": ("ITEM", "item_cyclone"),
}

def parse_line(line: str) -> dict[str, str] | None:
    offset = line.find(MARKER)
    if offset < 0:
        return None
    result: dict[str, str] = {}
    for token in line[offset + len(MARKER):].strip().split():
        if "=" in token:
            key, value = token.split("=", 1)
            result[key] = value
    if not all(result.get(key) for key in ("pid", "hero", "system", "action", "verdict", "reason")):
        return None
    return result

def summarize(lines: list[str], min_ready_samples: int = 3) -> dict:
    rows: dict[tuple[str, str, str, str], dict] = {}
    gates: dict[tuple[str, str], Counter[str]] = {}
    recognized = 0
    for line in lines:
        event = parse_line(line)
        if event is None:
            continue
        recognized += 1
        identity = (event["pid"], event["hero"])
        system, action = event["system"], event["action"]
        if system == "BOT" and action == "cast_gate":
            gates.setdefault(identity, Counter())[event["reason"]] += 1
            continue
        if system in ("ABILITY", "ITEM") and event["verdict"] == "STATUS":
            category, canonical = system, action
        elif system == "BANISH" and event["verdict"] in ("ALLOW", "BLOCK", "NO_PROPOSAL"):
            category, canonical = ALIAS.get(action, ("ABILITY", action))
        else:
            continue
        key = (identity[0], identity[1], category, canonical)
        record = rows.setdefault(key, {
            "pid": identity[0], "hero": identity[1], "category": category, "action": canonical,
            "status": Counter(), "decisions": Counter(), "reasons": Counter(), "intents": Counter(),
        })
        if event["verdict"] == "STATUS":
            record["status"][event["reason"]] += 1
        else:
            record["decisions"][event["verdict"]] += 1
            record["reasons"][event["reason"]] += 1
            if "intent" in event:
                record["intents"][event["intent"]] += 1

    output = []
    for _, row in sorted(rows.items()):
        status, decisions = row["status"], row["decisions"]
        ready = status.get("READY", 0)
        if ready >= min_ready_samples and sum(decisions.values()) == 0:
            review = "READINESS_WITHOUT_DECISION_TRACE"
        elif ready >= min_ready_samples and decisions.get("NO_PROPOSAL", 0) > 0 and decisions.get("ALLOW", 0) == 0:
            review = "READY_WITH_NO_PROPOSAL"
        elif decisions.get("BLOCK", 0) > decisions.get("ALLOW", 0):
            review = "POLICY_BLOCK_FREQUENT"
        else:
            review = "NO_AUTOMATIC_FLAG"
        output.append({
            **{k: row[k] for k in ("pid", "hero", "category", "action")},
            "status": dict(sorted(status.items())),
            "decisions": dict(sorted(decisions.items())),
            "reasons": dict(sorted(row["reasons"].items())),
            "intents": dict(sorted(row["intents"].items())),
            "review": review,
        })
    return {
        "schema": "oha-decision-summary-v1",
        "events": recognized,
        "min_ready_samples": min_ready_samples,
        "limitations": "READY is not evidence that casting was tactically desirable; ALLOW is not proof a cast executed.",
        "cast_gates": [
            {"pid": pid, "hero": hero, "status": dict(sorted(counter.items()))}
            for (pid, hero), counter in sorted(gates.items())
        ],
        "actions": output,
    }

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="Captured Dota console/log text")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    parser.add_argument("--min-ready-samples", type=int, default=3, help="Threshold to flag status-only activity")
    args = parser.parse_args()
    if args.min_ready_samples < 1:
        parser.error("--min-ready-samples must be >= 1")
    try:
        data = summarize(args.log.read_text(encoding="utf-8", errors="replace").splitlines(), args.min_ready_samples)
    except OSError as exc:
        parser.error(str(exc))
    if args.json:
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return 0
    print(f"Recognized {data['events']} decision records")
    print("NOTE:", data["limitations"])
    for gate in data["cast_gates"]:
        print(f"BOT  {gate['hero']} pid={gate['pid']} cast_gate={gate['status']}")
    for row in data["actions"]:
        print(
            f"{row['review']}: {row['hero']} pid={row['pid']} {row['category']} {row['action']}"
            f" status={row['status']} decision={row['decisions']} reasons={row['reasons']}"
        )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
