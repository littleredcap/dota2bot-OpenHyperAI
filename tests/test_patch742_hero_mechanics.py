"""7.42 follow-on hero audit: evidence only, NOT client ability tests.

Each test asserts what the unchanged OHA source still does and tracks the
unimplemented strategy, never claims that a new action works in Dota 2.
"""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from patch742_audit import strip_lua_comments

KV_SHA = "77a6ccca87bab183caaf0c09fd2813f2695b7a5b"


def source(path):
    return strip_lua_comments((ROOT / path).read_text(encoding="utf-8"))


def between(text, start, end):
    a = text.find(start)
    if a < 0:
        raise AssertionError("Missing source region: " + start)
    b = text.find(end, a + len(start))
    if b < 0:
        raise AssertionError("Missing source end: " + end)
    return text[a:b]


class Patch742HeroMechanicsTests(unittest.TestCase):
    def test_document_is_analysis_not_finished_strategy(self):
        doc = (ROOT / "docs/PATCH742_HERO_MECHANICS_DEEP_DIVE.md").read_text(encoding="utf-8")
        for token in (
            "C742-17", "C742-18", "C742-19", "C742-20", "C742-21",
            "C742-19-BUY", "C742-17-GUARD",
            "lone_druid_spirit_bear_summon_druid", KV_SHA
        ):
            self.assertIn(token, doc)
        self.assertIn("没有游戏客户端测试", doc)
        self.assertIn("正向待测", doc)
        self.assertIn("反向待测", doc)

    def test_dazzle_new_shard_active_is_missing_and_old_projection_remains(self):
        s = source("bots/BotLib/hero_dazzle.lua")
        self.assertNotIn("dazzle_through_the_realm", s)
        self.assertIn('GetAbilityByName("dazzle_nothl_projection")', s)
        self.assertIn('GetAbilityByName("dazzle_nothl_projection_end")', s)
        self.assertIn("function X.ConsiderNothlProjection()", s)
        self.assertIn("function X.ConsiderNothlProjectionEnd()", s)

    def test_dazzle_stale_body_validity_guard_is_a_separate_risk(self):
        s = source("bots/BotLib/hero_dazzle.lua")
        region = between(s, "function X.ConsiderNothlProjectionEnd()", "function X.ConsiderR()")
        self.assertIn("local _bot = J.Utils.GameStates.dazzleNothl[bot:GetPlayerID()].body", region)
        self.assertIn("if J.IsValid(bot) then", region)
        self.assertIn("J.IsRetreating( _bot )", region)

    def test_undying_bite_not_executed_but_default_shard_is_purchased(self):
        s = source("bots/BotLib/hero_undying.lua")
        self.assertNotIn("undying_bite", s)
        self.assertIn("X['bDeafaultAbility'] = false", s)
        for role in ("pos_1", "pos_3", "pos_4"):
            block = between(s, "sRoleItemsBuyList['" + role + "'] = {", "\n}")
            self.assertIn('"item_aghanims_shard"', block)
        self.assertIn("sRoleItemsBuyList['pos_2'] = sRoleItemsBuyList['pos_1']", s)
        pos5 = between(s, "sRoleItemsBuyList['pos_5'] = {", "\n}")
        self.assertNotIn('"item_aghanims_shard"', pos5)

    def test_spirit_bear_new_ability_is_on_bear_and_absent_from_logic(self):
        s = source("bots/BotLib/hero_lone_druid_bear.lua")
        self.assertIn("local bear = GetBot()", s)
        self.assertIn("bear:GetAbilityByName('lone_druid_savage_roar_bear')", s)
        self.assertIn("function X.SkillsComplement()", s)
        self.assertNotIn("lone_druid_spirit_bear_summon_druid", s)
        self.assertIn("sRoleItemsBuyList['pos_1'] = { }", s)
        self.assertIn("if not Utils.GetLoneDruid(bear).hero:IsAlive() then return 0 end", s)
        data = json.loads((ROOT / "docs/patch742_change_impacts.json").read_text(encoding="utf-8"))
        rule = next(x for x in data["rules"] if x["id"] == "C742-18")
        self.assertEqual(rule["needle"], "lone_druid_spirit_bear_summon_druid")
        self.assertEqual(rule["classification"], "NEW_CAPABILITY_GAP")
        self.assertIn(KV_SHA, rule["source_kv"])
        self.assertIn("npc_units.txt", rule["source_kv"])

    def test_pugna_scepter_innate_is_not_an_active_cast_and_channel_guard_blocks(self):
        s = source("bots/BotLib/hero_pugna.lua")
        self.assertNotIn("Action_UseAbility(pugna_oblivion_savant)", s)
        self.assertNotIn("GetAbilityByName('pugna_oblivion_savant')", s)
        self.assertIn("abilityR:IsFullyCastable()", s)
        self.assertIn("J.CanNotUseAbility( bot )", s)
        shared = source("bots/FunLib/jmz_func.lua")
        check = between(shared, "function J.CanNotUseAbility( bot )", "end")
        self.assertIn("bot:IsChanneling()", check)

    def test_death_prophet_original_cast_and_immune_target_filters_are_still_present(self):
        s = source("bots/BotLib/hero_death_prophet.lua")
        q = between(s, "function X.ConsiderQ()", "function X.ConsiderW()")
        e = between(s, "function X.ConsiderE()", "function X.ConsiderR()")
        self.assertIn("abilityQ:IsFullyCastable()", q)
        self.assertIn("function X.ConsiderE()", e)
        self.assertIn("J.CanCastOnNonMagicImmune", e)
        self.assertIn("modifier_death_prophet_spirit_siphon_slow", e)

    def test_dota_742_mechanics_snapshot_is_not_inference_from_old_lua(self):
        doc = (ROOT / "docs/PATCH742_HERO_MECHANICS_DEEP_DIVE.md").read_text(encoding="utf-8")
        self.assertIn("dazzle_through_the_realm", doc)
        self.assertIn("undying_bite", doc)
        self.assertIn("pugna_oblivion_savant", doc)
        self.assertIn("Spirit Siphon", doc)
        self.assertIn("128", (ROOT / "docs/PATCH742_CHANGE_IMPACT.md").read_text(encoding="utf-8"))

    def test_missing_new_skill_does_not_magically_mean_a_client_error(self):
        data = json.loads((ROOT / "docs/patch742_change_impacts.json").read_text(encoding="utf-8"))
        for id_ in ("C742-17", "C742-18", "C742-19"):
            row = next(x for x in data["rules"] if x["id"] == id_)
            self.assertEqual(row["classification"], "NEW_CAPABILITY_GAP")
            self.assertIsNotNone(row["client_gate"])
        self.assertNotIn("STRATEGY_VALIDATED",
                         (ROOT / "docs/PATCH742_HERO_MECHANICS_DEEP_DIVE.md").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
