# B05 / B06 全房独立原画与坐标验收

日期：2026-10-03。分支：`codex/optimize-b05-b06-art-boss`。B05、B06 已正式接入，默认六章与 Lv30；开放、成长和历史付款兼容见 [正式接入记录](b05_b06_release.md)。本报告记录当前完整房间表现，取代 [此前首房报告](b05_b06_art_acceptance.md) 中重复地面材质、建筑模块与桥栏拼装的当前场景结论；原身体和十二招技能美术继续使用。

## 当前接入与视觉标准

14 房逐一使用自己的完整环境原画。B05 保留 L26–L30、BO05 原画及对应六块原生细节，L25 改为完整原画；B06 七房全部替换为完整原画。明亮手绘卡通奇幻、高机位三分之四斜俯视和 2.5D 质感通过正常镜头截图检查：暖日照、清楚的木纹/珍珠石材、可见台沿与建筑前侧、较弱透视、独立生态与建筑构图。前四章 L01/L07/L13/L19 作为实际显示参考，并在同一夹具中留存截图。

| 房间 | 当前原画与识别 | 验收状态 |
|---|---|---|
| L25 花径入口 | 新完整树城原画；两侧林庭与中央木桥 | 正式；中心及四角 |
| L26 藤门苗圃 | 独立苗圃、藤门与木庭 | 正式；中心及四角 |
| L27 露台花桥 | 独立花桥露台与花木生态 | 正式；中心及四角 |
| L28 树脂工坊 | 独立树脂工坊与木质工位 | 正式；中心及四角 |
| L29 日照高台 | 独立日照露台与聚光叶机关 | 正式；中心及四角 |
| L30 四季温室 | 独立四季温室、树庭与外围水瀑 | 正式；中心及四角 |
| BO05 花冠王座 | 独立花冠首领庭 | 正式；中心及四角 |
| L31 贝桥前街 | 新完整贝桥原画；宽双平台、中央常干桥 | 正式；中心、四角及高潮 |
| L32 螺塔码头 | 新完整螺塔码头原画 | 正式；中心、四角及高潮 |
| L33 珊瑚集市 | 新完整珊瑚摊位与街巷原画 | 正式；中心、四角及高潮 |
| L34 珍珠工坊 | 新完整贝壳工坊原画 | 正式；中心、四角及高潮 |
| L35 潮钟水庭 | 新完整 Y 形水庭与潮钟原画 | 正式；中心、四角及高潮 |
| L36 巨蟹船坞 | 新完整蟹船工地与渠桥原画 | 正式；中心、四角及高潮 |
| BO06 行走堡垒湾 | 新完整首领海湾原画 | 正式；中心、四角及高潮 |

职业、角色成长、技能栏、生命/资源/护盾、自动攻击与战斗 HUD 复用现有实现。没有为 B05/B06 另写职业或战斗界面。B06 潮水只在既有浅水多边形上绘制透明水层，由房间原潮汐时钟决定湿地；没有用新画面改变周期、机关或结算。

## 一个蓝图坐标映射

固定蓝图 `2800×1800` 使用 `FixedRoomLayouts.PLAYFIELD_SCALE=0.58`，实际场地为 `1624×1044`。B05/B06 几何脚本直接读取这项已有常量。每张原画的 `placement_normalized_rect` 决定同一仿射映射：`painting.size = arena.size / placement.size`，`painting.origin = arena.origin - placement.origin * painting.size`。背景采样、干地多边形、路线、入口出口、机关交互脚点和镜头绘制范围均以该房蓝图为依据。

- L25/L31 的绘图 placement 为 `[0.11,0.13,0.78,0.68]`，其余十二房为 `[0.11,0.13,0.78,0.74]`。只调整绘图映射，固定玩法几何保持原值。
- B05 使用已有 `EnvironmentBackdrop → WorldArt → EnvironmentChunks`；L25 停用旧重复材质和旧细节覆盖。其余六房的细节纹理按相同 source rect 映射。
- B06 `environment_painting.gd` 一次绘制本房完整原画，水层 UV 使用同一 `source_rect`；镜头读取实际 `painted_bounds()`。初始化失败保留原背景回退，切房释放房间拥有的水层与纹理。
- 自动断言原画、通行多边形、主路线、入口出口、根井实际碰撞脚点和排水闸源图脚点映射一致。渲染前后对比玩法坐标快照，确认不改几何和奖励位置。
- 第一轮目视检查发现 L31 东南脚点落到画面水边下方，已把绘图高度从 `.74` 改为 `.68`，重新检查四角和高潮截图后通过。不能用坐标断言代替目视验收。
- 用户指出柱下方台突兀后，定位为旧 `RoomAppearance` 自动绘制的石质高台；已对 B05 低掩体及关闭藤桥的障碍移除额外高台和矩形阴影，物件以碰撞中心落地并排序。原图、碰撞矩形、路径与机关规则保留。

