# OHA-Next：Dota 2 客户端待验证清单

> 建立：2026-11-19。**这是未来的测试债务登记，不代表现在要安装客户端或搭建监控系统。**  
> 关联：[需求](OHA_NEXT_REQUIREMENTS.md) · [公平强度目标](OHA_NEXT_STRENGTH_OBJECTIVE.md) · [社区研究与策略假设](GAMEPLAY_RESEARCH_AND_IDEAS.md)  
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
| VT-001 / release_gate | [#5 Meepo 拾取](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | **7.42** 在没有/持有 Shard、各级 Divided We Stand、不同本体/分身的情况下读取 `HasShard()`、`GetAbilityByName('meepo_divided_we_stand')`、`GetBehavior()`、`IsTrained()`、`IsFullyCastable()`、`GetCastRange()`；确认官方技能 KV 标记为 `PASSIVE` 时，Bot API 是否真的允许单位目标拾取；提交命令后验证实际携带/缴械，而非只看到调用 | Client 6983 提取 KV + 7 项离线 Mock；**blocked_no_client** |
| VT-002 / release_gate | [#5 Meepo Fling](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | 拾取成功后 `meepo_fling_release` 什么时候显现、能否施放到敌方英雄/友方 Meepo/地面、技能等级范围和释放后状态、5 秒到期；验证当前代码的 `GetSpecialValueInt('range')`、`Action_UseAbilityOnEntity` 是否真实有效 | 新技能名由客户端 KV 确认；实际动作链未测；**blocked_no_client** |
| VT-003 / release_gate | [#5 Meepo 使用收益](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | **反例重点**：远程/特殊兵线小兵快被反补、塔前关键兵、核心正在依赖攻击输出、敌方即将逃离投掷范围、原本更好的一套 Poof/Earthbind。比较“拾取/投掷”与“不施放”的结果；必须确认策略不会仅因附近有小兵/敌人就无脑使用。当前代码**没有**经济/兵线机会成本评分、结束后目标丢失处置 | 用户提出的具体机会成本场景 + 本项目静态代码分析；**blocked_no_client** |
| VT-004 / release_gate | [#5 Meepo 新策略误伤](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) | 确认只接收合法友方单位、不意外打断引导、不同分身调用无冲突；携带时被缴械/共享伤害是否造成反效果；即使 Fling 目标失效也有安全结束路径 | 当前设计排除拾起 Meepo，但尚无引擎证据；**blocked_no_client** |
| VT-005 / release_gate | [#4 Meepo Dig 与旧技能](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) | 无神杖时不存在 Dig 不会报 Lua 错；有神杖后技能名称和施放有效；删除 MegaMeepo 后技能升级表、Poof、Earthbind 不受旧句柄影响 | 6 项离线 Mock；**blocked_no_client** |
| VT-006 / release_gate | [#4 兽王/狼人装备](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) | 真实购买流程不会再向已移除 Overlord 下单；公共物品库加载成功，Dominator 后续出装不发生长时间停滞 | 旧装备引用静态清理、Lua 检查；**blocked_no_client** |
| VT-007 / release_gate | [#6 Roshan 复活启发式](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) | 在 7.42 普通/加速和 Turbo 的 1/2/3+ 次 Roshan 死亡后，核对 `GetRoshanKillTime()` 更新、Lua 实例是否在多 Bot 中重载、真实可刷新窗口与 10/9/8 分钟保守上界；有缺失击杀记录时不提前误判；不使用隐藏状态作弊 | 9 个离线 Mock；**blocked_no_client** |
| VT-008 / research | [#3 7.42 中立装备审计](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3) | 标准对局与 FretBots/Buff 增强对局分开：新版四阶选项、实际 `item_*` 名称、轮出物品是否能 `CreateItem`，普通公平模式不获得额外装备 | 静态审计；**blocked_no_client** |
| VT-009 / research | [#3 7.42 地图/Tormentor](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3) | 核对 15:00 首次刷新、Greater Horn of Battle 的内部名称/使用方式，以及 Twin Gates 移动后路径和旧坐标；不可用旧地图快照冒充新版本 | 官方 7.42 规则；**blocked_no_client** |

## 3. 原有逻辑 PR 与未来策略场景

| ID / 重要性 | PR / 需求 | 场景与通过条件 | 当前状态 |
| --- | --- | --- | --- |
| VT-010 / release_gate | [#1 游走目标锁定](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) · F-05 | 引擎真正运行团队游走模式时，验证锁定期限、失效目标解锁、目标切换与其它模式打断；不只提取函数做 Mock | **blocked_no_client** |
| VT-011 / release_gate | [#1 Roshan DPS](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) · F-07 | 验证攻击速度/物抗估算与实际 Roshan DPS、队友是否可到场；测试无玩家、队伍不齐和切换边的场景 | **blocked_no_client** |
| VT-012 / research | F-07 / 新候选 F-10 **敌方打 Roshan 时是否争夺** | 可见敌方打盾 vs 敌人消失的“怀疑”两种不同情报；不同人数、技能/CD、TP、距离、兵线、基地风险；记录 contest / steal / trade / defend / scout 选择，验证无作弊透视和允许改变计划 | **planned，当前只研究，不运行** |
| VT-013 / research | F-06/F-07 **关键目标后的转换** | 抢到 Aegis 或拿到新 Tormentor 掉落后，能否合理处理兵线、推塔、控图与撤退；避免只为拿奖励而送团灭 | **planned，当前只研究，不运行** |

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
