# Dota 2 7.42 结构性兼容审计（第一轮）

> 状态：**静态审计记录，不是修复或“已经兼容 7.42”的声明**  
> 审计日期：2026-11-19  
> 审计基准：`littleredcap/dota2bot-OpenHyperAI:oha-next`，SHA `cb814c6c8dc51ed08045d6efd9f4a48147992711`（与原作者 `forest0xia:main` 在审计时相同）  
> 目标版本：Valve 2026-11-18 发布的 Dota 2 **7.42**  
> 官方依据：[7.42 Gameplay Update](https://www.dota2.com/newsentry/689773669992367212) · [7.42 Patch Notes](https://www.dota2.com/patches/7.42)  
> 需求依据：F-01 目标版本兼容；详细证据等级以 [OHA_NEXT_REQUIREMENTS.md](OHA_NEXT_REQUIREMENTS.md) 为准（此文档仍在独立 PR 中，链接需等该 PR 合入后在 `oha-next` 生效）。

## 0. 审计规则

- **E2（源码冲突）**：Valve 正式版本规则与本项目**实际有效代码**不一致，能指出精确位置。E2 足以提出修复 PR，但**不等于已经在 7.42 游戏客户端复现**。
- **E1 / 待确认**：补丁明确变化，但当前无法确认对应 API、运行分支或实际效果，不能写作“已证实 Bug”。
- **能力缺口**：新机制尚未接入主动决策，不等于既有机制运行错误。
- 本轮检查了核心公共文件、中立物品两套额外发放模块、Roshan、部分英雄与出装代码；另针对数个被移除物品/技能的关键词抽样扫描了仓库 **128 个 `bots/BotLib/hero_*.lua` 文件**。这不是覆盖 7.42 **全部**改动的全量审计；不可把“未命中关键词”误写成“已适配”。
- **普通 Bot 对局与 FretBots / Buff 加强模式分开评价。** 后者可能有额外装备发放行为，不应直接外推到普通对局。
- 用户当前要求**先做需求/兼容核查，不搭建新故障监控或批量对局设施**；本轮不修改运行代码、不宣称任何游戏实测。

## 1. 已定位的不匹配（E2）

| ID / 建议审查序 | 官方 7.42 变化 | 当前源码证据 | 潜在影响与边界 |
| --- | --- | --- | --- |
| C742-01 / 优先 | **Meepo：删除 MegaMeepo**；Divided We Stand 的 Shard 效果重做，Dig 改为 Scepter 提供 | [hero_meepo.lua:161–162](../bots/BotLib/hero_meepo.lua) 与 [186–231](../bots/BotLib/hero_meepo.lua) 仍获取 `meepo_megameepo` / `meepo_megameepo_fling` 并调用；[703–745](../bots/BotLib/hero_meepo.lua) 对 `MegaMeepo:IsTrained()`、`MegaMeepoFling:IsHidden()` **无 nil 保护**；出装仍先买 Shard | 旧能力句柄若是 nil，将发生 Lua 方法调用异常；旧 Fling 句柄与新子技能的内部名/解锁条件也需核查。**未实机证明何时返回 nil**，不能将“必崩溃”当事实 |
| C742-02 / 优先 | **Helm of the Overlord 被移除** | [hero_beastmaster.lua:76](../bots/BotLib/hero_beastmaster.lua)、[hero_lycan.lua:92](../bots/BotLib/hero_lycan.lua) 的 `pos_3` 出装列表仍有 `item_helm_of_the_overlord` | 该物品已不再是有效购买目标，相关装备计划需要重新选择；具体购买状态机遇到无效目标时的行为尚未复现 |
| C742-03 / 优先（加强模式） | **中立装备从五阶改为四阶**，新的时间为 0:00 / 15:00 / 30:00 / 50:00，且每阶通过预定池选项 | [FretBots/SettingsDefault.lua:63–73](../bots/FretBots/SettingsDefault.lua) 仍设置 `maxPerTier`、`timings`、`timingsDefault` 五个值；[FretBots/SettingsNeutralItemTable.lua:148–165](../bots/FretBots/SettingsNeutralItemTable.lua) 仍有 `tier=5`；[Buff/NeutralItems.lua:123,298–312](../bots/Buff/NeutralItems.lua) 仍按五阶发放 | FretBots / Buff **额外发放机制**与正式 7.42 不一致；不能直接推断普通无加强模式也会生成这些物品。是否保留作弊/增强模式的自定义时间须单独决策 |
| C742-04 / 优先（加强模式） | **多项中立装备轮出或改阶** | [FretBots/SettingsNeutralItemTable.lua](../bots/FretBots/SettingsNeutralItemTable.lua) 仍**启用**已轮出的 `item_duelist_gloves`、`item_occult_bracelet`、`item_dagger_of_ristul`、`item_essence_ring`、`item_poor_mans_shield`、`item_searing_signet`、`item_medallion_of_courage`、`item_unrelenting_eye`、`item_flayers_bota`、`item_spider_legs`、`item_desolator_2` 等；`item_psychic_headband`、`item_rattlecage`、`item_dezun_bloodrite` 等阶数仍旧 | 额外发放逻辑确实会从该候选表选取装备（[FretBots/NeutralItems.lua:124–145](../bots/FretBots/NeutralItems.lua)），但轮出物品的 `CreateItem` 在当前引擎会失败、返回 nil 还是仍可创建，**需要测试后判断**。不能只改数字而不核对完整池 |
| C742-05 / 优先 | **Roshan 每次死亡后基础复活时间递减 1 分钟，最低 5 分钟** | [jmz_func.lua:4977–4990](../bots/FunLib/jmz_func.lua) 的 `J.IsRoshanAlive()` 在击杀后使用固定的常规 `11 * 60` 秒，Turbo 为 `6 * 60` 秒；[mode_roshan_generic.lua:108–123](../bots/mode_roshan_generic.lua) 依赖该判断 | 7.42 中可能已经刷新、但脚本仍认为未刷新，延迟接近 Roshan 或错误改变模式欲望；是**静态策略风险**，尚未获得游戏内日志 |
| C742-06 / 优先 | **Leshrac Nihilism 7.42 重做为范围缴械、持续驱散；不再让自己虚无** | [hero_leshrac.lua:943–970](../bots/BotLib/hero_leshrac.lua) 原实现若检测到足以致命的来袭攻击弹道，即使附近没有敌人也想施放 Nihilism；但 7.42 已失去自身虚无效果。原句柄也未做 nil 保护 | 施法的**旧自保理由已失效**，可能浪费神杖关键技能、错误解除敌人的负面状态。已于 [Draft PR #8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8) 保守修正，9 项 Lua Mock 通过，未实机验证 |

**注意：** 上表是六组兼容性问题，不是“五个已经实机复现的 Bug”。并且 C742-03、04 为可选/加强模式，不能与标准 Bot 模式混算影响范围。

### 1.1 具体版本变化与当前数据

- 7.42 官方列出的中立物品正式选项是四阶，包括新的 `Red Ledger`、`Brick`、`Balmhook`、`Vile Phial`、`Helm of the Hivemind` 等。内部 `item_*` 名称必须依据 7.42 客户端数据确定，**不能从展示名自行拼写**。
- 除表中列出的物品外，还需核对 `item_cloak_of_flames`、`item_giant_maul`、`item_stygian_desolator` 对应的旧内部名；不要把注释中的历史装备误算成有效候选。
- `Buff/NeutralItems.lua` 的分配时间为常规 0 / 17 / 27 / 37 / 60 分钟（Turbo 特殊计算），与正式 7.42 的 0 / 15 / 30 / 50 分钟不同。这是增强模式自定义发放，不应在明确模式设计前机械替换。

## 2. 7.42 变化已确认，但尚不能确定是否构成当前 Bug

| 项目 | Valve 变化 | 已读源码与审查判断 | 状态 |
| --- | --- | --- | --- |
| Tormentor | 首次刷新改为 **15:00**（原 20:00）；护盾基础值 **4000**；掉落 **Greater Horn of Battle**，第二次及以后击杀另掉 Shard | [jmz_func.lua:6002–6018](../bots/FunLib/jmz_func.lua) 存在日夜位置规则，[mode_farm_generic.lua:137–146](../bots/mode_farm_generic.lua) 读取 Tormentor 附近友军；本轮**未找到经过验证的首次刷新硬编码使用路径**。新掉落物的主动使用策略尚未确认 | E1：需要追踪调用/命名/API，不得宣称当前必然漏打 |
| Twin Gates / 地形 | 双门移到地图上/下边缘；部分野点、两队中路塔和河道地形移动 | [mode_roshan_generic.lua:12–15](../bots/mode_roshan_generic.lua) 的旧 Twin Gate 坐标是**注释**，不是执行代码；[aba_site.lua](../bots/FunLib/aba_site.lua) 的部分野点路径使用 `GetNeutralSpawners()` 动态查询。其它坐标和 TP/gate 路径尚未全量审查 | E1：不能仅因文件中出现旧坐标就认定 Bug |
| Meepo 新技能结构 | Shard 现在作用于 Divided We Stand，Dig 改为 Scepter；Fling 是新的附属行动 | 旧技能名在代码中直接调用已如 C742-01；**新附属技能的准确内部名**须以 7.42 客户端数据核对，不能猜测 | E1（API 身份）+ E2（旧调用） |
| Beastmaster Scepter | 删除 Drums of Slom，Scepter 提供 **Summon Ancient Thunderhide** | [hero_beastmaster.lua:166](../bots/BotLib/hero_beastmaster.lua) 的旧 Drums 引用已注释，不能算活跃旧技能；尚未找到 Thunderhide 主动使用逻辑，可能是未实现的**新能力缺口** | E1 / 功能缺口 |
| Chaos Knight | 删除 Fundamental Forging，新增带主动效果的 **Ahead, Armageddon** | [hero_chaos_knight.lua](../bots/BotLib/hero_chaos_knight.lua) 主要使用 `sAbilityList` 的原有技能索引和 Q/W/R 考虑函数，新主动尚需专门实现/适配；技能槽变化需游戏数据确认 | E1 / 功能缺口 |
| Leshrac Nihilism 实机行为 | 7.42 保留无目标施放，但效果改为缴械/持续驱散，不再自身虚无 | 原触发理由与 7.42 冲突已单独列为 C742-06；**实际 Bot API 可用性、持续驱散是否会移除队友控制、何时值得施放**尚需客户端验证 | E2 已定位逻辑冲突；策略收益与引擎结果仍 E1/未知 |
| 新购买装备 / Item Potency | 7.42 加入新购物装备、移除 `Javelin`、`Khanda` 等，调整多种物品合成；新增 Item Potency 机制 | 128 个英雄文件的**指定字符串扫描**发现兽王/狼人仍购入 Overlord（C742-02），但不是所有物品和合成条件的全量核验。合成优先复用 `GetItemComponents()`，避免照抄旧配方 | E1 / 后续审查 |

## 3. 本轮实际完成的检查与限制

1. 确认 Valve 7.42 发布时间和官方规则；确认仓库 `main` / `oha-next` 与上游 `forest0xia/main` 同为 `cb814c6c8dc51ed08045d6efd9f4a48147992711`，**没有 7.42 的新提交自动同步进来**。
2. 读取 `hero_meepo.lua`、`hero_beastmaster.lua`、`hero_lycan.lua`、`hero_leshrac.lua`、`hero_chaos_knight.lua`、`hero_furion.lua` 及相关公共、物品和模式文件；选择性扫描 128 个英雄文件中的旧物品/技能名称。
3. 检查 FretBots 配置、发放实现和 Buff 专用中立物品模块，确认旧候选表的有效行不是全部历史注释。
4. **未做**：运行 Dota 7.42、验证 `GetAbilityByName` 在删除技能时实际返回什么、检查全部英雄新技能槽、重跑全量生成 Lua、核验 7.42 最新 `npc_abilities.txt` / `neutral_items.txt` 精确内部名、评估游戏强度、对照统计。故上述 E2 不能升级为 E4。

## 4. 下一批建议的独立修复 PR（当前仅列需求，不提交玩法改动）

| 顺序 | 修复范围 | 最小验收 |
| --- | --- | --- |
| A | Meepo：删除旧 MegaMeepo 主动调用路径或安全保护，并按新 Shard/Scepter 机制重新实现 | 无 nil 方法调用；离线模拟旧能力不存在、技能隐藏/未训练、升级后新行为；准确能力 ID 需实机/数据核验 |
| B | 兽王/狼人：移除 Overlord 购买目标并选择版本允许的出装替代 | 正常出装计划不引用已移除目标；购买链不会因空缺停滞；替代品的实际购买仍需游戏确认 |
| C | Roshan：不再仅凭死后固定 11 分钟推断存活；依据可验证的游戏时间/状态接口与 7.42 规则修订 | 多次击杀和不同复活时间下的离线用例；在不知当前状态时保留保守处理和未知状态 |
| D | FretBots/ Buff：针对加强模式调整有效四阶池，清理轮出项，核验内部 ID 与新发放语义 | 有效列表仅包含目标版本允许的候选、阶数正确、无 nil item 发放；仍区分标准对局与额外发放 |
| E | 新目标、新主动能力和新物品：Greater Horn of Battle、Beastmaster、Chaos Knight、Leshrac 与地图坐标 | 核对当前游戏数据和 API 可用性后分别建小 PR；不把未实现新功能称为已存在 Bug |
| F | Leshrac Nihilism：新版自保方式、可见敌方目标与短 CD 触发 | [Draft PR #8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8) 已修复旧弹道自保判定、刷新神杖句柄，9 项 Lua 5.1 Mock 通过；**未在 Dota 7.42 验证实际施法与驱散收益** |

本清单不是所有英雄或所有机制的最终适配验收。每项修复都要说明 E2 静态依据、离线覆盖和实机未验证部分，默认通过 PR 审查，不直接修改 `main`。

## 5. 官方依据与可追溯链接

- [Valve 7.42 正式公告（2026-11-18）](https://www.dota2.com/newsentry/689773669992367212)
- [Valve 7.42 详细补丁说明：英雄、物品、中立装备、Roshan/Tormentor 与地图](https://www.dota2.com/patches/7.42)
- [本仓库被审计基准提交](https://github.com/littleredcap/dota2bot-OpenHyperAI/commit/cb814c6c8dc51ed08045d6efd9f4a48147992711)
- [仓库原有 7.41a 升级规范](PATCH_UPDATE_GUIDE.md)

**更新规则：** 如果 Valve 后续发布 7.42a 等热修、客户端实际数据与补丁文本不同，记录完整版本与证据，追加审计结论；不要静默覆盖历史记录。