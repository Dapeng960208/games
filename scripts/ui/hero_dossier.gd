extends RefCounted
## Camp dossier and skill ledger share one illustrated, source-backed inspector.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Sheet = preload("res://scripts/ui/stat_sheet.gd")
const SkillInspect = preload("res://scripts/ui/skill_inspection.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const SKILLS := ["q","secondary","f","ultimate"]
const ACTIONS := ["skill_q","skill_secondary","skill_f","skill_ultimate"]

static func render(panel: Control) -> void:
	var id: String = panel.preview_hero
	var hero: Dictionary = ContentRegistry.hero(id)
	var level := Game.hero_level(id)
	var report := Inspect.breakdown(id,level,Game.hero_loadout(id),Game.profile.equipment,null,int(Game.profile.get("ruleset_version",1)),Game.hero_talents(id))
	var identity := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(210,510))
	MineStyle.literal(identity,Inspect.t("英雄名册","HERO ROSTER"),Vector2(16,14),Vector2(178,25),15,MineStyle.CYAN)
	for index: int in ContentRegistry.heroes().size():
		var hero_id: String = ContentRegistry.heroes()[index]
		var definition := ContentRegistry.hero(hero_id)
		var choice := MineStyle.button(identity,"",Vector2(12,57+index*109),Vector2(186,97),func(): panel.preview_hero = hero_id; panel._render())
		choice.name = "Preview_"+hero_id
		MineStyle.button_skin(choice,"card")
		if hero_id == id: MineStyle.selected(choice,"card")
		MineStyle.hero_portrait(choice,hero_id,Vector2(5,9),Vector2(67,78))
		MineStyle.literal(choice,MineStyle.content_text(definition,"name"),Vector2(80,12),Vector2(96,28),19)
		MineStyle.literal(choice,MineStyle.content_text(definition,"class_name"),Vector2(80,44),Vector2(96,22),13,MineStyle.CYAN)
		MineStyle.literal(choice,"Lv."+str(Game.hero_level(hero_id)),Vector2(80,69),Vector2(96,20),13,MineStyle.MUTED)
		choice.tooltip_text = MineStyle.content_text(definition,"name")
	var note := Inspect.t("各职业保留上次配装，共用库存","Heroes keep their loadouts and share gear")
	if id == str(Game.profile.selected_hero) and not Game.last_loadout_missing.is_empty():
		note = Inspect.t("缺失预设已使用当前装备","Missing preset slots use current gear")
	MineStyle.literal(identity,note,Vector2(16,397),Vector2(178,39),13,MineStyle.MUTED)
	panel.action_button = MineStyle.button(identity,"HERO_SELECTED" if id == Game.profile.selected_hero else "SELECT_HERO",Vector2(12,451),Vector2(186,43),panel._select_hero)
	panel.action_button.name = "PrimaryAction"
	panel.action_button.disabled = id == Game.profile.selected_hero
	MineStyle.primary(panel.action_button)
	MineStyle.hero_portrait(panel.body,id,Vector2(219,5),Vector2(294,382))
	var caption := MineStyle.panel(panel.body,Vector2(226,395),Vector2(292,115))
	MineStyle.literal(caption,MineStyle.content_text(hero,"name"),Vector2(16,10),Vector2(260,36),27)
	MineStyle.literal(caption,MineStyle.content_text(hero,"class_name")+" · Lv."+str(level),Vector2(16,54),Vector2(260,26),17,MineStyle.CYAN)
	var play := MineStyle.label(caption,"HERO_"+id+"_PLAY",Vector2(16,85),Vector2(260,20),12,MineStyle.MUTED)
	play.tooltip_text = play.text
	play.text = play.text.replace("\n"," · ")
	play.autowrap_mode = TextServer.AUTOWRAP_OFF
	play.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	play.clip_text = true
	var right := MineStyle.panel(panel.body,Vector2(534,0),Vector2(682,510))
	MineStyle.literal(right,Inspect.t("角色属性","Character attributes"),Vector2(20,15),Vector2(640,33),24)
	MineStyle.literal(right,Inspect.t("当前职业配装 · 完整数值来源","Saved loadout · complete stat sources"),Vector2(20,54),Vector2(640,25),14,MineStyle.MUTED)
	var stats: Dictionary = report.total
	for index: int in 4:
		var key: String = ["max_hp","attack","armor","magic_resist"][index]
		metric(right,Inspect.caption(key),Inspect.value(key,float(stats.get(key,0)),false,false,int(stats.get("ruleset_version",1))),Vector2(20+index*161,92),Vector2(151,64))
	var scroll := ScrollContainer.new()
	scroll.name = "HeroStatScroll"
	scroll.position = Vector2(20,179)
	scroll.size = Vector2(642,311)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(scroll)
	var sheet := Sheet.new()
	scroll.add_child(sheet)
	sheet.configure(report,618)

