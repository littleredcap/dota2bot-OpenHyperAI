# OHA-Next：问题/需求状态台账——最小修复 ≠ AI 策略完成

> **更新：2026-11-20。** 当前工作以 [`oha-next`](https://github.com/littleredcap/dota2bot-OpenHyperAI/tree/oha-next) 为稳定基线。表中引用的功能修复均在**未合并的独立 PR**，离线 CI 通过不等于 7.42 客户端实测，局部正确性也不等于 AI 实战强度提高。
>
> 对应：[总需求 U/D/F](OHA_NEXT_REQUIREMENTS.md) · [客户端 VT 台账](CLIENT_VALIDATION_BACKLOG.md) · [策略 R/I/W](GAMEPLAY_STRATEGY_CATALOG.md) · [7.42 英雄静态矩阵（PR #15）](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/audit/patch742-hero-matrix/docs/PATCH_7_42_HERO_MATRIX.md)。

## 1. 设计原则

同一个问题必须**分别回答**：

1. **实现状态（Implementation）**：已经理解并提出局部正确性修复，还是实现了新策略？是否已合并？
2. **验证状态（Verification）**：只有源码分析、生产代码的 Mock/CI，还是实际客户端验证及公平比赛收益？
3. **策略成熟度（Strategy）**：只沿用旧施法时机、对少数条件作保护，还是完整考虑机会成本、反例、连招和战术收益？
4. **后续工作**：即使最小修复“完成”，也必须列出尚未实现的新版主动、施放时机或策略优化，不得靠一个 `fixed` 标签掩盖。

### 1.1 状态码（人工可读、单一含义）

| 维度 | 状态码 | 精确含义 |
| --- | --- | --- |
| 实现 | `REPORTED` | 只有用户/上游报告，未确认现有代码必然有 Bug |
| 实现 | `SCOPED` | 已缩小至具体源码或能力缺口，还没有对应的最小修复 PR |
| 实现 | `MIN_FIX_DRAFT` | 已提交**最小修复**的独立 PR，未合并；只声明改动范围 |
| 实现 | `EXP_DRAFT` | 实验性新行为，仍 Draft，可能默认关闭 |
| 实现 | `INFRA_DRAFT` | 工具、诊断和测试能力的 PR，不能冒充游戏策略完善 |
| 实现 | `DOC_DRAFT` | 文档/审计方案的 PR，不代表游戏代码变更或用户已经得到功能 |
| 实现 | `DEFERRED` | 已记录、暂缓研发；不要因有文档就声称实现 |
| 实现 | `MERGED` / `REVERTED` | 将来有 GitHub 合并或回退证据时才使用；本次无此类 |
| 验证 | `NO_RUN` | 未执行受控测试 |
| 验证 | `STATIC_ONLY` | 只有静态/代码证据，没有可执行的通过结果 |
| 验证 | `OFFLINE_PASS` | 对应 PR 的 Lua 5.1 / Python Mock/CI 通过，**客户端尚未验证** |
| 验证 | `CLIENT_PASS` / `MATCH_PASS` | 将来分别要求真实 Dota 行为证据/公平多场表现；本次无此类 |
| 策略 | `OLD` | 只修正确认失效的逻辑，原其他 `Consider/SkillsComplement` 施法条件沿用，并未证明最优 |
| 策略 | `PARTIAL` | 增加局部意图/安全阈值，尚有明显反例或收益优化债务 |
| 策略 | `TODO` | 新技能、机会成本或战术策略尚未实现 |
| 策略 | `RESEARCH` | 需要先查证或复现，不能凭猜测实施 |
| 策略 | `N_A` | 文档、安装、测试工具等不直接涉及 AI 施法策略 |
| 策略 | `STRATEGY_VALIDATED` | 将来需要实机时序、负例和有效公平对照证据才能使用；本次无此类 |

**重要：** `MIN_FIX_DRAFT + OFFLINE_PASS + OLD` 的含义是“局部适配补丁准备好并通过离线回归；原技能释放时机未优化”，**不是**“英雄已适配完毕”，也**不是**“AI 变强”。即便后来 PR 变成 `MERGED`，策略栏也必须独立保留 `OLD/PARTIAL/TODO`，直到新的测试证据充分。

**证据等级 E0～E4** 继续沿用 [需求总表](OHA_NEXT_REQUIREMENTS.md)；此处的验证列记录**实现候选经过何种测试**，不取代缺陷的 E2 静态证据或 E4 客户端复现证据。

## 2. 已报告或已发现的具体上游 Issue

| 稳定 ID | 具体问题/需求 | 实现 | 验证 | 策略 | 已做的最小范围 | 后续未完成的行为/验收 | 关联 PR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GH-155 | 物品丢下又捡回（[上游 #155](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/155)） | MIN_FIX_DRAFT | OFFLINE_PASS | OLD | 追踪主动丢弃物品，防止同一物品被通用拾取逻辑反复拾回。 | 检查跨脚本物品句柄共享、满背包、莲花及合法队友递送；后续仍可优化背包价值/出售时机。 | [PR #7](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/7) |
| GH-159 | 敌方多人死亡仍刷野不推进（[上游 #159](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/159)） | MIN_FIX_DRAFT | OFFLINE_PASS | PARTIAL | 补充人数优势推进窗口、兵线/队友与基地威胁保护；保留原推线模式。 | 需要判断推进路线、敌方买活风险、实际集结/拆塔效果与撤退时机；T2/T3 待验证。 | [PR #11](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/11)、[PR #13](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/13) |
| GH-170 | OD/暗影恶魔/风杖放逐误救敌人（[上游 #170](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/170)） | MIN_FIX_DRAFT | OFFLINE_PASS | PARTIAL | 按可见队友攻击、追击/保人意图区分阻止部分敌方放逐。 | 未覆盖所有弹道、大招落点、未来伤害、控制衔接；需评估不能误拦截留人与救援。 | [PR #10](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/10)、[PR #13](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/13) |
| GH-176 | 小兵偷家、Ancient/T4 防守优先级低（[上游 #176](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/176)） | MIN_FIX_DRAFT | OFFLINE_PASS | PARTIAL | 只为可见、实际攻击基地建筑的小兵威胁分配有限防守者。 | 仍需真实 TP 可达性、步行路径、选择可参战者、与其它路守塔/推进协调和严重基地压力回归。 | [PR #9](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/9)、[PR #13](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/13) |
| GH-171 | 重复购买魔棒等不可叠加物品（[上游 #171](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/171)） | REPORTED | STATIC_ONLY | RESEARCH | 已知购买状态机有持有计数、已有组件与重建队列判断，未提交修复。 | 先复现物品购买 vs 组件合成、信使/背包、换位/换英雄情形，避免一刀切禁止合法合成。 | — |
| GH-172 | Linux 安装/模块大小写错误（[上游 #172](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/172)） | SCOPED | STATIC_ONLY | N_A | 定位安装脚本 sudo 后用 HOME 读取 Steam，且 VScript 大小写敏感。 | 独立修复用户路径/权限和 Lua require 路径，提供临时目录测试；未实机验证。 | — |
| GH-169 | Flatpak Steam 无 .OHA 名称（[上游 #169](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/169)） | REPORTED | STATIC_ONLY | N_A | 记录用户报告的 Flatpak Steam 安装路径差异。 | 适配安全路径检测并与 Linux #172 联合回归；需 Flatpak 实测。 | — |
| GH-160 | 选人按人类站位错误匹配角色（[上游 #160](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/160)） | REPORTED | NO_RUN | RESEARCH | 已登记问题，尚未定位确定性源码根因。 | 审查选人、分路、交换位置与角色计算；再根据可复现 Mock 单独修复。 | — |
| GH-167 | FretBots 3/4 号位对线和守家短暂停滞（[上游 #167](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/167)） | REPORTED | NO_RUN | RESEARCH | 外部报告；与 #176 的小兵偷家不是同一已证实根因。 | 需锁定模式 GetDesire/Think 时序与无后续指令路径后做局部回归。 | — |
| GH-164 | 分推/肉山信号/分散行动等（[上游 #164](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/164)） | REPORTED | NO_RUN | RESEARCH | 泛化的战术观察；不按一条宽泛 Issue 直接重写 AI。 | 拆解成可复现的分推、组队、Ping 响应场景并分别登记。 | — |
| GH-139 | 辅助与核心抢补刀（[上游 #139](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/139)） | REPORTED | NO_RUN | RESEARCH | 外部场景报告，尚无可归因的局部修复。 | 按 pos、血量阈值、队友补刀意图做正反例；不能禁止辅助所有补刀。 | — |
| GH-145 | 友方 Bot 团战前离开（[上游 #145](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/145)） | REPORTED | NO_RUN | RESEARCH | 外部报告，尚未证明具体撤退模式规则错误。 | 结合生命/危险评估、模式抢占和目标重选做场景回归。 | — |
| GH-090 | TP 后又步行返回原路（[上游 #90](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/90)） | REPORTED | STATIC_ONLY | RESEARCH | 已有目标/模式往返的静态调查背景，未声称整体根因解决。 | 按目标失效、回城刚结束、队友支援和冷却做状态转换复现。 | — |
| GH-122 | 辅助插眼和抱团行为（[上游 #122](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/122)） | REPORTED | NO_RUN | RESEARCH | 外部复合需求，尚未实施。 | 区分买眼、使用时机、位置选择和实际团队目标价值。 | — |
| GH-156 | 后期升级飞鞋 2 的提议（[上游 #156](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/156)） | REPORTED | NO_RUN | TODO | 需求候选而非已确认 Bug；无新出装规则。 | 核验 7.42 装备合法性、模式及已持有 Guardian Greaves/Bearing 例外后研究。 | — |
| GH-151 | Demo 模式 Bot 购买行为（[上游 #151](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/151)） | REPORTED | NO_RUN | RESEARCH | 用户报告，目前未修复。 | 需先确定 Demo 环境是否应跳过购物，再创建场景回归。 | — |
| GH-137 | 综合 Bot 行为/Turbo 异常（[上游 #137](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/137)） | REPORTED | NO_RUN | RESEARCH | 综合性描述并非单一可测试缺陷。 | 拆分单点追击、Roshan 路径、敌方站位等有具体症状的问题。 | — |
| GH-105 | 装备与支援决策综合反馈（[上游 #105](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/105)） | REPORTED | NO_RUN | RESEARCH | 外部综合反馈，现阶段不推断单一根因。 | 按角色/战术场景拆分后续具体问题。 | — |

## 3. Dota 7.42 明确兼容问题和新版能力缺口

| 稳定 ID | 具体问题/需求 | 实现 | 验证 | 策略 | 已做的最小范围 | 后续未完成的行为/验收 | 关联 PR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C742-01 | Meepo MegaMeepo 删除与 Dig 调整 | MIN_FIX_DRAFT | OFFLINE_PASS | TODO | 移除旧 MegaMeepo 调用、增加 Dig 条件安全处理。 | 新 Dig / Shard 技能时机、拾起与 Fling 仍需实机；见 VT-001～005。 | [PR #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) |
| C742-SHARD | Meepo 新 Shard 拾取 / Fling | EXP_DRAFT | OFFLINE_PASS | TODO | 原型受开关保护，默认关闭并移除未经验证的默认早购。 | 需评估小兵兵线价值、携带缴械与共享伤害、时序和中断后动作。 | [PR #5](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5)、[PR #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) |
| C742-02 | 兽王/狼人旧 Helm of the Overlord 出装 | MIN_FIX_DRAFT | OFFLINE_PASS | OLD | 移除已被删除的装备购买路径与公共配方引用。 | 不等于已为各位置选择了新版本最优装备；需要真实购买链路测试。 | [PR #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) |
| C742-03 | FretBots 中立物品五阶配置 | SCOPED | STATIC_ONLY | RESEARCH | 已定位增强模式的旧阶数与时间表，无默认游戏修复。 | 核对四阶新候选、真实内部 ID、增强模式是否刻意保留独立规则。 | [PR #3](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3)、[PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| C742-04 | Buff 增强模式旧中立装备池 | SCOPED | STATIC_ONLY | RESEARCH | 识别已轮出物品和五阶发放规则。 | 与标准模式分开核实 CreateItem、非公平增强开关和回退。 | [PR #3](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3)、[PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| C742-05 | Roshan 7.42 递减复活窗口 | MIN_FIX_DRAFT | OFFLINE_PASS | PARTIAL | 保守修订已观察击杀数对应最晚复活估计，避免旧固定时间一刀切。 | 需要真正目标可见性、第一次 / 多次击杀、Turbo、队友协调和争盾策略。 | [PR #6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) |
| C742-06 | Leshrac Nihilism 失去自虚无 | MIN_FIX_DRAFT | OFFLINE_PASS | OLD | 删除基于旧自虚无的弹道保命触发，保留谨慎的近身防守。 | 需评估持续驱散、敌方缴械、队友控制冲突、Scepter 有无及施法时机。 | [PR #8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8) |
| C742-07 | 先知 Oldgrowth 从主动改被动 | MIN_FIX_DRAFT | OFFLINE_PASS | OLD | 移除错误的主动 Cast 和 Consider；保留其他主动技能原本的时机。 | 新被动的触发与与 Sprout / Nature's Call 的协同未独立优化；见 VT-020。 | [PR #16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16) |
| C742-08 | 亚巴顿 Mist Coil / Shard / Scepter 重做 | MIN_FIX_DRAFT | OFFLINE_PASS | OLD | 移除旧纯粹伤害与攻击伤害计算、无用 self_damage 字段读取。 | 仍需判断生命消耗下的安全施法阈值、神杖 AoE、护盾与新效果的最佳时机；VT-022。 | [PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) |
| C742-09 | 混沌骑士 Ahead, Armageddon 主动 | SCOPED | OFFLINE_PASS | TODO | 已确认新技能 ID/槽位并测试原 Q/W/R 索引，未加入新主动动作。 | 先核实幻象可用性、地点、施法打断和与 Q/W/R 的控制链，设计新 Consider；VT-023。 | [PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) |
| C742-10 | Chen Zealot 与 Holy Persuasion 召回 | MIN_FIX_DRAFT | OFFLINE_PASS | TODO | 移除失效 Summon Convert 句柄、Consider 与施法，保持 Hand/Penitence/Holy/Favor 原顺序。 | Zealot 的主动复活与自施法召回未实现；需确认目标标记、范围、时机及与原招野冲突；VT-021。 | [PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) |
| C742-11 | 兽王新神杖 Ancient Thunderhide | SCOPED | STATIC_ONLY | TODO | 已发现新召唤能力尚未写入英雄逻辑。 | 需核实内部 ID 与召唤目标/控制、与原野兽技能和团队任务的协同。 | [PR #3](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3)、[PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| C742-13 | Javelin 7.42 移除 | MIN_FIX_DRAFT | OFFLINE_PASS | N_A | 从公共 sBasicItems 移除旧 item_javelin 分类。 | 仍需核验新配方/新版购物数据和真实库存；不等于全英雄物品适配完成；VT-024。 | [PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) |
| C742-14 | Overlord 通用主动逻辑残留 | SCOPED | STATIC_ONLY | N_A | 确认 ability_item_usage_generic.lua 仍有已移除装备 Consider 路径。 | 核对不可达性后清理，保留 Dominator 合法主动；与 #4 联合测试。 | [PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| C742-ALL | 7.42 全部英雄与共用系统兼容覆盖 | DOC_DRAFT | OFFLINE_PASS | RESEARCH | 建立 128 个英雄 Lua 文件清单和特定风险指纹，不等于逐英雄认证。 | 其余英雄/天赋/被动/物品/地图仍需逐条比对官方变化，之后按风险小 PR 修复。 | [PR #3](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3)、[PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |

## 4. 工程基础、质量规范与测评需求

| 稳定 ID | 具体问题/需求 | 实现 | 验证 | 策略 | 已做的最小范围 | 后续未完成的行为/验收 | 关联 PR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ENG-ROAM | Team Roam 目标锁定与 Roshan DPS | MIN_FIX_DRAFT | OFFLINE_PASS | PARTIAL | 保持原模式框架，修复锁定退出与 DPS 估计的局部逻辑。 | 真实目标切换/可达队友/下令与受控场景待验证，不能称团队策略优化完成。 | [PR #1](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) |
| ENG-REQ | OHA-Next 架构、需求、客户端测试登记 | DOC_DRAFT | STATIC_ONLY | N_A | 建立 U/D/F/VT 文档与版本来源及验收边界。 | 本登记表新增所有具体问题的修复/验证/策略三维跟踪；文档 PR 尚未合并。 | [PR #2](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/2) |
| ENG-DQ1 | 技能状态与决策原因诊断 | INFRA_DRAFT | OFFLINE_PASS | N_A | 默认关闭的技能/物品状态采样、部分 BLOCK/ALLOW 和离线日志分析。 | 不是全英雄有效施法机会证明；待扩展动作执行结果和客户端可靠采集。 | [PR #12](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/12) |
| ENG-JOINT | #159/#170/#176 联合模式回归 | INFRA_DRAFT | OFFLINE_PASS | N_A | 70 项离线跨模块与日志测试（历史 CI），不替代三项独立修复。 | 需求变化后持续跑联合场景；真实 Dota 模式竞争仍未验证。 | [PR #13](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/13) |
| ENG-METRICS | 多场对局表现评估、DotaMax 指标参考 | INFRA_DRAFT | OFFLINE_PASS | N_A | 支持手工 JSON / 已知 OpenDota 比赛导入及英雄/版本/位置表现比较。 | Local Host 真实数据自动采集暂停；未积累真实 OHA 数据，尚无强度结论。 | [PR #14](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/14) |
| ENG-PATCH-MATRIX | 7.42 静态风险矩阵与离线错误分析 | INFRA_DRAFT | OFFLINE_PASS | N_A | 128 个 hero Lua 目录盘点、E1/E2 指纹与现有日志分类。 | UNREVIEWED ≠ 兼容；无人值守客户端自动对局仍是未来方案。 | [PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| ENG-PATCH742-JOINT | 7.42 最小修复的组合测试与本地使用包 | INFRA_DRAFT | OFFLINE_PASS | N_A | 合并 PR #4/#6/#8/#16/#17 的变更快照，同时保留 Overlord/Javelin 清理；44 个原有场景和 5 个联合断言通过，打包 Local Dev Script ZIP。 | 仍需按 VT-025 验证客户端确实加载该集成 SHA、选人/技能/购买正常；不能标记全英雄适配或策略收益；本集成 Draft 不直接合并。 | [PR #18](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/18) |
| ENG-CLIENT | 无需人工盯屏的客户端自动验证 | DEFERRED | NO_RUN | N_A | 已有日志分类与方案文档，暂未自动启动 Dota。 | 待真正客户端/独立运行环境可用，再验证执行结果、持续停滞和可观察性。 | [PR #12](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/12)、[PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| ENG-REGISTER | 每项最小修复与未来策略债务独立跟踪 | DOC_DRAFT | STATIC_ONLY | N_A | 本文件集中列出已发现的具体问题、PR、离线验证、策略边界。 | 以后发现新问题即加稳定 ID；最小修复合并不能自动标成策略完成。 | [PR #2](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/2) |
| U-14 | 用户明确要求每项 Issue/需求记录「最小修复 vs 未来策略」 | DOC_DRAFT | STATIC_ONLY | N_A | 已建立三轴台账、稳定 ID、具体修复与未来施法时机债务。 | 随后每个新 Issue/需求先登记，再在具体 PR 及验证后分别更新；旧项目不因最小修复而关闭。 | [PR #2](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/2)、[PR #12](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/12) |
| D-23 | PR 状态门禁与最小修复策略债务验证 | INFRA_DRAFT | OFFLINE_PASS | N_A | Python 检查稳定 ID、状态合法性、PR 关联、未完成后续工作；PR 模板列三轴。 | 当前 PR 合并状态需按 GitHub 单独核对；未来 PR 应更新台账，不准仅因 CI 通过就标 CLIENT_PASS/STRATEGY_VALIDATED。 | [PR #2](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/2)、[PR #12](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/12) |

## 5. 游戏策略功能需求 F-01～F-11（与需求总表保持同一 ID）

| 稳定 ID | 具体问题/需求 | 实现 | 验证 | 策略 | 已做的最小范围 | 后续未完成的行为/验收 | 关联 PR |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F-01 | 7.42 兼容总体需求 | SCOPED | OFFLINE_PASS | RESEARCH | 多个独立小 PR 修复部分结构问题，矩阵中仍有大量未核验英雄。 | 按英雄/技能/物品/模式逐条验收；实机后才能谈整体兼容。 | [PR #3](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/3)、[PR #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)、[PR #6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6)、[PR #8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8)、[PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15)、[PR #16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16)、[PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) |
| F-02 | 英雄技能与物品使用 | SCOPED | OFFLINE_PASS | RESEARCH | #170 / 7.42 各项提供局部示例，并未改进所有英雄决策。 | 按每个英雄的合法性、机会成本、反例、连招与冷却做逐项审查。 | [PR #10](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/10)、[PR #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) |
| F-03 | 基础行为/无效停滞 | SCOPED | OFFLINE_PASS | RESEARCH | #155 有局部物品循环修复；其他停滞现象未证实根因。 | 待确定模式竞争、TP 往返、无后续行动的可观察场景。 | [PR #7](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/7) |
| F-04 | 对线、刷野与资源分配 | REPORTED | NO_RUN | TODO | 保留策略图谱；尚未针对抢刀 / 让经济实现新策略。 | 核心与辅助的补刀、支援机会成本、兵线经济需要独立回归。 | — |
| F-05 | 团战集火、留人、撤退 | SCOPED | OFFLINE_PASS | PARTIAL | OD/SD/Eul 等局部放逐冲突已提出防护。 | 预测队友弹道/技能伤害、目标切换与连招收益；不能全靠人数阈值。 | [PR #10](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/10)、[PR #1](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) |
| F-06 | 推进/防守/胜势终结 | SCOPED | OFFLINE_PASS | PARTIAL | #159 与 #176 各自有限条件修复及联合回归。 | 真实兵线/买活未知性、时间窗、队伍分工、守家与推进竞争。 | [PR #9](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/9)、[PR #11](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/11)、[PR #13](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/13) |
| F-07 | Roshan、Tormentor 与目标决策 | SCOPED | OFFLINE_PASS | PARTIAL | Roshan DPS 和复活上界有小修复。 | 控盾/争盾/侦察/换塔/让盾时机和 Tormentor 新规则未完善。 | [PR #1](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1)、[PR #6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) |
| F-08 | 选角、定位与针对性出装 | REPORTED | NO_RUN | TODO | 已有正常选角与装备代码，但未按该功能作新版本策略验收。 | 按英雄角色/对手阵容及可用主动能力调优；不重复买不合适道具。 | — |
| F-09 | 英雄/模式覆盖扩大 | SCOPED | STATIC_ONLY | RESEARCH | 7.42 静态矩阵明确标明未审查英雄。 | 逐个英雄核对技能/天赋/模式，不按文件存在判断支持程度。 | [PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) |
| F-10 | 敌方 Roshan 争夺或换目标 | DEFERRED | NO_RUN | TODO | 研究需求，尚无新策略代码。 | 基于合法可见证据区分确证/怀疑；决定集结、抢盾、换塔或守家。 | — |
| F-11 | 整局策略与成熟打法引入 | DEFERRED | NO_RUN | TODO | 已有阶段性策略目录，当前优先局部正确性与 7.42。 | 按攻略成熟度 R、实现覆盖 I、真实收益 W 分开验证，择优实施。 | [PR #2](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/2) |


## 6. 新发现 / 修复 / 关闭流程（强制）

1. **先登记**：发现新的 Issue、补丁变更、需求或源码反例后，新增一个稳定 ID；给出来源、具体场景、已知证据等级、影响模块和 `REPORTED` / `SCOPED`。泛化症状要拆成可验证的个案，不能一键标记修复。
2. **再提交 PR**：实际修改只能更新对应行的实现状态和**最小改动范围**；每个 PR 应在描述中引用本台账的稳定 ID，明确“我改了原有施法时机、沿用旧施法时机、还是新写策略”，且写出至少一个**合法反例**。
3. **测试更新验证，不更新策略**：CI pass 只能升至 `OFFLINE_PASS`；真实客户端测试必须有 Dota build、OHA commit、实际执行证据、场景和 VT 编号；胜率结论必须进一步有合理对照与样本量。
4. **最小修复合并后**：只有 GitHub 合并证据才能标 `MERGED`，**仍保留 `OLD/PARTIAL/TODO`**。不得删掉后续策略工作；只有对应能力研究完成，另起策略 PR 并有足够证据后才能更新策略状态。
5. **补丁变化 / 复现推翻**：旧证据失效时降级回 `SCOPED` 或 `RESEARCH` 并写明原因；保留历史关联和失效条件，不覆盖历史补丁版本。
6. **记录冲突与依赖**：如 #4/#17 都修改公共物品库，应在 PR 中记录交集和联合回归，不通过一个所谓“大一统修复”抹平独立问题状态。
7. **不要求用户盯屏**：目前先做静态、离线 Mock 和可收集日志；需要实机时登记 VT，后续采用真实的自动采集和异常片段审查，不把没有日志当成“行为正常”。

### 今后每个条目的标准格式

```yaml
id: GH-000 / C742-00 / F-00 / ENG-...
source: 官方补丁/上游 Issue/用户需求/本项目源码
observed_symptom_or_requirement: 具体触发情况，不混入尚未实现的目标
evidence_level: E0/E1/E2/E3/E4
implementation_status: REPORTED/SCOPED/MIN_FIX_DRAFT/...
verification_status: NO_RUN/STATIC_ONLY/OFFLINE_PASS/...
strategy_status: OLD/PARTIAL/TODO/RESEARCH/N_A/STRATEGY_VALIDATED
minimum_change: 实际代码改了哪些判断和施法动作
retained_logic: 哪些旧 Consider / SkillsComplement / 购买流程保持不变
unimplemented_strategy: 新主动、释放时机、技能连招、资源与战术收益
positive_and_negative_cases: 必须允许与必须阻止的场景
links: PR、源码、CI、VT、客户端证据
next_gate: 下一步需要什么证据才可进入新的状态
```

### 旧文档如何理解

[OHA_NEXT_REQUIREMENTS.md](OHA_NEXT_REQUIREMENTS.md) 按 U/D/F 类型定义**需求范围与验收**，其历史“当前状态”文字可能来自之前的 PR 快照；**本台账是具体 Issue / 小 PR 最新实施、验证和策略成熟度的统一索引**。[CLIENT_VALIDATION_BACKLOG.md](CLIENT_VALIDATION_BACKLOG.md) 继续记录真实客户端的场景债务；[GAMEPLAY_STRATEGY_CATALOG.md](GAMEPLAY_STRATEGY_CATALOG.md) 的 R/I/W 继续用于大范围策略成熟度，不可从本台账推导为 R3/I3/W2。
