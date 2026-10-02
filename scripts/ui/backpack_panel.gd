extends Control
const Traits = preload("res://scripts/ui/equipment_traits.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Details = preload("res://scripts/ui/equipment_details.gd")
const Grid = preload("res://scripts/ui/equipment_grid.gd")
const Sheet = preload("res://scripts/ui/stat_sheet.gd")
const Relics = preload("res://scripts/combat/class_relics.gd")
## Paused expedition folio. The owner supplies modal pause/input handling;
## this panel never rebuilds a world scene or permanently grants trial loot.
signal equipment_changed()
const Gear = preload("res://scripts/core/backpack_equipment.gd")
const Advice = preload("res://scripts/ui/equipment_advice.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const SLOTS := ["head", "chest", "hands", "legs", "feet", "ring", "charm", "weapon"]
const SLOT_NAMES := {"head":"头部", "chest":"胸甲", "hands":"手套", "legs":"裤子", "feet":"鞋子", "ring":"戒指", "charm":"饰品", "weapon":"武器"}
const SLOT_EN := {"head":"Head", "chest":"Chest", "hands":"Hands", "legs":"Legs", "feet":"Feet", "ring":"Ring", "charm":"Charm", "weapon":"Weapon"}
const RATIOS := ["crit_chance", "crit_multiplier", "cooldown_reduction", "damage_bonus", "damage_reduction", "equipment_damage_reduction", "armor_damage_reduction", "magic_damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration", "attack_speed_bonus", "move_speed_bonus"]
const ATTRIBUTES := [
	["attack", "攻击力", "Attack"], ["ability_power", "法术强度", "Ability power"],
	["max_hp", "最大生命", "Max health"], ["resource_max", "资源上限", "Max resource"],
	["armor", "护甲", "Armor"], ["magic_resist", "魔法抗性", "Magic resistance"],
	["armor_damage_reduction", "物理减伤", "Physical reduction"], ["magic_damage_reduction", "魔法减伤", "Magic reduction"],
	["equipment_damage_reduction", "装备减伤", "Equipment reduction"], ["damage_bonus", "伤害加成", "Damage bonus"],
	["crit_chance", "暴击率", "Critical chance"], ["crit_multiplier", "暴击伤害", "Critical damage"],
	["attack_interval", "普攻间隔", "Attack interval"], ["attack_speed_bonus", "装备攻速加成", "Equipment attack speed"],
	["move_speed", "移动速度", "Movement speed"], ["move_speed_bonus", "装备移速加成", "Equipment movement speed"],
	["range", "普攻距离", "Basic attack range"], ["cooldown_reduction", "冷却缩减", "Cooldown reduction"],
	["armor_penetration", "物理穿透", "Armor penetration"], ["magic_penetration", "法术穿透", "Magic penetration"],
	["true_damage_bonus", "附加真实伤害", "Additional true damage"], ["resource_regen", "资源回复/秒", "Resource regen/sec"],
	["burn_damage", "燃烧伤害加成", "Burn damage bonus"], ["corrosion_damage_bonus", "腐蚀伤害加成", "Corrosion damage bonus"],
	["status_duration", "状态持续加成", "Status duration bonus"]]
var room: Node
var close_callback: Callable
var tab := "inventory"
var filter := "all"
var selected_id := ""
var selected_slot := "weapon"
var checkpoint := ""
var detail_root: Control
var status_label: Label
var message := ""
var busy := false
var search_query := ""
var detail_tab := "stats"
var inventory_scroll := 0

func configure(source_room: Node, close: Callable) -> void:
	room = source_room
	close_callback = close
	name = "BackpackPanel"
	size = Vector2(1060,620)
	mouse_filter = Control.MOUSE_FILTER_STOP
	checkpoint = str(Game.run.expedition.get("checkpoint_id", "")) if Game.run != null else ""
	selected_id = str(Game.run.loadout_snapshot.get("weapon", "")) if Game.run != null else ""
	_render()

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _slot_name(slot: String) -> String:
	return str(SLOT_EN.get(slot, slot)) if Words.locale == "en" else str(SLOT_NAMES.get(slot, slot))

func _text(parent: Node, value: String, at: Vector2, extent: Vector2, font_size: int = 16, tint: Color = MineStyle.INK) -> Label:
	var label := MineStyle.literal(parent, value, at, extent, font_size, tint)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

func _button(parent: Node, id: String, text: String, at: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := MineStyle.button(parent, "", at, extent, action)
	button.name = id
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	return button

func _render() -> void:
	for child: Node in get_children(): remove_child(child); child.queue_free()
	if Game.run == null: return
	_text(self, _t("远征行囊", "EXPEDITION BACKPACK"), Vector2(24,14), Vector2(420,40), 26, MineStyle.INK)
	var gear_tab := _button(self, "BackpackInventoryTab", _t("装备背包", "Equipment"), Vector2(485,16), Vector2(150,40), func(): tab = "inventory"; _render())
	var stat_tab := _button(self, "BackpackAttributesTab", _t("角色属性", "Attributes"), Vector2(646,16), Vector2(150,40), func(): tab = "stats"; _render())
	MineStyle.tab(gear_tab, tab == "inventory")
	MineStyle.tab(stat_tab, tab == "stats")
	_button(self, "CloseBackpack", _t("关闭 · ", "Close · ")+ProfileStore.Controls.label_for("pause", Game.profile.settings.get("controls", {}), Words.locale), Vector2(866,16), Vector2(170,40), close_callback)
	_identity()
	if tab == "inventory": _inventory(); _detail()
	else: _attributes()
	var phase := str(Game.run.expedition.get("phase", ""))
	var scope := _t("战斗中换装立即生效，清场后保存；本局掉落需成功撤离才永久入库。", "Combat swaps apply now and save when cleared; new loot joins your collection only after extraction.") if phase == "combat" else _t("配装立即保存，仅影响本次远征；本局掉落需成功撤离才永久入库。", "Changes save now for this expedition; new loot joins your collection only after extraction.")
	status_label = _text(self, message if not message.is_empty() else scope, Vector2(24,573), Vector2(1012,34), 14, MineStyle.RED if not message.is_empty() else MineStyle.MUTED)
	status_label.max_lines_visible = 2
	status_label.tooltip_text = scope+"\n"+_t("暂停中可自由换装；不会恢复生命、资源或冷却。", "Swaps are allowed while paused; health, resources and cooldowns are preserved.")+"\n"+(_t("本次会话打开背包 %d 次 · 换装 %d 次", "This session: %d backpack opens · %d swaps") % [Game.run.backpack_opens, Game.run.loadout_changes])
	_text(self, _t("暂停换装 · 生命与冷却保留", "Paused swaps · HP/cooldowns preserved"), Vector2(24,51), Vector2(790,17), 12, MineStyle.MUTED)

func _identity() -> void:
	var hero: Dictionary = ContentRegistry.hero(Game.run.hero_id)
	var card := MineStyle.panel(self, Vector2(20,69), Vector2(236,493))
	card.name = "BackpackEquippedSlots"
	MineStyle.hero_portrait(card, Game.run.hero_id, Vector2(12,5), Vector2(44,54))
	_text(card, MineStyle.content_text(hero,"name"), Vector2(66,7), Vector2(158,26), 18)
	_text(card, MineStyle.content_text(hero,"class_name")+" · Lv."+str(Game.run.level), Vector2(66,34), Vector2(158,22), 12, MineStyle.CYAN)
	# A single scan path matches the inventory folio: item art, slot, name, rank.
	var display_slots: Array[String] = ["weapon","head","chest","hands","legs","feet","ring","charm"]
	for index: int in display_slots.size():
		var slot: String = display_slots[index]
		var id := str(Game.run.loadout_snapshot.get(slot, ""))
		var item: Dictionary = Game.equipment_definition(id,true)
		var at := Vector2(10,64+index*45)
		var cell := _button(card, "BackpackSlot_"+slot, "", at, Vector2(216,44), func(): tab = "inventory"; filter = slot; selected_slot = slot; selected_id = id; search_query = ""; inventory_scroll = 0; message = ""; _render())
		MineStyle.button_skin(cell,"socket")
		if filter == slot: MineStyle.selected(cell,"socket")
		MineStyle.equipment_icon(cell, item if not item.is_empty() else {"slot":slot}, Vector2(5,3), Vector2(38,38))
		_text(cell, _slot_name(slot), Vector2(51,3), Vector2(119,16), 11, MineStyle.CYAN if filter == slot else MineStyle.MUTED)
		var item_name := MineStyle.content_text(item,"name",_t("空槽位", "Empty slot") if slot in Game.equipment_slots(true) else _t("未开放", "Locked"))
		var item_label := _text(cell, item_name, Vector2(51,20), Vector2(155,20), 12)
		item_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		var level := int(Game.run.equipment_snapshot.get(id, {}).get("enhancement_rank", Game.run.equipment_snapshot.get(id, {}).get("level", 0)))
		var rank := _text(cell, "+"+str(level) if not id.is_empty() else "", Vector2(176,3), Vector2(30,16), 11, MineStyle.CYAN if filter == slot else MineStyle.AMBER)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cell.tooltip_text = item_name
		if not slot in Game.equipment_slots(true): cell.modulate = Color(1,1,1,.6)
	var hp := _text(card, _t("生命 ", "Health ")+"%d / %d" % [ceili(Game.run.hp), ceili(Game.run.max_hp)], Vector2(14,433), Vector2(208,21), 13)
	hp.name = "BackpackHealth"
	var bar := MineStyle.meter(card, Vector2(14,458), Vector2(208,4), MineStyle.RED)
	bar.max_value = Game.run.max_hp; bar.value = Game.run.hp
	_text(card, MineStyle.content_text(hero,"resource_name")+"  %d / %d" % [ceili(Game.run.resource),ceili(float(Game.run.stats.resource_max))], Vector2(14,468), Vector2(208,21), 12, MineStyle.CYAN)

func _inventory() -> void:
	var card := MineStyle.panel(self,Vector2(268,69),Vector2(386,493))
	card.name = "BackpackOwnedInventory"
	var shown: Array[Dictionary] = []
	for entry: Dictionary in Gear.available(Game):
		var item: Dictionary = Game.equipment_definition(entry.id,true)
		var query := search_query.strip_edges().to_lower()
		if filter != "all" and entry.slot != filter: continue
		if not query.is_empty() and not (MineStyle.content_text(item,"name")+" "+MineStyle.content_text(item,"affix_text")).to_lower().contains(query): continue
		shown.append(entry)
	_text(card,_t("已拥有装备","OWNED EQUIPMENT")+" · "+str(shown.size()),Vector2(16,12),Vector2(258,28),18,MineStyle.INK)
	_button(card,"BackpackAllItems",_t("全部","All"),Vector2(296,8),Vector2(74,36),func(): filter = "all"; search_query = ""; inventory_scroll = 0; _render())
	var search := LineEdit.new()
	search.name = "BackpackSearch"
	search.position = Vector2(16,51)
	search.size = Vector2(354,36)
	search.text = search_query
	search.placeholder_text = _t("搜索名称 / 词条","Search name / affix")
	search.add_theme_font_size_override("font_size",14)
	search.add_theme_color_override("font_color",MineStyle.INK)
	search.add_theme_color_override("font_placeholder_color",MineStyle.MUTED)
	search.add_theme_stylebox_override("normal",MineStyle.box(MineStyle.PAPER_LIGHT,MineStyle.COPPER,1))
	search.add_theme_stylebox_override("focus",MineStyle.box(MineStyle.PAPER_LIGHT,MineStyle.CYAN,1))
	card.add_child(search)
	search.text_changed.connect(func(value: String):
		search_query = value; inventory_scroll = 0; _render()
		var next := find_child("BackpackSearch",true,false) as LineEdit
		if next != null: next.grab_focus(); next.caret_column = value.length())
	var choice := OptionButton.new()
	choice.name = "BackpackSlotFilter"
	choice.position = Vector2(16,94)
	choice.size = Vector2(354,34)
	choice.fit_to_longest_item = false
	choice.add_theme_font_size_override("font_size",14)
	card.add_child(choice)
	var slots: Array = ["all"]+Game.equipment_slots(true)
	for slot: String in slots: choice.add_item(_t("全部槽位","All slots") if slot == "all" else _slot_name(slot))
	choice.select(maxi(0,slots.find(filter)))
	choice.item_selected.connect(func(index: int): filter = slots[index]; inventory_scroll = 0; _render())
	var scroll := _scroll(card,"BackpackItemScroll",Vector2(16,140),Vector2(354,338))
	var grid := Grid.new()
	grid.name = "BackpackEquipmentGrid"
	scroll.add_child(grid)
	grid.configure(334,3)
	for entry: Dictionary in shown:
		var item: Dictionary = Game.equipment_definition(entry.id,true)
		var badge := _t("已穿戴","Equipped") if entry.equipped else _t("本局掉落","Run loot") if entry.pending else _t("已入库","Secured")
		grid.add_item(item,entry.level,Game.run.hero_id,"BackpackItem_",selected_id == entry.id,badge+" +"+str(entry.level),func(): inventory_scroll = scroll.scroll_vertical; selected_id = entry.id; selected_slot = entry.slot; message = ""; _render(),entry.equipped)
	if shown.is_empty():
		var empty := _text(grid,_t("当前筛选无装备。点全部清除筛选；本局掉落需撤离才永久入库。","No matching gear. Choose All to clear filters. Run loot is secured after extraction."),Vector2.ZERO,Vector2(334,130),15,MineStyle.MUTED)
		empty.custom_minimum_size.x = 334
	scroll.set_deferred("scroll_vertical",inventory_scroll)

func _detail() -> void:
	detail_root = MineStyle.panel(self, Vector2(666,69), Vector2(374,493))
	detail_root.name = "BackpackItemDetails"
	if not selected_slot in Game.equipment_slots(true):
		_text(detail_root, _slot_name(selected_slot), Vector2(18,16), Vector2(338,32), 22, MineStyle.AMBER)
		_text(detail_root, _t("此槽位为后续装备扩展预留，目前没有可穿戴物品。", "This slot is reserved for future equipment; no items are available yet."), Vector2(18,65), Vector2(338,100), 16, MineStyle.MUTED)
		return
	var comparison := Gear.preview(Game, selected_id, selected_slot)
	if comparison.is_empty(): return
	var data: Dictionary = Game.equipment_definition(selected_id,true)
	# The selected item is the visual anchor; all figures still come from the
	# same live preview and complete scrollable Details component below.
	MineStyle.equipment_icon(detail_root, data if not data.is_empty() else {"slot":selected_slot}, Vector2(133,9), Vector2(108,108))
	var title := _text(detail_root, MineStyle.content_text(data,"name",_t("未装备", "Unequipped")), Vector2(18,121), Vector2(338,45), 21,MineStyle.INK)
	title.max_lines_visible = 2
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = title.text
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	var metadata := _slot_name(selected_slot)+" · +"+str(comparison.level)
	if not Inspect.rarity(data).is_empty(): metadata = Inspect.rarity_label(data)+" · "+metadata
	if data.get("instance_record") is Dictionary: metadata = "Lv.%d · " % int(data.instance_record.item_level)+metadata
	if not data.is_empty(): metadata += " · "+MineStyle.content_text(data,"race_name")
	var identity := _text(detail_root, metadata, Vector2(18,169), Vector2(338,29), 12, MineStyle.CYAN)
	identity.max_lines_visible = 2
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.tooltip_text = metadata
	identity.mouse_filter = Control.MOUSE_FILTER_PASS
	for index: int in 3:
		var page: String = ["stats","compare","set"][index]
		var detail_button := _button(detail_root,"BackpackDetailTab_"+page,[_t("属性","Attributes"),_t("对比","Compare"),_t("套装","Set effects")][index],Vector2(16+index*115,204),Vector2(112,34),func(): detail_tab = page; _render())
		detail_button.add_theme_font_size_override("font_size",14)
		MineStyle.tab(detail_button, detail_tab == page)
	MineStyle.divider(detail_root,Vector2(24,198),326)
	var scroll := _scroll(detail_root,"BackpackComparisonScroll",Vector2(16,251),Vector2(342,171))
	var content := Details.new()
	scroll.add_child(content)
	content.configure(data,int(comparison.level),320,Game.run.hero_id,comparison.current_stats,comparison.next_stats,detail_tab)
	var wearing: bool = selected_id == str(comparison.current_id) and int(comparison.level) == int(Game.run.equipment_snapshot.get(selected_id, {}).get("enhancement_rank",Game.run.equipment_snapshot.get(selected_id, {}).get("level",0)))
	var equip_text := _t("选择装备", "Select equipment") if selected_id.is_empty() else (_t("已穿戴", "Equipped") if wearing else _t("穿戴 · 立即生效", "Equip · apply now"))
	var equip := _button(detail_root, "BackpackEquip", equip_text, Vector2(16,437), Vector2(219,44), func(): _apply(selected_id,selected_slot))
	MineStyle.primary(equip)
	equip.disabled = busy or wearing or selected_id.is_empty()
	var remove := _button(detail_root, "BackpackUnequip", _t("脱下", "Unequip"), Vector2(245,437), Vector2(113,44), func(): _apply("",selected_slot))
	remove.disabled = busy or str(comparison.current_id).is_empty()

func _set_changes(list: Node, before: Dictionary, after: Dictionary) -> void:
	var ids: Array = before.get("sets", {}).keys()
	for id: String in after.get("sets", {}):
		if not ids.has(id): ids.append(id)
	ids.sort()
	for id: String in ids:
		var old := int(before.get("sets", {}).get(id,0))
		var next := int(after.get("sets", {}).get(id,0))
		var data: Dictionary = ContentRegistry.sets().get(id, {})
		_flow_text(list, MineStyle.content_text(data,"name",id)+" · %d → %d" % [old,next]+_t(" 件", " pieces"),399,16,MineStyle.AMBER)
		for threshold: int in [2,4,6]:
			var gained := old < threshold and next >= threshold
			var lost := old >= threshold and next < threshold
			var tag := _t("激活", "Gained") if gained else (_t("失去", "Lost") if lost else (_t("保留", "Active") if next >= threshold else _t("未激活", "Inactive")))
			var effect: Dictionary = data.get("thresholds", {}).get(str(threshold), {})
			_flow_text(list, "%s · %d" % [tag,threshold]+_t(" 件：", " pieces: ")+MineStyle.content_text(effect,"text"),399,14,MineStyle.GREEN if gained else MineStyle.RED if lost else MineStyle.MUTED)

func _attributes() -> void:
	var card := MineStyle.panel(self,Vector2(268,69),Vector2(772,493))
	card.name = "BackpackCharacterAttributes"
	_text(card,_t("完整属性 · 数值与加成来源","FULL ATTRIBUTES · VALUES & SOURCES"),Vector2(18,10),Vector2(736,36),21,MineStyle.AMBER)
	var scroll := _scroll(card,"BackpackAttributeScroll",Vector2(16,57),Vector2(740,417))
	var sheet := Sheet.new()
	scroll.add_child(sheet)
	var actor: Variant = room.get("player") if is_instance_valid(room) else null
	sheet.configure(Inspect.breakdown(Game.run.hero_id,Game.run.level,Game.run.loadout_snapshot,Game.run.equipment_snapshot,actor,Game.run.ruleset_version(),Game.hero_talents(Game.run.hero_id)),718,"BackpackAttribute_")
	if is_instance_valid(actor) and actor.get("loadout") != null:
		var modifiers: Dictionary = actor.get("loadout").call("modifiers")
		var names := {"damage_bonus":_t("触发伤害加成","Triggered damage bonus"),"crit_bonus":_t("触发暴击率","Triggered critical chance"),"attack_speed_bonus":_t("触发攻速加成","Triggered attack speed"),"move_speed_bonus":_t("触发移速加成","Triggered move speed"),"damage_reduction_bonus":_t("触发减伤加成","Triggered reduction"),"cost_reduction":_t("技能消耗减免","Skill cost reduction")}
		for key: String in names:
			if float(modifiers.get(key,0)) > 0: Details.flow(sheet,str(names[key])+"  %.1f%%" % (float(modifiers[key])*100),718,14,MineStyle.CYAN)
	for id: String in Game.run.relics:
		var relic: Dictionary = Relics.display(Game.run.hero_id,id,int(Game.run.stats.get("relic_levels",{}).get(id,1)),str(Game.run.expedition.get("biome_id","")), Game.run.ruleset_version())
		Details.flow(sheet,_t("本局遗物 · ","RUN RELIC · ")+MineStyle.content_text(relic,"name"),718,16,MineStyle.AMBER)
		Details.flow(sheet,MineStyle.content_text(relic,"description"),718,14)

func _apply(id: String, slot: String) -> void:
	if busy: return
	busy = true
	var result: Dictionary = Gear.apply(room,id,slot,checkpoint)
	busy = false
	if bool(result.get("success",false)):
		selected_id = id
		message = ""
		equipment_changed.emit()
	else: message = str(result.get("error",_t("换装失败。", "Equipment change failed.")))
	_render()

func _scroll(parent: Node, id: String, at: Vector2, extent: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = id
	scroll.position = at
	scroll.size = extent
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	parent.add_child(scroll)
	return scroll

func _flow_text(parent: Node, value: String, width: float, font_size: int = 15, tint: Color = MineStyle.INK) -> Label:
	var label := MineStyle.literal(parent,value,Vector2.ZERO,Vector2(width,0),font_size,tint)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _stat_name(key: String) -> String:
	for definition: Array in ATTRIBUTES:
		if str(definition[0]) == key: return _t(str(definition[1]),str(definition[2]))
	return Words.text("STAT_"+key.to_upper())

func _value(key: String, number: float) -> String:
	if key in RATIOS or key in ["attack_speed","damage_reduction"]: return "%.1f%%" % (number*100.0)
	if key == "attack_interval": return "%.3f s" % number
	return "%.1f" % number
