# 游戏代码待办与十二关路线图

更新日期：2026-10-03。前四副本按“一房一张背景”接入独立原画、地图用途分组与房间 UI；PR #2交付S00–S10的数值和装备循环，S11自然平衡继续暂缓。本文件记录实施和后续事项；实际范围见 [开发进度](DEVELOPMENT_PROGRESS.md)，目标见 [用户需求](USER_LEVEL_BRIEF.md) 与 [设计稿](LEVEL_DESIGN_V1.md)。

PR #4已按最新授权完成合并前审查修复：普通保存增加同代陈旧状态保护，精确失败重试与Windows回收站进程锁已定向验证。全局UI、三职业、普通怪和高清资源的具体本轮检查见[PR #4审查记录](audits/PR4_ACCEPTANCE_2026-10-02.md)。S11自然平衡、长期玩法、实际音频输出及后八关仍按原边界保留，不能因合并本PR提前计作完成。

第二轮审查A13–A30已通过PR #1合入，并与本地同期装备UI改进整合；历史定向证据见[修复与验收](audits/GAMEPLAY_AUDIT_ROUND2_FIXES_2026-10-01.md)。八槽/实例/随机品质已由PR #2的S03–S06实现并接入保存与界面；分支时机、战斗背包换装频率、状态/护盾理解和自然多局体验继续待游玩验证。

等级、装备与全量Buff实施依据为[数值方案](balance/LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md)、[目标数值全表](balance/TARGET_NUMERICAL_TABLES.md)及[S00–S11执行清单](balance/NUMERICAL_REDESIGN_EXECUTION_STEPS.md)。S00–S10已实现，正常新档默认使用×10整数规则、20级天赋、124模板/八槽实例及最高+10手动强化，旧进行中冒险冻结旧版本。本轮按用户授权验收和修复PR #2，证据见[本地验收记录](balance/PR2_ACCEPTANCE_2026-10-02.md)；自然平衡未完成。

数值方案的最新约束见[随机强化方案](balance/RANDOM_FORGING_DESIGN.md)及[章节/Boss标尺](balance/BOSS_DIFFICULTY_CALIBRATION.md)：各品质掉落上限、三组强化等效和每阶随机收益统一计算；1–12章递增，未来B05–B12仅规划接口。全金约+2的对应章D4碾压表现属于后续12组职业/Boss实战目标，尚未实现或验证。

## 前四关下一轮事项

2026-10-02 合并后界面回归及背包/战斗性能的修复与定向证据见[追加修复记录](audits/POST_PR2_UI_FIXES_2026-10-02.md)：商城及腿/戒图示、战利品交互、主动拾取、奖励保存、种子精度和首领动作已处理；装备视图缓存、原生图集预取、白绿紫金标识、AI属性查询和首次命中资源预热已核查。L23自然受击与普攻击杀已观察；当前配装/遗物的D4酋长站撸样本死亡，其他移动打法、帧波动及完整S11仍待自然游玩校调。

