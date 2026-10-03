# L37 有界真实引擎候选观察

入口：`res://tests/levels/b07/test_l37_live_encounter.tscn`。

必须通过现有 managed runner / shared Godot lock 运行。该脚本要求：

- `GAMES_TEST_OUTPUT_DIR` 已存在；managed runner 的 XDG_DATA_HOME / APPDATA 使 user:// 也位于该输出目录。
- `--candidate-b07 --test-profile=user://test_b07_candidate/l37_live_encounter.json`
- `--b07-art-trial --b07-midground-trial --b07-convergence-review`
- profile 必须是尚不存在的新隔离档；失败不覆盖旧档。

图形模式保留真实 HUD，物理窗口 2560×1440 / 逻辑视口 1280×720，最多 8 张 PNG。headless 使用同场景、相同输入计划、正常物理路径，只跳过图像获取。没有手动 physics/FSM/advance、改出生点、写玩家位置、禁用 AI/runtime 或添加无敌。通过正常 `Game.set_setting` 对隔离档启用 auto_attack，没有攻击/技能/闪避输入；`Game.run.shots` 是本次自动普攻起手计数，不是命中数。

确定性脚本输入：0.25–2.25 秒向右，4.0–4.6 秒向下，7.0–7.6 秒向上，其余松键。计时使用引擎 physics delta；初始真实出生 cohort 死亡/移除、玩家死亡或 25 秒触发终止。最后 post_draw 可能推进少量额外物理帧，terminal 保存触发条件时状态，frames.snapshot_t 与 engine_physics_frame 保存实际获取时刻；不冻结战斗、不声称精确固定步截图。

输出 `L37_live_encounter_report.json`：

- initial：真实出生身份/位置、difficulty、hero_level、stats、loadout/equipment、隔离档路径。
- coverage：每只初始敌人的首次 telegraph/locked/execute/recovery、死亡时刻、最近玩家距离、缺失阶段与观察结束原因。
- events：普通输入，首次阶段及真实 command，M02 motion 起点/移除/可确认落地点及玩家距离，M03 outgoing/return/removal 与可观察原因。
- trace：约 0.1 秒采样，HP/盾/自动普攻起手计数、玩家/敌人、卡片候选与可见卡矩形。
- cards：真实 badge visibility/show_detail、候选 ID、卡/身体/HUD Control 矩形及交叠。HUD 排除全屏根 Control/布局容器；面板、按钮、非空状态 Label 等是保守内容边界，不是逐像素透明度分析，也不宣称无 HUD 遮挡。
- frames：定时与先发生事件请求、实际 snapshot_t、真实战斗状态、PNG；最后一张预留给结束。

难度 0 的 M03 不配置 disc_return（仅 difficulty >= 2）；“返程未覆盖”是配置边界，不能靠改难度、技能或摆怪制造覆盖。路径耗尽不等于回到主人手中；现有 runtime 无移除原因信号的分支明确报告不确定的墙体/拦截/清理，不伪造具体原因。M02 只有保留 motion 已满 duration 且实际落点吻合锁定 target 时才标记确认落地，其余归为中断/碰撞未确认。

这是 Lv31 候选初始化与脚本普通键盘输入的短战斗观察。不是人工自然游玩、正常成长链路、全招式覆盖或自然平衡验收。探针新增时未运行任何 Godot；由协调者统一 managed runner 检查。

## 最终绘制证据与已确认问题

早期physics trace只说明物理采样时状态，不一定等于最终画出的卡片。修前批次`20261003T110742236737Z-8056e252`的8张图已查看，其diagnostic请求在post_draw时均恢复2卡，不能把请求标签当作视觉错误证明。

因此增加显式`--b07-live-render-observe`只读诊断：SkillBadge在实际_draw中保存真正画出的卡矩形，探针在每次frame_post_draw检查并立即保存异常图，不再等到下一帧；旧选择/布局逻辑未改。图形必须带该flag；headless仍只能检查逻辑，不能冒充最终draw。

真正修前基线为`20261003T111340531950Z-c1c68021`：280个post_draw样本，7张2560×1440已逐张查看，0运行失败、无SCRIPT ERROR。t9.25出现实际3卡/2候选（`L37_live_03_diagnostic_card_selection.png`），左两卡互相叠压并覆盖角色；t0.8有右卡边缘进入QuestRibbon（`L37_live_01_diagnostic_hud_overlap.png`）。该批全程统计：1帧卡数不一致，3帧卡/HUD矩形相交，1帧卡/身体矩形相交。HUD是保守内容矩形，不能把透明留白相交单独宣称像素遮挡；已同时核对实际图。

