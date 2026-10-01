# 游戏代码待办与十二关路线图

更新日期：2026-10-01。按最新需求继续完善前四副本的敌群难度、数量、种族技能与首领战术。本文件记录实施和后续事项；实际范围见 [开发进度](DEVELOPMENT_PROGRESS.md)，目标见 [用户需求](USER_LEVEL_BRIEF.md) 与 [设计稿](LEVEL_DESIGN_V1.md)。

## 前四关下一轮事项

| 编号 | 工作与状态 | 主要入口 | 完成条件 |
|---|---|---|---|
| MAP01 P0 | 房间摆放分组，仅草稿 | data/fixed_rooms.json、scripts/world/fixed_room_layouts.gd、prop_identity.gd、docs/drafts/room-placement-20261001/ | 按用途成组，中心主路通畅；目标与装饰分开；保留全部运行字段，同步 28 张图并检查典型实机房 |
| MAP02 P0 | 同族七房独立构图，待开发 | scripts/world/world_art.gd、environment_chunks.gd、room_appearance.gd、环境资源 | 地标、边缘、生活区和地面细节各房可辨；风格、尺度、接缝与碰撞一致；不能同母图换色计完成 |
| MAP03 P0 | 地板比例和空场感校对 | presentation_metrics.gd、world_camera.gd、环境 metadata、蓝图 | 实际镜头下砖、人物、门和道具尺度符合参考；避免持续放大人物；大窗口不露画外，HUD 完整 |
| COM01 P0 | 枪口出弹和枪手打击感，待修 | hero_visual.gd、hero_feedback.gd、projectile_visual.gd、projectile.gd、room.gd、hero_skill_atlas.gd、combat_audio.gd | 可见弹体从本次姿态枪口发出，方向一致，墙角不穿模；后坐、闪光、命中和声音同节奏，保留物理结算规则 |
| COM02 P1 | 三职业十二技能专属效果，未开始 | hero_abilities.gd、hero_feedback.gd、skill_input_feedback.gd、scripts/ui/hud.gd、技能素材 | 每招蓄力/释放/命中或落点语言可辨，连招提示清楚；降低特效保留信息，不能仅换颜色 |
| COM03 P1 | 累计野怪量增加约40%，计划与实际运行已检查 | enemy_profiles.gd 的 encounter_plan、room.gd、config/ | 已通过有限后续波次增量与五难度数量检查，保留并发、弹体和召唤上限；后续按自然群战节奏调校 |
| COM04 P1 | 四族普通怪特性已接入并通过实效检查 | enemy_biome_skills.gd、enemy_difficulty.gd、enemy_skill_runtime.gd、enemy_brain.gd、first_four_construct_hive.gd | 护盾、毒蚀、回血、狂怒及冷却真实生效；普通怪20级高难效果已检查，保留36原型预警；后续调校区域群战平衡 |
| COM05 P1 | 四首领独立战术与专属主动技能已接入并通过实效检查 | boss_brain.gd、boss_profiles.gd、boss.gd | 按距离和冷却选招、追击/绕行/拉开距离，新增交叉雷网/三点酸雨/缝线牢笼/裂岩跃击；保留主题反制、锁定预警与弱点停顿，后续完善独立动画和自然战斗平衡 |
| UI01 P1 | 页面和信息细节收尾 | scripts/ui/style.gd、button_skin.gd、main.gd、expedition_panel.gd、backpack_panel.gd、hud.gd | 使用独特 UI 构件；焦点、禁用态和文案清楚；中英文及 1280×720、1920×1080、1280×900 不截断；只检查实际改动页 |
| ANIM01 P2 | 完整角色动作和附件 | hero_art_family.gd、hero_walk_atlas.gd、hero_basic_atlas.gd、hero_skill_atlas.gd | 头像身份、身体高度、脚点一致；补连续动作与必要朝向；枪口锚点一致，拒收候选不启用 |

未带目录的战斗脚本均位于 scripts/combat/，世界脚本位于 scripts/world/。

MAP01 不能整房字典覆盖运行数据。文档草稿不含全部运行字段，后续只合并批准陈设、地标和说明，保留 biome_id、首领反制、固定奖励、任务、信标、遭遇及状态，再重绘图纸。

## 装备循环实施顺序

当前是六槽固定模板和预强化。完整目标是通关高难度副本，获得本族装备，配装提升，出售或洗练后继续挑战。每步保持旧档和撤离事务安全。

