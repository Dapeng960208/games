extends RefCounted
## Page drafts are local; Game owns skill values, commits and expedition locks.
const Inspect = preload("res://scripts/presentation/equipment/equipment_inspection.gd")
const Sheet = preload("res://scripts/presentation/screens/stat_sheet.gd")
const SkillInspect = preload("res://scripts/presentation/screens/skill_inspection.gd")
const RoleSkin = preload("res://scripts/presentation/components/role_skin.gd")
const Sampler = preload("res://scripts/infrastructure/assets/texture_sampler.gd")
const SKILLS := ["q","secondary","f","ultimate"]
const ACTIONS := ["skill_q","skill_secondary","skill_f","skill_ultimate"]

static func render(panel: Control) -> void:
	var id := _hero_id(panel)
	var view := _view(panel,"hero_view",id)
	var identity: Dictionary = view.get("identity",view)
	var colors := RoleSkin.palette(id)
	var roster := RoleSkin.panel(panel.body,id,Vector2.ZERO,Vector2(206,510))
	GameStyle.literal(roster,_t("冒险者名册","ADVENTURERS"),Vector2(16,16),Vector2(174,29),21,colors.deep)
	for index: int in ContentRegistry.heroes().size():
		var hero_id := str(ContentRegistry.heroes()[index])
		var candidate := _view(panel,"hero_view",hero_id)
		var data: Dictionary = candidate.get("identity",candidate)
		var choice := _button(roster,"Preview_"+hero_id,"",Vector2(12,59+index*104),Vector2(182,94),func(): _preview(panel,hero_id),hero_id,hero_id == id)
		GameStyle.hero_portrait(choice,hero_id,Vector2(3,7),Vector2(66,80))
		GameStyle.literal(choice,_text(data,"name",GameStyle.content_text(ContentRegistry.hero(hero_id),"name")),Vector2(75,10),Vector2(101,29),21,RoleSkin.palette(hero_id).deep)
		GameStyle.literal(choice,_text(data,"class_name",GameStyle.content_text(ContentRegistry.hero(hero_id),"class_name")),Vector2(75,43),Vector2(101,46),18,RoleSkin.palette(hero_id).accent)
	var editable := _can_edit(panel,view) and not panel.has_meta("dossier_fixture")
	GameStyle.literal(roster,_t("独立配装 · 共用库存","Own loadouts · shared gear") if editable else _t("本次出征配置已锁定","Expedition configuration locked"),Vector2(16,385),Vector2(174,57),18,colors.muted).name = "HeroConfigLockReason"
	panel.action_button = _button(roster,"PrimaryAction",_t("当前出征角色","Current hero") if id == str(Game.profile.get("selected_hero","CH01")) else _t("选择此角色","Choose hero"),Vector2(12,452),Vector2(182,44),func(): panel._select_hero(),id,false,true)
	panel.action_button.disabled = not editable or id == str(Game.profile.get("selected_hero","CH01"))
	var portrait := RoleSkin.panel(panel.body,id,Vector2(222,0),Vector2(332,510))
	GameStyle.literal(portrait,_text(identity,"title",_text(identity,"class_name")),Vector2(18,17),Vector2(296,31),24,colors.accent)
	GameStyle.hero_portrait(portrait,id,Vector2(18,58),Vector2(296,333))
	GameStyle.literal(portrait,_text(identity,"name"),Vector2(18,399),Vector2(296,37),29,colors.deep)
	GameStyle.literal(portrait,"Lv.%d · %d / %d %s" % [int(view.get("level",Game.hero_level(id))),int(view.get("collected_count",4)),int(view.get("total_count",12)),_t("技能","skills")],Vector2(18,449),Vector2(296,35),18,colors.accent)
	var profile := RoleSkin.panel(panel.body,id,Vector2(570,0),Vector2(646,510))
	GameStyle.literal(profile,_t("职业档案","CLASS PROFILE"),Vector2(20,14),Vector2(606,31),24,colors.deep)
	GameStyle.literal(profile,_text(identity,"role_summary"),Vector2(20,54),Vector2(606,51),18,colors.text).name = "HeroRoleSummary"
	var stats: Dictionary = view.get("stats",{})
	for index: int in 4:
		var key: String = ["max_hp","ability_power" if id == "CH03" else "attack","armor","magic_resist"][index]
		metric(profile,Inspect.caption(key),Inspect.value(key,float(stats.get(key,0)),false,false,int(stats.get("ruleset_version",1))),Vector2(20+index*154,116),Vector2(144,67),id)
	var scroll := _scroll(profile,"HeroStatScroll",Vector2(20,199),Vector2(606,286))
	var flow := _flow(scroll,582)
	_paragraph(flow,_t("战斗节奏","COMBAT RHYTHM"),582,20,colors.accent)
	_paragraph(flow,SkillInspect.authored_text(_text(identity,"mechanic_text"),int(stats.get("ruleset_version",1))),582,18,colors.text).name = "HeroMechanicDescription"
	_paragraph(flow,_t("已装备 · 出征前准备四个技能","EQUIPPED · FOUR SKILLS"),582,20,colors.accent)
	var skill_view := _view(panel,"skill_page_view",id)
	var equipped: Array = view.get("loadout",skill_view.get("loadout",[]))
	for index: int in mini(4,equipped.size()):
		var entry := SkillInspect.entry(skill_view,str(equipped[index]))
		var item := _button(flow,"HeroEquipped_"+SKILLS[index],_binding(index)+" · "+str(entry.get("name",equipped[index])),Vector2.ZERO,Vector2(582,44),func(): _open_skill(panel,id,str(equipped[index])),id)
		item.custom_minimum_size = Vector2(582,44)
	var report: Dictionary = view.get("stat_report",{})
	if not report.is_empty():
		var toggle := _button(flow,"ToggleStatSources",_t("展开属性与来源","Show attributes and sources"),Vector2.ZERO,Vector2(582,44),func(): panel.set_meta("dossier_sources_open",not bool(panel.get_meta("dossier_sources_open",false))); panel.set_meta("dossier_focus","ToggleStatSources"); panel._render(),id,bool(panel.get_meta("dossier_sources_open",false)))
		toggle.custom_minimum_size = Vector2(582,44)
		if bool(panel.get_meta("dossier_sources_open",false)):
			var sheet := Sheet.new()
			flow.add_child(sheet)
			sheet.configure(report,582)
			for label: Node in sheet.find_children("*","Label",true,false): label.add_theme_font_size_override("font_size",18)
	profile.set_meta("hero_view",view.duplicate(true))
	_restore_focus(panel)

