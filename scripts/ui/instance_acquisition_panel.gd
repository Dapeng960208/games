extends RefCounted
## Read-only quotes/ranges; actual rolls appear only after a durable transaction.
const Eligibility = preload("res://scripts/ui/equipment_eligibility.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Transactions = preload("res://scripts/core/instance_transactions.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const RARITY_NAMES := {"white":["白色","White"],"green":["绿色","Green"],"purple":["紫色","Purple"],"gold":["金色","Gold"]}

static func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func _label(parent: Control, text: String, at: Vector2, extent: Vector2, size: int = 16) -> Label:
	return MineStyle.literal(parent,text,at,extent,size,MineStyle.INK)

static func _change(panel: Control, key: String, value: Variant) -> void:
	if panel.busy: return
	panel.set(key,value)
	if key in ["selected_set","creation_power_type"]: panel.creation_omitted.clear()
	if key in ["selected_set", "selected_item"]:
		var definition: Dictionary = ContentRegistry.sets(2).get(str(value), {}) if key == "selected_set" else ContentRegistry.equipment(str(value), 2)
		var allowed: Array = definition.get("allowed_heroes", [])
		if allowed.size() == 1: panel.creation_power_type = ContentRegistry.ClassPolicy.power_type(str(allowed[0]))
	panel.creation_transaction_id = ""
	panel.creation_message = ""
	panel._render()

static func render(panel: Control) -> void:
	var crafting: bool = panel.mode == "craft"
	var set_mode: bool = not crafting and panel.shop_sets
	var rarities: Array = ["green","purple","gold"] if crafting else ["white","green"]
	if not panel.creation_rarity in rarities: panel.creation_rarity = str(rarities[0])
	if panel.creation_power_type.is_empty(): panel.creation_power_type = "magic" if Game.profile.selected_hero == "CH03" else "physical"
	panel.creation_level = clampi(Game.hero_level() if panel.creation_level <= 0 else panel.creation_level,1,Game.hero_level())
	var ids: Array = ContentRegistry.sets(2).keys() if set_mode else ContentRegistry.equipment_ids(2)
	ids.sort()
	var selected: String = panel.selected_set if set_mode else panel.selected_item
	if not selected in ids: selected = str(ids[0])
	if set_mode: panel.selected_set = selected
	else: panel.selected_item = selected
	var left := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(238,510))
	_label(left,_t("选择套装","CHOOSE SET") if set_mode else _t("选择模板","CHOOSE TEMPLATE"),Vector2(14,12),Vector2(210,30),20)
	var scroll := ScrollContainer.new()
	scroll.name = "InstanceCreationCatalog"
	scroll.position = Vector2(12,54)
	scroll.size = Vector2(214,444)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = 194
	scroll.add_child(rows)
	for id: String in ids:
		var definition: Dictionary = ContentRegistry.sets(2)[id] if set_mode else ContentRegistry.equipment(id,2)
		var row := MineStyle.button(rows,"",Vector2.ZERO,Vector2(194,62),func(): _change(panel,"selected_set" if set_mode else "selected_item",id))
		row.name = "CreationChoice_"+id
		row.custom_minimum_size = Vector2(194,62)
		MineStyle.button_skin(row,"card")
		var artwork: Dictionary = ContentRegistry.equipment(ContentRegistry.set_item_ids(id,2)[0],2) if set_mode else definition
		MineStyle.equipment_icon(row,artwork,Vector2(5,8),Vector2(46,46)).name = "CreationChoiceArt_"+id
		var caption := _label(row,MineStyle.content_text(definition,"name"),Vector2(56,11),Vector2(128,41),14)
		caption.max_lines_visible = 2
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.tooltip_text = caption.text+"\n"+Eligibility.label(definition)
		caption.text += "\n"+Eligibility.label(definition)
		if id == selected: MineStyle.selected(row,"card")
	var right := Control.new()
	right.position = Vector2(254,0)
	right.size = Vector2(962,510)
	panel.body.add_child(right)
	MineStyle.panel(right,Vector2.ZERO,Vector2(594,510)).name = "CreationPreviewCard"
	MineStyle.panel(right,Vector2(610,0),Vector2(352,510)).name = "CreationOrderCard"
	_label(right,_t("打造配置" if crafting else "购买配置","CRAFT OPTIONS" if crafting else "ORDER OPTIONS"),Vector2(630,14),Vector2(312,30),18)
	MineStyle.divider(right,Vector2(630,49),312)
	var definition: Dictionary = ContentRegistry.sets(2)[selected] if set_mode else ContentRegistry.equipment(selected,2)
	_label(right,MineStyle.content_text(definition,"name"),Vector2(20,12),Vector2(554,40),25).name = "CreationItemName"
	var eligibility := _label(right,Eligibility.label(definition)+_t(" · 新装备 +0", " · New item +0"),Vector2(20,55),Vector2(554,27),15)
	eligibility.name = "CreationEligibility"
	eligibility.tooltip_text = _t("通用件任意职业可穿；物理/法术是属性取向，请比较实际收益。专属套全部八槽均受限。", "Universal items fit all classes; Physical/Magic is their stat focus. Compare actual gains. All eight pieces of exclusive sets are restricted.")
	eligibility.mouse_filter = Control.MOUSE_FILTER_PASS
	_label(right,_t("品质","Quality"),Vector2(630,60),Vector2(312,24),14)
	var quality := OptionButton.new()
	quality.name = "CreationRarity"
	quality.position = Vector2(630,86)
	quality.size = Vector2(312,36)
	for rarity: String in rarities:
		var gate: int = {"green":5,"purple":10,"gold":15}.get(rarity,1)
		quality.add_item(_t(RARITY_NAMES[rarity][0],RARITY_NAMES[rarity][1])+(_t(" · Lv%d解锁"," · unlock Lv%d") % gate if crafting else ""))
	quality.select(rarities.find(panel.creation_rarity))
	quality.disabled = panel.busy
	right.add_child(quality)
	quality.item_selected.connect(func(index: int): _change(panel,"creation_rarity",rarities[index]))
	_label(right,_t("属性类型","Power type"),Vector2(630,134),Vector2(312,24),14)
	var power := OptionButton.new()
	power.name = "CreationPowerType"
	power.position = Vector2(630,160)
	power.size = Vector2(312,36)
	power.add_item(_t("物理型","Physical")); power.add_item(_t("法术型","Magic"))
	power.select(1 if panel.creation_power_type == "magic" else 0)
	power.disabled = panel.busy
	right.add_child(power)
	power.item_selected.connect(func(index: int): _change(panel,"creation_power_type","magic" if index == 1 else "physical"))
	_label(right,_t("装备等级（不高于当前角色）","Item level (up to current hero)"),Vector2(630,208),Vector2(312,24),14)
	var item_level := SpinBox.new()
	item_level.name = "CreationItemLevel"
	item_level.position = Vector2(630,234)
	item_level.size = Vector2(312,36)
	item_level.min_value = 1; item_level.max_value = Game.hero_level(); item_level.step = 1
	item_level.value = panel.creation_level
	item_level.editable = not panel.busy
	right.add_child(item_level)
	item_level.value_changed.connect(func(value: float): _change(panel,"creation_level",int(value)))
	var request: Dictionary = {"hero_id":str(Game.profile.selected_hero),"rarity":panel.creation_rarity,"power_type":panel.creation_power_type,"item_level":panel.creation_level}
	var missing: Array = []
	if set_mode:
		missing = Transactions.missing_set_templates(Game.profile,selected,panel.creation_power_type)
		request["set_id"] = selected; request["template_ids"] = []
		for id: String in missing:
			if not panel.creation_omitted.has(id): request.template_ids.append(id)
	else: request["template_id"] = selected
	var quote: Dictionary = Transactions.quote_set(Game.profile,request) if set_mode else Transactions.quote_craft(Game.profile,request) if crafting else Transactions.quote_purchase(Game.profile,request)
	_preview(right,selected,set_mode,missing)
	var complete: bool = set_mode and missing.is_empty()
	var lines: PackedStringArray = []
	if set_mode:
		lines.append(_t("该类型缺件 %d / 8；明确列出的缺件总价九折。","Missing %d / 8 · 10%% off the listed pieces.") % missing.size())
		lines.append(_t("已选择 %d 件，以下可取消勾选。","%d selected; uncheck any piece below.") % request.template_ids.size())
	else:
		lines.append(_t("物理/法术决定属性取向；通用件跨职业穿戴时请比较实际收益。", "Physical/Magic sets the stat focus; compare actual benefits when sharing universal items."))
		lines.append(_t("主属性范围（不提前抽取结果）","Main-stat ranges (no preview roll)"))
		var low := _main_range(selected,request,0)
		var high := _main_range(selected,request,100)
		for key: String in low:
			lines.append(Inspect.caption(key)+": "+_format_stat(key,float(low[key]))+" – "+_format_stat(key,float(high[key])))
		lines.append(_t("打造：绿色Lv5 / 紫色Lv10 / 金色Lv15。先击败对应首领解锁模板。","Craft: green Lv5 / purple Lv10 / gold Lv15. Defeat the matching boss to unlock its templates.") if crafting else _t("商店仅售白色与绿色；紫色与金色请前往打造。","Shop stocks white and green. Craft purple and gold equipment."))
		lines.append(_t("普通随机词条 %d 条；分位 u 为 0–100，共101档。","%d random affixes; u=0–100, 101 possible quantiles.") % int(Numbers.value("rarities")[panel.creation_rarity].affix_count))
	var text_scroll := ScrollContainer.new()
	text_scroll.name = "CreationDescription"
	text_scroll.position = Vector2(20,268); text_scroll.size = Vector2(554,226)
	text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(text_scroll)
	var description_rows := VBoxContainer.new()
	description_rows.custom_minimum_size.x = 534
	text_scroll.add_child(description_rows)
	var description := _label(description_rows,"\n".join(lines),Vector2.ZERO,Vector2(534,0),14 if set_mode else 16)
	description.custom_minimum_size.x = 534
	if set_mode:
		for id: String in missing:
			var item := ContentRegistry.equipment(id,2)
			var checkbox := CheckBox.new()
			checkbox.name = "CreationInclude_"+id
			checkbox.custom_minimum_size = Vector2(534,70)
			checkbox.tooltip_text = MineStyle.content_text(item,"name")
			checkbox.button_pressed = not panel.creation_omitted.has(id)
			checkbox.disabled = panel.busy
			description_rows.add_child(checkbox)
			MineStyle.equipment_icon(checkbox,item,Vector2(38,5),Vector2(56,56)).name = "CreationMissingArt_"+id
			var caption := _label(checkbox,checkbox.tooltip_text,Vector2(102,5),Vector2(412,24),15)
			caption.autowrap_mode = TextServer.AUTOWRAP_OFF
			caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var ranges: PackedStringArray = []
			var low := _main_range(id,request,0)
			var high := _main_range(id,request,100)
			for key: String in low:
				var caption_text: String = {"max_hp":"HP","magic_resist":"MR"}.get(key,Inspect.caption(key)) if Words.locale == "en" else Inspect.caption(key)
				ranges.append(caption_text+" "+_format_stat(key,float(low[key]))+"–"+_format_stat(key,float(high[key])))
			_label(checkbox," / ".join(ranges),Vector2(102,31),Vector2(412,34),12)
			checkbox.toggled.connect(func(enabled: bool):
				if enabled: panel.creation_omitted.erase(id)
				else: panel.creation_omitted[id] = true
				panel.creation_transaction_id = ""
				panel.creation_message = ""
				panel._render())
	var cost_lines: PackedStringArray = [_t("本次成本","COST"),_t("金币 %d / 持有 %d","Gold %d / owned %d") % [int(quote.get("gold",0)),int(Game.profile.permanent_gold)]]
	for material: String in quote.get("materials", {}):
		cost_lines.append(_material_name(material)+_t(" %d / 持有 %d"," %d / owned %d") % [int(quote.materials[material]),int(Game.profile.get("materials",{}).get(material,0))])
	if int(quote.get("pending_count",0)) > 0: cost_lines.append(_t("背包满：物品进入待领取，不折金币。","Inventory full: items wait for collection, never auto-sold."))
	_scroll_text(right,"CreationCost","\n".join(cost_lines),Vector2(630,287),Vector2(312,130),14)
	var message: String = panel.creation_message
	if message.is_empty() and not bool(quote.get("ok",false)) and not complete: message = error_text(str(quote.get("error","")))
	var affordable: bool = int(Game.profile.permanent_gold) >= int(quote.get("gold",0))
	for material: String in quote.get("materials",{}):
		if int(Game.profile.get("materials",{}).get(material,0)) < int(quote.materials[material]): affordable = false
	if not affordable and message.is_empty(): message = _t("金币或材料不足。","Not enough gold or materials.")
	if complete: message = _t("该属性八件已拥有；穿戴仍要求职业与等级符合。", "All eight stat variants owned; class and level requirements still apply.")
	if message.is_empty() and Game.profile.selected_hero not in definition.get("allowed_heroes", []): message = _t("当前职业不可穿 · 可为对应职业购买\n", "Current class cannot equip · may buy for its class\n")+Eligibility.label(definition)
	_scroll_text(right,"CreationResult",message,Vector2(630,424),Vector2(312,31),12)
	var action := MineStyle.button(right,"",Vector2(630,461),Vector2(312,36),func(): _submit(panel,request,crafting,set_mode,complete))
	action.custom_minimum_size.y = 36
	action.add_theme_font_size_override("font_size",15)
	action.name = "PrimaryAction"
	action.text = _t("穿戴该套装","Equip this set") if complete else _t("打造并保存","Craft and save") if crafting else _t("购买缺件并保存","Buy missing pieces and save") if set_mode else _t("购买并保存","Buy and save")
	var matching_type: bool = Game.profile.selected_hero in definition.get("allowed_heroes", [])
	action.disabled = panel.busy or (not complete and (not bool(quote.get("ok",false)) or not affordable)) or (complete and not matching_type)
	MineStyle.primary(action)
	panel.action_button = action
	panel.item_list = scroll

