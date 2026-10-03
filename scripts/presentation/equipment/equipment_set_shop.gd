extends RefCounted
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Details = preload("res://scripts/presentation/equipment/equipment_details.gd")
## Painted set catalogue; all purchases/equips use the durable Game APIs.

static func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func _label(parent: Control, text: String, at: Vector2, extent: Vector2, font_size: int = 16, tint: Color = GameStyle.INK) -> Label:
	var label := GameStyle.literal(parent,text,at,extent,font_size,tint)
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label

static func render(panel: Control) -> void:
	var left := GameStyle.panel(panel.body,Vector2.ZERO,Vector2(834,510))
	_label(left,_t("六件成套 · 缺件九折 · 可单独购买", "SIX PIECES · 10% OFF MISSING PIECES"),Vector2(18,10),Vector2(798,28),16,GameStyle.AMBER)
	var scroll := ScrollContainer.new()
	scroll.name = "SetCatalog"
	scroll.position = Vector2(12,48)
	scroll.size = Vector2(810,450)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	left.add_child(scroll)
	panel.item_list = scroll
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",10)
	scroll.add_child(grid)
	var ids: Array[String] = ["S09","S10","S11","S12","S13","S14","S01","S02","S03","S04","S05","S06","S07","S08"]
	for id: String in ids:
		var data: Dictionary = ContentRegistry.sets().get(id,{})
		var quote: Dictionary = Game.equipment_set_quote(id)
		var row := GameStyle.button(grid,"",Vector2.ZERO,Vector2(256,140),func(): panel.set_scroll = scroll.scroll_vertical; panel.selected_set = id; panel._render())
		row.name = "Set_"+id
		row.custom_minimum_size = Vector2(256,140)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if id == panel.selected_set: GameStyle.selected(row,"card")
		var heading := _label(row,GameStyle.content_text(data,"name"),Vector2(12,9),Vector2(232,25),19)
		heading.autowrap_mode = TextServer.AUTOWRAP_OFF
		heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label(row,GameStyle.content_text(data,"shop_role",GameStyle.content_text(data,"status_name")),Vector2(12,36),Vector2(232,22),13,GameStyle.CYAN)
		for i in range(quote.items.size()):
			GameStyle.equipment_icon(row,ContentRegistry.equipment(quote.items[i]),Vector2(8+i*40,61),Vector2(40,40))
		var state := _t("已拥有 %d/6 · %d 金币", "%d/6 owned · %d gold") % [int(quote.owned),int(quote.price)]
		if quote.missing.is_empty(): state = _t("已集齐 · 可一键穿戴", "Complete · Equip all six")
		elif not str(quote.locked_boss).is_empty(): state = _t("首领解锁 · 已拥有 %d/6", "Boss unlock · %d/6 owned") % int(quote.owned)
		_label(row,state,Vector2(12,109),Vector2(232,24),13,GameStyle.AMBER)
	scroll.set_deferred("scroll_vertical",panel.set_scroll)
	_detail(panel)

