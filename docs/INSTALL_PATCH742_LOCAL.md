# 本地安装与使用：7.42 集成兼容修复（测试版）

> **这是测试分支，不是 Steam Workshop 正式更新，也不是已实机验证的版本。**
> `integration/patch742-smoke` 只组合 [#4](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/4)、[#6](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/6)、[#8](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/8)、[#16](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/16)、[#17](https://github.com/littleredcap/dota2bot-OpenHyperAI/pull/17) 的 7.42 兼容**最小修复**。未包含 [#159/#170/#176](https://github.com/littleredcap/dota2bot-OpenHyperAI/pulls) 的其它战术 PR，也未覆盖全部英雄。
>
> 安装依据：[OHA 上游手动安装说明 #69](https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/69) · [Local Dev Script / Local Host 指南 #68](https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/68)。当前集成测试分支尚未在 Dota 客户端实测。

## 一、Windows：推荐安装步骤

1. **获取本分支，而非 Workshop 或默认 main**：进入 [集成分支](https://github.com/littleredcap/dota2bot-OpenHyperAI/tree/integration/patch742-smoke)，选 **Code → Download ZIP**，解压并找到根目录 `bots` 文件夹。或者从 [CI Actions](https://github.com/littleredcap/dota2bot-OpenHyperAI/actions/workflows/integration-patch742.yml) 中一次**成功**的运行下载 `OHA-7.42-local-dev-scripts` 测试包（可能需要 GitHub 登录，artifact 有有效期）。
2. 在 Steam 库中右键 **Dota 2 → 属性 → 已安装文件 → 浏览**，然后进入：
   
   ```text
   <Dota 2 安装目录>\game\dota\scripts\vscripts\
   ```
   
   常见路径是：
   
   ```text
   C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\dota\scripts\vscripts\
   ```
3. **备份**旧的 `vscripts\bots`，如改名为 `bots_before_patch742`。如果旧 `bots` 是指向 Workshop 的**符号链接或目录联接**，只解除**链接本身**，不要修改目标 Workshop 目录。不确定链接性质时先不要删除文件。**不要运行原来的 `quick-install-oha.bat`**：它指向 Workshop 订阅包，会重新加载未合并的旧版。
4. 将下载的完整 `bots` 放在 `vscripts` 下，正确目录形状：
   
   ```text
   ...\game\dota\scripts\vscripts\bots\hero_selection.lua
   ...\game\dota\scripts\vscripts\bots\BotLib\hero_meepo.lua
   ...\game\dota\scripts\vscripts\bots\BotLib\hero_chen.lua
   ...\game\dota\scripts\vscripts\bots\FunLib\aba_item.lua
   ```
   
   不能形成 `...\vscripts\bots\bots\hero_selection.lua` 的多重嵌套。普通 Bot 模式先只复制 `bots/`；暂不覆盖 `game/Customize` 或其它高级环境配置。
5. 启动 Dota 2，选择 **Play Dota → Custom Lobby → Create**。服务器设为 **Local Host**。机器人脚本（天辉/夜魇）选 **Local Dev Script**，填充空位，并将机器人难度设为非 None。
6. Bot 名称通常带有 `.OHA` 后缀，说明至少加载了 OHA 家族脚本；**不证明它恰好来自本修复版本**。要确认具体版本，必须核对本地 `vscripts\bots` 不是旧 Workshop 链接、脚本文件来自当前 commit，并可比较来自同一 Actions 运行的 ZIP SHA-256。
7. 测试后退出游戏，将 `bots` 目录替换为步骤 3 保存的原版本即可回滚；如原来使用 Workshop 链接，需要恢复原先链接/订阅配置。

### 为什么不能直接订阅 Workshop？

各修复仍处于 GitHub Draft PR，未合入 fork 的 `oha-next`、`main` 或官方 Workshop。Workshop 下载的是发布者上传的脚本，不会从你的 fork 自动同步这些新改动。

### 先不要启用 FretBots/增强模式

首场兼容性检查建议使用普通 Local Host / Local Dev Script，而非 FretBots/Buff；增强模式可能赋予额外经验、金币与中立装备，并且 7.42 中立装备规则仍有待适配。无须开启作弊指令就可以检查基础技能和 Bot 选人行为。

## 二、Linux/macOS

Linux Steam 的常见目录：`~/.local/share/Steam/steamapps/common/dota 2 beta/game/dota/scripts/vscripts/bots`，也可能是 `~/.steam/steam/...`；macOS 通常在用户 `Library/Application Support/Steam` 下。**以 Steam“浏览本地文件”找到的真实目录为准。**

重要限制：[上游 Linux Issue #172](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/172) 已报告目录/`require` 的大小写敏感问题，部分旧安装器在 sudo 下错误使用 `/root`；[Flatpak Issue #169](https://github.com/forest0xia/dota2bot-OpenHyperAI/issues/169) 也指出独立安装路径问题。本 7.42 集成分支**没有修复这些 Linux/Flatpak 安装兼容问题**。不要直接执行旧版 Linux 安装器的 `sudo` 操作，也不要无差别把所有 Lua 字符串转小写。

## 三、后续实机检查（你方便时才做）

- 记下当前 Dota patch、OHA commit、使用的英雄和阵营。
- 确认 Local Dev Script 已加载、选人正常、没有 VScript nil 方法访问或脚本缺失错误。
- 分别测试 Meepo、Leshrac、先知、Chen、Abaddon、兽王/狼人等变化；Roshan 的复活计时需专门场景，不是打完一场普通局就全部验证。
- 如保留控制台日志，可选用 [PR #15 的离线日志异常分类工具](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/audit/patch742-hero-matrix/scripts/patch742_log_triage.py)，但它**不在这个兼容集成分支中**，也不能自动启动 Dota。
- 所有尚未验证的真实游戏动作继续按 [状态台账](https://github.com/littleredcap/dota2bot-OpenHyperAI/blob/docs/upstream-fork-workflow/docs/ISSUE_AND_REQUIREMENT_STATUS.md) 保留待测标记。没有错误日志不意味着已完整兼容。

## 四、开发者 Git 安装

```bash
git fetch origin
git switch integration/patch742-smoke
git rev-parse HEAD
# 将此 checkout 的 bots 文件夹复制到 Dota 2 vscripts/bots
```

游戏端不需要 TypeScript 或 Node，集成分支已包含可运行的 Lua 文件。**勿只复制一个 hero_*.lua**；英雄 Lua 还依赖同版本的公共模块和相应物品/模式逻辑。