static func render_skills(panel: Control) -> void:
	var id: String = str(Game.profile.get("selected_hero","CH01"))
	var hero: Dictionary = ContentRegistry.hero(id)
	var level := Game.hero_level(id)
	var stats: Dictionary = Game.selected_stats()
	var selected: String = str(panel.get_meta("dossier_skill","q"))
	if selected not in SKILLS: selected = "q"
	var dossier := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(250,510))
	MineStyle.literal(dossier,Inspect.t("职业成长","HERO PROGRESSION"),Vector2(18,14),Vector2(214,25),15,MineStyle.CYAN)
	MineStyle.hero_portrait(dossier,id,Vector2(30,48),Vector2(190,200))
	MineStyle.literal(dossier,MineStyle.content_text(hero,"name"),Vector2(18,255),Vector2(214,36),25)
	MineStyle.literal(dossier,MineStyle.content_text(hero,"class_name")+" · Lv."+str(level),Vector2(18,299),Vector2(214,28),16,MineStyle.CYAN)
	var xp: int = int(Game.profile.get("hero_xp",{}).get(id,0))
	MineStyle.label(dossier,"HERO_XP_MAX" if level >= 20 else "HERO_XP",Vector2(18,337),Vector2(214,48),14,MineStyle.MUTED,{"xp":xp,"next":ContentRegistry.next_level_xp(level,int(stats.get("ruleset_version",1)))})
	var passive := MineStyle.button(dossier,"PASSIVE_DASH",Vector2(18,403),Vector2(214,42),func(): panel._show_core_actions(hero))
	passive.name = "OpenCoreActions"
	passive.add_theme_font_size_override("font_size",15)
	var branches := MineStyle.button(dossier,"SKILL_BRANCHES",Vector2(18,456),Vector2(214,38),panel._show_branches)
	branches.name = "OpenBranches"
	branches.add_theme_font_size_override("font_size",15)
	var rail := MineStyle.panel(panel.body,Vector2(266,0),Vector2(286,510))
	MineStyle.literal(rail,Inspect.t("主动技能","ACTIVE SKILLS"),Vector2(18,14),Vector2(250,29),17,MineStyle.CYAN)
	for index: int in SKILLS.size():
		var slot: String = SKILLS[index]
		var skill: Dictionary = hero.get("skills",{}).get(slot,{})
		var unlocked := level >= int(skill.get("unlock",index+1))
		var action := MineStyle.button(rail,"",Vector2(12,58+index*96),Vector2(262,86),func(): panel.set_meta("dossier_skill",slot); panel._render())
		action.name = "InspectSkill_"+slot
		MineStyle.button_skin(action,"card")
		if selected == slot: MineStyle.selected(action,"card")
		skill_icon(action,id,slot,Vector2(10,10),Vector2(60,60))
		var binding := ControlBindings.label_for(ACTIONS[index],Game.profile.get("settings",{}).get("controls",{}),Words.locale)
		MineStyle.literal(action,binding,Vector2(79,8),Vector2(168,24),14,MineStyle.CYAN if unlocked else MineStyle.MUTED)
		MineStyle.literal(action,MineStyle.content_text(skill,"name"),Vector2(79,35),Vector2(168,43),17)
		action.tooltip_text = MineStyle.content_text(skill,"name")+" · Lv."+str(int(skill.get("unlock",index+1)))
	MineStyle.literal(rail,Inspect.t("选择技能查看效果与成长","Select a skill for effects and upgrades"),Vector2(18,454),Vector2(250,42),13,MineStyle.MUTED)
	var detail := MineStyle.panel(panel.body,Vector2(568,0),Vector2(648,510))
	var entry := SkillInspect.ledger_entry(id,level,stats,selected,Game.hero_branches(id))
	detail.set_meta("skill_entry",entry)
	skill_icon(detail,id,selected,Vector2(22,19),Vector2(86,86))
	MineStyle.literal(detail,str(entry.title),Vector2(124,23),Vector2(494,39),26)
	MineStyle.literal(detail,Inspect.t("已解锁 · 等级 %d","Unlocked · Level %d") % int(entry.unlock) if bool(entry.unlocked) else Inspect.t("等级 %d 解锁","Unlocks at level %d") % int(entry.unlock),Vector2(124,70),Vector2(494,27),16,MineStyle.CYAN if bool(entry.unlocked) else MineStyle.MUTED)
	metric(detail,MineStyle.content_text(hero,"resource_name"),str(entry.spec.get("cost",0)),Vector2(22,124),Vector2(192,62))
	metric(detail,Inspect.t("冷却时间","Cooldown"),"%.1f s" % float(entry.spec.get("cooldown",0)),Vector2(225,124),Vector2(192,62))
	metric(detail,Inspect.t("解锁等级","Unlock level"),"Lv."+str(entry.unlock),Vector2(428,124),Vector2(198,62))
	var scroll := ScrollContainer.new()
	scroll.name = "SkillDescriptionScroll"
	scroll.position = Vector2(22,207)
	scroll.size = Vector2(604,222)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	detail.add_child(scroll)
	var explanation := MineStyle.literal(scroll,str(entry.description),Vector2.ZERO,Vector2(580,0),16)
	explanation.name = "InspectedSkillDescription"
	explanation.custom_minimum_size.x = 580
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MineStyle.literal(detail,Inspect.t("成长里程碑","GROWTH MILESTONES"),Vector2(22,439),Vector2(604,24),13,MineStyle.MUTED)
	for index: int in 10:
		var gate: int = [1,2,3,4,10,12,14,16,18,20][index]
		var mark := MineStyle.literal(detail,str(gate),Vector2(22+index*60,470),Vector2(52,24),17,MineStyle.CYAN if level >= gate else MineStyle.MUTED)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func skill_icon(parent: Node, hero: String, slot: String, at: Vector2, extent: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Sampler.sampled("res://assets/generated/skills/"+hero+"_"+slot+"_v1.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = at
	icon.size = extent
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

static func metric(parent: Node, caption: String, value: String, at: Vector2, extent: Vector2) -> void:
	var card := Panel.new()
	card.position = at
	card.size = extent
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel",MineStyle.box(Color("f3f0e7"),Color("e4ddca"),1))
	parent.add_child(card)
	MineStyle.literal(card,caption,Vector2(12,7),Vector2(extent.x-24,22),13,MineStyle.MUTED)
	MineStyle.literal(card,value,Vector2(12,30),Vector2(extent.x-24,28),22,MineStyle.CYAN)
