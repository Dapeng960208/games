# 三职业重构契约

状态：代码及新版 UI 已接入，36 技能释放与三职业首关流程已复查；完整新美术与整体正式验收尚未完成。更新：2026-10-03。

## 固定规则

每职业十二个主动技能，本职业任选四个，输入槽 `q/secondary/f/ultimate` 对应 Q/W/E/R。技能身份为 `CH01_SK01` 至 `CH03_SK12`，冷却、成长、分支及装备触发跟随身份。只有营地能提交四槽及分支；整次出征冻结配置。基础普攻、闪避、枪手装填不占主动槽。

三职业分别采用怒气狂战、机动装填、单星灵协同。角色页、技能页全部重做；战斗 HUD 保留当前布局，显示真实新机制。动作强调灵敏、清晰及重量，视觉停顿不改变游戏时钟。美术原创或定制。岑线仍为成年女性。露弥按最新指令采用暗黑魔法师造型，胸部丰满、腰线清晰、肩臂与腿部纤细；黑曜黑、午夜紫、银饰与幽蓝魔光，不能改成整体肥胖或樱粉配色。

## 代码所有权

主智能体拥有 Game/Main、总目录、英雄总表、数值规则、房间运行适配、固定房间字段合并、资源索引和测试注册。A1 拥有角色/施法/被动中央入口与输入。A2–A4 各自拥有 `scripts/gameplay/characters/kits/*_kit.gd`，包含各十二技能数据、有限时间轴、效果及职业值状态。A5 拥有角色/技能页；A6 拥有 HUD/技能格；A7 拥有成长、营地服务、RunSession 与 CombatSnapshot；A8 拥有装备消费者及遗物；A9 拥有美术、动作与表现；A10 拥有检查和测试并独占 Godot 导入/构建进程。

## 目录和职业接口

`SkillCatalog.skills(hero_id)` 返回十二项字典；`skill(skill_id)` 返回一项；`starter_ids(hero_id)` 返回前四个身份。三十六技能规格保存于 `numerical.json.class_skill_specs`，三个职业模块的 `skill_specs()` 读取同一表并加工身份与说明，目录不预加载以避免循环。技能数据至少含 `skill_id/hero_id/name/origin_slot/effect_kind/cost/cooldown/base_cooldown`，数值单位沿现有 RuntimeRules。

职业模块提供 `configure(player), tick(delta), timeline(data), resolve_skill(cast,index), apply_skill_variant(data,rank,branch), on_original_hit(target,packet,result), on_skill_release(cast), primary_damage_multiplier(), damage_multiplier(skill_id), attack_speed_multiplier(), movement_multiplier(), can_primary(), on_primary_created(), on_dash_finished(success), export_state(), restore_state(data), hud_state()`。不适用方法返回无增益或空值。第一次释放可返回伤害/护盾修正；该次施法之后保留已冻结数值。枪手提供 `request_reload()`；职业装备命令由 A1/A8 协调。

`HeroActor.skill_id_for_slot(slot)`、`skill_progress(skill_id)`、`combat_hud_view()` 为适配入口。施法记录含 `cast_id/skill_id/input_slot/origin/target/direction/rank/branch/stats_snapshot`；原始命中与衍生效果明确分流，根事件去重有界。

## Game 与保存接口

`get_loadout(hero_id)`、`get_skill_progress(hero_id,skill_id)` 优先读取出征冻结的四槽/分支，熟练度读取永久档并从下一次施法生效。`apply_skill_config(hero_id,four_skill_ids,branch_choices,operation_id="")` 返回 `{ok,reason,operation_id}`。`record_skill_release(skill_id,cast_id,base_cooldown,in_combat)` 与 `grant_skill_group(group_id,operation_id="")` 交由 SkillConfigService。技能服务自己的 record 方法不需要基础冷却参数，读取稳定目录。

主存档 schema/settlement 仍为 3，新增技能子版本 1 和职业战斗子版本 2。熟练度累计门槛 0/20/60/140/300；解锁永久保留。所有永久成长提交携带 `run.receipt()` 的已提交检查点，不用半房间 `live_receipt()`。旧档只在完整验证后迁移，未知损坏档保持写保护。

## UI 读模型

`hero_view(hero_id,context)`：`hero_id, identity{name,title,class_name,role_summary,mechanic_text}, stats, stat_report, loadout, collected_count,total_count,editable,lock_reason`。

`skill_page_view(hero_id,context)`：`hero_id,skills,loadout,branch_choices,editable,lock_reason`。每个技能含 `skill_id,name,description,unlocked,mastery_xp,mastery_level,spec,branches,source,icon_id`。

`combat_hud_view()`：`hero_id,hp,max_hp,shield,resource,resource_max,slots:Array,role_state`。技能含 `slot,input_slot,skill_id,name,name_en,description,description_en,cooldown,remaining,cost,locked,lock_reason,casting,cast_progress,queued,queue_position,busy,ready,key,icon_id,branch,rank`；`cooldown` 是冻结的总冷却，`remaining` 是该身份的实际剩余冷却。职业状态由模块导出，HUD 不计算判定或资源。

## 奖励与验收门槛

SG01–SG08 对应 L02/L05/L08/L11/L14/L17/L20/L23，每组分别解锁三个职业 SK05–SK12。探索节点可达、清场与距离/视线校验沿现有规则。L11 技能档案与原金币装备奖励独立记账。

UI、战斗、保存、装备及美术分别达到就绪后，才确认正式集成完成。用户最新要求优先：完整新美术仍在整理时，已授权通过新版 UI/Main 先行复查三十六技能、普通怪交互和职业操作节奏；此时明确使用旧完整位图动作回退，不把先行功能复查作为新美术验收。检查必须使用隔离档，真实图形与自然玩法记录单独标注。通过模块检查不能标记整体完成。

## 2K 显示与资源门槛

用户目标屏幕为 2560×1440。1280×720 继续作为逻辑布局基准，通过 `canvas_items` 在目标窗口渲染，不能先把整幅 720p 画面放大成测试截图。HUD 原位置不移动；正文最低 18 个逻辑像素，在真实 2K 窗口核对字体、技能图标、按钮和角色轮廓。

资源检查按最终显示尺寸与每帧有效主体像素进行。战斗身体为 112 世界像素，2K 画面约占 224 屏幕像素；手绘源帧主体目标高度至少约 448 像素，武器完整保留。禁止把 64 个角色塞进一张低分辨率图集，再仅凭整图大小声称达到 2K。动作按方向或少帧拆分，图集不超过 2048×2048，实际帧区域、脚点和释放锚点逐项记录。

角色页立绘按真实控件显示尺寸核对；来源记录保留工具返回的实际宽高，不把放大导出标成原生高分辨率。技能图标沿现有原创矢量图标体系，可以按显示尺寸渲染；身体插画必须使用手绘位图，程序矢量人物只能作为隔离技术样板。2K 的 UI 图形检查与完整新美术验收分别记录。