static func render_skills(panel: Control) -> void:
	var id := _hero_id(panel)
	var view := _view(panel,"skill_page_view",id)
	var colors := RoleSkin.palette(id)
	var draft := _draft(panel,id,view)
	var equipped: Array = draft.get("loadout",[])
	var slot := clampi(int(panel.get_meta("dossier_slot",0)),0,3)
	var selected := str(panel.get_meta("dossier_skill_id",equipped[slot] if equipped.size() == 4 else ""))
	var entries: Array = view.get("skills",[])
	if SkillInspect.entry(view,selected).is_empty() and not entries.is_empty(): selected = str(entries[0].get("skill_id",""))
	panel.set_meta("dossier_skill_id",selected)
	var editable := _can_edit(panel,view)
	var rail := RoleSkin.panel(panel.body,id,Vector2.ZERO,Vector2(272,510))
	for index: int in ContentRegistry.heroes().size():
		var hero_id := str(ContentRegistry.heroes()[index])
		var role := _view(panel,"hero_view",hero_id)
		var identity: Dictionary = role.get("identity",role)
		_button(rail,"SkillHero_"+hero_id,_text(identity,"name",GameStyle.content_text(ContentRegistry.hero(hero_id),"name")),Vector2(12+index*84,13),Vector2(80,44),func(): _preview(panel,hero_id),hero_id,hero_id == id)
	GameStyle.literal(rail,_t("已装备技能","EQUIPPED SKILLS"),Vector2(16,66),Vector2(240,28),21,colors.deep)
	for index: int in 4:
		var skill_id := str(equipped[index]) if index < equipped.size() else ""
		var entry := SkillInspect.entry(view,skill_id)
		var action := _button(rail,"InspectSkill_"+SKILLS[index],"",Vector2(12,104+index*74),Vector2(248,68),func(): panel.set_meta("dossier_slot",index); panel.set_meta("dossier_skill_id",skill_id); panel.set_meta("dossier_focus","InspectSkill_"+SKILLS[index]); panel._render(),id,index == slot)
		action.set_meta("skill_id",skill_id)
		action.set_meta("input_slot",SKILLS[index])
		skill_icon(action,id,skill_id,Vector2(8,8),Vector2(48,48))
		GameStyle.literal(action,_binding(index)+" · Lv.%d" % int(entry.get("mastery_level",1)),Vector2(66,5),Vector2(139,27),18,colors.accent)
		GameStyle.literal(action,str(entry.get("name","")),Vector2(66,34),Vector2(176,28),18,colors.text)
		var swap := _button(rail,"SwapSkill_"+SKILLS[index],"↕",Vector2(224,108+index*74),Vector2(32,29),func(): _swap_next(panel,id,view,index),id)
		swap.custom_minimum_size = Vector2(32,29)
		swap.disabled = not editable
		swap.tooltip_text = _t("与下一槽互换","Swap with next slot")
	var lock_text := str(view.get("lock_reason",""))
	if lock_text.is_empty(): lock_text = _t("出征期间只读，回营地后调整","Read only during expeditions; edit in camp") if not editable else _t("选槽位，再选技能替换","Choose a slot, then a skill")
	var lock_label := GameStyle.literal(rail,_t("出征锁定 · 回营地调整","Locked · Edit in camp") if not editable else lock_text,Vector2(16,405),Vector2(240,40),18,colors.muted)
	lock_label.name = "SkillConfigLockReason"
	lock_label.tooltip_text = lock_text
	lock_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	lock_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var apply := _button(rail,"ApplySkillConfig",_t("应用配置","Apply"),Vector2(12,452),Vector2(121,44),func(): _apply(panel,id,view),id,false,true)
	apply.disabled = not editable or not _dirty(draft,view) or bool(draft.get("busy",false))
	var discard := _button(rail,"DiscardSkillDraft",_t("还原","Revert"),Vector2(141,452),Vector2(119,44),func(): panel.remove_meta("dossier_draft_"+id); panel.remove_meta("dossier_message"); panel._render(),id)
	discard.disabled = not _dirty(draft,view) or bool(draft.get("busy",false))
	var pool := RoleSkin.panel(panel.body,id,Vector2(288,0),Vector2(460,510))
	var search := LineEdit.new()
	search.name = "SkillPoolSearch"
	search.position = Vector2(12,13)
	search.size = Vector2(436,43)
	search.placeholder_text = _t("搜索本职业技能","Search this class's skills")
	search.text = str(panel.get_meta("dossier_search",""))
	search.add_theme_font_size_override("font_size",18)
	for state: String in ["normal","focus","read_only"]:
		search.add_theme_stylebox_override(state,GameStyle.box(colors.paper,colors.accent if state == "focus" else colors.border,2 if state == "focus" else 1))
	search.add_theme_color_override("font_color",colors.text)
	search.add_theme_color_override("font_placeholder_color",colors.muted)
	search.add_theme_color_override("caret_color",colors.accent)
	pool.add_child(search)
	search.text_changed.connect(func(value: String): panel.set_meta("dossier_search",value); _filter_pool(panel))
	var filter := str(panel.get_meta("dossier_filter","all"))
	for index: int in 3:
		var value: String = ["all","learned","equipped"][index]
		_button(pool,"SkillFilter_"+value,[_t("全部","All"),_t("已学会","Learned"),_t("已装备","Equipped")][index],Vector2(12+index*147,65),Vector2(142,44),func(): panel.set_meta("dossier_filter",value); _filter_pool(panel),id,filter == value)
	var grid := GridContainer.new()
	grid.name = "SkillPoolGrid"
	grid.position = Vector2(12,120)
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",8)
	pool.add_child(grid)
	for entry: Dictionary in entries:
		var skill_id := str(entry.get("skill_id",""))
		var learned := bool(entry.get("unlocked",false))
		var action := _button(grid,"SkillPool_"+skill_id,"",Vector2.ZERO,Vector2(138,88),func(): panel.set_meta("dossier_skill_id",skill_id); panel.set_meta("dossier_focus","SkillPool_"+skill_id); panel._render(),id,skill_id == selected)
		action.custom_minimum_size = Vector2(138,88)
		action.set_meta("entry",entry.duplicate(true))
		action.set_meta("equipped",skill_id in equipped)
		skill_icon(action,id,skill_id,Vector2(8,5),Vector2(42,42))
		GameStyle.literal(action,"Lv.%d" % int(entry.get("mastery_level",1)) if learned else _t("未解锁","Locked"),Vector2(56,4),Vector2(76,27),18,colors.accent if learned else colors.muted)
		GameStyle.literal(action,_t("已装备","Equipped") if skill_id in equipped else _t("已学会","Learned") if learned else _t("待收集","Explore"),Vector2(56,28),Vector2(76,24),18,colors.muted)
		var title := GameStyle.literal(action,str(entry.get("name","")),Vector2(7,54),Vector2(124,31),18,colors.text)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		action.tooltip_text = str(entry.get("name",""))+"\n"+str(entry.get("description",""))
	var empty := GameStyle.literal(pool,_t("没有匹配的技能","No matching skills"),Vector2(22,230),Vector2(416,60),21,colors.muted)
	empty.name = "SkillPoolEmpty"
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_filter_pool(panel)
	var detail := RoleSkin.panel(panel.body,id,Vector2(764,0),Vector2(452,510))
	_render_detail(panel,detail,id,view,draft,selected,editable)
	panel.body.set_meta("skill_page_view",view.duplicate(true))
	_restore_focus(panel)