该输入计划未使用技能/闪避，候选初始CH01 Lv31、HP6091、starter装备，约24.37秒死亡。自然首波三身份均进入预警/锁定/施放/恢复；M02后续跃击期间死亡，不能宣称完整落地覆盖。M03三次出盘路程耗尽，D0本身没有D2+回程。死亡与耗时不能当正常装备/操作的平衡结论。

首版headless解析出现过include变量类型推断错误，已显式bool；个别初检有退出ObjectDB泄漏警告，未把它当图形验收。所有运行均为managed shared lock隔离输出；实际截图/JSON日志仅在artifacts/test_runs保留，不入库。

## 运行时修复与复验

`l37_skill_card_layout.gd`现在在合法L37三开关review中安装房间级Coordinator（process_priority=10000）。每次普通HUD处理结束后，统一读取当前全敌候选和readout，刷新全部badge并发布frame/selected_ids/placements批次；_draw只消费该批，不再沿用逐actor物理更新造成的局部选择。卡片障碍加入实际可见HUD内容Control矩形，排除全屏根、空Label及隐藏控件。关闭review和其他房间不走新分支。极小视口或极端拥挤仍有明确least-overlap fallback，不承诺任意布局无交叠。

冻结检查调用相同publish API，仅用于零时钟读表现状态；正常首波探针完全由真实Coordinator驱动，不手工刷新。探针在priority=20000检查发布批次，在post_draw依据badge真正_draw出的矩形独立检查。发布批次和最终draw的记录分开，physics trace也原样保留。

定向批次`20261003T112052322578Z-656e139c`：HUD移动/隐藏/控件排除、受控原动作/真实移动、关闭review和L38/L01拒绝闸门均0fail，无SCRIPT ERROR。后者是范围闸门回归，不代表B01全关验收。新增HUD单元初次在SceneTree._initialize过早读取可见性失败，改为deferred入树后检查，原断言未放宽。

正常AI headless `20261003T112220311312Z-43e67435`：3442次发布批次检查，身份/张数/身体/HUD矩形问题0；场景仍按原输入约24.37秒死亡。首次增加probe issue表达式时曾有类型推断解析错误，已显式bool，未以退出码零掩盖脚本错误。

父任务实际图形批次`20261003T112544247538Z-d35f0ba1`：7张2560×1440全已查看，291次真实post_draw与291次发布检查，卡片身份/数量不一致0，卡/身体相交0，卡/HUD相交0；严格后处理断言通过，无SCRIPT ERROR，仅软件驱动VSync警告。包含旧问题附近t0.8及t9.25的定时图，原三卡重叠已变为两卡分开。某些卡避让到较远外围，归属线较长，仍需之后的可用性收敛。正常AI、伤害、输入、出生点和几何未改，24.383秒死亡仍不构成平衡结论。

其余已见而未修改：死亡后candidate清理Game.run，HUD refresh直接return，终局血条停在此前451/6091；D0卡片沿用通用反制说明，M01提到D2尾扫、M03提到D2两段回返，不能据文案声称D0覆盖它们。M02本次跃击期间被击败，未验证完整自然落地；D0无飞盘回程。连续动画0套、M11blocked、35件B07专属装备资源及运行登记均未完成，本轮不声称全关或整体参考验收。

## 完整背景复用的只读分析

原`canyon_backdrop.png`为1552×1013。当前review裁`[0,380,1552,633]`后cover到蓝图[-900,-800,4600,3000]，入口实际只采原图约x291–937/y499–862，2K画面约3.96物理像素放大每源像素；主城被裁走，模糊远岩无法承担主体蜥城。

若仅取消crop、同一painted bounds与镜头不变，cover缩放约2.964蓝图单位/源像素（居中纵裁约1.224蓝图单位），入口可见原图约x0–1034/y190–772，2K约2.48倍放大。可恢复左侧连贯峡谷、桥及岩体空间关系，但主体日镜上部仍出入口画面，城门下部仍受北侧固定地面遮挡。可复用的是完整远景叙事，不是现成可走城台；仅取消crop不能称参考完成。本阶段未据此改背景、镜头或生成新图。
