# B05 / B06 停止开发 checkpoint

> 历史保存记录：用户已于本日明确恢复任务。本轮首房与首领美术验收的当前结论、实机证据和范围见 [美术验收](b05_b06_art_acceptance.md)。下文保留当时 WIP 状态，不代表当前工作树。

日期：2026-10-03。用户要求保存进度、上传当前分支并终止任务。本记录是 **WIP 交接**，不是美术完成或验收声明。

分支：`codex/optimize-b05-b06-art-boss`；起点为实际 fetch 的 main `ab2c1d1136c88e657f8238aed9d878930269a67e`。没有修改 B07/B08 分支、合并 main 或强推。

## 已保存内容

- B05 新增首房外观：M01 藤鞭人形植灵、M02 幼芽种荚炮手、M04 花语治疗者；各有 idle / telegraph / execute 三姿态图集和独立动作登记。
- B06 新增首房外观：M01 成人三叉戟海族、M02 海族幼体操控寄居蟹贝壳炮、M03 成人海龟壳盾卫；各有三姿态图集和独立动作登记。
- 原有身体 PNG、图鉴 / 头像 / 怪物 UI 和默认动作登记保留。新增 `first_room_entry()` / `first_room_bank()` 供房间身体使用，默认 `entry()` / `bank()` 仍取旧资源。没有重新编号身份。
- 首房遭遇代码仅给 L25 的 M01/M02/M04、L31 的 M01/M02/M03 设置新增外观标记；`EnemyArt.install` 和 `EnemyVisual` 已写选择接口。**全局资源索引尚未登记这些新逻辑 ID，因此当前会回退旧身体；未证明新身体在游戏中加载。**
- 共享分层 renderer、纯 alpha 走区外侧裁剪 shader，以及 L25/L31 候选接线已保存。`first_room_layers.json` 两关实际配置尚未创建，环境仍回退原场景。L32+ 没有扩展。
- L25/L31 的候选走区 JSON 已改为连续双平台与宽桥草稿，入口 / 出口 / 主路线、机关 ID、遭遇身份和数值没有改。L31 的 north / south 原浅水 ID 缩到平台内，潮汐时钟没有改。这些几何变更 **尚未跑修改后的导航和整体首房验收**；旧背景与新轮廓也未对齐，恢复时须先处理。
- 新增共享首房 capture 测试及套件登记，支持真实生产 prepare/apply、原波次、HUD、导航、身体脚点、有效 alpha 像素与 2560×1440 原始 framebuffer。最后的新增外观断言修改未再次运行。
- 巨树建筑 / 深根瀑布、贝壳神殿 / 深岩瀑布、两关远景、木地面以及桥梁候选原生输出保留；Boss 技能特效与六图标候选保留。均未接入。来源清单见 [候选来源登记](../../assets/levels/b05/registration/stop_checkpoint_sources.json)。原生成文件仍在 `/workspace/generated_images/`，没有删除失败候选。

## 已验证与未验证的边界

旧生产基线 `artifacts/test_runs/B06/20261003T060052275635Z-8adc15b4/`：107 checks、0 failures、退出 0；console 无 `SCRIPT ERROR` / `ERROR:`。四张 L25/L31 入口与中心帧为真实 2560×1440 RGBA framebuffer，已实际查看。大面积木地板 / 白蓝网格地板占据镜头，参考建筑仅在边缘，确认了本轮改造原因。

共享 renderer 的独立图形 probe、Godot 4.7.2 导入及隔离候选启动曾通过；最后证据 `artifacts/test_runs/B06/20261003T061009961293Z-d7a04426/console.log`。probe 证明走区内部透明、外侧保留，region 裁剪和缺资源无部分安装，但 **不等于新版实际首房验收**。

六种新增身体源的图集边界、哈希、注册锚点已检查，B05 loader 的隔离解析通过。B05 图集均 1254²；B06 M02 是 2172×724，另外两种 1254²。登记记录各动作有效身体 / 武器像素，不能把整个图集当单帧。所有新增运行质量 gate 仍为 false。

图形检查使用 llvmpipe 软件渲染，仅证明图形路径和原始画面输出；不是目标硬件性能验收。所有游戏验证使用 managed `test_workspace.py` 与隔离 test profile，真实玩家档未参与。日志、截图、缓存、隔离存档不入 Git。

## 用户最后确认的范围与清晰度要求

优先让参考中的植灵 / 海族轮廓真实进入首房，再修背景、建筑、桥、水瀑和纵深。不主动向用户发 B05/B06 图片。原怪物 UI 和源图保留；新增素材不能冒充已接入。

2560×1440 是实际游玩画面目标，不要求每张源图都是原生 2K。角色按每动作有效身体 / 武器像素对最大镜头及 UI 用途分别记录；至少 1:1 为基础，1.25–1.5 倍余量是实现建议。近景建筑 / 地面按细节密度采用模块、分块或重复纹理；远景允许有意柔化。图标建议有效图案为最大 UI 显示的两倍，并检查小尺寸识别。技能 FX 按单帧有效包围盒和实际最大范围，不用 atlas 总尺寸掩盖单格像素。最终记录源有效像素、实际最大显示尺寸、倍率和真实 2K 帧结论；目前新素材的显示尺寸 / 实机结论未填。

Boss 规划仍要求独立语义：BO05 的 crown_sweep / three_roots / pod_rain / growth_rings / bloom_transplant / season_bloom；BO06 的 siege_claw / dual_cannon / tidal_wall / shell_bombard / coral_escort / return_pincer。现有根矛、水矛是候选，不能据此声称两关六套独立特效已实现。没有修改伤害、暴击、装备标准或做全局重平衡；PR9 遗留未纳入。

## 中断位置与恢复所需信息

最后中断于两张桥梁候选的正式修复生图：B05 原桥右端裁切；B06 原桥含不该出现的实色背景。调用中断时未返回完成映射，两份新输出仅作为未分类 archive 保留，不是已确认修复。没有继续新生图或开发。

需要显式恢复任务后才可继续：登记新资源逻辑 ID，填写两关生产层配置，检查候选几何 / 浅水 / 机关接近路，再实际运行新增外观与环境的 2K 测试。此前的通过结果不能替代这些步骤。

正确引擎：`/workspace/.cloud-games/engine/Godot_v4.7.2-stable_linux.x86_64`，不是 PATH 中旧 Godot。测试入口使用 `tools/testing/test_workspace.py run --biome B06 -- ...`，图形模式、`--candidate-b06` 及唯一 `--test-profile=user://test_b05_b06_first_room_art/test_<name>.json`；详见新增测试的 guard。原临时 Xorg :98 在收尾停止，不将它当共享设施继续运行。

Library 的精确 reference 文件 ID：B05 `libfile_002d410d5a7081918d45f9c9b31ec629`，B06 `libfile_fae6e261f1348191923fe80922f215a1`。本环境只有 Library 写工具，缺读取 / prepare_materialize，原参考字节没有 materialize；已查看用户直接附图，不能声称拿到了原文件和版本元数据。此前 Library 保存尝试在 tools/list 网络阶段失败，未产生 Library ID。新增角色登记保存完整 prompt；部分早期 Boss FX 的精确 prompt 未留在可恢复 snapshot，清单明确空缺，不虚构来源 / 许可。