static func _render_detail(panel: Control, detail: Control, id: String, view: Dictionary, draft: Dictionary, selected: String, editable: bool) -> void:
	var entry := SkillInspect.entry(view,selected)
	var colors := RoleSkin.palette(id)
	detail.set_meta("skill_entry",entry.duplicate(true))
	skill_icon(detail,id,selected,Vector2(18,14),Vector2(66,66))
	GameStyle.literal(detail,str(entry.get("name",_t("技能资料准备中","Skill data preparing"))),Vector2(98,18),Vector2(336,34),25,colors.deep)
	var rank := int(entry.get("mastery_level",1))
	GameStyle.literal(detail,_t("主动技能 · 熟练度 Lv.%d","Active skill · Mastery Lv.%d") % rank,Vector2(98,54),Vector2(336,29),18,colors.accent)
	var scroll := _scroll(detail,"SkillDescriptionScroll",Vector2(18,95),Vector2(416,398))
	var flow := _flow(scroll,392)
	var message := str(panel.get_meta("dossier_message",""))
	if not message.is_empty(): _paragraph(flow,message,392,18,GameStyle.RED if bool(panel.get_meta("dossier_message_error",false)) else colors.accent).name = "SkillConfigMessage"
	var spec: Dictionary = entry.get("spec",{})
	var cooldown: Variant = spec.get("cooldown",null)
	_paragraph(flow,_t("消耗 %s · 冷却 %s 秒","Cost %s · Cooldown %s s") % [str(spec.get("cost","—")),"%.2f" % float(cooldown) if cooldown != null else "—"],392,20,colors.accent).name = "SkillActualNumbers"
	_paragraph(flow,SkillInspect.spec_facts(spec),392,18,colors.muted).name = "SkillActualTimeline"
	_paragraph(flow,str(entry.get("description","")),392,18,colors.text).name = "InspectedSkillDescription"
	var mastery: Dictionary = entry.get("mastery",{})
	var xp := int(entry.get("mastery_xp",mastery.get("xp",0)))
	var next_xp: Variant = mastery.get("next_threshold",null)
	_paragraph(flow,_t("熟练度","MASTERY"),392,20,colors.accent)
	_paragraph(flow,_t("已满级 · 累计 %d 熟练度","Maximum level · %d total XP") % xp if rank >= 5 else _t("累计 %d / %s · 升级从下次施法生效","Total %d / %s · Upgrades apply to the next cast") % [xp,str(next_xp) if next_xp != null else "—"],392,18,colors.text).name = "SkillMasteryProgress"
	_paragraph(flow,_t("真实战斗的首次释放获得熟练度；多段及附伤只计一次。","Mastery comes from the first actual release in combat; multiple hits and derived effects count once."),392,18,colors.muted)
	var branches: Dictionary = entry.get("branches",{})
	if not branches.is_empty():
		_paragraph(flow,_t("技能分支","SKILL BRANCHES"),392,20,colors.accent)
		var gate := int(entry.get("branch_mastery_level",4 if selected.ends_with("SK01") else 5))
		var choice := str(draft.get("branches",{}).get(selected,""))
		for branch: String in branches:
			var value: Variant = branches[branch]
			var data: Dictionary = value if value is Dictionary else {"name":_t("分支 ","Branch ")+branch,"description":str(value)}
			var action := _button(flow,"SkillBranch_"+branch,("● " if branch == choice else "")+_text(data,"name",branch),Vector2.ZERO,Vector2(392,44),func(): _set_branch(panel,id,view,selected,branch),id,branch == choice)
			action.custom_minimum_size = Vector2(392,44)
			action.disabled = not editable or rank < gate
			action.tooltip_text = _t("熟练度 Lv.%d 开放","Opens at mastery Lv.%d") % gate
			_paragraph(flow,_text(data,"description"),392,18,colors.muted)
		var reset := _button(flow,"SkillBranch_original",_t("使用原技能","Use original skill"),Vector2.ZERO,Vector2(392,44),func(): _set_branch(panel,id,view,selected,""),id,choice.is_empty())
		reset.custom_minimum_size = Vector2(392,44)
		reset.disabled = not editable or rank < gate or choice.is_empty()
	_paragraph(flow,_t("获取来源","ACQUISITION"),392,20,colors.accent)
	_paragraph(flow,SkillInspect.source_text(entry),392,18,colors.text).name = "SkillAcquisitionSource"
	var slot := clampi(int(panel.get_meta("dossier_slot",0)),0,3)
	var values: Array = draft.get("loadout",[])
	var replace := _button(flow,"ReplaceDraftSkill",_t("装备至 %s","Equip to %s") % _binding(slot),Vector2.ZERO,Vector2(392,48),func(): _replace(panel,id,view,selected,slot),id,false,true)
	replace.custom_minimum_size = Vector2(392,48)
	replace.disabled = not editable or not bool(entry.get("unlocked",false)) or values.size() != 4 or str(values[slot]) == selected
	_paragraph(flow,_t("已在其他槽位的技能会互换，统一应用后生效。","A skill already in another slot swaps with this slot. Apply the complete draft to save."),392,18,colors.muted)

