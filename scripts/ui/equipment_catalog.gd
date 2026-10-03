extends RefCounted
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Grid = preload("res://scripts/ui/equipment_grid.gd")
const Details = preload("res://scripts/ui/equipment_details.gd")

static func render(panel: Control) -> void:
	var ids: Array = panel._filtered_equipment()
	if not ids.has(panel.selected_item): panel.selected_item = str(ids[0]) if not ids.is_empty() else ""
	_loadout(panel)
	var middle := MineStyle.panel(panel.body,Vector2(254,0),Vector2(580,510))
	var search := LineEdit.new()
	search.name = "EquipmentSearch"
	search.position = Vector2(14,12)
	search.size = Vector2(274,34)
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
	var reset := MineStyle.button(middle,"",Vector2(464,12),Vector2(102,34),panel._toggle_catalog)
	reset.custom_minimum_size.y = 34
	reset.name = "ViewAllEquipment"
	reset.text = Inspect.t("清除筛选","Reset")
	reset.add_theme_font_size_override("font_size",14)
	var slots: Array = ["all"]+Game.equipment_slots()
	var slot_choice := _choice(middle,"EquipmentSlotFilter",Vector2(14,54),Vector2(160,34))
	for slot: String in slots: slot_choice.add_item(Words.text("ALL") if slot == "all" else Words.text("SLOT_"+slot.to_upper()))
	slot_choice.select(maxi(0,slots.find(panel.slot_filter)))
	slot_choice.item_selected.connect(func(index: int): panel.slot_filter = slots[index]; panel.list_scroll = 0; panel._render())
	var sets: Array = ["all"]+ContentRegistry.sets().keys()
	var set_choice := _choice(middle,"EquipmentSetFilter",Vector2(184,54),Vector2(200,34))
	for id: String in sets: set_choice.add_item(Inspect.t("全部套装","All sets") if id == "all" else MineStyle.content_text(ContentRegistry.sets()[id],"name"))
	set_choice.select(maxi(0,sets.find(panel.set_filter)))
	set_choice.item_selected.connect(func(index: int): panel.set_filter = sets[index]; panel.list_scroll = 0; panel._render())
	var scope := Inspect.t("商城目录","Shop catalog") if panel.mode == "shop" else Inspect.t("已拥有装备","Owned equipment")
	var fit := CheckButton.new()
	fit.name = "OnlyUsableEquipment"
	fit.position = Vector2(300,12)
	fit.size = Vector2(156,34)
	fit.text = Inspect.t("职业适配","Class fit")+" · "+str(ids.size())
	fit.button_pressed = panel.available_only
	fit.add_theme_font_size_override("font_size",13)
	fit.tooltip_text = scope+"\n"+Inspect.t("启用时只显示已解锁且适配当前职业的装备。","When enabled, show unlocked gear relevant to this hero.")
	middle.add_child(fit)
	fit.toggled.connect(func(enabled: bool): panel.available_only = enabled; panel.list_scroll = 0; panel._render())
	var sort := _choice(middle,"EquipmentSort",Vector2(394,54),Vector2(172,34))
	for text: String in [Inspect.t("按槽位排列","Sort by slot"),Inspect.t("按名称排列","Sort by name"),Inspect.t("按价格排列","Sort by price"),Inspect.t("按强化排列","Sort by refinement")]: sort.add_item(text)
	sort.select(panel.sort_order)
	sort.item_selected.connect(func(index: int): panel.sort_order = index; panel.list_scroll = 0; panel._render())
	var scroll := ScrollContainer.new()
	scroll.name = "EquipmentGridScroll"
	scroll.position = Vector2(14,100)
	scroll.size = Vector2(552,398)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	middle.add_child(scroll)
	panel.item_list = scroll
	var grid := Grid.new()
	grid.name = "EquipmentGrid"
	scroll.add_child(grid)
	grid.configure(532,5)
	for id: String in ids:
		var item: Dictionary = panel._definition(id)
		var equipped: bool = str(Game.profile.loadout.get(item.slot,"")) == id
		var owned: bool = Game.profile.equipment.has(id)
		var footer := Inspect.t("已穿戴","Equipped") if equipped else Inspect.t("已拥有","Owned") if owned else str(item.price)+Inspect.t(" 金"," gold")
		if owned: footer += " +"+str(Game.equipment_level(id))
		var cell := grid.add_item(item,Game.equipment_level(id),Game.profile.selected_hero,"Item_",panel.selected_item == id,footer,func(): panel.list_scroll = scroll.scroll_vertical; panel.selected_item = id; panel._render(),equipped)
		if not panel._unlocked(item): cell.modulate = Color(.85,.85,.85,.8)
		cell.tooltip_text += "\n"+panel._availability_reason(item)
	if ids.is_empty():
		var empty := MineStyle.literal(grid,Inspect.t("当前筛选没有装备。清除筛选可查看所有已拥有装备；新品在商城购买。","No matching gear. Clear filters to show owned items; buy new equipment in the shop."),Vector2.ZERO,Vector2(532,150),16,MineStyle.MUTED)
		empty.custom_minimum_size.x = 532
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
	var left := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(238,510))
	left.name = "EquippedLoadout"
	MineStyle.literal(left,Inspect.t("当前穿戴","EQUIPPED"),Vector2(14,10),Vector2(210,24),16,MineStyle.MUTED)
	var slots: Array = Game.equipment_slots()
	var row_height := 49 if slots.size() == 8 else 63
	for index: int in slots.size():
		var slot: String = slots[index]
		var id := str(Game.profile.loadout.get(slot,""))
		var item: Dictionary = panel._definition(id)
		var button := MineStyle.button(left,"",Vector2(10,40+index*row_height),Vector2(218,row_height-4),func(): panel.slot_filter = slot; panel.set_filter = "all"; panel.search_query = ""; panel.selected_item = id; panel.list_scroll = 0; panel._render())
		button.name = "Slot_"+slot
		button.custom_minimum_size = Vector2(218,row_height-4)
		MineStyle.button_skin(button,"socket")
		if panel.slot_filter == slot: MineStyle.selected(button,"socket")
		MineStyle.equipment_icon(button,item if not item.is_empty() else {"slot":slot},Vector2(1,-2),Vector2(48,48)).name = "FittedEquipmentArt_"+slot
		MineStyle.literal(button,Words.text("SLOT_"+slot.to_upper()),Vector2(55,3),Vector2(121,17),12,MineStyle.MUTED)
		var rank := MineStyle.literal(button,"+"+str(Game.equipment_level(id)),Vector2(179,12),Vector2(31,21),13,MineStyle.CYAN if panel.slot_filter == slot else MineStyle.AMBER)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var label := MineStyle.literal(button,MineStyle.content_text(item,"name",Words.text("EMPTY_SLOT")),Vector2(55,22),Vector2(126,21),12,Inspect.rarity_color(item))
		label.name = "FittedEquipmentName_"+slot
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = Inspect.tooltip(item,Game.equipment_level(id),Game.profile.selected_hero) if not item.is_empty() else Words.text("EMPTY_SLOT")
	var suggestion: String = panel._suggested_equipment()
	var recommend := MineStyle.button(left,"",Vector2(10,441),Vector2(218,32),func(): panel.selected_item = suggestion; panel.slot_filter = str(panel._definition(suggestion).get("slot","all")); panel.list_scroll = 0; panel._render())
	recommend.name = "RecommendEquipment"
	recommend.custom_minimum_size.y = 32
	recommend.text = Inspect.t("查看同槽建议","Slot suggestion") if not suggestion.is_empty() else Inspect.t("暂无同槽建议","No slot suggestion")
	recommend.add_theme_font_size_override("font_size",13)
	recommend.disabled = suggestion.is_empty()
	var stats: Dictionary = panel._selected_stats()
	var version := int(stats.get("ruleset_version",1))
	var summary := MineStyle.literal(left,Inspect.t("生命 %s · 护甲 %s","HP %s · Armor %s") % [Inspect.value("max_hp",stats.max_hp,false,false,version),Inspect.value("armor",stats.armor,false,false,version)],Vector2(14,482),Vector2(210,20),12,MineStyle.MUTED)
	summary.name = "LoadoutStatSummary"
	summary.tooltip_text = Inspect.t("攻击 %s · 法强 %s","ATK %s · Power %s") % [Inspect.value("attack",stats.attack,false,false,version),Inspect.value("ability_power",stats.ability_power,false,false,version)]

