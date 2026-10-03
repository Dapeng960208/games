# L37 独立背景与详情接入候选

2026-10-03。用户已明确批准按第三张完整原画的真实地坪边界重标 L37。旧固定轮廓是此前保护约束，不是用户要求；`f7abd96308bb8c6eaabe8e594a82bc16be5cdbaa` 保留旧几何及三张对旧轮廓失败的候选。原失败记录不改写为通过。

## 实际改变

- 选择第三张 `mask_first_boundary_candidate.png`，原字节复制到标准 `background/environment.png`。PNG 1536×1024，未放大/改色/裁剪；不是原生2K图。
- 明确新开关 `--b07-room-painting-review`，同时需真实隔离 B07 candidate。WorldArt在查缓存前检查权限，验证 L37/ B07 /candidate_only/独立纹理ID；新模式成功时不加载旧trial图层，共用EnvironmentChunks和WorldCamera。
- 仅 `data/levels/b07/content.json#room_geometry/L37/walkable_polygon` 改变。所有其他JSON内容逐值比较不变，包括其他六房、入口出口、镜座祭坛手闸、遭遇、掩体、光路、数值和成长。
- 原画源像素8角：[(210,241),(435,144),(1230,144),(1354,263),(1378,724),(1238,822),(334,822),(192,698)]。实际原图查看与边缘亮度变化交叉量测；不规则石沿约4–8源像素不确定性，保留角色导航半径内缩，不宣称数学公式等于精确分割。
- 沿用设计契约 placement=[.1,.12,.8,27/35]，全画世界范围(-203,-162.4,2030,4060/3)。实际蓝图角点由源像素反算。面积1,347,870.7→1,320,315.5076世界单位²，减少2.04435%，与初算1.845%相差约0.20百分点；仍为凸单平台。
- 现有功能物件 source anchor/foot 不动；现有职业、HUD、SkillBadge一致性修复复用。共用镜头基准.85、正常跟随玩家，无旧trial人为偏置。

## 用户指定 L07 的真实目录/消费模式

`assets/levels/b02/rooms/l07/background/`：environment.png、environment.json、environment.prompt.json。

`detail/`：top_left.webp、top_middle.webp、top_right.webp、bottom_left.webp、bottom_middle.webp、bottom_right.webp、manifest.json。不是透明道具，也不是母图切成六块后冒充高清。

- 背景逻辑ID：`asset://world/rooms/L07_environment_v1.*` → WorldArt.environment_definition/rect/point。
- 详情逻辑ID：`asset://world/rooms_2k/L07/{id}.webp` 与 manifest.json → EnvironmentChunks.configure 末尾的 EnvironmentDetail.configure。
- L07详情为六次原生细节重绘，原source_rect依次：[0,0,520,528]、[504,0,528,528]、[1016,0,520,528]、[0,504,520,520]、[504,504,528,520]、[1016,504,520,520]。
- `environment_detail.gd:65–88` 用同一destination世界矩形映射source_rect，按原生纹理尺寸算比例、16/24源像素窄羽化。母图底层保留，失效时回退；房间节点释放六块内存，不称流式加载。
- 现有 `tools/assets/world/package_environment_tiles.py prepare L37` 生成精确参考裁片；这些只是输入，不是最终详情资源。原生重绘需至少2.35倍源裁片密度；无损WebP须decoded RGB一致、无resize。

B07 L37采用相同 background/ 与 detail/ 目录和逻辑层次。当前背景已为接入候选；detail/manifest.json明确approved=false和缺6块，不把已有镜座/桥/棚组件算详情。详情需要独立原生重绘与构图/接缝验证后才能启用，不能用占位裁图或插值补数。

## 定向检查

批次 `20261003T120824354395Z-1cf4374a`：新模式102检查0失败；关闭模式4检查0失败。

- 同一WorldArt背景/边界/镜头变换，六母图分块共享同一纹理。
- 七房Geometry.validate仍通过；新旧JSON只有L37轮廓变化。
- 180世界单位完整安全路宽：中心线最小边距125.375，扣90半宽余35.375。
- 导航半径12/14/18/24，各自从入口到出口、镜座、祭坛、两手闸及3遭遇点，共32路径通过；最大终点残差4.8世界单位（检查阈值5）。用生产navigation_direction/move_actor，独立导航探针，非人工游玩。
- 缓存不能绕过关闭开关；L01仍能加载，L38不会被冒称独立房间。
- 初次批次 `20261003T120729872773Z-5cf146e1` 有2项测试断言失败：JSON浮点数组直接与整型数组比较。改为真实坐标比较后重跑；没有为通过改运行坐标。

