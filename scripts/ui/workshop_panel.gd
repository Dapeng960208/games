extends Control
## Original mineral-workshop dossier UI. All actions commit through Game.
## Hero/equipment artwork prefers the game's original ImageGen PNGs.

const SLOTS := ["weapon","head","chest","hands","feet","charm"]
const SKILLS := ["q","secondary","f","ultimate"]
const KEYS := ["Q","RMB","F","R"]
var app: Node
var mode := "heroes"
var preview_hero := ""
var selected_item := ""
var slot_filter := "all"
var set_filter := "all"
var list_scroll := 0
var busy := false
var body: Control
var item_list: ScrollContainer
var action_button: Button

func _ready() -> void:
	preview_hero = str(Game.profile.get("selected_hero","CH01"))
	_render()

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	MineStyle.label(self,"WORKSHOP_KICKER",Vector2(32,21),Vector2(750,25),16,MineStyle.AMBER)
	MineStyle.label(self,{"heroes":"HERO_DOSSIERS","skills":"SKILL_LEDGER","inventory":"EQUIPMENT_BENCH","shop":"SUPPLY_CATALOG","upgrade":"UPGRADE_BENCH"}.get(mode,"EQUIPMENT_BENCH"),Vector2(32,55),Vector2(820,46),32)
	MineStyle.label(self,"BANK_TOTAL",Vector2(928,41),Vector2(322,46),22,MineStyle.AMBER,{"gold":Game.profile.get("permanent_gold",0)})
	var tabs := [["heroes","TAB_HEROES"],["skills","TAB_SKILLS"],["inventory","TAB_GEAR"],["shop","TAB_SHOP"],["upgrade","TAB_UPGRADE"]]
	for i in range(tabs.size()):
		var data: Array = tabs[i]
		var tab := MineStyle.button(self,data[1],Vector2(32+i*198,112),Vector2(182,44),func(): _switch_page(data[0]))
		tab.name = "Tab_"+data[0]
		if mode == data[0]:
			tab.add_theme_stylebox_override("normal",MineStyle.box(Color("3a3023"),MineStyle.AMBER,2))
	MineStyle.button(self,"RETURN_CAMP",Vector2(1030,112),Vector2(218,44),app.show_camp).name = "ReturnCamp"
	body = Control.new()
	body.position = Vector2(32,178)
	body.size = Vector2(1216,510)
	add_child(body)
	if mode == "heroes":
		_render_heroes()
	elif mode == "skills":
		_render_skills()
	else:
		_render_equipment()
	var focus := find_child("PrimaryAction",true,false) as Button
	if focus != null and not focus.disabled:
		focus.grab_focus()
	else:
		var back := find_child("ReturnCamp",true,false) as Button
		if back != null:
			back.grab_focus()

func _switch_page(next_mode: String) -> void:
	mode = next_mode
	app.route = "workshop_"+mode
	selected_item = ""
	list_scroll = 0
	_render()

func _render_heroes() -> void:
	var heroes: Array = ContentRegistry.heroes()
	for i in range(heroes.size()):
		var id := str(heroes[i])
		var data: Dictionary = ContentRegistry.hero(id)
		var card := MineStyle.panel(body,Vector2(i*244,0),Vector2(228,510))
		if id == preview_hero:
			card.add_theme_stylebox_override("panel",MineStyle.box(MineStyle.RAISED,MineStyle.AMBER,2))
		MineStyle.literal(card,"0"+str(i+1)+" / "+MineStyle.content_text(data,"class_name"),Vector2(17,12),Vector2(194,30),17,MineStyle.resource_color(data.get("resource_type","rage")))
		MineStyle.hero_portrait(card,id,Vector2(4,49),Vector2(220,238))
		MineStyle.literal(card,MineStyle.content_text(data,"name"),Vector2(18,300),Vector2(193,36),25)
		MineStyle.literal(card,MineStyle.content_text(data,"title"),Vector2(18,341),Vector2(193,33),17,MineStyle.MUTED)
		MineStyle.label(card,"HERO_LEVEL",Vector2(18,382),Vector2(193,32),18,MineStyle.AMBER,{"level":Game.hero_level(id)})
		var select := MineStyle.button(card,"INSPECT",Vector2(16,439),Vector2(196,48),func(): preview_hero = id; _render())
		select.name = "Preview_"+id
	var hero: Dictionary = ContentRegistry.hero(preview_hero)
	var info := MineStyle.panel(body,Vector2(742,0),Vector2(474,510))
	MineStyle.label(info,"DOSSIER_NOTE",Vector2(22,15),Vector2(428,25),16,MineStyle.MUTED)
	MineStyle.literal(info,MineStyle.content_text(hero,"name")+" / "+MineStyle.content_text(hero,"class_name"),Vector2(22,55),Vector2(428,66),25)
	MineStyle.label(info,"HERO_"+preview_hero+"_PLAY",Vector2(22,132),Vector2(428,114),19)
	MineStyle.label(info,"RESOURCE_"+str(hero.get("resource_type","rage")).to_upper()+"_RULE",Vector2(22,257),Vector2(428,102),18,MineStyle.resource_color(hero.get("resource_type","rage")))
	MineStyle.label(info,"HERO_SWITCH_NOTE",Vector2(22,367),Vector2(428,60),16,MineStyle.MUTED)
	action_button = MineStyle.button(info,"HERO_SELECTED" if preview_hero == Game.profile.get("selected_hero","") else "SELECT_HERO",Vector2(22,439),Vector2(428,48),_select_hero)
	action_button.name = "PrimaryAction"
	action_button.disabled = preview_hero == Game.profile.get("selected_hero","")

