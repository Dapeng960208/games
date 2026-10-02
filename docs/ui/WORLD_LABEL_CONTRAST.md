# 场景交互文字：2K 对比度补修

日期：2026-10-02。范围仅为 `room_objectives.gd` 的目标名称／阶段文字，以及 `room_props.gd` 的信标名称／说明／休眠文字。

## 问题与处理

实际 L06、L10 的 2560×1440 游戏截图中，浅石地面上的目标与信标文字呈浅灰色。原代码直接加载 NotoSansSC 可变字体，其 fvar 默认字重和 OS/2 字重均为 **100**，小字细线缺少实色笔画；可读的 HUD 已明确使用字重 500。原文字也与道具共用调色材质，但独立材质一次图形验证后仍然灰细，不能把材质当作已确认的唯一原因。

- 新增 `scripts/ui/world_label_layer.gd`：文字置于宿主的独立子画布，以无光照 `CanvasItemMaterial` 绘制，不继承道具调色。道具本身继续使用原材质
- 世界文字统一复用 FontVariation **wght=500**，与现有 HUD 相同；原字体文件、字号和字符串不变
- 采用已有米白／常青墨色主题，配薄黄铜边和小圆角底。底色不透明，地图明暗不再改变文字背景对比
- 主要文字／底色对比度 **11.27:1**；说明和休眠文字 **6.30:1**。比值是 sRGB 线性化后计算的颜色对比度，不能替代实际像素观察
- 目标保留 17px 字号及脚点下 44 的基线；信标保留 15/13px 字号、49/67 基线、原面板位置和 40 高度。未更改原字符串、键位或内容条件
- 保留目标 260 范围／`always_label`、active／carried／destroyed／done／phase 条件；保留信标 160 范围、视线、语言、armed／used／cooldown 条件。绘制无独立逻辑更新，不消耗信标、不推进目标

## 定向验证

`tests/test_world_label_contrast.gd/.tscn` 使用隔离档与真实 L06、L10 生产房间。只检查与本次文字补修相关的内容，不运行平衡套件，S11 继续暂停。

- 无图形最终检查：**43 项，0 失败**；Godot 4.7.2，未出现 ERROR／SCRIPT ERROR
- 检查独立材质、原变换／深度、宿主重绘连接、无独立 tick、房间／碰撞／目标／信标／镜头状态不变，以及随宿主释放
- 图形模式固定 1280×720 逻辑画布、真实 **2560×1440 framebuffer**。生成 L06／L10 中央视角，以及信标中英文可用／需要重新靠近／休眠六状态；检测实际深色字形像素
- 首次图形运行（仅材质／底板修复，尚未设置字重 500）为 **80 项，21 失败**，截图仍显灰细；因此继续定位并修正了可变字体默认字重。首次失败截图保留在 ignored 的 `artifacts/world-label-contrast/v1/`
- 最终字重版本图形复测：**81 项，0 失败**，Godot 4.7.2／OpenGL Compatibility／llvmpipe，真实 2560×1440；无 ERROR／SCRIPT ERROR，仅软件驱动不支持切换 VSync 的警告。日志为 `artifacts/world-label-gpu-v2.log`
- **八张实际截图均已查看**：L06 两个可见回路提示、L10 中央复苏信标，以及中英文各三种信标状态均有清晰的实色笔画。L10 可用状态下相邻信标／幼巢的底板边缘相接，完整文字仍可读；保留固定基线，未借移动功能点掩盖问题。此证据仅覆盖上述状态，不等于全部地图、拥挤战斗或整个 UI 的最终验收
- 本补修可独立作为代码检查点；截图不入库，地图／野怪美术审批不属于此检查点。当前用户运行中的独立预览未被修改

夹具明确重绘冻结房间的文字。L10 正中点至东回流幼巢距离为 262.606，超过原 260 范围，因此该视角不显示此目标文字；旧环境夹具移动玩家后未请求文字重绘，可能保留先前位置的提示。信标六状态视角在原范围内显示并检查该目标。没有扩大提示范围或移动功能点。夹具读取当前批准的生产背景；L06／L10 原生美术包尚未批准时，背景使用原有 fallback，不将屏幕 2K 写作已批准的原生美术升级。

PowerShell 入口：`tools/test.ps1 -Suite world_label_contrast -SkipImport`；图形检查追加 `-Graphical`。

Linux 直接入口：`tools/godot/godot --headless --audio-driver Dummy --path . res://tests/test_world_label_contrast.tscn -- --test-profile=res://artifacts/world-label-contrast/test_world_label_contrast_headless.json`。图形运行移除 `--headless`，需已可用的私有显示器；受限环境将 HOME、XDG_DATA_HOME、XDG_CACHE_HOME 指到可写的隔离目录，并以 120 秒 timeout 限制运行。

截图、日志、隔离档均位于 ignored 的 `artifacts/world-label-contrast/`，不入 Git。本次不修改地图贴图／加载器、普通怪美术、玩法参数、实际玩家存档或公开部署。
