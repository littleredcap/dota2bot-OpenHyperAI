"""No-network regression for the OHA per-match statistics and cohort rules."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import bot_performance as perf


def hero(slot, *, is_bot=True, hero_name="npc_dota_hero_axe", position=3, kills=2, deaths=3, assists=7, damage=10000):
    return {
        "player_slot": slot, "is_oha_bot": is_bot, "hero": hero_name,
        "position": position, "kills": kills, "deaths": deaths, "assists": assists,
        "gold_per_min": 400, "xp_per_min": 480, "hero_damage": damage,
        "tower_damage": 1200, "last_hits": 100, "hero_healing": None,
    }


def manual_match(match_id="local-demo-1", patch="7.42", build="test-abc", team_kills=20):
    return {
        "schema": "oha.match.v1", "match_id": match_id, "duration_seconds": 2400,
        "patch": patch, "bot_build": build, "game_mode": "all_pick",
        "lobby_type": "custom_local", "difficulty": "fretbots-2",
        "opponent_profile": "valve_default", "radiant_win": True,
        "team_kills": {"radiant": team_kills, "dire": 10},
        "team_hero_damage": {"radiant": 50000, "dire": 40000},
        "players": [hero(0), hero(1, is_bot=False)],
    }


def opendota_player(slot):
    return {
        "player_slot": slot, "hero_id": 100 + slot, "kills": 2 + (slot == 0),
        "deaths": 3, "assists": 6, "hero_damage": 2000,
        "gold_per_min": 350, "xp_per_min": 430, "tower_damage": 100,
    }


def opendota_match():
    return {
        "match_id": 9876543210, "duration": 2200, "radiant_win": False,
        "game_mode": 1, "lobby_type": 7,
        "players": [opendota_player(slot) for slot in list(range(5)) + list(range(128, 133))],
    }


class BotPerformanceTests(unittest.TestCase):
    def test_manual_kp_share_won_and_optional_unknown(self):
        rows = perf.manual_records(manual_match())
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["player_slot"], 0)
        self.assertTrue(row["won"])
        self.assertAlmostEqual(row["kill_participation"], 9 / 20)
        self.assertAlmostEqual(row["hero_damage_share"], .2)
        self.assertIsNone(row["hero_healing"])
        self.assertEqual(row["position"], 3)

    def test_kp_undefined_for_team_zero_kills(self):
        match = manual_match(team_kills=0)
        match["players"][0]["kills"] = 0
        match["players"][0]["assists"] = 0
        row = perf.manual_records(match)[0]
        self.assertIsNone(row["kill_participation"])

    def test_partial_roster_does_not_guess_damage_or_team_kills(self):
        match = manual_match()
        del match["team_kills"]
        del match["team_hero_damage"]
        row = perf.manual_records(match)[0]
        self.assertIsNone(row["team_kills"])
        self.assertIsNone(row["kill_participation"])
        self.assertIsNone(row["hero_damage_share"])

    def test_requires_explicit_oha_selection_not_every_ai(self):
        match = manual_match()
        del match["players"][0]["is_oha_bot"]
        with self.assertRaisesRegex(perf.DataError, "is_oha_bot"):
            perf.manual_records(match)

    def test_manual_rejects_missing_kda_and_negative(self):
        match = manual_match()
        del match["players"][0]["assists"]
        with self.assertRaisesRegex(perf.DataError, "kills/deaths/assists"):
            perf.manual_records(match)
        match = manual_match()
        match["players"][0]["kills"] = -2
        with self.assertRaisesRegex(perf.DataError, "nonnegative"):
            perf.manual_records(match)

    def test_manual_rejects_duplicate_player_slot(self):
        match = manual_match()
        match["players"].append(hero(0))
        with self.assertRaisesRegex(perf.DataError, "duplicate"):
            perf.manual_records(match)

    def test_open_dota_full_roster_team_kp_damage_share(self):
        match = opendota_match()
        meta = {"patch": "7.42", "bot_build": "abc123",
                "difficulty": "standard", "opponent_profile": "test"}
        rows = perf.opendota_records(match, {0}, None, meta, {0: 1},
                                    {"100": "npc_dota_hero_antimage"})
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["hero"], "npc_dota_hero_antimage")
        self.assertEqual(row["team_kills"], 11)
        self.assertAlmostEqual(row["hero_damage_share"], .2)
        self.assertAlmostEqual(row["kill_participation"], 9 / 11)
        self.assertFalse(row["won"])
        self.assertEqual(row["position"], 1)

    def test_unknown_open_dota_hero_id_and_role_are_explicit(self):
        rows = perf.opendota_records(opendota_match(), {128}, None,
                    {"patch": "unknown", "bot_build": "x", "difficulty": "unknown", "opponent_profile": "unknown"},
                    {}, {})
        self.assertEqual(rows[0]["hero"], "hero_id:228")
        self.assertIsNone(rows[0]["position"])
        self.assertTrue(perf.summary(rows)["unknown_context"])

    def test_open_dota_player_data_is_not_automatically_classified_as_oha(self):
        with tempfile.TemporaryDirectory() as td:
            input_path = Path(td) / "input.json"
            input_path.write_text(json.dumps(opendota_match()), encoding="utf-8")
            self.assertEqual(perf.cli([
                "ingest", "--format", "opendota", "--input", str(input_path),
                "--out", str(Path(td) / "data.jsonl")
            ]), 2)

    def test_manual_does_not_store_names_accounts_or_chat(self):
        match = manual_match()
        match["players"][0].update({"account_id": 12345, "name": "private", "chat": "secret"})
        payload = json.dumps(perf.manual_records(match))
        self.assertNotIn("private", payload)
        self.assertNotIn("12345", payload)
        self.assertNotIn("secret", payload)

    def test_dataset_idempotent_and_refuses_conflict(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "stats.jsonl"
            rows = perf.manual_records(manual_match())
            self.assertEqual(perf.append_dataset(path, rows), (1, 1))
            self.assertEqual(perf.append_dataset(path, rows), (0, 1))
            modified = [dict(rows[0], kills=100)]
            with self.assertRaisesRegex(perf.DataError, "Conflicting"):
                perf.append_dataset(path, modified)
            self.assertEqual(len(perf.load_dataset(path)), 1)

    def test_wilson_ci_and_kp_missing_samples(self):
        rows = perf.manual_records(manual_match(team_kills=0))
        data = perf.summary(rows)
        self.assertEqual(data["sample_count"], 1)
        self.assertEqual(data["metric_samples"]["kill_participation"], 0)
        self.assertIsNone(data["metrics"]["kill_participation"])
        self.assertEqual(data["zero_team_kill_matches"], 1)
        self.assertEqual(perf.wilson(0, 0), None)
        self.assertAlmostEqual(perf.wilson(20, 20)[1], 1.)

    def test_never_flag_with_small_sample_even_if_very_different(self):
        a = perf.manual_records(manual_match("a", build="base"))[0]
        b = perf.manual_records(manual_match("b", build="candidate"))[0]
        b["won"] = False
        b["kill_participation"] = 0.01
        report = perf.analyze([a, b], "base", "candidate", 30)
        self.assertEqual(len(report["comparisons"]), 1)
        comp = report["comparisons"][0]
        self.assertFalse(comp["eligible"])
        self.assertEqual(comp["review_flags"], [])

    def test_comparison_separates_patch_and_role(self):
        a = perf.manual_records(manual_match("a", build="base"))[0]
        b = perf.manual_records(manual_match("b", patch="7.43", build="candidate"))[0]
        c = perf.manual_records(manual_match("c", build="candidate"))[0]
        c["position"] = 4
        report = perf.analyze([a, b, c], "base", "candidate", 1)
        self.assertEqual(report["comparisons"], [])

    def test_missing_role_never_triggers_comparison(self):
        a = perf.manual_records(manual_match("a", build="base"))[0]
        b = perf.manual_records(manual_match("b", build="candidate"))[0]
        a["position"] = b["position"] = None
        report = perf.analyze([a, b], "base", "candidate", 1)
        self.assertEqual(len(report["comparisons"]), 1)
        self.assertFalse(report["comparisons"][0]["eligible"])

    def test_30v30_baseline_difference_only_flags_review(self):
        rows = []
        for i in range(30):
            a = perf.manual_records(manual_match(f"base-{i}", build="base"))[0]
            b = perf.manual_records(manual_match(f"cand-{i}", build="candidate"))[0]
            b["won"] = False
            b["kill_participation"] = .05
            b["hero_damage"] = 500
            rows.extend([a, b])
        result = perf.analyze(rows, "base", "candidate", 30)
        comparison = result["comparisons"][0]
        self.assertTrue(comparison["eligible"])
        self.assertIn("WIN_RATE_CI_SEPARATION_REVIEW", comparison["review_flags"])
        self.assertIn("KP_DROP_REVIEW", comparison["review_flags"])
        self.assertIn("HERO_DAMAGE_PM_DROP_REVIEW", comparison["review_flags"])
        self.assertIn("not itself a diagnosis", result["limitations"][0])

    def test_markdown_is_descriptive(self):
        rows = perf.manual_records(manual_match())
        report = perf.analyze(rows)
        md = perf.markdown_report(report)
        self.assertIn("OHA Bot performance report", md)
        self.assertIn("npc_dota_hero_axe", md)
        self.assertIn("Only explicit OHA bot slots", md)

    def test_cli_end_to_end_import_and_report_json(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td)
            source = path / "test.json"
            dataset = path / "data.jsonl"
            md = path / "report.md"
            j = path / "report.json"
            source.write_text(json.dumps(manual_match()), encoding="utf-8")
            self.assertEqual(perf.cli(["ingest", "--format", "manual", "--input", str(source),
                                       "--out", str(dataset)]), 0)
            self.assertEqual(perf.cli(["report", "--data", str(dataset),
                                       "--json-out", str(j), "--md-out", str(md)]), 0)
            self.assertEqual(json.loads(j.read_text(encoding="utf-8"))["bot_observations"], 1)
            self.assertIn("Win%", md.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