func _select_hero() -> void:
	if busy:
		return
	busy = true
	if Game.select_hero(preview_hero):
		busy = false
		_render()
	else:
		busy = false
		app._show_save_error()

func _render_skills() -> void:
	var id: String = Game.profile.get("selected_hero","CH01")
	var hero: Dictionary = ContentRegistry.hero(id)
	var level: int = Game.hero_level(id)
	var stats: Dictionary = Game.selected_stats()
	var dossier := MineStyle.panel(body,Vector2.ZERO,Vector2(290,510))
	MineStyle.hero_portrait(dossier,id,Vector2(37,14),Vector2(216,204))
	MineStyle.literal(dossier,MineStyle.content_text(hero,"name"),Vector2(20,220),Vector2(250,34),26)
	MineStyle.label(dossier,"HERO_LEVEL",Vector2(20,259),Vector2(250,29),18,MineStyle.AMBER,{"level":level})
	var xp: int = int(Game.profile.get("hero_xp",{}).get(id,0))
	MineStyle.label(dossier,"HERO_XP_MAX" if level >= 20 else "HERO_XP",Vector2(20,294),Vector2(250,31),17,MineStyle.MUTED,{"xp":xp,"next":ContentRegistry.next_level_xp(level)})
	MineStyle.label(dossier,"DOSSIER_STATS",Vector2(20,339),Vector2(252,61),17,MineStyle.INK,{"hp":int(stats.get("max_hp",100)),"damage":"%.1f" % float(stats.get("attack",20)),"armor":int(stats.get("armor",0))})
	MineStyle.button(dossier,"PASSIVE_DASH",Vector2(18,416),Vector2(254,48),func(): _show_core_actions(hero))
	MineStyle.label(dossier,"CORE_ACTIONS_UNLOCK",Vector2(20,471),Vector2(252,29),16,MineStyle.MUTED)
	for i in range(SKILLS.size()):
		var skill: Dictionary = hero.get("skills",{}).get(SKILLS[i],{})
		skill = skill.duplicate(true)
		skill.merge(HeroAbilities.preview_spec(id,level,stats,SKILLS[i]),true)
		var description_text := MineStyle.content_text(skill,"description")
		for upgrade: Dictionary in hero.get("upgrades",[]):
			if upgrade.get("skill","") == SKILLS[i] and level >= int(upgrade.get("level",99)):
				description_text = Words.text("SKILL_UPGRADE_ACTIVE",{"level":upgrade.get("level",0)})+"\n"+MineStyle.content_text(upgrade,"description")+"\n\n"+Words.text("BASE_SKILL")+"\n"+description_text
		var branches: Dictionary = Game.hero_branches(id)
		var choice: String = str(branches.get(SKILLS[i],""))
		if not choice.is_empty():
			var branch_level := "18" if SKILLS[i] == "q" else "20"
			var branch: Dictionary = hero.get("branches",{}).get(branch_level,{}).get(choice,{})
			description_text = Words.text("BRANCH_ACTIVE",{"choice":choice})+" · "+MineStyle.content_text(branch,"name")+"\n"+MineStyle.content_text(branch,"description")+"\n\n"+Words.text("BASE_SKILL")+"\n"+description_text
		var unlocked := level >= int(skill.get("unlock",[2,4,6,8][i]))
		var panel := MineStyle.panel(body,Vector2(310,(i/2)*182),Vector2(442,164))
		panel.position.x += (i%2)*464
		MineStyle.literal(panel,Words.text("KEY_SECONDARY") if i == 1 else KEYS[i],Vector2(18,13),Vector2(68,31),22,MineStyle.AMBER if unlocked else MineStyle.MUTED)
		MineStyle.literal(panel,MineStyle.content_text(skill,"name"),Vector2(91,13),Vector2(333,35),21)
		MineStyle.label(panel,"SKILL_READY" if unlocked else "SKILL_LOCKED",Vector2(18,52),Vector2(406,27),16,MineStyle.GREEN if unlocked else MineStyle.MUTED,{"level":skill.get("unlock",[2,4,6,8][i]),"cost":skill.get("cost",0),"cooldown":"%.1f" % float(skill.get("cooldown",0))})
		var explanation := ScrollContainer.new()
		explanation.position = Vector2(18,86)
		explanation.size = Vector2(406,65)
		explanation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(explanation)
		var description := MineStyle.literal(explanation,description_text,Vector2.ZERO,Vector2(381,0),16,MineStyle.MUTED)
		description.custom_minimum_size.x = 381
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rail := MineStyle.panel(body,Vector2(310,382),Vector2(906,128))
	MineStyle.label(rail,"UNLOCK_TRACK",Vector2(18,10),Vector2(650,27),17,MineStyle.AMBER)
	MineStyle.button(rail,"SKILL_BRANCHES",Vector2(670,8),Vector2(218,44),_show_branches).name = "OpenBranches"
	for i in range(10):
		var gate: int = [2,4,6,8,10,12,14,16,18,20][i]
		var mark := MineStyle.label(rail,str(gate),Vector2(18+i*86,60),Vector2(70,27),20,MineStyle.GREEN if level >= gate else MineStyle.MUTED)
		mark.text = str(gate)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MineStyle.label(rail,"UNLOCK_LEGEND",Vector2(18,100),Vector2(870,27),16,MineStyle.MUTED)

