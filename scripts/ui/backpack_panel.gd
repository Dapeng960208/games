extends Control
const Traits = preload("res://scripts/ui/equipment_traits.gd")
## Paused parchment inventory. The owner supplies modal pause/input handling;
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
	_text(self, _t("远征行囊", "EXPEDITION BACKPACK"), Vector2(24,14), Vector2(350,40), 26, MineStyle.AMBER)
	var gear_tab := _button(self, "BackpackInventoryTab", _t("装备背包", "Equipment"), Vector2(485,16), Vector2(150,40), func(): tab = "inventory"; _render())
	var stat_tab := _button(self, "BackpackAttributesTab", _t("角色属性", "Attributes"), Vector2(646,16), Vector2(150,40), func(): tab = "stats"; _render())
	MineStyle.selected(gear_tab if tab == "inventory" else stat_tab)
	_button(self, "CloseBackpack", _t("关闭 · Esc", "Close · Esc"), Vector2(866,16), Vector2(170,40), close_callback)
	_identity()
	if tab == "inventory": _inventory(); _detail()
	else: _attributes()
	var phase := str(Game.run.expedition.get("phase", ""))
	var scope := _t("战斗中换装立即生效，清场后保存；本局掉落需成功撤离才永久入库。", "Combat swaps apply now and save when cleared; new loot joins your collection only after extraction.") if phase == "combat" else _t("配装立即保存，仅影响本次远征；本局掉落需成功撤离才永久入库。", "Changes save now for this expedition; new loot joins your collection only after extraction.")
	status_label = _text(self, message if not message.is_empty() else scope, Vector2(24,573), Vector2(1012,34), 14, MineStyle.RED if not message.is_empty() else MineStyle.MUTED)
	status_label.max_lines_visible = 2
	status_label.tooltip_text = scope

func _identity() -> void:
	var hero: Dictionary = ContentRegistry.hero(Game.run.hero_id)
	var card := MineStyle.panel(self, Vector2(20,69), Vector2(228,493))
	card.name = "BackpackEquippedSlots"
	MineStyle.hero_portrait(card, Game.run.hero_id, Vector2(12,8), Vector2(65,78))
	_text(card, MineStyle.content_text(hero,"name")+" · Lv."+str(Game.run.level), Vector2(84,16), Vector2(133,30), 20)
	_text(card, MineStyle.content_text(hero,"class_name"), Vector2(84,49), Vector2(133,35), 14, MineStyle.CYAN)
	for index: int in SLOTS.size():
		var slot: String = SLOTS[index]
		var id := str(Game.run.loadout_snapshot.get(slot, ""))
		var item: Dictionary = ContentRegistry.equipment(id)
		var at := Vector2(10+(index%2)*107,102+(index/2)*74)
		var cell := _button(card, "BackpackSlot_"+slot, "", at, Vector2(100,66), func(): filter = slot; selected_slot = slot; selected_id = id; message = ""; _render())
		MineStyle.button_skin(cell,"socket")
		if filter == slot: MineStyle.selected(cell,"socket")
		MineStyle.equipment_icon(cell, item if not item.is_empty() else {"slot":slot}, Vector2(3,2), Vector2(52,52))
		_text(cell, _slot_name(slot), Vector2(54,8), Vector2(44,22), 12, MineStyle.MUTED)
		var level := int(Game.run.equipment_snapshot.get(id, {}).get("level", 0))
		_text(cell, "+"+str(level) if not id.is_empty() else _t("空槽", "Empty"), Vector2(53,31), Vector2(44,22), 15, MineStyle.AMBER)
		cell.tooltip_text = MineStyle.content_text(item,"name",_t("该槽位尚无实装装备", "Equipment for this slot is not yet implemented"))
		if not slot in Registry.SLOTS: cell.modulate = Color(1,1,1,.6)
	var hp := _text(card, _t("生命 ", "Health ")+"%d / %d" % [ceili(Game.run.hp), ceili(Game.run.max_hp)], Vector2(14,410), Vector2(200,25), 15)
	hp.name = "BackpackHealth"
	var bar := MineStyle.meter(card, Vector2(14,439), Vector2(200,6), MineStyle.RED)
	bar.max_value = Game.run.max_hp; bar.value = Game.run.hp
	_text(card, MineStyle.content_text(hero,"resource_name")+"  %d / %d" % [ceili(Game.run.resource),ceili(float(Game.run.stats.resource_max))], Vector2(14,453), Vector2(200,25), 14, MineStyle.CYAN)

