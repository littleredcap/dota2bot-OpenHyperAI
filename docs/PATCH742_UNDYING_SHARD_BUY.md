# C742-19-BUY：Undying 的 7.42 默认 Shard 购买与当前可用策略一致性

**实现状态**：MIN_FIX_DRAFT · **验证**：以本 PR CI 为准 · **策略**：TODO（Zombie Bite 时机仍未实现）。

## 依据和局部修复范围

[Valve 7.42](https://www.dota2.com/patches/7.42) 明确移除 Aghanim's Shard 对 Tombstone 的旧升级，改为授予新主动 **Zombie Bite**。固定 [客户端 Hero KV](https://github.com/dotabuff/d2vpkr/blob/77a6ccca87bab183caaf0c09fd2813f2695b7a5b/dota/scripts/npc/heroes/npc_dota_hero_undying.txt) 的 `Ability4=undying_bite`，`IsGrantedByShard=1`，`AbilityUnitTargetTeam=ENEMY`。

原 `hero_undying.lua` 的 `SkillsComplement` 仍只支持 Decay、Soul Rip、Tombstone、Flesh Golem；没有新 Bite 的 `Consider` 或 `Action_UseAbilityOnEntity`。但 pos1/2/3/4 默认列表仍把 Shard 作为主动采购项目。这意味着 Bot 目前没有为这项购买实现新版主动的可靠收益路径，而不是说 Shard 在游戏里无用。

最小改动：**只从三个实际存储的默认出装列表 pos1、pos3、pos4 删除 `item_aghanims_shard`；pos2 继承 pos1 因而同步生效。pos5 本就不买，无需修改。**

其余装备次序、技能、天赋与普通购买处理不变。`J.SetUserHeroInit` 仍可在生产中覆盖用户自定义出装；本修复**不禁止用户自行买 Shard**，也不拦截来自 Tormentor 等合法来源的 Shard（该途径的游戏行为尚未实机验证）。FretBots/PvN 特殊出装保持原状。

## 正反回归

`tests/test_patch742_undying_shard_default.lua` 从**实际生产文件**抽取默认购买列表和 `J.SetUserHeroInit` 的调用区域。测试所有 5 个角色的购买链、关键原装备、pos2 继承、用户自定义 Shard 仍可选、PvN 模式及原技能/卖出设置不变。通过 `Lua 5.1` 执行，并检查所有修改源码的语法。

## 未来策略和验收门槛

Zombie Bite 不是“拿到魔晶就自动会用”，必须独立设计：对英雄与对非远古小兵的不同价值（沉默、吸血、可控僵尸）、能否安全突进、队友补刀资源、Debuff Immunity、未见目标与自身行动机会成本。**不能拿旧 Tombstone 的 Shard 使用意图直接当新 Bite 策略**。

未来若制定有验证的 Bite 决策，应重新评估各位置默认购买时机，而不是永久禁止魔晶。相关需求：C742-19、C742-19-BUY 与客户端 `VT-029 / VT-034`。

**限制**：未进行 Dota 2 真实游戏购买或技能执行测试，不能证明经济/胜率提升。独立 Draft，基于 `oha-next`，不直接合并。
