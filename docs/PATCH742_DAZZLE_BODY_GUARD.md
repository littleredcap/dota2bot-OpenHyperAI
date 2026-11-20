# C742-17-GUARD：Dazzle Nothl Projection End 缓存对象校验

**实现状态**：MIN_FIX_DRAFT · **验证**：以 PR Actions 为准，尚无客户端 · **策略**：OLD（保持原结束投影时机）。

## 确定的问题

当前 `oha-next` 的 `hero_dazzle.lua::ConsiderNothlProjectionEnd` 取得 `GameStates.dazzleNothl[playerID].body` 为 `_bot`，却通过 `J.IsValid(bot)` 校验当前灵魂单位，然后对缓存的 `_bot` 调用 `J.IsRetreating(_bot)` 和 `J.GetHP(_bot)`。这会在缓存缺失/句柄失效时调用错误对象而产生运行时风险。原 `J.IsValid()` 定义在 `FunLib/jmz_func.lua`，对 nil、IsNull、可见性、存活和建筑类型进行检查。

### 最小修复

- 将要验证的对象改为真正用于后续决策的 `hBody`（缓存的物理本体），并允许整个缓存表或玩家条目为 nil。
- 当敌人列表为空时，仍按原策略尽快 End；当敌人存在时，继续保留“本体合法、正在撤退且 HP < 60% 才 End”的原定条件。
- **未增加任何 Through the Realm 主动使用策略**，不改变 Nothl Projection 开启时机、Shallow Grave/其它 Q/W/E 优先级或目标判断。
- 从生产源提取 `X.ConsiderNothlProjectionEnd` + 真正的 `J.IsValid` 定义，执行正反 Lua 5.1 Mock，覆盖 nil、缺失缓存、过时/不可见/死亡本体，及所有旧合法/不合法 End 场景。

### 尚待研究

- 7.42 Shard 提供的 `dazzle_through_the_realm` 的位移时机、身体 Root/Leash 状态、投影是否值得结束、危险位置评估与其它技能竞争，仍属 [C742-17](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/docs/upstream-fork-workflow/docs/ISSUE_AND_REQUIREMENT_STATUS.md) 的策略 TODO。
- 客户端 `VT-035` 需验证实际缓存及主/灵魂单位有效性；离线 Mock 通过不证明引擎上下文或胜率。
- 旧状态在某些引擎阶段可能不向 Lua 暴露有效 body；本补丁选择**无有效缓存就不触发该危险分支**，不尝试凭猜测恢复对象。

**回退**：revert 单独 PR；基于未改动的 `oha-next`；不自动合并。
