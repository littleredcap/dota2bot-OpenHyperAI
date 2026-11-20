import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from patch742_audit import strip_lua_comments, matching, audit
from patch742_log_triage import analyze


class SourceAudit(unittest.TestCase):
    def test_comments_are_not_live_code(self):
        source = """-- item_helm_of_the_overlord
--[[ meepo_megameepo ]]
local s = 'hello -- world'
bot:ActionQueue_UseAbility(CurseOfTheOldGrowth)
"""
        live = strip_lua_comments(source)
        self.assertNotIn("item_helm_of_the_overlord", live)
        self.assertNotIn("meepo_megameepo", live)
        self.assertIn("'hello -- world'", live)
        self.assertIn("ActionQueue_UseAbility", live)

    def test_present_absent_fingerprints(self):
        self.assertTrue(matching("print('foo')", {"check":"absent", "needle":"armageddon"}))
        self.assertFalse(matching("print('armageddon')", {"check":"absent", "needle":"armageddon"}))
        self.assertFalse(matching("-- old ability", {"check":"present","needle":"old ability"}))

    def test_inventory_is_not_a_compatibility_certification(self):
        root = Path(__file__).resolve().parents[1]
        result = audit(root)
        self.assertEqual(result["problems"], [])
        self.assertGreaterEqual(result["hero_file_count"], 120)
        self.assertGreater(result["counts"]["UNREVIEWED"], 0)
        self.assertEqual(result["hero_file_count"], sum(result["counts"].values()))
        self.assertGreater(result["checked_rules"], 0)
        self.assertIn("UNREVIEWED != compatible", result["note"])


class ConsoleScreening(unittest.TestCase):
    def test_runtime_errors_and_decision_reasons(self):
        result = analyze([
            "random line\n",
            "[VScript] Script Runtime Error: attempt to index a nil value\n",
            "[OHA_DECISION] pid=1 hero=abc system=ABILITY action=q verdict=STATUS reason=READY\n",
            "[OHA_DECISION] pid=1 hero=abc system=BANISH verdict=BLOCK reason=ALLIED_FOCUS_2PLUS\n",
            "Failed to find scripts/vscripts/bots/fretbots.lua\n",
        ])
        self.assertEqual(result["errors"]["VScript_error"], 1)
        self.assertEqual(result["errors"]["nil_call_or_index"], 1)
        self.assertEqual(result["errors"]["missing_script"], 1)
        self.assertEqual(result["decision_events"], 2)
        self.assertEqual(len(result["decision_reasons"]), 2)
        self.assertIn("not evidence of missed casts", result["limitations"])

    def test_empty_log_does_not_imply_valid_ai(self):
        result = analyze(["no data\n"])
        self.assertEqual(result["decision_events"], 0)
        self.assertEqual(result["errors"], {})
        self.assertIn("not proof of healthy gameplay", result["limitations"])


if __name__ == "__main__":
    unittest.main()
