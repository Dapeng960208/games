extends RefCounted
## V2 camp forging hub. All mutations go through atomic Game transactions;
## price previews never request a random candidate.
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const RARITY_NAMES := {"white":["白色","White"],"green":["绿色","Green"],"purple":["紫色","Purple"],"gold":["金色","Gold"]}
const KINDS := ["enhance","enhancement_reroll","reforge","refine","inherit","sell","dismantle"]
const TITLES := {"enhance":["强化","Enhance"],"enhancement_reroll":["阶重锻","Reroll step"],"reforge":["词条重铸","Reforge"],"refine":["词条精炼","Refine"],"inherit":["强化继承","Inherit"],"sell":["出售","Sell"],"dismantle":["拆解","Dismantle"]}

static func _t(zh: String,en: String) -> String:
	return en if Words.locale == "en" else zh

static func _label(owner: Node,text: String,at: Vector2,extent: Vector2,font: int = 15) -> Label:
	var label := MineStyle.literal(owner,text,at,extent,font,MineStyle.INK)
	label.tooltip_text = text
	return label

static func _title(kind: String) -> String:
	return _t(TITLES[kind][0],TITLES[kind][1]) if TITLES.has(kind) else _t("提交选择","Confirm choice")

static func _rarity_title(rarity: String) -> String:
	return _t(RARITY_NAMES[rarity][0],RARITY_NAMES[rarity][1]) if RARITY_NAMES.has(rarity) else rarity

static func _power_title(power: String) -> String:
	return _t("法术型","Magic") if power == "magic" else _t("物理型","Physical")

static func _locked(panel: Control) -> bool:
	return panel.busy or not panel.forge_transaction_id.is_empty()

static func _change(panel: Control,key: String,value: Variant) -> void:
	if _locked(panel): return
	panel.set(key,value)
	panel.forge_message = ""
	panel.forge_result_details = ""
	if key == "selected_item":
		panel.forge_affix_index = 0
		panel.forge_affix_type = ""
		panel.forge_source_instance_id = ""
	panel._render()

static func _restore_retry(panel: Control) -> void:
	if not Game.has_method("pending_forging_v2"): return
	var pending: Dictionary = Game.call("pending_forging_v2")
	if pending.is_empty(): return
	panel.forge_transaction_id = str(pending.operation_id)
	panel.forge_frozen_kind = str(pending.kind)
	panel.forge_frozen_request = pending.request.duplicate(true)
	panel.selected_item = str(pending.request.get("target_instance_id",pending.request.get("instance_id","")))
	if pending.kind != "resolve_reforge": panel.forge_kind = str(pending.kind)
	panel.forge_message = _t("上次保存失败；重试同一交易，或取消尚未付款的操作。","The previous save failed. Retry this transaction, or cancel its unpaid attempt.")