func _show_branches() -> void:
	var id: String = Game.profile.get("selected_hero","CH01")
	var hero: Dictionary = ContentRegistry.hero(id)
	var level: int = Game.hero_level(id)
	var selected: Dictionary = Game.hero_branches(id)
	var panel: Panel = app._push_modal("SKILL_BRANCHES",Vector2(1100,626))
	for column in range(2):
		var slot: String = "q" if column == 0 else "ultimate"
		var gate: int = 18 if column == 0 else 20
		var offset := Vector2(28+column*534,82)
		var group: Dictionary = hero.get("branches",{}).get(str(gate),{})
		var current := str(selected.get(slot,""))
		MineStyle.literal(panel,("Q" if column == 0 else "R")+" / "+Words.text("BRANCH_GATE",{"level":gate}),offset,Vector2(510,32),20,MineStyle.AMBER if level >= gate else MineStyle.MUTED)
		for i in range(2):
			var choice: String = ["A","B"][i]
			var data: Dictionary = group.get(choice,{})
			var at := offset+Vector2(0,45+i*166)
			var button := MineStyle.button(panel,"",at,Vector2(510,47),func(): _choose_branch(slot,choice))
			button.name = "Branch_"+slot+"_"+choice
			button.text = ("● " if current == choice else choice+" / ")+MineStyle.content_text(data,"name")
			button.disabled = level < gate or current == choice
			var scroll := ScrollContainer.new()
			scroll.position = at+Vector2(10,55)
			scroll.size = Vector2(490,99)
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			panel.add_child(scroll)
			var explanation := MineStyle.literal(scroll,MineStyle.content_text(data,"description"),Vector2.ZERO,Vector2(464,0),18,MineStyle.MUTED)
			explanation.custom_minimum_size.x = 464
			explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var original := MineStyle.button(panel,"BRANCH_ORIGINAL",offset+Vector2(0,381),Vector2(510,46),func(): _choose_branch(slot,""))
		original.name = "Branch_"+slot+"_original"
		original.disabled = current.is_empty() or level < gate
		if current.is_empty():
			original.text = "● "+Words.text("BRANCH_ORIGINAL")
	MineStyle.label(panel,"BRANCH_RULE",Vector2(28,529),Vector2(768,72),17,MineStyle.MUTED)
	MineStyle.button(panel,"BACK",Vector2(832,545),Vector2(240,51),app._pop_modal).grab_focus()