func _inventory() -> void:
	var card := MineStyle.panel(self, Vector2(260,69), Vector2(315,493))
	card.name = "BackpackOwnedInventory"
	var items := Gear.available(Game)
	var shown: Array[Dictionary] = []
	for item: Dictionary in items:
		if filter == "all" or str(item.slot) == filter: shown.append(item)
	_text(card, (_t("已拥有装备", "Owned equipment") if filter == "all" else _slot_name(filter))+" · "+str(shown.size()), Vector2(12,12), Vector2(205,27), 18, MineStyle.AMBER)
	_button(card, "BackpackAllItems", _t("全部", "All"), Vector2(230,7), Vector2(72,38), func(): filter = "all"; _render())
	var scroll := _scroll(card, "BackpackItemScroll", Vector2(10,52), Vector2(295,428))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if shown.is_empty():
		_flow_text(list, _t("此槽位暂无装备。裤子与戒指保留为后续装备扩展槽位。", "No owned gear for this slot. Legs and rings are reserved for future equipment."), 278, 15, MineStyle.MUTED)
	for entry: Dictionary in shown:
		var id: String = entry.id
		var data: Dictionary = ContentRegistry.equipment(id)
		var row := _button(list, "BackpackItem_"+id, "", Vector2.ZERO, Vector2(278,82), func(): selected_id = id; selected_slot = str(data.slot); message = ""; _render())
		row.custom_minimum_size = Vector2(278,82)
		row.clip_contents = true
		MineStyle.button_skin(row,"card")
		if selected_id == id: MineStyle.selected(row,"card")
		MineStyle.equipment_icon(row, data, Vector2(4,6), Vector2(67,67))
		var title := _text(row, MineStyle.content_text(data,"name"), Vector2(77,8), Vector2(188,40), 16)
		title.max_lines_visible = 2
		var badge := _t("已穿戴", "Equipped") if bool(entry.equipped) else (_t("本局掉落", "Run loot") if bool(entry.pending) else _t("已入库", "Secured"))
		_text(row, badge+" · "+_slot_name(str(entry.slot))+" +"+str(entry.level), Vector2(77,54), Vector2(188,22), 12, MineStyle.CYAN if bool(entry.equipped) else MineStyle.AMBER)
		row.tooltip_text = MineStyle.content_text(data,"name")+"\n"+MineStyle.content_text(data,"affix_text")