static func render(panel: Control,recycling: bool = false) -> void:
	_restore_retry(panel)
	var ids: Array = Game.profile.equipment.keys()
	ids.sort()
	if not panel.selected_item in ids: panel.selected_item = str(ids[0]) if not ids.is_empty() else ""
	var left := MineStyle.panel(panel.body,Vector2.ZERO,Vector2(286,510))
	_label(left,_t("独立装备实例","EQUIPMENT INSTANCES"),Vector2(14,12),Vector2(258,30),19)
	var scroll := ScrollContainer.new()
	scroll.name = "ForgeInventory"
	scroll.position = Vector2(12,54)
	scroll.size = Vector2(262,442)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = 242
	scroll.add_child(rows)
	for id: String in ids:
		var record: Dictionary = Game.profile.equipment[id]
		var item := Registry.equipment(str(record.template_id),2)
		var button := MineStyle.button(rows,"",Vector2.ZERO,Vector2(242,62),func(): _change(panel,"selected_item",id))
		button.name = "ForgeInstance_"+id.replace(":","_").replace("/","_")
		button.set_meta("instance_id",id)
		button.custom_minimum_size = Vector2(242,62)
		button.text = MineStyle.content_text(item,"name")+" +%d\niLv%d · %s · %s" % [int(record.enhancement_rank),int(record.item_level),_rarity_title(str(record.rarity)),id.right(8)]
		button.add_theme_font_size_override("font_size",13)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = id+"\n"+_power_title(str(record.power_type))+" · "+str(record.location)
		button.disabled = _locked(panel)
		if id == panel.selected_item: MineStyle.selected(button)
	var right := MineStyle.panel(panel.body,Vector2(300,0),Vector2(916,510))
	if panel.selected_item.is_empty():
		_label(right,_t("背包没有装备。","No equipment in inventory."),Vector2(20,24),Vector2(870,80),22)
		panel.action_button = null
		return
	var record: Dictionary = Game.profile.equipment[panel.selected_item]
	var item := Registry.equipment(str(record.template_id),2)
	_label(right,MineStyle.content_text(item,"name")+" +"+str(int(record.enhancement_rank)),Vector2(16,10),Vector2(682,32),23).name = "ForgeItemName"
	var identity := _label(right,"iLv%d · %s · %s · %s" % [int(record.item_level),_rarity_title(str(record.rarity)),_power_title(str(record.power_type)),str(record.instance_id)],Vector2(16,46),Vector2(872,24),12)
	identity.name = "ForgeInstanceIdentity"
	identity.autowrap_mode = TextServer.AUTOWRAP_OFF
	identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lock_button := MineStyle.button(right,"",Vector2(722,10),Vector2(178,34),func(): _toggle_lock(panel,record))
	lock_button.name = "ForgeLock"
	lock_button.text = _t("解锁装备","Unlock gear") if record.lock_state else _t("锁定装备","Lock gear")
	lock_button.add_theme_font_size_override("font_size",14)
	lock_button.disabled = _locked(panel) or record.has("pending_reforge")
	var kinds: Array = ["sell","dismantle"] if recycling else KINDS
	if not panel.forge_kind in kinds and panel.forge_transaction_id.is_empty(): panel.forge_kind = str(kinds[0])
	var tab_width := 880.0 / kinds.size()
	for index in kinds.size():
		var kind: String = kinds[index]
		var tab := MineStyle.button(right,"",Vector2(16+index*tab_width,81),Vector2(tab_width-6,36),func(): _change(panel,"forge_kind",kind))
		tab.name = "ForgeAction_"+kind
		tab.text = _title(kind)
		tab.add_theme_font_size_override("font_size",14)
		tab.disabled = _locked(panel)
		if kind == panel.forge_kind: MineStyle.selected(tab)
	if record.has("pending_reforge"):
		_render_pending(panel,right,record)
		return
	var request := _selectors(panel,right,record)
	var kind: String = panel.forge_kind
	if not panel.forge_transaction_id.is_empty():
		kind = panel.forge_frozen_kind
		request = panel.forge_frozen_request.duplicate(true)
	var quote: Dictionary = Game.call("quote_forging_v2",kind,request) if Game.has_method("quote_forging_v2") else {"ok":false,"error":"FORGE_NOT_READY"}
	var detail_rows := _detail_scroll(right,"ForgeDetails",Vector2(16,177),Vector2(544,242))
	_text_row(detail_rows,_state_text(record),"ForgeStepList")
	_text_row(detail_rows,_preview_text(record,quote,kind),"ForgeIntegerPreview")
	_text_row(detail_rows,_rules_text(kind,record,panel.forge_rank),"ForgeRuleExplanation")
	if not panel.forge_result_details.is_empty(): _text_row(detail_rows,panel.forge_result_details,"ForgeLastResult")
	var costs := _detail_scroll(right,"ForgeCostsScroll",Vector2(580,177),Vector2(318,242))
	_text_row(costs,_cost_text(quote,kind,record),"ForgeCost")
	var message: String = panel.forge_message
	if message.is_empty() and not bool(quote.get("ok",false)): message = error_text(str(quote.get("error","")))
	if message.is_empty() and not _affordable(quote): message = _t("金币或材料不足。","Not enough gold or materials.")
	_label(right,message,Vector2(16,425),Vector2(884,34),13).name = "ForgeResult"
	var retry: bool = not panel.forge_transaction_id.is_empty()
	var action := MineStyle.button(right,"",Vector2(16,466),Vector2(660 if retry else 884,34),func(): _confirm_or_submit(panel,kind,request,quote))
	action.name = "PrimaryAction"
	action.text = _t("重试同一交易并保存","Retry same transaction and save") if retry else _title(kind)+_t("并保存"," and save")
	action.disabled = panel.busy or (not retry and (not bool(quote.get("ok",false)) or not _affordable(quote)))
	panel.action_button = action
	if retry: _cancel_retry_button(panel,right)

static func _choice(owner: Control,id: String,at: Vector2,extent: Vector2,labels: Array,selected: int,disabled: bool) -> OptionButton:
	var button := OptionButton.new()
	button.name = id
	button.position = at
	button.size = extent
	button.fit_to_longest_item = false
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override("font_size",14)
	for label: String in labels: button.add_item(label)
	if not labels.is_empty(): button.select(clampi(selected,0,labels.size()-1))
	button.disabled = disabled or labels.is_empty()
	owner.add_child(button)
	return button