static func _replace(panel: Control, id: String, view: Dictionary, skill_id: String, slot: int) -> void:
	if not _can_edit(panel,view) or not bool(SkillInspect.entry(view,skill_id).get("unlocked",false)): return
	var draft := _draft(panel,id,view)
	var values: Array = draft.get("loadout",[]).duplicate()
	if values.size() != 4: return
	var previous := values.find(skill_id)
	if previous >= 0: values[previous] = values[slot]
	values[slot] = skill_id
	draft["loadout"] = values
	draft["operation_id"] = ""
	panel.set_meta("dossier_draft_"+id,draft)
	panel.set_meta("dossier_focus","ApplySkillConfig")
	panel._render()

static func _swap_next(panel: Control, id: String, view: Dictionary, slot: int) -> void:
	var values: Array = _draft(panel,id,view).get("loadout",[])
	if values.size() == 4: _replace(panel,id,view,str(values[(slot+1)%4]),slot)

static func _set_branch(panel: Control, id: String, view: Dictionary, skill_id: String, branch: String) -> void:
	if not _can_edit(panel,view): return
	var draft := _draft(panel,id,view)
	var choices: Dictionary = draft.get("branches",{}).duplicate()
	choices[skill_id] = branch
	draft["branches"] = choices
	draft["operation_id"] = ""
	panel.set_meta("dossier_draft_"+id,draft)
	panel.set_meta("dossier_focus","SkillBranch_"+(branch if not branch.is_empty() else "original"))
	panel._render()