func _choose_branch(slot: String, choice: String) -> void:
	if Game.set_hero_branch(slot,choice):
		app._pop_modal()
		_render()
		_show_branches()
	else:
		if not Game.last_error.is_empty():
			app._show_save_error()

func _show_core_actions(hero: Dictionary) -> void:
	var panel: Panel = app._push_modal("PASSIVE_DASH",Vector2(742,492))
	var passive: Dictionary = hero.get("passive",{})
	var dash: Dictionary = hero.get("dash",{})
	MineStyle.literal(panel,MineStyle.content_text(passive,"name"),Vector2(28,80),Vector2(686,38),23,MineStyle.CYAN)
	MineStyle.literal(panel,MineStyle.content_text(passive,"description"),Vector2(28,122),Vector2(686,151),18)
	MineStyle.literal(panel,Words.text("DASH_LABEL")+" / "+MineStyle.content_text(dash,"name"),Vector2(28,283),Vector2(686,36),22,MineStyle.AMBER)
	MineStyle.label(panel,"DASH_DETAILS",Vector2(28,326),Vector2(686,70),18,MineStyle.MUTED,{"distance":dash.get("distance",0),"cooldown":dash.get("cooldown",0)})
	MineStyle.button(panel,"BACK",Vector2(488,414),Vector2(226,50),app._pop_modal).grab_focus()

func _render_equipment() -> void:
	var left := MineStyle.panel(body,Vector2.ZERO,Vector2(250,510))
	MineStyle.label(left,"FITTED_LOADOUT",Vector2(16,13),Vector2(218,27),18,MineStyle.AMBER)
	for i in range(SLOTS.size()):
		var slot: String = SLOTS[i]
		var equipped: String = str(Game.profile.get("loadout",{}).get(slot,""))
		var item: Dictionary = ContentRegistry.equipment(equipped) if not equipped.is_empty() else {}
		var slot_button := MineStyle.button(left,"",Vector2(12,52+i*55),Vector2(226,48),func(): slot_filter = slot; selected_item = equipped; list_scroll = 0; _render())
		slot_button.name = "Slot_"+slot
		slot_button.text = ""
		MineStyle.equipment_icon(slot_button,item if not item.is_empty() else {"slot":slot},Vector2(4,2),Vector2(44,44))
		var full_name := Words.text("SLOT_"+slot.to_upper())+" · "+(MineStyle.content_text(item,"name") if not item.is_empty() else Words.text("EMPTY_SLOT"))
		var fitted := MineStyle.literal(slot_button,full_name,Vector2(51,5),Vector2(167,39),16)
		fitted.autowrap_mode = TextServer.AUTOWRAP_OFF
		fitted.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fitted.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_button.tooltip_text = full_name
	var stats: Dictionary = Game.selected_stats()
	MineStyle.label(left,"DOSSIER_STATS",Vector2(16,397),Vector2(218,67),16,MineStyle.MUTED,{"hp":int(stats.get("max_hp",100)),"damage":"%.1f" % float(stats.get("attack",20)),"armor":int(stats.get("armor",0))})
	MineStyle.label(left,"SHARED_GEAR",Vector2(16,472),Vector2(218,27),16,MineStyle.CYAN)
	var middle := MineStyle.panel(body,Vector2(268,0),Vector2(442,510))
	MineStyle.label(middle,"CATALOG_LABEL",Vector2(16,10),Vector2(406,26),17,MineStyle.MUTED)
	var filter_button := MineStyle.button(middle,"",Vector2(14,48),Vector2(202,44),_cycle_slot)
	filter_button.text = Words.text("FILTER_SLOT")+": "+Words.text("ALL" if slot_filter == "all" else "SLOT_"+slot_filter.to_upper())
	filter_button.add_theme_font_size_override("font_size",16)
	var sets_button := MineStyle.button(middle,"",Vector2(228,48),Vector2(200,44),_cycle_set)
	sets_button.text = Words.text("FILTER_SET")+": "+(Words.text("ALL") if set_filter == "all" else set_filter)
	sets_button.add_theme_font_size_override("font_size",16)
	item_list = ScrollContainer.new()
	item_list.position = Vector2(14,108)
	item_list.size = Vector2(414,384)
	item_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(item_list)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation",8)
	item_list.add_child(stack)
	var ids := _filtered_equipment()
	if selected_item.is_empty() or not ids.has(selected_item):
		selected_item = str(ids[0]) if not ids.is_empty() else ""
	for value in ids:
		var id := str(value)
		var data: Dictionary = ContentRegistry.equipment(id)
		var row := MineStyle.button(stack,"",Vector2.ZERO,Vector2(392,74),func(): list_scroll = item_list.scroll_vertical; selected_item = id; _render())
		row.name = "Item_"+id
		row.custom_minimum_size = Vector2(392,74)
		if id == selected_item:
			row.add_theme_stylebox_override("normal",MineStyle.box(MineStyle.RAISED,MineStyle.AMBER))
		MineStyle.equipment_icon(row,data,Vector2(12,8),Vector2(56,56))
		MineStyle.literal(row,MineStyle.content_text(data,"name"),Vector2(82,9),Vector2(286,29),18)
		var owned: bool = Game.profile.get("equipment",{}).has(id)
		var state := Words.text("OWNED")+" +"+str(_item_level(id)) if owned else Words.text("PRICE_GOLD",{"gold":data.get("price",0)})
		MineStyle.literal(row,state,Vector2(82,41),Vector2(286,24),16,MineStyle.MUTED)
	item_list.set_deferred("scroll_vertical",list_scroll)
	if ids.is_empty():
		MineStyle.label(stack,"NO_EQUIPMENT",Vector2.ZERO,Vector2(392,90),18,MineStyle.MUTED)
	_render_equipment_detail()