static func _selectors(panel: Control,right: Control,record: Dictionary) -> Dictionary:
	var request := {"hero_id":Game.profile.selected_hero,"instance_id":record.instance_id,"expected_revision":int(record.get("forge_revision",0))}
	var kind: String = panel.forge_kind
	if kind == "enhancement_reroll":
		var labels: Array = []
		for index in record.enhancement_steps.size():
			var step: Dictionary = record.enhancement_steps[index]
			labels.append(_t("第%d阶 · g%d%% · c%d/3","Step %d · g%d%% · c%d/3") % [index+1,int(step.g),int(step.pity)])
		panel.forge_rank = clampi(panel.forge_rank,1,maxi(1,labels.size()))
		var chooser := _choice(right,"ForgeRank",Vector2(16,130),Vector2(530,35),labels,panel.forge_rank-1,_locked(panel))
		chooser.item_selected.connect(func(index: int): _change(panel,"forge_rank",index+1))
		request["rank"] = panel.forge_rank
	elif kind in ["reforge","refine"]:
		var labels: Array = []
		for affix: Dictionary in record.affix_type_and_quantile: labels.append(_caption(str(affix.type))+" · u"+str(int(affix.u)))
		panel.forge_affix_index = clampi(panel.forge_affix_index,0,maxi(0,labels.size()-1))
		if kind == "reforge" and int(record.reforge_slot) >= 0: panel.forge_affix_index = int(record.reforge_slot)
		var chooser := _choice(right,"ForgeAffix",Vector2(16,130),Vector2(384,35),labels,panel.forge_affix_index,_locked(panel) or (kind == "reforge" and int(record.reforge_slot) >= 0))
		chooser.item_selected.connect(func(index: int): _change(panel,"forge_affix_index",index))
		request["affix_index"] = panel.forge_affix_index
		if kind == "reforge":
			var legal := Instances.legal_affixes(str(record.template_id),str(record.power_type))
			for index in record.affix_type_and_quantile.size():
				if index != panel.forge_affix_index: legal.erase(str(record.affix_type_and_quantile[index].type))
			if not panel.forge_affix_type in legal: panel.forge_affix_type = str(legal[0]) if not legal.is_empty() else ""
			var names: Array = []
			for type: String in legal: names.append(_caption(type))
			var type_choice := _choice(right,"ForgeAffixType",Vector2(414,130),Vector2(484,35),names,legal.find(panel.forge_affix_type),_locked(panel))
			type_choice.item_selected.connect(func(index: int): _change(panel,"forge_affix_type",legal[index]))
			request["affix_type"] = panel.forge_affix_type
	elif kind == "inherit":
		var ids: Array[String] = []
		var names: Array = []
		for id: String in Game.profile.equipment:
			var source: Dictionary = Game.profile.equipment[id]
			if id == record.instance_id or source.power_type != record.power_type or Registry.equipment(source.template_id,2).slot != Registry.equipment(record.template_id,2).slot: continue
			ids.append(id)
			names.append(_t("来源：","Source: ")+MineStyle.content_text(Registry.equipment(source.template_id,2),"name")+" +%d · iLv%d · %s" % [int(source.enhancement_rank),int(source.item_level),id.right(8)])
		if not panel.forge_source_instance_id in ids: panel.forge_source_instance_id = str(ids[0]) if not ids.is_empty() else ""
		var chooser := _choice(right,"ForgeInheritanceSource",Vector2(16,130),Vector2(884,35),names,ids.find(panel.forge_source_instance_id),_locked(panel))
		for index in ids.size(): chooser.set_item_tooltip(index,ids[index])
		chooser.item_selected.connect(func(index: int): _change(panel,"forge_source_instance_id",ids[index]))
		request = {"hero_id":Game.profile.selected_hero,"target_instance_id":record.instance_id,"source_instance_id":panel.forge_source_instance_id,
			"target_revision":int(record.get("forge_revision",0)),"source_revision":int(Game.profile.equipment.get(panel.forge_source_instance_id,{}).get("forge_revision",0))}
	else:
		_label(right,_t("角色等级%d · 强化门槛 Lv5/10/15/20 → +3/+5/+8/+10","Hero Lv%d · Enhancement gates Lv5/10/15/20 → +3/+5/+8/+10") % Game.hero_level(),Vector2(16,129),Vector2(884,37),14)
	return request

static func _detail_scroll(owner: Control,id: String,at: Vector2,extent: Vector2) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = id
	scroll.position = at
	scroll.size = extent
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	owner.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = extent.x-20
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows

static func _text_row(rows: VBoxContainer,text: String,id: String) -> void:
	if text.is_empty(): return
	var label := _label(rows,text,Vector2.ZERO,Vector2(rows.custom_minimum_size.x,0),14)
	label.name = id
	label.custom_minimum_size.x = rows.custom_minimum_size.x
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

static func _factor(record: Dictionary) -> float:
	var total := 100
	for step: Dictionary in record.get("enhancement_steps",[]): total += int(step.g)
	return total/100.0

