"""Regression of the selected 7.42 patch-driven evidence registry."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from patch742_impact import audit, matches, validate_rule, REQUIRED_IDS

ROOT = Path(__file__).resolve().parents[1]


class PatchImpactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = audit(ROOT)

    def test_current_official_patch_evidence_is_reproducible(self):
        self.assertEqual(self.report["problems"], [])
        self.assertEqual(self.report["curated_patch_changes"], len(REQUIRED_IDS))
        self.assertEqual(self.report["hero_files_scanned"], 128)

    def test_confirmed_legacy_weaver_cast_is_not_treated_as_strategy_success(self):
        ids = {r["id"]: r for r in self.report["rules"]}
        self.assertTrue(ids["C742-16"]["fingerprint_matched"])
        self.assertEqual(ids["C742-16"]["classification"], "DIRECT_CONFLICT")
        self.assertIn("not real-client", ids["C742-16"]["note"])

    def test_undying_client_skill_name_matches_pinned_data(self):
        # The actual 7.42 KV calls it undying_bite, not undying_zombie_bite.
        import json
        data = json.loads((ROOT / "docs/patch742_change_impacts.json").read_text())
        record = next(x for x in data["rules"] if x["id"] == "C742-19")
        self.assertEqual(record["needle"], "undying_bite")
        self.assertIn("77a6ccca87bab183caaf0c09fd2813f2695b7a5b", record["source_kv"])
        self.assertEqual(record["classification"], "NEW_CAPABILITY_GAP")

    def test_comments_do_not_make_removed_skill_usage_true(self):
        self.assertFalse(matches("--[[ old_spell ]] \n-- old_spell",
                                 {"needle": "old_spell", "test": "present"}))
        self.assertTrue(matches("-- old_spell", {"needle": "old_spell", "test": "absent"}))
        self.assertTrue(matches("local a = 'old_spell'",
                                {"needle": "old_spell", "test": "present"}))

    def test_missing_new_ability_is_not_classified_as_a_bug(self):
        ids = {r["id"]: r for r in self.report["rules"]}
        for name in ("C742-09", "C742-10-NEW", "C742-17", "C742-18", "C742-19"):
            self.assertEqual(ids[name]["classification"], "NEW_CAPABILITY_GAP")
            self.assertTrue(ids[name]["fingerprint_matched"])
        self.assertIn("NOT a compatibility certificate", self.report["coverage_note"])

    def test_no_old_innate_reference_cannot_imply_compatibility(self):
        ids = {r["id"]: r for r in self.report["rules"]}
        self.assertEqual(ids["C742-22"]["classification"], "NO_LEGACY_REFERENCE")
        self.assertEqual(ids["C742-23"]["classification"], "NO_LEGACY_REFERENCE")
        self.assertTrue(ids["C742-22"]["fingerprint_matched"])
        self.assertTrue(ids["C742-23"]["fingerprint_matched"])

    def test_128_hero_file_removed_item_signature_counts_are_pinned(self):
        actual = self.report["removed_item_active_hero_files"]
        self.assertEqual(actual["item_khanda"], 0)
        self.assertEqual(actual["item_javelin"], 0)
        self.assertEqual(actual["item_helm_of_the_overlord"], 2)

    def test_official_source_and_unfinished_strategy_are_mandatory(self):
        import json
        data = json.loads((ROOT / "docs/patch742_change_impacts.json").read_text())
        rule = dict(data["rules"][0])
        rule.pop("future_strategy")
        with self.assertRaises(ValueError):
            validate_rule(rule, data["official_patch"], data["source_kv_commit"])
        rule = dict(data["rules"][0])
        rule["classification"] = "DIRECT_CONFLICT"
        rule["test"] = "absent"
        with self.assertRaises(ValueError):
            validate_rule(rule, data["official_patch"], data["source_kv_commit"])

    def test_all_existing_legacy_item_references_are_reviewed_not_hidden(self):
        ids={r["id"]:r for r in self.report["rules"]}
        self.assertEqual(ids["C742-14"]["classification"], "SEMANTIC_REVIEW")
        self.assertEqual(ids["C742-15"]["classification"], "DIRECT_CONFLICT")
        self.assertEqual(self.report["problems"], [])


if __name__ == "__main__":
    unittest.main()
