"""Documentation status validation should fail on accidental false completion claims."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from check_issue_status import parse_register, pr_is_indexed, PR_LINK, ROW_ID

ROW = ("| GH-155 | 物品循环 | MIN_FIX_DRAFT | OFFLINE_PASS | OLD | "
       "防止反复拾取 | 仍需客户端以及背包优先级优化 | "
       "[PR #7](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/7) |")


class IssueRegisterTests(unittest.TestCase):
    def test_current_54_plus_entries_pass(self):
        root = Path(__file__).resolve().parents[1]
        rows, errors = parse_register(
            (root / "docs/ISSUE_AND_REQUIREMENT_STATUS.md").read_text(encoding="utf-8")
        )
        self.assertEqual(errors, [])
        self.assertGreaterEqual(len(rows), 54)
        self.assertTrue(any(r["id"] == "U-14" for r in rows))
        self.assertTrue(any(r["id"] == "D-23" for r in rows))
        self.assertTrue(any(r["id"] == "C742-10" and r["strategy"] == "TODO" for r in rows))
        self.assertTrue(any(r["id"] == "GH-170" and r["strategy"] == "PARTIAL" for r in rows))
        self.assertTrue(any(r["id"] == "C742-07" and r["strategy"] == "OLD" for r in rows))
        self.assertFalse(any(r["verification"] in ("CLIENT_PASS", "MATCH_PASS") for r in rows))
        self.assertFalse(any(r["implementation"] == "MERGED" for r in rows))

    def test_invalid_work_status_is_rejected(self):
        _, errors = parse_register(ROW.replace("MIN_FIX_DRAFT", "FIXED_ALL_DONE"))
        self.assertTrue(any("unsupported implementation" in err for err in errors))

    def test_minimal_fix_requires_a_future_action(self):
        _, errors = parse_register(ROW.replace("仍需客户端以及背包优先级优化", "—"))
        self.assertTrue(any("future action required" in err for err in errors))

    def test_incomplete_strategy_never_claims_full_maturity(self):
        _, errors = parse_register(ROW.replace("OLD", "STRATEGY_VALIDATED"))
        self.assertTrue(any("requires actual match evidence" in err for err in errors))

    def test_unlinked_draft_cannot_claim_ci(self):
        _, errors = parse_register(ROW.replace(
            "[PR #7](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/7)", "—"))
        self.assertTrue(any("concrete PR link" in err for err in errors))

    def test_duplicate_stable_ids_are_rejected(self):
        _, errors = parse_register(ROW + "\n" + ROW)
        self.assertTrue(any("duplicate ID GH-155" in err for err in errors))

    def test_pr_review_gate_requires_explicit_issue_link(self):
        root = Path(__file__).resolve().parents[1]
        rows, errors = parse_register(
            (root / "docs/ISSUE_AND_REQUIREMENT_STATUS.md").read_text(encoding="utf-8")
        )
        self.assertEqual(errors, [])
        self.assertTrue(pr_is_indexed(rows, 17))
        self.assertTrue(pr_is_indexed(rows, 2))
        self.assertFalse(pr_is_indexed(rows, 9999))

    def test_rule_formats_are_strict(self):
        self.assertIsNotNone(ROW_ID.fullmatch("C742-13"))
        self.assertIsNotNone(ROW_ID.fullmatch("F-01"))
        self.assertIsNotNone(ROW_ID.fullmatch("U-14"))
        self.assertIsNotNone(ROW_ID.fullmatch("D-23"))
        self.assertIsNone(ROW_ID.fullmatch("UNKNOWN-1"))
        self.assertEqual(PR_LINK.findall(ROW), ["7"])


if __name__ == "__main__":
    unittest.main()
