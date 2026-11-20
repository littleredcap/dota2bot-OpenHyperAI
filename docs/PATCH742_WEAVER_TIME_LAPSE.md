# C742-16：Weaver 神杖 Time Lapse（友方）7.42 最小修复

**来源**：[Valve 7.42 官方补丁](https://www.dota2.com/patches/7.42)（Weaver：神杖强化 Time Lapse 移到共享冷却的新独立技能）与当前 [7.42 英雄 KV](https://github.com/dotabuff/d2vpkr/blob/master/dota/scripts/npc/heroes/npc_dota_hero_weaver.txt)。

## 静态错误及证据

- 当前 `oha-next` 的 `bots/BotLib/hero_weaver.lua` 里，原 Time Lapse 使用 `weaver_time_lapse`。这在 7.42 仍是**无目标、自身回溯**技能。
- 原代码 `X.ConsiderTimeLapse()` 在 Weaver 持有神杖并检测到核心队友残血受追击时返回队友句柄，但 `X.SkillsComplement()` 却用旧 `TimeLapse` 发送 `Action_UseAbilityOnEntity(TimeLapse, Target)`。7.42 不再是该技能的合法目标形式。
- 当前 7.42 KV 明确 `Ability4=weaver_time_lapse_ally`，其 `AbilityBehavior` 为 `DOTA_ABILITY_BEHAVIOR_UNIT_TARGET`，对友方单位施放，范围 500，且与原 `weaver_time_lapse` 共享冷却。

**证据等级 E2**：确定的静态结构冲突，非已在 Dota 2 客户端复现。

## 精确改动

- 每次 `SkillsComplement` 都获取 `weaver_time_lapse_ally`，兼容游戏中途才获得神杖的情况。
- 保持 **Self** 回溯继续使用原 `weaver_time_lapse` 的无目标发令。
- 仅**已有判断认为值得救队友**时，且确实有神杖、`weaver_time_lapse_ally` 句柄存在并可释放，使用新技能的施法范围和单位目标发令。
- 如果新的友方技能句柄不存在、不能释放或考虑函数没有目标，则不占用本帧行动，继续原有 Shukuchi/Swarm 判断。
- 不改动原先是否救援的 HP、核心角色、受追击条件，也不改变其它技能施法优先级。

## 测试与边界

- `tests/test_patch742_weaver_time_lapse.lua`：**直接提取原生产函数** `SkillsComplement` 与 `ConsiderTimeLapse` 执行 12 个 Lua 5.1 Mock 场景，包括自身无神杖、残血核心救援、能力缺失、神杖未到手、冷却、距离、未受追击、非核心、局内获得神杖及旧分支不存在。
- `luac5.1 -p` 源码/测试语法 + GitHub Actions。
- **尚未运行客户端**：实际新增能力是否被 `GetAbilityByName` 获取、共享冷却、是否成功救援、动作队列/禁用帮助设置均需未来客户端验证；此处只按已有施法判断进行**最小兼容修复**，**不代表友军回溯时机已经优化**。
- 后续策略工作：救援目标评分、对方关键技能/伤害、真正能否挽救队友、我方位移/团战机会成本、与 Shukuchi/Swarm 的优先级竞争等需单独研究与实机验证。

**未修改**：Weaver 的其他旧施法条件/购买方案，`main` / `oha-next` 及其它 PR。
