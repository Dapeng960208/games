# 素材、字体与运行依赖

2026-10-01 逐房背景重设计新增 28 张独立完整原画：`assets/generated/world/rooms/{L01–L24,BO01–BO04}_environment_v1.png`。每张均由内置 ImageGen 独立生成，同族 v3 原图仅作画风、色板与小石砖尺度参考；28 房的建筑、生态、外景与铺地分别构图，PNG 保留生成原始像素。相邻 `.prompt.json` 记录完整提示词、参考图角色和原始输出路径，运行 JSON 保存纹理、1536×1024 尺寸、统一玩法坐标映射与逐房干地轮廓。旧四族环境仍保留为来源及兼容回退。新房间的六区块共享各自完整原画，不表示六张独立生成图或显存流式加载。房间铭牌、28 种徽记和路线小图由本工程 GDScript 绘制，未引入外部图标。

2026-10-01 固定房间更新新增四族 80 个独立道具区、32 个边缘模块区和四张完整连续环境母图。资源为 `assets/generated/props/fixed_B0*_props_v1.*`、`assets/generated/world/fixed_B0*_edges_v1.*` 与 `fixed_B0*_environment_v2.*`，相邻 prompt/regions/metadata JSON 记录内置 ImageGen 来源、坐标、脚点和生成提示词。南瓜墓镇另有浅色地面备用图 `fixed_B03_floor_v1.*`。所有 PNG 保留生成像素；运行时仅取样、缩放和按固定布局拼接。环境六区块共享同一母图，不是六张独立生成或重绘的图片。

本轮比例修正启用 `fixed_B0*_environment_v3.*`：由内置 ImageGen 参考各自 v2 原图细化铺地、调整材质色彩，主要外围地标位置与地面轮廓继续由原坐标注册；相邻完整 prompt 与 metadata 记录来源、参考图和 SHA-256。三职业的站立、步态、普攻及技能统一按 `presentation_metrics.gd` 的 112 世界像素身体尺度绘制，普通敌人使用既有注册高度的 1.20 倍；下文历史 88 像素记录保留为原始生成来源，不是当前呈现尺度。

当前按钮为内置 ImageGen 生成的 v5：[透明原图](../assets/generated/ui/workshop_buttons_v5.png)、[完整提示词](../assets/generated/ui/workshop_buttons_v5.prompt.json)、[取样区域](../assets/generated/ui/workshop_buttons_v5.regions.json)。1536×1024 RGBA 原图保留生成像素，六类构件分别为蓝色符文主操作、米白手册次操作、青绿叶革页签、罗盘返回、珊瑚红危险操作与浅色装备卡片。文字、安全边距、九宫格伸缩、选中标记和状态反馈由 GDScript 绘制；下拉选择器共用次操作取样。

历史 v2 按钮来源继续保留：[透明原图](../assets/generated/ui/storybook_buttons_v2.png)、[完整提示词](../assets/generated/ui/storybook_buttons_v2.prompt.json)、[取样区域](../assets/generated/ui/storybook_buttons_v2.regions.json)。其中卷轴构件已被全局 v5 按钮皮肤替换，旧资源仍可用于历史设计记录和非按钮装饰。设计册中的 runtime 图片为真实 Godot 画面。

2026-10-01 的首四关原型使用统一明亮手绘奇幻基准。构装、虫族、南瓜僵尸、兽人／食人魔的四个最终怪物图集见 `assets/generated/enemies/storybook_B01_bodies_v2.*` 至 `storybook_B04_bodies_v2.*`；40 个普通怪／首领区域、脚点与来源均保存在相邻 JSON。首四族地图道具、自动信标和三联地面见 `assets/generated/props/storybook_*` 与 `assets/generated/world/storybook_floor_factions_v2.*`。60 件装备的当前资源及首四族八件核心覆盖由 `assets/generated/equipment/storybook_equipment_v2.manifest.json` 统一注册，相邻 provenance 记录原始提示词、生成输出路径和 SHA256。以上位图由内置 ImageGen 为本工程生成，原始像素保留；纹理裁取、朝向、缩放和运行时淡化由代码实现。候选、旧种族方案和未通过质量门的 M10 动作图保留为开发来源，未作为当前正式动作启用。

