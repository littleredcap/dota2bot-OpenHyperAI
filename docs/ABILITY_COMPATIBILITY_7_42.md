# Dota 2 7.42 — Hero Ability Compatibility Audit (P2)

Audit date: **2026-11-20**. Scope: structural compatibility of **127 BotLib/hero_*.lua files** and the main shared spell-name/weight tables. This is a static audit, **not** a claim that all 127 heroes play correctly in a Dota 2 match.

## Ground truth

- Dota 2 7.42: https://www.dota2.com/patches/7.42 (released 2026-11-18)
- Extracted game hero slots: https://github.com/dotabuff/d2vpkr/tree/master/dota/scripts/npc/heroes
- Extracted ability ID registry: https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/npc_ability_ids.txt (blob `f14794e0ce9e153ff9d2b3c38e38ff5b49d75222`)

For each of the 127 hero scripts, inspected literal `GetAbilityByName()` references against that hero's exported `Ability1..AbilityN` slots and separately checked shared named spell tables against the game ability-ID registry. **Names in the global ability-ID registry may remain for removed/conditional spells; membership alone does NOT mean the ability is currently attached to a given hero.** Extra references were treated as review candidates, not automatic failures. Heroes using `sAbilityList` or dynamic spell/shape swapping require additional validation.

## Confirmed safe fixes applied

| Area | Patch | Rationale |
|---|---|---|
| Clinkz (`BotLib/hero_clinkz.lua`) | Guard missing Tar Bomb / Burning Barrage handles | Tar Bomb is not a normal 7.42 hero slot; an unguarded `:IsFullyCastable()` on nil could terminate the think callback |
| Clinkz | Check Burning Army's own trainability/castability, not Burning Barrage's | Corrects an independent cross-ability gating error |
| Chen (`BotLib/hero_chen.lua`) | Guard optional `chen_summon_convert` before `:IsFullyCastable()` | No matching current default hero slot; avoid a nil dereference |
| Grimstroke (`BotLib/hero_grimstroke.lua`) | Guard optional `grimstroke_return` before `:IsHidden()` | No matching current default hero slot; avoid a nil dereference |
| Beastmaster (`BotLib/hero_beastmaster.lua`) | Resolve `beastmaster_summon_razorback` and `beastmaster_summon_raptor` by current exact names | Exported hero ability names; avoids reliance on stale aliases or filtered slot indexes |
| Shared spell weights (`FunLib/spell_list.lua`) | Rename old Razorback, Raptor and Pangolier Lucky Shot keys | The canonical keys in exported game data are `beastmaster_summon_razorback`, `beastmaster_summon_raptor`, `pangolier_lucky_shot` |
| TS/Lua spell probabilities (`typescript/bots/FunLib/spell_prob_list.ts` and `bots/FunLib/spell_prob_list.lua`) | Update both Beastmaster spell keys in source **and** generated output | Keep build output consistent with TypeScript source; a future `npm run build:lua` must not restore old names |

Selected commits:
- Clinkz: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/2f63787457250ad34cef276c8ce407170dd93167
- Grimstroke: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/9b13f7b2c768dee19e7150828640b5713fa6faf4
- Chen: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/523521434f31e31d2ac60908e75e2dc588a4ec73
- Beastmaster Razorback: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/4cc774399952b3a6ccaa6cdba79a7133318f29ba
- Shared spell list: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/7ec31546034a53e6373cc1a6effa7f0958a51602
- TS/Lua probabilities: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/07c95432090b65f1c02f976c78d33258f6daef92 and https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/99c0053b74b266833e78daa6b811bec3a81eb6b8

## Review findings NOT yet eligible for a speculative change