| 编号 | 工作与状态 | 主要入口 | 完成条件 |
|---|---|---|---|
| MAP01 P0 | 28 房用途分组已接入；历史草稿单独保留 | data/room_presentations.json、scripts/world/room_presentation.gd、fixed_room_layouts.gd、prop_identity.gd | 56 分组与 168 陈设按用途摆放；保留原蓝图、实体掩体与奖励；用真实 28 房运行图册记录当前状态 |
| MAP02 P0 | 28 房独立完整背景与房间识别 UI 已接入 | assets/generated/world/rooms/、scripts/world/world_art.gd、environment_chunks.gd、scripts/ui/room_identity_plate.gd | 同族七张独立原画；各房地标、边缘、生活区和地面各异；本房边界/镜头/六区块/小图一致，资源像素摘要与实际加载路径各不相同 |
| MAP03 P0 | 地板比例和空场感校对 | presentation_metrics.gd、world_camera.gd、环境 metadata、蓝图 | 实际镜头下砖、人物、门和道具尺度符合参考；避免持续放大人物；大窗口不露画外，HUD 完整 |
| MAP04 P0 | 全屏背景放大采样已改善并定向验证；高分辨率原画细节仍待完善 | environment_chunks.gd、shaders/environment_sampling.gdshader、tests/test_environment_clarity.gd | 放大重建、缩小 mip 抗锯齿、六块接缝连续；L16/BO04 两窗口及 L16 实际全屏 GPU 50 项通过，保持人物/镜头/地形；源图仍为 1536×1024，不以采样改善代替高分辨率美术 |
| COM01 P0 | 姿态枪口展示路径、方向锁定与墙边裁切已接入并通过针对性检查；新增三拍枪焰/曳光/命中变化 | hero_visual.gd、hero_feedback.gd、projectile_visual.gd、projectile.gd、room.gd、hero_skill_atlas.gd、combat_audio.gd | 保留真实物理弹道；后续检查全部方向、密集地形和自然射击的声音/动作主观手感 |
| COM02 P1 | 三职业技能专属效果与声音已接入；新增x1–x100连击增伤、五档特效、Buff与普攻轮换，机制/UI/实际GPU练习场已检查 | hero_abilities.gd、hit_chain.gd、hero_feedback.gd、projectile.gd、impact_feedback.gd、scripts/ui/hud.gd、hit_chain_readout.gd | 继续校调自然群战与增伤平衡；降低特效保留实际读数与范围；不把受控练习场通过当作完整动画/平衡完成 |
| COM03 P1 | 累计野怪量增加约40%，计划与实际运行已检查 | enemy_profiles.gd 的 encounter_plan、room.gd、config/ | 已通过有限后续波次增量与五难度数量检查，保留并发、弹体和召唤上限；后续按自然群战节奏调校 |
| COM04 P1 | 四族普通怪特性已接入并通过实效检查 | enemy_biome_skills.gd、enemy_difficulty.gd、enemy_skill_runtime.gd、enemy_brain.gd、first_four_construct_hive.gd | 护盾、毒蚀、回血、狂怒及冷却真实生效；普通怪20级高难效果已检查，保留36原型预警；后续调校区域群战平衡 |
| COM05 P1 | 四首领独立战术、16招逐难度解锁和施法HUD已接入并检查 | boss_brain.gd、boss_ability_catalog.gd、boss_skill_presentation.gd、boss_cast_plate.gd、boss.gd | 每位首领进阶至极限逐档新增一招，按距离/冷却选择；HUD显示实际施法与锁定进度，保留主题反制和弱点停顿；16新招实效及中英文三窗口GPU通过，完整独立动画和自然战斗平衡待完善 |
| COM06 P0 | 野怪攻击射程与稳定仇恨已补修；真实main暂停恢复检查通过，原整群停止现场待重启复核 | enemy.gd、enemy_brain.gd、tests/test_enemy_attack_flow.gd、tests/test_enemy_live_room.gd | 侧移及辅助转近战按实际招式接近，保留完整预警；节点失效/普攻仇恨正常；真实B03→L15原生首波与M开关均能攻击，现场运行进程早于修复写入，未确认原整群停止根因 |
| COM07 P1 | 599普通怪身体外观与36施法徽章已接入并检查 | enemy_art.gd、enemy_visual.gd、room.gd、docs/ENEMY_VARIANTS.md | 独立房间累计分配，真实纹理/region去重；120个普通房/难度有限计划重复率0%，L15/L19极限真实生成已检查；技能召唤重复率、完整逐帧动画与主观密集群战可读性待完善 |
| COM08 P0 | 首领贴身空招、静止岩缝与断层中缝已修复；具名战士极限站撸基准通过 | boss_brain.gd、boss_ability_catalog.gd、tests/test_boss_targeting.gd、tests/test_boss_stationary.gd | 按真实危险环与身体半径选招，不消耗轮换；静止岩缝与瞄准断层实伤、锁后侧移实躲已检查；原生Lv12／Lv20 S06＋RL03 II战士持续普攻及W/E/R均死亡，28项0失败；保留完整预警与反制，其他临时构筑和自然平衡继续游玩校调 |
| COM09 P0 | 四关9/12/15/18种、真实新机制/难度技能、原生身体及短预警已接入并定向验证；最终GPU呈现在验收 | enemy_ability_catalog.gd、enemy_warning_timing.gd、enemy_brain.gd、boss_brain.gd、enemy_skill_runtime.gd、enemy_profiles.gd、monster_codex.gd | 54种全技能及D1–D4门槛共源；18新机制实效/反制；54种施法UI；高清身体/图鉴身份；对应关卡和数值文档同步，详见ORDINARY_MONSTER_EXPANSION.md；S11仍暂停 |
| UI01 P1 | 装备／属性／页头重构、六类 v5 按钮和确认操作等宽已接入并截图检查 | scripts/ui/style.gd、button_skin.gd、main.gd、equipment_catalog.gd、equipment_details.gd、backpack_panel.gd、hud.gd | 中英文 51 状态共 102 张 1280×720 GPU 截图已审查；装备页另查三窗口；焦点／禁用态、真实数值与成对按钮已检查；新增界面继续按实际改动校对，证据见 UI_SCREENSHOT_AUDIT.md |
| ANIM01 P2 | 完整角色动作和附件 | hero_art_family.gd、hero_walk_atlas.gd、hero_basic_atlas.gd、hero_skill_atlas.gd | 头像身份、身体高度、脚点一致；补连续动作与必要朝向；枪口锚点一致，拒收候选不启用 |

