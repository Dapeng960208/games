extends VBoxContainer
## Shared complete, scrollable source table for camp and expedition screens.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")

func configure(data: Dictionary, width: float, prefix: String = "HeroAttribute_") -> void:
	name = "CharacterStatSheet"
	custom_minimum_size.x = width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",5)
	set_meta("breakdown",data.duplicate(true))
	_line(Inspect.t("角色基础 + 等级成长 + 装备变化 = 当前总值", "Base + level growth + gear change = current total"),width,14,MineStyle.MUTED)
	_table_row([Inspect.t("属性","Attribute"),Inspect.t("基础","Base"),Inspect.t("成长","Level"),Inspect.t("装备","Gear"),Inspect.t("总值","Total")],width,true)
	for group: Array in Inspect.GROUPS:
		_heading(Inspect.t(group[0],group[1]),width)
		for key: String in group[2]:
			var base := float(data.intrinsic.get(key,0))
			var growth := float(data.leveled.get(key,0))-base
			var gear := float(data.total.get(key,0))-float(data.leveled.get(key,0))
			var total := float(data.total.get(key,0))
			var row := _table_row([Inspect.caption(key),Inspect.value(key,base),Inspect.value(key,growth,true),Inspect.value(key,gear,true),Inspect.value(key,total)],width)
			row.name = "StatSource_"+key
			row.set_meta("sources",{"base":base,"growth":growth,"gear":gear,"total":total})
			row.get_child(4).name = prefix+key
			row.tooltip_text = Inspect.caption(key)+"\n"+Inspect.value(key,base)+" + "+Inspect.value(key,growth,true)+" + "+Inspect.value(key,gear,true)+" = "+Inspect.value(key,total)
			if key in ["attack_interval","armor_damage_reduction","magic_damage_reduction"]:
				row.tooltip_text += "\n"+Inspect.t("装备列显示按真实公式计算的总值变化；间隔越低越快，减伤由护甲/魔抗推导。", "Gear shows the resolved change: lower intervals are faster; reductions derive from armor/resistance.")
	for note: String in Inspect.cap_notes(data.total): _line(note,width,14,MineStyle.AMBER)
	var changed := false
	for group: Array in Inspect.GROUPS:
		for key: String in group[2]:
			if is_equal_approx(float(data.live.get(key,0)),float(data.total.get(key,0))): continue
			if not changed: _heading(Inspect.t("当前战斗变化","CURRENT COMBAT CHANGES"),width); changed = true
			_line(Inspect.caption(key)+"  "+Inspect.value(key,float(data.total.get(key,0)))+" → "+Inspect.value(key,float(data.live[key])),width,15,MineStyle.CYAN)
	_heading(Inspect.t("装备词条与套装 · 条件效果","AFFIXES & SETS · CONDITIONAL EFFECTS"),width)
	_line(Inspect.t("下列效果满足条件后触发，未触发的伤害、护盾或恢复不会计入上方常驻数值。", "These effects require their stated conditions. Untriggered damage, shields and recovery are not counted in permanent values."),width,14,MineStyle.MUTED)
	for slot: String in ContentRegistry.SLOTS:
		var id := str(data.total.get("loadout",{}).get(slot,""))
		var item: Dictionary = ContentRegistry.equipment(id)
		if item.is_empty(): continue
		_line(MineStyle.content_text(item,"name")+" +"+str(data.owned.get(id,{}).get("level",0)),width,15,MineStyle.CYAN)
		_line(MineStyle.content_text(item,"affix_text"),width,14)
	for id: String in data.total.get("sets",{}):
		var set_data: Dictionary = ContentRegistry.sets().get(id,{})
		var count := int(data.total.sets[id])
		_line(MineStyle.content_text(set_data,"name")+" · %d/6" % count,width,17,MineStyle.AMBER)
		for tier: int in [2,4,6]:
			_line((Inspect.t("已激活 ","Active ") if count >= tier else Inspect.t("未激活 ","Inactive "))+str(tier)+Inspect.t(" 件："," pieces: ")+MineStyle.content_text(set_data.get("thresholds",{}).get(str(tier),{}),"text"),width,14,MineStyle.GREEN if count >= tier else MineStyle.MUTED)
	var hero: Dictionary = ContentRegistry.hero(str(data.hero_id))
	var passive: Dictionary = hero.get("passive",{})
	_heading(Inspect.t("职业被动 · ","HERO PASSIVE · ")+MineStyle.content_text(passive,"name"),width)
	_line(MineStyle.content_text(passive,"description"),width,14)

func _table_row(values: Array, width: float, header: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(width,30)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation",0)
	add_child(row)
	for i: int in values.size():
		var span := width*.36 if i == 0 else width*.16
		var label := _line(str(values[i]),span,13 if header else 14,MineStyle.AMBER if header else MineStyle.INK if i == 4 else MineStyle.MUTED,row)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 30
		if i > 0: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row

func _heading(text: String, width: float) -> void:
	var label := _line(text,width,17,MineStyle.AMBER)
	label.custom_minimum_size.y = 30

func _line(text: String, width: float, font_size: int = 14, tint: Color = MineStyle.INK, owner: Node = self) -> Label:
	var label := MineStyle.literal(owner,text,Vector2.ZERO,Vector2(width,0),font_size,tint)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label