static func _state_text(record: Dictionary) -> String:
	var lines: PackedStringArray = [_t("当前总倍率 F = %.2f；增幅加算，不是逐阶复利。","Current total F = %.2f; step gains add, never compound.") % _factor(record)]
	for index in record.enhancement_steps.size():
		var step: Dictionary = record.enhancement_steps[index]
		lines.append(_t("第%d阶：g %d%% · 无提高 c %d/3%s","Step %d: g %d%% · no-improvement c %d/3%s") % [index+1,int(step.g),int(step.pity),_t(" · 已满"," · MAX") if int(step.g)==12 else ""])
	return "\n".join(lines)

static func _caption(key: String) -> String:
	if key == "resource_gain_bonus": return _t("资源获取加成","Resource gain bonus")
	if key == "hp_ratio": return _t("生命百分比","Health bonus")
	return Inspect.caption(key)

static func _format(key: String,value: Variant) -> String:
	var affix: Dictionary = Numbers.value("affixes").get(key,{})
	if affix.get("scaling") == "percent" or key in Inspect.RATIOS or key == "move_speed": return "%.1f%%" % (float(value)*100.0)
	return str(int(value))

static func _stat_lines(before: Dictionary,after: Dictionary) -> String:
	var lines: PackedStringArray = []
	for key: String in before:
		if not after.has(key): continue
		lines.append(_caption(key)+": "+_format(key,before[key])+" → "+_format(key,after[key]))
	return "\n".join(lines)

static func _preview_text(record: Dictionary,quote: Dictionary,kind: String) -> String:
	var before: Dictionary = quote.get("before_main_stats",Instances.main_stats(record))
	var lines: PackedStringArray = [_t("主属性整数预览","MAIN ATTRIBUTE PREVIEW")]
	if kind == "enhance" and quote.has("after_stats_min"):
		for key: String in before:
			lines.append(_caption(key)+": "+_format(key,before[key])+" → "+_format(key,quote.after_stats_min.get(key,0))+"–"+_format(key,quote.after_stats_max.get(key,0)))
	elif kind == "enhancement_reroll" and quote.has("old_gain"):
		var rank := int(quote.get("request",{}).get("rank",1))
		var minimum := record.duplicate(true)
		var maximum := record.duplicate(true)
		minimum.enhancement_steps[rank-1].g = int(quote.old_gain)+(1 if quote.get("guaranteed",false) else 0)
		maximum.enhancement_steps[rank-1].g = int(minimum.enhancement_steps[rank-1].g) if quote.get("guaranteed",false) else 12
		minimum.enhancement_steps[rank-1].pity = 0
		maximum.enhancement_steps[rank-1].pity = 0
		var low := Instances.main_stats(minimum)
		var high := Instances.main_stats(maximum)
		for key: String in before:
			lines.append(_caption(key)+": "+_format(key,before[key])+" → "+_format(key,low.get(key,0))+"–"+_format(key,high.get(key,0)))
	elif quote.has("after_main_stats"):
		lines.append(_stat_lines(before,quote.after_main_stats))
	else:
		for key: String in before: lines.append(_caption(key)+": "+_format(key,before[key]))
	if kind == "inherit" and quote.has("after_steps"):
		var source_id := str(quote.get("request",{}).get("source_instance_id",""))
		var source: Dictionary = Game.profile.equipment.get(source_id,{})
		if not source.is_empty(): lines.append(_t("来源实例：","Source instance: ")+source_id+"\n"+_state_text(source))
		var after_record := record.duplicate(true)
		after_record.enhancement_steps = quote.after_steps.duplicate(true)
		lines.append(_t("目标 F %.2f → %.2f；来源强化归 +0","Target F %.2f → %.2f; source becomes +0") % [_factor(record),_factor(after_record)])
		lines.append(_t("逐阶取优后的向量：","Merged steps:")+"\n"+_state_text(after_record))
	if kind == "refine" and quote.has("after_stats"):
		var index := int(quote.get("request",{}).get("affix_index",0))
		if index < record.affix_type_and_quantile.size():
			var affix: Dictionary = record.affix_type_and_quantile[index]
			var key: String = affix.type
			lines.append(_t("词条 u%d → u%d；","Affix u%d → u%d; ") % [int(affix.u),mini(100,int(affix.u)+10)]+_caption(key)+": "+_format(key,quote.before_stats.get(key,0))+" → "+_format(key,quote.after_stats.get(key,0)))
			if quote.has("current_loadout_before"):
				var actual_key: String = {"attack_speed":"attack_speed_bonus","move_speed":"move_speed_bonus","damage_reduction":"equipment_damage_reduction"}.get(key,key)
				lines.append(_t("当前配装实际有效值：","Current loadout effective value: ")+_caption(actual_key)+" "+_format(actual_key,quote.current_loadout_before.get(actual_key,0))+" → "+_format(actual_key,quote.current_loadout_after.get(actual_key,0)))
				for note: String in Inspect.cap_notes(quote.current_loadout_after): lines.append(note)
				if not bool(quote.get("equipped",false)): lines.append(_t("此件未装备，因此当前配装不变；精炼只改善该收藏实例。","This item is unequipped, so the current loadout is unchanged; refining improves this stored instance."))
	return "\n".join(lines)