未带目录的战斗脚本均位于 scripts/combat/，世界脚本位于 scripts/world/。

MAP01 不能整房字典覆盖运行数据。本轮通过独立表现配置只重组无碰撞陈设，保留 biome_id、首领反制、固定奖励、任务、信标、遭遇及状态。历史草稿不含全部运行字段，继续单独留存；新表现索引见 [ROOM_PRESENTATION](ROOM_PRESENTATION.md)，生产截图图册按定向检查生成。

## 装备循环实施顺序

正常新局已使用八槽独立实例、白绿紫金随机词条、本族掉落、购买/打造、随机强化、保底重锻、词条重铸/精炼、继承和出售/拆解。旧进行中冒险继续六槽历史规则至回营地。高难度配装表现和自然获取时长仍属S11待验证目标。

商城历史扩充增加6套共36件，旧规则目录96件／14套；PR #2补齐14套裤/戒共28模板，新规则目录124件。单件重复购买、九折补齐和一键穿戴走永久档事务，商城套装的打造族材映射独立登记，不混入自然掉落池。详见 [装备商城与回收](EQUIPMENT_MARKET.md)及[本地验收记录](balance/PR2_ACCEPTANCE_2026-10-02.md)。

入口已补修：营地「装备商城」和工坊「采购装备」默认展示六套新装备，仓库提示已拥有范围及筛选数量，营地「装备工坊」提示多选回收；GPU 装备市场 238 项检查通过。

| 编号 | 工作 | 入口与依赖 | 完成条件 |
|---|---|---|---|
| EQ01 P1 | 八槽和独立实例已接入并定向验收 | content_registry.gd、equipment_instances.gd、profile_store.gd、backpack_equipment.gd、stat_resolver.gd | 124模板、legs/ring全链路、同模板独立ID、旧档迁移与冻结局、配装/比较/入库保存通过 |
| EQ02 P1 | 白绿紫金与随机词条已接入并定向验收 | equipment_instances.gd、equipment_acquisition.gd、equipment_effects.gd、stat_resolver.gd | 白0/绿2/紫3/金4、种族/槽位/职业合法池、互斥和触发上限已检查；自然平衡待S11 |
| EQ03 P1 | 难度与本族实例掉落已接入并定向验收 | room_rewards.gd、expedition_rewards.gd、expedition_state.gd、run_state.gd | 冻结随机结果、召唤零奖励、撤离入库、死亡丢临时资产、唯一结算、D4同族保底已检查 |
| EQ04 P1 | 实例出售/拆解与唯一退款账本已接入 | instance_forging.gd、instance_forging_panel.gd、run_controller.gd、profile_store.gd | 按实例回收，锁定/穿戴/未结算保护、实付退款和跨族材料归属已检查；旧模板多选回收保留历史路径 |
| EQ05 P2 | 强化/重锻/重铸/精炼/继承已接入并定向验收 | instance_forging.gd、instance_economy.gd、instance_forging_panel.gd、保存事务 | +10、随机8–12%、四次保底、固定重铸槽、继承逐阶取优与逐笔补差、失败重试不重抽已检查；自然经济待S11 |
| EQ06 P2 | 血药和蓝药 | 库存、player.gd、run_controller.gd、HUD 和绑定 | 真库存、真实恢复与冷却，职业资源适配，满值不浪费，暂停/死亡/恢复一致 |
| EQ07 P2 | 装备改变游戏中装饰 | 依赖八槽与附件；英雄绘制及装备美术 | 各方向/动作显示头胸手腿鞋武器附件，戒指饰品合理表现；不能仅改头像或背包图 |
| REL01 P2 | 独立种族遗物和构筑 | class_relics.gd、race_relics.gd、数据和 UI | 掉落与种族机制相符，派生伤害不递归，组合有取舍，显示触发条件与真实效果 |

