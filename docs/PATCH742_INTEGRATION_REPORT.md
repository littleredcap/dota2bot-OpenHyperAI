# 7.42 已有兼容修复：联合回归（Draft）

**基线**：`oha-next` = `cb814c6c8dc51ed08045d6efd9f4a48147992711`。仅检验已修复代码的**组合后离线行为**；没有 Dota 客户端、未合并到主分支、不能据此宣称 AI 更强。

## 集成的独立来源

| 原 PR | 已做最小修复 | 仍待策略/实机验证 |
| --- | --- | --- |
| [#4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4) | Meepo 删除旧 MegaMeepo 路径、Dig 空句柄保护，兽王/狼人删除旧 Overlord 默认出装和公共配方 | 新 Shard、Dig、装备替代的有效使用 |
| [#6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6) | Roshan 已观察击杀次数的保守复活上界 | 真实复活随机窗口 / Turbo / 合理争盾时机 |
| [#8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8) | Leshrac Nihilism 不再按旧虚无保命理由释放，保护空句柄 | 新缴械/驱散决策与队友控制配合 |
| [#16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16) | 先知 Oldgrowth 被动化后删除旧主动施法 | 新被动与其它技能协同 |
| [#17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) | Chen 旧 Summon Convert、Abaddon 错误 Shard 纯粹伤害、Javelin 清理 | Zealot、CK Armageddon、Coil 新生命消耗与装备 |

本分支未包括 #159/#170/#176 的战术修复，亦未启用实验 Meepo Shard。

## 同一文件的必要合并

`bots/FunLib/aba_item.lua` 在 #4 中删除 `item_helm_of_the_overlord` 的配方初始化，在 #17 中删除 `item_javelin` 基础分类。**必须同时保留两项删除**，不能直接以一个 PR 的文件覆盖另一个。

新增 `tests/test_patch742_integration.lua` 在模拟环境中实际 `dofile` 初始化整份公共物品库：当尝试访问已移除装备的组件时测试桩会主动报错，同时要求合法的 Helm of the Dominator 映射保留。另检查 Chen、先知、亚巴顿、Meepo、Leshrac 和 Roshan 的源码共同存在。

## CI 验收

五个原 PR 的生产函数回归（Meepo 7、Roshan 9、Leshrac 9、先知 4、Chen/Abaddon/物品 15），共 **44 个**已有场景，加上 5 个组合断言；同时对相关 Lua 源码和测试进行 Lua 5.1 语法检查。

CI 通过后打包 `OHA-7.42-local-dev-scripts`：包含 `bots/` ZIP 和 SHA-256，便于用户自行在 Dota 2 的 Local Dev Script 下测试；**它是测试包，不是官方发布版**。

[Windows/Linux/macOS 安装与回滚说明](INSTALL_PATCH742_LOCAL.md) · [问题与策略状态台账](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/docs/upstream-fork-workflow/docs/ISSUE_AND_REQUIREMENT_STATUS.md)

仍未完成任何实机行为测试和真实胜率对照，单个 PR 的 Draft 状态与独立回滚保留。