static func _apply(panel: Control, id: String, view: Dictionary) -> void:
	if not _can_edit(panel,view) or not Game.has_method("apply_skill_config"): return
	if panel.has_meta("dossier_fixture"):
		var fixture: Dictionary = panel.get_meta("dossier_fixture",{})
		panel.set_meta("dossier_message",str(fixture.get("apply_message",_t("预览模式：草稿仅用于界面预览，没有写入存档。","Preview only: this draft has not been written to a save."))))
		panel.set_meta("dossier_message_error",bool(fixture.get("apply_failed",false)))
		panel._render()
		return
	var draft := _draft(panel,id,view)
	if bool(draft.get("busy",false)): return
	if str(draft.get("operation_id","")).is_empty(): draft["operation_id"] = "skill-config:"+Crypto.new().generate_random_bytes(16).hex_encode()
	draft["busy"] = true
	panel.set_meta("dossier_draft_"+id,draft)
	var result: Dictionary = Game.call("apply_skill_config",id,draft.get("loadout",[]),draft.get("branches",{}),str(draft.operation_id))
	draft["busy"] = false
	if bool(result.get("ok",false)):
		panel.remove_meta("dossier_draft_"+id)
		panel.set_meta("dossier_message",_t("配置已保存，下次出征使用这四个技能。","Configuration saved for your next expedition."))
		panel.set_meta("dossier_message_error",false)
		panel.set_meta("dossier_focus","InspectSkill_"+SKILLS[int(panel.get_meta("dossier_slot",0))])
	else:
		draft["operation_id"] = str(result.get("operation_id",draft.operation_id))
		panel.set_meta("dossier_draft_"+id,draft)
		panel.set_meta("dossier_message",SkillInspect.config_reason(str(result.get("reason",result.get("error","")))))
		panel.set_meta("dossier_message_error",true)
		panel.set_meta("dossier_focus","ApplySkillConfig")
	panel._render()