| 编号 | 工作 | 入口与依赖 | 完成条件 |
|---|---|---|---|
| EQ01 P1 | 八槽和独立实例 | scripts/data/content_registry.gd、scripts/core/profile_store.gd、backpack_equipment.gd、stat_resolver.gd、data/equipment.json | legs/ring 全链路生效，同模板多件有实例 ID，旧六槽迁移，配装/比较/入库不串件 |
| EQ02 P1 | 白绿紫金与随机词条 | 依赖 EQ01；装备目录、equipment_effects.gd、掉落和属性结算 | 品质越高词条越多；设计草案白0/绿2/紫3/金4，数值需平衡；种族/槽位/职业池、互斥和触发上限真实生效；品质与强化分开 |
| EQ03 P1 | 难度与本族实例掉落 | scripts/world/room_rewards.gd、scripts/core/expedition_state.gd、run_state.gd | 难度影响数量、属性和品质权重；不回退别族；撤离永久入库，死亡不保存临时物品，重试不重复奖励 |
| EQ04 P1 | 背包出售 | 依赖实例；backpack_panel.gd、workshop_panel.gd、profile_store.gd | 售价预览、已装备物明确处理，删除指定实例与金币原子保存；重复点击一次结算 |
| EQ05 P2 | 洗练和提升 | 依赖 EQ01/EQ02/EQ04；工坊、装备效果、保存 | 显示成本和结果，品质/词条数遵守规则；失败不重复扣款或重抽已确认结果 |
| EQ06 P2 | 血药和蓝药 | 库存、player.gd、run_controller.gd、HUD 和绑定 | 真库存、真实恢复与冷却，职业资源适配，满值不浪费，暂停/死亡/恢复一致 |
| EQ07 P2 | 装备改变游戏中装饰 | 依赖八槽与附件；英雄绘制及装备美术 | 各方向/动作显示头胸手腿鞋武器附件，戒指饰品合理表现；不能仅改头像或背包图 |
| REL01 P2 | 独立种族遗物和构筑 | class_relics.gd、race_relics.gd、数据和 UI | 掉落与种族机制相符，派生伤害不递归，组合有取舍，显示触发条件与真实效果 |

死亡保持用户确认：扣本局金币与未结算经验，保留已有等级。当前金币损失为本局 50%；后续经济调整需明确更新规则，不能悄悄扣永久装备或已结算经验。

## 十二副本状态

| 地图 | 状态 | 种族、首领和机制 |
|---|---|---|
| B01 晴辉遗庭 | 原型接入，继续完善 | 魔法构装；日曜机关巨像；能源回路破盾 |
| B02 琥珀虫巢 | 原型接入，继续完善 | 虫族；琥珀虫后；毁巢断援和外壳弱点 |
| B03 南瓜墓镇 | 原型接入，继续完善 | 僵尸；缝合镇长；封墓抑制复苏 |
| B04 赤岩战寨 | 原型接入，继续完善 | 兽人与食人魔；裂岩大酋长；冲撞拆障 |
| B05 繁花树庭 | 待开发 | 植灵；千枝花冠树王；生长、藤桥、花台和根须 |
| B06 琉潮珊城 | 待开发 | 海族；行走巨蟹堡垒；潮汐、路线与移动 |
| B07 金沙蜥城 | 待开发 | 蜥人；日轮蜥王；日光反射、显隐与破盾 |
| B08 浮羽空港 | 待开发 | 翼人；苍穹风羽统领；风道、顺风与俯冲 |
| B09 霜晶王庭 | 待开发 | 冰晶雪灵；霜晶女王；缓和惯性与冰桥重组 |
| B10 熔辉魔堡 | 待开发 | 炎魔火元素；熔冠魔君；喷发预警和冷却通路 |
| B11 虹伞菌谷 | 待开发 | 菌灵；万伞菌母；弹跳和孢子连锁 |
| B12 星辉龙庭 | 待开发 | 星辉龙裔；星冠古龙；星门与多位置星核破盾 |

后八关逐一补故事、独立美术、普通怪、三技能分阶段首领及反制、六房与首领场地、主题装备/遗物、五难度和掉落。未具备独立资源与真实机制时保持待开发，不以更名换色提前计完成。

## 交付要求

每次更新真实进度和待办，给出运行代码与资源，做直接相关的检查或短段实机观察，提交便于 diff 的版本。素材记录纹理、region、脚点和来源。主观手感未确认就如实保留，不扩大 review 或重复全量测试。