static func _rules_text(kind: String,record: Dictionary,rank: int) -> String:
	match kind:
		"enhance": return _t("100%升一阶。本阶 g=8/9/10/11/12%，概率10/20/40/20/10%。只提高平值主属性；k/u、普通词条、移速百分比和固定特性不变。","100% rank success. Step g=8/9/10/11/12%, with probabilities 10/20/40/20/10%. Only flat main attributes improve; k/u, ordinary affixes, movement percentages and fixed effects stay unchanged.")
		"enhancement_reroll":
			var pity := int(record.enhancement_steps[rank-1].pity) if rank > 0 and rank <= record.enhancement_steps.size() else 0
			return _t("Lv10解锁。取旧/新 g 较高者；费用不退，未提高也记录。","Unlocks at Lv10. Keep the higher old/new g; payment is nonrefundable, including unchanged rolls.")+"\n"+(_t("c=3：本次确定提高1个百分点，不再抽样。","c=3: this attempt guarantees +1 percentage point, with no random draw.") if pity == 3 else _t("再连续%d次无提高后，下次保底提高1个百分点。","After %d more unchanged attempts, the following attempt guarantees +1 percentage point.") % (3-pity))
		"reforge": return _t("此实例永久绑定一个可重铸槽。付款保存后显示冻结的新词条，选择保留旧词条或替换；退出重开不会重抽，也不退费用。","One reforge slot is permanently bound to this instance. Pay and save to reveal a frozen affix, then keep the old affix or replace it. Reopening never rerolls or refunds payment.")
		"refine": return _t("u增加10，最高100；不更换类型。已装备且当前有效属性无提升时拒绝收费。","Increase u by 10, up to 100, without changing type. Equipped items with no effective improvement cannot be charged.")
		"inherit": return _t("来源N≥目标N；同槽同类型，逐阶取较高g，同g保留目标c。目标强化不相加，来源归0。已付账本原子移到目标；固定手续费、重锻与重锻补差不退款。","Source N≥target N, same slot/type. Take higher g per step; ties keep target pity. Ranks do not add and the source becomes +0. Paid history moves to the target; fixed fee, rerolls and reroll makeup are nonrefundable.")
		"sell": return _t("出售永久移除这一实例。返冻结购买基准的25% + 实际基础强化金币的20%，各向下取整。免费预强化不虚构退款。打造、重铸、精炼、重锻及其补差不退。","Selling removes this instance permanently. Return 25% of frozen purchase baseline plus 20% of actual basic enhancement gold, each rounded down. Free ranks create no refund. Creation, reforge, refine, rerolls and reroll makeup are excluded.")
		"dismantle": return _t("拆解永久移除这一实例。品质基础材料 + 实际基础强化锻材/族材各50%向下取整，保留原材料ID。核心、金币、打造及其它改善材料不退。","Dismantling removes this instance permanently. Return rarity base materials plus 50% of actual basic enhancement forge/race materials, rounded down by original material ID. No cores, gold, creation or other improvement materials are refunded.")
	return ""

static func _material_name(id: String) -> String:
	if id == "forge": return _t("锻材","Forge material")
	return id.get_slice(":",1)+(_t("族材"," material") if id.begins_with("race:") else _t("核心"," core"))

