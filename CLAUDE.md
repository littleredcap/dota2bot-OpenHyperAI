# Dota 2 Bot Scripts - Claude Code Guide

## Project Overview

This is the **dota2bot-OpenHyperAI** project -- Lua bot scripts for Dota 2 that run in custom lobbies. Currently supports Patch 7.41/7.41a with 127 heroes.

## Key Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** -- Complete codebase architecture, file map, naming conventions, all systems explained
- **[docs/PATCH_UPDATE_GUIDE.md](docs/PATCH_UPDATE_GUIDE.md)** -- Step-by-step runbook for updating when a new Dota 2 patch drops
- **[docs/OHA_NEXT_ARCHITECTURE.md](docs/OHA_NEXT_ARCHITECTURE.md)** -- OHA-Next target architecture and incremental delivery plan; separate from the existing code map
- **[docs/OHA_NEXT_REQUIREMENTS.md](docs/OHA_NEXT_REQUIREMENTS.md)** -- User requirements, engineering decisions, acceptance criteria and unresolved choices
- **[docs/OHA_NEXT_STRENGTH_OBJECTIVE.md](docs/OHA_NEXT_STRENGTH_OBJECTIVE.md)** -- User-confirmed goal A: maximum fair-play win probability, without resource/vision cheats or humanlike-play constraints
- **[docs/MATCH_DATA_PIPELINE.md](docs/MATCH_DATA_PIPELINE.md)** -- Planned telemetry, data validity, upload and assistant access
- **[docs/UPSTREAM_AND_FORK_WORKFLOW.md](docs/UPSTREAM_AND_FORK_WORKFLOW.md)** -- Branch roles, provenance and risk-based T0–T3 verification

**Read these docs FIRST before making any changes.** They contain everything needed to make targeted updates without scanning the entire repo.

## Common Tasks

### Check for New Patches

To check if there are patches we haven't updated for:
1. Fetch `https://www.dota2.com/datafeed/patchnoteslist?language=english`
2. Compare latest version against "Last updated for" in `docs/PATCH_UPDATE_GUIDE.md`
3. If newer patch exists, follow the update process below

### Patch Update (most common)

When user says "update for patch X.XX" or provides patch notes:

1. Read `docs/PATCH_UPDATE_GUIDE.md` for the step-by-step process
2. Fetch patch data: `https://www.dota2.com/datafeed/patchnotes?version=X.XX&language=english`
3. Fetch d2vpkr data (shops.txt, neutral_items.txt) for authoritative item/ability names
4. **Categorize changes**: STRUCTURAL (need code) vs NUMBER-ONLY (game API handles) vs TALENT SWAPS
5. **Always verify ability names on Liquipedia** -- patch note summaries can be wrong
6. Follow the checklist in order: items -> hero builds -> abilities -> neutrals -> actives -> map changes
7. **Always update TS sources** for any TS-generated Lua files changed (see ARCHITECTURE.md Section 13)

### Add a New Hero

1. Copy a similar existing hero from `bots/BotLib/` as template
2. Add to `FretBots/HeroNames.lua`, `FunLib/aba_hero_roles_map.lua`, `FunLib/spell_list.lua`
3. See "New Heroes" section in `docs/PATCH_UPDATE_GUIDE.md`

### Fix a Hero's Item Build

1. Read `bots/BotLib/hero_[name].lua`
2. Edit the `sRoleItemsBuyList['pos_N']` arrays
3. Items use `item_[internal_name]` format -- check `FunLib/aba_item.lua` for valid names

### Fix a Hero's Ability Logic

1. Read `bots/BotLib/hero_[name].lua`
2. The `SkillsComplement()` function controls ability casting priority
3. Each ability has a `ConsiderX()` function returning desire + target
4. See "Skill / Ability System" in `docs/ARCHITECTURE.md`

## Important Rules

- **Use `GetItemComponents()` for item recipes** -- don't hardcode component arrays
- **Use `sAbilityList[N]` references** when possible -- resilient to ability renames
- **Always update BOTH neutral item files** (Buff/ AND FretBots/)
- **Verify on Liquipedia** before trusting patch note summaries about ability names
- **Verify according to change risk** using the OHA-Next T0–T3 policy. Documentation and isolated tool changes do not require a game. Engine-dependent behavior claims need real game evidence, preferably automated; do not require the owner to manually play every PR. Record missing real-game coverage explicitly, and never equate mock success with stronger gameplay.

## OHA-Next Contribution Boundary

Keep `main` as the upstream mirror and use small PRs targeting `oha-next`; merges remain owner-reviewed. **Optimize for fair-play match-winning ability, not humanlike behavior, inflated GPM/KDA, or unfair resource/vision access.** Distinguish bug evidence from strength evidence; no real-match claims without fair comparisons. `oha-next` is a development integration branch, not an automatic stable-release claim. Read the requirement IDs and architecture boundary relevant to the change, preserve TS/generated-Lua ownership, and update implementation status only with evidence. Match runners, telemetry and artifacts described as planned are not already configured.
