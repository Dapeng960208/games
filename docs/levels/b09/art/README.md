# B09 原创资源登记

本批资源按普通怪与首领 → 房间效果图 → 陈设与材质的顺序设计，主题是日照霜晶王庭、淡紫晶面、冰青反光和香槟金暖灯。随后按 B02 L07 的 `background/`＋`detail/` 结构完成七房地图接入。全部原图为本任务生成，未复制 B05/B06 角色或场景；角色图集重新排布和六房背景迁移仅引用本批 B09 自身原图。

`provenance.json`、`environment.prompt.json` 和 `detail/manifest.json` 保存完整提示词、生成日期、参考来源与 SHA-256。角色和背景原图按字节复制到仓库，保留来源元数据；运行时按登记区域裁取姿态。高清 detail 逐片由 `image_gen` 原生生成，转无损 WebP 后核对解码 RGB 一致，未做离线放大。生成工具未提供可确认的模型 ID／版本，因此登记为 `null`。

## 角色：18 种普通怪与霜晶女王

每张 `poses.png` 含待机、蓄势、释放三个独立姿态。下表路径均指向原图；对应来源文件与原图同目录。运行登记见 [actors.json](../../../../assets/levels/b09/registration/actors.json)，记录各姿态区域、脚点、晶核锚点和视觉出口；`runtime_quality_gate_passed: false` 表示尚未完成连续动画验收。

| ID | 角色与轮廓 | 原图 |
|---|---|---|
| M01 | 棱晶守卫：双棱肩甲、晶剑、胸甲 | [poses.png](../../../../assets/levels/b09/enemies/m01/poses.png) |
| M02 | 雪灵法师：浮雪披帛与雪团 | [poses.png](../../../../assets/levels/b09/enemies/m02/poses.png) |
| M03 | 冰棱投手：三叉晶臂 | [poses.png](../../../../assets/levels/b09/enemies/m03/poses.png) |
| M04 | 霜足侦察晶：三脚晶体 | [poses.png](../../../../assets/levels/b09/enemies/m04/poses.png) |
| M05 | 晶壳搬盾者：方晶背壳与宽盾 | [poses.png](../../../../assets/levels/b09/enemies/m05/poses.png) |
| M06 | 暖光窃取者：抱灯兜帽晶体 | [poses.png](../../../../assets/levels/b09/enemies/m06/poses.png) |
| M07 | 镜冰剑士：单镜面长刃 | [poses.png](../../../../assets/levels/b09/enemies/m07/poses.png) |
| M08 | 寒铃咏者：冰铃三环 | [poses.png](../../../../assets/levels/b09/enemies/m08/poses.png) |
| M09 | 滑刃巡卫：双足冰刀 | [poses.png](../../../../assets/levels/b09/enemies/m09/poses.png) |
| M10 | 雪绒投弹手：圆雪球筐 | [poses.png](../../../../assets/levels/b09/enemies/m10/poses.png) |
| M11 | 双面晶炮：前后晶管 | [poses.png](../../../../assets/levels/b09/enemies/m11/poses.png) |
| M12 | 棱柱塑形者：悬浮凿具 | [poses.png](../../../../assets/levels/b09/enemies/m12/poses.png) |
| M13 | 冰核巨像：外环大晶与内核 | [poses.png](../../../../assets/levels/b09/enemies/m13/poses.png) |
| M14 | 裂桥监工：长臂晶尺 | [poses.png](../../../../assets/levels/b09/enemies/m14/poses.png) |
| M15 | 环霜封路者：水平霜环 | [poses.png](../../../../assets/levels/b09/enemies/m15/poses.png) |
| M16 | 晶镜织射者：折射三角支架 | [poses.png](../../../../assets/levels/b09/enemies/m16/poses.png) |
| M17 | 王庭雪骑：晶鹿骑具 | [poses.png](../../../../assets/levels/b09/enemies/m17/poses.png) |
| M18 | 冠晶仲裁者：冠状多面核心 | [poses.png](../../../../assets/levels/b09/enemies/m18/poses.png) |
| BO09 | 霜晶女王：悬浮冰冠、晶裙、心核与晶剑 | [poses.png](../../../../assets/levels/b09/bosses/bo09/poses.png) |

## 七房运行背景与高清 detail

七房底图已经通过前四关共用 `WorldArt → Backdrop → EnvironmentChunks → WorldCamera` 管线进入游戏。每房 `background/environment.json` 登记 placement 与可走多边形，`detail/manifest.json` 登记六片高清图的原画裁区、映射及羽化边界；实际可通行范围与机关落点见 [room_geometry.json](../../../../data/levels/b09/room_geometry.json)。placement 为 `[0.10, 0.10, 0.80, 0.74]`，未整房覆盖全局固定房间运行 JSON。