- **Hero-specific legacy references**: old names still appear in some scripts (e.g. Morphling's strength Adaptive Strike, Tinker's Defense Matrix fallback, OD's Essence Aura, Marci's Guardian, Faceless Void's old Time Zone). Some are optional abilities, dynamically acquired spells, commented code, or defensive fallbacks. Absence from the hero's default slot list is not proof that every reference should be deleted.
- **Changed/new abilities with no existing bot strategy**: canonical name mapping does not implement tactical use of new mechanics (e.g. Beastmaster's Thunderhide, Chen's Zealot, some changed hero innate abilities). These require inspecting actual skill behavior, target restrictions, and game testing.
- **Tinker**: regular casting path uses current Deploy Turrets and can guard missing abilities; the file also contains legacy `HeatSeekingMissile` code in a dormant combo helper. Do not revive or replace the combo without checking the entire caller chain.
- **Rubick / Morphling / Invoker / Meepo / Kez / Largo**: special stolen, summoned, transformed, invoked, and stance/song skills are not reliably audited by comparing only default hero slots; they require dynamic runtime coverage.
- **Talent swaps, exact cast target changes, and ability special-value keys** have not been exhaustively verified against 7.42 patch notes and in-game behavior. This phase focuses on name/slot safety and obviously invalid call sites, not global tactical changes.
- A separate change to `hero_meepo.lua` already exists in the branch (removal of MegaMeepo handling). It was *not part of the direct P2 edits documented here* and should be separately validated if needed.

## Verification and limitations

Static GitHub readback verified that:
- Clinkz, Chen and Grimstroke now guard the potentially absent handles.
- Beastmaster uses the canonical Raptor and Razorback names.
- `spell_list.lua` no longer uses the globally unregistered old Razorback and Lucky Shot keys.
- TypeScript probability keys match the committed generated Lua keys.
- `bots/BotLib/hero_undying.lua` still has **no default Aghanim's Shard purchase**; Zombie Bite remains intentionally deferred.

**No local Lua build, syntax-checking toolchain, or Dota 2 runtime execution was performed during this P2 review.** Individual structural fixes need in-game verification. This is not a complete gameplay or regression certification.

## Next scoped work

1. Run a deterministic Lua compile/syntax pass (`luac -p` for hand-written Lua plus TS build) and verify that generated files do not drift.
2. Test the affected optional-ability paths in a 7.42 local-host lobby; detect nil references in runtime logs without prematurely altering strategy.
3. Triage specific patch-note *structural* changes (targeting type, new/removed abilities, innate transitions, talent swaps) in `docs/PATCH_UPDATE_GUIDE.md` order.
4. Keep Undying Zombie Bite and its shard-purchase strategy on hold pending mature community guidance and separate evaluation.

## 7.42 structural follow-up — 2026-11-20

Follow-up scope: confirmed **cast-target API changes**, **explicit talent-side swaps**, and **innate ability skill-build changes**. Verified against the 7.42 patch description plus current game hero slot data. This section extends, but does not supersede, the initial name/slot audit above.

### Confirmed fixes

| Hero | Root cause | Minimal correction |
|---|---|---|
| Weaver (`hero_weaver.lua`) | The 7.42 Aghanim's Scepter ally-targeted Time Lapse moved to a separate `weaver_time_lapse_ally` ability. The old bot targeted allies through the self-only `weaver_time_lapse` and read its cast range. | Refresh ally ability handle after Scepter purchase, check unlock/castability, cast that handle on allied heroes, and use its actual cast range. Keep self Time Lapse as the existing no-target action. |
| Abaddon (`hero_abaddon.lua`) | Level 15 talent choices swapped left/right in 7.42; old preferred side could now choose the opposite talent. | Invert the level 15 preference from right to left while preserving other levels. Some talents were replaced in the patch, so this does not promise identical pre-patch effects. |
| Beastmaster (`hero_beastmaster.lua`) | Since 7.41, `beastmaster_inner_beast` is innate (not learnable), but two item-independent level-up lists still contained four index-4 entries instead of training `beastmaster_summon_raptor` (index 3). | Replace only those four index-4 entries with index 3 in both builds. Each build now contains four points in each learnable basic (1/2/3) and three ult points (6). Preserve position-specific ordering. |
| Meepo (`hero_meepo.lua`) | 7.42 moved Dig (`meepo_petrify`) to an Aghanim's Scepter grant. If no handle exists yet, `Dig:IsTrained()` would dereference nil. | Guard nil before calling `IsTrained()` / `IsFullyCastable()`. The separate Shard Fling mechanic is not implemented by this change. |

Commits:
- Weaver: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/60560c30d3f53095704ad7b311b12182e014e6ac
- Abaddon: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/a773dab8afec618834b606968b40458433e80823
- Beastmaster skill builds: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/14adf879542b51c7ce645dae60b6321b3c4e9a70
- Meepo Dig: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/6be9891f4ba426ebe8aaacc09f5ee886c2b5b16e

### Findings intentionally not modified

- **Chen (7.42 Zealot)**: new active resurrection on an innate and a new Holy Persuasion self-cast are available, but the existing bot has no verified logic to decide when to activate them. Existing creep-targeting remains valid.
- **Beastmaster (Summon Ancient Thunderhide)**: Aghanim's Scepter now grants a new no-target summon. Purchase plans and summoning/creep control behavior require a separate tactical review; it was not introduced as an untested auto-cast in this structural patch.
- **Meepo (Divided We Stand + Shard)**: Fling/pickup has nontrivial unit targeting and effects. This change only protects Dig and does not attempt to build a new Fling combo.
- **Dazzle (Through the Realm)**: new Shard sub-ability has no validated action conditions; not automatically cast.
- **Pugna (Oblivion Savant)**: Scepter upgrade reworked into charges. Existing spell actions remain; charge-aware repeat-casting is a new behavior and requires targeted tests.
- **Other talent replacements/moves**: changes in effect/level are not automatically equivalent to swapping sides. No blanket rewrites of preferred talents or item builds were done.
- **Innate handling in `FunLib/aba_skill.lua`**: the global dynamic slot filter should be validated with visible non-learnable innates before changing it across 127 heroes. The Beastmaster fix is targeted and does not mutate the shared loader.
- **Undying**: Zombie Bite remains deferred, and `item_aghanims_shard` remains absent from the default Undying builds.

### Verification limits

GitHub file readback and static comparisons were used. **No `luac` compile, TS build, bot match, or actual Dota 2 runtime execution occurred**. The four targeted fixes address known incompatibilities, but this is not a blanket guarantee that all 7.42 hero abilities are compatible.

## Deferred Aghanim purchases and base-skill follow-up

Policy adopted 2026-11-20: do **not** automatically purchase Scepter or Shard upgrades whose new/reworked behavior has not yet been evaluated. See [AGHANIMS_DEFERRED_7_42.md](AGHANIMS_DEFERRED_7_42.md) for the full by-hero list, restoration criteria, default-build limits, and check command.

- 13 heroes temporarily defer Scepter/Blessing; 7 heroes (including Undying, which was already deferred earlier) temporarily defer Shard. The purchase-edit passes removed 22 Scepters, 41 Blessings, and 21 Shards from 17 unique hero files; Undying's earlier removal is not included in that count.
- Abaddon Shard is additionally deferred: 7.39 moved its upgrade to Aphotic Shield, while the script still modeled the obsolete Mist Coil pure-attack effect. The outdated kill estimate was removed; Shard purchase remains on hold pending further review.
- Leshrac is additionally deferred: its 7.42 Scepter-granted Nihilism was reworked into a disarm/continuous dispel and requires a new use-case review. The optional handler also received a nil guard. The list now covers **13 Scepter** and **7 Shard** heroes, including Undying.
- `npm run check:deferred-aghanims` ensures none of those forbidden upgrades re-enter the specified **default** buy lists. `npm run build` now executes the check before the TypeScript-to-Lua compilation step.
- Existing code for Weaver ally Time Lapse and Meepo Dig remains available for later validation but their new Scepter purchases are deferred; no unverified new upgrade spells have been enabled as a consequence of this policy.
- Medusa `hero_medusa.lua`: Gorgon's Grasp was changed from **physical to magical** damage in 7.42. Updated `CanKillTarget` in `ConsiderGorgonGrasp()` from `DAMAGE_TYPE_PHYSICAL` to `DAMAGE_TYPE_MAGICAL`, preserving the rest of the cast logic. Commit: https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/037d35111bfbe9ba9a9adf0e8443304e5ec1f391

All stated checks are **static readback and JavaScript syntax validation**, not a completed Dota 2 match test or a full local `npm run build`. Remaining structural compatibility work excludes speculative automatic use of newly granted Scepter/Shard abilities.

## 逐项施法条件复核

见 [7.42 技能接入检查](CAST_CONDITIONS_7_42.md)。该表区分补丁和 KV 证据、离线回归以及尚未执行的客户端测试。
