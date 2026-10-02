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
const SkillInspect = preload("res://scripts/ui/skill_inspection.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const StatSheet = preload("res://scripts/ui/stat_sheet.gd")
const InstanceForging = preload("res://scripts/ui/instance_forging_panel.gd")
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
var forge_kind := "enhance"
var forge_rank := 1
var forge_affix_index := 0
var forge_affix_type := ""
var forge_source_instance_id := ""
var forge_transaction_id := ""
var forge_frozen_kind := ""
var forge_frozen_request: Dictionary = {}
var forge_message := ""
var forge_result_details := ""
var _equipment_views: Dictionary = {}
var _resolved_stats: Dictionary = {}

func _ready() -> void:
	preview_hero = str(Game.profile.get("selected_hero","CH01"))
	_render()

func _render() -> void:
	# These views belong to one render only. Any equip/forge/filter action starts
	# a new render and reads the latest committed records, including duplicate IDs.
	_equipment_views.clear()
	_resolved_stats.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var header := MineStyle.panel(self,Vector2.ZERO,Vector2(1280,64))
	header.name = "WorkshopHeader"
	var emblem := TextureRect.new()
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.texture = load("res://assets/generated/ui/refactor_v1/decor/compass_emblem.png")
	emblem.position = Vector2(25,3)
	emblem.size = Vector2(51,58)
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(emblem)
	MineStyle.literal(header,_t("营地工坊","CAMP WORKSHOP"),Vector2(77,18),Vector2(168,32),19)
	var tabs := [["heroes",_t("英雄","Heroes")],["skills",_t("技能","Skills")],["inventory",_t("装备","Gear")],["shop",_t("商店","Shop")],["upgrade",_t("锻造","Forge")]]
	if int(Game.profile.get("ruleset_version",1)) == 2: tabs.insert(4,["craft",_t("打造","Craft")])
	for i in range(tabs.size()):
		var data: Array = tabs[i]
		var tab := MineStyle.button(header,"",Vector2(271+i*93,11),Vector2(86,44),func(): _switch_page(data[0]))
		tab.name = "Tab_"+data[0]
		tab.text = data[1]
		tab.add_theme_font_size_override("font_size",18)
		_nav_style(tab,mode == data[0])
	var codex := MineStyle.button(header,"",Vector2(836,11),Vector2(90,44),func(): app.show_codex())
	codex.name = "OpenMonsterCodex"
	codex.text = _t("图鉴","Codex")
	codex.add_theme_font_size_override("font_size",18)
	_nav_style(codex,false)
	MineStyle.literal(header,"◉",Vector2(940,21),Vector2(24,25),19,MineStyle.AMBER)
	var gold := MineStyle.literal(header,str(int(Game.profile.get("permanent_gold",0))),Vector2(971,17),Vector2(120,31),22)
	gold.tooltip_text = _t("永久金币","Permanent gold")
	var return_button := MineStyle.button(header,"RETURN_CAMP",Vector2(1104,10),Vector2(153,44),app.show_camp)
	return_button.name = "ReturnCamp"
	return_button.add_theme_font_size_override("font_size",16)
	_nav_style(return_button,false)
	var heading := MineStyle.label(self,{"heroes":"HERO_DOSSIERS","skills":"SKILL_LEDGER","inventory":"EQUIPMENT_BENCH","shop":"SUPPLY_CATALOG","upgrade":"UPGRADE_BENCH"}.get(mode,"EQUIPMENT_BENCH"),Vector2(48,83),Vector2(756,45),30)
	heading.name = "WorkshopHeading"
	if mode == "shop": heading.text = _t("装备商城", "EQUIPMENT SHOP")
	if mode == "inventory": heading.text = _t("装备回收" if inventory_recycle else "装备背包", "EQUIPMENT RECYCLING" if inventory_recycle else "EQUIPMENT INVENTORY")
	if mode == "craft": heading.text = _t("定向打造", "CRAFT EQUIPMENT")
	if mode == "upgrade": heading.text = _t("精工锻造", "EQUIPMENT FORGE") if int(Game.profile.get("ruleset_version",1)) == 2 else _t("装备强化", "EQUIPMENT REFINEMENT")
	if mode in ["inventory","shop","craft","upgrade"]:
		var attributes := MineStyle.button(self,"",Vector2(48,130),Vector2(148,32),_show_character_stats)
		attributes.name = "OpenCharacterStats"
		attributes.text = _t("角色属性", "Character stats")
		attributes.add_theme_font_size_override("font_size",14)
		_secondary_style(attributes,false)
	if mode == "shop":
		var catalog_toggle := MineStyle.button(self,"",Vector2(214,130),Vector2(206,32),func(): shop_sets = not shop_sets; creation_transaction_id = ""; creation_message = ""; _render())
		catalog_toggle.name = "ToggleSetShop"
		catalog_toggle.text = _t("查看单件装备", "Individual items") if shop_sets else _t("查看装备套装", "Equipment sets")
		catalog_toggle.add_theme_font_size_override("font_size",14)
		_secondary_style(catalog_toggle,true)
	elif mode == "inventory":
		var recycle_toggle := MineStyle.button(self,"",Vector2(214,130),Vector2(206,32),func(): inventory_recycle = not inventory_recycle; _render())
		recycle_toggle.name = "ToggleRecycle"
		recycle_toggle.text = _t("返回装备背包", "Back to inventory") if inventory_recycle else (_t("回收装备", "Recycle gear") if int(Game.profile.get("ruleset_version",1)) == 2 else _t("多选回收装备", "Recycle equipment"))
		recycle_toggle.add_theme_font_size_override("font_size",14)
		_secondary_style(recycle_toggle,inventory_recycle)
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
	elif int(Game.profile.get("ruleset_version",1)) == 2 and mode == "upgrade":
		InstanceForging.render(self)
	elif mode == "shop" and shop_sets:
		SetShop.render(self)
	elif mode == "inventory" and inventory_recycle:
		Recycle.render(self)
	else:
		_render_equipment()
	MineStyle.literal(self,_t("Esc  返回营地    ·    Tab  切换焦点    ·    Enter  确认","Esc  Return to camp    ·    Tab  Navigate    ·    Enter  Confirm"),Vector2(40,695),Vector2(750,20),12,MineStyle.MUTED)
	var focus := find_child("PrimaryAction",true,false) as Button
	if focus != null and not focus.disabled:
		focus.grab_focus()
	else:
		var back := find_child("ReturnCamp",true,false) as Button
		if back != null:
			back.grab_focus()

static func _nav_style(button: Button, active: bool) -> void:
	button.custom_minimum_size = Vector2(44,32)
	MineStyle.tab(button,active)

static func _secondary_style(button: Button, active: bool) -> void:
	button.custom_minimum_size.y = 32
	MineStyle.button_skin(button,"selected_card" if active else "secondary")
	button.add_theme_color_override("font_color",MineStyle.CYAN if active else MineStyle.INK)

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

func _definition(id: String) -> Dictionary:
	if not _equipment_views.has(id): _equipment_views[id] = Game.equipment_definition(id)
	return _equipment_views[id]

func _selected_stats() -> Dictionary:
	if _resolved_stats.is_empty(): _resolved_stats = Game.selected_stats()
	return _resolved_stats

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
	HeroDossier.render_skills(self)


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
	for entry: Array in [[MineStyle.content_text(passive,"name_v2" if int(Game.profile.get("ruleset_version",1)) == 2 and passive.has("name_v2") else "name"),23,MineStyle.CYAN],[SkillInspect.passive_text(hero,Game.selected_stats()),18,MineStyle.INK],[Words.text("DASH_LABEL")+" / "+MineStyle.content_text(dash,"name"),22,MineStyle.AMBER],[Words.text("DASH_DETAILS",{"distance":dash.get("distance",0),"cooldown":dash.get("cooldown",0)}),18,MineStyle.MUTED]]:
		var label := MineStyle.literal(flow,entry[0],Vector2.ZERO,Vector2(661,0),entry[1],entry[2])
		label.custom_minimum_size.x = 661
	MineStyle.button(panel,"BACK",Vector2(488,414),Vector2(226,50),app._pop_modal).grab_focus()

func _render_equipment() -> void:
	Catalog.render(self)

func _filtered_equipment() -> Array:
	var output: Array = []
	for value in (ContentRegistry.equipment_ids(int(Game.profile.get("ruleset_version",1))) if mode == "shop" else Game.profile.get("equipment",{}).keys()):
		var id := str(value)
		var data: Dictionary = _definition(id)
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
		var first: Dictionary = _definition(a)
		var second: Dictionary = _definition(b)
		if sort_order == 1: return MineStyle.content_text(first,"name").naturalnocasecmp_to(MineStyle.content_text(second,"name")) < 0
		if sort_order == 2 and int(first.price) != int(second.price): return int(first.price) < int(second.price)
		if sort_order == 3 and _item_level(a) != _item_level(b): return _item_level(a) > _item_level(b)
		if sort_order == 0 and first.slot != second.slot:
			var slots := Game.equipment_slots()
			return slots.find(first.slot) < slots.find(second.slot)
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
	if Game.profile.get("equipment",{}).has(str(item.get("instance_id",item.get("id","")))): return true
	var boss := str(item.get("unlock_boss",""))
	return _effect_available(str(item.get("id",""))) and (boss.is_empty() or Game.profile.get("bosses",[]).has(boss))

func _availability_reason(item: Dictionary) -> String:
	var id := str(item.get("instance_id",item.get("id","")))
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
	var selected_slot := str(_definition(selected_item).get("slot",slot_filter))
	if selected_slot == "all": selected_slot = "weapon"
	var before: Dictionary = _selected_stats()
	# An inspect-only suggestion uses a transparent benefit predicate. It does
	# not rank the whole build or value untriggered affixes as permanent stats.
	var candidates := _filtered_equipment()
	for owned_first: bool in [true,false]:
		for id: String in candidates:
			var item: Dictionary = _definition(id)
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
	return int(item.get("enhancement_rank",item.get("level",0))) if item is Dictionary else int(item)

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