| 房间 | 构图与接入重点 | 实际背景 | 高清 detail 清单 |
|---|---|---|---|
| L49 雪阶外庭 | 雪阶主庭、短冰面、晶门 | [environment.png](../../../../assets/levels/b09/rooms/l49/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/l49/detail/manifest.json) |
| L50 暖灯街廊 | 沿边工坊、暖灯与街廊主路 | [environment.png](../../../../assets/levels/b09/rooms/l50/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/l50/detail/manifest.json) |
| L51 双晶桥 | 两岸裂隙、双桥与可走连接 | [environment.png](../../../../assets/levels/b09/rooms/l51/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/l51/detail/manifest.json) |
| L52 棱镜雕坊 | 晶柱足迹、斜向掩体、东侧暖灯 | [environment.png](../../../../assets/levels/b09/rooms/l52/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/l52/detail/manifest.json) |
| L53 冰核广庭 | 中央圆庭与外围四块小冰岛；巨像后仅一次桥切换待完成 | [environment.png](../../../../assets/levels/b09/rooms/l53/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/l53/detail/manifest.json) |
| L54 冠晶长阶 | 三平台、两组双通路、四座桥 | [environment.png](../../../../assets/levels/b09/rooms/l54/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/l54/detail/manifest.json) |
| BO09 霜晶王座 | 粗雪环、冰翼、暖灯与晶座；完整外缘桥通行待接入 | [environment.png](../../../../assets/levels/b09/rooms/bo09/background/environment.png) | [manifest.json](../../../../assets/levels/b09/rooms/bo09/detail/manifest.json) |

L49／L50／L51／L52／L53／BO09 的背景沿用本批 B09 原画，迁移时保持字节一致。L54 以 [旧 overview.png](../../../../assets/levels/b09/rooms/l54/overview.png) 为编辑来源，仅增补两个平台连接处的平行通路，新运行底图和来源哈希见 [background/provenance.json](../../../../assets/levels/b09/rooms/l54/background/provenance.json)。旧图留存用于来源追溯，不作为当前运行背景。

七房共 42 张原生高清 detail：39 张为 1254×1254，3 张为 1244×1264；逐轴像素密度至少为对应原画裁区的 2.375 倍。清单分别记录原背景 SHA-256、裁区、参考裁图哈希、生成 PNG 哈希、解码 RGB 哈希、完整提示词和无损 WebP 哈希；实际尺寸按生成结果登记，不将提示词请求的分辨率当作实际输出。底图作为回退与窄羽化区基底，高清片以相同映射覆盖，不属于流式加载。

本轮七房中心／四角原生状态及七张底图比较共 42 张 GPU 图全部复核通过，包含 L51／L54 母图覆盖修复后的实景；合并后地图／路径检查 1184／0，合并后新地图 2K 操作 247／0。当前状态为隔离候选／地图与 2K 受控接入验收通过，合并后 GPU 已通过 247 项检查；不表示全设计、自然平衡或连续动画通过。详见 [验证记录](../validation.md)。

资源审计通过：33 张来源、19 身份／57 姿态、42 张原生 detail（84,502,242 字节），原图哈希、登记区域、实际尺寸与无损编码核对通过，没有与 B05/B06 相同文件内容。仓库路径与文档链接审计通过。

## 陈设与材质

| 资源 | 用途 | 原图 |
|---|---|---|
| 暖灯 | 常亮交互机关与范围粗雪 | [source.png](../../../../assets/levels/b09/environment/warm_lamp/source.png) |
| 晶柱 | 边界陈设、低掩体及可拆折射柱 | [source.png](../../../../assets/levels/b09/environment/crystal_column/source.png) |
| 晶宫拱门 | 房间入口／清场出口 | [source.png](../../../../assets/levels/b09/environment/palace_arch/source.png) |
| 晶桥 | 完整、裂纹、重组三个状态 | [source.png](../../../../assets/levels/b09/environment/bridge/source.png) |
| 粗雪材质 | 结束惯性的主路地面 | [source.png](../../../../assets/levels/b09/environment/snow_floor/source.png) |
| 亮冰材质 | 明确标识的局部滑行区域 | [source.png](../../../../assets/levels/b09/environment/ice_floor/source.png) |

当前资源包括 19 张角色图集／57 个姿态、七房运行背景、42 张高清 detail 与六项陈设／材质原图，另保留 L54 旧背景来源。35 件装备沿用共用槽位图标，独立装备插画尚未完成。缓存、生成源下载副本与运行截图留在忽略目录中，必要来源记录、提示词、哈希与版权说明随资源入库。