static func _cost_text(quote: Dictionary,kind: String,record: Dictionary = {}) -> String:
	if not quote.has("gold"): return _t("暂不可操作：","Unavailable: ")+error_text(str(quote.get("error","")))
	var lines: PackedStringArray = [_t("本次成本","COST"),_t("金币 %d / 持有 %d","Gold %d / owned %d") % [int(quote.get("gold",0)),int(Game.profile.permanent_gold)]]
	for id: String in quote.get("materials",{}): lines.append(_material_name(id)+" %d / %d" % [int(quote.materials[id]),int(Game.profile.get("materials",{}).get(id,0))])
	if kind == "inherit":
		lines.append(_t("固定手续费：100金（不乘装备等级）","Fixed fee: 100 gold (unscaled)"))
		var base_sum := 0
		for index in quote.get("base_makeup",[]).size():
			var amount := int(quote.base_makeup[index])
			base_sum += amount
			lines.append(_t("基础第%d阶补差：%d金","Base step %d makeup: %d gold") % [index+1,amount])
		lines.append(_t("基础补差合计：%d金","Base makeup subtotal: %d gold") % base_sum)
		var reroll_sum := 0
		for row: Dictionary in quote.get("reroll_makeup",[]):
			reroll_sum += int(row.amount)
			lines.append(_t("重锻第%d阶补差：%d金 · %s","Reroll step %d makeup: %d gold · %s") % [int(row.rank),int(row.amount),str(row.operation_id)])
		lines.append(_t("重锻补差合计：%d金（不可退款）","Reroll makeup subtotal: %d gold (nonrefundable)") % reroll_sum)
	if kind in ["sell","dismantle"]:
		lines.append(_t("本次回收获得","RETURN"))
		if kind == "sell":
			lines.append(_t("金币：%d","Gold: %d") % int(quote.get("gold_return",0)))
			var paid := 0
			for entry: Dictionary in record.get("enhancement_gold_ledger",[]):
				if entry.get("kind") in ["enhancement","enhancement_makeup"]: paid += int(entry.amount)
			@warning_ignore("integer_division")
			var base_return: int = int(record.get("purchase_baseline_gold",0))/4
			@warning_ignore("integer_division")
			var paid_return: int = paid/5
			lines.append(_t("冻结基准返还：%d金\n可退实际强化金币%d → 返还%d金","Frozen baseline return: %d gold\nRefundable actual enhancement %d → %d gold") % [base_return,paid,paid_return])
		elif not record.is_empty():
			var base: Dictionary = Numbers.value("salvage_base")[record.rarity]
			lines.append(_t("品质基础：%d锻材 + %d族材","Rarity base: %d forge + %d race material") % [int(base.common),int(base.race)])
			var paid := {}
			for entry: Dictionary in record.get("material_ledger",[]):
				if entry.get("kind") == "enhancement" and (entry.material_id == "forge" or str(entry.material_id).begins_with("race:")): paid[entry.material_id] = int(paid.get(entry.material_id,0))+int(entry.amount)
			for material: String in paid:
				@warning_ignore("integer_division")
				var returned: int = int(paid[material])/2
				lines.append(_material_name(material)+_t("：实付%d → 返还%d"," paid %d → return %d") % [int(paid[material]),returned])
		for id: String in quote.get("materials_return",{}): lines.append(_material_name(id)+": "+str(int(quote.materials_return[id])))
		lines.append(_t("锁定、已装备、待领取、待提交词条时不可回收。","Locked, equipped, pending collection or pending reforge items cannot be recycled."))
	return "\n".join(lines)

static func _affordable(quote: Dictionary) -> bool:
	if int(Game.profile.permanent_gold) < int(quote.get("gold",0)): return false
	for id: String in quote.get("materials",{}):
		if int(Game.profile.get("materials",{}).get(id,0)) < int(quote.materials[id]): return false
	return true

static func _render_pending(panel: Control,right: Control,record: Dictionary) -> void:
	var pending: Dictionary = record.pending_reforge
	_label(right,_t("已付款的冻结候选 · 退出/重载不重抽","PAID, FROZEN CANDIDATE · REOPENING DOES NOT REROLL"),Vector2(16,129),Vector2(884,38),18).name = "PendingReforge"
	var request := {"hero_id":Game.profile.selected_hero,"instance_id":record.instance_id,"expected_revision":int(record.get("forge_revision",0)),"pending_operation_id":pending.operation_id,"choice":"replace"}
	var quote: Dictionary = Game.call("quote_forging_v2","resolve_reforge",request) if Game.has_method("quote_forging_v2") else {}
	var rows := _detail_scroll(right,"PendingReforgeDetails",Vector2(16,179),Vector2(884,225))
	_text_row(rows,_t("旧：","Old: ")+_caption(str(pending.old_affix.type))+" u"+str(int(pending.old_affix.u))+"\n"+_t("新：","New: ")+_caption(str(pending.new_affix.type))+" u"+str(int(pending.new_affix.u)),"PendingReforgeComparison")
	_text_row(rows,_stat_lines(quote.get("before_stats",{}),quote.get("after_stats",{})),"PendingReforgeStats")
	_text_row(rows,_t("选择不会再次扣款。保留旧词条也不退还已经支付的费用；绑定槽位保持。","This choice costs nothing further. Keeping the old affix does not refund the paid fee; the slot stays bound."),"PendingReforgeRules")
	var message: String = panel.forge_message
	if message.is_empty() and not bool(quote.get("ok",false)): message = error_text(str(quote.get("error","")))
	_label(right,message,Vector2(16,419),Vector2(884,36),13).name = "ForgeResult"
	var retry: bool = not panel.forge_transaction_id.is_empty()
	if retry:
		var button := MineStyle.button(right,"",Vector2(16,466),Vector2(660,34),func(): _submit(panel,panel.forge_frozen_kind,panel.forge_frozen_request))
		button.name = "PrimaryAction"
		button.text = _t("重试已选结果并保存","Retry saving the chosen result")
		button.disabled = panel.busy
		panel.action_button = button
		_cancel_retry_button(panel,right)
	else:
		var keep := MineStyle.button(right,"",Vector2(16,466),Vector2(432,34),func(): var choice := request.duplicate(true); choice.choice = "keep"; _submit(panel,"resolve_reforge",choice))
		keep.name = "KeepReforge"
		keep.text = _t("保留旧词条","Keep old affix")
		keep.disabled = panel.busy or not bool(quote.get("ok",false))
		var replace := MineStyle.button(right,"",Vector2(466,466),Vector2(434,34),func(): _submit(panel,"resolve_reforge",request))
		replace.name = "ReplaceReforge"
		replace.text = _t("替换为新词条","Replace with new affix")
		replace.disabled = keep.disabled
		panel.action_button = replace

