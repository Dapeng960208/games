extends RefCounted
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Grid = preload("res://scripts/ui/equipment_grid.gd")
const Details = preload("res://scripts/ui/equipment_details.gd")

static func render(panel: Control) -> void:
	var ids: Array = panel._filtered_equipment()
	if not ids.has(panel.selected_item): panel.selected_item = str(ids[0]) if not ids.is_empty() else ""
	_loadout(panel)
	var middle := MineStyle.panel(panel.body,Vector2(268,0),Vector2(442,510))
	var search := LineEdit.new()
	search.name = "EquipmentSearch"
	search.position = Vector2(14,12)
	search.size = Vector2(240,36)
	search.text = panel.search_query
	search.placeholder_text = Inspect.t("搜索名称 / 词条","Search name / affix")
	search.add_theme_font_size_override("font_size",15)
	search.add_theme_color_override("font_color",MineStyle.INK)
	search.add_theme_color_override("font_placeholder_color",MineStyle.MUTED)
	search.add_theme_stylebox_override("normal",MineStyle.box(MineStyle.PAPER_LIGHT,MineStyle.COPPER,1))
	search.add_theme_stylebox_override("focus",MineStyle.box(MineStyle.PAPER_LIGHT,MineStyle.CYAN,1))
	middle.add_child(search)
	search.text_changed.connect(func(value: String):
		panel.search_query = value; panel.list_scroll = 0; panel._render()
		var next := panel.find_child("EquipmentSearch",true,false) as LineEdit
		if next != null: next.grab_focus(); next.caret_column = value.length())
	var reset := MineStyle.button(middle,"",Vector2(264,9),Vector2(164,40),panel._toggle_catalog)
	reset.name = "ViewAllEquipment"
	reset.text = Inspect.t("清除筛选","Clear filters")
	reset.add_theme_font_size_override("font_size",14)
	var slots: Array = ["all"]+Game.equipment_slots()
	var slot_choice := _choice(middle,"EquipmentSlotFilter",Vector2(14,59),Vector2(202,38))
	for slot: String in slots: slot_choice.add_item(Words.text("ALL") if slot == "all" else Words.text("SLOT_"+slot.to_upper()))
	slot_choice.select(maxi(0,slots.find(panel.slot_filter)))
	slot_choice.item_selected.connect(func(index: int): panel.slot_filter = slots[index]; panel.list_scroll = 0; panel._render())
	var sets: Array = ["all"]+ContentRegistry.sets().keys()
	var set_choice := _choice(middle,"EquipmentSetFilter",Vector2(228,59),Vector2(200,38))
	for id: String in sets: set_choice.add_item(Inspect.t("全部套装","All sets") if id == "all" else MineStyle.content_text(ContentRegistry.sets()[id],"name"))
	set_choice.select(maxi(0,sets.find(panel.set_filter)))
	set_choice.item_selected.connect(func(index: int): panel.set_filter = sets[index]; panel.list_scroll = 0; panel._render())
	var scope := Inspect.t("商城目录","Shop catalog") if panel.mode == "shop" else Inspect.t("已拥有装备","Owned equipment")
	var fit := CheckButton.new()
	fit.name = "OnlyUsableEquipment"
	fit.position = Vector2(14,104)
	fit.size = Vector2(202,33)
	fit.text = Inspect.t("职业适配","Class fit")+" · "+str(ids.size())
	fit.button_pressed = panel.available_only
	fit.add_theme_font_size_override("font_size",13)
	fit.tooltip_text = scope+"\n"+Inspect.t("启用时只显示已解锁且适配当前职业的装备。","When enabled, show unlocked gear relevant to this hero.")
	middle.add_child(fit)
	fit.toggled.connect(func(enabled: bool): panel.available_only = enabled; panel.list_scroll = 0; panel._render())
	var sort := _choice(middle,"EquipmentSort",Vector2(228,104),Vector2(200,33))
	for text: String in [Inspect.t("按槽位排列","Sort by slot"),Inspect.t("按名称排列","Sort by name"),Inspect.t("按价格排列","Sort by price"),Inspect.t("按强化排列","Sort by refinement")]: sort.add_item(text)
	sort.select(panel.sort_order)
	sort.item_selected.connect(func(index: int): panel.sort_order = index; panel.list_scroll = 0; panel._render())
	var scroll := ScrollContainer.new()
	scroll.name = "EquipmentGridScroll"
	scroll.position = Vector2(14,147)
	scroll.size = Vector2(414,349)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	middle.add_child(scroll)
	panel.item_list = scroll
	var grid := Grid.new()
	grid.name = "EquipmentGrid"
	scroll.add_child(grid)
	grid.configure(394,4)
	for id: String in ids:
		var item: Dictionary = Game.equipment_definition(id)
		var equipped: bool = str(Game.profile.loadout.get(item.slot,"")) == id
		var owned: bool = Game.profile.equipment.has(id)
		var footer := Inspect.t("已穿戴","Equipped") if equipped else Inspect.t("已拥有","Owned") if owned else str(item.price)+Inspect.t(" 金"," gold")
		if owned: footer += " +"+str(Game.equipment_level(id))
		var cell := grid.add_item(item,Game.equipment_level(id),Game.profile.selected_hero,"Item_",panel.selected_item == id,footer,func(): panel.list_scroll = scroll.scroll_vertical; panel.selected_item = id; panel._render(),equipped)
		if not panel._unlocked(item): cell.modulate = Color(.85,.85,.85,.8)
		cell.tooltip_text += "\n"+panel._availability_reason(item)
	if ids.is_empty():
		var empty := MineStyle.literal(grid,Inspect.t("当前筛选没有装备。清除筛选可查看所有已拥有装备；新品在商城购买。","No matching gear. Clear filters to show owned items; buy new equipment in the shop."),Vector2.ZERO,Vector2(394,150),16,MineStyle.MUTED)
		empty.custom_minimum_size.x = 394
	scroll.set_deferred("scroll_vertical",panel.list_scroll)
	detail(panel)

