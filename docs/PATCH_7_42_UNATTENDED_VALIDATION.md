# Dota 2 7.42：无人值守兼容性验证方案（设计与第一版工具）

**状态：仅源码检查、离线模拟和日志分析工具。尚未启动 Dota 2 客户端，亦未验证服务器能否自动完成一局。**

## 核心结论

静态检查只能发现确定的旧技能/旧装备引用、被动技能仍施法、旧参数使用、新增技能未接入等问题。即便静态检查全通过，也不能证明客户端能够执行相应动作、队友不会因模式冲突抢掉指令，或战术强度达到预期。

第一轮检查在 [英雄静态矩阵](PATCH_7_42_HERO_MATRIX.md) 中按 E2 / E1 / UNREVIEWED 标记。完整规则和源码指纹在 [机器可读清单](patch742_hero_inventory.json)。脚本 [patch742_audit.py](../scripts/patch742_audit.py) 会核对 128 个 hero_*.lua 文件与已登记的补丁冲突，但**没有登记的英雄始终处于待完整核验状态**。

## 未来可以不用你盯屏的三阶段流程

### 1. 批量运行、固定环境（尚未实现）

优先试验官方 Local Host 的 Bot vs Bot 对局模式；如果想无人值守运行多个对局，也可以隔离研究 Dota 2 dedicated server / [dota2-env](https://github.com/Passerby/dota2-env) 等环境，但要先确认其 Lua Bot Script 目录、OHA .OHA 命名、FretBots 适配和结束判定可靠。不得直接覆盖你的正式 Steam 安装目录。

每次测试需记录：Dota Patch、OHA commit SHA、英雄/位置、对手阵容、难度、模式、随机种子（若可控）、脚本日志路径；所有无法获得的信息明确写为 UNKNOWN。

### 2. 只记录异常与必要状态（日志追踪为可选功能）

* 现有 DQ-1 [Draft PR #12](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/12) 提供选定英雄主动技能 READY、COOLDOWN、NO_MANA、部分 ALLOW/BLOCK 和 NO_PROPOSAL 原因；默认关闭。
* 下一阶段仅在已经验证运行时 API 后，逐步采集：Lua runtime error、脚本加载失败、同一物品购买失败次数、丢弃/拾取循环、无目标长时间空闲、推进/防守模式短时间频繁切换等。
* 技能若需判断未施放原因，必须把 CANDIDATE、ALLOW/BLOCK、ACTION_REQUESTED 与执行后状态联系起来。只看到 READY 不能证明有合理目标；只看到 ALLOW 不能证明客户端执行成功。
* 日志限频、采样并按英雄过滤。忽略聊天和账户信息，避免不断打印影响帧率。某个时间段没有记录，不等于没有异常。

### 3. 自动离线归类、仅人工审查异常片段

现有第一版 [patch742_log_triage.py](../scripts/patch742_log_triage.py) 只能从已捕获的日志自动统计 VScript runtime error、nil 索引/调用、缺失脚本和已有 [OHA_DECISION] 记录：

    python3 scripts/patch742_log_triage.py dota-console.log --out local/patch742/triage.json

它不会联网或启动客户端；当前不会分析音视频或完整回放。输出仅包含错误类别与行号，不复制原始玩家聊天文本。

后续在真实对局中确认事件可靠性后，再加入以下候选异常判定：

| 候选异常 | 建议最低证据 | 必须排除的正常情形 |
| --- | --- | --- |
| SCRIPT_ERROR | 真实 Lua stack trace / 错误位置 | 插件/用户自定义脚本与 OHA 是否相关 |
| REPEATED_PURCHASE_FAIL | 相同物品连续失败及购买队列/金币 | 商店库存、购买范围、库存不足 |
| ITEM_DROP_PICKUP_LOOP | 连续物品句柄/短时间交替 Drop/Pickup | 有计划的递送和正常卖出 |
| CAST_READY_NO_ACTION | 连续多次 READY + 有效目标候选 + 未被其它行动合法抢占 | 无合格施法机会、控制状态、连招预留 |
| IDLE_STUCK | 长时间位置变化极小且没有合法行动意图 | 守点、隐身埋伏、合理原地输出 |
| PUSH_THRASH | 推进与刷野/回防在短时间反复跳转 | 兵线/敌人突然改变、合法撤退 |
| LOW_KP / LOW_WINRATE | 同角色、同阵容难度、足够样本量的数据差异 | 位置、阵容差异及随机波动 |

所有结果初始都标记 REVIEW，不自动认定英雄 AI 有 Bug，也不直接改动战术逻辑。

## 现在完成的边界

1. **已完成**：静态 7.42 源文件风险矩阵与机器可读规则、离线自动检查、日志分类工具和 CI。
2. **未完成**：完整 7.42 每英雄每技能新旧机制比对、真实技能 ID/效果校验、无人值守 Dota 安装/启动/对局、完整技能事件和伤害日志采集。
3. **无需你现在打开游戏**：当前无需 Dota 客户端；真实客户端测试属于日后单独、明确的实施步骤。
4. 本轮不修改正式分支的英雄策略；现有修复 [#4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)、[#6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) 和 [#8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8) 均保持独立 Draft。
