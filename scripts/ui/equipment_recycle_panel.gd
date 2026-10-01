extends RefCounted
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
## Multi-select inventory recycling, with a concrete confirmation and one save.

static func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func _label(parent: Control, text: String, at: Vector2, extent: Vector2, font_size: int = 16, tint: Color = MineStyle.INK) -> Label:
	var label := MineStyle.literal(parent,text,at,extent,font_size,tint)
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label

static func render(panel: Control) -> void:
	for id: String in panel.sale_selection.keys():
		if not Game.profile.equipment.has(id) or id in Game.profile.loadout.values(): panel.sale_selection.erase(id)
	var left := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(710,510))
	_label(left,_t("装备回收 · 选中需要售出的装备", "RECYCLE · SELECT EQUIPMENT TO SELL"),Vector2(18,10),Vector2(670,28),18,MineStyle.AMBER)
	var select_all := MineStyle.button(left,"",Vector2(16,43),Vector2(328,38),func():
		for id: String in Game.profile.equipment:
			if not id in Game.profile.loadout.values(): panel.sale_selection[id] = true
		panel._render())
	select_all.name = "SelectAllForSale"
	select_all.text = _t("全选未穿戴装备", "Select all unequipped")
	select_all.add_theme_font_size_override("font_size",16)
	var clear := MineStyle.button(left,"",Vector2(356,43),Vector2(338,38),func(): panel.sale_selection.clear(); panel._render())
	clear.name = "ClearSaleSelection"
	clear.text = _t("清空选择", "Clear selection")
	clear.add_theme_font_size_override("font_size",16)
	var scroll := ScrollContainer.new()
	scroll.name = "RecycleCatalog"
	scroll.position = Vector2(12,91)
	scroll.size = Vector2(686,407)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	left.add_child(scroll)
	panel.item_list = scroll
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation",8)
	scroll.add_child(stack)
	var ids: Array = Game.profile.equipment.keys()
	ids.sort()
	for id: String in ids:
		var item: Dictionary = ContentRegistry.equipment(id)
		var equipped: bool = id in Game.profile.loadout.values()
		var selected: bool = panel.sale_selection.has(id)
		var row := MineStyle.button(stack,"",Vector2.ZERO,Vector2(666,76),func():
			panel.recycle_scroll = scroll.scroll_vertical
			if panel.sale_selection.has(id): panel.sale_selection.erase(id)
			else: panel.sale_selection[id] = true
			panel._render())
		row.name = "SellItem_"+id
		row.custom_minimum_size = Vector2(666,76)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.disabled = equipped
		row.tooltip_text = Inspect.tooltip(item,Game.equipment_level(id),Game.profile.selected_hero)
		MineStyle.button_skin(row,"card")
		if selected: MineStyle.selected(row,"card")
		MineStyle.equipment_icon(row,item,Vector2(8,5),Vector2(64,64))
		var caption := _label(row,MineStyle.content_text(item,"name")+" +"+str(Game.equipment_level(id)),Vector2(84,8),Vector2(432,28),19)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label(row,_t("已穿戴 · 无法出售", "Equipped · Cannot sell") if equipped else _t("回收获得 %d 金币", "Sell for %d gold") % Game.equipment_sell_value(id),Vector2(84,43),Vector2(432,24),15,MineStyle.MUTED if equipped else MineStyle.AMBER)
		_label(row,"✓" if selected else ("●" if equipped else "○"),Vector2(598,18),Vector2(46,40),28,MineStyle.GREEN if selected else MineStyle.MUTED)
	scroll.set_deferred("scroll_vertical",panel.recycle_scroll)
	var detail := MineStyle.panel(panel.body,Vector2(728,0),Vector2(488,510))
	var selected_ids: Array = panel.sale_selection.keys()
	selected_ids.sort()
	var total := 0
	var summary := ""
	for id: String in selected_ids:
		var item: Dictionary = ContentRegistry.equipment(id)
		var price: int = Game.equipment_sell_value(id)
		total += price
		summary += MineStyle.content_text(item,"name")+" +"+str(Game.equipment_level(id))+"  ·  "+str(price)+_t(" 金币", " gold")+"\n\n"
	_label(detail,_t("回收清单", "RECYCLE SUMMARY"),Vector2(18,12),Vector2(450,33),26)
	_label(detail,_t("已选择 %d 件装备", "%d pieces selected") % selected_ids.size(),Vector2(18,57),Vector2(450,30),19,MineStyle.CYAN)
	_label(detail,_t("预计获得  %d 金币", "Proceeds: %d gold") % total,Vector2(18,93),Vector2(450,38),28,MineStyle.AMBER).name = "SaleTotal"
	var summary_scroll := ScrollContainer.new()
	summary_scroll.name = "SaleSummary"
	summary_scroll.position = Vector2(18,151)
	summary_scroll.size = Vector2(452,236)
	summary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(summary_scroll)
	var description := _label(summary_scroll,summary if not summary.is_empty() else _t("点击左侧装备勾选，可一次出售多件。\n当前穿戴的装备受到保护。", "Select equipment on the left to sell multiple pieces.\nEquipped items are protected."),Vector2.ZERO,Vector2(426,0),16,MineStyle.MUTED)
	description.custom_minimum_size.x = 426
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(detail,_t("回收价：基础售价 25% + 强化成本 20%\n逐项向下取整；售出会移除装备及其强化。", "Value: 25% base price + 20% refinement cost.\nRounded down per part; sold gear and refinement are removed."),Vector2(18,398),Vector2(450,44),13,MineStyle.MUTED)
	panel.action_button = MineStyle.button(detail,"",Vector2(18,449),Vector2(452,46),func(): _confirm(panel,selected_ids,total))
	panel.action_button.name = "PrimaryAction"
	MineStyle.button_skin(panel.action_button,"danger")
	panel.action_button.text = _t("出售选中装备 · %d 金币", "Sell selected · %d gold") % total
	panel.action_button.disabled = selected_ids.is_empty() or panel.busy