图形脚本 `/workspace/shared/b07l37_painting_cap.sh` 交父错峰：3个合法位置的冻结构图夹具＋现有正常AI/伤害/脚本输入首波。总120秒，静态引擎30秒/首波引擎60秒，共用managed锁与Dummy音频。未自行运行图形。真实画面、自然战斗可读性仍待验；连续角色动画仍0，M11 blocked。

## 实际底图图形结果与详情进展

父执行批次 `20261003T121215798179Z-fdba4061`：静态111检查0失败，3张受控机位＋7张真实AI脚本输入帧全部实际查看。330个postdraw样本在旧采集器中计0交叠，但实际 `L37_live_04_M02_motion_start.png` 的右上技能卡被自绘连击增伤牌下压。此漏检不能算UI通过。

根因：HitChainReadout是Control自行绘制，不是Panel/Label。现有HUD早有 `active_buff_coverage_rects()`，本次复用该方法并正确从Canvas坐标映射，不新增UI。新定向测试加入自绘覆盖及隐藏状态；实图复验待父安排。首波24.4秒死亡沿用非标准装备/脚本输入限制，群体身体重叠与死亡HUD停在451的问题仍保留，不据此作平衡结论。

详情已完成6张原生重绘并无损WebP打包，原生1244×1264或1254×1254，最小密度2.375倍；每张实际查图、decoded RGB等于原PNG，不插值放大。每块source_rect、prompt、原生成路径、哈希、来源与QA在detail/manifest.json登记，approved=false。`--b07-native-detail-review`仅在合法L37独立整画模式下调用原EnvironmentDetail候选路径，其他章不改变。

详情初次批次 `20261003T121845956977Z-a31f8b9e` 虽逻辑121项0失败，日志因新WebP未导入有ResourceLoader错误并回退读图；已判非clean，补标准导入后才能运行真帧。旧记录保留。六块主轮廓与大纹样初查接近，但局部石缝/叶形/微对比被重新描绘；原画/详情A/B与拼缝尚待验，不能提前将approved设true。

补充：标准导入批次 `20261003T122007335558Z-632f3559` 因首次扫描旧工作区资源超过65秒超时，六个目标纹理已导入；之后窄运行 `20261003T122209231293Z-46824c16` 为121检查0失败、ERROR/WARNING均0，6块真实加载无回退。生成的非本轮.import/.uid仅本地暂存，不纳入资源提交。自绘HUD补漏纯检查与关闭review回归批次 `20261003T121556785887Z-14f18213` 通过。

## 最终本轮图形复核

父运行 `20261003T122349570762Z-6cb9a02e` 完成exit0。入口/中心/出口3组底图与详情A/B共6张，正常AI固定输入7张，总13张2560×1440均实际查看。静态136检查0失败；280个postdraw样本批次身份/数量与已纳入自绘连击/增益HUD的交叠均0，实际M02 motion_start画面也确认原连击牌压卡问题消失。日志只有llvmpipe VSync警告，无SCRIPT ERROR/资源错误。

详情让石材、蜥首、城墙更清楚，这三个机位未见明显硬接缝；局部石缝/叶形重新描绘、微对比更强，窄羽化仍保留部分母图像素，不能宣称细节完全逐像素一致。该房仍是单层大庭院切片，远景建筑不是可走上层；镜头裁切下并未展示参考图所有多层关系。

本轮完成首房独立background＋6张原生detail候选接入、统一映射与已批准边界微调。其余6房整画/详情仍缺；全场景验收、连续动画、装备和完整战斗均未完成。detail.approved仍false，双review开关保留。群体角色身体重叠、死亡HUD停451以及非标准基线约24.38秒死亡仍如实保留。

提交前本地整理后批次 `20261003T122816272739Z-771fa5d8`：详情121项/关闭开关4项/自绘HUD几何测试全部通过且无ERROR；原历史review窄回归 `20261003T122932765227Z-15dd6328` 通过。旧review西边锚点断言改为读取当前已获准的L37首尾顶点，不再硬编码已被替换的旧轮廓，原图与旧证据未动。183个本次导入附生的旧资源.import/.uid移入本地_tmp保留，正式新增7张纹理的.import导入设置随资源提交，.godot缓存与截图/日志/档均不提交。
