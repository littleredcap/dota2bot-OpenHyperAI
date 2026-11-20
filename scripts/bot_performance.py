#!/usr/bin/env python3
"""Offline OHA bot match importer and performance comparison (stdlib only).

Does not automatically collect Local Host games or assert that metrics imply an AI bug.
Never stores Steam account IDs, player names, chat, or replay contents.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import statistics
import sys
import urllib.error
import urllib.request


class DataError(ValueError):
    pass


COUNTS = ("kills", "deaths", "assists", "last_hits", "denies", "obs_placed", "sen_placed", "camps_stacked")
NUMBERS = ("gold_per_min", "xp_per_min", "net_worth", "hero_damage", "tower_damage", "hero_healing", "stun_seconds")
METRICS = COUNTS + NUMBERS
OPEN_DOTA_FIELDS = {key: key for key in METRICS}
OPEN_DOTA_FIELDS["stun_seconds"] = "stuns"


def text_field(value, name, fallback="unknown"):
    if value is None or value == "":
        return fallback
    if not isinstance(value, (str, int)) or isinstance(value, bool):
        raise DataError(f"{name} must be a string or integer")
    result = str(value).strip()
    if not result or any(ord(char) < 32 for char in result):
        raise DataError(f"{name} must be nonempty and printable")
    return result[:128]


def nonnegative(value, label, integer=False):
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or value < 0:
        raise DataError(f"{label} must be a finite, nonnegative number")
    if integer and int(value) != value:
        raise DataError(f"{label} must be an integer")
    return int(value) if integer else float(value)


def slot_of(value):
    slot = nonnegative(value, "player_slot", integer=True)
    if slot not in (*range(5), *range(128, 133)):
        raise DataError("player_slot must be 0..4 (Radiant) or 128..132 (Dire)")
    return slot


def side_of(slot):
    return "radiant" if slot < 5 else "dire"


def position_of(value):
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        raise DataError("position must be 1..5 or null")
    try:
        pos = int(value)
    except (TypeError, ValueError):
        raise DataError("position must be 1..5 or null") from None
    if pos not in range(1, 6) or str(value) not in (str(pos),):
        raise DataError("position must be 1..5 or null")
    return pos


def read_json(path):
    try:
        with Path(path).open(encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        raise DataError(f"Cannot read JSON {path}: {exc}") from exc


def sorted_sources(inputs):
    paths = []
    for text in inputs:
        path = Path(text)
        if path.is_dir():
            paths.extend(sorted(path.glob("*.json")))
        elif path.is_file():
            paths.append(path)
        else:
            raise DataError(f"Input path not found: {path}")
    if not paths:
        raise DataError("No .json input files")
    return paths


def roster_totals(players):
    """Only derive team totals when exactly five unique player slots exist."""
    result = {}
    for team in ("radiant", "dire"):
        members = [p for p in players if side_of(p["player_slot"]) == team]
        if len(members) != 5 or len({p["player_slot"] for p in members}) != 5:
            result[team] = (None, None)
            continue
        kills = sum(p["kills"] for p in members) if all(p["kills"] is not None for p in members) else None
        damage = sum(p["hero_damage"] for p in members) if all(p["hero_damage"] is not None for p in members) else None
        result[team] = (kills, damage)
    return result


def inspect_players(raw_players, source):
    if not isinstance(raw_players, list) or not raw_players:
        raise DataError("match.players must be a nonempty list")
    players = []
    used = set()
    for player in raw_players:
        if not isinstance(player, dict):
            raise DataError("each match.players entry must be an object")
        slot = slot_of(player.get("player_slot"))
        if slot in used:
            raise DataError(f"duplicate player_slot {slot} in one match")
        used.add(slot)
        record = {"player_slot": slot}
        for key in METRICS:
            source_key = OPEN_DOTA_FIELDS[key] if source == "opendota" else key
            record[key] = nonnegative(player.get(source_key), f"player {slot}.{source_key}", integer=key in COUNTS)
        if any(record[k] is None for k in ("kills", "deaths", "assists")):
            raise DataError(f"player {slot}: kills/deaths/assists must be present (no implicit zeros)")
        players.append(record)
    return players


def optional_side_total(raw, team, label):
    if raw is None:
        return None
    if not isinstance(raw, dict):
        raise DataError(f"{label} must be a dict indexed by radiant/dire")
    return nonnegative(raw.get(team), f"{label}.{team}", integer=label == "team_kills")


def manual_records(match):
    if not isinstance(match, dict) or match.get("schema") != "oha.match.v1":
        raise DataError("Manual input requires schema='oha.match.v1'")
    required = ("match_id", "duration_seconds", "patch", "bot_build", "game_mode", "lobby_type", "difficulty", "opponent_profile", "radiant_win")
    for key in required:
        if key not in match or match[key] is None:
            raise DataError(f"Manual input missing required match field {key}")
    if not isinstance(match["radiant_win"], bool):
        raise DataError("radiant_win must be true or false")
    duration = nonnegative(match["duration_seconds"], "duration_seconds", integer=True)
    if not 1 <= duration <= 36000:
        raise DataError("duration_seconds out of range (1..36000)")
    raw_players = match.get("players")
    players = inspect_players(raw_players, "manual")
    totals = roster_totals(players)
    raw_by_slot = {slot_of(p["player_slot"]): p for p in raw_players}
    result = []
    for player in players:
        slot = player["player_slot"]
        original = raw_by_slot[slot]
        if "is_oha_bot" not in original or not isinstance(original["is_oha_bot"], bool):
            raise DataError(f"player {slot} requires explicit boolean is_oha_bot")
        if not original["is_oha_bot"]:
            continue
        team = side_of(slot)
        kills = optional_side_total(match.get("team_kills"), team, "team_kills")
        dmg = optional_side_total(match.get("team_hero_damage"), team, "team_hero_damage")
        result.append(make_row(player, team, match, "manual", duration,
                               original.get("hero"), original.get("position"),
                               kills if kills is not None else totals[team][0],
                               dmg if dmg is not None else totals[team][1],
                               match["radiant_win"]))
    if not result:
        raise DataError("Manual match has no is_oha_bot=true player")
    return result


def opendota_records(match, bot_slots, bot_side, metadata, positions, hero_map):
    if not isinstance(match, dict) or "players" not in match:
        raise DataError("OpenDota input must contain match.players")
    if not isinstance(match.get("radiant_win"), bool):
        raise DataError("OpenDota match missing boolean radiant_win; no outcome will be guessed")
    duration = nonnegative(match.get("duration"), "duration", integer=True)
    if duration is None or not 1 <= duration <= 36000:
        raise DataError("OpenDota duration must be 1..36000 seconds")
    if "match_id" not in match:
        raise DataError("OpenDota match_id is required for deduplication")
    players = inspect_players(match["players"], "opendota")
    totals = roster_totals(players)
    source_by_slot = {slot_of(p["player_slot"]): p for p in match["players"]}
    data = dict(metadata)
    data["match_id"] = match["match_id"]
    data["game_mode"] = text_field(match.get("game_mode"), "game_mode")
    data["lobby_type"] = text_field(match.get("lobby_type"), "lobby_type")
    # Do NOT interpret a numeric OpenDota patch ID as a Dota patch version.
    data["patch"] = metadata.get("patch") or "unknown"
    result = []
    for player in players:
        slot = player["player_slot"]
        team = side_of(slot)
        if not (slot in bot_slots or (bot_side in ("radiant", "dire", "both") and (bot_side == team or bot_side == "both"))):
            continue
        original = source_by_slot[slot]
        hero_id = original.get("hero_id")
        if hero_id is None:
            raise DataError(f"OpenDota player {slot} lacks hero_id")
        hero = hero_map.get(str(hero_id), f"hero_id:{hero_id}")
        if not isinstance(hero, str) or not hero:
            raise DataError(f"Invalid hero mapping for ID {hero_id}")
        if "position" in original:
            # OpenDota positions are only accepted when explicit 1-5 is supplied.
            pos = original["position"]
        else:
            pos = positions.get(slot)
        result.append(make_row(player, team, data, "opendota", duration, hero, pos,
                               totals[team][0], totals[team][1], match["radiant_win"]))
    if not result:
        raise DataError("No selected OHA bot slots in this OpenDota match")
    return result


def make_row(player, team, match, source, duration, hero, position, team_kills, team_damage, radiant_win):
    if hero is None:
        raise DataError("Bot hero required: do not assume a role or hero from unknown player data")
    row = {
        "schema": "oha.bot_row.v1",
        "source": source,
        "match_id": text_field(match["match_id"], "match_id"),
        "player_slot": player["player_slot"],
        "team": team,
        "hero": text_field(hero, "hero"),
        "position": position_of(position),
        "patch": text_field(match.get("patch"), "patch"),
        "bot_build": text_field(match.get("bot_build"), "bot_build"),
        "game_mode": text_field(match.get("game_mode"), "game_mode"),
        "lobby_type": text_field(match.get("lobby_type"), "lobby_type"),
        "difficulty": text_field(match.get("difficulty"), "difficulty"),
        "opponent_profile": text_field(match.get("opponent_profile"), "opponent_profile"),
        "duration_seconds": duration,
        "won": radiant_win if team == "radiant" else not radiant_win,
        "team_kills": nonnegative(team_kills, "team_kills", integer=True),
        "team_hero_damage": nonnegative(team_damage, "team_hero_damage"),
    }
    row.update(player)
    row["kill_participation"] = ((player["kills"] + player["assists"]) / team_kills
                                 if team_kills and team_kills > 0 else None)
    row["hero_damage_share"] = (player["hero_damage"] / team_damage
                                if team_damage and team_damage > 0 and player["hero_damage"] is not None else None)
    return row


def validate_stored(row):
    if not isinstance(row, dict) or row.get("schema") != "oha.bot_row.v1":
        raise DataError("Dataset requires oha.bot_row.v1 rows")
    for field in ("match_id", "hero", "team", "patch", "bot_build", "game_mode", "lobby_type", "difficulty", "opponent_profile", "source"):
        if not isinstance(row.get(field), str) or not row[field]:
            raise DataError(f"Stored row missing {field}")
    if row["team"] not in ("radiant", "dire") or side_of(slot_of(row.get("player_slot"))) != row["team"]:
        raise DataError("Stored team/player_slot inconsistent")
    position_of(row.get("position"))
    for key in METRICS:
        nonnegative(row.get(key), key, integer=key in COUNTS)
    for key in ("team_kills", "team_hero_damage", "kill_participation", "hero_damage_share"):
        nonnegative(row.get(key), key, integer=key == "team_kills")
    duration = nonnegative(row.get("duration_seconds"), "duration_seconds", integer=True)
    if not duration or duration > 36000:
        raise DataError("Stored duration_seconds invalid")
    if not isinstance(row.get("won"), bool):
        raise DataError("Stored won must be boolean")


def load_dataset(path):
    records = {}
    if not Path(path).exists():
        return records
    with Path(path).open(encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
                validate_stored(row)
            except (DataError, json.JSONDecodeError) as exc:
                raise DataError(f"{path}:{lineno}: {exc}") from exc
            key = (row["source"], row["match_id"], row["player_slot"])
            if key in records and records[key] != row:
                raise DataError(f"Conflicting dataset row {key}")
            records[key] = row
    return records


def append_dataset(path, rows):
    records = load_dataset(path)
    added = 0
    for row in rows:
        validate_stored(row)
        key = (row["source"], row["match_id"], row["player_slot"])
        if key in records:
            if records[key] != row:
                raise DataError(f"Conflicting re-import {key}; use a new dataset or fix the original")
        else:
            records[key] = row
            added += 1
    dest = Path(path)
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Stable output allows audit and diffs; write a temporary sibling first.
    temp = dest.with_name(dest.name + ".tmp")
    with temp.open("w", encoding="utf-8") as f:
        for key in sorted(records):
            f.write(json.dumps(records[key], ensure_ascii=False, sort_keys=True, allow_nan=False) + "\n")
    temp.replace(dest)
    return added, len(records)


def wilson(wins, n, z=1.959963984540054):
    if n == 0:
        return None
    p = wins / n
    denom = 1 + z * z / n
    mid = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt((p * (1 - p) + z * z / (4 * n)) / n) / denom
    return [max(0., mid - half), min(1., mid + half)]


def average(values):
    values = [v for v in values if v is not None]
    return round(statistics.mean(values), 5) if values else None


def divide_or_none(a, b):
    return a / b if a is not None and b and b > 0 else None


# Dimensions must match exactly for comparisons; we never auto-infer OHA roles.
CONTEXT = ("hero", "position", "patch", "game_mode", "lobby_type", "difficulty", "opponent_profile", "source", "team")
OUTPUT_METRICS = ("kills", "deaths", "assists", "gold_per_min", "xp_per_min",
                  "kill_participation", "hero_damage_share", "hero_damage_per_min",
                  "tower_damage_per_min", "healing_per_min", "last_hits_per_min",
                  "deaths_per_10min", "obs_placed", "sen_placed", "camps_stacked", "stun_seconds", "net_worth")


def summary(rows):
    first = rows[0]
    out = {key: first[key] for key in (*CONTEXT, "bot_build")}
    out["sample_count"] = len(rows)
    out["matches_count"] = len({(r["source"], r["match_id"]) for r in rows})
    out["wins"] = sum(r["won"] is True for r in rows)
    out["win_rate"] = round(out["wins"] / len(rows), 5)
    out["win_rate_wilson_95"] = wilson(out["wins"], len(rows))
    computed = []
    for r in rows:
        mins = r["duration_seconds"] / 60
        computed.append({
            **r,
            "hero_damage_per_min": divide_or_none(r["hero_damage"], mins),
            "tower_damage_per_min": divide_or_none(r["tower_damage"], mins),
            "healing_per_min": divide_or_none(r["hero_healing"], mins),
            "last_hits_per_min": divide_or_none(r["last_hits"], mins),
            "deaths_per_10min": divide_or_none(r["deaths"], mins / 10),
        })
    out["metrics"] = {key: average([r.get(key) for r in computed]) for key in OUTPUT_METRICS}
    out["metric_samples"] = {key: sum(r.get(key) is not None for r in computed) for key in OUTPUT_METRICS}
    out["zero_team_kill_matches"] = sum(r["team_kills"] == 0 for r in rows)
    out["unknown_context"] = any(out[key] in (None, "unknown", "") for key in CONTEXT if key != "position") or out["position"] is None
    return out


def analyze(rows, baseline_build=None, candidate_build=None, min_games=30):
    groups = defaultdict(list)
    for row in rows:
        key = tuple(row[k] for k in (*CONTEXT, "bot_build"))
        groups[key].append(row)
    summaries = [summary(group) for _, group in sorted(groups.items(), key=lambda kv: str(kv[0]))]
    comparisons = []
    if baseline_build is not None and candidate_build is not None:
        pairs = defaultdict(dict)
        for entry in summaries:
            key = tuple(entry[k] for k in CONTEXT)
            pairs[key][entry["bot_build"]] = entry
        for key, by_build in sorted(pairs.items(), key=lambda kv: str(kv[0])):
            if baseline_build not in by_build or candidate_build not in by_build:
                continue
            a, b = by_build[baseline_build], by_build[candidate_build]
            ready = (not a["unknown_context"] and not b["unknown_context"] and
                     a["sample_count"] >= min_games and b["sample_count"] >= min_games)
            flags = []
            if ready:
                if b["win_rate_wilson_95"][1] < a["win_rate_wilson_95"][0]:
                    flags.append("WIN_RATE_CI_SEPARATION_REVIEW")
                ak, bk = a["metrics"]["kill_participation"], b["metrics"]["kill_participation"]
                if (ak is not None and bk is not None and
                    min(a["metric_samples"]["kill_participation"], b["metric_samples"]["kill_participation"]) >= min_games
                    and bk <= ak - 0.15):
                    flags.append("KP_DROP_REVIEW")
                ad, bd = a["metrics"]["hero_damage_per_min"], b["metrics"]["hero_damage_per_min"]
                if (ad and bd is not None and bd <= ad * 0.8 and
                    min(a["metric_samples"]["hero_damage_per_min"], b["metric_samples"]["hero_damage_per_min"]) >= min_games):
                    flags.append("HERO_DAMAGE_PM_DROP_REVIEW")
                ag, bg = a["metrics"]["gold_per_min"], b["metrics"]["gold_per_min"]
                if (ak is not None and bk is not None and ag and bg and
                    bg >= ag * 1.1 and bk <= ak - 0.15 and
                    min(a["metric_samples"]["kill_participation"], b["metric_samples"]["kill_participation"]) >= min_games):
                    flags.append("GPM_UP_KP_DOWN_REVIEW")
            comparisons.append({
                "context": dict(zip(CONTEXT, key)),
                "baseline_build": baseline_build,
                "candidate_build": candidate_build,
                "baseline_n": a["sample_count"], "candidate_n": b["sample_count"],
                "eligible": ready,
                "reason": "COMPARABLE" if ready else "INSUFFICIENT_SAMPLES_OR_UNKNOWN_CONTEXT",
                "win_rate_delta": round(b["win_rate"] - a["win_rate"], 5),
                "kp_delta": round(b["metrics"]["kill_participation"] - a["metrics"]["kill_participation"], 5)
                            if a["metrics"]["kill_participation"] is not None and b["metrics"]["kill_participation"] is not None else None,
                "review_flags": flags,
            })
    return {
        "schema": "oha.performance_report.v1",
        "scope": "Only explicitly marked OHA bot observations; offline descriptive metrics.",
        "limitations": [
            "Low KDA/KP is not itself a diagnosis of an AI error.",
            "Wilson intervals describe individual win rates, not causation or an experiment-wide significance guarantee.",
            "Replay-derived metrics can be absent; missing data is never replaced by zero.",
            "No comparisons without equal hero, position, patch, game mode, lobby type, difficulty, opponent profile, source and side.",
            "At least min_games observations in both builds, plus non-missing comparison context, are required for review flags.",
        ],
        "min_games": min_games,
        "bot_observations": len(rows),
        "match_count": len({(r["source"], r["match_id"]) for r in rows}),
        "groups": summaries,
        "comparisons": comparisons,
    }


def markdown_report(report):
    def num(value, percent=False, precision=2):
        if value is None:
            return "—"
        return f"{value * 100:.1f}%" if percent else f"{value:.{precision}f}"
    lines = [
        "# OHA Bot performance report",
        "",
        f"Recorded OHA bot observations: **{report['bot_observations']}** across **{report['match_count']}** matches.",
        "Only explicit OHA bot slots are included. Missing values are not zeros.",
        "",
        "## Hero / position / build breakdown",
        "",
        "| Hero | Pos | Build | Patch | Side | Games | Win% (Wilson 95%) | KP | GPM | XPM | Hero DPM | Tower DPM | Damage share |",
        "| --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in report["groups"]:
        metrics = item["metrics"]
        ci = item["win_rate_wilson_95"]
        win = f"{num(item['win_rate'], True)} ({num(ci[0], True)}–{num(ci[1], True)})"
        cells = [
            item["hero"], str(item["position"] or "?"), item["bot_build"][:12], item["patch"],
            item["team"], str(item["sample_count"]), win,
            num(metrics["kill_participation"], True), num(metrics["gold_per_min"]),
            num(metrics["xp_per_min"]), num(metrics["hero_damage_per_min"]),
            num(metrics["tower_damage_per_min"]), num(metrics["hero_damage_share"], True),
        ]
        lines.append("| " + " | ".join(str(x).replace("|", "/").replace("\n", " ") for x in cells) + " |")
    lines.extend(["", "## Matched build comparisons", "",
                  "Flags are **review leads**, not automatically confirmed defects.",
                  ""])
    if not report["comparisons"]:
        lines.append("No baseline-vs-candidate pair was requested or available.")
    else:
        for item in report["comparisons"]:
            c = item["context"]
            flags = ", ".join(item["review_flags"]) if item["review_flags"] else "none"
            lines.append(f"- **{c['hero']}** pos {c['position']}, {c['patch']}, {c['team']}: "
                         f"{item['baseline_n']} vs {item['candidate_n']} observations; "
                         f"eligible={item['eligible']}; win delta={num(item['win_rate_delta'], True)}; "
                         f"KP delta={num(item['kp_delta'], True)}; review flags={flags}.")
    lines.extend(["", "## Interpretation limits", ""])
    lines.extend(f"- {limit}" for limit in report["limitations"])
    return "\n".join(lines) + "\n"


def parse_slots(text):
    if not text:
        return set()
    slots = set()
    for raw in text.split(","):
        try:
            value = int(raw.strip())
        except ValueError:
            raise DataError(f"Invalid player_slot {raw!r}") from None
        slots.add(slot_of(value))
    return slots


def parse_positions(text):
    result = {}
    if not text:
        return result
    for pair in text.split(","):
        if ":" not in pair:
            raise DataError("positions syntax must be player_slot:position,...")
        raw_slot, raw_pos = pair.split(":", 1)
        result[slot_of(int(raw_slot))] = position_of(raw_pos)
    return result


def fetch_public_match(match_id, output):
    if not str(match_id).isdigit():
        raise DataError("match_id must be numeric for OpenDota fetch")
    request = urllib.request.Request(
        f"https://api.opendota.com/api/matches/{match_id}",
        headers={"User-Agent": "OHA-Bot-Performance/1.0 (manual fetch by ID)"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            content = response.read(10 * 1024 * 1024 + 1)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise DataError(f"OpenDota fetch failed (match may be unavailable/private): {exc}") from exc
    if len(content) > 10 * 1024 * 1024:
        raise DataError("OpenDota match response exceeds 10MB")
    try:
        result = json.loads(content)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DataError("OpenDota response was not valid JSON") from exc
    if not isinstance(result, dict) or "players" not in result:
        raise DataError("OpenDota returned no public match players")
    path = Path(output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    return str(path)


def cli(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    imp = sub.add_parser("ingest", help="Import local/manual or saved OpenDota match JSON")
    imp.add_argument("--input", nargs="+", required=True, help="JSON files or directories")
    imp.add_argument("--format", choices=("manual", "opendota"), required=True)
    imp.add_argument("--out", required=True, help="Persistent local JSONL dataset")
    sel = imp.add_mutually_exclusive_group()
    sel.add_argument("--bot-slots", help="OpenDota: explicit OHA player slots, e.g. 0,1,128")
    sel.add_argument("--bot-side", choices=("radiant", "dire", "both"), help="OpenDota: when ALL slots on that side are OHA bots")
    imp.add_argument("--positions", help="OpenDota: explicit player_slot:position pairs; never guess from lane_role")
    imp.add_argument("--hero-map", help="Optional JSON {hero_id: internal_hero_name}")
    imp.add_argument("--patch", help="Explicit Dota patch, e.g. 7.42; unknown otherwise")
    imp.add_argument("--build", help="OHA commit SHA/label, e.g. cb814c6c; unknown otherwise")
    imp.add_argument("--difficulty", default="unknown")
    imp.add_argument("--opponent-profile", default="unknown")
    rep = sub.add_parser("report", help="Analyze stored dataset, optionally compare two builds")
    rep.add_argument("--data", required=True)
    rep.add_argument("--json-out", help="Write JSON report")
    rep.add_argument("--md-out", help="Write Markdown report")
    rep.add_argument("--baseline-build")
    rep.add_argument("--candidate-build")
    rep.add_argument("--min-games", type=int, default=30)
    fetch = sub.add_parser("fetch", help="Fetch one public OpenDota match explicitly by ID")
    fetch.add_argument("--match-id", required=True)
    fetch.add_argument("--out", required=True)
    args = p.parse_args(argv)

    try:
        if args.command == "fetch":
            print(f"Saved public match to {fetch_public_match(args.match_id, args.out)}")
        elif args.command == "ingest":
            if args.format == "opendota" and not args.bot_slots and not args.bot_side:
                raise DataError("OpenDota requires explicit --bot-slots or --bot-side; never infer OHA bots")
            if args.format == "manual" and (args.bot_slots or args.bot_side or args.positions or args.hero_map):
                raise DataError("Manual records already contain OHA selection/position; OpenDota-only options are unsupported")
            hero_map = read_json(args.hero_map) if args.hero_map else {}
            if not isinstance(hero_map, dict):
                raise DataError("--hero-map JSON must be a dict")
            metadata = {
                "patch": args.patch or "unknown",
                "bot_build": args.build or "unknown",
                "difficulty": args.difficulty,
                "opponent_profile": args.opponent_profile,
            }
            rows = []
            for path in sorted_sources(args.input):
                match = read_json(path)
                if args.format == "manual":
                    rows.extend(manual_records(match))
                else:
                    rows.extend(opendota_records(
                        match, parse_slots(args.bot_slots), args.bot_side,
                        metadata, parse_positions(args.positions), hero_map))
            added, total = append_dataset(args.out, rows)
            print(f"Imported {added} new OHA bot observations; total {total} in {args.out}")
        else:
            if (args.baseline_build is None) != (args.candidate_build is None):
                raise DataError("Specify both --baseline-build and --candidate-build")
            if args.min_games < 1:
                raise DataError("--min-games must be >= 1")
            records = load_dataset(args.data)
            report = analyze(list(records.values()), args.baseline_build,
                             args.candidate_build, args.min_games)
            md = markdown_report(report)
            if args.json_out:
                path = Path(args.json_out)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False), encoding="utf-8")
            if args.md_out:
                path = Path(args.md_out)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(md, encoding="utf-8")
            if not args.json_out and not args.md_out:
                print(md)
            else:
                print(f"Report: {report['bot_observations']} bot observations, {report['match_count']} matches")
        return 0
    except (DataError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(cli())