static func _cancel_retry_button(panel: Control,right: Control) -> void:
	var button := MineStyle.button(right,"",Vector2(690,466),Vector2(210,34),func():
		if panel.busy: return
		if Game.has_method("cancel_pending_forging_v2") and bool(Game.call("cancel_pending_forging_v2",panel.forge_transaction_id)):
			_clear_retry(panel)
			panel.forge_message = _t("未付款操作已取消。","Unpaid attempt cancelled.")
			panel._render())
	button.name = "CancelForgeRetry"
	button.text = _t("取消未付款操作","Cancel unpaid attempt")
	button.add_theme_font_size_override("font_size",12)
	button.disabled = panel.busy

static func _clear_retry(panel: Control) -> void:
	panel.forge_transaction_id = ""
	panel.forge_frozen_kind = ""
	panel.forge_frozen_request = {}

static func _toggle_lock(panel: Control,record: Dictionary) -> void:
	if _locked(panel) or not Game.has_method("set_equipment_lock_v2"): return
	var result: Variant = Game.call("set_equipment_lock_v2",str(record.instance_id),not bool(record.lock_state))
	var success: bool = result if result is bool else bool(result.get("ok",false))
	panel.forge_message = _t("锁定状态已保存。","Lock state saved.") if success else error_text(Game.last_error)
	panel._render()

static func _confirm_or_submit(panel: Control,kind: String,request: Dictionary,quote: Dictionary) -> void:
	if panel.busy or panel.action_button == null or panel.action_button.disabled: return
	if kind not in ["sell","dismantle"] or not panel.forge_transaction_id.is_empty():
		_submit(panel,kind,request)
		return
	panel.busy = true
	panel.action_button.disabled = true
	var modal: Panel = panel.app._push_modal(_t("确认回收这一实例","Confirm recycling this instance"),Vector2(780,460))
	modal.name = "ForgeRecycleConfirmation"
	var rows := _detail_scroll(modal,"ForgeConfirmDetails",Vector2(28,88),Vector2(724,268))
	_text_row(rows,str(request.instance_id)+"\n"+_cost_text(quote,kind,Game.profile.equipment[request.instance_id])+"\n"+_rules_text(kind,Game.profile.equipment[request.instance_id],1),"ForgeConfirmSummary")
	modal.get_parent().tree_exiting.connect(func():
		if is_instance_valid(panel) and panel.is_inside_tree() and panel.busy:
			panel.busy = false
			panel._render())
	var actions := MineStyle.action_pair(modal,"BACK","",382,func(): panel.busy = false; panel.app._pop_modal(); panel._render(),func(): _commit_confirmation(panel,modal,kind,request))
	actions[0].name = "CancelForgeRecycle"
	actions[1].name = "ConfirmForgeRecycle"
	actions[1].text = _title(kind)+_t("这一实例"," this instance")
	MineStyle.button_skin(actions[1],"danger")
	actions[0].grab_focus()

static func _commit_confirmation(panel: Control,modal: Panel,kind: String,request: Dictionary) -> void:
	if not is_instance_valid(modal) or not panel.busy: return
	var button := modal.find_child("ConfirmForgeRecycle",true,false) as Button
	if button == null or button.disabled: return
	button.disabled = true
	panel.busy = false
	panel.app._pop_modal()
	_submit(panel,kind,request)

static func _submit(panel: Control,kind: String,request: Dictionary) -> void:
	if panel.busy or not Game.has_method("forge_equipment_v2"): return
	panel.busy = true
	if panel.action_button != null: panel.action_button.disabled = true
	if panel.forge_transaction_id.is_empty():
		panel.forge_transaction_id = "forge:"+Crypto.new().generate_random_bytes(16).hex_encode()
		panel.forge_frozen_kind = kind
		panel.forge_frozen_request = request.duplicate(true)
	var result: Dictionary = Game.call("forge_equipment_v2",panel.forge_frozen_kind,panel.forge_frozen_request,panel.forge_transaction_id)
	if bool(result.get("ok",false)):
		panel.forge_message = _t("交易已保存。","Transaction saved.")
		panel.forge_result_details = _result_text(result.get("receipt",{}))
		_clear_retry(panel)
	else:
		panel.forge_message = error_text(str(result.get("error",Game.last_error)))
		var pending: Dictionary = Game.call("pending_forging_v2") if Game.has_method("pending_forging_v2") else {}
		if pending.is_empty(): _clear_retry(panel)
		else: panel.forge_message += _t(" 重试将保留同一结果。"," Retrying preserves the same result.")
	await panel.get_tree().create_timer(0.25).timeout
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	panel.busy = false
	panel._render()