func _filtered_equipment() -> Array:
	var output: Array = []
	for value in ContentRegistry.equipment_ids():
		var id := str(value)
		var data: Dictionary = ContentRegistry.equipment(id)
		if mode != "shop" and not Game.profile.get("equipment",{}).has(id):
			continue
		if slot_filter != "all" and data.get("slot","") != slot_filter:
			continue
		if set_filter != "all" and str(data.get("set_id","")) != set_filter:
			continue
		output.append(id)
	return output

func _cycle_slot() -> void:
	var all_slots: Array = ["all"]+SLOTS
	slot_filter = all_slots[(all_slots.find(slot_filter)+1)%all_slots.size()]
	list_scroll = 0
	_render()

func _cycle_set() -> void:
	var ids: Array = ["all"]
	for value in ContentRegistry.equipment_ids():
		var id := str(ContentRegistry.equipment(str(value)).get("set_id",""))
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	set_filter = ids[(ids.find(set_filter)+1)%ids.size()]
	list_scroll = 0
	_render()

func _item_level(id: String) -> int:
	var item: Variant = Game.profile.get("equipment",{}).get(id,{})
	return int(item.get("level",0)) if item is Dictionary else int(item)

func _render_equipment_detail() -> void:
	var detail := MineStyle.panel(body,Vector2(728,0),Vector2(488,510))
	if selected_item.is_empty():
		MineStyle.label(detail,"NO_EQUIPMENT",Vector2(24,65),Vector2(440,140),21,MineStyle.MUTED)
		return
	var data: Dictionary = ContentRegistry.equipment(selected_item)
	var owned: bool = Game.profile.get("equipment",{}).has(selected_item)
	var equipped := str(Game.profile.get("loadout",{}).get(data.get("slot",""),"")) == selected_item
	MineStyle.equipment_icon(detail,data,Vector2(18,16),Vector2(78,78))
	MineStyle.literal(detail,MineStyle.content_text(data,"name"),Vector2(112,20),Vector2(348,44),22)
	MineStyle.literal(detail,Words.text("SLOT_"+str(data.get("slot","")).to_upper())+" / "+str(data.get("set_id",""))+" / +"+str(_item_level(selected_item)),Vector2(112,65),Vector2(348,27),16,MineStyle.AMBER)
	var text_area := ScrollContainer.new()
	text_area.position = Vector2(22,109)
	text_area.size = Vector2(444,267)
	text_area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(text_area)
	var text: String = Words.text("BASE_STATS")+"\n"+_format_stats(data.get("base_stats",{}))
	var current_id := str(Game.profile.get("loadout",{}).get(data.get("slot",""),""))
	if not current_id.is_empty() and current_id != selected_item:
		var current: Dictionary = ContentRegistry.equipment(current_id)
		text += "\n\n"+Words.text("CURRENT_ITEM")+" · "+MineStyle.content_text(current,"name")+"\n"+_format_stats(current.get("base_stats",{}))
	if current_id != selected_item:
		var before: Dictionary = Game.selected_stats()
		var after: Dictionary = Game.preview_stats(selected_item)
		var changes: PackedStringArray = []
		for key in ["max_hp","attack","armor","attack_interval","move_speed","crit_chance","cooldown_reduction","damage_bonus","damage_reduction","burn_damage","corrosion_damage_bonus","status_duration"]:
			if not is_equal_approx(float(before.get(key,0)),float(after.get(key,0))):
				changes.append(Words.text("STAT_"+key.to_upper())+"  "+_stat_value(key,before.get(key,0))+" → "+_stat_value(key,after.get(key,0)))
		if not changes.is_empty():
			text += "\n\n"+Words.text("PREVIEW_CHANGES")+"\n"+"\n".join(changes)
	if mode == "upgrade" and owned and _item_level(selected_item) < 5:
		var before: Dictionary = Game.preview_stats(selected_item)
		var after: Dictionary = Game.preview_upgrade_stats(selected_item)
		var gains: PackedStringArray = []
		for key in ["max_hp","attack","armor","attack_interval","move_speed","crit_chance","cooldown_reduction","damage_bonus","damage_reduction","burn_damage","corrosion_damage_bonus","status_duration"]:
			if not is_equal_approx(float(before.get(key,0)),float(after.get(key,0))):
				gains.append(Words.text("STAT_"+key.to_upper())+"  "+_stat_value(key,before.get(key,0))+" → "+_stat_value(key,after.get(key,0)))
		text += "\n\n"+Words.text("PREVIEW_UPGRADE")+"\n"+("\n".join(gains) if not gains.is_empty() else Words.text("UPGRADE_ROUNDING"))
	var affix := MineStyle.content_text(data,"affix_text")
	if not affix.is_empty():
		text += "\n\n"+Words.text("EQUIPMENT_AFFIX")+"\n"+affix
		if not _effect_available(selected_item):
			text += "\n"+Words.text("AFFIX_UNAVAILABLE")
	text += _set_description(str(data.get("set_id","")))
	text += _lost_set_description(data,current_id)
	var description := MineStyle.literal(text_area,text,Vector2.ZERO,Vector2(421,0),17,MineStyle.MUTED)
	description.custom_minimum_size.x = 421
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var action := "EQUIP_ITEM"
	var disabled := false
	var note := "EQUIP_NOTE"
	var cost: int = int(data.get("price",0))
	if mode == "shop" and not owned:
		action = "BUY_ITEM"
		var boss: String = str(data.get("unlock_boss",""))
		if not _effect_available(selected_item):
			disabled = true
			note = "AFFIX_UNAVAILABLE"
		elif not boss.is_empty() and not Game.profile.get("bosses",[]).has(boss):
			disabled = true
			note = "BOSS_LOCKED"
		elif int(Game.profile.get("permanent_gold",0)) < cost:
			disabled = true
			note = "INSUFFICIENT_GOLD"
		else:
			note = "PURCHASE_NOTE"
	elif mode == "upgrade":
		action = "UPGRADE_ITEM"
		cost = _upgrade_cost(selected_item)
		note = "UPGRADE_NOTE"
		if _item_level(selected_item) >= 5:
			disabled = true
			note = "UPGRADE_MAX"
		elif not Game.upgrade_has_gain(selected_item):
			disabled = true
			note = "UPGRADE_CAPPED"
		elif int(Game.profile.get("permanent_gold",0)) < cost:
			disabled = true
			note = "INSUFFICIENT_GOLD"
	elif equipped:
		action = "ITEM_EQUIPPED"
		disabled = true
	MineStyle.label(detail,note,Vector2(22,386),Vector2(444,51),16,MineStyle.RED if disabled and not equipped else MineStyle.MUTED,{"cost":cost,"boss":data.get("unlock_boss","")})
	action_button = MineStyle.button(detail,action,Vector2(22,447),Vector2(444,48),_commit_item)
	action_button.name = "PrimaryAction"
	action_button.disabled = disabled
	if action in ["BUY_ITEM","UPGRADE_ITEM"]:
		action_button.text += " · "+str(cost)