没有用设计草稿整房覆盖运行 JSON。`data/levels/b05/room_geometry.json`、`data/levels/b06/room_geometry.json` 和 `data/world/fixed_rooms.json` 保持冻结。

## 原画、来源和实际尺寸

本轮选用八张新的完整原画：B05 L25 与 B06 全七房，来自内置 `image_gen`，参考 B05 L26 或前四章 B04 L19 的实际原画风格。生成结果原文件按字节复制入库，没有后续裁剪、调色、缩放或锐化修改。每房 `background/environment.json`、同目录 `*.prompt.json` 与资源索引保存原文件 SHA256、提示词、参考图和当前映射。L25/L31 使用 `environment_released.png`，其余六张 B06 使用 `environment.png`；此前源图与 provenance 保留。

新完整原画实际为 **1536×1024**，不是原生 2K 源图；渲染截图是实际 **2560×1440** framebuffer。B05 六房已有原生细节块各 **1254×1254**，其 source rect、原 PNG 哈希和解码 RGB 哈希均纳入现有资源完整性检查。原始图、来源与版权记录保留；未采用的生成变体不作为运行素材。

所选素材与提示词位于：

- `assets/levels/b05/rooms/l25/background/environment_released.png` 与 `environment_released.prompt.json`。
- `assets/levels/b06/rooms/l31/background/environment_released.png` 与 `environment_released.prompt.json`。
- `assets/levels/b06/rooms/{l32,l33,l34,l35,l36,bo06}/background/environment.png` 与 `environment.prompt.json`。

L25 旧细节包标记 `superseded_reference`；B06 旧模块/pilot 继续作为来源和专用历史夹具参考，正常房间由完整原画渲染器负责。第一轮 L31 生成图作为修改来源保留。没有把旧模块示例的状态提升为当前完整原画的验收结论。

## 直接验证与复现

Godot 4.7.2、RTX 3060 Laptop GPU、OpenGL 3.3 NVIDIA 581.83。逻辑视口 1280×720，窗口/实际 framebuffer 2560×1440，正常镜头缩放至少 `.85`。所有套件用隔离 runner，不传 `-Candidate`，不读取或更改玩家档。

| 检查 | checks / failures | 运行 ID |
|---|---:|---|
| 14 房及前四章参考房，背景/几何/脚点/镜头、无额外方台与81帧 | 554 / 0 | `20261003T130008562-a228f36f` |
| 两首房、18 姿态、原 HUD 与 4 帧 | 220 / 0 | 同上 |
| 两首领十二招、减少特效、绘制只读与 26 帧 | 197 / 0 | `20261003T121319609-f87253d5` |
| B06 环境生命周期/失败回退/纹理释放 | 556 / 0 | `20261003T121734136-f8e6f5db` |
| B06 实际 Main 潮相/切房/保存恢复/撤离 | 217 / 0 | 同上 |
| 实际镜头边界/缩放/前四章兼容 | 406 / 0 | 同上 |
| B05 三职业远征、藤桥、奖励去重与恢复 | 650 / 0 | `20261003T130008562-a228f36f` |
| 34个正式原生细节包、原PNG/WebP/RGB哈希、映射与切房释放 | 1771 / 0 | `20261003T123335334-674e1d89` |

最近有效结果共8个直接相关套件，**4,571 checks，0 failures**；当前全房81帧、首房4帧和首领26帧合计111张实机图形证据。中途一次截图夹具等待窗口刷新超时，仅保存15帧、不计入通过项；已复用既有首房夹具的 `RenderingServer.force_draw(false)`，最终全部85张复拍与后续藤桥事务检查通过。

最终新增两张修订图的正式导入通过：`20261003T123245154-b27a01e6`。截图和 `room_paintings.json` 在 `tools/godot/test-runs/<运行 ID>` 忽略目录；只提交生产素材、来源、夹具与本报告。原图像素 QA 的 `Image.load_from_file` 导出提示来自测试脚本；生产渲染使用导入纹理。

```powershell
.\tools\test.ps1 -ImportOnly
.\tools\test.ps1 -SkipImport -Graphical -Suite b05_b06_room_paintings,b05_b06_first_room_art,b05_b06_boss_skill_art
.\tools\test.ps1 -SkipImport -Suite environment_native_resources,b06_environment_lifecycle,b06_main_progression,world_camera,b05_candidate_traversal
python tools/maintenance/audit_repository.py
```

视觉验收结论针对上述真实房间视图、完整原画接入与共用映射。自然全职业/难度/种子平衡、连续动作、全部分辨率体验和长期硬件性能仍持续验证，不能由固定视图、原图尺寸或通过断言数推定。
