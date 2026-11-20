# OHA-Next：Dota 2 客户端待验证清单

> 建立：2026-11-19。**这是未来的测试债务登记，不代表现在要安装客户端或搭建监控系统。**  
> 关联：[需求](OHA_NEXT_REQUIREMENTS.md) · [问题与未来策略状态台账](ISSUE_AND_REQUIREMENT_STATUS.md) · [公平强度目标](OHA_NEXT_STRENGTH_OBJECTIVE.md) · [社区研究与策略假设](GAMEPLAY_RESEARCH_AND_IDEAS.md)  
> 对局监控、批跑和回传设施继续 **deferred**；已有 GitHub Lua Mock 通过只证明对应离线断言，不能自动把本表标为通过。

## 1. 登记和关闭规则

- **必须登记的事项**：依赖真实 Dota Bot Scripting API、游戏机制动态状态、动作队列、路径/视野、物品购买/装备时机、客户端版本、不同英雄对战行为或公平胜率的结论。
- 每项有不可复用的 `VT-xxx`，绑定需求编号、相关 PR、**确切运行版本 SHA**、测试场景、必须观察的状态和验收标准。后续补上引擎 build、日期、日志/录像或测试 run 链接。
- 状态：`blocked_no_client` → `ready` → `running` → `passed` / `failed` / `inconclusive`；新增需求用 `planned`。单独标注 `mock_passed` 作为离线证据，不把它升级为 `passed`。
- **阻塞级别分开**：`release_gate` 表示不应以“已实战兼容/增强”名义发布；`research` 表示新策略需要收集数据。当前不因 release gate 去强制部署客户端或要求用户人工完成对局。
- 失败或无法执行也保留原因。已经过期的游戏补丁、PR 改版、技能 ID 更新时重新审查；变更 ID 不能直接覆盖旧证据。
- **绝不自动通过**：如果游戏没加载目标 Lua、缺少目标英雄、触发条件未出现、对局提前中止或看不到动作后果，结果保持 `inconclusive`。

## 2. F-01 当前 PR 关联测试

