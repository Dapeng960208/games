extends Control
## Original mineral-workshop dossier UI. All actions commit through Game.
## Hero/equipment artwork prefers the game's original ImageGen PNGs.

const SLOTS := ["weapon","head","chest","hands","feet","charm"]
const SKILLS := ["q","secondary","f","ultimate"]
const BINDING_ACTIONS := ["skill_q","skill_secondary","skill_f","skill_ultimate"]
const Advice = preload("res://scripts/ui/equipment_advice.gd")
const SetShop = preload("res://scripts/ui/equipment_set_shop.gd")
const Recycle = preload("res://scripts/ui/equipment_recycle_panel.gd")
const HeroDossier = preload("res://scripts/ui/hero_dossier.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const StatSheet = preload("res://scripts/ui/stat_sheet.gd")
const InstanceCreation = preload("res://scripts/ui/instance_acquisition_panel.gd")
const Catalog = preload("res://scripts/ui/equipment_catalog.gd")
var app: Node
var mode := "heroes"
var preview_hero := ""
var selected_item := ""
var slot_filter := "all"
var set_filter := "all"
var available_only := false
var search_query := ""
var sort_order := 0
var detail_tab := "stats"
var set_detail_tab := "set"
var list_scroll := 0
var busy := false
var body: Control
var item_list: ScrollContainer
var action_button: Button
var shop_sets := true
var selected_set := "S09"
var set_scroll := 0
var inventory_recycle := false
var sale_selection: Dictionary = {}
var recycle_scroll := 0
var creation_rarity := "white"
var creation_power_type := ""
var creation_level := 0
var creation_transaction_id := ""
var creation_message := ""
var creation_omitted: Dictionary = {}

func _ready() -> void:
	preview_hero = str(Game.profile.get("selected_hero","CH01"))
	_render()

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var header := MineStyle.panel(self,Vector2(32,14),Vector2(1216,148))
	header.name = "WorkshopHeader"
	MineStyle.literal(header,_t("营地工坊 / 永久档案","CAMP WORKSHOP / PERMANENT RECORD"),Vector2(18,8),Vector2(730,20),12,MineStyle.AMBER)
	var heading := MineStyle.label(header,{"heroes":"HERO_DOSSIERS","skills":"SKILL_LEDGER","inventory":"EQUIPMENT_BENCH","shop":"SUPPLY_CATALOG","upgrade":"UPGRADE_BENCH"}.get(mode,"EQUIPMENT_BENCH"),Vector2(18,35),Vector2(730,44),28)
	heading.name = "WorkshopHeading"
	if mode == "shop": heading.text = _t("套装商城 · 14 套", "SET SHOP · 14 SETS") if shop_sets else _t("单件装备目录", "EQUIPMENT SHOP")
	if mode == "inventory": heading.text = _t("装备回收" if inventory_recycle else "装备背包", "EQUIPMENT RECYCLING" if inventory_recycle else "EQUIPMENT INVENTORY")
	if mode == "craft": heading.text = _t("定向打造", "CRAFT EQUIPMENT")
	if mode == "upgrade": heading.text = _t("装备强化", "EQUIPMENT REFINEMENT")
	MineStyle.literal(header,_t("金币","GOLD"),Vector2(802,13),Vector2(160,19),12,MineStyle.AMBER)
	MineStyle.literal(header,str(int(Game.profile.get("permanent_gold",0))),Vector2(802,34),Vector2(160,32),23,MineStyle.INK)
	MineStyle.button(header,"RETURN_CAMP",Vector2(982,27),Vector2(214,45),app.show_camp).name = "ReturnCamp"
	var tabs := [["heroes",_t("英雄档案","Heroes")],["skills",_t("技能成长","Skills")],["inventory",_t("装备背包","Inventory")],["shop",_t("装备商城","Shop")],["upgrade",_t("精工强化","Refine")]]
	if int(Game.profile.get("ruleset_version",1)) == 2: tabs.insert(4,["craft",_t("定向打造","Craft")])
	for i in range(tabs.size()):
		var data: Array = tabs[i]
		var tab := MineStyle.button(header,"",Vector2(18+i*(122 if tabs.size() == 6 else 144),96),Vector2(114 if tabs.size() == 6 else 134,40),func(): _switch_page(data[0]))
		tab.name = "Tab_"+data[0]
		tab.text = data[1]
		tab.add_theme_font_size_override("font_size",16)
		if mode == data[0]: MineStyle.selected(tab)
	if mode in ["inventory","shop","craft","upgrade"]:
		var attributes := MineStyle.button(header,"",Vector2(774,96),Vector2(184,40),_show_character_stats)
		attributes.name = "OpenCharacterStats"
		attributes.text = _t("角色属性", "Character stats")
		attributes.add_theme_font_size_override("font_size",16)
	if mode == "shop":
		var catalog_toggle := MineStyle.button(header,"",Vector2(976,96),Vector2(220,40),func(): shop_sets = not shop_sets; creation_transaction_id = ""; creation_message = ""; _render())
		catalog_toggle.name = "ToggleSetShop"
		catalog_toggle.text = _t("查看单件装备", "Individual items") if shop_sets else _t("查看装备套装", "Equipment sets")
		catalog_toggle.add_theme_font_size_override("font_size",15)
	elif mode == "inventory":
		var recycle_toggle := MineStyle.button(header,"",Vector2(976,96),Vector2(220,40),func(): inventory_recycle = not inventory_recycle; _render())
		recycle_toggle.name = "ToggleRecycle"
		recycle_toggle.text = _t("返回装备背包", "Back to inventory") if inventory_recycle else _t("多选回收装备", "Recycle equipment")
		recycle_toggle.add_theme_font_size_override("font_size",15)
		MineStyle.button_skin(recycle_toggle,"secondary" if inventory_recycle else "danger")
	body = Control.new()
	body.position = Vector2(32,178)
	body.size = Vector2(1216,510)
	add_child(body)
	if mode == "heroes":
		_render_heroes()
	elif mode == "skills":
		_render_skills()
	elif int(Game.profile.get("ruleset_version",1)) == 2 and mode in ["shop","craft"]:
		InstanceCreation.render(self)
	elif mode == "shop" and shop_sets:
		SetShop.render(self)
	elif mode == "inventory" and inventory_recycle:
		Recycle.render(self)
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
	creation_transaction_id = ""
	creation_message = ""
	app.route = "workshop_"+mode
	# Keep the inspected item across inventory, shop and refinement whenever
	# it belongs to that page. _render_equipment handles an unavailable item.
	list_scroll = 0
	_render()

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _render_heroes() -> void:
	HeroDossier.render(self)

func _show_character_stats() -> void:
	var popup: Panel = app._push_modal("",Vector2(920,620))
	popup.name = "CampCharacterAttributes"
	MineStyle.literal(popup,_t("角色属性 · ","CHARACTER STATS · ")+MineStyle.content_text(ContentRegistry.hero(Game.profile.selected_hero),"name"),Vector2(24,20),Vector2(680,39),26,MineStyle.AMBER)
	var close := MineStyle.button(popup,"BACK",Vector2(736,19),Vector2(158,42),app._pop_modal)
	close.name = "CloseCampCharacterStats"
	var scroll := ScrollContainer.new()
	scroll.name = "CampStatScroll"
	scroll.position = Vector2(24,76)
	scroll.size = Vector2(872,521)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	popup.add_child(scroll)
	var sheet := StatSheet.new()
	scroll.add_child(sheet)
	sheet.configure(Inspect.breakdown(Game.profile.selected_hero,Game.hero_level(),Game.profile.loadout,Game.profile.equipment,null,int(Game.profile.get("ruleset_version",1)),Game.hero_talents()),850)
	close.grab_focus()

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
		var unlocked := level >= int(skill.get("unlock",[1,2,3,4][i]))
		var panel := MineStyle.panel(body,Vector2(310,(i/2)*182),Vector2(442,164))
		panel.position.x += (i%2)*464
		var binding_key: String = ControlBindings.label_for(BINDING_ACTIONS[i],Game.profile.get("settings",{}).get("controls",{}),Words.locale)
		MineStyle.literal(panel,binding_key,Vector2(18,13),Vector2(68,31),13 if binding_key.length()>3 else 22,MineStyle.AMBER if unlocked else MineStyle.MUTED)
		MineStyle.literal(panel,MineStyle.content_text(skill,"name"),Vector2(91,13),Vector2(333,35),21)
		MineStyle.label(panel,"SKILL_READY" if unlocked else "SKILL_LOCKED",Vector2(18,52),Vector2(406,27),16,MineStyle.GREEN if unlocked else MineStyle.MUTED,{"level":skill.get("unlock",[1,2,3,4][i]),"cost":skill.get("cost",0),"cooldown":"%.1f" % float(skill.get("cooldown",0))})
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
		var gate: int = [1,2,3,4,10,12,14,16,18,20][i]
		var mark := MineStyle.label(rail,str(gate),Vector2(18+i*86,60),Vector2(70,27),20,MineStyle.GREEN if level >= gate else MineStyle.MUTED)
		mark.text = str(gate)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MineStyle.label(rail,"UNLOCK_LEGEND",Vector2(18,94),Vector2(870,23),14,MineStyle.MUTED)

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
	var scroll := ScrollContainer.new()
	scroll.name = "CoreActionsScroll"
	scroll.position = Vector2(28,80)
	scroll.size = Vector2(686,310)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var flow := VBoxContainer.new()
	flow.add_theme_constant_override("separation",12)
	scroll.add_child(flow)
	for entry: Array in [[MineStyle.content_text(passive,"name"),23,MineStyle.CYAN],[MineStyle.content_text(passive,"description"),18,MineStyle.INK],[Words.text("DASH_LABEL")+" / "+MineStyle.content_text(dash,"name"),22,MineStyle.AMBER],[Words.text("DASH_DETAILS",{"distance":dash.get("distance",0),"cooldown":dash.get("cooldown",0)}),18,MineStyle.MUTED]]:
		var label := MineStyle.literal(flow,entry[0],Vector2.ZERO,Vector2(661,0),entry[1],entry[2])
		label.custom_minimum_size.x = 661
	MineStyle.button(panel,"BACK",Vector2(488,414),Vector2(226,50),app._pop_modal).grab_focus()

func _render_equipment() -> void:
	Catalog.render(self)

func _filtered_equipment() -> Array:
	var output: Array = []
	for value in (ContentRegistry.equipment_ids(int(Game.profile.get("ruleset_version",1))) if mode == "shop" else Game.profile.get("equipment",{}).keys()):
		var id := str(value)
		var data: Dictionary = Game.equipment_definition(id)
		if mode != "shop" and not Game.profile.get("equipment",{}).has(id):
			continue
		var equipped := str(Game.profile.get("loadout",{}).get(data.get("slot",""),"")) == id
		if available_only and not equipped and (not _unlocked(data) or not Advice.is_relevant(data,str(Game.profile.get("selected_hero","CH01")))):
			continue
		if slot_filter != "all" and data.get("slot","") != slot_filter:
			continue
		if set_filter != "all" and str(data.get("set_id","")) != set_filter:
			continue
		if not search_query.strip_edges().is_empty():
			var searchable := MineStyle.content_text(data,"name")+" "+MineStyle.content_text(data,"affix_text")+" "+MineStyle.content_text(ContentRegistry.sets().get(str(data.get("set_id","")),{}),"name")+" "+Words.text("SLOT_"+str(data.slot).to_upper())
			if not searchable.to_lower().contains(search_query.strip_edges().to_lower()): continue
		output.append(id)
	output.sort_custom(func(a: String, b: String) -> bool:
		var first: Dictionary = Game.equipment_definition(a)
		var second: Dictionary = Game.equipment_definition(b)
		if sort_order == 1: return MineStyle.content_text(first,"name").naturalnocasecmp_to(MineStyle.content_text(second,"name")) < 0
		if sort_order == 2 and int(first.price) != int(second.price): return int(first.price) < int(second.price)
		if sort_order == 3 and _item_level(a) != _item_level(b): return _item_level(a) > _item_level(b)
		if sort_order == 0 and first.slot != second.slot: return SLOTS.find(first.slot) < SLOTS.find(second.slot)
		return a < b)
	return output

func _toggle_catalog() -> void:
	available_only = false
	set_filter = "all"
	slot_filter = "all"
	search_query = ""
	list_scroll = 0
	_render()

func _unlocked(item: Dictionary) -> bool:
	if Game.profile.get("equipment",{}).has(str(item.get("id",""))): return true
	var boss := str(item.get("unlock_boss",""))
	return _effect_available(str(item.get("id",""))) and (boss.is_empty() or Game.profile.get("bosses",[]).has(boss))

func _availability_reason(item: Dictionary) -> String:
	var id := str(item.get("id",""))
	if Game.profile.get("equipment",{}).has(id):
		var equipped := str(Game.profile.get("loadout",{}).get(item.get("slot",""),"")) == id
		return _t("已挂载", "Equipped")+" +"+str(_item_level(id)) if equipped else Words.text("OWNED")+" +"+str(_item_level(id))
	if not _effect_available(id): return Words.text("AFFIX_UNAVAILABLE")
	if not _unlocked(item):
		var boss_id := str(item.get("unlock_boss",""))
		var boss: Dictionary = WorldCatalog.bosses().get(boss_id,{})
		return _t("击败首领：", "Defeat boss: ")+MineStyle.content_text(boss,"name",boss_id)
	var price := int(item.get("price",0))
	return Words.text("PRICE_GOLD",{"gold":price})+(_t(" · 余额不足", " · Need more gold") if int(Game.profile.get("permanent_gold",0)) < price else "")

func _suggested_equipment() -> String:
	var hero := str(Game.profile.get("selected_hero","CH01"))
	var selected_slot := str(Game.equipment_definition(selected_item).get("slot",slot_filter))
	if selected_slot == "all": selected_slot = "weapon"
	var before: Dictionary = Game.selected_stats()
	# An inspect-only suggestion uses a transparent benefit predicate. It does
	# not rank the whole build or value untriggered affixes as permanent stats.
	var candidates := _filtered_equipment()
	for owned_first: bool in [true,false]:
		for id: String in candidates:
			var item: Dictionary = Game.equipment_definition(id)
			var owned: bool = Game.profile.get("equipment",{}).has(id)
			if owned != owned_first or item.get("slot","") != selected_slot or not _unlocked(item): continue
			if str(Game.profile.get("loadout",{}).get(selected_slot,"")) == id or not Advice.is_relevant(item,hero): continue
			if not owned and int(item.get("price",0)) > int(Game.profile.get("permanent_gold",0)): continue
			var after: Dictionary = Game.preview_stats(id)
			if Advice.lost_tiers(before,after).is_empty() and _has_relevant_gain(hero,before,after): return id
	return ""

func _has_relevant_gain(hero: String, before: Dictionary, after: Dictionary) -> bool:
	var keys: Array[String] = ["max_hp","armor","magic_resist","move_speed","crit_chance","crit_multiplier","cooldown_reduction","damage_bonus","damage_reduction","true_damage_bonus"]
	if hero == "CH03":
		var current_power: float = HeroAbilities.preview_powers(hero, before).skill_H
		var next_power: float = HeroAbilities.preview_powers(hero, after).skill_H
		if next_power > current_power + 0.00001: return true
		keys.append_array(["resource_max","magic_penetration"])
	else: keys.append_array(["attack","armor_penetration"])
	for key: String in keys:
		if float(after.get(key,0)) > float(before.get(key,0)) + 0.00001: return true
	return float(after.get("attack_interval",1)) < float(before.get("attack_interval",1)) - 0.00001

func _item_level(id: String) -> int:
	var item: Variant = Game.profile.get("equipment",{}).get(id,{})
	return int(item.get("level",0)) if item is Dictionary else int(item)

func _render_equipment_detail() -> void:
	Catalog.detail(self)

func _upgrade_cost(id: String) -> int:
	return Game.upgrade_cost(id)

func _effect_available(id: String) -> bool:
	var path := "res://scripts/combat/equipment_effects.gd"
	if not ResourceLoader.exists(path):
		return false
	var implementation: Script = load(path)
	return implementation.call("implemented_ids").has(id) or (int(Game.profile.get("ruleset_version",1)) == 2 and not ContentRegistry.equipment(id,2).is_empty() and ContentRegistry.equipment(id,2).get("affix_id","") == "")

func _commit_item() -> void:
	if busy or selected_item.is_empty() or (action_button != null and action_button.disabled):
		return
	busy = true
	action_button.disabled = true
	var id := selected_item
	var success := false
	if int(Game.profile.get("ruleset_version",1)) == 2 and Game.profile.get("equipment",{}).get(id,{}).get("location","") == "pending":
		if creation_transaction_id.is_empty(): creation_transaction_id = "claim:"+Crypto.new().generate_random_bytes(16).hex_encode()
		success = bool(Game.call("claim_pending_equipment",id,creation_transaction_id))
		if success: creation_transaction_id = ""
	elif mode == "shop" and not Game.profile.get("equipment",{}).has(id):
		success = Game.buy_equipment(id)
	elif mode == "upgrade":
		success = Game.upgrade_equipment(id)
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
