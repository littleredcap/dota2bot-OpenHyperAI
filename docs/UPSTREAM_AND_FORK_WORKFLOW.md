# OHA-Next：上游同步与社区 Fork 引入规范

> 状态：拟作为 OHA-Next 的长期维护规范；最终以合入 `oha-next` 的版本为准。
>
> 建立日期：2026-11-19
>
> 主项目：[littleredcap/dota2bot-OpenHyperAI](https://github.com/littleredcap/dota2bot-OpenHyperAI)  
> 上游：[forest0xia/dota2bot-OpenHyperAI](https://github.com/forest0xia/dota2bot-OpenHyperAI)  
> 初始对齐提交：`cb814c6c8dc51ed08045d6efd9f4a48147992711`

## 1. 决策摘要

1. **主线可控、上游可追踪**：`main` 尽量作为上游镜像，禁止在其上直接实施 OHA-Next 定制开发；`oha-next` 是我们的开发集成分支，不自动等同于稳定发布。
2. **上游变更：先同步 `main`，再验证后集成到 `oha-next`**。不要自动把上游每次提交直接合进正在测试的 OHA-Next。
3. **其他 Fork：按具体提交或模块审查，选择性移植**。默认不做跨 Fork 的整仓库合并；规模大的重构重新设计分批引入。
4. **所有代码改动经过独立分支与 PR**：记录来源、理由、兼容版本、测试和回滚方式。默认由仓库所有者审查后合并，禁止直接自动合并。
5. **用户已选择目标 A：公平规则下尽可能提高获胜概率**。正常对局（不靠额外金币、经验、属性、专属中立装备或非法战争迷雾信息）作为强度比较基准；FretBots/ Buff 增强难度另作评测。合法发育产生更多 GPM/XPM 不算作弊，拟人化不是目标。强度定义见 [OHA_NEXT_STRENGTH_OBJECTIVE.md](OHA_NEXT_STRENGTH_OBJECTIVE.md)。
6. **外部代码的许可与署名是合入条件**：没有确认再分发权限的项目可以阅读、讨论设计，但不得直接复制其受保护的代码。

本规范约定仓库协作与验证流程；**经用户确认的公平强度目标**见 [OHA_NEXT_STRENGTH_OBJECTIVE.md](OHA_NEXT_STRENGTH_OBJECTIVE.md)，需求与验收见 [OHA_NEXT_REQUIREMENTS.md](OHA_NEXT_REQUIREMENTS.md)，目标架构与推进路线见 [OHA_NEXT_ARCHITECTURE.md](OHA_NEXT_ARCHITECTURE.md)，对局数据采集和助手读取见 [MATCH_DATA_PIPELINE.md](MATCH_DATA_PIPELINE.md)。[ARCHITECTURE.md](ARCHITECTURE.md) 保留现有代码地图，Dota 2 版本适配的数据核验步骤仍以 [PATCH_UPDATE_GUIDE.md](PATCH_UPDATE_GUIDE.md) 为基础。

## 2. 分支与职责

| 位置 | 作用 | 操作规则 |
| --- | --- | --- |
| `forest0xia/...:main` | 上游原版 OHA | 只读取与跟踪 |
| `littleredcap/...:main` | 尽可能纯净的上游同步镜像 | 只做上游快进同步；不要直接开发 |
| `littleredcap/...:oha-next` | 我们的开发集成线 | 仅接收审核通过的 PR；实验状态与稳定发布分开标注 |
| `fix/*`, `feature/*`, `docs/*` | 单功能修改 | 从 `oha-next` 分出，提交 PR 到 `oha-next` |
| `integration/upstream-*` | 上游更新集成与冲突处理 | 从 `oha-next` 分出，合并上游镜像后测通再发 PR |
| `port/<source>-*` | 从其他 Fork 移植 | 从 `oha-next` 分出，记录外部来源提交并单独测试 |

现状（2026-11-19）：`main` 与上游起始提交一致；`oha-next` 已建立；`fix/patch-001` 对应 [PR #1](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1)，**处于 Draft/待游戏验证**，不是已进入 `oha-next` 的稳定功能。

## 3. 原作者仓库：持续同步流程

### 3.1 何时检查

- 上游出现新提交、修复英雄 API、地图/装备适配、新版本 Release 或影响整体决策的修复时检查。
- 建议每周人工检查一次；大版本（例如 7.42）发布或上游出现高优先级修复时立即检查。
- 检查不等于自动合并。记录上游 Commit SHA、变更摘要、修改文件、与本地改动的冲突及风险。
- 若上游长期不更新，继续独立维护本项目的版本兼容与测试。

### 3.2 更新本地 `main`（一次性设置 remote）

在本项目的 Git 克隆目录执行：

```bash
git remote add upstream https://github.com/forest0xia/dota2bot-OpenHyperAI.git
# 如果 upstream 已存在，不重复执行 remote add；用 git remote -v 核实。
git fetch upstream --prune
git fetch origin --prune

# 先审查上游独有提交和改动规模
git log --oneline main..upstream/main
git diff --stat main..upstream/main

# 确保主分支没有本地定制提交；不允许强制覆盖
git switch main
git pull --ff-only origin main
git merge --ff-only upstream/main
git push origin main
```

`--ff-only` 失败时暂停，调查分叉原因；禁止使用 `git reset --hard`、`git push --force` 来“解决”分歧。也可在 GitHub 的 `main` 页面使用 **Sync fork**，但同步前仍应检查改动。

### 3.3 把上游更新引入 `oha-next`

```bash
git fetch origin --prune
git switch oha-next
git pull --ff-only origin oha-next
git switch -c integration/upstream-YYYYMMDD
git merge --no-ff origin/main

# 审查冲突、构建；按第 6 节的变更风险选择离线 / 真实测试
git diff --check
npm ci
npm run build

git push -u origin integration/upstream-YYYYMMDD
```

**只创建 PR：** `integration/upstream-YYYYMMDD` → `oha-next`；PR 必须列出上游起止 SHA、冲突处理与验证记录。

- **简单无冲突更新**：按第 6 节选择检查；纯文档无需游戏测试，涉及运行行为时补相应离线 / 自动游戏场景。
- **地图、技能、物品、经济或机器人行为的重大更新**：额外运行对应英雄/模式的回归测试；不通过时先保留上游镜像更新，暂缓 `oha-next` 集成。
- **上游修复与我们的改造冲突**：以实际测试和代码正确性决定保留/融合/替换，不默认“上游优先”或“我们优先”。
- **紧急单点修复**：可从上游挑选具体提交到独立 `fix/*` 分支，但随后仍须处理常规同步的重复提交或冲突。

### 3.4 TypeScript 与生成 Lua

仓库部分 `bots/FunLib/*.lua` 来自 `typescript/bots/FunLib/*.ts` 的构建。应先识别源文件：

- 存在 TS 源文件：优先修改 TS，并通过 `npm run build` 更新生成 Lua；同时检查生成文件差异。
- 仅有手写 Lua：修改其 Lua 原文件；不要假设所有 BotLib 英雄文件都可由 TS 生成。
- 不把“只改了生成 Lua、下一次构建会覆盖”的补丁作为合格移植。

## 4. 其他 Fork：研究与移植流程

**原则：参考设计比复制整仓代码更常见。** Fork 新旧、提交数、Stars、近期 `pushed_at` 都只是线索，不能替代实际代码和游戏测试。

### 4.1 候选准入

先记录：源仓库 URL、与上游关系（真正 Fork 或独立衍生仓库）、目标分支、**精确提交 SHA**、变更文件、许可证、依赖、覆盖问题、已有测试、当前 Dota 2 版本。

按照以下门槛决定：

1. 许可证及第三方代码来源不清楚 → 只参考思路，暂不复制源码。
2. 没有独立代码变化、仅同步上游 → 不作为引入候选。
3. 只靠 README 宣称性能更强、没有测试数据 → 作为假设，不能直接认为优于 OHA。
4. 与已引入模块功能重叠或修改公共动作控制权 → 先做接口/冲突设计，禁止同时启用两个互相抢指令的系统。
5. 有明确回归测试、与项目目标高度一致、改动边界清晰 → 优先排队。

### 4.2 推荐引入方式

| 来源情况 | 推荐方式 |
| --- | --- |
| 单个独立 Bug 修复、依赖清晰、提交可追溯 | `git cherry-pick -x <sha>`，保留来源 |
| 原项目修复跨多次提交 | 先梳理依赖提交、逐步移植；必要时手动重做 |
| 重构跨度过大、与我们架构不同 | 参考设计，独立重实现，保留参考链接 |
| 神经网络/策略权重来自合成数据 | 只引入评测/日志/实验框架，实际游戏胜率验证后再考虑启用 |
| 源代码再利用许可不明确 | 只阅读和研究，不原样搬运 |

示例（仅作为操作模板，`<SHA>` 必须换为已经审查过的真实提交）：

```bash
git remote add fork-canshuqwp https://github.com/canshuqwp/dota2bot-OpenHyperAI.git
git fetch fork-canshuqwp
git switch oha-next
git pull --ff-only origin oha-next
git switch -c port/canshuqwp-specific-fix

git show --stat <SHA>
git cherry-pick -x <SHA>
# 若冲突或连带大规模更改：停止自动移植，手动分析并拆分。
git diff --check
npm ci
npm run build
git push -u origin port/canshuqwp-specific-fix
```

之后创建 PR 到 `oha-next`。PR 中链接**源仓库的具体 commit**；注明我们保留了哪些部分、删除/替代哪些部分、是否与上游后续变更重复。手动改写也应在提交/PR 中标注 `Based on:` 来源链接。

## 5. 已调研的社区项目与优先级

以下为 **2026-11-19 的静态研究候选清单**，不是已经合并的依赖。每次准备引入前重新核实目标提交、代码、许可证及回归测试。

| 优先级 | 仓库 | 已观察到的价值 | 本项目处理方式 |
| --- | --- | --- | --- |
| 高 | [0xvktr/dota2bot-OpenHyperAI](https://github.com/0xvktr/dota2bot-OpenHyperAI) | `tests/hero_harness.lua` 与大量英雄技能测试，另有英雄逻辑修复 | **优先研究/移植测试框架**；英雄行为逐项验证 |
| 高 | [canshuqwp/dota2bot-OpenHyperAI](https://github.com/canshuqwp/dota2bot-OpenHyperAI) | 模式切换发呆、TP 摇摆、防守、打野让资源修复；见 [cadcb385](https://github.com/canshuqwp/dota2bot-OpenHyperAI/commit/cadcb38525188fe8f8093d91b5427feeae3d9a92)、[8c2fc546](https://github.com/canshuqwp/dota2bot-OpenHyperAI/commit/8c2fc546a096c110d64b6dad6343a9163a46f974) | 逐个提交审查，优先挑确定性的行为 Bug |
| 高 | [certainlyForgiveHer/dota2bot-OpenHyperAI](https://github.com/certainlyForgiveHer/dota2bot-OpenHyperAI) | `lane_probe.lua`、`tests/lane_probe/analyze_lane_log.js` 可采集/对比对线行为 | 优先吸收诊断与 A/B 评测方式 |
| 中 | [Andertaker73/dota2bot-OpenHyperAI](https://github.com/Andertaker73/dota2bot-OpenHyperAI) | `action_gates.lua`、`responder_policy.lua` 与防守/缓存重构 | 参考动作仲裁思路，不整库替换 |
| 中 | [mamonis-114514/dota2bot-OpenHyperAI](https://github.com/mamonis-114514/dota2bot-OpenHyperAI) | `gank_lib.lua`、`draft_lib.lua`：开雾、敌方阵容特征、动态出装 | 参考团队运营与针对性装备，核实版本数据 |
| 研究 | [theChaiyakorn/dota2bot-OpenHyperAI](https://github.com/theChaiyakorn/dota2bot-OpenHyperAI) | 规则 + Lua MLP 辅助补刀/反补/换血、离线训练及日志 | 作为实验框架；样本/权重未经充分真实对局验证 |
| 只读评估 | [anggara-ts/OpenHyperAI-too](https://github.com/anggara-ts/OpenHyperAI-too) | 较新的英雄行为、物品与走位实现；目录结构独立演化 | **仓库元数据未显示明确许可证**；明确许可前只比较设计，暂不复制 |
| 低 | [Maxxoto/Dota-OpenHyperAI-Agent](https://github.com/Maxxoto/Dota-OpenHyperAI-Agent) | LLM 聊天/顾问模块与配置流程 | 当前目标是游戏决策强度，不优先移植联网聊天 |
| 高（测试设施） | [dragonghy/dota2bot](https://github.com/dragonghy/dota2bot) | Lua 模拟测试、GitHub CI、无头批量对局工具、A/B 与日志解析框架 | 优先参考测试体系；批跑脚手架需实机校准，**尚未移植** |

不要因为某个项目有 10、50、100 个提交就默认更强；也不能仅因原版主仓库没有更新，就接受其他分支的所有修改。

## 6. 自动化优先的验证与评审门槛

**开发原则：不要求仓库所有者对每个 PR 亲自进入 Dota 2 打一局。** 维护者负责提供可复现的自动测试和对照数据，人工操作仅保留在重要版本、重大行为变更或自动测试无法解释的异常。

**当前进度决定（2026-11-19）：** 用户要求先做 AI 玩法需求，暂不开发全员故障监控、真实自动对局或数据回传平台。以下 T2 批跑和 watchdog 规则保留为未来恢复此类测试时的质量要求，**不是当前实施 F-01～F-09 玩法需求的阻塞前置条件**。现阶段仍以既有 T0/T1 检查为基础，未做真实引擎测试的效果必须标明未验证。

下表描述目标验证体系；当前实际覆盖范围见表后的能力说明，不表示这些检查已全部配置。

| 等级 | 实施位置 | 检查项 | 仓库所有者是否必须操作 |
| --- | --- | --- | --- |
| T0：静态检查 | GitHub Actions / 本地 CI | `git diff --check`、Lua 5.1 语法、TypeScript 编译、引用/配置校验 | 否；每 PR 自动运行 |
| T1：离线行为单测 | Lua 模拟 Bot API、确定性场景 | 目标锁定、技能合法性、伤害估算、模式优先级、装备/技能数据等 | 否；验证受影响行为，必要时增加对应断言 |
| T2：真实自动对局 | **需要另外配置**安装 Dota 2 的本地 Linux/Windows 主机或云端测试机 | AI 自主打完对局、采集日志、GPM/XPM/死亡/行为、A/B 和队伍镜像 | 否；由测试平台自动执行 |
| T3：人工游戏体验 | 正式发布或特别异常时 | 观察动作抖动、团战合理性、用户体验；可以只复核短场景/录像 | 偶尔需要，非逐 PR 门槛 |

**当前能力与限制（2026-11-19）：** [PR #1](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) 已加入首批 Lua 5.1 语法检查与 5 个离线行为回归用例；[GitHub Actions 测试](https://github.com/littleredcap/dota2bot-OpenHyperAI/actions/runs/44456852894)已通过，但该 PR 仍是 Draft，且 CI 尚未覆盖全部英雄和模块。**没有已配置的 Dota 2 真实自动对局主机。** 不能声称 GitHub Actions 普通托管 Runner 可以直接运行完整 Dota 2 对局。T2 落地前，不可将“静态/模拟测试成功”写作“游戏内验证通过”。

### 6.1 哪些情况允许不做人工测试

- 文档、注释、独立构建工具修改：T0 / 链接检查；无需 T2/T3。
- 纯算法函数或局部修复：T0 + T1 必须通过；优先用少量 T2 场景补充。T2 环境未就绪时保留在实验分支 / Draft；所有者审核后可将隔离、默认关闭的实验功能合入开发集成线，必须标明“未游戏实测”。没有隔离开关的核心行为实验继续留在 Draft，禁止作为正式稳定发布依据。
- 英雄技能、团队策略或地图大改：T0 + T1 + T2 对照测试后再作为已验证改进；T3 由风险/数据异常决定。
- 正式发布或大版本适配：至少完成 T0、T1、T2，并进行一次短时 T3 人工抽检；无需让用户亲自反复打数十局。

### 6.2 T2 自动对局落地计划

优先调研 [dragonghy/dota2bot](https://github.com/dragonghy/dota2bot) 的 `tests/` 和 `tools/batch_test/`。其代码包含 `lua5.1 tests/run_tests.lua`、`run_batch.sh`、日志解析、A/B 对照和按需云测试文档，适合作为**工程参考**。

该项目的 [批量测试说明](https://github.com/dragonghy/dota2bot/blob/main/tools/batch_test/README.md) 仍标注首跑待校准，但当前 [parse_log.py](https://github.com/dragonghy/dota2bot/blob/main/tools/batch_test/parse_log.py) 说明声称已用 2026-07-19 的真实完赛日志校准；两处状态不同步。其 [A/B 构建工具](https://github.com/dragonghy/dota2bot/blob/main/tools/batch_test/make_ab_build.py) 仍列有 VM / 缓存隔离的待验证假设。可参考已有实现与经验，**我方环境尚未验证**，也没有移植它的整套方案。

首场闭环需至少 1 局身份匹配的有效完赛，取得可信胜负、时长及必需数据，并由助手实际读回。**同时要求所有预期 Bot 的位置/行为自报及数据覆盖率被记录，并校准独立于被测 Bot Lua 的实体观察方式，以发现 Bug 导致的隐蔽停滞；独立观察不可用时必须披露检测盲区。** 超时诊断包不能替代成功路径验收。协议、状态模型、异常检测与上传读取详见 [MATCH_DATA_PIPELINE.md](MATCH_DATA_PIPELINE.md)。

T2 任务需提供版本 / 构建身份、游戏构建、双方阵容与阵营、关键设置的请求值及生效证据、随机种子控制的支持状态、启动 / 结束状态、结果来源、资源消耗和原始日志位置。区分执行状态、数据有效性与评估结论；必要身份 / 结果缺失不能当成功对局，可选指标缺失标 unknown，不造数也不一概否定无关指标。

对比前先验证双方版本隔离，再使用匹配条件并交换阵营。两个版本分别自博弈的天辉胜率不能证明候选更强；所有尝试与排除原因都须报告。先小规模校准，再扩展批量测试。

**批量测试的前置门槛：** 100 局局末战绩不能证明不存在**Bug 导致的原地不动**；验证 watchdog 时必须分别注入“Bot 仍发心跳但不再有行动进展”与“Lua 失效导致 Bot 不再上报，而引擎实体仍在”的场景。第二类需要经验证的独立引擎观察，不能指望出错脚本自证故障。应保存位置、时间线、最近命令和错误证据；正常蹲守、死亡、暂停不应被简单误判。零告警必须同时报告全员覆盖率和外部观察能力，否则视为未知。

### 强度声明分级（与 E0～E4 缺陷证据分开）

未来每项功能 PR 需注明其类型：`compatibility_identified`（仅定位适配问题）、`logic_checked`（局部逻辑检查）、`game_checked`（真实场景核验）、`strength_signal`（有限公平对照初步信号）、`strength_supported`（有足够公平对照和泛化证据支持）或 `regression`/`inconclusive`。仅有离线单测不等于胜率增长，严禁以较高 GPM、KDA 或击杀数直接替代获胜能力。细则见 [OHA_NEXT_STRENGTH_OBJECTIVE.md](OHA_NEXT_STRENGTH_OBJECTIVE.md)。

### 6.3 每个 PR 的填写内容

- **来源**：上游/外部 Fork 的 URL、源提交 SHA、许可证和必要署名；独立开发注明 `Original implementation`。
- **目标和改动范围**：问题、预期可测结果、受影响文件、是否改变动作优先级和所有权。
- **验证矩阵**：明确 T0/T1/T2/T3 哪些已通过、未执行、受阻；附证据链接，绝不把未执行写成通过。
- **对照效果**：与未修改 OHA 或上一版 `oha-next` 在同版本、同阵容、交换阵营下对照；记录关键统计，FretBots 数值优势单独标识。
- **回滚**：可通过 `git revert` 回退；禁止将多个独立高风险功能捆绑到同一个无法拆分的 PR。

**通过 T0/T1 不证明游戏内逻辑更强；通过少量 T2 也不等同于胜率显著提高。** 未经验证的改进须标记为实验性。

## 7. 维护日志（随 PR 更新）

| 日期 | 来源 | 引入内容 / 来源提交 | 项目 PR | 当前状态 |
| --- | --- | --- | --- | --- |
| 2026-11-19 | 上游 OHA | 初始 `cb814c6c8dc51ed08045d6efd9f4a48147992711` | — | `main` / `oha-next` 基线 |
| 2026-11-19 | OHA-Next 自研 | 目标锁定和 Roshan 队伍 DPS 修复 | [#1](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/1) | Draft，待游戏验证，**未合并** |
| 2026-11-19 | 社区 Fork 候选 | 测试工具、行为修复、对线日志等，见第 5 节 | — | 调研中，**未移植** |
| 2026-11-19 | OHA-Next 设计 | 目标架构、需求 ID、对局采集及助手读取协议 | [#2](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/2) | 设计文档；真实采集 / 回传**未实现** |

每次引入一项外部功能，应在本表追加：日期、源仓库 + commit、对应 PR、测试数据位置、决策（`planned` / `rejected` / `in PR` / `merged` / `reverted`）。不得把“计划研究”记成“已经移植”。

## 8. 团队默认禁止事项

- 禁止向 `main` 直接提交 OHA-Next 个性化功能。
- 禁止对共享分支进行强制推送、用重置抹平分歧。
- 禁止未经审查整合其他 Fork 的整条 `main`。
- 禁止自动合并到 `oha-next`，尤其是没跑游戏测试的行为逻辑。
- 禁止把未知许可的代码、外部 API 密钥、测试账号、敏感日志写进仓库。
- 禁止声称“更新了 Dota 版本就提高了 AI 智商”；版本兼容和决策能力必须分开测试。

---

**维护约定：** 这份文档会随我们的集成策略变化和每次上游/社区代码引入而更新。重要架构变更须先更新规范，再开发或在同一个 PR 中更新规范。