func _detail() -> void:
	detail_root = MineStyle.panel(self, Vector2(587,69), Vector2(453,493))
	detail_root.name = "BackpackItemDetails"
	if not selected_slot in Registry.SLOTS:
		_text(detail_root, _slot_name(selected_slot), Vector2(18,16), Vector2(417,32), 22, MineStyle.AMBER)
		_text(detail_root, _t("此槽位为后续装备扩展预留，目前没有可穿戴物品。", "This slot is reserved for future equipment; no items are available yet."), Vector2(18,65), Vector2(417,100), 16, MineStyle.MUTED)
		return
	var comparison := Gear.preview(Game, selected_id, selected_slot)
	if comparison.is_empty(): return
	var data: Dictionary = ContentRegistry.equipment(selected_id)
	var current: Dictionary = ContentRegistry.equipment(str(comparison.current_id))
	MineStyle.equipment_icon(detail_root, data if not data.is_empty() else {"slot":selected_slot}, Vector2(13,13), Vector2(96,96))
	var title := _text(detail_root, MineStyle.content_text(data,"name",_t("未装备", "Unequipped")), Vector2(119,15), Vector2(318,49), 21)
	title.max_lines_visible = 2
	var metadata := _slot_name(selected_slot)+" · +"+str(comparison.level)
	if not data.is_empty(): metadata += " · "+MineStyle.content_text(data,"race_name")
	_text(detail_root, metadata, Vector2(119,71), Vector2(318,42), 14, MineStyle.AMBER).max_lines_visible = 2
	var scroll := _scroll(detail_root, "BackpackComparisonScroll", Vector2(16,122), Vector2(421,301))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	_flow_text(list, _t("当前槽位：", "Current slot: ")+MineStyle.content_text(current,"name",_t("未装备", "Unequipped")), 399, 14, MineStyle.MUTED)
	if not data.is_empty():
		var origin := _t("本局掉落 · 撤离后入库", "Run loot · extract to secure") if bool(comparison.pending) else _t("永久仓库 · 本局可用", "Permanent collection · available this run")
		_flow_text(list, origin, 399, 14, MineStyle.CYAN)
		var traits := Traits.new()
		list.add_child(traits)
		traits.configure(data, int(comparison.level), 399, Game.run.hero_id)
	_flow_text(list, _t("角色属性 · 当前 → 更换后", "Character values · current → equipped"), 399, 17, MineStyle.CYAN)
	var changed := false
	for definition: Array in ATTRIBUTES:
		var key: String = definition[0]
		var before := float(comparison.current_stats.get(key,0.0))
		var after := float(comparison.next_stats.get(key,0.0))
		if is_equal_approx(before,after): continue
		changed = true
		var gain := after < before if key == "attack_interval" else after > before
		_flow_text(list, _stat_name(key)+"  "+_value(key,before)+" → "+_value(key,after), 399, 15, MineStyle.GREEN if gain else MineStyle.RED)
	if not changed: _flow_text(list, _t("基础属性不变，请比较词条与套装效果。", "Base values unchanged; compare affixes and set effects."),399,15,MineStyle.MUTED)
	_set_changes(list, comparison.current_stats, comparison.next_stats)
	var advice: Array[String] = Advice.summarize(Game.run.hero_id, comparison.current_stats, comparison.next_stats)
	for line: String in advice: _flow_text(list, line, 399, 14, MineStyle.CYAN)
	var wearing: bool = selected_id == str(comparison.current_id) and int(comparison.level) == int(Game.run.equipment_snapshot.get(selected_id, {}).get("level",0))
	var equip_text := _t("选择一件装备", "Select equipment") if selected_id.is_empty() else (_t("已穿戴", "Equipped") if wearing else _t("穿戴 · 立即生效", "Equip · apply now"))
	var equip := _button(detail_root, "BackpackEquip", equip_text, Vector2(16,437), Vector2(283,44), func(): _apply(selected_id,selected_slot))
	MineStyle.primary(equip)
	equip.disabled = busy or wearing or selected_id.is_empty()
	var remove := _button(detail_root, "BackpackUnequip", _t("脱下", "Unequip"), Vector2(310,437), Vector2(127,44), func(): _apply("",selected_slot))
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
	var card := MineStyle.panel(self, Vector2(260,69), Vector2(780,493))
	card.name = "BackpackCharacterAttributes"
	_text(card, _t("完整属性 · 基础 + 装备 / 当前战斗值", "Full attributes · base + gear / current combat"), Vector2(18,10), Vector2(744,36), 20, MineStyle.AMBER)
	var scroll := _scroll(card, "BackpackAttributeScroll", Vector2(16,57), Vector2(748,417))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var base: Dictionary = StatResolver.resolve(Game.run.hero_id, Game.run.level, {}, {})
	var actor: Node = room.get("player") if is_instance_valid(room) else null
	for definition: Array in ATTRIBUTES:
		var key: String = definition[0]
		var value := float(Game.run.stats.get(key,0.0))
		var live := float(actor.call("stat",key,value)) if is_instance_valid(actor) else value
		var basis := float(base.get(key,0.0))
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(726,34)
		list.add_child(row)
		var label := _flow_text(row,_stat_name(key),240,16)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var source := _flow_text(row,_value(key,basis)+" + "+_value(key,value-basis),235,14,MineStyle.MUTED)
		source.tooltip_text = _t("角色基础（含等级） + 装备贡献；条件词条不计入固定属性。", "Hero base (including level) + gear; conditional affixes are not constant stats.")
		source.mouse_filter = Control.MOUSE_FILTER_PASS
		var current := _flow_text(row,_value(key,live),145,18,MineStyle.CYAN if not is_equal_approx(live,value) else MineStyle.INK)
		current.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		current.name = "BackpackAttribute_"+key
	_flow_text(list,_t("条件触发效果、遗物与信标加成以实战触发为准，未发生的条件不会折算成常驻攻击力。", "Conditional affixes, relics and beacon bonuses depend on combat triggers; inactive conditions are not counted as constant attack."),726,14,MineStyle.MUTED)
	if is_instance_valid(actor) and actor.get("loadout") != null:
		var modifiers: Dictionary = actor.get("loadout").call("modifiers")
		var modifier_names := {"damage_bonus":_t("装备临时伤害加成", "Temporary gear damage bonus"),"crit_bonus":_t("临时暴击率加成", "Temporary critical bonus"),"attack_speed_bonus":_t("临时攻速加成", "Temporary attack speed"),"move_speed_bonus":_t("临时移速加成", "Temporary movement speed"),"damage_reduction_bonus":_t("临时减伤加成", "Temporary reduction"),"slow_resistance":_t("减速抵抗", "Slow resistance"),"cost_reduction":_t("技能消耗减免", "Skill cost reduction")}
		for key: String in modifier_names:
			var amount := float(modifiers.get(key,0.0))
			if amount > 0.0: _flow_text(list,str(modifier_names[key])+"  %.1f%%" % (amount*100.0),726,15,MineStyle.CYAN)
	_set_changes(list,Game.run.stats,Game.run.stats)
	var hero: Dictionary = ContentRegistry.hero(Game.run.hero_id)
	var passive: Dictionary = hero.get("passive", {})
	_flow_text(list,_t("角色被动 · ", "Hero passive · ")+MineStyle.content_text(passive,"name"),726,18,MineStyle.AMBER)
	_flow_text(list,MineStyle.content_text(passive,"description"),726,15)

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
