extends VBoxContainer
## Complete numbers are always in the detail pane, never truncated tooltips only.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Numbers = preload("res://config/numerical_rules.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Advice = preload("res://scripts/ui/equipment_advice.gd")

func configure(item: Dictionary, level: int, width: float, hero_id: String, before: Dictionary, after: Dictionary, page: String = "stats") -> void:
	name = "EquipmentDetailContent"
	custom_minimum_size.x = width
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation",6)
	set_meta("item_id",str(item.get("instance_id",item.get("id",""))))
	set_meta("level",level)
	var version := 2 if item.get("instance_record") is Dictionary else int(after.get("ruleset_version",1))
	if page == "compare":
		_compare(hero_id,before,after,width)
	elif page == "set":
		set_changes(self,before,after,width,str(item.get("set_id","")))
	else:
		_heading(Inspect.t("装备属性 · 强化 +%d","ATTRIBUTES · +%d") % level,width)
		_row([Inspect.t("属性","Attribute"),Inspect.t("基础","Base"),Inspect.t("强化","Refine"),Inspect.t("实际","Actual")],width,true)
		var base := Inspect.item_values(item,0,hero_id)
		var actual := Inspect.item_values(item,level,hero_id)
		for key: String in actual:
			if version == 2 and is_zero_approx(float(actual[key])): continue
			var row := _row([Inspect.caption(key),Inspect.value(key,float(base.get(key,0)),false,true,version),Inspect.value(key,float(actual[key])-float(base.get(key,0)),true,true,version),Inspect.value(key,float(actual[key]),false,true,version)],width)
			row.name = "ItemStat_"+key
			row.set_meta("values",{"base":float(base.get(key,0)),"refinement":float(actual[key])-float(base.get(key,0)),"actual":float(actual[key])})
		if actual.is_empty(): _line(Inspect.t("无常驻基础属性，查看下方专属词条。","No permanent base stats; see the special affix below."),width,14)
		if version == 2: _line(Inspect.t("基础列含未强化主属性＋普通词条；下方k范围只表示主属性。", "Base includes unenhanced main stats + random affixes. The k range below is for main stats only."),width,13,MineStyle.MUTED).name = "BaseIncludesAffixes"
		if item.get("instance_record") is Dictionary: _instance_rolls(item.instance_record,width)
		_heading(Inspect.t("专属词条 · 条件触发","SPECIAL AFFIX · CONDITIONAL"),width)
		_line(MineStyle.content_text(item,"affix_text",Inspect.t("无专属词条","No special affix")),width,15)
		_line(Inspect.t("强化只提高平值主属性；普通随机词条不吃强化，专属特性按条件触发。","Enhancement increases flat main attributes only. Random affixes do not scale with enhancement; special traits trigger under their stated conditions.") if version == 2 else Inspect.t("强化提高基础属性；专属词条按条件触发。","Refinement increases base stats; special affixes require their conditions."),width,13,MineStyle.MUTED)
		if float(actual.get("max_mana",0)) > 0 and str(ContentRegistry.hero(hero_id).get("resource_type","")) != "mana":
			_line(Inspect.t("当前英雄使用非魔法资源，此法力加成不生效。","This hero uses a non-mana resource; this mana bonus does not apply."),width,14,MineStyle.AMBER)

	if item.get("instance_record") is Dictionary:
		var record: Dictionary = item.instance_record
		_line("iLv %d · %s · %s" % [int(record.item_level),Inspect.rarity_name(str(record.rarity)),Inspect.type_name(str(record.power_type))],width,15,Inspect.rarity_color(item)).name = "InstanceIdentity"
		var identity := _line(Inspect.t("实例：","Instance: ")+str(record.instance_id),width,11,MineStyle.MUTED)
		identity.name = "InstanceId"
		identity.autowrap_mode = TextServer.AUTOWRAP_OFF
		identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var waiver := Inspect.waiver_note(record,hero_id)
		if not waiver.is_empty(): _line(waiver,width,14,MineStyle.AMBER).name = "LegacyEquipWaiver"

func _compare(hero: String, before: Dictionary, after: Dictionary, width: float) -> void:
	var version := int(after.get("ruleset_version",1))
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
			var row := _row([Inspect.caption(key),Inspect.value(key,old,false,false,version),Inspect.value(key,next,false,false,version),Inspect.value(key,next-old,true,false,version)],width)
			row.name = "CompareStat_"+key
			row.set_meta("values",{"current":old,"preview":next,"delta":next-old})
			row.get_child(3).add_theme_color_override("font_color",MineStyle.GREEN if gain else MineStyle.RED)
	if count == 0: _line(Inspect.t("常驻属性不变，请比较词条与套装。","Permanent values are unchanged; compare affixes and sets."),width,14,MineStyle.MUTED)
	if version == 2: _combat_comparison(hero,before,after,width)
	for note: String in Inspect.cap_notes(after): _line(note,width,13,MineStyle.AMBER)
	set_changes(self,before,after,width)