| ID / 重要性 | PR/对象 | 需要在客户端验证的实际场景和通过条件 | 当前证据与状态 |
| --- | --- | --- | --- |
| VT-001 / release_gate | [#5 Meepo 拾取](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | **7.42** 在没有/持有 Shard、各级 Divided We Stand、不同本体/分身的情况下读取 `HasShard()`、`GetAbilityByName('meepo_divided_we_stand')`、`GetBehavior()`、`IsTrained()`、`IsFullyCastable()`、`GetCastRange()`；确认官方技能 KV 标记为 `PASSIVE` 时，Bot API 是否真的允许单位目标拾取；提交命令后验证实际携带/缴械，而非只看到调用 | Client 6983 提取 KV + 9 项 Shard 离线 Mock（15 项含父分支）；**blocked_no_client** |
| VT-002 / release_gate | [#5 Meepo Fling](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | 拾取成功后 `meepo_fling_release` 什么时候显现、能否施放到敌方英雄/友方 Meepo/地面、技能等级范围和释放后状态、5 秒到期；验证当前代码的 `GetSpecialValueInt('range')`、`Action_UseAbilityOnEntity` 是否真实有效 | 新技能名由客户端 KV 确认；实际动作链未测；**blocked_no_client** |
| VT-003 / release_gate | [#5 Meepo 使用收益](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | **反例重点**：远程/特殊兵线小兵快被反补、塔前关键兵、核心正在依赖攻击输出、敌方即将逃离投掷范围、原本更好的一套 Poof/Earthbind。比较“拾取/投掷”与“不施放”的结果；必须确认策略不会仅因附近有小兵/敌人就无脑使用。当前代码**没有**经济/兵线机会成本评分、结束后目标丢失处置 | 用户提出的具体机会成本场景 + 本项目静态代码分析；**blocked_no_client** |
| VT-004 / release_gate | [#5 Meepo 新策略误伤](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | 确认只接收合法友方单位、不意外打断引导、不同分身调用无冲突；携带时被缴械/共享伤害是否造成反效果；即使 Fling 目标失效也有安全结束路径 | 当前设计排除拾起 Meepo；实验代码 `ENABLE_EXPERIMENTAL_SHARD_AI = false` **默认禁用**（直到在客户端核验且机会成本规则达标）；尚无引擎证据；**blocked_no_client** |
| VT-005 / release_gate | [#4 Meepo Dig 与旧技能](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) | 无神杖时不存在 Dig 不会报 Lua 错；有神杖后技能名称和施放有效；删除 MegaMeepo 后技能升级表、Poof、Earthbind 不受旧句柄影响 | 6 项离线 Mock；**blocked_no_client** |
| VT-006 / release_gate | [#4 兽王/狼人装备](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) | 真实购买流程不会再向已移除 Overlord 下单；公共物品库加载成功，Dominator 后续出装不发生长时间停滞 | 旧装备引用静态清理、Lua 检查；**blocked_no_client** |
| VT-007 / release_gate | [#6 Roshan 复活启发式](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) | 在 7.42 普通/加速和 Turbo 的 1/2/3+ 次 Roshan 死亡后，核对 `GetRoshanKillTime()` 更新、Lua 实例是否在多 Bot 中重载、真实可刷新窗口与 10/9/8 分钟保守上界；有缺失击杀记录时不提前误判；不使用隐藏状态作弊 | 9 个离线 Mock；**blocked_no_client** |
| VT-008 / research | [#3 7.42 中立装备审计](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3) | 标准对局与 FretBots/Buff 增强对局分开：新版四阶选项、实际 `item_*` 名称、轮出物品是否能 `CreateItem`，普通公平模式不获得额外装备 | 静态审计；**blocked_no_client** |
| VT-009 / research | [#3 7.42 地图/Tormentor](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3) | 核对 15:00 首次刷新、Greater Horn of Battle 的内部名称/使用方式，以及 Twin Gates 移动后路径和旧坐标；不可用旧地图快照冒充新版本 | 官方 7.42 规则；**blocked_no_client** |

| VT-014 / release_gate | [#4 默认 Meepo 出装](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) + [#5 实验魔晶](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | **7.42** 各职责默认购买链是否不再在散失后优先买 Shard，并仍能继续购买后续合法物品；自定义角色出装是否不受阻；若通过游戏奖励被动获得 Shard，策略关闭时不会误发无效命令。未来只有经过 VT-001～004 的能力/收益验证后才重新评估主动购买时机 | 静态移除默认购买路径；Lua 5.1 回归在 #4/#5 分支执行；**blocked_no_client** |

## 3. 原有逻辑 PR 与未来策略场景

| ID / 重要性 | PR / 需求 | 场景与通过条件 | 当前状态 |
| --- | --- | --- | --- |
| VT-010 / release_gate | [#1 游走目标锁定](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) · F-05 | 引擎真正运行团队游走模式时，验证锁定期限、失效目标解锁、目标切换与其它模式打断；不只提取函数做 Mock | **blocked_no_client** |
| VT-011 / release_gate | [#1 Roshan DPS](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) · F-07 | 验证攻击速度/物抗估算与实际 Roshan DPS、队友是否可到场；测试无玩家、队伍不齐和切换边的场景 | **blocked_no_client** |
| VT-012 / research | F-07 / 新候选 F-10 **敌方打 Roshan 时是否争夺** | 可见敌方打盾 vs 敌人消失的“怀疑”两种不同情报；不同人数、技能/CD、TP、距离、兵线、基地风险；记录 contest / steal / trade / defend / scout 选择，验证无作弊透视和允许改变计划 | **planned，当前只研究，不运行** |
| VT-013 / research | F-06/F-07 **关键目标后的转换** | 抢到 Aegis 或拿到新 Tormentor 掉落后，能否合理处理兵线、推塔、控图与撤退；避免只为拿奖励而送团灭 | **planned，当前只研究，不运行** |

| VT-015 / release_gate | [PR #7：Issue #155 物品循环](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/7) | 在真实 Dota 7.42 中，Bot 野外背包紧张时主动丢弃 Magic Wand/Stick/Quelling Blade 后，`mode_team_roam_generic.lua` 写入的 `bot.ohaDiscardedItems[item]` 是否可被 `item_purchase_generic.lua` 跨脚本读取并阻止同一物品被捡回；正常意外掉落物仍能拾回；后期主动丢弃莲花不循环；实际游戏无动作反复覆盖 | 上游 [#155](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/155) + [Lua CI 9/9](https://github.com/littleredcap/dota2bot-OpenHyperAI/actions/runs/44533284252)；**blocked_no_client** |
| VT-016 / release_gate | [PR #8：7.42 Leshrac Nihilism](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8) | 无神杖时 `GetAbilityByName('leshrac_greater_lightning_storm')` nil/隐藏情况，神杖后句柄、`IsTrained`、`radius` 和实际无目标施放；确认 7.42 已无自身虚无、缴械/基础驱散是否生效以及是否意外解除敌方所受队友控制 | 官方 7.42 + [Lua CI 9/9](https://github.com/littleredcap/dota2bot-OpenHyperAI/actions/runs/44534515652)；**blocked_no_client** |
| VT-017 / release_gate | [Issue #176 Draft PR #9](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/9)：纯小兵攻击 Ancient/T4 的防守 | 7.42：没有敌方英雄在高地，**己方合法可见**小兵攻击目标分别是远古、四塔和普通移动中的小兵。确认 `GetUnitList(UnitType.Enemies)`、`GetAttackTarget()` 与跨 Bot `GetTeamMember()` 的实际返回，是否仅指派最近存活 Bot 到 Mid 防守入口并成功移动/打掉威胁；对没有视野、有人在打团、普通兵线经过、多人推塔等场景不可误召集全队；TS 生成 Lua 的运行版本身份必须与修复 SHA 一致 | [TS 构建+Lua 10/10](https://github.com/littleredcap/dota2bot-OpenHyperAI/actions/runs/44544007208)；**blocked_no_client** |

| VT-018 / release_gate | [Issue #170 Draft PR #10](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/10)：放逐与队友伤害冲突 | 实际对局演示 OD Astral、SD Disruption、Eul 追击吹风：敌方低 HP 正被队友普攻、2+ 队友集火、敌人已受控时不应普通进攻放逐；敌人引导关键技能时仍可打断；我方英雄面临危险时仍可救援。进一步覆盖 **Sniper/Lion/Lina 未命中大招、WD 持续伤害、凤凰蛋和多次 Eul** 等当前规则未能识别的场景，记录误拦截与漏保护。 | [Lua Mock 10/10](https://github.com/littleredcap/dota2bot-OpenHyperAI/actions/runs/44544655042)；跨英雄技能时序/真实强度 **blocked_no_client** |

| VT-019 / research | [上游 Issue #159](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/159)：敌人多数死亡后 Bot 仍打野、不推塔 | 在固定游戏构建、无 FretBots 额外资源时，分别检查敌方 0/1/2/3 名英雄存活、我方附近 1/2/3 名队友、近远 T2/高地与兵线是否到位的场景：实际 `GetFarmDesire` / `GetPushDesire` / 其它模式的候选值、最终选择及后续动作。既要避免优势时长期刷野，也不应因修改而让单个核心无兵线强行冲高。优先验证 `aba_push.ts` 深入敌方基地时少于 3 名附近友军限制，以及 `mode_farm_generic.lua` 对敌方少量存活英雄的提前退出；**现已有 Draft PR #11 局部修复，仍待实机验证** | 仅 [Issue #159](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/159) + 静态 E2 假设；**planned / blocked_no_client** |

## 3.5 最新 7.42 最小修复的客户端验收债务（新增）

> **注意：所有条目均尚未运行客户端。** 本表不是要求用户盯着对局，而是为了未来一次性/自动化复现时不忘记验证实际技能行为；若无法实际获取某个 API 状态，就标记 unknown / inconclusive。

| VT / 等级 | 问题与 PR | 实机必须观察的正反场景 / 策略未完成部分 | 状态 |
| --- | --- | --- | --- |
| VT-020 / release_gate | [先知 Oldgrowth 被动化 PR #16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16) · C742-07 | 技能已经成为被动时不能提交旧主动指令；Sprout、Nature's Call、Teleportation、Wrath 的合法施法不会受误删影响；被动触发协同仍需另立优化任务。 | `mock_passed`；**blocked_no_client** |
| VT-021 / release_gate | [Chen Summon Convert / Zealot PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) · C742-10 | 不存在旧 Summon Convert 时技能流程不得 nil 调用；旧 Hand/Penitence/Persuasion/Favor 保持可施法；Zealot 新复活与 Holy Persuasion 自我召回需先确认单位/可施法条件、技能冷却与合法动作回执，**尚未实现**。 | `mock_passed`（仅旧逻辑）；**blocked_no_client** |
| VT-022 / release_gate | [Abaddon Coil PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) · C742-08 | 有/无 Shard 时 Mist Coil 的真实伤害、生命消耗、低 HP 安全阈值与神杖 AoE；不得凭旧纯粹伤害估算错误抢人头；原护盾救援需要保留。 | `mock_passed`（伤害类型）；**blocked_no_client** |
| VT-023 / research | [CK 新 Armageddon 槽位 Mock PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) · C742-09 | 确认 Ability4/6、幻象就绪、地面目标、冲锋引导及 Q/W/R 对冲锋的打断；**现无 Armageddon 策略代码**，不能因槽位测试通过即宣称可用。 | `mock_passed`（仅槽位） + 新策略 `planned`；**blocked_no_client** |
| VT-024 / release_gate | [7.42 Javelin 清理 PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) · C742-13 | `sBasicItems` 不含 Javelin；版本实际商店及组合装备购买链有效；与 PR #4 Overlord 清理同时合并后不会初始化异常、购买队列卡死。 | `mock_passed`（物品分类）；**blocked_no_client** |

## 3.6 7.42 组合包的独立客户端验证（新增）

| ID / 重要性 | PR/对象 | 场景和通过条件 | 当前状态 |
| --- | --- | --- | --- |
| VT-025 / release_gate | [7.42 五项最小修复整合 Draft PR #18](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/18) · ENG-PATCH742-JOINT | 通过 Local Host + Local Dev Script 加载 **PR #18 实际 commit SHA** 而不是 Workshop 旧脚本；验证 OHA 后缀、核心模块启动、Meepo/Leshrac/Furion/Chen/Abaddon/Beastmaster/Lycan 的主要初始化/购买/施法，无 Lua 错误；对已移除 Javelin/Overlord 不再请求配方。每项功能独立 VT-005～007、VT-016、VT-020～024 仍需逐条验收。**单纯看到 .OHA 不能确认文件 SHA**，本地实际文件/启动标记需另证据。 | 联合 CI 44 + 5 项通过；尚无实际 Dota 客户端，**blocked_no_client** |

## 3.7 7.42 补丁驱动结构检查的后续客户端门槛（已登记、未测试）

| 验证编号 | 对应问题与当前代码 | 必须满足的实机观测与反例 | 状态 |
| --- | --- | --- | --- |
| VT-026 / release_gate | C742-16 Weaver Time Lapse (Ally) · [#19](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/19) | 没有神杖时自身无目标回溯正常；获得神杖后 bot:GetAbilityByName('weaver_time_lapse_ally') 有效、500 距离救援友军成功、两个回溯共享冷却；句柄缺失/友军不合法时不失去正常 Shukuchi 或其它行动。 | 生产函数 Lua 12/12 Mock，**blocked_no_client** |
| VT-027 / research | C742-17 Dazzle Through the Realm · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 核对 Shard 新句柄、施法类型、Nothl Projection 本体/灵魂坐标、受控/被缠绕时禁用、结束投影的真实条件。尚无新 Consider。 | **blocked_no_client** |
| VT-028 / research | C742-18 Lone Druid Spirit Bear 新英雄复活 · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 神杖后英雄濒死时熊是否持有英雄灵魂，熊复活技能 ID、可见状态、冷却、合法施法及熊被击杀时的负面结果；未确认前不编造动作。 | **blocked_no_client** |
| VT-029 / research | C742-19 Undying Zombie Bite · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 确认 Shard `undying_bite` 技能存在时的目标类型、是否能使用、目标失效/抗性等边界；分析其与其他技能使用时机是否冲突。 | **blocked_no_client** |
| VT-030 / research | C742-20 Pugna Oblivion Savant Scepter · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 在原 Q/W/E/R 冷却期、有/无 Scepter 情形实际读取 IsFullyCastable 与额外施法充能，确认重新施法与旧决策是否互相抢指令；不尝试主动施放被动。 | **blocked_no_client** |
| VT-031 / research | C742-11 Beastmaster Ancient Thunderhide · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 神杖后新 `beastmaster_summon_thunderhide` 能力可用性、已召唤雷霆蜥蜴状态、冷却/目标与团队任务协调；缺失时安全跳过。 | **blocked_no_client** |
| VT-032 / research | C742-22/23 Nyx Scarab Metabolism 和 Lycan Pack Hunter 新被动 · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 核对旧 Innate 不再可用、新被动生效和英雄/受控单位标记对可见信息的影响；没有旧名字符串不能当作实机正常。 | **blocked_no_client** |
| VT-033 / research | C742-21 Death Prophet Shard/Scepter 效果交换 · [#20](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/20) | 实测 Crypt Swarm 充能、Spirit Siphon 神杖效果、旧技能升级/购买与高价值施法窗口；记录正反例和装备收益。 | **blocked_no_client** |

## 4. 执行顺序和所需最小证据

未来首次可用客户端时，不应让所有测试混在一起跑数十局：先验证 *脚本加载版本* → VT-001/002/005 的 Meepo API → VT-007 Roshan 计时 → VT-006 购物 → 后续策略场景；只在相应行为能正确触发并观察时才进入完整对局与对照。

对每个测试至少填写：

```text
test_id:
repo + bot_sha:
dota_build / mode / radiant-dire:
pr / configuration:
repro_steps:
input_preconditions:
observable_expected_result:
actual_observed_result:
evidence_link: (log, video, artifact or local file)
outcome: passed | failed | inconclusive
known_gap:
```

**对局客户端、游戏内脚本加载验证和自动数据回传尚未配置。** 现在注册的是未来的可执行清单，不代表用户需要立刻打开电脑、自己操作英雄或运行长时间比赛。
