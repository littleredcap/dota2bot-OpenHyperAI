# Dota 2 客户端对局验证


每次客户端 Bot 对局均须按 [对局记录规范](BOT_MATCH_RECORDING.md) 完成单局报告并更新 [对局索引](BOT_MATCH_INDEX.md)。

用本地主机运行 OHA 对天地星的纯 Bot 对局。短局适合复测补刀、换血、拉野和补给等前期行为。比较发育曲线、推守塔和胜负时，保留完整录像。每局记下要验证的改动、对应的游戏场景和判断标准。

## 1. 核对脚本和测试条件

在仓库根目录运行 `git rev-parse --short HEAD` 和 `git status --short`，记录提交及参与本局的本地改动。Dota 2 从 `<Dota 安装目录>\game\dota\scripts\vscripts\bots` 加载本地开发脚本。若 `bots` 是 Windows 目录联接，用 PowerShell 的 `Get-Item -LiteralPath <bots 路径>` 核对 `Target`。若使用文件副本，至少比对这次改动的 Lua 文件和选人脚本。`bots_example` 是 Valve 的示例目录。

天地星（BBOT）选择 **天地星AI · 固定搭配**，创意工坊 ID 为 `1627071163`。随机搭配的 ID 是 `1573671599`，有独立的脚本目录。若房间下拉菜单缺少固定搭配，先在对应工坊条目核对订阅及本地下载状态。Windows 上的固定搭配脚本位于 `<Steam 库>\steamapps\workshop\content\570\1627071163`。记录脚本版本日期。固定搭配脚本的开场问候也可能显示「随机搭配」，以房间设置、工坊目录和实际选人为准。 [固定搭配](https://steamcommunity.com/sharedfiles/filedetails/?id=1627071163) · [随机搭配](https://steamcommunity.com/sharedfiles/filedetails/?id=1573671599)

默认使用双方困难难度、全英雄选择、标准地图、十个 Bot。OHA 使用公平配置，FretBots 和 Buff 关闭。房间开启「允许作弊指令」时，本流程只用它调节本地主机速度。英雄资源和局内操作由 Bot 自行决定。

## 2. 固定双方英雄

这套对照使用火枪（狙击手）、骷髅王（冥魂大帝）、龙骑、术士和小 Y（暗影萨满）。用英雄内部名指定五人，选人结束后以界面或录像中的十个英雄为准。

跨阵容验证沿用本节的选人办法，让两边同时换成同一套英雄。第二套建议用近战核心搭配法术爆发，重点核对接团和强势期判断。[阵容策略与跨阵容验收](BOT_LINEUP_STRATEGY_7_42.md)

### 天辉 OHA

在 `<Dota 安装目录>\game\dota\scripts\vscripts\game\Customize\general.lua` 放置本局配置。先备份已有文件。如文件已有需要保留的设置，在测试副本里合并下面的字段，赛后恢复原文件。

```lua
local config = require('bots.Customize.general')
config.Enable = true
config.Allow_Repeated_Heroes = true
config.Allow_Trash_Talk = false
config.Allow_AI_GPT_Response = false
config.Radiant_Heros = {
    'npc_dota_hero_skeleton_king',
    'npc_dota_hero_sniper',
    'npc_dota_hero_dragon_knight',
    'npc_dota_hero_warlock',
    'npc_dota_hero_shadow_shaman',
}
return config
```

OHA 换到夜魇时使用 `Dire_Heros`。OHA 可能打乱选人顺序，判断是否镜像时比较五个英雄的集合。对线分析另从小地图或录像核实谁走中、谁搭哪位辅助。

### 夜魇天地星

备份 `workshop\content\570\1627071163\hero_selection.lua`，记录原文件哈希。备份放在游戏目录之外。打开本地文件，在 `function Think()` 前声明本局英雄列表。

```lua
local mirrorDraft = {
    'npc_dota_hero_sniper',
    'npc_dota_hero_dragon_knight',
    'npc_dota_hero_skeleton_king',
    'npc_dota_hero_shadow_shaman',
    'npc_dota_hero_warlock',
}
```

在 `Think()` 的自定义挑选和常规挑选分支，把各自的 `SelectHero(id, sSelectHero)` 调用改为 `SelectHero(id, mirrorDraft[i] or sSelectHero)`。`i` 沿用循环里的队内槽位。选人以外的 BBOT 逻辑保持原版。若创意工坊更新导致代码结构变化，重新检查实际传给 `SelectHero` 的值。

## 3. 建房和验收

1. 在客户端右下角依次选择「开始 DOTA」「比赛房间」「创建」。在房间设置里选择「本地主机」和「全英雄选择」，勾选「机器人填满空位」。房间可见性设为隐藏。
2. 设天辉机器人为「本地开发脚本」，夜魇机器人为「天地星AI · 固定搭配」，双方难度均为「困难」。需要加速时勾选「允许作弊指令」。
3. 点自己名字旁的 `×` 进入「未分配玩家」，确认两个队伍的十个席位均留给 Bot，然后开始比赛，以观察者身份进入。
4. 等选人结束。天辉应显示带 `.OHA` 的 Bot 名称，夜魇应显示天地星 Bot。核对双方各有指定五人，最好留一张选人截图。如阵容不一致，退出这场试局，优先核对房间所选版本、创意工坊 ID 和两个本地配置的落点。

## 4. 开启并测定最高可用倍速

客户端「设置 → 游戏 → 杂项」启用控制台。在「设置 → 快捷键 → 界面」查快捷键，也可用设置搜索框搜索「控制台」。本机恢复常用键位后，用反斜杠键（`\`）打开，按 `Esc` 关闭。此前对局临时用过 `F10`。如果当前键盘布局无法打开控制台，可临时绑定一个空闲键。

在本地主机进入比赛后打开控制台，按顺序逐行输入，每行按一次回车。

```text
sv_cheats 1
host_timescale 3
help host_timescale
```

`help host_timescale` 应显示当前值为 `3`，默认值为 `1`。收到 `cheat protected` 时检查房间是否为本地主机，再确认 `sv_cheats 1` 已执行。设置成功后关闭控制台，观察游戏时钟是否加快。

- `3` 已在本机对照局中实测生效。客户端的 `help host_timescale` 没有列出数值上限。要找更快的可用值，在单独的短试局从 `3` 提到 `4`、`5`，每次都查询实际值。
- 每档用现实时间计时至少 30 秒，实际倍速为「游戏时钟增加的秒数 ÷ 现实经过的秒数」。屏幕上的观战播放按钮会随模式变化，测量时以本地主机的游戏时钟为准。
- 选择实际推进最快且运行稳定的一档。检查持续卡顿、Bot 停止出指令、成串的 `Excessive frame time ... clamped` 或 Lua 运行错误是否随提速出现。若出现异常或继续提高参数也没有更快，退回最近一档稳定值。正式对照从相同的游戏时间设为相同倍速，并记录任何变更的时间。
- 需恢复常速时，先执行 `host_timescale 1`，再执行 `sv_cheats 0`。若出现 Lua 错误，记下游戏时间和完整堆栈。可以用 `condump` 请求导出当前控制台缓冲区，并确认 `condumpXX.log` 已生成。缓冲区较早的内容可能已被覆盖。

## 5. 采样、判定和复原

| 时间 | 至少记录 |
| --- | --- |
| 5:00、10:00 | 三路实际配对、正反补、净资产和死亡。核心缺刀时回看核心离线时长、敌方反补、辅助的补刀归属和换血。 |
| 16:00、20:00 | 人头、净资产差、被拆和拿到的塔、核心线野收入、关键装备到手时间。 |
| 终场 | 胜方、局长、比分、终场净资产，以及三核心的 K/D/A、GPM/XPM、英雄和建筑伤害。 |

从游戏时钟 `0:00` 起算，表里注明录像采样的实际时间。开过倍速时，需要从录像校对局长。例如 `9106112564` 的客户端概览显示 `27:23`，录像游戏时钟在约 `48:58` 结束。每千金英雄伤害按 `英雄伤害 × 1000 ÷ 总获得金钱` 计算。只有 GPM 时，可以用 `GPM × 游戏分钟数` 估算总获得金钱并注明估算。净资产单独记录。按实际分路、位置和英雄对照，GPM 或输出高低结合关键消耗、参战、存活及拆塔表现解释。

对要验证的技能、道具或守塔决策，至少留一次有时间点的可观察证据，例如战斗日志中的施放、录像中可见的冷却、回防到场或留下吃线的英雄。必要条件一直未出现时，记作「本局未覆盖」。看胜率时多打几局并交换阵营，同一批对照沿用版本、难度、地图和倍速。参考[已有对局评估和场景](BOT_MATCH_EVALUATION_7_42.md)。

归档结算数据、比赛 ID 或 `.dem` 文件名。Windows 本地录像通常位于 `<Dota 安装目录>\game\dota\replays`，进行中可能名为 `auto-…-start-….dem`。检查录像可读后恢复天地星原选人文件和 OHA 原有用户配置。原先无 OHA 用户配置时移除本局新增的 `general.lua`。如果文件在对局期间又被改动，先核对哈希并保留更新。恢复临时改过的控制台键位。