func _instance_rolls(record: Dictionary, width: float) -> void:
	_heading(Inspect.t("主属性分位与范围","MAIN ROLLS & RANGES"),width)
	var low := record.duplicate(true)
	var high := record.duplicate(true)
	for key: String in record.main_rolls:
		low.main_rolls[key] = 0
		high.main_rolls[key] = 100
	var low_stats := Instances.main_stats(low)
	var high_stats := Instances.main_stats(high)
	var actual := Instances.main_stats(record)
	for key: String in actual:
		_line(Inspect.caption(key)+" · k %d/100 · %s [%s–%s]" % [int(record.main_rolls[key]),Inspect.value(key,float(actual[key]),false,true,2),Inspect.value(key,float(low_stats[key]),false,true,2),Inspect.value(key,float(high_stats[key]),false,true,2)],width,14).name = "MainRoll_"+key
	if not record.affix_type_and_quantile.is_empty():
		_heading(Inspect.t("普通词条分位与范围","RANDOM AFFIX ROLLS & RANGES"),width)
		for index: int in record.affix_type_and_quantile.size():
			low.affix_type_and_quantile[index].u = 0
			high.affix_type_and_quantile[index].u = 100
		low_stats = Instances.affix_stats(low)
		high_stats = Instances.affix_stats(high)
		actual = Instances.affix_stats(record)
		for affix: Dictionary in record.affix_type_and_quantile:
			var key: String = affix.type
			_line(Inspect.caption(key)+" · u %d/100 · %s [%s–%s]" % [int(affix.u),Inspect.value(key,float(actual[key]),false,true,2),Inspect.value(key,float(low_stats[key]),false,true,2),Inspect.value(key,float(high_stats[key]),false,true,2)],width,14).name = "AffixRoll_"+key
	var gains := 0
	var steps: PackedStringArray = []
	for index: int in record.enhancement_steps.size():
		var step: Dictionary = record.enhancement_steps[index]
		gains += int(step.g)
		steps.append("+%d: g %d%% · c %d/3" % [index+1,int(step.g),int(step.pity)])
	_line(Inspect.t("强化倍率 F %.2f；每阶增幅加算","Enhancement F %.2f; step gains add") % (1.0+gains/100.0)+( "\n"+"\n".join(steps) if not steps.is_empty() else ""),width,14,MineStyle.MUTED).name = "InstanceEnhancement"

func _combat_comparison(hero: String, before: Dictionary, after: Dictionary, width: float) -> void:
	_heading(Inspect.t("战斗参考 · 条件效果未触发","COMBAT ESTIMATES · NO CONDITIONAL PROCS"),width)
	_line(Inspect.t("有效生命假定零穿透；普攻期望DPS含常驻暴击/增伤，不含弱点、连击、目标减伤；Q显示每包基础整数。", "Effective HP assumes zero penetration. Expected basic DPS includes permanent crit/bonus, excluding weak points, combos and target mitigation. Q shows each base packet."),width,13,MineStyle.MUTED)
	var old := Advice.combat_metrics(hero,before)
	var next := Advice.combat_metrics(hero,after)
	for entry: Array in [["physical_ehp","物理有效生命 ≈","Physical effective HP ≈"],["magic_ehp","魔法有效生命 ≈","Magic effective HP ≈"],["basic_dps","普攻期望DPS ≈","Expected basic DPS ≈"],["q_packet","Q 每包基础伤害","Q base damage / packet"]]:
		var key: String = entry[0]
		var integer_packet := key == "q_packet" and int(after.get("ruleset_version",1)) == 2
		var old_text := str(int(old[key])) if integer_packet else "%.1f" % float(old[key])
		var next_text := str(int(next[key])) if integer_packet else "%.1f" % float(next[key])
		_line(Inspect.t(entry[1],entry[2])+"  "+old_text+" → "+next_text,width,14).name = "CombatCompare_"+key

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
	row.custom_minimum_size = Vector2(width,34)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation",0)
	add_child(row)
	for i: int in values.size():
		var span := width*.43 if i == 0 else width*.19
		var label := flow(row,str(values[i]),span,12 if width < 350 else 13,MineStyle.MUTED if header else MineStyle.INK if i == 3 else MineStyle.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.y = 34
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if not header:
			var background := MineStyle.box(Color(MineStyle.COPPER,.035 if get_child_count() % 2 == 0 else .075),Color(0,0,0,0),0)
			background.shadow_size = 0
			background.content_margin_left = 2
			background.content_margin_right = 2
			label.add_theme_stylebox_override("normal",background)
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