func _format_stats(stats: Dictionary) -> String:
	var lines: PackedStringArray = []
	for key in stats:
		var value := "%.1f%%" % (float(stats[key])*100.0) if str(key) == "move_speed" else _stat_value(str(key),stats[key])
		lines.append(Words.text("STAT_"+str(key).to_upper())+"  +"+value)
	return " · ".join(lines) if not lines.is_empty() else Words.text("NO_BASE_STATS")

func _stat_value(key: String, value: Variant) -> String:
	if key == "attack_interval":
		return "%.2f s" % float(value)
	if key in ["attack_speed","crit_chance","cooldown_reduction","damage_bonus","damage_reduction","burn_damage","corrosion_damage_bonus","status_duration"]:
		return "%.1f%%" % (float(value)*100.0)
	return "%.1f" % float(value)

func _set_description(set_id: String) -> String:
	if set_id.is_empty():
		return ""
	var count := 0
	for id in Game.profile.get("loadout",{}).values():
		if ContentRegistry.equipment(str(id)).get("set_id","") == set_id:
			count += 1
	var data: Dictionary = ContentRegistry.sets().get(set_id,{})
	var output := "\n\n"+Words.text("SET_COUNT",{"set":MineStyle.content_text(data,"name",set_id),"count":count})
	var candidate: Dictionary = ContentRegistry.equipment(selected_item)
	var equipped_id: String = str(Game.profile.get("loadout",{}).get(candidate.get("slot",""),""))
	var after := count
	if equipped_id != selected_item:
		after += 1
		if ContentRegistry.equipment(equipped_id).get("set_id","") == set_id:
			after -= 1
	for threshold in [2,4,6]:
		var effect: Dictionary = data.get("thresholds",{}).get(str(threshold),{})
		var marker := "●" if count >= threshold else "○"
		if count < threshold and after >= threshold:
			marker = "+"
		output += "\n"+marker+" "+str(threshold)+" · "+MineStyle.content_text(effect,"text")
	return output