static func _choice(owner: Node, id: String, at: Vector2, extent: Vector2) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = id
	choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	choice.position = at
	choice.size = extent
	choice.add_theme_font_size_override("font_size",14)
	choice.fit_to_longest_item = false
	choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	owner.add_child(choice)
	return choice

static func _loadout(panel: Control) -> void:
	var left := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(250,510))
	MineStyle.literal(left,Inspect.t("当前穿戴 · 八槽","EQUIPPED · EIGHT SLOTS") if Game.equipment_slots().size() == 8 else Inspect.t("当前穿戴 · 六槽","EQUIPPED · SIX SLOTS"),Vector2(16,13),Vector2(218,27),17,MineStyle.AMBER)
	for index: int in Game.equipment_slots().size():
		var slot: String = Game.equipment_slots()[index]
		var id := str(Game.profile.loadout.get(slot,""))
		var item: Dictionary = Game.equipment_definition(id)
		var button := MineStyle.button(left,"",Vector2(12,(48 if Game.equipment_slots().size() == 8 else 52)+index*(41 if Game.equipment_slots().size() == 8 else 55)),Vector2(226,39 if Game.equipment_slots().size() == 8 else 48),func(): panel.slot_filter = slot; panel.set_filter = "all"; panel.search_query = ""; panel.selected_item = id; panel.list_scroll = 0; panel._render())
		button.name = "Slot_"+slot
		MineStyle.button_skin(button,"socket")
		MineStyle.equipment_icon(button,item if not item.is_empty() else {"slot":slot},Vector2(1,-2),Vector2(40,40) if Game.equipment_slots().size() == 8 else Vector2(52,52)).name = "FittedEquipmentArt_"+slot
		MineStyle.literal(button,Words.text("SLOT_"+slot.to_upper())+" +"+str(Game.equipment_level(id)),Vector2(58,3),Vector2(160,17),12,MineStyle.AMBER)
		var label := MineStyle.literal(button,MineStyle.content_text(item,"name",Words.text("EMPTY_SLOT")),Vector2(58,18 if Game.equipment_slots().size() == 8 else 21),Vector2(160,21 if Game.equipment_slots().size() == 8 else 23),12 if Game.equipment_slots().size() == 8 else 14)
		label.name = "FittedEquipmentName_"+slot
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = Inspect.tooltip(item,Game.equipment_level(id),Game.profile.selected_hero) if not item.is_empty() else Words.text("EMPTY_SLOT")
	var suggestion: String = panel._suggested_equipment()
	var recommend := MineStyle.button(left,"",Vector2(12,388),Vector2(226,44),func(): panel.selected_item = suggestion; panel.slot_filter = str(Game.equipment_definition(suggestion).get("slot","all")); panel.list_scroll = 0; panel._render())
	recommend.name = "RecommendEquipment"
	recommend.text = Inspect.t("查看同槽建议","Slot suggestion") if not suggestion.is_empty() else Inspect.t("暂无同槽建议","No slot suggestion")
	recommend.add_theme_font_size_override("font_size",14)
	recommend.disabled = suggestion.is_empty()
	var stats: Dictionary = Game.selected_stats()
	MineStyle.literal(left,Inspect.t("生命 %.1f · 护甲 %.1f\n攻击 %.1f · 法强 %.1f","HP %.1f · Armor %.1f\nATK %.1f · Power %.1f") % [stats.max_hp,stats.armor,stats.attack,stats.ability_power],Vector2(16,444),Vector2(218,56),14,MineStyle.MUTED)

