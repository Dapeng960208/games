# B07 独立房间原画与统一映射自查

2026-10-03。依据用户最新要求：明亮手绘卡通奇幻，高机位三分之四斜俯视，2.5D；参考前四章独立房间原画与统一坐标接入，职业/战斗界面复用。基线 `0cfc111b4a84071febbaaa8cbb011e5ab0b2c911` 保留，旧候选和失败证据不删除。本轮为源文件/实际图片自查与设计，尚未生成新整画、改运行代码或运行引擎。

## 结果与证据

- 前四章每章 7 张独立房间原画，共 28 张；物理路径 `assets/levels/b0N/rooms/<room>/background/environment.png`，旁有 environment.json 和 prompt.json。28 个 PNG 哈希均不同，尺寸均 1536×1024。章级 shared 回退图不计入。
- 已查看 L01/L07/L13/L19 原画像素及用户 B07 参考 `B07(1).png`，并重看实际 2K `20261003T112544247538Z-d35f0ba1/L37_live_00_entry.png`。前四章是高视角、完整连续地坪与周边建筑同画；B07 入口是大片重复砂岩纹理、直立切边和分离大蜥首，画面空旷，远景细节放大模糊。暖色与蜥族母题存在，但不能视为统一风格/空间关系已通过。
- **B07 完整独立房间原画 0/7**。21 张房间 PNG 是远景、地面、岩壁和独立局部组件；包括 `canyon_backdrop.png` 也不是带注册通行地面的完整房间图。角色/UI修复测试通过不构成场景视觉验收。

| 房间 | 已有局部来源 | 独立整画缺口与新构图职责 |
|---|---|---|
| L37 晒鳞城门 | 地面/峡谷/岩壁/蜥首及未验收城桥候选 | 1 张城门庭院整画；边界外完整承托城垣、蜥首与峡谷，中央保留真实战斗/引光净空 |
| L38 绿松石集市 | market_awning_stall | 1 张集市整画；朱红布棚/绿松石摊街环绕南北通道，双镜座不被棚柱覆盖 |
| L39 驭沙学庭 | sand_study_table | 1 张学庭整画；驭沙院落、侧缘学台，左下至右上的真实路线 |
| L40 反光工坊 | mirror_workbench | 1 张工坊整画；周边镜匠台与低矮屋檐，横向通道与三个真实镜座 |
| L41 日轮阶庙 | temple_portico | 1 张阶庙整画；高处殿门仅边界外景观，战斗平面不假画跨层必经阶梯 |
| L42 方尖碑广场 | sandstone_obelisk | 1 张碑广场整画；外缘碑群与完整地基，四个真实镜座及西入东北出路线 |
| BO07 日轮王台 | throne_backdrop | 1 张首领王台整画；边缘日轮王座与四镜、中央祭坛/Boss真实脚点净空 |

所有旧图保留作风格/组件参考；缺口不能靠拼图数量抵消。

## 前四章真实接入链

1. `scripts/infrastructure/assets/world_art.gd:22–65` 以 blueprint_room_id 优先选择房间 environment manifest，经 AssetCatalog 解析，缺失才走章级回退。
2. `world_art.gd:70–87`：R.size=layout.arena.size/placement.size；R.position=arena.position−placement.position×R.size；T(u)=R.position+u×R.size。背景、归一化点和干地 polygon 同源。
3. `fixed_room_layouts.gd:7–8,115–150` 将 2800×1800 蓝图统一乘 0.58，仅一次。`environment_backdrop.gd:62–64` 使用原 layout.arena，不使用 polygon 外包矩形重新缩放背景。
4. `environment_chunks.gd:16–59` 六块是同一完整母图共享比例的分区，既非六张拼画也非流式加载。
5. `room_controller.gd:356–372` 使用地面 polygon 约束脚点；镜头接 painted_bounds。`world_camera.gd:98–153` 共用常规基准 zoom=.85，镜头跟随玩家，限于整画范围。
6. `room_depth_sprite.gd:12–27` 节点 position=item.foot，真实脚点排序/人物遮挡淡化；`room_appearance.gd:124–135` 原图和旧回退脚点策略存在差异，不能全部猜贴图底部。

注意前四章 metadata 不是逐字段统一：placement 均 [.11,.13,.78,.74]，但 walkable_normalized_rect 有保守中央矩形/边界外包范围等不同历史含义。真正地面取每房 polygon。B07应复用变换契约，不照抄旧不一致文案。边界算法 `room_boundary.gd:11–42` 要求凸多边形；不能因原画凹岸而悄悄改变该约束。

## B07 断点与仍正确部分

