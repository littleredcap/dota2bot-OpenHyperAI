# Dota 2 7.42 英雄源码兼容矩阵（离线初筛）

**注意：只完成了全部 hero_*.lua 文件的目录清单和特定高风险变更规则审查；尚未逐个验证官方 7.42 的所有英雄改动。没有被标记的文件为 UNREVIEWED，不是通过。**

- 基线：`cb814c6c8dc51ed08045d6efd9f4a48147992711` (`oha-next`)；2026-11-18 的 [Valve 7.42](https://www.dota2.com/patches/7.42)。
- 共 128 个英雄 Lua 源码文件（含 `hero_lone_druid_bear.lua` 辅助单位文件；不等于正式英雄数量）。
- E2 静态冲突 8 个文件，E1 需核验 5 个文件，其余 115 个文件仍待逐条审计；E2 不代表已实机复现。
- 旧版结构性审计 [PR #3](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3)；Meepo / Overlord [#4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)、Leshrac [#8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8)、Roshan [#6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) 均仍为独立待审核 PR。

| 脚本 | 分类 | 规则编号 | 已知风险或剩余任务 |
| --- | --- | --- | --- |
| `bots/BotLib/hero_abaddon.lua` | E2 | C742-08, C742-08-SHARD | Mist Coil 自伤改生命消耗，旧特殊值与行为要核查；7.42 Shard 已改强化 Aphotic Shield，旧 Mist Coil 仍把 Shard 伤害估算为纯粹伤害；PR #17 |
| `bots/BotLib/hero_abyssal_underlord.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_alchemist.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_ancient_apparition.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_antimage.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_arc_warden.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_axe.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_bane.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_batrider.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_beastmaster.lua` | E2 | C742-02, C742-11 | 包含已删除的 Overlord 默认装备；已有 PR #4；新神杖能力 Ancient Thunderhide 尚未处理；内部名已核对 7.42 Hero KV |
| `bots/BotLib/hero_bloodseeker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_bounty_hunter.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_brewmaster.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_bristleback.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_broodmother.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_centaur.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_chaos_knight.lua` | E1 | C742-09 | 新主动 Armageddon 尚未接入；已核对 7.42 Hero KV，仍需考虑冲锋中断 |
| `bots/BotLib/hero_chen.lua` | E2 | C742-10, C742-10-OLD | 新 Zealot 主动与 Holy Persuasion 召回尚未实现；旧 Summon Convert 见 C742-10-OLD；7.42 Chen 的 Ability4 改为 chen_zealot；旧 Summon Convert 句柄仍被调用；PR #17 |
| `bots/BotLib/hero_clinkz.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_crystal_maiden.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_dark_seer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_dark_willow.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_dawnbreaker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_dazzle.lua` | E1 | C742-17 | Shard 新增 Through the Realm 主动，当前 Dazzle 未考虑；新增技能时机尚待研究 |
| `bots/BotLib/hero_death_prophet.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_disruptor.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_doom_bringer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_dragon_knight.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_drow_ranger.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_earth_spirit.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_earthshaker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_elder_titan.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_ember_spirit.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_enchantress.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_enigma.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_faceless_void.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_furion.lua` | E2 | C742-07 | Oldgrowth 已改被动，旧脚本仍请求主动释放 |
| `bots/BotLib/hero_grimstroke.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_gyrocopter.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_hoodwink.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_huskar.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_invoker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_jakiro.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_juggernaut.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_keeper_of_the_light.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_kez.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_kunkka.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_largo.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_legion_commander.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_leshrac.lua` | E2 | C742-06 | Nihilism 旧弹道自救意图不符合新版效果；已有 PR #8 |
| `bots/BotLib/hero_lich.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_life_stealer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_lina.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_lion.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_lone_druid.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_lone_druid_bear.lua` | E1 | C742-18 | 神杖赋予熊的复活内部 ID 已从 npc_units.txt 确认：lone_druid_spirit_bear_summon_druid；单位独立技能脚本未处理；引擎可用性尚未验证 |
| `bots/BotLib/hero_luna.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_lycan.lua` | E2 | C742-02 | 包含已删除的 Overlord 默认装备；已有 PR #4 |
| `bots/BotLib/hero_magnataur.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_marci.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_mars.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_medusa.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_meepo.lua` | E2 | C742-01 | 旧 MegaMeepo 技能被删除，仍有旧句柄；已有 PR #4 |
| `bots/BotLib/hero_mirana.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_monkey_king.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_morphling.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_muerta.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_naga_siren.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_necrolyte.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_nevermore.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_night_stalker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_nyx_assassin.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_obsidian_destroyer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_ogre_magi.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_omniknight.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_oracle.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_pangolier.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_phantom_assassin.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_phantom_lancer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_phoenix.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_primal_beast.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_puck.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_pudge.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_pugna.lua` | E1 | C742-20 | Oblivion Savant 的 Scepter 冷却再施法重做；现有脚本未显式感知其充能，待语义核验（不等于必须主动施放被动） |
| `bots/BotLib/hero_queenofpain.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_rattletrap.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_razor.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_riki.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_ringmaster.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_rubick.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_sand_king.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_shadow_demon.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_shadow_shaman.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_shredder.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_silencer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_skeleton_king.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_skywrath_mage.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_slardar.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_slark.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_snapfire.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_sniper.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_spectre.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_spirit_breaker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_storm_spirit.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_sven.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_techies.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_templar_assassin.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_terrorblade.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_tidehunter.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_tinker.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_tiny.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_treant.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_troll_warlord.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_tusk.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_undying.lua` | E1 | C742-19 | 7.42 Shard 新增 Zombie Bite 主动，7.42 Hero KV 中技能内部名为 undying_bite；当前未接入 |
| `bots/BotLib/hero_ursa.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_vengefulspirit.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_venomancer.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_viper.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_visage.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_void_spirit.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_warlock.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_weaver.lua` | E2 | C742-16 | 7.42 Scepter Time Lapse (Ally) 是独立技能；原逻辑仍以无目标自身回溯句柄对友军下令；PR #19 |
| `bots/BotLib/hero_windrunner.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_winter_wyvern.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_wisp.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_witch_doctor.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |
| `bots/BotLib/hero_zuus.lua` | UNREVIEWED | — | 尚未逐条比对 7.42 英雄补丁；未发现关键词不等于兼容 |

## 共用模块（不计算在英雄文件总数内）

| 规则 | 文件 | 需要核验 |
| --- | --- | --- |
| C742-03 | `bots/FretBots/SettingsDefault.lua` | 增强模式五阶奖励配置；7.42 正式中立装备为四阶 |
| C742-04 | `bots/Buff/NeutralItems.lua` | Buff 增强模式存在第五阶自定义发放，不代表普通模式也存在 |
| C742-05 | `bots/FunLib/jmz_func.lua` | Roshan 固定复活窗口与 7.42 递减复活机制可能冲突；已有 PR #6 |

| C742-13 | `bots/FunLib/aba_item.lua` | Javelin 已被 7.42 移除，但仍处于公共基础物品名单 |
| C742-14 | `bots/ability_item_usage_generic.lua` | 已移除 Overlord 仍保留旧主动逻辑，可能已不可达 |
| C742-15 | `bots/FunLib/aba_item.lua` | 公共物品表仍查询 Overlord 旧配方；PR #4 已处理 |

## 分类含义

- **E2**：游戏补丁与活动源码存在明确冲突（仍要在真实客户端中验证执行路径）。
- **E1**：新版技能未实现、旧字段疑似不再适用、或内部 ID / 目标类型尚未确认。不能误写成运行时崩溃。
- **UNREVIEWED**：仅列入文件盘点；缺少每个英雄的完整 7.42 新旧行为比对，不能宣称已兼容。

## 离线再生与验证

运行 `python3 scripts/patch742_audit.py --check` 检查清单、证据规则和共用模块是否仍与当前 checkout 一致。`--json` 输出机器可读的扫描报告。该工具不访问网络、不启动客户端。

## 游戏验证

参见 [无需人工盯屏的 7.42 验证方案](PATCH_7_42_UNATTENDED_VALIDATION.md)。