static func detail(panel: Control) -> void:
	var right := MineStyle.panel(panel.body,Vector2(728,0),Vector2(488,510))
	if str(panel.selected_item).is_empty():
		MineStyle.literal(right,Inspect.t("选择装备查看完整属性。","Select equipment to inspect every attribute."),Vector2(22,28),Vector2(444,90),19,MineStyle.MUTED)
		panel.action_button = null
		return
	var item: Dictionary = Game.equipment_definition(panel.selected_item)
	var owned: bool = Game.profile.equipment.has(panel.selected_item)
	var current_id := str(Game.profile.loadout.get(item.slot,""))
	var equipped: bool = current_id == panel.selected_item
	MineStyle.equipment_icon(right,item,Vector2(14,9),Vector2(78,78)).name = "CandidateEquipmentArt"
	var title := MineStyle.literal(right,MineStyle.content_text(item,"name"),Vector2(102,11),Vector2(367,53),21)
	title.max_lines_visible = 2
	title.tooltip_text = title.text
	var level: int = Game.equipment_level(panel.selected_item)
	if item.get("instance_record") is Dictionary:
		title.tooltip_text += "\niLv %d · %s · %s" % [int(item.instance_record.item_level),str(item.instance_record.rarity),str(item.instance_id)]
	MineStyle.literal(right,Words.text("SLOT_"+str(item.slot).to_upper())+" · +"+str(level)+" · "+(Inspect.t("已穿戴","Equipped") if equipped else Inspect.t("已拥有","Owned") if owned else Inspect.t("未拥有","Not owned")),Vector2(102,70),Vector2(367,26),14,MineStyle.AMBER)
	for index: int in 3:
		var key: String = ["stats","compare","set"][index]
		var tab := MineStyle.button(right,"",Vector2(14+index*154,105),Vector2(146,38),func(): panel.detail_tab = key; panel._render())
		tab.name = "EquipmentDetailTab_"+key
		tab.text = [Inspect.t("完整属性","Attributes"),Inspect.t("数值对比","Compare"),Inspect.t("套装效果","Set effects")][index]
		tab.add_theme_font_size_override("font_size",15)
		if panel.detail_tab == key: MineStyle.selected(tab)
	var scroll := ScrollContainer.new()
	scroll.name = "EquipmentDetails"
	scroll.position = Vector2(20,153)
	scroll.size = Vector2(448,274)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(scroll)
	var content := Details.new()
	scroll.add_child(content)
	var before: Dictionary = Game.selected_stats()
	var after: Dictionary = Game.preview_stats(panel.selected_item)
	if panel.mode == "upgrade" and owned: before = Game.preview_stats(panel.selected_item); after = Game.preview_upgrade_stats(panel.selected_item)
	content.configure(item,level,426,Game.profile.selected_hero,before,after,panel.detail_tab)
	var action := "EQUIP_ITEM"
	var note := Inspect.t("穿戴后使用预览数值。","Equip to use the previewed values.")
	var cost := int(item.price)
	var disabled: bool = panel.busy
	if panel.mode == "shop" and not owned:
		action = "BUY_ITEM"
		disabled = disabled or not panel._unlocked(item) or int(Game.profile.permanent_gold) < cost
		note = panel._availability_reason(item) if disabled else Inspect.t("购买后入库；可再选择穿戴。","Purchase adds it to inventory; equip separately.")
	elif panel.mode == "upgrade":
		action = "UPGRADE_ITEM"
		cost = Game.upgrade_cost(panel.selected_item)
		disabled = disabled or not owned or level >= 5 or not Game.upgrade_has_gain(panel.selected_item) or int(Game.profile.permanent_gold) < cost
		note = Inspect.t("强化已达上限或没有有效提升。","Refinement is capped or has no effective gain.") if level >= 5 or not Game.upgrade_has_gain(panel.selected_item) else Inspect.t("强化 +1：%d 金币；仅提高基础属性。","Refine +1: %d gold; increases base stats only.") % cost
		if int(Game.profile.permanent_gold) < cost: note = Inspect.t("金币不足。","Not enough gold.")
	elif equipped:
		action = "ITEM_EQUIPPED"
		disabled = true
		note = Inspect.t("当前已穿戴 · 可在强化页提升。","Currently equipped · Refine on the upgrade page.")
	if item.get("instance_record") is Dictionary and not equipped and not preload("res://scripts/core/equipment_instances.gd").can_equip(item.instance_record,Game.profile.selected_hero,Game.hero_level()):
		disabled = true
		note = Inspect.t("职业类型或装备等级不符合。","Class type or item level requirement is not met.")
	var pending_claim: bool = owned and item.get("instance_record",{}).get("location","") == "pending"
	if pending_claim and panel.mode == "inventory":
		action = "CLAIM_INSTANCE"
		disabled = panel.busy
		note = Inspect.t("待领取物品仍归你所有；背包有空间时可领取。","This item is retained; collect it when inventory space is available.")
	MineStyle.literal(right,note,Vector2(20,433),Vector2(448,29),13,MineStyle.MUTED)
	panel.action_button = MineStyle.button(right,action,Vector2(20,465),Vector2(448,36),panel._commit_item)
	panel.action_button.name = "PrimaryAction"
	MineStyle.primary(panel.action_button)
	panel.action_button.disabled = disabled
	if action == "CLAIM_INSTANCE": panel.action_button.text = Inspect.t("领取到背包","Collect to inventory")
	if action in ["BUY_ITEM","UPGRADE_ITEM"]: panel.action_button.text += " · "+str(cost)
