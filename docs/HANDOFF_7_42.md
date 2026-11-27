# OpenHyperAI 7.42 交接

继续在工作分支 `fix/7.42-confirmed-followups` 开发。本轮行为改动提交为 `71a37a2`，分支历史已包含旧草稿 #28 的改动。后续通过 PR 评审进入主线。[GitHub 工作分支](https://github.com/littleredcap/dota2bot-OpenHyperAI/tree/fix/7.42-confirmed-followups)

## 现状与下一步

- 这批改动覆盖补刀与补给、清线后刷野、外塔回防与侧路换塔、战后推进。最新中期改动已通过 30 组离线回归及 311 个 Lua 文件的语法检查，待实战复测。上一场完整录像 `9106667244` 是对照基线，20 分钟 OHA 净资产落后 8,648，塔伤 700 比 8,285。[对局复盘](BOT_MATCH_EVALUATION_7_42.md)
- 下次优先看 12–25 分钟能否及时回防、侧路兵线能否到塔、赢团后有没有拿塔。中路连续被远程清兵时，现有逻辑会逐波重算。记录是否反复停推，再决定何时组织换路。中立装备后续先核对公平模式的选装与附魔接口，再补 Red Ledger、Brick 等主动用法。

## 验证规范

- 先用 Lua 5.1 运行 `npm run check:offline` 和 `git diff --check`，跳过构建。Windows 上已有 `vscripts/bots` 联接到 `D:\workspace\OpenHyperAI\bots`，开局前核对目标，保留游戏示例目录 `bots_example`。
- 实机用本地主机，天辉 OHA 对夜魇天地星 AI · 固定搭配（工坊 `1627071163`）。双方困难难度，都选火枪、骷髅王、龙骑、术士和小 Y。关闭 FretBots 和 Buff，资源按正常规则获取，决策只用可见、已目击和公开的信息。加速使用已实测的 `host_timescale 3`。[建房、选人和录像流程](BOT_MATCH_VALIDATION.md)
- 按游戏时钟记录 5、10 分钟各路补刀和净资产，12–25 分钟记录回防到场、侧路到塔、塔伤与收入来源。保存比赛 ID 或录像，胜率只计完整局。优先离线复现，需引擎确认的场景集中到客户端。

## 暂缓项

尸王 Bite 和未经适配的新神杖、魔晶保留现有暂缓购买设置。若单独复测拉席克 Nihilism，固定提交 `74b6668fda1ea85bf9e39c6e806707379e03cbab`，只记录普通神杖后技能是否出现及有无施放证据。[Draft #23](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/23)
