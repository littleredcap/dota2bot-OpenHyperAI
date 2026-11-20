# Dota 2 7.42 — Deferred Aghanim's Scepter / Shard Purchases

Decision: **2026-11-20**. This project intentionally stops **default** purchases of Aghanim upgrades whose new/reworked benefit from 7.41f–7.42 requires further hero-specific review or missing cast/target logic. Restore them only after mature community build guidance, verified ability behavior, and a separate consideration of economic opportunity cost.

This is a **buy-list policy**, not a blanket denial of in-game buffs, Roshan drops, custom hero overrides, or special PvN/AllShadow item presets. Do not replace missing upgrades with speculative items; keep the rest of each position's existing item order.

## Scepter defer list

For every hero below, remove both `item_ultimate_scepter` and `item_ultimate_scepter_2` from **all** default role builds. The latter (Blessing) uses Scepter as a recipe ingredient and would otherwise bypass the deferral.

| Hero script | 7.42 structural reason |
|---|---|
| `abaddon` | Borrowed Time no longer upgraded; Mist Coil now receives AoE/attacks from Scepter |
| `abyssal_underlord` | 7.41f reworked Scepter bonuses; 7.42 Fiend's Gate generates Pit of Malice only at the destination |
| `beastmaster` | New Summon Ancient Thunderhide ability; summon and creep-AI usage pending |
| `death_prophet` | Scepter moved from Exorcism to Spirit Siphon |
| `juggernaut` | Swiftslash removed; Scepter now upgrades Blade Fury |
| `life_stealer` | Scepter Infest targeting/reflection restrictions changed |
| `lone_druid` | New Spirit Bear Summon Lone Druid castable; includes special bear item builds |
| `leshrac` | Scepter-granted Nihilism was reworked into a no-target disarm and dispel; existing usage lacks validation |
| `meepo` | Dig now granted with Scepter instead of Shard |
| `morphling` | Morph Scepter echo/replicant mechanic reworked |
| `pugna` | Oblivion Savant Scepter grants charges and permits recasts |
| `sand_king` | Scepter bonus moved from Epicenter to Burrowstrike |
| `weaver` | Ally Time Lapse moved into separate Scepter-granted castable; its script has a preliminary handler but no runtime validation |

## Shard defer list

Remove `item_aghanims_shard` from default builds for:

| Hero script | 7.42 structural reason |
|---|---|
| `dazzle` | New Through the Realm Nothl Projection sub-ability |
| `death_prophet` | Shard moved to Crypt Swarm with two charges and a new slow |
| `disruptor` | Shard now upgrades Kinetic Field's knockback behavior |
| `meepo` | New pickup and Fling mechanic on Divided We Stand |
| `monkey_king` | Shard changes the Tree Dance / Primal Spring jump's landing-point semantics |
| `undying` | Previously deferred Zombie Bite; remains absent from default builds |

The first five entries were changed during the initial policy pass. Undying was already excluded in `hero_undying.lua` and remains unchanged. Heroes not listed here may still buy their existing Scepter, Blessing, and Shard entries; this is not a blanket ban.

## Implemented changes and safeguards

- Removed **22 direct Scepter**, **41 Blessing** and **16 Shard** entries across **16 hero files** (79 active entries across these passes). The separate prior Undying Shard removal is not counted here.
- Role aliases, such as Juggernaut's shared build, inherit the updated purchase list. Lone Druid's separate `pos_1_w_bear` list was also updated.
- `bots/item_purchase_generic.lua` builds its purchase queue from the hero's `sBuyList`, so removing the upgrades from those default lists prevents the normal queue from buying them.
- Added `scripts/check-deferred-aghanims.js`, exposed as `npm run check:deferred-aghanims`. `npm run build` runs this check before TypeScript-to-Lua generation. The check covers the specified default role build sections and will fail if a deferred purchase is reintroduced.
- Custom `Customize/hero/*` overrides, optional game modes, manual purchases, scripted bonuses, and Aghanim rewards are outside this default-build guard. These may still grant upgrades.

## Restoration criteria

1. Reliable community guidance has converged on the hero upgrade's purpose, relative purchase timing, and common alternative items.
2. For newly granted **active** abilities: verify handle names, behavior flags, cast types, target legality, charge/mana/cooldown interactions, and actual Bot API use. For reworked existing abilities: verify that the bot's priorities still make sense.
3. Validate with game logs and multiple representative matches. Distinguish technical cast success from in-game value.
4. Restore purchases **by hero and position**, not all at once. Remove that hero from the corresponding deferred guard list, update the buy-list(s), and re-run `npm run check:deferred-aghanims` and `npm run build`.
5. Record the reason, patch version, and observed benefit before restoring either the Scepter or its Blessing.

## References

- Valve 7.42: https://www.dota2.com/patches/7.42
- Game item recipes: https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/items.txt
- Previous ability audit: [ABILITY_COMPATIBILITY_7_42.md](ABILITY_COMPATIBILITY_7_42.md)
- Previous item audit: [ITEM_COMPATIBILITY_7_42.md](ITEM_COMPATIBILITY_7_42.md)

**Not a runtime certification:** GitHub readback confirms the selected purchase entries are removed. Bot gameplay and economic outcomes were not tested in this policy pass.
