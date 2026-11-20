# 7.42 第二批确定性兼容修复：Chen / Abaddon / 公共物品

**基线**：`oha-next` SHA `cb814c6c8dc51ed08045d6efd9f4a48147992711`。**仅静态源码和 Lua 5.1 Mock 验证，没有在 Dota 2 客户端实机运行。**

## 1. 判断何时施法，与发出施法动作的区别

OHA 的英雄脚本通常在 `X.Consider*` 内根据游戏状态返回施法意愿/目标，再由 `X.SkillsComplement` 调用 `Action_UseAbility*` 发送指令。这次主要排除版本更新后**已不再成立的施法路径和错误伤害预测**，没有用全新自制策略替换英雄原有判断。

### Chen — 停用已移除的 Summon Convert

- 7.42 英雄定义 [npc_dota_hero_chen.txt](https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/heroes/npc_dota_hero_chen.txt) 指出 Ability4 为 `chen_zealot`；旧 `chen_summon_convert` 已不再是有效英雄技能栏能力。
- 原代码 `SummonConvert:IsFullyCastable()` 在句柄缺失时可触发 Lua nil 调用；现移除旧句柄、旧 Consider、旧施法动作及仅供旧 Consider 使用的死代码。
- 7.42 [Zealot](https://www.dota2.com/patches/7.42) 的主动功能是**复活指定的已受膏 Zealot**，不是旧的“随机召唤一个新兵”。因此**不得把旧的“刷野/推线/进攻时施放”条件直接搬给 Zealot**。
- 原有 `Hand of God`、`Penitence`、`Holy Persuasion`、`Divine Favor` 的先后顺序与考虑函数不变。
- **尚未实现**：Zealot 复活/任命、Holy Persuasion 自身施法召回、单位识别与冷却协调。这些需要确认可观察的 Zealot 存活标记、施放可用条件和技能响应，不应猜测。

### Abaddon — 避免误判魔晶 Coil 为纯粹伤害

- [Valve 7.42](https://www.dota2.com/patches/7.42)：Mist Coil 的自伤改为**生命消耗**（数值不变），新增自身/敌方移速效果并由 Scepter 提供范围攻击；目前 Shard 增强的是 **Aphotic Shield**，不再把 Mist Coil 变成基于普通攻击的纯粹伤害。
- 旧代码使用 `if J.HasAghanimsShard(bot) then nDamage=bot:GetAttackDamage(); nDamageType=DAMAGE_TYPE_PURE` 错误估计对敌人是否致命，可能导致放弃本能击杀的目标或对不该死的目标过度承诺。已删除这个过时分支。
- 删除未被任何行为逻辑使用的 `GetSpecialValueInt('self_damage')` 查询；其字段是否保留不影响现有判断。
- 不新增未验证的 `GetHealthCost` Bot API；是否能支付生命消耗由客户端引擎 `IsFullyCastable()` 优先负责；**低血量施法风险和神杖 AoE 收益仍待专项验证**。
- 原有护盾救援、打断、目标优先级与发令方式不变。

### 公共物品 — 移除已退场的 Javelin 分类

- [Valve 7.42](https://www.dota2.com/patches/7.42) 明确移除 Javelin，[商店数据 shops.txt](https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/shops.txt) 也不包含该商品。
- 从 `FunLib/aba_item.lua` 的 `sBasicItems` 中移除 `item_javelin`。不改变普通购买配方解析，仍由 `GetItemComponents` 获取当前组件。
- 已移除的 Helm of the Overlord 在 `aba_item.lua` 的旧初始化问题**属于已存在的 [PR #4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)**，本 PR 不重复修改同一逻辑；合并时须联合检查。

### Chaos Knight — 数据已查实，主动策略未擅自新增

- 当前 [英雄技能定义](https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/heroes/npc_dota_hero_chaos_knight.txt) 表明 Ability4=`chaos_knight_armageddon`、Ability6=`chaos_knight_phantasm`、Ability7=`chaos_knight_armageddons_flank_end`。
- [Valve 7.42](https://www.dota2.com/patches/7.42) 说明 Armageddon 为**地点施法**，要求 Phantasm 生成的幻象存活；冲锋准备时间内及冲锋期间其它技能可能中断冲锋。直接在原技能循环中加施法可能毁掉原有 Q/W/R 连招。
- 本 PR 通过**真实 `aba_skill.lua::GetAbilityList()` Mock**验证这套新槽位结构不会挤占原有 [1],[2],[3],[6] 索引；不以此声称 Dota 客户端技能槽绝对正确，更不将缺少新主动策略认定为运行时报错。
- 等能测试施法中断、幻象身份、目标点和打断逻辑时，再独立提出 CK 新技能策略 PR。

## 2. 可验证的回归契约

`tests/test_patch742_chen_abaddon_items.lua` 从真实生产 Lua 提取：

- Chen `SkillsComplement()`：无技能提案不报错，Hand of God、Penitence、Holy Persuasion、Divine Favor 依旧按原优先级行动，不能行动时不操作。
- Abaddon `ConsiderMistCoil()`：有无 Shard 都以真实技能的魔法伤害作单目标击杀估算、无法施放时返回 None，不访问旧 self_damage 字段。
- `aba_item.lua::sBasicItems`：实际初始化结果不含 Javelin，保留其它合法基础组件。
- `aba_skill.lua::GetAbilityList()`：针对官方英雄数据的 Chen/CK Ability4 与 Ability6 测试新 innate / hidden slot 的映射。

**离线通过 != 实机兼容通过**：未验证技能内部 KV 与当前用户 Dota 客户端一致性、Zealot 的复活触发、CK 冲锋时序、Abaddon 生命消耗特性或装备配方。不得借 CI 结果宣称胜率提高。

## 3. 后续合并

本 PR 基于 `oha-next` 并保持 Draft。与 #4 可能存在对 `aba_item.lua` 的共同修改（分别位于基础物品列表与配方初始化），合并前必须合并验证。其他 7.42 英雄风险继续在 [静态兼容矩阵 PR #15](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/15) 中标记为未充分验证。
