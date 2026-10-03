# B09 原创资源登记

本批资源按普通怪与首领 → 房间效果图 → 陈设与材质的顺序设计，主题是日照霜晶王庭、淡紫晶面、冰青反光和香槟金暖灯。全部原图为本任务新生成，未复制 B05/B06 角色或场景；角色图集重新排布时仅引用本批 B09 自身原图。

每个目录中的 `provenance.json` 保存完整提示词、生成日期、参考来源及原图 SHA-256。原图按字节复制到仓库，保留生成器附带的来源元数据；运行时用区域登记裁取姿态。生成工具未提供可确认的模型 ID／版本，因此登记为 `null`。

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

## 房间设计图

效果图用于表达建筑、材质和布局意图。实际可通行范围、机关落点与两条通路按 [room_geometry.json](../../../../data/levels/b09/room_geometry.json) 登记；没有覆盖全局固定房间运行 JSON。

| 房间 | 构图重点 | 原图 |
|---|---|---|
| L49 雪阶外庭 | 东西粗雪道、两片短冰面、北缘晶门 | [overview.png](../../../../assets/levels/b09/rooms/l49/overview.png) |
| L50 暖灯街廊 | 边缘暖灯工坊与 S 形主路 | [overview.png](../../../../assets/levels/b09/rooms/l50/overview.png) |
| L51 双晶桥 | 中央裂隙、南北双桥 | [overview.png](../../../../assets/levels/b09/rooms/l51/overview.png) |
| L52 棱镜雕坊 | 低晶柱掩体、东侧暖灯环路 | [overview.png](../../../../assets/levels/b09/rooms/l52/overview.png) |
| L53 冰核广庭 | 中央粗雪圆庭、外围四座冰岛 | [overview.png](../../../../assets/levels/b09/rooms/l53/overview.png) |
| L54 冠晶长阶 | 三段平台、双路连桥 | [overview.png](../../../../assets/levels/b09/rooms/l54/overview.png) |
| BO09 霜晶王座 | 中央环庭、左右冰翼、暖灯与晶座 | [overview.png](../../../../assets/levels/b09/rooms/bo09/overview.png) |

## 陈设与材质

| 资源 | 用途 | 原图 |
|---|---|---|
| 暖灯 | 常亮交互机关与范围粗雪 | [source.png](../../../../assets/levels/b09/environment/warm_lamp/source.png) |
| 晶柱 | 边界陈设、低掩体及可拆折射柱 | [source.png](../../../../assets/levels/b09/environment/crystal_column/source.png) |
| 晶宫拱门 | 房间入口／清场出口 | [source.png](../../../../assets/levels/b09/environment/palace_arch/source.png) |
| 晶桥 | 完整、裂纹、重组三个状态 | [source.png](../../../../assets/levels/b09/environment/bridge/source.png) |
| 粗雪材质 | 结束惯性的主路地面 | [source.png](../../../../assets/levels/b09/environment/snow_floor/source.png) |
| 亮冰材质 | 明确标识的局部滑行区域 | [source.png](../../../../assets/levels/b09/environment/ice_floor/source.png) |

合计 32 张原图、57 个角色姿态。缓存、下载目录与运行截图留在忽略目录中，来源记录与版权说明随原图入库。
