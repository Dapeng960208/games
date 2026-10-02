extends Control
## A single cleared-room drop, compared against the committed run loadout.
## The owner captures the checkpoint and commits the decision through Game.
signal choice_requested(decision: String)

const Advice = preload("res://scripts/ui/equipment_advice.gd")
const Traits = preload("res://scripts/ui/equipment_traits.gd")
const Details = preload("res://scripts/ui/equipment_details.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const MAJOR_STATS := ["attack", "ability_power", "max_hp", "armor", "magic_resist"]
const OTHER_STATS := ["attack_interval", "move_speed", "resource_max", "armor_penetration", "magic_penetration", "true_damage_bonus", "crit_chance", "crit_multiplier", "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration"]
const RATIO_STATS := ["crit_chance", "crit_multiplier", "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration"]
var preview: Dictionary = {}
var selected_decision := "keep"
var busy := false
var equip_button: Button
var keep_button: Button
var scrolls: Array[ScrollContainer] = []

func configure(comparison: Dictionary) -> void:
	preview = comparison.duplicate(true)
	_build()

func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _build() -> void:
	MineStyle.literal(self, _t("战利品对比", "EQUIPMENT LOOT"), Vector2(24,16), Vector2(932,36), 28, MineStyle.AMBER)
	var is_demo: bool = Game.run != null and bool(Game.run.get("demo"))
	var rule := _t("仅在本次试玩中试装。试玩结束后恢复正式配装；包括撤离带回的装备，都不会进入正式库存。", "Fit gear only for this trial. Your regular loadout returns afterward; even extracted trial loot never enters your progression inventory.") if is_demo else _t("现在换上，仅在本局生效。无论是否装备，新装备都留在战利品中，成功撤离后才永久入库。", "Equip for this run. Either choice keeps the drop as loot; extract successfully to add it to your collection.")
	var rule_label := MineStyle.literal(self, rule, Vector2(24,57), Vector2(932,40), 16, MineStyle.MUTED)
	rule_label.name = "FieldEquipmentScope"
	MineStyle.literal(self, _t("基础值对比 · 触发收益见词条 · Tab 切换 / ↑↓ 滚动", "Base values · Triggered benefits: affixes · Tab / ↑↓"), Vector2(330,26), Vector2(626,22), 13, MineStyle.MUTED)
	var slot := str(preview.get("slot", ""))
	var current: Dictionary = Game.equipment_definition(str(preview.get("current_id", "")),true)
	var candidate: Dictionary = Game.equipment_definition(str(preview.get("equipment_id", "")),true)
	_equipment_card("FieldCurrentEquipment", current, slot, Vector2(24,105), false, int(preview.get("current_level", 0)))
	_equipment_card("FieldNextEquipment", candidate, slot, Vector2(498,105), true, int(preview.get("level", 0)))
	_build_stats()
	_build_sets(current, candidate)
	_build_advice()
	equip_button = MineStyle.button(self, "", Vector2(24,558), Vector2(458,44), func(): _submit("equip"))
	equip_button.name = "FieldEquipNow"
	equip_button.text = _t("拾取并装备 · 本局生效", "Collect & equip · this run")
	equip_button.add_theme_font_size_override("font_size", 19)
	keep_button = MineStyle.button(self, "", Vector2(498,558), Vector2(458,44), func(): _submit("keep"))
	keep_button.name = "FieldKeepCurrent"
	keep_button.text = _t("拾取至行囊 · 保持当前装备", "Pack loot · keep current")
	keep_button.add_theme_font_size_override("font_size", 19)
	MineStyle.primary(keep_button, MineStyle.CYAN)
	_link_focus()
	keep_button.grab_focus()

func _equipment_card(node_name: String, item: Dictionary, slot: String, at: Vector2, incoming: bool, equipment_level: int = 0) -> void:
	var card := MineStyle.panel(self, at, Vector2(458,250))
	card.name = node_name
	card.clip_contents = true
	var accent := MineStyle.AMBER if incoming else MineStyle.CYAN
	card.add_theme_stylebox_override("panel",MineStyle.box(MineStyle.PAPER_LIGHT.lerp(accent,0.05),accent.lightened(0.32),1))
	var icon := MineStyle.equipment_icon(card, item if not item.is_empty() else {"slot":slot}, Vector2(12,17), Vector2(112,112))
	icon.name = "FieldEquipmentIcon"
	MineStyle.literal(card, _t("新获得", "NEW DROP") if incoming else _t("当前装备", "CURRENT"), Vector2(140,9), Vector2(304,22), 14, accent)
	var item_name := MineStyle.content_text(item, "name", _t("空槽位", "Empty slot"))
	var title := MineStyle.literal(card, item_name, Vector2(140,36), Vector2(304,56), 20,Inspect.rarity_color(item))
	title.name = "FieldEquipmentName"
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = item_name
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	var set_id := str(item.get("set_id", ""))
	var set_data: Dictionary = ContentRegistry.sets().get(set_id, {})
	var metadata := Words.text("SLOT_" + slot.to_upper())
	if not Inspect.rarity(item).is_empty(): metadata = Inspect.rarity_label(item)+" · "+metadata
	if equipment_level > 0: metadata += _t(" · 强化 +", " · Refined +")+str(equipment_level)
	if not set_id.is_empty():
		metadata += " · " + MineStyle.content_text(set_data, "name", set_id)
	var detail := MineStyle.literal(card, metadata, Vector2(140,101), Vector2(304,23), 14, accent)
	detail.autowrap_mode = TextServer.AUTOWRAP_OFF
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.tooltip_text = metadata
	detail.mouse_filter = Control.MOUSE_FILTER_PASS
	var scroll := _scroll(card, "FieldNextAffix" if incoming else "FieldCurrentAffix", Vector2(14,132), Vector2(430,106))
	if item.is_empty():
		_scroll_label(scroll, _t("无装备词条", "No equipment affix"), 404, 15, MineStyle.MUTED)
	else:
		if item.get("instance_record") is Dictionary:
			var details := Details.new()
			scroll.add_child(details)
			details.configure(item,equipment_level,404,Game.run.hero_id,preview.get("current_stats",{}),preview.get("next_stats",{}))
		else:
			var traits := Traits.new()
			scroll.add_child(traits)
			traits.configure(item, equipment_level, 404, Game.run.hero_id, true)

func _build_stats() -> void:
	MineStyle.literal(self, _t("本局基础属性 · 当前 → 更换后", "BASE STATS · CURRENT → EQUIPPED"), Vector2(24,363), Vector2(458,26), 17, MineStyle.CYAN)
	var scroll := _scroll(self, "FieldStatChanges", Vector2(24,393), Vector2(458,88))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	var before: Dictionary = preview.get("current_stats", {})
	var after: Dictionary = preview.get("next_stats", {})
	var changed: Array[String] = []
	var unchanged: Array[String] = []
	for key: String in MAJOR_STATS + OTHER_STATS:
		if not is_equal_approx(float(before.get(key, 0.0)), float(after.get(key, 0.0))):
			changed.append(key)
		elif MAJOR_STATS.has(key):
			unchanged.append(key)
	for key: String in changed + unchanged:
		var old := float(before.get(key, 0.0))
		var next := float(after.get(key, 0.0))
		var delta := next - old
		var improved := delta < 0.0 if key == "attack_interval" else delta > 0.0
		var tint := MineStyle.MUTED if is_zero_approx(delta) else (MineStyle.GREEN if improved else MineStyle.RED)
		var row := HBoxContainer.new()
		row.name = "FieldStat_" + key
		row.add_theme_constant_override("separation", 4)
		list.add_child(row)
		var caption := _cell(row, Words.text("STAT_" + key.to_upper()), 169, 15, MineStyle.INK)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cell(row, _value(key, old), 62, 15, MineStyle.MUTED)
		_cell(row, "→", 18, 15, MineStyle.MUTED)
		_cell(row, _value(key, next), 62, 15, tint)
		_cell(row, ("+" if delta > 0.0 else "") + _value(key, delta), 75, 15, tint)

func _cell(parent: Node, text: String, width: float, font_size: int, tint: Color) -> Label:
	var label := MineStyle.literal(parent, text, Vector2.ZERO, Vector2(width,22), font_size, tint)
	label.custom_minimum_size = Vector2(width,22)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label

func _value(key: String, value: float) -> String:
	if int(preview.get("next_stats",{}).get("ruleset_version",1)) == 2:
		return Inspect.value(key,value,false,false,2)
	if key == "attack_interval":
		return "%.3fs" % value
	if key in RATIO_STATS:
		return "%.1f%%" % (value * 100.0)
	return "%.1f" % value

func _build_sets(current: Dictionary, candidate: Dictionary) -> void:
	MineStyle.literal(self, _t("套装档位 · 更换后变化", "SET TIERS · AFTER EQUIPPING"), Vector2(498,363), Vector2(458,26), 17, MineStyle.AMBER)
	var scroll := _scroll(self, "FieldSetChanges", Vector2(498,393), Vector2(458,88))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	var before: Dictionary = preview.get("current_stats", {}).get("sets", {})
	var after: Dictionary = preview.get("next_stats", {}).get("sets", {})
	var affected: Array[String] = []
	for item: Dictionary in [current, candidate]:
		var set_id := str(item.get("set_id", ""))
		if not set_id.is_empty() and not affected.has(set_id):
			affected.append(set_id)
	if affected.is_empty():
		_scroll_label(list, _t("此替换不影响套装档位。", "This swap does not affect set tiers."), 432, 15, MineStyle.MUTED)
	for set_id: String in affected:
		var definition: Dictionary = ContentRegistry.sets().get(set_id, {})
		var old := int(before.get(set_id, 0))
		var next := int(after.get(set_id, 0))
		_scroll_label(list, MineStyle.content_text(definition, "name", set_id) + " · %d → %d" % [old, next] + _t(" 件", " pieces"), 432, 15, MineStyle.INK)
		# Put gained/lost tiers first so consequential changes are visible before
		# the scrollable descriptions of retained or still inactive tiers.
		var thresholds: Array[int] = []
		for tier: int in [2,4,6]:
			if (old >= tier) != (next >= tier): thresholds.append(tier)
		for tier: int in [2,4,6]:
			if not thresholds.has(tier): thresholds.append(tier)
		for tier: int in thresholds:
			var gained := old < tier and next >= tier
			var lost := old >= tier and next < tier
			var tag := _t("+ 激活", "+ Gained") if gained else (_t("− 失去", "− Lost") if lost else (_t("● 保留", "● Active") if next >= tier else _t("○ 未激活", "○ Inactive")))
			var tint := MineStyle.GREEN if gained else (MineStyle.RED if lost else MineStyle.MUTED)
			var effect: Dictionary = definition.get("thresholds", {}).get(str(tier), {})
			_scroll_label(list, tag + " · " + str(tier) + _t(" 件：", " pieces: ") + MineStyle.content_text(effect, "text"), 432, 14, tint)

func _build_advice() -> void:
	var summary := Control.new()
	summary.name = "FieldEquipmentAdvice"
	summary.position = Vector2(24,482)
	summary.size = Vector2(932,66)
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary)
	var before: Dictionary = preview.get("current_stats",{})
	var after: Dictionary = preview.get("next_stats",{})
	var hero := str(before.get("hero_id",Game.run.hero_id if Game.run != null else "CH01"))
	var lines: Array[String] = Advice.summarize(hero,before,after)
	var loses_set := not Advice.lost_tiers(before,after).is_empty()
	for index in mini(lines.size(),3):
		var label := MineStyle.literal(summary,lines[index],Vector2(0,index*22),Vector2(932,22),14,MineStyle.RED if index == 0 and loses_set else MineStyle.CYAN if index == 0 else MineStyle.INK)
		label.name = "FieldAdviceLine"+str(index)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _scroll(parent: Node, node_name: String, at: Vector2, extent: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.position = at
	scroll.size = extent
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	scroll.add_theme_stylebox_override("focus", MineStyle.box(Color(0,0,0,0), MineStyle.CYAN, 1))
	parent.add_child(scroll)
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			scroll.scroll_vertical += 30 if event.is_action_pressed("ui_down") else -30
			scroll.accept_event())
	scrolls.append(scroll)
	return scroll

func _scroll_label(parent: Node, text: String, width: float, font_size: int, tint: Color) -> Label:
	var label := MineStyle.literal(parent, text, Vector2.ZERO, Vector2(width,0), font_size, tint)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _link_focus() -> void:
	var controls: Array[Control] = [keep_button, equip_button]
	for scroll: ScrollContainer in scrolls:
		controls.append(scroll)
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index - 1, controls.size())])
	equip_button.focus_neighbor_right = equip_button.get_path_to(keep_button)
	equip_button.focus_neighbor_left = equip_button.get_path_to(keep_button)
	keep_button.focus_neighbor_right = keep_button.get_path_to(equip_button)
	keep_button.focus_neighbor_left = keep_button.get_path_to(equip_button)

func _submit(decision: String) -> void:
	if busy:
		return
	selected_decision = decision
	set_busy(true)
	choice_requested.emit(decision)

func set_busy(value: bool) -> void:
	busy = value
	equip_button.disabled = value
	keep_button.disabled = value
	if not value:
		(equip_button if selected_decision == "equip" else keep_button).grab_focus()
