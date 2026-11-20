# Dota 2 7.42 — Item Compatibility Audit

Audit date: 2026-11-20. Scope: **item compatibility**, not the full 7.42 hero/ability patch or a new item-build meta.

## Sources

- Valve patch: https://www.dota2.com/patches/7.42
- Game shop: https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/shops.txt (snapshot blob `9c181b073fce427ec0a3d8cf5aae8e4ba966d417`)
- Game artifacts/enchantments: https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/neutral_items.txt (snapshot blob `e9aea38841f017653bd102c323b443f3c8ed9746`)
- Game item KV: https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/items.txt (snapshot blob `295eec34b7913103c6e129437022dbf8b98af306`)

## Reviewed and changed

1. Scanned the 127 hero builds in `bots/BotLib/hero_*.lua`, checking internal purchase IDs against current shop names, supported upgrade IDs, and project-defined virtual outfits/bundles.
2. Removed the deprecated `item_helm_of_the_overlord` default purchase from Beastmaster Pos 3 and Lycan Pos 3 (the latter build is shared by Pos 4/5). Retained `item_helm_of_the_dominator`; no speculative replacement purchase.
3. Removed 10 `item_angels_demise` purchases (the internal name for removed **Khanda**) from Bounty Hunter, Luna, Morphling, Tinker, and Zeus; removed its component registration.
4. Removed invalid `item_great_scepter` from Tidehunter Pos 1; its normal `item_ultimate_scepter` entry remains.
5. Removed obsolete shop registry entries/recipe handlers for Javelin, Helm of the Overlord, and Revenant's Brooch. Revenant's Brooch is now a Tier 3 **passive** artifact; its old active-use handler was deleted.
6. Heaven's Halberd now reads the item's cast range dynamically instead of assuming the old fixed range. Recipes for reworked purchasable upgrades continue to use the Dota `GetItemComponents()` API.
7. Registered the six purchasable 7.42 additions in `FunLib/aba_item.lua`: `item_bloodslinger`, `item_caduceus`, `item_ristuls_devotion`, `item_berserkers_sabatons`, `item_skypiercer`, `item_starforge`. **Not** inserted into hero purchase lists; their active-use strategies are not yet implemented.
8. Removed the obsolete Tome of Knowledge from the **basic purchasable-items list**. Its name may still appear in historical debug references; these are not hero purchases.
9. Updated **both** `Buff/NeutralItems.lua` and `FretBots/SettingsNeutralItemTable.lua` to match the four-tier 7.42 neutral system: 12 artifacts in each tier (48 total) and 6/10/10/8 allowed enhancement names (34 tier+enhancement entries). Existing FretBots role weights were preserved; newly eligible artifacts use neutral role weights.
10. Removed the obsolete Tier 5 distribution in Buff mode. Buff normal timing is 0/15/30/50 minutes, Turbo timing remains half that schedule.
11. `FretBots/SettingsDefault.lua` now uses four tiers: default game timings 0/15/30/50 minutes; enhanced baseline timing 0/5/20/50 minutes to preserve its former roughly 10-minute Tier 2/3 timing advantage. FretBots' separate difficulty mechanism remains intact.
12. In `FretBots/NeutralItems.lua`, exhausted role-specific selection now falls back to the valid remaining tier pool, with a final guard against `math.random(0)`.

## Review boundaries / follow-up

- **No in-game test was run.** Lua file consistency and source tables were checked by static readback, but only a real match can establish that neutral creation, enhancement slots, purchasing, and modified item actions work end-to-end.
- Buff and FretBots continue to **grant neutral items programmatically** using their established difficulty-mode behavior. This is not a full implementation of the vanilla 7.42 Madstone crafting interface or the game's four match-specific offered artifacts per tier.
- New active neutral artifacts (notably `item_red_ledger` and `item_brick`) are present in the valid pools but do not yet have dedicated item-use `ConsiderItemDesire` handlers. Do not assume their actives are used.
- Newly registered shop items are not recommended for default hero builds until their purchase strategy and active-use logic are reviewed.
- Existing item handlers beyond the confirmed 7.42 structural changes have not been comprehensively gameplay-tested.
- **Undying's Zombie Bite / Aghanim's Shard remains intentionally deferred**. Do not restore the shard to its default builds without a separate evaluation of behavior, targets, opportunity cost, and community guidance.
- This is an item-specific audit. `docs/PATCH_UPDATE_GUIDE.md` remains the canonical checklist for broader hero, ability, map, and patch maintenance.

## Verification summary

Source readback checked that both neutral systems contain exactly the 48 current artifacts with matching tiers and the 34 supported tier+enhancement entries, that no active Tier 5 neutral list is retained, and that the known removed default purchase entries have been removed. The results are **static checks, not successful runtime tests**.

## Beastmaster farm milestone follow-up

Beastmaster's role build already retained Helm of the Dominator, but the hero-specific farming rule still waited for the removed Helm of the Overlord. The farming rule now checks Dominator under the existing 14,000 net-worth threshold and leaves the separate BKB threshold (18,000) unchanged. No item purchases, team logic or shared farming fallbacks were changed.

`lua5.1 tests/test_7_42_beastmaster_farm.lua` loads the generated gameplay module and covers both item checks plus their exact threshold boundaries. This verifies the item milestone, not whether Beastmaster should fight in every such game state.

### FretBots neutral timer in mixed human/Bot lobbies

A team with fewer than five Bots can finish all four tiers without filling the team's award cap. The finding timer now stops when the initialized Bot roster has no pending tiers, as well as when the original caps are satisfied. Future award times and incomplete Bot state still wait; per-tier award caps and tier-closing rules are unchanged. Regression fixtures exercise 5v5 and 4v5 Bot allocations and distinguish waiting from completion. In-game inventory delivery, including full slots, remains a separate validation item.