func _lost_set_description(candidate: Dictionary, equipped_id: String) -> String:
	var previous_set: String = str(ContentRegistry.equipment(equipped_id).get("set_id",""))
	if previous_set.is_empty() or previous_set == str(candidate.get("set_id","")):
		return ""
	var output := ""
	var previous_count := int(Game.selected_stats().get("sets",{}).get(previous_set,0))
	var previous_definition: Dictionary = ContentRegistry.sets().get(previous_set,{})
	for threshold in [2,4,6]:
		if previous_count == threshold:
			var effect: Dictionary = previous_definition.get("thresholds",{}).get(str(threshold),{})
			output += "\n\n"+Words.text("SET_LOSE",{"set":MineStyle.content_text(previous_definition,"name",previous_set),"count":threshold})+"\n"+MineStyle.content_text(effect,"text")
	return output

func _upgrade_cost(id: String) -> int:
	return Game.upgrade_cost(id)

func _effect_available(id: String) -> bool:
	var path := "res://scripts/combat/equipment_effects.gd"
	if not ResourceLoader.exists(path):
		return false
	var implementation: Script = load(path)
	return implementation.call("implemented_ids").has(id)

func _commit_item() -> void:
	if busy or selected_item.is_empty() or (action_button != null and action_button.disabled):
		return
	busy = true
	action_button.disabled = true
	var id := selected_item
	var success := false
	if mode == "shop" and not Game.profile.get("equipment",{}).has(id):
		success = Game.buy_equipment(id,"shop:"+id)
	elif mode == "upgrade":
		success = Game.upgrade_equipment(id,"upgrade:"+id+":"+str(_item_level(id)))
	else:
		success = Game.equip_item(id)
	if not success:
		busy = false
		if not Game.last_error.is_empty():
			_render()
			app._show_save_error()
		else:
			_render()
		return
	list_scroll = item_list.scroll_vertical
	# One visible confirmation per transaction; ignore a physical double click.
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	busy = false
	_render()
