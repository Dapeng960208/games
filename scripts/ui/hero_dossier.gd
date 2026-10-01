extends RefCounted
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Sheet = preload("res://scripts/ui/stat_sheet.gd")

static func render(panel: Control) -> void:
	var left := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(270,510))
	MineStyle.literal(left,Inspect.t("选择英雄 · 预览职业配装","HEROES · SAVED LOADOUT"),Vector2(16,13),Vector2(238,28),15,MineStyle.AMBER)
	var index := 0
	for id: String in ContentRegistry.heroes():
		var hero: Dictionary = ContentRegistry.hero(id)
		var button := MineStyle.button(left,"",Vector2(12,51+index*105),Vector2(246,96),func(): panel.preview_hero = id; panel._render())
		button.name = "Preview_"+id
		MineStyle.button_skin(button,"card")
		if id == panel.preview_hero: MineStyle.selected(button,"card")
		MineStyle.hero_portrait(button,id,Vector2(7,4),Vector2(66,82))
		MineStyle.literal(button,MineStyle.content_text(hero,"name"),Vector2(82,12),Vector2(151,30),20)
		MineStyle.literal(button,MineStyle.content_text(hero,"class_name")+" · Lv."+str(Game.hero_level(id)),Vector2(82,48),Vector2(151,33),14,MineStyle.CYAN)
		index += 1
	var preset_note := Inspect.t("各职业记住上次配装，仍共用同一库存。确认后切换出战英雄。", "Each hero remembers its loadout; all heroes share one collection. Confirm to switch.")
	if panel.preview_hero == str(Game.profile.selected_hero) and not Game.last_loadout_missing.is_empty():
		var slots: PackedStringArray = []
		for slot: String in Game.last_loadout_missing: slots.append(Words.text("SLOT_"+slot.to_upper()))
		preset_note = Inspect.t("缺失预设已使用当前装备：%s", "Missing preset slots use current gear: %s") % ", ".join(slots)
	MineStyle.literal(left,preset_note,Vector2(16,378),Vector2(238,58),14,MineStyle.MUTED)
	panel.action_button = MineStyle.button(left,"HERO_SELECTED" if panel.preview_hero == Game.profile.selected_hero else "SELECT_HERO",Vector2(14,447),Vector2(242,48),panel._select_hero)
	panel.action_button.name = "PrimaryAction"
	panel.action_button.disabled = panel.preview_hero == Game.profile.selected_hero
	var hero: Dictionary = ContentRegistry.hero(panel.preview_hero)
	var right := MineStyle.panel(panel.body,Vector2(286,0),Vector2(930,510))
	MineStyle.hero_portrait(right,panel.preview_hero,Vector2(18,15),Vector2(163,187))
	MineStyle.literal(right,MineStyle.content_text(hero,"name"),Vector2(20,210),Vector2(170,35),22)
	MineStyle.literal(right,"Lv."+str(Game.hero_level(panel.preview_hero)),Vector2(20,252),Vector2(170,25),17,MineStyle.AMBER)
	MineStyle.literal(right,MineStyle.content_text(hero,"class_name"),Vector2(20,285),Vector2(170,32),17,MineStyle.CYAN)
	var explanation := ScrollContainer.new()
	explanation.position = Vector2(20,324)
	explanation.size = Vector2(174,167)
	explanation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(explanation)
	var play := MineStyle.label(explanation,"HERO_"+panel.preview_hero+"_PLAY",Vector2.ZERO,Vector2(153,0),14,MineStyle.MUTED)
	play.custom_minimum_size.x = 153
	MineStyle.literal(right,Inspect.t("角色属性 · 配装后的真实总值","CHARACTER STATS · RESOLVED LOADOUT"),Vector2(210,13),Vector2(700,33),22,MineStyle.AMBER)
	var scroll := ScrollContainer.new()
	scroll.name = "HeroStatScroll"
	scroll.position = Vector2(210,54)
	scroll.size = Vector2(700,439)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(scroll)
	var sheet := Sheet.new()
	scroll.add_child(sheet)
	sheet.configure(Inspect.breakdown(panel.preview_hero,Game.hero_level(panel.preview_hero),Game.hero_loadout(panel.preview_hero),Game.profile.equipment,null,int(Game.profile.get("ruleset_version",1)),Game.hero_talents(panel.preview_hero)),678)
