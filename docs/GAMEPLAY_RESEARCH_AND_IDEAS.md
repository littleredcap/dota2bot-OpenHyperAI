# OHA-Next：社区机制研究与高胜率策略候选

> 2026-11-19 建立。用户提出：AI 判断不能只看技能是否可用；希望我们主动从高手攻略、补丁、职业比赛思路、社区讨论中**发现用户未必主动提到的策略机会**。  
> **属性：研究/需求候选，不是已证实 Bug、已实现算法、已实测收益或监控系统。**  
> 关联：[强度目标 A](OHA_NEXT_STRENGTH_OBJECTIVE.md) · [需求与 F 类](OHA_NEXT_REQUIREMENTS.md) · [客户端待验证项](CLIENT_VALIDATION_BACKLOG.md)  
> 当前不自动后台抓取社区，不启动客户端对局/故障监控；研究在用户请求、新补丁或关联 PR 开发时主动执行。

## 1. 我们到底要研究什么

产品目标是公平条件下更高的实际获胜能力，而非只提高补刀、命中率、GPM 或让 Bot 更忙。

对于任何策略都必须区分四层证据：

1. **规则事实**：Valve 新补丁、可追溯的客户端 KV/API；例如 7.42 的 Meepo Shard 拾取/投掷与携带缴械。
2. **社区经验**：玩家讨论、教练/教学视频、职业局思路；通常是条件性的**战术观点**，不是最佳策略定理。要核对日期/版本，辨别个人意见、样本与证据。
3. **工程假设**：明确 Bot 能合法读到哪些状态，推导优劣与失败反例，参考现有源码；未证明原仓库有 Bug 时标为 E0/E1。
4. **效果验证**：先局部复现、负例测试，再用公平对局比较是否真正更容易赢。没有实战验证不得宣称更强。

禁止把职业观战中的全图信息、赛后录像真值直接输入游戏内 Bot；**侦察、视野和推断**必须受局内合法信息限制。

## 2. 实例一：Meepo 7.42 魔晶的判断不是“有兵有敌就扔”

### 2.1 社区与版本证据

