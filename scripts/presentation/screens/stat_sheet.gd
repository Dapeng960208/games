extends VBoxContainer
## Shared complete, scrollable source table for camp and expedition screens.
const SkillInspect = preload("res://scripts/presentation/screens/skill_inspection.gd")
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")

func configure(data: Dictionary, width: float, prefix: String = "HeroAttribute_") -> void:
	name = "CharacterStatSheet"
	custom_minimum_size.x = width
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",7)
	set_meta("breakdown",data.duplicate(true))
	var version := int(data.total.get("ruleset_version",1))
	var expanded := version == 2
	_line(Inspect.t("基础 + 等级 + 天赋 + 装备 + 当前效果 = 总值；pp = 百分点", "Base + level + talents + gear + effects = total; pp = percentage points") if expanded else Inspect.t("角色基础 + 等级成长 + 装备变化 = 当前总值", "Base + level growth + gear change = current total"),width,14,GameStyle.MUTED)
	if expanded:
		var curve: Dictionary = preload("res://scripts/infrastructure/content/runtime_rules.gd").value("hero_class_profiles",{}).get(str(data.hero_id),{}).get("growth",{})
		if not curve.is_empty():
			_line(Inspect.t("每级按初始值增加：生命 %.1f%% · 攻击 %.1f%% · 法强 %.1f%%；护甲 +%d / 魔抗 +%d", "Per level, based on starting stats: HP %.1f%% · attack %.1f%% · spell power %.1f%%; armor +%d / magic resistance +%d") % [100*float(curve.max_hp),100*float(curve.attack),100*float(curve.ability_power),int(curve.armor),int(curve.magic_resist)],width,13,GameStyle.CYAN).name = "ClassGrowthFormula"
	var headers: Array = [Inspect.t("属性","Attribute"),Inspect.t("基础","Base"),Inspect.t("成长","Level")]
	if expanded: headers.append(Inspect.t("天赋","Talent"))
	headers.append(Inspect.t("装备","Gear"))
	if expanded: headers.append(Inspect.t("效果","Buff"))
	headers.append(Inspect.t("总值","Total"))
	_table_row(headers,width,true)
	for group: Array in Inspect.GROUPS:
		_heading(Inspect.t(group[0],group[1]),width)
		for key: String in group[2]:
			if not expanded and key in ["hp_ratio","resource_gain_bonus"]: continue
			var base := float(data.intrinsic.get(key,0))
			var leveled := float(data.leveled.get(key,0))
			var talented := float(data.get("talented",data.leveled).get(key,0))
			var permanent := float(data.total.get(key,0))
			var total := float(data.live.get(key,permanent)) if expanded else permanent
			var growth := leveled-base
			var talent := talented-leveled
			var gear := permanent-talented
			var buff := total-permanent
			var values: Array = [Inspect.caption(key),Inspect.value(key,base,false,false,version),Inspect.value(key,growth,true,false,version)]
			if expanded: values.append(Inspect.value(key,talent,true,false,version))
			values.append(Inspect.value(key,gear,true,false,version))
			if expanded: values.append(Inspect.value(key,buff,true,false,version))
			values.append(Inspect.value(key,total,false,false,version))
			var row := _table_row(values,width)
			row.name = "StatSource_"+key
			row.set_meta("sources",{"base":base,"growth":growth,"talents":talent,"gear":gear,"buff":buff,"total":total})
			row.get_child(values.size()-1).name = prefix+key
			row.tooltip_text = Inspect.caption(key)+"\n"+" | ".join(PackedStringArray(values.slice(1)))
			if key in ["attack_interval","armor_damage_reduction","magic_damage_reduction"]:
				row.tooltip_text += "\n"+Inspect.t("各来源显示真实公式产生的总值变化；间隔越低越快，减伤由护甲/魔抗推导。", "Sources show resolved changes: lower intervals are faster; reductions derive from armor/resistance.")
	for note: String in Inspect.cap_notes(data.total): _line(note,width,14,GameStyle.AMBER)
	if not expanded:
		var changed := false
		for group: Array in Inspect.GROUPS:
			for key: String in group[2]:
				if is_equal_approx(float(data.live.get(key,0)),float(data.total.get(key,0))): continue
				if not changed: _heading(Inspect.t("当前战斗变化","CURRENT COMBAT CHANGES"),width); changed = true
				_line(Inspect.caption(key)+"  "+Inspect.value(key,float(data.total.get(key,0)))+" → "+Inspect.value(key,float(data.live[key])),width,15,GameStyle.CYAN)
	_heading(Inspect.t("装备词条与套装 · 条件效果","AFFIXES & SETS · CONDITIONAL EFFECTS"),width)
	_line(Inspect.t("下列效果满足条件后触发，未触发的伤害、护盾或恢复不会计入上方常驻数值。", "These effects require their stated conditions. Untriggered damage, shields and recovery are not counted in permanent values."),width,14,GameStyle.MUTED)
	for slot: String in ContentRegistry.slots(int(data.total.get("ruleset_version",1))):
		var id := str(data.total.get("loadout",{}).get(slot,""))
		var record: Dictionary = data.owned.get(id,{})
		var item: Dictionary = ContentRegistry.equipment(str(record.get("template_id",id)),int(data.total.get("ruleset_version",1)))
		if item.is_empty(): continue
		_line(GameStyle.content_text(item,"name")+" +"+str(record.get("enhancement_rank",record.get("level",0))),width,15,GameStyle.CYAN)
		_line(GameStyle.content_text(item,"affix_text"),width,14)
	for id: String in data.total.get("sets",{}):
		var set_data: Dictionary = ContentRegistry.sets(int(data.total.get("ruleset_version",1))).get(id,{})
		var count := int(data.total.sets[id])
		_line(GameStyle.content_text(set_data,"name")+" · %d/%d" % [count,8 if int(data.total.get("ruleset_version",1)) == 2 else 6],width,17,GameStyle.AMBER)
		for tier: int in [2,4,6]:
			_line((Inspect.t("已激活 ","Active ") if count >= tier else Inspect.t("未激活 ","Inactive "))+str(tier)+Inspect.t(" 件："," pieces: ")+GameStyle.content_text(set_data.get("thresholds",{}).get(str(tier),{}),"text"),width,14,GameStyle.GREEN if count >= tier else GameStyle.MUTED)
			var trigger: Dictionary = data.get("triggers",{})
			var key := id+"_"+str(tier)
			if count >= tier and not trigger.is_empty() and (trigger.cooldowns.has(key) or trigger.buffs.has(key) or key in ["S06_4","S06_6"]):
				var remaining := maxf(0,float(trigger.cooldowns.get(key,0))-float(trigger.clock))
				var active_time := maxf(0,float(trigger.buffs.get(key,{}).get("until",0))-float(trigger.clock))
				_line(Inspect.t("内置冷却 %.1f 秒 · 当前增益剩余 %.1f 秒；仍需满足触发条件。","Internal cooldown %.1f s · active buff %.1f s left; trigger conditions still apply.") % [remaining,active_time],width,14,GameStyle.CYAN).name = "SetTrigger_"+key
	var hero: Dictionary = ContentRegistry.hero(str(data.hero_id))
	var passive: Dictionary = hero.get("passive",{})
	_heading(Inspect.t("职业被动 · ","HERO PASSIVE · ")+GameStyle.content_text(passive,"name_v2" if expanded and passive.has("name_v2") else "name"),width)
	_line(SkillInspect.passive_text(hero,data.live),width,14)

func _table_row(values: Array, width: float, header: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(width,32)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation",0)
	add_child(row)
	for i: int in values.size():
		var span := width*.30 if i == 0 else width*.70/(values.size()-1)
		var text := str(values[i]).replace("百分点"," pp")
		var label := _line(text,span,13 if header else 14,GameStyle.CYAN if header or i == values.size()-1 else GameStyle.INK if i == 0 else GameStyle.MUTED,row)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.tooltip_text = str(values[i])
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size.y = 32
		if i > 0: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row

func _heading(text: String, width: float) -> void:
	var rule := HSeparator.new()
	rule.custom_minimum_size = Vector2(width,8)
	rule.add_theme_stylebox_override("separator",GameStyle.rail_box(Color("e4ddca")))
	add_child(rule)
	var label := _line(text,width,17,GameStyle.CYAN)
	label.custom_minimum_size.y = 32

func _line(text: String, width: float, font_size: int = 14, tint: Color = GameStyle.INK, owner: Node = self) -> Label:
	var label := GameStyle.literal(owner,text,Vector2.ZERO,Vector2(width,0),font_size,tint)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label