- 游戏角色、普通敌人、首领、装备图、房间道具、地板、图标和主视觉按本项目废矿工业奇幻主题原创设计；位图由内置 ImageGen 生成并接入游戏，未使用竞品形象。资源旁的 JSON 记录提示词、来源或动画帧信息。
- 2026-09-30接入第三版明亮插画方向的地图与界面素材，均由内置`image_gen`按本项目选定的设计参考生成。日光营地背景、奶油石板地面与透明边缘石块/植物装饰分别见[营地来源](../assets/generated/world/storybook_camp_v1.json)、[地面来源](../assets/generated/world/storybook_floor_v1.json)、[边缘装饰来源](../assets/generated/world/storybook_edge_v1.json)；纸面底图见[纸面来源](../assets/generated/ui/storybook_parchment_v1.json)。上述PNG按生成原图接入，区域色调与摆放由运行代码处理。
- 2.5D建筑图集由内置`image_gen`于2026-09-30生成，包含立柱、横向残墙、纵向残墙、石台、台阶与拱门六种透明模块。来源与完整提示词见[建筑来源](../assets/generated/world/storybook_architecture_v2.json)，取样区域与脚点见[模块注册](../assets/generated/world/storybook_architecture_v2.regions.json)；PNG保持生成原图。建筑高度、平台侧面、接地阴影、脚点排序与遮挡淡化由本工程代码处理，地面移动仍使用实际2D碰撞。
- 三名英雄的透明彩绘胸像用于营地、角色界面与战斗HUD，来源见[CH01胸像](../assets/generated/heroes/CH01_storybook_portrait_v1.json)、[CH02胸像](../assets/generated/heroes/CH02_storybook_portrait_v1.json)、[CH03胸像](../assets/generated/heroes/CH03_storybook_portrait_v1.json)。它们是独立界面插画，不替代战斗逐姿态图集；PNG保留生成原图，HUD头像区域按元数据取样。
- CH01已启用与上述胸像一致的全身战斧素材家族，八张原始PNG由内置`image_gen`于2026-09-30生成，以[完整家族注册](../assets/generated/heroes/CH01_storybook_family_v1.json)统一选择，缺少任何一组有效资源时整族回退。通用姿态为[正面v1](../assets/generated/heroes/CH01_storybook_actions_front_v1.json)/[背面v1](../assets/generated/heroes/CH01_storybook_actions_back_v1.json)，步态见[步态注册](../assets/generated/heroes/CH01_storybook_walk_v1.json)，普攻为[正面v1](../assets/generated/heroes/CH01_storybook_basic_front_v1.json)/[背面v1](../assets/generated/heroes/CH01_storybook_basic_back_v1.json)，横扫为修正刃向后的[正面v2](../assets/generated/heroes/CH01_storybook_secondary_front_v2.json)/[背面v1](../assets/generated/heroes/CH01_storybook_secondary_back_v1.json)。各组JSON保留完整提示词、原始来源、透明区域检查与姿态锚点，PNG未改像素。每个正/背视角有四通用姿态、四步态、六普攻姿态和六横扫姿态；Q/F/R/闪避复用通用姿态，左右采用水平镜像形成四朝向，尚非完整八方向连续动画。
- 新导航图集包含英雄、技能、配装、商店、地图、金币、提灯、锁定等十二种图标；技能图集为三职业各四项技能提供十二个独立图标；HUD组件图集包含英雄与技能纸面条、任务纸片、黄铜圆框、回路闪电球与路线节点。完整提示词、日期、生成器和图像检查记录分别见[导航来源](../assets/generated/ui/storybook_navigation_v2.json)、[技能来源](../assets/generated/ui/storybook_abilities_v2.json)、[HUD组件来源](../assets/generated/ui/storybook_chrome_v2.json)。同名`.regions.json`记录运行时取样区域；原始PNG未裁切或重绘，纸面组件按九宫格伸缩适配实际文字与控件。
- 36类普通敌人与四个首领的明亮配色由`scripts/combat/enemy_palette.gd`着色器处理，区分珊瑚、靛蓝、翡翠、暖铜与紫晶色系，并保留黄铜关节和独立晶体/镜片色。复用原图、透明度与动作注册，没有新增怪物逐帧动画；身体受击与退场仍使用各自实际反馈逻辑。
- 先前CH01战斧素材的七份注册继续保留，作为整族回退及历史来源：generic v4战斗待机、basic v2、secondary v2、walk v3。完整提示词与来源分别见[战斧通用来源](../assets/generated/heroes/CH01_axe_v1_provenance.json)、[普攻来源](../assets/generated/heroes/CH01_axe_basic_v2_provenance.json)、[横扫来源](../assets/generated/heroes/CH01_axe_secondary_v2_provenance.json)、[走路来源](../assets/generated/heroes/CH01_axe_walk_v3_provenance.json)；当前战斗使用上述彩绘全身家族，角色卡使用彩绘胸像。下列旧锤版动作记录保留为更早来源，不代表当前仍展示旧武器。
- 先前锤版CH01走路初版来自内置ImageGen：[前视角](../assets/generated/heroes/CH01_walk_front_v2.png)、[后视角](../assets/generated/heroes/CH01_walk_back_v2.png)各四个不同关键姿态，左右朝向使用水平镜像；完整提示词见[来源记录](../assets/generated/heroes/CH01_walk_v2_provenance.json)。旧候选拒收说明`sources/CH01_walk_v1_rejected.json`按现有规则忽略，不属于运行资源。
- 枪手CH02同样启用四关键姿态走路初版，复用内置ImageGen原创[前图v2](../assets/generated/heroes/CH02_walk_front_v2.png)、[背图v2](../assets/generated/heroes/CH02_walk_back_v2.png)并修正脚部锚点，PNG未变；完整来源见[CH02走路记录](../assets/generated/heroes/CH02_walk_v2_provenance.json)。本轮ImageGen v3修复候选因支撑腿错误拒收，曾保存在本地 artifacts，现已按工作区清理要求删除，不作为运行资源上传。CH03正面步态候选仍拒收、禁用；四关键姿态初版不代表八帧或八方向连续动作完成。
- 技能预警、弹体、部分反馈、交互标记、UI 排版和形状由本工程 GDScript 绘制，并与实际战斗状态同步。
- 先前锤版CH01普攻使用内置ImageGen生成的原创透明[前视角图](../assets/generated/heroes/CH01_basic_front_v1.png)与[后视角图](../assets/generated/heroes/CH01_basic_back_v1.png)，各六姿态：三前摇、一命中、二收势；完整提示词与来源见[普攻来源记录](../assets/generated/heroes/CH01_basic_v1_provenance.json)。图集只供普攻，按真实反馈阶段以88世界像素绘制，不改伤害或冷却，也不代表所有角色动作完成。
- 先前锤版CH01鼠标右键“破桩横扫”使用内置ImageGen原创透明[前图](../assets/generated/heroes/CH01_secondary_front_v1.png)、[背图](../assets/generated/heroes/CH01_secondary_back_v1.png)，各六关键姿态：plant/coil/drive/contact/follow/ready；完整提示词与来源见[横扫来源记录](../assets/generated/heroes/CH01_secondary_v1_provenance.json)。PNG保持生成原样，背图以帧矩形避开四源像素分隔带；专用机械解锁→扫风声由本项目原创合成，四变体替换原有技能声音分支，不增加音效库数量。
- CH02鼠标右键已启用内置ImageGen原创透明[前图](../assets/generated/heroes/CH02_secondary_front_v1.png)、[背图](../assets/generated/heroes/CH02_secondary_back_v1.png)，源图各六姿态，当前施法仅映射brace/lock/absorb三姿态保持抵肩稳定；完整提示词与来源见[CH02技能来源记录](../assets/generated/heroes/CH02_secondary_v1_provenance.json)。
- CH03 F已启用内置ImageGen原创透明[前图v2](../assets/generated/heroes/CH03_f_front_v2.png)、[背图v3](../assets/generated/heroes/CH03_f_back_v3.png)，各六姿态；完整提示词与来源见[CH03技能来源记录](../assets/generated/heroes/CH03_f_v1_provenance.json)。上述三项技能均使用`*_front/back_v1.json`注册为88世界像素，PNG保持生成原样；失败候选未启用，已按工作区清理要求删除。此项不包含其余Q/R等技能或完整八方向动画。
- 地形与道具继续复用既有岩石、机械和区域液面资源，并接入上述新地面与边缘装饰；明亮区域配色、崖面与内沿由代码绘制或着色。普通干燥障碍已缩小并拓宽通行区域，具体布局规则见[README](../README.md)；装饰不参与碰撞，实体障碍与显示足迹对应。
- 怪物死亡后的短倒伏与退场由 `scripts/combat/enemy_defeat_feedback.gd` 捕获现有贴图、当前姿态并程序变换，未新增死亡逐帧图集；降低特效时采用静态淡出。普通、精英和召唤怪适用，首领与静态对象不使用此效果。
- 战斗音效和四首场景音乐均为本项目程序合成的原创声音，未使用第三方录音采样或商业配乐。音乐音符事件、配器和SHA-256见 `assets/music/score.json`，可复现生成器为 `tools/compose_audio.py`；其授权见 `assets/music/README.md`。
- 命中与死亡音效的金属、石质、有机材质响应均由 `scripts/audio/impact_synth.gd` 合成；每种提供四个独立PCM波形变体，播放音高固定为1。音乐在有效命中声音播放时暂时让位由运行逻辑控制，不改写配乐文件或玩家音量设置。
- 技能准备音与每次实际释放音由真实技能事件调度，取消后不再播放未来释放；准备音有48个PCM变体。陷阱触发、节点开火、领域脉冲新增12个PCM变体，均为本项目原创合成声音，不新增外部采样。时序验证与试听边界见本地验收记录。
- Noto Sans SC 字体来自 [Google Fonts 官方目录](https://github.com/google/fonts/tree/main/ofl/notosanssc)，遵循 SIL Open Font License 1.1。字体文件 `assets/fonts/NotoSansSC.ttf` 与完整许可 `assets/fonts/OFL.txt` 一并保留。
- Godot 引擎遵循 MIT 许可。仓库不包含引擎二进制；安装脚本从官方发行下载并核验完整性。分发独立游戏时须附引擎与依赖许可，参见 [Godot 官方许可说明](https://godotengine.org/license/)。

截图、录屏及原始生成过程的重复工作副本不属于游戏运行资源，未随本次核心源码上传。CH01旧锤版走路曾因高抬膝和缺少过渡而偏负重踏步；当前彩绘战斧家族与CH02步态仍以关键姿态播放。关键姿态不等于八帧循环或完整八方向连续动画，也不代表所有英雄动作完成。

当前统一尺度说明：以上各代素材中的 88 世界像素是生成注册时的历史记录；当前启用英雄身体已统一为 112 世界像素，实际显示以 presentation_metrics 和运行素材绑定为准。
