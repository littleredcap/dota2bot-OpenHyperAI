# OHA 多场 Bot 表现评估规范（P-1，初版）

**状态：Draft / 不改战术。** 本文件定义可复算的赛后表现指标、数据来源和异常筛查原则。它不是 Max+、DotaMax 或 STRATZ 的官方评分，也不声称已经采集真实 OHA 对局。

## 1. 为什么采用数据驱动的专项修复

目的是发现持续弱势的英雄 / 位置，再结合源代码、DQ-1 决策日志和对局回放寻找原因。不能把低 KDA、低击杀参与率、低英雄输出或单场败局直接等同于 Bot 决策缺陷；辅助、先手与推进英雄的贡献结构显著不同。

外部参考（仅借鉴指标类别和分析方法，不抓取私有评分）：

- **DotaMax / Max+**：其公开应用描述包含个人比赛战绩、胜率趋势图、雷达图、英雄和物品使用次数 / 胜率 / 伤害 / 克制关系。来源：[App Store 上的 Max+](https://apps.apple.com/cn/app/max-for-dota2-cs-go/id990892583)、[Max+ 官方应用关系说明](https://app.weibo.com/detail/1ptcXn)。这说明产品侧可采用趋势、角色维度、多轴指标，而不是断言 Max+ 使用某个未公开的综合评分公式。
- **玩加电竞**：[Dota 2 选手数据指标与公式](https://www.wanplus.cn/dota2/playerstats) 列出 KDA、参团率、GPM、CSPM、英雄伤害 / 每分钟输出、输出占比和经验占比。该来源明确给出参团率公式。
- **STRATZ**：[官网](https://stratz.com/) 描述角色 / 位置 / 对局 / 技能和装备分析及 IMP；[其知识库](https://github.com/STRATZ-Esports/knowledge-base/issues/23) 说明 IMP 使用与英雄、位置和游戏时长关联的专有模型。**不复制 IMP，也不声称本项目获得其模型权重。**
- **OpenDota**：[API 文档](https://opendota.apidocumentation.com/) 支持按已知 match_id 获取公开比赛数据；[开源数据表字段](https://github.com/odota/core/blob/master/sql/create_tables.cql) 包含英雄伤害、建筑伤害、治疗、补刀、插眼、技能 / 道具使用等字段。个别字段依赖 replay parse，不能预设始终存在。

## 2. 数据来源与可获得性

| 来源 | 第一版可用性 | 重要限制 |
| --- | --- | --- |
| OHA Local Host 自定义房间 | **手工整理赛后 JSON，可导入** | 不能假定存在可查询的公开 match_id；不承诺自动读取完整赛后面板 |
| 已收录的公开比赛 | **手动指定 match_id，OpenDota 获取 JSON** | 某些房间不收录；数据可能缺失或延迟解析；需要明确标记哪些玩家槽位是真正的 OHA Bot |
| DQ-1 决策日志 | 独立的诊断数据源 | READY / BLOCK 不等于击杀、技能执行成功或赛后伤害 |
| 本地 Bot API | 文档确认可读玩家 K/D/A、等级和部分状态 | 英雄伤害、视野、控制等赛后字段不能假定能通过 Bot API 完整读取；完整本地自动采集属于下一阶段 |

程序按来源分别保留记录。**缺失值使用 null / 报告显示“—”，不自动补零。** 不上传 Steam account_id、昵称、聊天和原始录像。JSONL 数据目录默认忽略提交。

### 统一的基础字段

- 一场比赛：`match_id`（允许 `local-...` 本地标识）、`duration_seconds`、`patch`、`bot_build`（OHA Git commit）、`game_mode`、`lobby_type`、`difficulty`、`opponent_profile`、`radiant_win`。
- 每个玩家槽位：`player_slot`（0–4 天辉 / 128–132 夜魇）、`hero`、`position`（1–5 或 null）、明确的 `is_oha_bot` 布尔值、`kills` / `deaths` / `assists`。
- 可选指标：`gold_per_min`、`xp_per_min`、`last_hits`、`denies`、`hero_damage`、`tower_damage`、`hero_healing`、`obs_placed`、`sen_placed`、`camps_stacked`、`stun_seconds`、`net_worth`。
- `team_kills` 和 `team_hero_damage` 是 **分队汇总**：若完整 5 人数据可用可安全求和，否则需由可信赛后结果显式提供；不可按队伍中的部分 Bot 自行计算总数。
- OpenDota 的 `hero_id` 若未提供英雄映射，会显示 `hero_id:123`，不会自行假设内置英雄名；`lane_role` **不等于** OHA 的 1–5 号位，位置须明确输入或保持 null。

## 3. 指标定义与优先级

| 优先级 | 指标 | 计算与解读 |
| --- | --- | --- |
| P0 | 胜率 + 样本量 | 胜场 / 有效场次；同时给出 Wilson 95% 区间，避免小样本按胜率排序 |
| P0 | K / D / A、KDA | 保存三个原始数；描述性 KDA 约定为 `(K+A)/max(D,1)`；零死亡不当作无限大 |
| P0 | 击杀参与率 KP | `(K+A)/TeamKills`；若 TeamKills = 0 或未知，KP = null，**不是零** |
| P0 | GPM、XPM、补刀 / 分钟 | 按角色和版本比较发育，不对辅助设统一绝对门槛 |
| P0 | 英雄伤害 / 分钟、建筑伤害 / 分钟 | `damage / (duration_seconds/60)`；对推进型英雄不能只看英雄伤害 |
| P1 | 英雄伤害占比 | `hero_damage/team_hero_damage`，要求队伍完整伤害数据；不是伤害效率 |
| P1 | 死亡 / 10 分钟、治疗 / 分钟 | 分析先手、救援、保命和辅助贡献，必须结合英雄定位 |
| P1 | 插眼、反眼、野区堆叠、控制持续时间 | 数据源支持时才展示；零与 null 区分；没有可用数据就不作排名 |
| P2 | 前 10 分钟对线、装备时间点、肉山与高地响应、时段参战 | 需要解析完整回放或额外事件记录；**本版尚未支持** |
| P2 | 技能 / 物品使用成功率、未施法机会 | 需要合法的技能事件与动作回执；不能从剩余冷却推断，暂不计算 |

本版**不计算“综合智能评分”**。尤其不允许靠可加权的 KDA+GPM 把守家、插眼、保护队友等行为错误地评为无价值。

## 4. 分组与对照实验

### 4.1 必须匹配的条件

比较时严格对齐：`英雄 × 位置 × patch × game_mode × lobby_type × difficulty × opponent_profile × source × 阵营`，并以不同 `bot_build` 为候选/基线。未记录位置或关键环境条件为 `unknown` 的组只生成描述性数据，**不能给出异常结论**。

推荐 A/B：同一游戏版本，同英雄同位置，基线 commit 与候选 commit 分别收集多场；均衡天辉/夜魇、对手和英雄阵容。每场配置写入原始记录。阵容难度未匹配的数据只可做探索性分析。

### 4.2 样本与异常标记

- 同一可比条件下，两版本**各至少 30 个 Bot 观察样本**才进行初筛；30 场并不足以证明胜率差异，建议进一步扩样至 50–100+ 场或进行针对性重复实验。
- 胜率的 Wilson 区间分开计算。两组区间不重叠才生成 `WIN_RATE_CI_SEPARATION_REVIEW`（保守审查线索，**不等于严格的 A/B 假设检验**）。
- 相同条件下，KP 下降至少 15 个百分点可标 `KP_DROP_REVIEW`，英雄伤害 / 分钟下降至少 20% 可标 `HERO_DAMAGE_PM_DROP_REVIEW`。
- GPM 增长至少 10% 同时 KP 下降至少 15 个百分点，标 `GPM_UP_KP_DOWN_REVIEW`，作为“可能过度刷钱”的调查线索。所有阈值为工程初始启发式，需在积累数据后校准。
- 每项比较若对应指标数据未覆盖两组各至少 30 个样本，不生成该指标的审查标记。
- 严禁据此自动修改英雄 AI、自动合并 PR、声称因果关系或将未知字段视为零。多英雄多指标筛查还要考虑多重比较。

## 5. 当前可执行的工具链

仅依赖 Python 3 标准库。所有输入读取本地 JSON，默认**没有网络请求**。

### 5.1 导入 Local Host 赛后记录

复制 [示例 JSON](../docs/examples/oha_match.example.json) 为新文件，填入**真实**赛后数据及对应 Bot commit；不可把示例数据用作真实对局统计。

```bash
python3 scripts/bot_performance.py ingest --format manual \
  --input local/bot_performance/match-001.json \
  --out local/bot_performance/matches.jsonl
```

`is_oha_bot` 必须显式提供；混入人类玩家也不会误计为 Bot。没有完整伤害数据的比赛仍可分析 KDA、胜率和经济，KP 只有提供完整队伍击杀总数才计算。

### 5.2 导入公开比赛（有实际 match_id 时才用）

```bash
python3 scripts/bot_performance.py fetch --match-id YOUR_PUBLIC_MATCH_ID \
  --out local/bot_performance/public-match.json

python3 scripts/bot_performance.py ingest --format opendota \
  --input local/bot_performance/public-match.json \
  --bot-slots 0,1,2,3,4 --positions 0:1,1:2,2:3,3:4,4:5 \
  --patch 7.42 --build commit-abc --difficulty custom2 \
  --opponent-profile fixed-bots-v1 \
  --out local/bot_performance/matches.jsonl
```

上面的 `--bot-slots` 只是**格式示例**，使用时必须替换成实际 OHA Bot 槽位。不得把其他 Valve/人类玩家冒充成 OHA Bot。已知全队均为 OHA Bot 时才可使用 `--bot-side radiant|dire|both`。OpenDota 的公开数据并不能验证这些标记。

### 5.3 生成汇总与基线对比

```bash
python3 scripts/bot_performance.py report \
  --data local/bot_performance/matches.jsonl \
  --json-out local/bot_performance/summary.json \
  --md-out local/bot_performance/summary.md

python3 scripts/bot_performance.py report \
  --data local/bot_performance/matches.jsonl \
  --baseline-build BASE_COMMIT --candidate-build NEW_COMMIT \
  --min-games 30 \
  --md-out local/bot_performance/ab-review.md
```

数据以 `(source, match_id, player_slot)` 去重；重复导入相同记录不重复计数，冲突记录直接拒绝（不静默覆盖）。

## 6. 下一阶段验证（明确不在本 PR 内）

1. **Local Host 数据自动导出验证**：先在真实 Dota 客户端检查比赛结束时 Bot Lua 回调是否仍可运行，以及哪些单位/玩家统计 API 在赛后可靠，测试人机混编与两阵营。不要假定 Valve API 提供完整英雄伤害/眼位；如缺少，需确认合法的本地 scoreboard / replay 导出手段。
2. **离线赛后采集转自动化**：建立确实可靠的本地采集器之后再替换手工输入；拒绝编造不存在的 match_id 或公开统计。
3. **对照实验**：按相同版本和英雄池批量采集真实数据；只有出现稳定低 KP / 低胜率或高经济低贡献异常，才开启 DQ-1 诊断或专项审计。

### 验收与边界

- 单元测试覆盖公式、缺失数据、完全 / 不完整阵容、隐私、重复导入、角色版本分组、样本门槛、报告输出。
- 不启动 Dota、不用未验证的游戏 API、不影响任何 Bot 战术行为。
- CI 成功仅说明本地 JSON 分析可复算，**不能说明任何真实 OHA Bot 表现优劣**。
