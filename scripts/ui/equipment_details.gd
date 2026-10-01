extends VBoxContainer
## Complete numbers are always in the detail pane, never truncated tooltips only.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Advice = preload("res://scripts/ui/equipment_advice.gd")

func configure(item: Dictionary, level: int, width: float, hero_id: String, before: Dictionary, after: Dictionary, page: String = "stats") -> void:
	name = "EquipmentDetailContent"
	custom_minimum_size.x = width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",6)
	set_meta("item_id",str(item.get("instance_id",item.get("id",""))))
	set_meta("level",level)
	if page == "compare":
		_compare(hero_id,before,after,width)
	elif page == "set":
		set_changes(self,before,after,width,str(item.get("set_id","")))
	else:
		_heading(Inspect.t("装备属性 · 强化 +%d 实际值","ITEM ATTRIBUTES · ACTUAL +%d VALUES") % level,width)
		_row([Inspect.t("属性","Attribute"),Inspect.t("基础","Base"),Inspect.t("强化","Refine"),Inspect.t("实际","Actual")],width,true)
		var base := Inspect.item_values(item,0,hero_id)
		var actual := Inspect.item_values(item,level,hero_id)
		for key: String in actual:
			var row := _row([Inspect.caption(key),Inspect.value(key,float(base.get(key,0)),false,true),Inspect.value(key,float(actual[key])-float(base.get(key,0)),true,true),Inspect.value(key,float(actual[key]),false,true)],width)
			row.name = "ItemStat_"+key
			row.set_meta("values",{"base":float(base.get(key,0)),"refinement":float(actual[key])-float(base.get(key,0)),"actual":float(actual[key])})
		if actual.is_empty(): _line(Inspect.t("无常驻基础属性，查看下方专属词条。","No permanent base stats; see the special affix below."),width,14)
		_heading(Inspect.t("专属词条 · 条件触发","SPECIAL AFFIX · CONDITIONAL"),width)
		_line(MineStyle.content_text(item,"affix_text",Inspect.t("无专属词条","No special affix")),width,15)
		_line(Inspect.t("强化只提高基础属性；词条需满足条件，未触发时不计入角色常驻数值。","Refinement increases base stats. Affixes require their conditions and are separate from permanent character values."),width,13,MineStyle.MUTED)
		if actual.has("max_mana") and str(ContentRegistry.hero(hero_id).get("resource_type","")) != "mana":
			_line(Inspect.t("当前英雄使用非魔法资源，此法力加成不生效。","This hero uses a non-mana resource; this mana bonus does not apply."),width,14,MineStyle.AMBER)

func _compare(hero: String, before: Dictionary, after: Dictionary, width: float) -> void:
	_heading(Inspect.t("角色属性 · 当前 → 更换 / 强化后","CHARACTER VALUES · CURRENT → PREVIEW"),width)
	var summary := Control.new()
	summary.name = "EquipmentAdvice"
	summary.set_meta("before",before.duplicate(true))
	summary.set_meta("after",after.duplicate(true))
	add_child(summary)
	var lines := Advice.summarize(hero,before,after)
	summary.custom_minimum_size = Vector2(width,22*mini(3,lines.size()))
	for index: int in mini(3,lines.size()):
		var label := MineStyle.literal(summary,lines[index],Vector2(0,index*22),Vector2(width,22),14,MineStyle.RED if index == 0 and not Advice.lost_tiers(before,after).is_empty() else MineStyle.CYAN)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = lines[index]
	_row([Inspect.t("属性","Attribute"),Inspect.t("当前","Current"),Inspect.t("预览","Preview"),Inspect.t("变化","Change")],width,true)
	var count := 0
	for group: Array in Inspect.GROUPS:
		for key: String in group[2]:
			var old := float(before.get(key,0))
			var next := float(after.get(key,0))
			if is_equal_approx(old,next): continue
			count += 1
			var gain := next < old if key == "attack_interval" else next > old
			var row := _row([Inspect.caption(key),Inspect.value(key,old),Inspect.value(key,next),Inspect.value(key,next-old,true)],width)
			row.name = "CompareStat_"+key
			row.set_meta("values",{"current":old,"preview":next,"delta":next-old})
			row.get_child(3).add_theme_color_override("font_color",MineStyle.GREEN if gain else MineStyle.RED)
	if count == 0: _line(Inspect.t("常驻属性不变，请比较词条与套装。","Permanent values are unchanged; compare affixes and sets."),width,14,MineStyle.MUTED)
	for note: String in Inspect.cap_notes(after): _line(note,width,13,MineStyle.AMBER)
	set_changes(self,before,after,width)

static func set_changes(owner: Node, before: Dictionary, after: Dictionary, width: float, selected_set: String = "") -> void:
	var ids: Array = before.get("sets",{}).keys()
	for id: String in after.get("sets",{}):
		if not ids.has(id): ids.append(id)
	if not selected_set.is_empty() and not ids.has(selected_set): ids.append(selected_set)
	ids.sort()
	if ids.is_empty(): flow(owner,Inspect.t("此装备不属于套装。","This item has no set."),width,15,MineStyle.MUTED)
	for id: String in ids:
		var data: Dictionary = ContentRegistry.sets().get(id,{})
		var old := int(before.get("sets",{}).get(id,0))
		var next := int(after.get("sets",{}).get(id,0))
		flow(owner,MineStyle.content_text(data,"name")+" · %d → %d / %d" % [old,next,8 if int(after.get("ruleset_version",1)) == 2 else 6],width,17,MineStyle.AMBER)
		for tier: int in [2,4,6]:
			var gained := old < tier and next >= tier
			var lost := old >= tier and next < tier
			var state := Inspect.t("将激活","Gained") if gained else Inspect.t("将失去","Lost") if lost else Inspect.t("已激活","Active") if next >= tier else Inspect.t("未激活","Inactive")
			var label := flow(owner,"%s · %d" % [state,tier]+Inspect.t(" 件："," pieces: ")+MineStyle.content_text(data.get("thresholds",{}).get(str(tier),{}),"text"),width,14,MineStyle.GREEN if gained else MineStyle.RED if lost else MineStyle.MUTED)
			label.name = "SetEffect_"+id+"_"+str(tier)
			label.set_meta("state",state)

func _row(values: Array, width: float, header: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(width,32)
	row.add_theme_constant_override("separation",0)
	add_child(row)
	for i: int in values.size():
		var span := width*.40 if i == 0 else width*.20
		var label := flow(row,str(values[i]),span,13,MineStyle.AMBER if header else MineStyle.INK if i == 3 else MineStyle.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.y = 32
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i > 0: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row

func _heading(text: String, width: float) -> void:
	_line(text,width,16,MineStyle.CYAN).custom_minimum_size.y = 28

func _line(text: String, width: float, font_size: int = 14, tint: Color = MineStyle.INK) -> Label:
	return flow(self,text,width,font_size,tint)

static func flow(owner: Node, text: String, width: float, font_size: int = 14, tint: Color = MineStyle.INK) -> Label:
	var label := MineStyle.literal(owner,text,Vector2.ZERO,Vector2(width,0),font_size,tint)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label
