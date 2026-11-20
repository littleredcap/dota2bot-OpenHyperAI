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