static func _scroll_text(parent: Control, id: String, text: String, at: Vector2, extent: Vector2, font_size: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = id+"Scroll"
	scroll.position = at
	scroll.size = extent
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var label := _label(scroll,text,Vector2.ZERO,Vector2(extent.x-18,0),font_size)
	label.name = id
	label.custom_minimum_size.x = extent.x-18
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text

static func _preview(parent: Control, selected: String, set_mode: bool, missing: Array) -> void:
	var ids: Array = ContentRegistry.set_item_ids(selected,2) if set_mode else [selected]
	for index in ids.size():
		var item := ContentRegistry.equipment(str(ids[index]),2)
		var preview := MineStyle.panel(parent,Vector2(20+(index%4)*140,88+(index/4)*84) if set_mode else Vector2(194,87),Vector2(134,78) if set_mode else Vector2(206,168))
		preview.name = "CreationPreview_"+str(item.id)
		preview.mouse_filter = Control.MOUSE_FILTER_PASS
		preview.tooltip_text = MineStyle.content_text(item,"name")
		if set_mode: preview.tooltip_text += " · "+(_t("缺少","Missing") if item.id in missing else _t("已拥有","Owned"))
		MineStyle.equipment_icon(preview,item,Vector2(39,0) if set_mode else Vector2(29,0),Vector2(56,56) if set_mode else Vector2(148,140)).name = "CreationPreviewArt_"+str(item.id)
		var caption := _label(preview,Words.text("SLOT_"+str(item.slot).to_upper())+((" · "+_t("已拥有","Owned")) if set_mode and not item.id in missing else ""),Vector2(4,55) if set_mode else Vector2(8,138),Vector2(126,19) if set_mode else Vector2(190,24),11 if set_mode else 16)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func _main_range(template: String, request: Dictionary, quantile: int) -> Dictionary:
	var main := {}
	for key: String in Instances.main_keys(template,request.power_type): main[key] = quantile
	var affixes: Array = []
	var legal := Instances.legal_affixes(template,request.power_type)
	for index in int(Numbers.value("rarities")[request.rarity].affix_count): affixes.append({"type":legal[index],"u":quantile})
	var record := Instances.create({"instance_id":"preview","template_id":template,"source_event_id":"preview","item_level":request.item_level,"rarity":request.rarity,"power_type":request.power_type,"main_rolls":main,"affix_type_and_quantile":affixes})
	return Instances.main_stats(record)

static func _format_stat(key: String, amount: float) -> String:
	return Inspect.value(key,amount,false,true) if key in Inspect.RATIOS or key == "move_speed" else str(int(amount))

static func _material_name(id: String) -> String:
	if id == "forge": return _t("锻材","Forge material")
	return id.get_slice(":",1)+(_t("族材"," material") if id.begins_with("race:") else _t("核心"," core"))

static func error_text(code: String) -> String:
	if code == "CLASS_POWER_MISMATCH": return _t("专属套属性不符：法师用法术，战士/枪手用物理。", "Wrong stats for class set: Mage uses Magic; Warrior/Gunner use Physical.")
	if code == "CLASS_LOCKED": return _t("当前职业不能穿戴该专属套。", "Current class cannot equip this exclusive set.")
	var messages := {"INSUFFICIENT_GOLD":["金币不足。","Not enough gold."],"INSUFFICIENT_MATERIALS":["材料不足。","Not enough materials."],"CRAFT_LEVEL_LOCKED":["打造解锁等级：绿5、紫10、金15。","Craft unlocks: green Lv5, purple Lv10, gold Lv15."],"ITEM_LEVEL_LOCKED":["装备等级不能超过当前角色。","Item level exceeds the current hero."],"TEMPLATE_LOCKED":["先击败对应首领解锁模板。","Defeat the required boss to unlock this template."],"PROFILE_CAPACITY":["存档容量不足；交易未生效。","Save capacity reached; transaction was not applied."]}
	return _t(messages[code][0],messages[code][1]) if messages.has(code) else code

static func _submit(panel: Control, request: Dictionary, crafting: bool, set_mode: bool, complete: bool) -> void:
	if panel.busy or panel.action_button.disabled: return
	panel.busy = true
	panel.action_button.disabled = true
	if panel.creation_transaction_id.is_empty(): panel.creation_transaction_id = "creation:"+Crypto.new().generate_random_bytes(16).hex_encode()
	var result: Dictionary
	if complete:
		result = {"ok":Game.equip_equipment_set(str(request.set_id)),"receipt":{}}
	else:
		var method: String = "craft_equipment_v2" if crafting else "purchase_equipment_set_v2" if set_mode else "purchase_equipment_v2"
		result = Game.call(method,request,panel.creation_transaction_id)
	if bool(result.get("ok",false)):
		var items: Array = result.get("receipt",{}).get("items",[])
		panel.creation_message = _t("已保存 %d 件独立装备；可在背包查看实际结果。","Saved %d independent items; inspect the actual rolls in Inventory.") % items.size() if not complete else _t("套装已穿戴。","Set equipped.")
		panel.creation_transaction_id = ""
	else:
		panel.creation_message = error_text(str(result.get("error",Game.last_error)))+_t(" 重试保留同一交易。"," Retry keeps the same transaction.")
	await panel.get_tree().create_timer(0.3).timeout
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	panel.busy = false
	panel._render()
