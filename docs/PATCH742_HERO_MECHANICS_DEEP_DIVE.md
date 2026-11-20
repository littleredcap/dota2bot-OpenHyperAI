# Dota 2 7.42：五个英雄的新版技能行为审查（仅分析）

> 日期：2026-11-20；OHA 基线：`oha-next` `cb814c6c8dc51ed08045d6efd9f4a48147992711`。
> **本文件不是 AI 策略实现、不是完整 7.42 英雄兼容认证，也没有游戏客户端测试。** 与 [补丁驱动审查 PR #20](PATCH742_CHANGE_IMPACT.md) 配套，继续遵守 [最小修复 ≠ 技能策略成熟](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/docs/upstream-fork-workflow/docs/ISSUE_AND_REQUIREMENT_STATUS.md)。
>
> 规则事实：[Valve 官方 7.42](https://www.dota2.com/patches/7.42)。
> 可复核的客户端数据快照：[d2vpkr 提交 77a6ccca87bab183caaf0c09fd2813f2695b7a5b](https://github.com/dotabuff/d2vpkr/commit/77a6ccca87bab183caaf0c09fd2813f2695b7a5b)。
> 该快照可确认技能名称、部分行为/目标类型，但**不能证明 Valve Bot Scripting Lua 在 Local Host 环境中必然能执行新技能**。

## 结论矩阵

| 条目 | 7.42 可核对的客观规则 | 当前 OHA 的情况 | 实现判断 | 下一步 |
| --- | --- | --- | --- | --- |
| C742-17 Dazzle | Shard 新增 `dazzle_through_the_realm`：无目标、即时、0 冷却/蓝耗；本体向投影灵魂处移动，缠绕/束缚时不能施放，眩晕时仍允许（但眩晕状态延续） | `hero_dazzle.lua` 在 `SkillsComplement` 调用 Nothl Projection / End，没有 Through the Realm 的 `Consider` 或施放；Shard 仍在多位置默认出装 | `SCOPED / STATIC_ONLY / TODO`，**新能力缺口，不是证明旧投影失效** | 不急于删除 Shard：Shard 同时提供 Projection 的施法与牵引距离收益；先设计新移动与原 End 的互斥时序 |
| C742-19 Undying | Shard **不再强化 Tombstone**，现在授予 `undying_bite`；对敌方单位施放，物理攻击伤害，消耗 70 Mana、18 秒 CD，咬英雄附带沉默/削弱，咬非远古小兵可转化为可控僵尸 | `hero_undying.lua` 只处理 Decay、Soul Rip、Tombstone、Flesh Golem，**无 Bite**；默认出装 pos1（pos2 继承）、pos3、pos4 **仍购买 Shard**，pos5 不买 | `SCOPED / STATIC_ONLY / TODO`，并产生独立采购决策问题 C742-19-BUY | **P0 候选**：保守地暂停默认购买无已实现主动收益的 Shard（只改默认，不覆盖用户定制），或先实现带正反例的合理 Bite 施法；不要把旧 Tombstone 强化误当已获价值 |
| C742-18 Lone Druid 的 Spirit Bear | Bear 持有相应 Scepter 时可保存英雄的灵魂，并在英雄致命事件 0.5 秒后使用无目标主动复活；100 Mana，120 秒 CD；熊死亡则存储的英雄也死亡 | 新能力在 **Spirit Bear 单位**：`npc_units.txt` 的 `npc_dota_lone_druid_bear1` **Ability4=\`lone_druid_spirit_bear_summon_druid\`**。`hero_lone_druid_bear.lua` 仅考虑 Return/Savage Roar，未识别新技能；熊默认购买列表为空、英雄列表有 Scepter | `SCOPED / STATIC_ONLY / TODO`；需要明确 Bear 实际持有 Scepter 的条件，不能从英雄购买名单推断熊已拥有 | **P0/P1**：先确认英雄灵魂暂存时 `IsAlive` 状态、Bear 是否继续执行 `SkillsComplement`、Bear mana 和技能句柄、物品持有人，再设计存活优先与复活触发 |
| C742-20 Pugna | `pugna_oblivion_savant` 是**被动**；Scepter 加 2 次额外施法储备，每 20 秒恢复一次，可在原技能冷却时再施放；新 Life Drain 可多条同时存在，但不可对同一目标多重吸取 | `hero_pugna.lua` 的 Q/W/E/R 均仍通过 `IsFullyCastable` 判断，没有额外次数的价值模型。公用 `J.CanNotUseAbility` 在 `bot:IsChanneling()` 时直接阻止当前英雄决策 | `SCOPED / STATIC_ONLY / RESEARCH`；**不能对被动 Oblivion Savant 发主动施法命令**，当前动作是否能在持续吸取中追加仍需游戏 API 验证 | **P1**：先验证在冷却中的 `IsFullyCastable`、充能变化、正在引导 Life Drain 时能否连续施法、旧动作是否打断吸取；再优化主动资源消耗 |
| C742-21 Death Prophet | Shard 现在给 Crypt Swarm 两次充能与短暂强减速；Scepter 现在增强 Spirit Siphon（最大生命值伤害、偷攻速等），Exorcism 不再提供旧神杖升级 | `hero_death_prophet.lua` 的 Q/E 仍调用原技能接口，Q 用 `IsFullyCastable`，E 过滤 `J.CanCastOnNonMagicImmune` 和已有 Siphon modifier；没有对充能/神杖免疫交互的专项判断 | `SCOPED / STATIC_ONLY / RESEARCH`，**并非 Q/E 必然不能释放** | **P1**：检查 2 次 Crypt Swarm 应保留还是立即使用、Scepter Siphon 对 Debuff Immunity 的合法施法/生效判定，以及 Q/E 的资源机会成本 |

## A. Dazzle：新穿越技能和已有投影结束是两个不同动作

- 来源：`[npc_dota_hero_dazzle.txt](https://github.com/dotabuff/d2vpkr/blob/77a6ccca87bab183caaf0c09fd2813f2695b7a5b/dota/scripts/npc/heroes/npc_dota_hero_dazzle.txt)`，`Ability4`、`Ability6`、`Ability7` 分别为 Through the Realm、Nothl Projection、Projection End。`dazzle_through_the_realm` 有 `IsGrantedByShard=1` 和 `DependentOnAbility=dazzle_nothl_projection`。
- 当前代码：[hero_dazzle.lua](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_dazzle.lua#L195-L360)。投影结束已有 `ConsiderNothlProjectionEnd()`；新增穿越技能不能复用该 `Consider` 的“附近没敌人就 End”条件，否则可能把本体移动到不安全的战场位置。
- **正向待测**：Shard + 投影进行中、本体没有被束缚、灵魂位置明显更安全且需要本体移动；需保证不打断有价值的正在执行的技能/救援。
- **反向待测**：无 Shard、未进入投影、身体被 Root/Leash、移动本体会被集火、只需正常 End、意外重复触发。**不能以“能用且0 CD”为唯一理由施法。**
- 额外静态代码风险（**非新技能已复现 Bug**）：现有 `ConsiderNothlProjectionEnd()` 先取得 `_bot = GameStates.dazzleNothl[...].body`，却使用 `if J.IsValid(bot) then` 判断，接着访问 `J.IsRetreating(_bot)`。该有效性判断对象不一致；如缓存的 body 失效，存在潜在 nil/旧实体操作风险。应另做最小护栏用例，避免与新增技能策略捆绑。
- **策略债务**：当前 Dazzle 默认 Shard 还有**额外投影范围/牵引范围**的潜在独立收益，不能仅因 Through the Realm 未实现就机械删除默认购买。

## B. Undying：魔晶购买与 Bot 实际技能使用能力错配

- 来源：`[npc_dota_hero_undying.txt](https://github.com/dotabuff/d2vpkr/blob/77a6ccca87bab183caaf0c09fd2813f2695b7a5b/dota/scripts/npc/heroes/npc_dota_hero_undying.txt)`（`Ability4=undying_bite`；`IsGrantedByShard=1`；`UNIT_TARGET_ENEMY`，英雄和普通单位；固定施法范围 400）。官方 7.42 明确移除 Tombstone 的 Shard 增强。
- 当前源码：[hero_undying.lua](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_undying.lua#L25-L169) `X['bDeafaultAbility']=false` 且没有 `GetAbilityByName('undying_bite')`，既有四个主动 `Consider` 保留；默认购买列表 pos1、pos3、pos4 包含 `item_aghanims_shard`，pos2 继承 pos1。
- **风险**：即使金币/物品购买成功，也不表示 Bot 会使用新魔晶。此处更接近可从源码确认的“默认购买能力不匹配”，不是已证明某场对局失败。
- 两条可选小 PR（**不应同时无条件做**）：
  1. 先移除 pos1/2/3/4 的**默认** Shard 购买项，保留定制出装/奖励获得 Shard 的处理，等合理 Bite 策略可用后再审查恢复购买（类似 Meepo 的规则）。
  2. 先实现新的 `ConsiderZombieBite`：英雄与小兵两个用途分开计算，合法性优先（距离/视野/目标状态/蓝量）、比较物理攻击+250伤害、自我回血、沉默、僵尸收益、走位冲锋风险及攻击/施法机会成本；不因有兵就咬。
- **正向待测**：有合法高价值英雄目标且短距离冲锋安全；非远古小兵被击杀确实产生可控僵尸并能完成战术任务。
- **反向待测**：无 Shard、冷却/蓝不足、远古或不可见目标、冲锋深入塔/高地、抢核心正要补的兵、低生命值冲入危险区域；不能把魔晶收益等同于“咬中目标次数”。
- 注意 KV 中 `AbilityUnitTargetFlags` 有针对 Debuff Immune 的目标标记，**并不证明**官方描述的控制效果能穿透 Debuff Immunity；客户端需分开验证“能下达目标命令”和“实际施加沉默/变形”。

## C. Lone Druid：新技能属于熊，不属于 Druid 主体

- 官方 [7.42](https://www.dota2.com/patches/7.42) 的召回与暂存规则；客户端实体 KV 在 **`[npc_units.txt](https://github.com/dotabuff/d2vpkr/blob/77a6ccca87bab183caaf0c09fd2813f2695b7a5b/dota/scripts/npc/npc_units.txt#L16283-L16311)`**，`npc_dota_lone_druid_bear1` 的 **`Ability4=lone_druid_spirit_bear_summon_druid`**。这个真实内部名称比之前文档中的 `summon_lone_druid` 字符串更精确。
- [熊脚本](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_lone_druid_bear.lua#L1-L185)：读取 `GetBot()` 为 Bear，只处理 Return 和 Savage Roar；`X.sBuyList` 各位置均为空，`X.ConsiderQ()` 在 `hero:IsAlive()==false` 时返回 0。**后者是旧 Return 判断，不能简单复用于新版复活**；灵魂暂存期间引擎是否将 hero 标记为 Alive 需要实机查证。
- [Druid 本体脚本](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_lone_druid.lua#L36-L116) 的 `pos_1_w_bear` 默认购买 Scepter，但单看这条无法证明**熊**拥有该升级，需先核实物品传递/进货逻辑。
- **正向待测**：Druid 在熊的牵引范围内受到致命伤害、熊正确持有 Scepter、英雄处于灵魂暂存状态、熊具有 100 Mana、技能句柄可用并等待官方规定的 0.5s；施放成功后 Druid 复活。
- **反向待测**：没有 Bear Scepter、熊不存在/正在死亡、英雄只是普通死亡、技能冷却、熊蓝不足、熊已被控制、攻击熊会导致主英雄死亡；先安全判断是否应该躲避敌人再复活，不能无脑冲回敌方高地。
- 需要先验证测试模式下真正启动 Bear `SkillsComplement()` 的调用来源与频率，才能编写新技能逻辑。**仅 Lua Mock 让技能存在，不代表 Valve Bot 引擎会在灵魂状态中运行熊 AI。**

## D. Pugna：不是给被动技能新增施法动作

- 来源：[npc_dota_hero_pugna.txt](https://github.com/dotabuff/d2vpkr/blob/77a6ccca87bab183caaf0c09fd2813f2695b7a5b/dota/scripts/npc/heroes/npc_dota_hero_pugna.txt)：`pugna_oblivion_savant` 的 `AbilityBehavior` 仍为 `PASSIVE`，`HasScepterUpgrade=1`，Scepter 时 `AbilityCharges=2`、`ChargeRestoreTime=20`、`recast_min_cooldown=0.25`。
- [原技能优先级](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_pugna.lua#L230-L295) 为 Q → W → E → R；各技能 `IsFullyCastable` 仍驱动原 Consider。是否能使用 Scepter 赠予的额外施法机会、是否能对同一目标有效地多重 Life Drain 必须以引擎实际行为验证。
- 另一个具体策略限制：公用 [`J.CanNotUseAbility`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/FunLib/jmz_func.lua#L113-L128) 在 `bot:IsChanneling()` 为真时返回不可决策。`Life Drain` 是 `CHANNELLED`；**原框架可能因此错过新版本允许的多条 Life Drain 同时存在的机会**，但不能仅凭源码判断引擎是否允许在引导中直接发第二个技能动作，需客户端验证。
- **正向待测**：Scepter 两层储备，原技能刚进入 CD 超过 0.25 秒，确有值得重复施放的合法目标，`IsFullyCastable` / 消耗与两次允许窗口一致；两条 Life Drain 用不同目标，实测旧吸取是否保持。
- **反向待测**：无 Scepter、未获得充能、同一目标已被 Life Drain、0.25s 缓冲未结束、其它技能打断当前更有价值的 Life Drain；不要为消费储备而无条件重施法。
- **最小正确性方案**：不新增 `Action_UseAbility(pugna_oblivion_savant)`；先只写/运行 API 观测测试。根据实测调整 Q/W/E/R 的资源意图，不必重写整份英雄脚本。

## E. Death Prophet：现有技能能施放 ≠ 7.42 新升级效果用得好

- 来源：[npc_dota_hero_death_prophet.txt](https://github.com/dotabuff/d2vpkr/blob/77a6ccca87bab183caaf0c09fd2813f2695b7a5b/dota/scripts/npc/heroes/npc_dota_hero_death_prophet.txt)：Crypt Swarm `HasShardUpgrade=1`、Shard 时 `AbilityCharges=2`、充能恢复按技能等级；Spirit Siphon `HasScepterUpgrade=1`，新 `max_health_damage_pct` 和 `attack_slow` 增强；新效果对 Debuff Immunity 的穿透应分目标可施放与实际生效验证。
- [原 Q 判断](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_death_prophet.lua#L291-L383) 通过 `abilityQ:IsFullyCastable()` 后继续根据击杀、AOE、团战和清线施放——该规则仍可能合理；**但没有对两层 Shard 储备/爆发/保留的策略评价**。
- [原 E 判断](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_death_prophet.lua#L554-L615) 使用 `J.CanCastOnNonMagicImmune` 和 `modifier_death_prophet_spirit_siphon_slow` 过滤。新版神杖额外效果能够穿透 Debuff Immunity，但这个旧过滤可能阻止**本应合法且高收益**的施放；需要确认整条 Siphon 是否可对免疫目标施放、哪些子效果生效，之后再作局部调整。
- **正向待测**：Shard 两次 Q 对集群敌人确实有足够收益并不会浪费最后一层保留；Scepter 对关键核心的最大生命值/攻速收益可观测。
- **反向待测**：为使用第二层 Q 丢失更高优先级的 Silence/Spirit Siphon、已受控制或无合法视野的目标；Scepter 特殊免疫行为必须经过实机验证后才允许放宽原保护检查。

## 推荐后续修复顺序与状态边界

| 顺序 | 独立任务 | 实现状态建议 | 成功门槛 |
| --- | --- | --- | --- |
| P0 | C742-19-BUY：Undying 已不兼容的默认 Shard 采购策略 | `SCOPED / STATIC_ONLY / TODO` | 对默认购买与自定义出装分别建立 Lua 测试：不会因无 Bite AI 而无条件早买 Shard，且不破坏其它装备/通过奖励获得 Shard 的逻辑 |
| P0 | C742-17-GUARD：Dazzle Projection End 缓存 body 检查对象错误 | `SCOPED / STATIC_ONLY / RESEARCH` | 生产函数原版在 body 无效时的负例 + 修复后不再 nil 调用；保留原安全 End 判断 |
| P1 | C742-18：Bear 神杖复活的可观察能力链 | `SCOPED / STATIC_ONLY / TODO` | 先验证 Scepter 实际持有人、熊单位技能 API、死/魂暂存状态与行动结果，再实现必要 Consider |
| P1 | C742-17 / C742-19：Dazzle Through Realm 与 Undying Bite 的目标、时机和打断 | `SCOPED / STATIC_ONLY / TODO` | 独立合法性、净收益、机会成本、反例；不依靠“技能可用”直接放 |
| P2 | C742-20 / C742-21：Pugna/DP Scepter/Shard 决策收益 | `SCOPED / STATIC_ONLY / RESEARCH` | 客户端先核实额外施法/充能/免疫机制，再根据可证伪场景优化 |

**不应改变**：原 Nothl Projection / Tombstone / Spirit Bear Return / Pugna 原 Q/W/E/R / Death Prophet 原 Q/E 的可用合法判断，除非明确复现与新机制矛盾。此轮没有实施新英雄战术代码，也未自动开启额外经济、隐藏视野或 FretBots。
