# Dota 2 7.42 补丁驱动的结构兼容性审查（第二轮，精选高风险项）

> **2026-11-20；仍为静态审查，未运行真实 Dota 2 客户端。** 本文件以 [Valve 官方 7.42（2026-11-18）](https://www.dota2.com/patches/7.42) 的**结构性变化**为入口，再检查仓库的实际 Lua 调用。初步选择高风险变更，不是官方全部 7.42 项目的逐条语义验证；无正则命中也不算兼容通过。

## 审查方法与真实覆盖

- **源码基线**：`oha-next` SHA `cb814c6c8dc51ed08045d6efd9f4a48147992711`；本审查仍检查**未合并的旧基线**，不因为已有修复 PR 而把主分支标绿。
- **技能身份核验**：参考当次 [d2vpkr Hero KV 固定提交](https://github.com/dotabuff/d2vpkr/commit/77a6ccca87bab183caaf0c09fd2813f2695b7a5b)，用技能内部名称、技能槽位、`AbilityBehavior` 和目标队伍而非技能展示名猜测 API。此 KV 是公开游戏数据镜像；API 真正能否在 Bot VM 使用仍须客户端验证。
- **文件覆盖**：对 **128 个 `bots/BotLib/hero_*.lua`** 做了限定旧物品关键词的扫描（包含独立的熊文件）；**并没有语义审完 128 个英雄、所有天赋与技能**。完整文件清单见 [第一轮矩阵](PATCH_7_42_HERO_MATRIX.md)。
- **本轮精确登记**：21 条手工核对的补丁影响记录，其中“活动源码直接冲突” 10 条、“新增能力缺口” 6 条、“旧机制语义待核验” 3 条、“定向搜索未见旧名称” 2 条。**记录数不等于不同英雄数，也不等于 Bug 数量**。
- 128 个英雄 Lua 的三种已移除购物物品的活动引用：`item_khanda` **0** 个文件，`item_javelin` **0** 个文件，`item_helm_of_the_overlord` **2** 个文件（兽王、狼人）。前两个“未命中”不证明其合成、购买模块或全部英雄策略已兼容。
- **静态证据等级**：E2 是与正式补丁确实冲突的活动源码，不等于在游戏中发生过错误；E1 是新版功能未利用/需要验证，不等于已有行为必然失效。

## 7.42 变更 → 源码 → 改动状态 → 剩余策略

| ID | 补丁变化及源码证据 | 判断 | 最小修复 / 现状 | 仍未完成的策略与验证 |
| --- | --- | --- | --- | --- |
| C742-01 | **Meepo 旧 MegaMeepo 删除**：7.42 删除 MegaMeepo；nil 句柄方法调用风险；[`bots/BotLib/hero_meepo.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_meepo.lua)（`present:GetAbilityByName('meepo_megameepo')`） | E2 · 活动源码直接冲突 | [Draft #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)：#4 移除旧 MegaMeepo，保留 Dig 保护；不实现新 Shard 拾取/Fling | 新 Shard 触发/目标和行动机会成本尚需另行设计；VT-005 |
| C742-02A | **Beastmaster 旧 Overlord 出装**：已移除装备仍在 pos3 默认出装；[`bots/BotLib/hero_beastmaster.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_beastmaster.lua)（`present:item_helm_of_the_overlord`） | E2 · 活动源码直接冲突 | [Draft #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)：原兽王出装只删除无效商品，不另猜最佳出装 | 新 Ancient Thunderhide 的使用与兽群协同尚未实现；VT-006 |
| C742-02B | **Lycan 旧 Overlord 出装**：已移除装备仍在 pos3 默认出装；[`bots/BotLib/hero_lycan.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_lycan.lua)（`present:item_helm_of_the_overlord`） | E2 · 活动源码直接冲突 | [Draft #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)：原狼人出装只删除无效商品，不另猜最佳出装 | 新 Pack Hunter 的利用、出装强度仍需验证；VT-006 |
| C742-06 | **Leshrac 旧 Nihilism 自虚无判断**：Nihilism 7.42 不再让自身虚无，旧躲弹道触发条件已失效；[`bots/BotLib/hero_leshrac.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_leshrac.lua)（`present:J.GetAttackProjectileDamageByRange(bot, 1200)`） | E2 · 活动源码直接冲突 | [Draft #8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8)：#8 删除旧自保理由并保护句柄 | 正确缴械/持续驱散的施放时机和不误解队友控制需独立验证；VT-016 |
| C742-07 | **Nature's Prophet Oldgrowth 被动化**：7.42 Oldgrowth 已变被动，却仍主动施法；[`bots/BotLib/hero_furion.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_furion.lua)（`present:ActionQueue_UseAbility(CurseOfTheOldGrowth)`） | E2 · 活动源码直接冲突 | [Draft #16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16)：#16 删除旧主动调用，保留其他技能原考虑函数 | 新被动与 Sprout、Nature's Call 的收益和连招未优化；VT-020 |
| C742-08 | **Abaddon 7.42 Shard 从 Mist Coil 转移**：7.42 Shard 强化 Aphotic Shield，旧 Coil 纯粹伤害击杀估算错误；[`bots/BotLib/hero_abaddon.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_abaddon.lua)（`present:nDamageType = DAMAGE_TYPE_PURE`） | E2 · 活动源码直接冲突 | [Draft #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17)：#17 移除旧 Shard 伤害假设，保留其他目标选择 | 生命消耗时机和新 Scepter AoE 仍需专项设计；VT-022 |
| C742-10-OLD | **Chen 旧 Summon Convert 删除**：7.42 Chen 新 Ability4 为 chen_zealot，旧召唤接口已不可用；[`bots/BotLib/hero_chen.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_chen.lua)（`present:GetAbilityByName('chen_summon_convert')`） | E2 · 活动源码直接冲突 | [Draft #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17)：#17 删除旧句柄/旧主动逻辑，保留其他 Consider 顺序 | Zealot 复活与 Holy Persuasion 自身召回尚未实现；VT-021 |
| C742-13 | **公共基础物品中含 Javelin**：7.42 已移除 Javelin，却仍列为基础物品；[`bots/FunLib/aba_item.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/FunLib/aba_item.lua)（`present:item_javelin`） | E2 · 活动源码直接冲突 | [Draft #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17)：#17 仅移除基本物品分类，不强制替换新购买 | 真实出装新配方和物品价值仍需版本验证；VT-024 |
| C742-15 | **公共物品表访问旧 Overlord 配方**：7.42 已移除 Overlord，初始化仍直接读取配方；[`bots/FunLib/aba_item.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/FunLib/aba_item.lua)（`present:Item['item_helm_of_the_overlord']`） | E2 · 活动源码直接冲突 | [Draft #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)：#4 删除旧初始化引用 | 所有新装备的购买执行及与新配方共存仍需确认；VT-006 |
| C742-16 | **Weaver 神杖友军 Time Lapse 分离**：7.42 Weaver Time Lapse (Ally) 是独立单位目标技能，原脚本仍用自身无目标能力对友军下令；[`bots/BotLib/hero_weaver.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_weaver.lua)（`present:Action_UseAbilityOnEntity(TimeLapse, Target)`） | E2 · 活动源码直接冲突 | [Draft #19](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/19)：#19 改用 weaver_time_lapse_ally 并保护句柄、原救援时机不变 | 救援对象价值、伤害预判与共享冷却的游戏执行需单独验证；VT-026 |
| C742-09 | **Chaos Knight Armageddon 新主动**：Ability4 新主动可令幻象冲锋，但原脚本没有这个施法决策；[`bots/BotLib/hero_chaos_knight.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_chaos_knight.lua)（`absent:chaos_knight_armageddon`） | E1 · 新能力未接入 | [Draft #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17)：只验证原 Q/W/R 的槽位不被新内置能力破坏，未做主动策略 | 需要幻象存活、目标地面位置、引导中断和替代动作的成本模型；VT-023 |
| C742-10-NEW | **Chen Zealot 新主动**：7.42 Ability4 新 Zealot 主动与旧 Summon Convert 不同；[`bots/BotLib/hero_chen.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_chen.lua)（`absent:chen_zealot`） | E1 · 新能力未接入 | [Draft #17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17)：删除无效旧召唤，暂不将旧召唤条件用于新技能 | 需查 Zealot 存活标记、复活时机、与 Holy Persuasion 的协调；VT-021 |
| C742-11 | **Beastmaster Scepter 新 Thunderhide**：7.42 神杖增加无目标召唤 Ancient Thunderhide；[`bots/BotLib/hero_beastmaster.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_beastmaster.lua)（`absent:beastmaster_summon_thunderhide`） | E1 · 新能力未接入 | 尚未提交修复：旧 Drums 调用此前已注释，新主动未接入 | 新召唤的空闲时机、团战/控图收益、现有受控单位指令仍需研究；VT-031 |
| C742-17 | **Dazzle Shard 新 Through the Realm**：7.42 神杖碎片为 Nothl Projection 添加子技能；[`bots/BotLib/hero_dazzle.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_dazzle.lua)（`absent:dazzle_through_the_realm`） | E1 · 新能力未接入 | 尚未提交修复：保留旧 Projection 与 End 施法，未追加新子技能 | 需考虑本体受控/被追击、灵魂位置、残留时间和新技能的窗口；VT-027 |
| C742-18 | **Lone Druid Scepter Bear 复活英雄**：7.42 神杖赋予 Spirit Bear 复活英雄的新能力；[`bots/BotLib/hero_lone_druid_bear.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_lone_druid_bear.lua)（`absent:lone_druid_spirit_bear_summon_druid`） | E1 · 新能力未接入 | 尚未提交修复：仍以原熊技能实现为基线，不猜内部技能 ID | 先核对熊携带灵魂状态、复活时机及熊被击杀的高代价风险；VT-028 |
| C742-19 | **Undying Shard 新 Zombie Bite**：7.42 英雄 KV 中 Ability4=undying_bite，为魔晶新增单位目标技能；[`bots/BotLib/hero_undying.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_undying.lua)（`absent:undying_bite`） | E1 · 新能力未接入 | 尚未提交修复：原 Decay/SoulRip/Tombstone/FleshGolem 保留，新 Bite 未施放 | 需查真实可用条件和目标选择、机会成本与反例；VT-029 |
| C742-20 | **Pugna Oblivion Savant 重做 Scepter**：7.42 神杖使被动 Oblivion Savant 可支持冷却技能的额外施放；[`bots/BotLib/hero_pugna.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_pugna.lua)（`absent:pugna_oblivion_savant`） | E1 · 机制语义待核验 | 尚未提交修复：原 Q/W/E/R 流程仍在，但未显式纳入新冷却充能情况；未证实旧技能无法释放 | 只在确认 API IsFullyCastable 与充能行为后，决定如何利用二次施放和时机；VT-030 |
| C742-21 | **Death Prophet Shard/Scepter 分配变化**：7.42 Shard 改强化 Crypt Swarm 充能，Scepter 改 Spirit Siphon；[`bots/BotLib/hero_death_prophet.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_death_prophet.lua)（`present:function X.ConsiderE()`） | E1 · 机制语义待核验 | 尚未提交修复：原技能目标判断存在但没有对应新机制的实机效果证据 | 需研究满层/释放频率、Scepter 开团与目标价值，不能机械改旧数字；VT-033 |
| C742-22 | **Nyx Mana Burn Innate 更替**：7.42 Mana Burn Innate 替换为 Scarab Metabolism；本文件未见直接使用旧技能 ID；[`bots/BotLib/hero_nyx_assassin.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_nyx_assassin.lua)（`absent:nyx_assassin_mana_burn`） | 定向搜索未发现旧名称 | 尚未提交修复：本次扫描未发现该精确旧名引用，既有主动技能不据此重写 | 仍需独立核验新 Innate、升级表和其它变化；未称英雄全面兼容；VT-032 |
| C742-23 | **Lycan Apex Predator Innate 更替**：7.42 Apex Predator 被 Pack Hunter 替换；本文件未见旧 Innate 句柄；[`bots/BotLib/hero_lycan.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/BotLib/hero_lycan.lua)（`absent:lycan_apex_predator`） | 定向搜索未发现旧名称 | 尚未提交修复：本次扫描未发现该精确旧名引用，已移除的 Overlord 另追踪 | 新版 Innate 对召唤物与目标选择收益未研究；VT-032 |
| C742-14 | **Overlord 通用物品主动残留**：7.42 已移除道具，原通用使用路径仍有旧映射，可能已不可达；[`bots/ability_item_usage_generic.lua`](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/oha-next/bots/ability_item_usage_generic.lua)（`present:X.ConsiderItemDesire["item_helm_of_the_overlord"]`） | E1 · 机制语义待核验 | 尚未提交修复：与 C742-15 的物品初始化路径分开，不把死代码当作运行时崩溃 | 应在有调用证据后做局部清理，保留 Dominator 有效功能；VT-024 |

## 五位英雄的进阶审查

已逐项核对 Dazzle、Undying、Lone Druid 的 Spirit Bear、Pugna、Death Prophet 当前施法逻辑及固定 7.42 技能数据，写明是否真的存在旧指令失效、是否仅属未利用新版主动，以及默认出装/技能抢占风险。见 [五英雄进阶分析与正反例、未来施法时机债务](PATCH742_HERO_MECHANICS_DEEP_DIVE.md)。特别确认 Lone Druid 新复活主动的内部 ID 来自 **Spirit Bear 单位 KV**，不是英雄 KV；以及 Undying 在 pos1/2/3/4 默认买魔晶但缺少 Bite AI 的具体采购错配。

## 为什么没有直接写出全部新版技能 AI？

这次发现的 Weaver 友军 Time Lapse 是**已有策略对应施法句柄错误**，可以保留旧 `ConsiderTimeLapse` 的救援意图、只修发令目标和手动新增句柄保护；对应独立 [Draft PR #19](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/19) 已执行 **12/12 Lua 5.1** 生产函数正反例，尚待实机。

但 Dazzle 的 `dazzle_through_the_realm`、Undying 的 `undying_bite`、Lone Druid 熊的英雄复活、Chen 的 `chen_zealot`、兽王的 `beastmaster_summon_thunderhide` 和 Chaos Knight 的 `chaos_knight_armageddon` 都是**新能力**。不编写尚未掌握的目标资格、冷却、技能动作中断和机会成本规则，避免“有技能就乱按”反而变弱。

同理，Pugna 的 Oblivion Savant 神杖充能是被动改造而非必须`Action_UseAbility`的新技能；不能机械添加主动施法。死亡先知神杖/魔晶转移、Lycan/Nyx 新被动等也不能仅靠字符串确定策略错误。

## 对应的最小修复优先级

1. **立即且证据充分的错误**：Weaver 旧友军 Time Lapse（[#19](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/19)），Chen 旧 Summon Convert / Abaddon 旧伤害 / Javelin（[#17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17)），Meepo/Overlord（[#4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)）、先知（[#16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16)）、Leshrac（[#8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8)）；各独立 Draft 未合并。
2. **新版主动能力缺口**：Dazzle / Lone Druid / Undying / CK / Chen / Beastmaster。需要先把真实施法目标类型、技能生效状态与可观察失败条件确定，再设计新`Consider`，不能按英雄 KV 名称直接编造时机。
3. **机制语义复核**：Pugna（充能再施法、Life Drain 新机制）、Death Prophet（Shard/Scepter 对调）、Lycan/Nyx Innate、通用物品，必要时比较局部`GetSpecialValue*`返回和硬编码值。
4. **再扩完整补丁覆盖**：Valve 对绝大多数英雄的数值更改通常由游戏运行时 API 提供；只有代码写死过时数值、错误升技能/选装备或错误目标类型时需要改代码。剩余 [英雄文件矩阵](PATCH_7_42_HERO_MATRIX.md) 继续标注未审查，**不能宣布已经完成全量 7.42 适配**。

## 可复现的离线证据检查

```bash
python3 scripts/patch742_audit.py --check
python3 scripts/patch742_impact.py --check
python3 -m unittest discover -s tests -p 'test_patch742_impact.py' -v
```

审查输入：[docs/patch742_change_impacts.json](patch742_change_impacts.json)。检查会验证 21 个已记录的源码指纹、文档、128 个英雄文件及已移除物品在这些文件中的出现情况。已合并代码版本变化时需要更新基线/证据；它**不会联网提取官方所有补丁，也不会替代真实客户端动作验证**。

参考原用户定义的三维进度：[Issue / 需求状态台账（PR #2）](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/docs/upstream-fork-workflow/docs/ISSUE_AND_REQUIREMENT_STATUS.md)；即使一个最小兼容修复已通过 CI，独立的新版释放时机和胜率增强仍保持 TODO / PARTIAL。

