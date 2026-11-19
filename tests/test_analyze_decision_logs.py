"""Deterministic offline analysis: never infer a missing cast from READY alone."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from analyze_decision_logs import parse_line, summarize

H = "hero=npc_dota_hero_obsidian_destroyer pid=2 t=600"

def line(system, action, verdict, reason, extra=""):
    return f"[OHA_DECISION] {H} system={system} action={action} verdict={verdict} reason={reason} {extra}"

class DecisionLogTests(unittest.TestCase):
    def test_rejects_unrelated_and_truncated_lines(self):
        self.assertIsNone(parse_line("BOT_CHAT hello"))
        self.assertIsNone(parse_line("[OHA_DECISION] system=BOT reason=READY"))

    def test_ready_without_reason_is_a_review_hint_not_a_bug(self):
        rows=[line("ABILITY","obsidian_destroyer_astral_imprisonment","STATUS","READY")]*3
        out=summarize(rows)
        self.assertEqual(out["events"],3)
        self.assertEqual(out["actions"][0]["review"],"READINESS_WITHOUT_DECISION_TRACE")
        self.assertIn("not evidence",out["limitations"])

    def test_block_reason_attaches_to_internal_spell_name(self):
        rows=[
            line("ABILITY","obsidian_destroyer_astral_imprisonment","STATUS","READY"),
            line("BANISH","astral_imprisonment","BLOCK","LOW_HP_ALLIED_DPS","intent=STOP_ESCAPE focus=1"),
            line("BANISH","astral_imprisonment","ALLOW","CHANNEL_INTERRUPT","intent=INTERRUPT"),
        ]
        out=summarize(rows,min_ready_samples=1)
        self.assertEqual(len(out["actions"]),1)
        event=out["actions"][0]
        self.assertEqual(event["status"]["READY"],1)
        self.assertEqual(event["decisions"]["BLOCK"],1)
        self.assertEqual(event["intents"]["STOP_ESCAPE"],1)
        self.assertEqual(event["review"],"NO_AUTOMATIC_FLAG")

    def test_eul_alias_and_bot_gate(self):
        rows=[
            line("ITEM","item_cyclone","STATUS","COOLDOWN"),
            line("BANISH","eul_escape","BLOCK","EXISTING_DISABLE","intent=STOP_ESCAPE"),
            line("BOT","cast_gate","STATUS","SILENCED"),
        ]
        result=summarize(rows)
        self.assertEqual(result["actions"][0]["category"],"ITEM")
        self.assertEqual(result["actions"][0]["action"],"item_cyclone")
        self.assertEqual(result["cast_gates"][0]["status"]["SILENCED"],1)

    def test_policy_no_proposal_and_no_false_cast_confirmation(self):
        rows=[
            line("ABILITY","obsidian_destroyer_astral_imprisonment","STATUS","READY")]*3 + [
            line("BANISH","astral_imprisonment","NO_PROPOSAL","NO_MATCHING_CONSIDER_RULE"),
        ]
        result=summarize(rows)
        self.assertEqual(result["actions"][0]["review"],"READY_WITH_NO_PROPOSAL")
        self.assertIn("not proof",result["limitations"])

if __name__ == "__main__":
    unittest.main()
