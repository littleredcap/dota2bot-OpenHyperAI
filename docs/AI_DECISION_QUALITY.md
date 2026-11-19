# OHA Bot decision-quality standard (DQ-1)

**Status:** proposed in a Draft PR. **Scope:** every change to mode desire, target selection, skill/item use, and defensive assignment.
No rule can guarantee intelligence in every Dota match; the objective is to make trade-offs explicit, inspectable, and regression-tested.

## 1. Research before changing behavior

Read the project's `docs/ARCHITECTURE.md`, Valve API reference, and both Lua and TypeScript owners of the affected logic. Do not infer game state that Valve intentionally hides (enemy buyback/cooldowns). Use current, visible state and documented APIs.

Independent design references, not drop-in dependencies:
- [adam3q/dota2ai — ability_item_usage_kunkka.lua](https://github.com/adam3q/dota2ai/blob/master/ability_item_usage_kunkka.lua): separates castability, desire, target and timed combo state.
- [edge-blade/Dota-2-AI-Bot-Experiment — ability_item_usage_luna.lua](https://github.com/edge-blade/Dota-2-AI-Bot-Experiment/blob/master/ability_item_usage_luna.lua): context-specific ability decisions (combat / retreat / farm).
- [Passerby/dota2-env — LLM_MATCH.md](https://github.com/Passerby/dota2-env/blob/main/docs/LLM_MATCH.md): optional action histories, structured reason logs and prompt debugging. This is an LLM-driven environment, not the OHA rule-based runtime; borrow observability patterns only.

## 2. Required decision contract

For every new rule or suppression, document:
1. **Intent:** INTERRUPT (interrupt), SAVE_ALLY, PEEL, STOP_ESCAPE, SETUP_COMBO, ISOLATE, NORMAL, DEFEND_BASE, ENDGAME_PUSH.
2. **Inputs and provenance:** visible target, ally attack target, lane state, cooldown (self only), timing, current mode. Explain missing or unreliable signals.
3. **Positive conditions:** when the new action is desirable.
4. **Counterexamples:** when the same action should still happen, or should be suppressed.
5. **Priority:** emergency save / base defense > routine push/farm, but don't suppress unrelated bots' duties.
6. **Fallback:** when confidence is missing, continue normal behavior where safe. Don't force zero desire across unrelated modes.
7. **Scope & rollback:** minimal files, feature default, how to turn diagnostics off.

**Rules must measure intent and opportunity cost**, not solely a hard threshold (e.g. `two allies attacking`, `three teammates nearby`). A proposal can be **BLOCKED** with a reason even when the ability is ready, or **NOT PROPOSED** because no target matched.

## 3. Observability / decision evidence

Optional module: `bots/FunLib/oha_decision_trace.lua`. Configuration: `bots/Customize/decision_trace.lua` (override copy at `game/Customize/decision_trace.lua`). Default is **Enable=false**. Set `Enable=true`, use `WatchHeroes` and `WatchAbilities` / `WatchItems` (or `WatchAllActiveAbilities=true` to sample all active spells of those heroes, including unlearned spells), and start a **Local Host** lobby with developer console/log capture enabled. Keep time, bot ID, target, intent, verdict and reason in one `[OHA_DECISION]` line. Output is rate-limited and contains no chat text or remote calls.

**Cast-gate status:** `system=BOT action=cast_gate` reports `SILENCED`, `STUNNED`, `CHANNELING`, `HEXED`, `USING_ABILITY` or `NO_OBVIOUS_BLOCK` on a sampled tick. `NO_OBVIOUS_BLOCK` does not imply that a candidate target or tactical reason exists. The snapshot is rate-limited to the selected hero only.

**Critical distinction:** `STATUS reason=READY` means the client reported the action castable; it does **not** mean the AI proposed the cast or had a tactical opportunity. `STATUS reason=COOLDOWN` explains why casting was unavailable, but not why a different action was chosen. Only a decision-site `verdict=BLOCK/ALLOW` establishes a specific rule outcome. Logging every spell or every frame is forbidden: sample at intervals and throttle identical reasons. Disable logging for performance-sensitive releases.

Data is observational, not authoritative truth about future projectiles, allies' intended actions, enemy buyback, or damage during the next second. Log `UNKNOWN` where signals are not available.

## 4. Mandatory regression matrix (each change)

| Dimension | Must-have scenario |
|---|---|
| Failure reproduced | Originally reported bad choice is blocked |
| Inverse | A legitimate alternative is still allowed |
| Boundaries | Just above/below HP, distance, duration and ally-count thresholds |
| Missing info | nil, hidden enemy, unlearned ability, cooldown and no mana |
| Priority collision | Two modes want the same bot; one bot must not deprive another of defense |
| Lifecycle | Enemy dies/respawns, target becomes unseen, hero swap, team splits/rejoins |
| Deployment | Pure Lua vs TSTL-generated Lua source is in sync |
| Timing | No one-frame cast spam, same-reason log throttle, objective stickiness |

Prefer tests invoking **production Lua** with Valve mocks and deterministic scenario inputs. String matching only checks wiring and must not replace behavioral assertions. If the behavior crosses `GetDesire()` and `Think()`, include an integration-style mocked mode selection. Explicitly state what only a Dota client can verify.

## 5. Definition of done

- Affected source/producer identified; TS changes rebuilt into Lua and drift-checked.
- Design note lists tradeoffs and counterexamples.
- Positive, negative, boundary, and joint-module regression cases run in CI.
- Logs support **why not cast**, not just cast actions; logs disabled by default.
- No unsupported assumptions about hidden opponent information.
- Draft PR stays Draft until runtime / match review. CI success is not evidence of in-game success.
- Manual validation: stage replay for low HP escape, overlapping ally DPS and crowd control, unseen enemies, team wipe push, enemy buyback, T4/Ancient creep attack, and concurrent other-lane defense.

## 6. Practical diagnostics workflow

1. Reproduce with logging enabled for relevant bots, not all heroes.
2. Search console output for `[OHA_DECISION]`; correlate `STATUS` (cooldown/mana) with `BANISH` (ALLOW/BLOCK) or other decision-site reasons using time and player ID.
3. Check whether the action was proposed. If only READY statuses appear, instrument the **Consider** function; absence of a BANISH log cannot prove the behavior was suppressed.
4. Create a deterministic inverse scenario and an edge-case test for every new reason code.
5. Compare old and new behavior with the same mocks; only then do in-game QA.
6. Return `Enable=false` when finished.

## 7. Current validation limits

The project runs under Valve's bot-script runtime with game-specific behavior. No isolated Lua mock or GitHub Actions run can prove actual TP pathing, ability animation timing, queued projectiles, channel interruption, fog-of-war edge cases, or match win rate. These remain client validation tasks.