- `room_environment.gd:10–24,63–104` 硬编码 BLUEPRINT_BOUNDS、MIDGROUND_BOUNDS，背景与地面分别 cover/crop，外部背景还被 walkable polygon 切除。数值同用 .58 不代表源图地面和场景脚点完成视觉注册。
- `environment_backdrop.gd:89–110` L37 专用 trial 优先并返回 trial.BOUNDS；`world_camera.gd:100–102,129,150–153` 另行 .72 及 (260,110)/(160,-160) 偏移。它是旧试验，不是前四章独立整画链。
- 其余六房没有独立 environment manifest 或 texture，回退通用地面。`room_layouts.gd:21` 仍为 formal_art_status=not_included。
- 正确部分须保留：`room_geometry.gd:12–20` 固定几何统一 .58；`room_layouts.gd:18,23–29` 地面、镜座、手闸、石掩体同一来源；`l37_prop_skins.gd:39–44` 真实机关脚点派生自同一 Geometry.world_point。不能挪机关配合错误图。
- B07 `room_controller.gd:358–361` 优先 layout.ground_polygon。新增 manifest 时保留此路径，再断言 manifest 映射 polygon 与它逐顶点一致，避免注册原画无意改变碰撞。

## 最小修正设计

详见同目录 `independent_room_mapping_plan.json`。这是设计契约，不是已存在资源的运行 manifest。

1. 先 L37 一张完整整画试片，确认高机位视角、明亮卡通材质、单一光向和地面边缘；再逐房出其余六张。整画包含永久背景与地坪，不另叠大面积地板遮盖。动态镜座/祭坛/掩体在指定空白脚点落地，避免烘焙重复机关。
2. 目标 3:2 画幅，使用实际输出尺寸，不以放大冒充原生细节。建议 placement=[.1,.12,.8,27/35]，蓝图整画范围 (-350,-280,3500,7000/3)，运行 R=(-203,-162.4,2030,4060/3)。X/Y比例一致，避免拉伸。这不是照搬前四章 placement 数值，而是复用同一公式。
3. 任意蓝图点 B 对应 u=(.1+B.x/3500,.12+B.y/(7000/3))，T(u)=.58B。七房所有边界/入口出口/机关已按此计算；浮点往返最大误差小于 1e-12 世界单位。L37入口(.191429,.505714)、出口(.808571,.505714)、镜座(.38,.39)、祭坛(.644,.39)。新图若不是3:2需先重算契约，不裁切源图来碰运气。
4. PNG/metadata/prompt/provenance 经 manifest 注册到前四章既有 `asset://world/rooms/L37_environment_v1.*` 逻辑入口，物理仍 `assets/levels/b07/rooms/l37/background/`。使用 WorldArt/EnvironmentChunks 的既有机制；新模式优先完整原画并停用旧trial层，旧源图及旧开关证据保留。不能只是加载新图后仍让 trial 遮住它。
5. 新模式恢复共用 WorldCamera 的正常 painted bounds 与玩家跟随，移除该模式 .72 和人工北偏移；旧试验开关保留。此项影响可见范围/主角屏幕位置，需要实际2K复验，但不改人物坐标或碰撞。不要再用镜头偏置补坏源图。
6. 真实功能物件继续原 foot 和 source anchor；需遮挡角色的物件用现有深度节点。新原画图中所有大体量建筑都在固定走区外，其视觉地基不得跨入通行净空；不能靠透明度/遮块掩盖冲突。

### 布局影响边界

上述最小方案保留七房当前凸地面、全部入口出口、路线、掩体、锁点、光路与距离数值。可在边界外表现城层高低和远处拱桥，不新增可走平台。

若用户要求参考图里的桥梁/楼梯本身承担实际通路，则需要重新设计通行 polygon、路线/镜座光路、掩体、遭遇锚点、导航及首领空间。现有单平面大庭院不能仅凭一张画变成真实多层路线；这应另报具体房间几何影响，不能暗改。

## 职业与UI复用边界

`candidate_scene.gd:30–38` 复用现有 CH01/CH02/CH03 与 Game.select_hero；:47实例化现有room.tscn；:65实例化现有hud.gd。不新增职业或战斗UI。0cfc111只改善现有 SkillBadge 的批次一致性/避让，保留。候选调试文本仍须与正式HUD区分，不把其叠加算新设计成果。

## 后续验证门槛

- 源图先实际看图，对所有固定锚点/干地边界叠加量测；失败保留并明示，不靠移动玩法点通过。
- 仅定向检查 manifest 解析、唯一源图、映射往返、原几何字节不变、旧开关/其他章不受影响。
- 父任务错峰图形：真实2560×1440入口、中心、出口与正常首波实际玩法，检查视角/脚点/尺度/遮挡/边界错位；单纯退出码零不能通过视觉。
- 连续动画仍 0 套，M11 blocked，B07装备注册/专图仍0；本场景改法不宣称补齐这些缺项。