static func _filter_pool(panel: Control) -> void:
	var grid: Node = panel.body.find_child("SkillPoolGrid",true,false)
	if grid == null: return
	var query := str(panel.get_meta("dossier_search","")).strip_edges().to_lower()
	var filter := str(panel.get_meta("dossier_filter","all"))
	var visible_count := 0
	for child: Node in grid.get_children():
		var entry: Dictionary = child.get_meta("entry",{})
		var matches := query.is_empty() or (str(entry.get("name",""))+" "+str(entry.get("skill_id",""))).to_lower().contains(query)
		matches = matches and (filter == "all" or filter == "learned" and bool(entry.get("unlocked",false)) or filter == "equipped" and bool(child.get_meta("equipped",false)))
		child.visible = matches
		if matches: visible_count += 1
	var empty: Control = panel.body.find_child("SkillPoolEmpty",true,false)
	if empty != null: empty.visible = visible_count == 0
	for value: String in ["all","learned","equipped"]:
		var button := panel.body.find_child("SkillFilter_"+value,true,false) as Button
		if button != null: RoleSkin.button(button,_hero_id(panel),filter == value)

static func _view(panel: Control, kind: String, id: String) -> Dictionary:
	if panel.has_meta("dossier_fixture"):
		var fixture: Dictionary = panel.get_meta("dossier_fixture",{})
		var data: Dictionary = fixture.get(kind,{})
		return data[id].duplicate(true) if data.has(id) else data.duplicate(true)
	if Game.has_method(kind):
		var result: Variant = Game.call(kind,id,"run" if Game.run != null else "camp")
		if result is Dictionary: return result
	return {}

static func _hero_id(panel: Control) -> String:
	if Game.run != null: return str(Game.run.hero_id)
	var preview := str(panel.get("preview_hero"))
	return preview if not preview.is_empty() else str(Game.profile.get("selected_hero","CH01"))