死亡保持用户确认：扣本局金币与未结算经验，保留已有等级。当前金币损失为本局 50%；后续经济调整需明确更新规则，不能悄悄扣永久装备或已结算经验。

## 十二副本状态

2026-10-03 PR #7 已合并，B05/B06 已整合至 main；默认 `data/numerical_v2.json` 仍为4章/Lv20、archive14，B05/B06 及 archive15 仍需显式隔离候选入口，不修改真实玩家档。用户最新授权将[平衡遗留问题](balance/BALANCE_FOLLOWUPS_2026-10-03.md)单独写成 PR，并分别创建分支/PR 开始 B07、B08 开发，覆盖此前“先完成共享模型再启动 B07+”的暂停范围。平衡遗留不阻塞这两章开工，但未完成项不因新章开发而计作通过；B09–B12 继续待开发。怪物公式与核验入口见[数值总案第9节](balance/LEVEL_EQUIPMENT_NUMERICAL_DESIGN.md#9-野怪首领与难度标尺)。

| 地图 | 状态 | 种族、首领和机制 |
|---|---|---|
| B01 晴辉遗庭 | 原型接入，继续完善 | 魔法构装；日曜机关巨像；能源回路破盾 |
| B02 琥珀虫巢 | 原型接入，继续完善 | 虫族；琥珀虫后；毁巢断援和外壳弱点 |
| B03 南瓜墓镇 | 原型接入，继续完善 | 僵尸；缝合镇长；封墓抑制复苏 |
| B04 赤岩战寨 | 原型接入，继续完善 | 兽人与食人魔；裂岩大酋长；冲撞拆障 |
| B05 繁花树庭 | 同树隔离候选已接入；难度/装备待验，默认未发布 | 植灵；千枝花冠树王；生长、藤桥、花台和根须 |
| B06 琉潮珊城 | 同树隔离候选已接入；难度/装备待验，默认未发布 | 海族；行走巨蟹堡垒；潮汐、路线与移动 |
| B07 金沙蜥城 | 已授权独立分支/PR 开发；尚未验收 | 蜥人；日轮蜥王；日光反射、显隐与破盾 |
| B08 浮羽空港 | 已授权独立分支/PR 开发；尚未验收 | 翼人；苍穹风羽统领；风道、顺风与俯冲 |
| B09 霜晶王庭 | 待开发 | 冰晶雪灵；霜晶女王；缓和惯性与冰桥重组 |
| B10 熔辉魔堡 | 待开发 | 炎魔火元素；熔冠魔君；喷发预警和冷却通路 |
| B11 虹伞菌谷 | 待开发 | 菌灵；万伞菌母；弹跳和孢子连锁 |
| B12 星辉龙庭 | 待开发 | 星辉龙裔；星冠古龙；星门与多位置星核破盾 |

后八关逐一补故事、独立美术、普通怪、三技能分阶段首领及反制、六房与首领场地、主题装备/遗物、五难度和掉落。未具备独立资源与真实机制时保持待开发，不以更名换色提前计完成。

## 交付要求

每次更新真实进度和待办，给出运行代码与资源，做直接相关的检查或短段实机观察，提交便于 diff 的版本。素材记录纹理、region、脚点和来源。主观手感未确认就如实保留，不扩大 review 或重复全量测试。

三职业定位、独立成长、八向动作和职业装备限制已接入并完成针对性验收，详见[方案与实际验收](character-optimization/ROLE_OPTIMIZATION_2026-10-02.md)。自然长期玩法及S11全量平衡仍未完成。
