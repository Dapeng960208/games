# 深渊拾荒者 / Abyss Salvager

原生 Godot 2D 单人游戏，交付范围为附件的 **M0 与 M1**。主菜单 → 营地 → 单房战斗 → 拾取三件机制遗物及废金 → 撤离／死亡 → 一次结算与永久保存 → 再次出发。

正式工程位于 `D:\dev\zgame\abyss-delver\godot`。上一级已有 Phaser 浏览器工程原样保留；本目录是独立原生工程，不依赖 Node、浏览器或网络。

## 直接运行

交付机器上双击 `RUN_GAME.cmd`，启动同目录自带的便携 Godot 和本工程。无需安装 Godot、注册账号或联网。

Windows 独立构建位于 `build/windows/AbyssSalvager.exe`。该可执行文件嵌入游戏资源，旁边附引擎与字体许可。运行验证记录见 [测试记录](docs/TEST_PLAN.md)。

从源码运行：

```powershell
.\tools\run.ps1
```

打开编辑器：

```powershell
.\tools\run.ps1 -Editor
```

如命令行执行策略不允许脚本，可双击 `RUN_GAME.cmd`；该启动器只对这次子进程设置执行方式，不修改系统策略。

## 已核实的环境

- Godot **4.7.2.stable.official.ed1daf0bf**，GDScript，2D，Compatibility / OpenGL 3.3。
- Windows 10 Enterprise LTSC 10.0.19044 x64；Intel Iris Xe Graphics，驱动 32.0.101.7085。
- 逻辑画布 1280×720，按窗口同比缩放；非 16:9 留边。营地截图已检查 1280×720、1920×1080、2560×1440。
- 版本来自实际可执行程序输出；不将此记录解释为“永远最新”。下载来源与校验和见 [环境记录](tools/godot/ENVIRONMENT.md)。

## 怎么玩

1. 主菜单建立档案，进入地表营地，选择“乘升降机 · 开始远征”。已有档案用“继续 · 返回营地”。
2. WASD 移动，鼠标瞄准，按住左键连续射击；空格冲刺并短暂无敌。红色扇形和读条是近战敌人的攻击预警。
3. 房间上方三个发光装置从左到右为分裂镜片、余烬灯芯、弧电线圈；靠近按 E 拾取。可以三件共存。
4. 击倒机械守卫后靠近铜色碎片吸附拾取废金。左下实时显示携带量与死亡保留量。
5. 回到房间西侧升降机，靠近按 E，确认撤离。守卫会持续增援，留在矿井没有强制倒计时。
6. 撤离保留全部废金；死亡或确认放弃保留 20%，向下取整。角色与起始武器保留，本局遗物清空，发现记录永久保存。
7. 结算后回营地即可再次出发。Tab 查看已装备遗物，Esc 暂停／返回；暂停菜单可以确认放弃。恢复后先松开攻击、冲刺、交互键，再继续操作。

设置已实现中英文切换、全屏／窗口和低闪烁。已装备遗物也可直接点击底部图标，立即暂停并查看机制。没有脉冲、经验等级、小地图、手柄或营地购买入口。

人物、怪物、三件遗物、矿井主视觉与地板均按本项目主题用内置 imagegen 原创设计并接入实际游戏；不是仅供展示的概念图。提示词和来源见 `docs/CHARACTER_ART.md`、`docs/IMAGEGEN_PROMPTS.md`、`docs/KEYART_PROMPT.md`、`docs/FLOOR_PROMPT.md`。

## 三件遗物的真实效果

| 遗物 | 当前机制 |
|---|---|
| 分裂镜片 | 主弹首次命中生成 2 枚侧弹，各 8 伤害，即基础 20 的 40%；侧弹不会继续分裂 |
| 余烬灯芯 | 武器投射物命中附加 3 秒燃烧，每秒 3 伤害；重复命中刷新时间，不叠层 |
| 弧电线圈 | 每第三发主弹的首次命中向附近最多 2 个其他敌人放电，各 7 伤害，即基础的 35% |

原始攻击、子弹、燃烧和电弧分别标记来源。附加伤害不能继续触发武器命中效果，另有触发预算和对象上限。数值集中在 `config/balance.gd`。

## 存档

正式档案：`%APPDATA%\AbyssSalvagerM1\profile.json`。

永久档案包含废金、发现记录、累计结算次数、最近一次结算和设置。奖励、发现合并、结算记录与活动远征清除写在同一份带版本的事务文档中。临时文件、备份和修订号用于恢复完整候选；损坏文件保留并显示提示。

M1 **不恢复远征中途状态**。正常关闭窗口或退出须先确认放弃；强制终止后，下一次启动按最近成功保存的本局携带量执行一次放弃结算，绝不恢复房间。写入失败不会展示成功到账，结算失败时保留原结局并提供重试。

测试使用 `user://test_*.json` 与其他专属测试目录，不重置正式玩家档案。

## 验证与导出

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test.ps1
```

上述测试包含存档与结算、真实战斗对象、主场景输入和暂停／UI 逻辑。图形测试需使用非 headless 引擎：

```powershell
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/test_ui.gd -- --test-profile=user://test_ui_graphics.json
```

会生成实际渲染截图到 `artifacts/`。跨进程测试、失败注入与遗物截图入口见 [TEST_PLAN.md](docs/TEST_PLAN.md)。所有测试脚本必须使用隔离档案。

Windows 导出（需同版本 Windows x64 export templates；本次交付机器已安装）：

```powershell
New-Item -ItemType Directory -Force .\build\windows | Out-Null
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" .\build\windows\AbyssSalvager.exe
```

导出配置已排除文档、测试、运行证据和工具目录。移交源码时不需要 `.godot` 缓存；Godot 首次打开会重新导入资源。

## 结构与后续

| 位置 | 职责 |
|---|---|
| `scenes/` | 独立主场景、角色、敌人、投射物、房间、HUD |
| `scripts/core/` | 局内状态、永久存档、开始与结算 |
| `scripts/combat/` | 角色输入、伤害／生命、敌人状态、弹体和遗物效果 |
| `scripts/ui/` | 页面、暂停栈、焦点、显示与本地化；不发放奖励 |
| `localization/strings.json` | 已实现界面的中英文文本键 |
| `config/balance.gd` | 集中数值与死亡保留函数 |
| `tests/`、`artifacts/` | 可复现测试与实际执行证据 |

完整交接请读：[设计](docs/GAME_DESIGN.md)、[UI 规范](docs/UI_SPEC.md)、[路线图](docs/ROADMAP.md)、[测试记录](docs/TEST_PLAN.md)、[已知问题](docs/KNOWN_ISSUES.md)、[素材来源](docs/ASSET_LICENSES.md)。

M2—M4 未实现。单测试房用于验证基础战斗和结算，不代表已经完成 15—25 分钟远征、玩法平衡或最终美术音效。没有联网、账号、统计收集或其他外部服务。