- [Valve 7.42](https://www.dota2.com/patches/7.42)：魔晶改为 Divided We Stand 拾取友方 Meepo 或小兵，再 Fling；携带者被缴械，被携带 Meepo 共享伤害，5 秒后掉下；技能范围和等级效果详见官方页。
- [Client 6983 Meepo KV](https://github.com/dotabuff/d2vpkr/blob/281a3058165bfe46681a657aaed8f5015eaac6b4/dota/scripts/npc/heroes/npc_dota_hero_meepo.txt)：`meepo_divided_we_stand` 与 `meepo_fling_release`；**前者在 KV 仍标记 PASSIVE**，所以 Lua Bot API 的真实施放行为必须客户端确认，不能凭 Mock 判定成功。
- [2026-11-19 Reddit 玩家讨论](https://www.reddit.com/r/DotA2/comments/1xzu6en/meepo_players_what_are_we_thinking/)：早期玩家提到救援、连环搬运可能性，也有人觉得新操作繁琐、不实用；意见冲突，**样本不足**，不能当作通用最优连招。
- [2026-08 Meepo 强势期讨论](https://www.reddit.com/r/TrueDoTA2/comments/1vmq6g4/to_all_the_meepo_spammers_whats_your_exact_game/)：可研究 Poof、Blink、多分身发育与强势期的收益，但文章在 7.42 前，不能直接套旧魔晶行为。

### 2.2 建议的决策层（未实现；参数需要校准）

**第一层：动作合法性（硬约束）**：确实持有 Shard，Bot 能识别主动技能及其施法行为；载体合法、在范围；敌人有合法可用的视野；无引导/动作队列重大冲突。无证据证明接口可施放时不自动发布“已实现”结论。

**第二层：预期收益**：杀敌/确保击杀、可靠减速和控制衔接、保护濒危单位、撤离风险、压制敌方撤退线路等。只因“附近有敌方英雄”不足以认定收益。若敌人容易离开投掷范围，应降低收益或不拾起。

**第三层：机会成本**：
- 拾起普通近战/远程小兵可能损失兵线控制、补刀/反补价值、对塔/英雄输出，甚至送给敌人不同的击杀/反补窗口；**不能因为已过对线期就永久忽略兵线价值**。
- 携带者暂时无法普攻，可能打断更优的 Poof/Earthbind/右键输出与撤退；被拾起的是另一个 Meepo 时共享伤害会增加全队 Meepo 死亡风险。
- 耗蓝、冷却、行动打断、5 秒持有上限、丢失敌人视野时如何安全结束携带，均应进入成本或硬约束。

**第四层：保守失败与战术回退**：目标失效、Fling 不可用、可用友方小兵已死、携带者被控制或拾取失败时，不能无限排队重试。确认资源价值和战斗收益足够明显前，优先选择原本 Poof/Net/移动/攻击行动。

一个**待测试的决策模板**（不是现在的实装，也没有硬编码魔法权重）：

```text
if Shard API or cast semantics not verified -> experimental, do not declare ready
if no legal pickup unit OR no safe action sequence -> no cast
benefit = estimated kill/save/control/position value * ability-to-hit confidence
cost = carried creep's lane/resource value
     + carrier disarm / forfeited attack and spell opportunity
     + shared-damage and death risk
     + lost mobility, mana, cooldown and failure risk
only consider cast if benefit clearly exceeds cost AND no better action dominates
on pickup: re-check target/vision/position; fling or choose verified safe fallback
```

**用户提出的反例（必须保留）：** 友方远程兵即将成为对手可反补目标，虽然有敌方英雄进入投掷范围，但拾起/扔出这个兵可能破坏更有价值的兵线行动。应比较边际收益；也要测试拿着兵被缴械后不能继续有效输出的反例。该例很少出现也不等于可以忽略其一般化逻辑——Bot 不应为了让技能触发而忽略机会成本。

### 2.3 对 [Draft PR #5](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/5) 的现状复核

当前实现的 `ConsiderShardPickup()`：
- 已有基本合法性过滤、`GetNearbyCreeps()` 中的普通友方小兵限定、敌方可见目标和若干技能/模式守卫；
- **没有**对己方近战/远程/旗帜兵的战术价值、敌方反补机会、兵线压力、携带期间被缴械、目标离开后的处置作决策比较；
- **没有**验证 `meepo_divided_we_stand`（KV: PASSIVE）在 Bot API 下是否可施放；7 个 Mock 只是由模拟对象按照预期响应；
- **不能**依据 13 个离线回归通过就宣布“好用、值得启用、提高胜率”。

因此 #5 继续 Draft；在验证动作链并补足最低限度机会成本规则前，**不建议开启为公平强度的默认稳定行为**。先把 [VT-001～VT-004](CLIENT_VALIDATION_BACKLOG.md) 标为 release gate。完善策略后新增独立的局部负面场景用例。

## 3. 实例二：敌人打 Roshan，AI 要不要过去抢？

**这不是单一的“GetDesire 高一点就五人往坑走”。** 需要从“是否知道敌人正在打”“能不能赶到”“抢下来的价值”“可能因此丢什么”四层决策。把“知道敌人打盾”与“敌人多人失踪、怀疑在打盾”分开，否则会靠作弊信息或误判浪费集结。

社区来源（原则参考，需按 7.42 地图/时间重核）：  
[Dotacoach Roshan 文章](https://dotacoach.gg/en/articles/roshan) 提到视野、排眼、分工站位、强杀时主动退出；  
[TrueDoTA2：什么时候打 Roshan](https://www.reddit.com/r/TrueDoTA2/comments/cazd1z) 强调兵线和双方英雄位置；  
[TrueDoTA2：高地破路后是否争盾](https://www.reddit.com/r/TrueDoTA2/comments/wfwsoo) 讨论“错误抢盾后可能直接输比赛”；  
[2025 Reddit：拿盾后是否立刻推高](https://www.reddit.com/r/learndota2/comments/1i7cv6p) 倾向先处理兵线、视野和装备冷却，再转化为建筑优势；  
[7.42 官方补丁](https://www.dota2.com/patches/7.42) 调整了 Roshan 复活基础时间，旧年份的固定时间规则不再照搬。

### 3.1 建议的决策状态

| 步骤 | 可用的合法信息（需要具体 API/日志核验） | 决策问题 |
| --- | --- | --- |
| 观察可信度 | 己方视野内敌方/肉山、最后见到敌人位置、合法探测/队友信号、已知 Roshan 击杀时间 | **确证 vs 猜测**；没有视野不能直接认为 Roshan 的 HP/敌人位置已知 |
| 时间与机动 | 队友及敌人的存活/复活、TP/位移和到场时间、坑内可视血量与己方能打断的技能 | 到达时 Roshan 是否可能已死？进坑还有胜机吗？ |
| 战斗资源 | 队伍 HP/MP、关键大招/控制、存活人数、阵容强弱、地形/视野优势、己方能否买活 | 争盾能不能赢团，而不是能不能撞进坑？ |
| 其他代价 | 兵线、边路塔、己方高地、可交换建筑、撤退路线 | 不过去是否有更好的拆塔/带线/守家收益？ |
| 事件反馈 | 观察到的敌方撤退/新支援/我方减员/信息失效 | 什么时候必须取消集结或改为带线？ |

### 3.2 行动不是二选一

| 输出行动 | 例子 | 失败保护 |
| --- | --- | --- |
| `contest_teamfight`（集结打团） | 兵线健康、关键团战技能齐、己方能快速入场，并有胜算 | 队友无法同步到场、己方关键资源失效、坑视野丢失则重新评估 |
| `steal_only`（小队/单人抢） | 核心阵容不适合 5v5，但存在合法技能/视野机会抢 Roshan 最后击杀或 Aegis | 不牺牲无买活核心；不能把未知 Roshan 血量当精确值 |
| `scout_or_delay`（侦察拖延） | 敌人多人失踪，怀疑打盾但无法确认 | 利用合法侦察/投射物开视野；侦察不等于必须全队进坑 |
| `trade_objective`（换资源） | 争夺胜算很低，但边路兵线可推进、可拆塔/夺取其它资源 | 计算逼近基地的风险、不能为了换小塔送掉远古 |
| `defend_or_reset`（守家/恢复） | 己方两路高地有危险，强行离家争盾失败会直接输 | 守家集结，等大招/复活/下次机会 |

这属于 [F-07](OHA_NEXT_REQUIREMENTS.md) 的扩展候选 **F-10**；目前尚未证明 OHA-Next 缺失全部这些行为。先审查其现有 `mode_roshan_generic.lua`、团队游走/防守模式后再立实现 PR。客户端场景登记 [VT-012](CLIENT_VALIDATION_BACKLOG.md)。

## 4. 本次从补丁与社区挖掘的更多候选（等待审查）

这些是**会影响胜率的研究方向**，优先级只是工程建议，绝非“已证实 Bot 有 Bug”。

| 候选 | 为什么值得研究 | 第一步应核查什么 | 来源 |
| --- | --- | --- | --- |
| IDEA-001 / P1 | 敌方 Roshan 的确证/怀疑、争团/抢盾/换资源/守家 | 现有团队决策里是否已覆盖，是否能合法获取线索 | 第 3 节的 Dotacoach、TrueDoTA2 |
| IDEA-002 / P1 | **7.42 Tormentor 新物品 Greater Horn of Battle** 可召唤三路线 Mega creeps，产生新的“拿 Tormentor → 同时推线/逼防守 → 转其他目标”策略可能 | 新物品 API 与目标选择，何时使用才不会白白送掉兵线价值 | [Valve 7.42](https://www.dota2.com/patches/7.42) |
| IDEA-003 / P1 | 7.42 Roshan 基础复活时间递减，可能提高反复控盾和围绕时间窗作视野/集结的价值 | 当前 Roshan 生死启发式、实际位置、与队伍目标的协调；区分时间估计与确定视野 | [Valve 7.42](https://www.dota2.com/patches/7.42)、[Draft PR #6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) |
| IDEA-004 / P1 | **拿到 Aegis 后的目标转换**：先修线还是直接推塔，哪些技能/买活条件允许上高 | 现有拿盾后团战/推进模式、兵线状态和关键冷却判断 | [Reddit 2025](https://www.reddit.com/r/learndota2/comments/1i7cv6p) |
| IDEA-005 / P2 | 7.42 双子门和中路地形变化，旧的支援/绕后路线可能低效，且新路径可能提供更好先手机会 | 静态地图坐标 vs `GetNeutralSpawners()` 等动态地图查询，TP/移动路径与可达性 | [Valve 7.42](https://www.dota2.com/patches/7.42) |
| IDEA-006 / P2 | 7.42 **Item Potency** 影响部分法球/幻象物品效果，可能改变英雄装备和目标优先级 | 哪些现有角色/幻象英雄的物品假设不再成立，需结合客户端数据 | [Valve 7.42](https://www.dota2.com/patches/7.42) |
| IDEA-007 / P2 | 7.42 Glyph 改动使逼出防御技能、分路消耗和推进时间窗值得重新计算 | 当前推塔/守塔模式是否读取 Glyph 状态，哪些数据对 Bot 可合法观察 | [Valve 7.42](https://www.dota2.com/patches/7.42) |
| IDEA-008 / P2 | **Meepo 新 XP 惩罚机制**：分身在最近 5 秒里分别获得经验会影响经验效率，或改变“分开刷/一起刷”的最优策略 | 目前 `hero_meepo.lua` / `MinionThink` 对多分身发育的假设；另建固定对局状态比较 | [Valve 7.42](https://www.dota2.com/patches/7.42) |
| IDEA-009 / P2 | **开视野要服务于具体决策**：为了防止被强开、抢盾、推塔、烟雾绕后而部署有用视野，而非简单做眼位次数 | 当前 Ward / team_roam 是否把眼位选择与后续团队目标绑定 | [DotaSense Vision（2026）](https://dotasense.com/guides/vision?lang=zh-CN) |

## 5. 持续发现策略的研究流程（不依赖用户主动想出所有机制）

每次遇到新补丁、策略 PR、某类游戏问题或用户要求研究，可按照相同流程：

1. **数据与事实**：对照 Valve 当前补丁、客户端解析/脚本 API 和仓库现有源码，筛出结构变化和可观测机会；不得把外部讨论的推测写成游戏机制。
2. **社区发现**：查最近版本的社区论坛、高手教学/攻略、比赛复盘和其他 Bot 实现。记录链接、发布日期、适用版本、作者主张与相反意见；职业局方案不默认适合 Bot API 和所有阵容。
3. **提出意料之外的候选**：使用第 4 节 `IDEA-xxx`，每项写清触发状态、可选择行动、何时不做、可能的获胜链路、输入是否能合法获得、已知反例、代码位置。
4. **排序与筛选**：估计胜率影响潜力、出现频率、源码证据强度、实现/退化风险、需要真实客户端验证程度。不会按观看量、Stars、热度直接断言收益。
5. **转换**：筛选后提升为 F 类具体需求 → 静态审查 → Mock 的正例和反例 → 小范围 PR → 未来必要时按 VT 项在客户端测试 → 公平对局验证。未选中的候选保留原因，不重复挖掘。
6. **版本复查**：新补丁或热修可能改变策略正确性。过时策略降级为历史参考；只根据新版本证据恢复。

当前没有创建自动抓取、定时提醒、常驻客户端或持续运行服务。用户继续询问项目进度或下一批需求时，可以直接按此清单重新检索最新社区资料并提供新建议；**没有配置日程工具就不能声称我会自动在后台监控社区**。

## 6. 本轮来源记录与局限

| 来源 | 日期/版本 | 可取的证据 | 不能直接推出 |
| --- | --- | --- | --- |
| [Valve 7.42](https://www.dota2.com/patches/7.42) | 2026-11-18 / 7.42 | 新机制、数字、规则、物品 | 某种策略必然提高胜率 |
| [d2vpkr Meepo KV](https://github.com/dotabuff/d2vpkr/blob/281a3058165bfe46681a657aaed8f5015eaac6b4/dota/scripts/npc/heroes/npc_dota_hero_meepo.txt) | Client 6983 / 2026-11-19 | 内部能力名称、KV 属性 | Lua Bot API 真实施放一定可用 |
| [Reddit Meepo 7.42](https://www.reddit.com/r/DotA2/comments/1xzu6en/meepo_players_what_are_we_thinking/) | 2026-11-18～19 | 新机制早期实战感受、操作顾虑 | 大样本最佳策略或技能无 Bug |
| [Reddit 旧 Meepo](https://www.reddit.com/r/TrueDoTA2/comments/1vmq6g4/to_all_the_meepo_spammers_whats_your_exact_game/) | 2026-08 / 7.42 之前 | 角色运营的通用思路 | 新 Shard 的使用/出装最优解 |
| [Dotacoach Roshan](https://dotacoach.gg/en/articles/roshan) | 非 7.42 专门版本 | 视野、分工、防反打的策略思想 | 当前坑地形、具体数值、版本计时 |
| [TrueDoTA2 Roshan 争夺](https://www.reddit.com/r/TrueDoTA2/comments/wfwsoo) | 2022 历史讨论 | 有时不能为抢盾牺牲高地 | 7.42 特定阵容下的当前成功率 |
| [Reddit Aegis 转换](https://www.reddit.com/r/learndota2/comments/1i7cv6p) | 2025 历史讨论 | 拿盾后兵线/冷却/推进的决策维度 | 当前版地图的准确最优路径 |

**下一步建议：** 优先把 #5 的策略机会成本与 VT-001～004 挂钩，随后审查 F-10（敌方 Roshan 争夺）在 OHA 当前模式中的真实实现范围。先做诊断与需求，不假定已经发现 Bug，也不立刻部署批跑系统。