static func _detail(panel: Control) -> void:
	var data: Dictionary = ContentRegistry.sets().get(panel.selected_set,{})
	var quote: Dictionary = Game.equipment_set_quote(panel.selected_set)
	var detail := GameStyle.panel(panel.body,Vector2(850,-80),Vector2(366,590))
	_label(detail,GameStyle.content_text(data,"name"),Vector2(18,10),Vector2(330,36),26)
	_label(detail,GameStyle.content_text(data,"shop_role",GameStyle.content_text(data,"status_name")),Vector2(18,45),Vector2(330,25),16,GameStyle.CYAN)
	for i in range(quote.items.size()):
		var item: Dictionary = ContentRegistry.equipment(quote.items[i])
		var at := Vector2(18+(i%3)*112,79+(i/3)*89)
		var button := GameStyle.button(detail,"",at,Vector2(106,83),func(): panel.shop_sets = false; panel.available_only = false; panel.slot_filter = "all"; panel.set_filter = "all"; panel.search_query = ""; panel.detail_tab = "stats"; panel.selected_item = str(item.id); panel._render())
		GameStyle.button_skin(button,"socket")
		button.name = "SetPiece_"+str(item.id)
		button.tooltip_text = Inspect.tooltip(item,Game.equipment_level(item.id),Game.profile.selected_hero)
		GameStyle.equipment_icon(button,item,Vector2(26,1),Vector2(54,54))
		_label(button,Words.text("SLOT_"+str(item.slot).to_upper()),Vector2(2,55),Vector2(102,15),11,GameStyle.AMBER).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label(button,_t("已拥有", "Owned") if Game.profile.equipment.has(item.id) else _t("缺少", "Missing"),Vector2(2,68),Vector2(102,14),10,GameStyle.GREEN if Game.profile.equipment.has(item.id) else GameStyle.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index: int in 2:
		var key: String = ["set","compare"][index]
		var toggle := GameStyle.button(detail,"",Vector2(18+index*170,270),Vector2(162,32),func(): panel.set_detail_tab = key; panel._render())
		toggle.name = "SetDetailTab_"+key
		toggle.text = _t("套装效果", "Set effects") if key == "set" else _t("整套属性对比", "Full set comparison")
		toggle.add_theme_font_size_override("font_size",15)
		toggle.custom_minimum_size.y = 32
		GameStyle.tab(toggle,panel.set_detail_tab == key)
	var effects := ScrollContainer.new()
	effects.name = "SetEffects"
	effects.position = Vector2(18,314)
	effects.size = Vector2(330,181)
	effects.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	effects.focus_mode = Control.FOCUS_ALL
	detail.add_child(effects)
	var count := int(Game.selected_stats().get("sets",{}).get(panel.selected_set,0))
	var content := Details.new()
	effects.add_child(content)
	var preview := Inspect.set_preview(panel.selected_set,Game.profile.selected_hero,Game.hero_level(),Game.profile.loadout,Game.profile.equipment)
	content.configure({"set_id":panel.selected_set},0,308,Game.profile.selected_hero,Game.selected_stats(),preview,panel.set_detail_tab)
	var note := _t("缺件 %d/6 · 原价 %d → 九折 %d 金币", "%d/6 missing · %d → %d gold (10%% off)") % [quote.missing.size(),int(quote.full_price),int(quote.price)]
	var complete: bool = quote.missing.is_empty()
	var fitted := count == 6
	var disabled: bool = panel.busy or (complete and fitted) or not str(quote.locked_boss).is_empty() or (not complete and int(quote.price) > int(Game.profile.permanent_gold))
	if complete: note = _t("已集齐六件 · 穿戴会替换当前六个槽位", "Complete · Equipping replaces all six slots")
	elif not str(quote.locked_boss).is_empty(): note = _t("击败首领解锁：", "Defeat to unlock: ")+str(quote.locked_boss)
	elif disabled: note += _t(" · 余额不足", " · Need more gold")
	_label(detail,note,Vector2(18,505),Vector2(330,38),14,GameStyle.MUTED)
	panel.action_button = GameStyle.button(detail,"",Vector2(18,550),Vector2(330,36),func(): _commit(panel,complete))
	panel.action_button.custom_minimum_size.y = 36
	panel.action_button.name = "PrimaryAction"
	GameStyle.primary(panel.action_button)
	panel.action_button.text = (_t("已穿戴整套", "Full set equipped") if fitted else _t("一键穿戴六件", "Equip all six pieces")) if complete else (_t("购买整套 · %d 金币", "Buy full set · %d gold") if int(quote.owned) == 0 else _t("补齐缺件 · %d 金币", "Complete set · %d gold")) % int(quote.price)
	panel.action_button.disabled = disabled

static func _commit(panel: Control, complete: bool) -> void:
	if panel.busy or panel.action_button.disabled: return
	panel.busy = true
	panel.action_button.disabled = true
	var success: bool = Game.equip_equipment_set(panel.selected_set) if complete else Game.buy_equipment_set(panel.selected_set)
	if not success:
		panel.busy = false
		panel._render()
		if not Game.last_error.is_empty(): panel.app._show_save_error()
		return
	await panel.get_tree().create_timer(0.3).timeout
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	panel.busy = false
	panel._render()