static func _result_text(receipt: Dictionary) -> String:
	var lines: PackedStringArray = []
	var request: Dictionary = receipt.get("request",{})
	var id := str(request.get("target_instance_id",request.get("instance_id","")))
	var before: Dictionary = receipt.get("before",{}).get(id,{})
	var after: Dictionary = receipt.get("after",{}).get(id,{})
	if not before.is_empty() and not after.is_empty():
		var old_main := Instances.main_stats(before)
		var new_main := Instances.main_stats(after)
		lines.append(_t("上次结果 F %.2f → %.2f","Last result F %.2f → %.2f") % [_factor(before),_factor(after)])
		lines.append(_stat_lines(old_main,new_main))
		if _factor(after) > _factor(before) and old_main == new_main:
			lines.append(_t("潜力提高；尚未跨过整数舍入边界，当前整数属性未变。","Potential improved; no integer rounding boundary was crossed, so current integer attributes are unchanged."))
	var outcome: Dictionary = receipt.get("result",{})
	if outcome.has("old_gain"):
		lines.append(_t("本阶 g %d%% → %d%%；c %d → %d；已付%d金，不退款。","This step g %d%% → %d%%; c %d → %d; paid %d gold, nonrefundable.") % [int(outcome.old_gain),int(outcome.gain),int(outcome.old_pity),int(outcome.pity),int(receipt.get("gold",0))])
	return "\n".join(lines)

static func error_text(code: String) -> String:
	var messages := {
		"INVALID_REQUEST":["请选择可用的来源实例、强化阶或词条。","Select an available source instance, enhancement step or affix."],"INCOMPATIBLE_SOURCE":["来源必须与目标同部位、同类型。","Source and target must share slot and power type."],
		"STALE_INSTANCE":["装备已变化，请重新选择操作。","This item changed; select the operation again."],"INSTANCE_NOT_FOUND":["该实例已不在背包中。","This instance is no longer in inventory."],
		"PENDING_FORGE_RETRY":["先重试或取消未付款的保存失败交易。","Retry or cancel the unpaid failed-save attempt first."],"STORAGE_TOO_LARGE":["保存容量不足；资产未改变。","Save capacity exceeded; assets are unchanged."],
		"INSTANCE_LOCKED":["装备已锁定；先解锁。","Item locked; unlock it first."],"INSTANCE_EQUIPPED":["已装备物品不能出售或拆解。","Equipped items cannot be sold or dismantled."],
		"INSTANCE_PENDING":["先领取待结算装备。","Collect this pending item first."],"TRANSACTION_PENDING":["先选择已付款的重铸结果。","Resolve the paid reforge first."],
		"ENHANCEMENT_LEVEL_LOCKED":["角色等级不足：Lv5/10/15/20开放+3/+5/+8/+10。","Hero level gate: Lv5/10/15/20 unlock +3/+5/+8/+10."],"REROLL_LEVEL_LOCKED":["阶重锻需要角色Lv10。","Step reroll requires hero Lv10."],
		"MAX_ENHANCEMENT":["强化已达+10上限。","Enhancement is already +10."],"MAX_GAIN":["该阶g已达12%。","This step is already g=12%."],"RANK_NOT_FOUND":["没有可重锻的这一阶。","That enhancement step does not exist."],
		"MAX_QUANTILE":["词条u已满100。","Affix u is already 100."],"NO_EFFECTIVE_IMPROVEMENT":["当前配装已封顶或实际值不变；不收取费用。","This loadout is capped or unchanged; no charge is allowed."],
		"NO_IMPROVEMENT":["继承后总增幅不会提高；不收取费用。","Inheritance would not improve total gain; no charge."],"NO_FLAT_MAIN":["此件没有可强化的平值主属性。","This item has no flat main attribute to improve."],
		"SOURCE_RANK_TOO_LOW":["来源强化阶数不得低于目标。","Source rank must be at least target rank."],"AFFIX_NOT_FOUND":["此件没有可选的普通词条。","This item has no selectable ordinary affix."],
		"INSUFFICIENT_GOLD":["金币不足。","Not enough gold."],"INSUFFICIENT_MATERIALS":["材料不足。","Not enough materials."],"STORAGE_DOCUMENT_TOO_LARGE":["保存容量不足；资产未改变。","Save capacity exceeded; assets are unchanged."]}
	return _t(messages[code][0],messages[code][1]) if messages.has(code) else code