static func _confirm(panel: Control, ids: Array, total: int) -> void:
	if panel.busy or ids.is_empty() or panel.action_button.disabled: return
	panel.busy = true
	panel.action_button.disabled = true
	var modal: Panel = panel.app._push_modal(_t("确认出售装备", "Confirm equipment sale"),Vector2(720,338))
	# Esc closes modals through the app. Release this page's lock on that path
	# as well as the explicit cancel button, without committing the selection.
	modal.get_parent().tree_exiting.connect(func():
		if is_instance_valid(panel) and panel.is_inside_tree() and panel.busy:
			panel.busy = false
			panel._render())
	_label(modal,_t("出售选中的 %d 件装备，获得 %d 金币。", "Sell the %d selected pieces for %d gold.") % [ids.size(),total],Vector2(28,88),Vector2(664,56),23,MineStyle.AMBER)
	_label(modal,_t("这些装备及其强化将从背包移除。\n以后重新购买会获得未强化的装备。", "These pieces and their refinement will be removed.\nBuying them again grants unrefined equipment."),Vector2(28,155),Vector2(664,68),18,MineStyle.MUTED)
	var transaction_id: String = "sale:"+Crypto.new().generate_random_bytes(16).hex_encode()
	var actions := MineStyle.action_pair(modal,"BACK","",260,func(): panel.app._pop_modal(); panel.busy = false; panel._render(),func(): _commit(panel,ids,transaction_id))
	var cancel := actions[0]
	cancel.name = "CancelEquipmentSale"
	var confirm := actions[1]
	confirm.name = "ConfirmEquipmentSale"
	MineStyle.button_skin(confirm,"danger")
	confirm.text = _t("确认出售 · %d 金币", "Confirm sale · %d gold") % total
	cancel.grab_focus()

static func _commit(panel: Control, ids: Array, transaction_id: String) -> void:
	if not panel.busy: return
	var modal: Control = panel.app.modals[-1].node
	var confirm := modal.find_child("ConfirmEquipmentSale",true,false) as Button
	if confirm == null or confirm.disabled: return
	confirm.disabled = true
	var success: bool = Game.sell_equipment_items(ids,transaction_id)
	panel.app._pop_modal()
	panel.busy = false
	if success: panel.sale_selection.clear()
	panel._render()
	if not success and not Game.last_error.is_empty(): panel.app._show_save_error()