static func detail(panel: Control) -> void:
	var right := MineStyle.panel(panel.body,Vector2(850,-80),Vector2(366,590))
	if str(panel.selected_item).is_empty():
		MineStyle.literal(right,Inspect.t("选择装备查看完整属性。","Select equipment to inspect every attribute."),Vector2(22,28),Vector2(322,90),19,MineStyle.MUTED)
		panel.action_button = null
		return
	var item: Dictionary = panel._definition(panel.selected_item)
	var owned: bool = Game.profile.equipment.has(panel.selected_item)
	var current_id := str(Game.profile.loadout.get(item.slot,""))
	var equipped: bool = current_id == panel.selected_item
	MineStyle.equipment_icon(right,item,Vector2(125,8),Vector2(116,116)).name = "CandidateEquipmentArt"
	var title := MineStyle.literal(right,MineStyle.content_text(item,"name"),Vector2(18,125),Vector2(330,44),21,Inspect.rarity_color(item))
	title.max_lines_visible = 2
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = title.text
	var level: int = Game.equipment_level(panel.selected_item)
	if item.get("instance_record") is Dictionary:
		title.tooltip_text += "\niLv %d · %s · %s" % [int(item.instance_record.item_level),str(item.instance_record.rarity),str(item.instance_id)]
	var identity := Words.text("SLOT_"+str(item.slot).to_upper())+" · +"+str(level)+" · "+(Inspect.t("已穿戴","Equipped") if equipped else Inspect.t("已拥有","Owned") if owned else Inspect.t("未拥有","Not owned"))
	if not Inspect.rarity(item).is_empty(): identity = "Lv.%d · " % int(item.instance_record.item_level)+Inspect.rarity_label(item)+" · "+identity
	var identity_label := MineStyle.literal(right,identity,Vector2(18,171),Vector2(330,23),13,Inspect.rarity_color(item))
	identity_label.name = "CandidateRarity"
	identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index: int in 3:
		var key: String = ["stats","compare","set"][index]
		var tab := MineStyle.button(right,"",Vector2(14+index*114,201),Vector2(110,32),func(): panel.detail_tab = key; panel._render())
		tab.name = "EquipmentDetailTab_"+key
		tab.text = [Inspect.t("属性","Attributes"),Inspect.t("对比","Compare"),Inspect.t("套装","Set effects")][index]
		tab.add_theme_font_size_override("font_size",15)
		panel._nav_style(tab,panel.detail_tab == key)
	var scroll := ScrollContainer.new()
	scroll.name = "EquipmentDetails"
	scroll.position = Vector2(18,243)
	scroll.size = Vector2(330,270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	right.add_child(scroll)
	var content := Details.new()
	scroll.add_child(content)
	var before: Dictionary = panel._selected_stats()
	var after: Dictionary = Game.preview_stats(panel.selected_item)
	if panel.mode == "upgrade" and owned: before = Game.preview_stats(panel.selected_item); after = Game.preview_upgrade_stats(panel.selected_item)
	content.configure(item,level,308,Game.profile.selected_hero,before,after,panel.detail_tab)
	var action := "EQUIP_ITEM"
	var note := Inspect.t("穿戴后使用预览数值。","Equip to apply these stats.")
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
		note = Inspect.t("当前已穿戴 · 可在强化页提升。","Equipped · Improve in Forge")
	if item.get("instance_record") is Dictionary and not equipped and not preload("res://scripts/core/equipment_instances.gd").can_equip(item.instance_record,Game.profile.selected_hero,Game.hero_level()):
		disabled = true
		note = Inspect.Eligibility.reason(item.instance_record, Game.profile.selected_hero, Game.hero_level())
	var pending_claim: bool = owned and item.get("instance_record",{}).get("location","") == "pending"
	if pending_claim and panel.mode == "inventory":
		action = "CLAIM_INSTANCE"
		disabled = panel.busy
		note = Inspect.t("待领取物品仍归你所有；背包有空间时可领取。","This item is retained; collect it when inventory space is available.")
	if item.get("instance_record") is Dictionary and panel.mode == "inventory" and not pending_claim:
		var forge := MineStyle.button(right,"",Vector2(205,518),Vector2(143,28),func(): panel.forge_kind = "enhance"; panel._switch_page("upgrade"))
		forge.name = "OpenInstanceForge"
		forge.text = Inspect.t("锻造 / 锁定", "Forge / lock")
		forge.custom_minimum_size.y = 28
		forge.add_theme_font_size_override("font_size",12)
		var hint := MineStyle.literal(right,note,Vector2(18,516),Vector2(180,29),11,MineStyle.MUTED)
		hint.name = "EquipmentActionHint"
		hint.tooltip_text = note
		hint.max_lines_visible = 2
		hint.clip_text = true
	else:
		MineStyle.literal(right,note,Vector2(18,518),Vector2(330,28),12,MineStyle.MUTED)
	panel.action_button = MineStyle.button(right,action,Vector2(18,548),Vector2(330,36),panel._commit_item)
	panel.action_button.custom_minimum_size.y = 36
	panel.action_button.name = "PrimaryAction"
	MineStyle.primary(panel.action_button)
	panel.action_button.disabled = disabled
	if action == "CLAIM_INSTANCE": panel.action_button.text = Inspect.t("领取到背包","Collect to inventory")
	if action in ["BUY_ITEM","UPGRADE_ITEM"]: panel.action_button.text += " · "+str(cost)