static func _draft(panel: Control, id: String, view: Dictionary) -> Dictionary:
	var key := "dossier_draft_"+id
	if not panel.has_meta(key): panel.set_meta(key,{"loadout":view.get("loadout",[]).duplicate(),"branches":view.get("branch_choices",{}).duplicate(),"operation_id":"","busy":false})
	return panel.get_meta(key)

static func _dirty(draft: Dictionary, view: Dictionary) -> bool:
	return draft.get("loadout",[]) != view.get("loadout",[]) or draft.get("branches",{}) != view.get("branch_choices",{})

static func _can_edit(panel: Control, view: Dictionary) -> bool:
	return Game.run == null and bool(view.get("editable",false))

static func _preview(panel: Control, id: String) -> void:
	if Game.run != null: return
	panel.preview_hero = id
	panel.remove_meta("dossier_skill_id")
	panel.remove_meta("dossier_message")
	panel.set_meta("dossier_focus","SkillHero_"+id if str(panel.get("mode")) == "skills" else "Preview_"+id)
	panel._render()

static func _restore_focus(panel: Control) -> void:
	var node_name := str(panel.get_meta("dossier_focus",""))
	if node_name.is_empty(): return
	var target: Control = panel.find_child(node_name,true,false) as Control
	if target != null and target.focus_mode != Control.FOCUS_NONE and not (target is BaseButton and target.disabled):
		target.grab_focus.call_deferred()

static func _open_skill(panel: Control, id: String, skill_id: String) -> void:
	panel.preview_hero = id
	panel.set_meta("dossier_skill_id",skill_id)
	panel.set_meta("dossier_focus","SkillPool_"+skill_id)
	if panel.has_method("_switch_page"): panel._switch_page("skills")
	else: panel.set_meta("dossier_page","skills"); panel._render()

static func _binding(index: int) -> String:
	return ControlBindings.label_for(ACTIONS[clampi(index,0,3)],Game.profile.get("settings",{}).get("controls",{}),Words.locale)

static func _text(data: Dictionary, key: String, fallback: String = "") -> String:
	return GameStyle.content_text(data,key,fallback)

static func _t(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

static func _button(parent: Node, node_name: String, text: String, at: Vector2, extent: Vector2, action: Callable, id: String, selected: bool = false, primary: bool = false) -> Button:
	var button := GameStyle.button(parent,"",at,extent,action)
	button.name = node_name
	button.text = text
	RoleSkin.button(button,id,selected,primary)
	return button

static func _scroll(parent: Node, node_name: String, at: Vector2, extent: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.position = at
	scroll.size = extent
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	parent.add_child(scroll)
	return scroll

static func _flow(parent: Node, width: float) -> VBoxContainer:
	var flow := VBoxContainer.new()
	flow.custom_minimum_size.x = width
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("separation",12)
	parent.add_child(flow)
	return flow

static func _paragraph(parent: Node, text: String, width: float, font_size: int, color: Color) -> Label:
	var label := GameStyle.literal(parent,text,Vector2.ZERO,Vector2(width,0),font_size,color)
	label.custom_minimum_size.x = width
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = text
	return label

static func skill_icon(parent: Node, hero: String, skill: String, at: Vector2, extent: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	var logical := "asset://skill."+skill.to_lower() if skill.begins_with("CH") else "asset://skills/"+hero+"_"+skill+"_v1.png"
	icon.texture = Sampler.sampled(logical) if ResourceLoader.exists(AssetCatalog.resolve(logical)) else null
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = at
	icon.size = extent
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

static func metric(parent: Node, caption: String, value: String, at: Vector2, extent: Vector2, hero_id: String = "CH01") -> void:
	var colors := RoleSkin.palette(hero_id)
	var card := RoleSkin.panel(parent,hero_id,at,extent)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameStyle.literal(card,caption,Vector2(10,6),Vector2(extent.x-20,24),18,colors.muted)
	GameStyle.literal(card,value,Vector2(10,33),Vector2(extent.x-20,28),23,colors.accent)
