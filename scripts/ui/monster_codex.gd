extends Control
## Read-only field guide. Every entry, portrait and resolved value comes from
## the production catalogs; opening the guide never writes or spawns a battle.
const Inspect = preload("res://scripts/ui/equipment_inspection.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Difficulty = preload("res://scripts/combat/enemy_difficulty.gd")
const Bosses = preload("res://scripts/combat/boss_profiles.gd")
const Brain = preload("res://scripts/combat/boss_brain.gd")
const Abilities = preload("res://scripts/combat/boss_ability_catalog.gd")
const EnemyImages = preload("res://scripts/combat/enemy_art.gd")
const EnemyAbilities = preload("res://scripts/combat/enemy_ability_catalog.gd")
const BiomeSkills = preload("res://scripts/combat/enemy_biome_skills.gd")
const Numerical = preload("res://scripts/combat/enemy_numerical_v2.gd")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Dossier = preload("res://scripts/ui/hero_dossier.gd")
const B05Content = preload("res://scripts/world/b05_content.gd")
const Rules = preload("res://config/numerical_rules.gd")
const BIOMES := ["B01","B02","B03","B04"]
var preview_unreleased_b05 := false
var biome_filter := "all"
var kind_filter := "all"
var search_query := ""
var selected_id := "M01"
var difficulty := 0
var inspector_tab := "skills"
var preview_level := 5
var ruleset := 2
var grid_scroll: ScrollContainer
var grid: GridContainer
var detail: Panel
var result_count: Label
var level_picker: OptionButton
var region_buttons: Dictionary = {}
var kind_buttons: Dictionary = {}

func configure(close: Callable, initial_biome: String = "all", preview_b05: bool = false) -> void:
	# Explicit isolated-preview opt-in; normal menus retain the release gate.
	preview_unreleased_b05 = preview_b05
	var biomes := available_biomes(preview_b05)
	var region_ids: Array = biomes.keys()
	name = "MonsterCodex"
	size = Vector2(1280,720)
	biome_filter = initial_biome if initial_biome in region_ids else "all"
	if biome_filter != "all": selected_id = str(biomes[biome_filter].enemy_ids[0])
	ruleset = int(Game.profile.get("ruleset_version",2))
	preview_level = default_level(selected_id)
	var header := MineStyle.panel(self,Vector2(26,20),Vector2(1228,68))
	MineStyle.literal(header,Inspect.t("怪物图鉴","Monster codex"),Vector2(22,10),Vector2(410,42),30)
	MineStyle.literal(header,Inspect.t("%d 种野怪 · %d 位首领","%d enemy archetypes · %d bosses") % [entry_ids(preview_b05).filter(func(key): return not str(key).begins_with("BO")).size(),entry_ids(preview_b05).filter(func(key): return str(key).begins_with("BO")).size()],Vector2(390,20),Vector2(460,30),16,MineStyle.MUTED)
	var back := MineStyle.button(header,"BACK",Vector2(1040,12),Vector2(166,44),close)
	back.name = "CloseMonsterCodex"
	var collection := MineStyle.panel(self,Vector2(26,105),Vector2(754,563))
	var region_width := 720.0 / float(region_ids.size()+1)
	for index: int in region_ids.size()+1:
		var key: String = "all" if index == 0 else region_ids[index-1]
		var button := MineStyle.button(collection,"",Vector2(16+index*region_width,68),Vector2(region_width-8,39),func(): _set_biome(key))
		button.name = "CodexRegion_"+key
		button.text = Inspect.t("全部区域","All regions") if key == "all" else MineStyle.content_text(biomes[key],"name")
		button.add_theme_font_size_override("font_size",14)
		button.tooltip_text = button.text
		region_buttons[key] = button
	var search := LineEdit.new()
	search.name = "CodexSearch"
	search.position = Vector2(16,14)
	search.size = Vector2(414,42)
	search.placeholder_text = Inspect.t("搜索怪物名称 / 编号","Search name / ID")
	search.add_theme_font_size_override("font_size",16)
	search.text_changed.connect(func(value: String): search_query = value; _refresh_grid())
	collection.add_child(search)
	for index: int in 3:
		var kind: String = ["all","enemy","boss"][index]
		var filter := MineStyle.button(collection,"",Vector2(443+index*99,14),Vector2(95,42),func(): kind_filter = kind; _refresh_grid())
		filter.name = "CodexKind_"+kind
		filter.text = [Inspect.t("全部","All"),Inspect.t("野怪","Enemies"),Inspect.t("首领","Bosses")][index]
		filter.add_theme_font_size_override("font_size",14)
		kind_buttons[kind] = filter
	result_count = MineStyle.literal(header,"",Vector2(856,23),Vector2(170,24),13,MineStyle.MUTED)
	result_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid_scroll = ScrollContainer.new()
	grid_scroll.name = "CodexCollectionScroll"
	grid_scroll.position = Vector2(16,122)
	grid_scroll.size = Vector2(722,424)
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.focus_mode = Control.FOCUS_ALL
	collection.add_child(grid_scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	grid_scroll.add_child(grid)
	detail = MineStyle.panel(self,Vector2(796,105),Vector2(458,563))
	detail.name = "CodexInspector"
	MineStyle.literal(self,Inspect.t("B05开发预览 · 章节未开放 · 部分美术待补齐","B05 development preview · chapter closed · artwork incomplete") if preview_unreleased_b05 else Inspect.t("图鉴仅供查看 · 属性取自当前规则的真实解析器","Read-only guide · stats use the current ruleset's production resolver"),Vector2(32,684),Vector2(1216,25),13,MineStyle.MUTED)
	_refresh_grid()
	_show_entry(selected_id)
	back.grab_focus()

static func available_biomes(include_b05: bool = false) -> Dictionary:
	var result := Catalog.biomes().duplicate(true)
	if include_b05 or int(Rules.value("implemented_chapters",4)) >= 5:
		var b05 := B05Content.catalog()
		result["B05"] = {"name":b05.name,"name_en":b05.name_en,"enemy_ids":b05.enemy_ids}
	return result

static func default_level(id: String) -> int:
	if id.begins_with("B06-") or id == "BO06": return 30
	return 25 if id.begins_with("B05-") or id == "BO05" else int(Numerical.chapter_levels(Numerical.chapter_for_id(id)).boss_level)

static func entry_ids(include_b05: bool = false) -> Array[String]:
	var result: Array[String] = []
	result.assign(Catalog.enemy_ids())
	result.append_array(Bosses.ids())
	if include_b05 or int(Rules.value("implemented_chapters",4)) >= 5:
		for id: String in B05Content.enemy_ids():
			if id not in result: result.append(id)
		if "BO05" not in result: result.append("BO05")
	return result

static func definition(id: String) -> Dictionary:
	if id.begins_with("B05-M"): return B05Content.enemy(id)
	if id == "BO05": return B05Content.boss()
	return Catalog.bosses().get(id,{}) if id.begins_with("BO") else Catalog.enemy(id)

static func resolved_entry(id: String, level: int, tier: int, version: int = 2) -> Dictionary:
	if id.begins_with("BO"): return Bosses.resolve(id,tier,version)
	var value := Profiles.resolve(id,level,"normal",version,tier)
	return Difficulty.apply(value,tier) if version == 1 else value

func filtered_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in entry_ids(preview_unreleased_b05):
		var value := definition(id)
		if biome_filter != "all" and value.get("biome_id","") != biome_filter: continue
		if kind_filter == "boss" and not id.begins_with("BO"): continue
		if kind_filter == "enemy" and id.begins_with("BO"): continue
		var text := (id+" "+str(value.get("name",""))+" "+str(value.get("name_en",""))).to_lower()
		if not search_query.strip_edges().is_empty() and not text.contains(search_query.strip_edges().to_lower()): continue
		result.append(id)
	return result

func _set_biome(value: String) -> void:
	biome_filter = value
	_refresh_grid()
	var ids := filtered_ids()
	if not ids.is_empty() and selected_id not in ids: _show_entry(ids[0])

func _refresh_grid() -> void:
	for child: Node in grid.get_children(): grid.remove_child(child); child.queue_free()
	for key: String in region_buttons:
		MineStyle.button_skin(region_buttons[key],"secondary")
		if key == biome_filter: MineStyle.primary(region_buttons[key])
	for key: String in kind_buttons:
		MineStyle.button_skin(kind_buttons[key],"secondary")
		if key == kind_filter: MineStyle.primary(kind_buttons[key])
	var ids := filtered_ids()
	result_count.text = Inspect.t("%d 条目","%d entries") % ids.size()
	for id: String in ids:
		var data := definition(id)
		var button := MineStyle.button(grid,"",Vector2.ZERO,Vector2(230,204),func(): _show_entry(id))
		button.custom_minimum_size = Vector2(230,204)
		button.name = "CodexEntry_"+id
		MineStyle.button_skin(button,"card")
		if id == selected_id: MineStyle.selected(button,"card")
		portrait(button,id,Vector2(17,9),Vector2(196,143))
		MineStyle.literal(button,id+" · "+(Inspect.t("首领","BOSS") if id.begins_with("BO") else role_label(str(data.get("role","")))),Vector2(12,156),Vector2(206,18),12,MineStyle.AMBER if id.begins_with("BO") else MineStyle.CYAN)
		var title := MineStyle.literal(button,MineStyle.content_text(data,"name"),Vector2(12,177),Vector2(206,23),16)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = MineStyle.content_text(data,"name")
	if ids.is_empty():
		var empty := MineStyle.literal(grid,Inspect.t("没有匹配的怪物\n试试其他名称或区域","No matches\nTry another name or region"),Vector2.ZERO,Vector2(710,100),18,MineStyle.MUTED)
		empty.custom_minimum_size = Vector2(710,100)
	elif selected_id not in ids:
		_show_entry(ids[0])

func _show_entry(id: String, reset_level: bool = true) -> void:
	var data := definition(id)
	if data.is_empty(): return
	selected_id = id
	if reset_level: preview_level = default_level(id)
	for child: Node in detail.get_children(): detail.remove_child(child); child.queue_free()
	for child: Node in grid.get_children():
		if child is Button:
			MineStyle.button_skin(child,"card")
			if child.name == "CodexEntry_"+id: MineStyle.selected(child,"card")
	var profile := resolved_entry(id,preview_level,difficulty,ruleset)
	detail.set_meta("resolved_profile",profile)
	portrait(detail,id,Vector2(18,10),Vector2(184,184))
	var title := MineStyle.literal(detail,MineStyle.content_text(data,"name"),Vector2(217,27),Vector2(221,88),23)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	MineStyle.literal(detail,id+" · "+MineStyle.content_text(available_biomes(preview_unreleased_b05).get(str(data.get("biome_id","")),{}),"name"),Vector2(217,126),Vector2(221,50),14,MineStyle.CYAN)
	level_picker = OptionButton.new()
	level_picker.name = "CodexLevel"
	level_picker.position = Vector2(20,213)
	level_picker.size = Vector2(116,35)
	level_picker.add_theme_font_size_override("font_size",14)
	for level: int in range(1,31 if id.begins_with("B06-") or id == "BO06" else (26 if id.begins_with("B05-") or id == "BO05" else 21)): level_picker.add_item("Lv."+str(level),level)
	level_picker.select(int(profile.get("enemy_level",preview_level))-1)
	level_picker.disabled = id.begins_with("BO")
	level_picker.item_selected.connect(func(index: int): preview_level = index+1; _show_entry(selected_id,false))
	detail.add_child(level_picker)
	var tiers := OptionButton.new()
	tiers.name = "CodexDifficulty"
	tiers.position = Vector2(150,213)
	tiers.size = Vector2(288,35)
	tiers.add_theme_font_size_override("font_size",14)
	for index: int in 5: tiers.add_item(difficulty_label(index),index)
	tiers.select(difficulty)
	tiers.item_selected.connect(func(index: int): difficulty = index; _show_entry(selected_id,false))
	detail.add_child(tiers)
	for index: int in 2:
		var tab_key: String = ["stats","skills"][index]
		var tab := MineStyle.button(detail,"",Vector2(20+index*213,256),Vector2(205,39),func(): inspector_tab = tab_key; _show_entry(selected_id,false))
		tab.name = "CodexDetailTab_"+tab_key
		tab.text = Inspect.t("属性与特性","Stats & traits") if tab_key == "stats" else Inspect.t("技能与难度解锁","Skills & unlocks")
		tab.add_theme_font_size_override("font_size",15)
		MineStyle.tab(tab,inspector_tab == tab_key)
	var scroll := ScrollContainer.new()
	scroll.name = "CodexSkillScroll"
	scroll.position = Vector2(20,305)
	scroll.size = Vector2(418,240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	detail.add_child(scroll)
	var flow := VBoxContainer.new()
	flow.custom_minimum_size.x = 394
	flow.add_theme_constant_override("separation",9)
	scroll.add_child(flow)
	if inspector_tab == "skills":
		if id.begins_with("BO"): _boss_details(flow,profile)
		else: _enemy_skill_catalog(flow,profile)
		return
	var metrics := Control.new()
	metrics.custom_minimum_size = Vector2(394,122)
	flow.add_child(metrics)
	for index: int in 4:
		var key: String = ["max_hp","damage","armor","magic_resist"][index]
		var caption := Inspect.t("基础攻击 A","Base attack A") if key == "damage" else Inspect.caption(key)
		var amount := str(int(profile.get(key,0))) if ruleset == 2 else "%.1f" % float(profile.get(key,0))
		Dossier.metric(metrics,caption,amount,Vector2((index%2)*203,(index/2)*64),Vector2(191,58))
	if id.begins_with("BO"): _boss_details(flow,profile)
	else: _enemy_details(flow,profile)

static func portrait(parent: Node, id: String, at: Vector2, extent: Vector2) -> TextureRect:
	# A separate clipped illustration box prevents any texture minimum-size
	# regression from painting over the card caption or inspector heading.
	var frame := Control.new()
	frame.name = "PortraitFrame_"+id
	frame.position = at
	frame.size = extent
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var view := TextureRect.new()
	view.name = "Portrait_"+id
	# Dedicated codex portraits can be upgraded independently of combat bodies.
	var hd_path := "res://assets/generated/ui/refactor_v1/codex/"+id+".png"
	var dedicated := FileAccess.file_exists(hd_path) or ResourceLoader.exists(hd_path)
	if dedicated:
		view.texture = Sampler.sampled(hd_path)
	else:
		# Match EnemyArt.install in the actual battle renderer. BossProfiles
		# visual_asset names pre-storybook placeholders, not current boss identity.
		var entry := preload("res://scripts/combat/b06_native_art.gd").boss_frame("","idle") if id == "BO06" and Rules.b06_candidate_enabled() else EnemyImages.entry_for(id)
		if not entry.is_empty():
			var atlas := AtlasTexture.new()
			atlas.atlas = entry.texture
			atlas.region = entry.region
			atlas.filter_clip = true
			view.texture = atlas
	# Expand mode must precede size: otherwise TextureRect clamps the requested
	# size to the native atlas region and a 2K canvas doubles the blurry sprite.
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var art_extent := extent-Vector2(16,16) if id.begins_with("B05-") else extent
	var fitted := art_extent
	if view.texture != null and not dedicated:
		var native := view.texture.get_size()
		var pixel_ratio := maxf(1.0,parent.get_viewport().get_stretch_transform().get_scale().x) if parent.is_inside_tree() else 1.0
		var scale_factor := minf(minf(art_extent.x/native.x,art_extent.y/native.y),1.0/pixel_ratio)
		fitted = native*scale_factor
	view.position = (extent-fitted)*0.5
	view.size = fitted
	view.set_meta("dedicated_codex_art",dedicated)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(view)
	if view.texture == null and (id.begins_with("B05-") or id == "BO05"):
		var pending := MineStyle.literal(frame,Inspect.t("美术制作中","ARTWORK IN PROGRESS"),Vector2(8,extent.y*0.35),Vector2(extent.x-16,extent.y*0.3),13,MineStyle.MUTED)
		pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pending.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return view

func _enemy_skill_catalog(flow: VBoxContainer, profile: Dictionary) -> void:
	var id := str(profile.get("enemy_id",selected_id))
	var skills: Array[Dictionary] = EnemyAbilities.all_skills(id,difficulty,profile)
	var unlocked := 0
	for skill: Dictionary in skills:
		if bool(skill.get("unlocked",false)): unlocked += 1
	_line(flow,difficulty_label(difficulty)+Inspect.t(" · 已解锁 %d / %d 项"," · %d / %d unlocked") % [unlocked,skills.size()],16,MineStyle.CYAN)
	if id.begins_with("B06-M"):
		_line(flow,Inspect.t("难度强化累计生效；按湿地高潮条件预览，未开放项按解锁难度展示。有效预警与冷却取自实际运行招式。","Upgrades are cumulative. Preview assumes wet/high tide; locked rows use unlock difficulty. Timing comes from runtime commands."),13,MineStyle.MUTED)
	else:
		_line(flow,Inspect.t("基础招式保留；更高难度累计开放新招式。灰色项未开放，其数值按当前所选难度预览。","Base moves remain; higher difficulties add moves. Grey entries are locked. Their numbers preview the currently selected difficulty."),13,MineStyle.MUTED)
	for skill: Dictionary in skills:
		var enabled := bool(skill.get("unlocked",false))
		var replaced := bool(skill.get("replaced",false))
		var active := enabled and not replaced
		var minimum := int(skill.get("min_difficulty",0))
		var card := PanelContainer.new()
		var key := str(skill.get("ability_id","")).replace(":","_")
		card.name = "CodexAbility_"+key
		card.set_meta("ability",skill.duplicate(true))
		card.add_theme_stylebox_override("panel",MineStyle.box(MineStyle.PAPER_LIGHT if active else Color("efeee7"),Color(MineStyle.CYAN,0.35) if active else Color("d7d3c7"),1))
		flow.add_child(card)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation",7)
		card.add_child(rows)
		_skill_line(rows,MineStyle.content_text(skill,"name"),17,MineStyle.INK if active else MineStyle.MUTED).name = "AbilityName"
		_skill_line(rows,(Inspect.t("基础招式","BASE MOVE") if minimum == 0 else difficulty_label(minimum))+" · "+(Inspect.t("已解锁 · 当前由高阶招式替代","UNLOCKED · REPLACED AT THIS TIER") if replaced else Inspect.t("已解锁","UNLOCKED") if enabled else Inspect.t("未解锁","LOCKED")),12,MineStyle.CYAN if active else MineStyle.MUTED).name = "AbilityUnlock"
		_skill_line(rows,MineStyle.content_text(skill,"effect"),14).name = "AbilityEffect"
		_skill_line(rows,Inspect.t("触发：","Trigger: ")+MineStyle.content_text(skill,"trigger"),13,MineStyle.MUTED).name = "AbilityTrigger"
		_skill_line(rows,Inspect.t("应对：","Counter: ")+MineStyle.content_text(skill,"counter"),14,MineStyle.CYAN if active else MineStyle.MUTED).name = "AbilityCounter"
		_skill_line(rows,Inspect.t("预警 %.2f秒 · 锁定 %.2f秒 · 冷却 %.2f秒","Tell %.2fs · lock %.2fs · cooldown %.2fs") % [float(skill.get("tell_seconds",0)),float(skill.get("lock_seconds",0)),float(skill.get("cooldown",0))],12,MineStyle.MUTED).name = "AbilityTiming"

func _skill_line(parent: Node, text: String, font_size: int, tint: Color = MineStyle.INK) -> Label:
	var label := MineStyle.literal(parent,text,Vector2.ZERO,Vector2(330,0),font_size,tint)
	label.custom_minimum_size.x = 330
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _enemy_details(flow: VBoxContainer, profile: Dictionary) -> void:
	var skill_header := HBoxContainer.new()
	skill_header.add_theme_constant_override("separation",10)
	flow.add_child(skill_header)
	var icon_data := EnemyImages.skill_icon_for(str(profile.get("enemy_id","")))
	if not icon_data.is_empty():
		var icon := TextureRect.new()
		var texture := AtlasTexture.new()
		texture.atlas = icon_data.texture
		texture.region = icon_data.region
		texture.filter_clip = true
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40,40)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_header.add_child(icon)
	var heading := MineStyle.literal(skill_header,Inspect.t("技能与应对","SKILLS & COUNTERPLAY"),Vector2.ZERO,Vector2(344,40),17,MineStyle.CYAN)
	heading.custom_minimum_size = Vector2(344,40)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line(flow,MineStyle.content_text(profile,"tell"))
	_line(flow,Inspect.t("应对：","Counter: ")+MineStyle.content_text(profile,"counter"),15,MineStyle.CYAN)
	var parameters: Dictionary = profile.get("attack_parameters",{})
	_line(flow,Inspect.t("预警 %.2f 秒 · 收势 %.2f 秒","Tell %.2f s · recovery %.2f s") % [float(parameters.get("tell_seconds",0)),float(profile.get("recovery_seconds",0))],14,MineStyle.MUTED)
	_line(flow,Inspect.t("当前等级招式","CURRENT LEVEL PATTERN"),17,MineStyle.AMBER)
	for description: String in profile.get("tier_descriptions",[]): _line(flow,description)
	var signature: Dictionary = profile.get("biome_skill",{})
	_line(flow,Inspect.t("种族特性 · ","REGION TRAIT · ")+MineStyle.content_text(signature,"name"),17,MineStyle.AMBER)
	_line(flow,trait_text(signature))
	_line(flow,Inspect.t("技能命中值还受招式、精英、阶段与目标减免影响。","Actual hits also depend on the move, rank, phase and target mitigation."),13,MineStyle.MUTED)

func _boss_details(flow: VBoxContainer, profile: Dictionary) -> void:
	_line(flow,Inspect.t("首领技能","BOSS ABILITIES"),18,MineStyle.CYAN)
	var thresholds: Array = profile.get("phase_thresholds",[.7,.35])
	_line(flow,Inspect.t("阶段切换：生命 %.0f%% / %.0f%%；额外招式按难度累计开放。","Phase changes: %.0f%% / %.0f%% HP. Extra abilities unlock cumulatively by difficulty.") % [float(thresholds[0])*100,float(thresholds[1])*100],14,MineStyle.MUTED)
	for skill: Dictionary in boss_skill_entries(str(profile.boss_id),difficulty,ruleset):
		_line(flow,str(skill.title),17,MineStyle.CYAN if bool(skill.unlocked) else MineStyle.MUTED)
		_line(flow,str(skill.description),14)
	_line(flow,Inspect.t("场地应对","ARENA COUNTERPLAY"),17,MineStyle.AMBER)
	_line(flow,str(profile.get("arena",{}).get("topology_and_counter","")))
	_line(flow,Inspect.t("招式数值来自运行时技能；伤害系数仍受难度、阶段和目标减免影响。","Move values come from runtime abilities; damage coefficients also depend on difficulty, phase and mitigation."),13,MineStyle.MUTED)

static func boss_skill_entries(id: String, tier: int, version: int = 2) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if id == "BO06":
		if not Rules.b06_candidate_enabled() or version != 2: return entries
		var skills = preload("res://scripts/combat/b06_enemy_skills.gd")
		for index: int in skills.BOSS_ACTIONS.size():
			var action: String = skills.BOSS_ACTIONS[index]
			var gate: int = skills.BOSS_GATES[index]
			var command: Dictionary = skills.boss_action(skills.boss_profile(maxi(tier,gate)),action,Vector2.ZERO,Vector2(300,0),1)
			var description := difficulty_label(gate)+" · "+(Inspect.t("已开放","available") if tier>=gate else Inspect.t("未开放：按解锁难度预览","locked: unlock-tier preview"))+"\n"+command_description(command)
			var stages: Array[Dictionary] = [command]
			for stage: int in range(1,int(command.get("stage_count",1))):
				var follow: Dictionary = skills.boss_action(skills.boss_profile(maxi(tier,gate)),action,Vector2.ZERO,Vector2(300,0),1,stage)
				stages.append(follow)
				description += "\n"+Inspect.t("后续第 %d 段（再次预警）","Follow-up %d (new warning)") % (stage+1)+"\n"+command_description(follow)
			entries.append({"id":action,"title":skills.BOSS_NAMES[index],"unlock_difficulty":gate,"unlocked":tier>=gate,"command":command,"stages":stages,"description":description})
		return entries
	var brain = preload("res://scripts/combat/b05_boss_brain.gd").new() if id == "BO05" else Brain.new()
	brain.configure(Bosses.resolve(id,4,version),1)
	var source := Node2D.new()
	var target := Node2D.new()
	target.position = Vector2(300,0)
	var actions: Array = brain.skill_pool()
	for action: String in actions:
		brain.configure(Bosses.resolve(id,4,version),1)
		var phases: PackedStringArray = []
		for phase: int in [1,2,3]:
			if action in brain.available_actions(phase): phases.append(str(phase))
		var gate := Abilities.tier(id,action)
		brain.configure(Bosses.resolve(id,maxi(tier,gate),version),1)
		brain.phase = int(phases[0]) if not phases.is_empty() else 1
		var command: Dictionary = brain._build_action(source,target,action)
		if command.is_empty(): continue
		var state := Inspect.t("阶段 ","Phases ")+" / ".join(phases)
		if gate > 0: state = difficulty_label(gate)+(" · "+Inspect.t("已开放","available") if tier >= gate else " · "+Inspect.t("未开放","locked"))
		var description := state+"\n"+command_description(command)
		if gate > tier: description += "\n"+Inspect.t("未开放：数值按解锁难度预览。","Locked: values preview its unlock difficulty.")
		entries.append({"id":action,"title":Abilities.title(action,Words.locale.begins_with("en")),"unlock_difficulty":gate,"unlocked":gate <= tier,"command":command.duplicate(true),"description":description})
	source.free()
	target.free()
	return entries

static func command_description(command: Dictionary) -> String:
	var kind := str(command.get("kind",""))
	var names := {"melee":["近战","Melee"],"projectile":["弹道","Projectile"],"ground_area":["地面范围","Ground area"],"charge":["突进","Charge"],"pull":["牵引","Pull"],"summon":["召唤","Summon"],"haste":["加速","Haste"]}
	var shapes := {"line":["直线","line"],"cone":["扇形","cone"],"circle":["圆形","circle"],"ring":["圆环","ring"]}
	var pair: Array = names.get(kind,[kind,kind])
	var shape: Array = shapes.get(str(command.get("shape","")),["",""])
	var lines: PackedStringArray = [Inspect.t(str(pair[0]),str(pair[1]))+" · "+Inspect.t(str(shape[0]),str(shape[1])),Inspect.t("预警 %.2f 秒 · 锁定 %.2f 秒 · 收势 %.2f 秒","Tell %.2f s · lock %.2f s · recovery %.2f s") % [float(command.get("tell",0)),float(command.get("lock",0)),float(command.get("recovery",0))]]
	if command.has("coefficient"): lines.append(Inspect.t("招式系数 %.0f%% · 阶段1预览","Action coefficient %.0f%% · phase 1 preview") % float(command.coefficient))
	if float(command.get("damage_multiplier",0)) > 0: lines.append(Inspect.t("单次伤害系数 ×%.2f","Per-hit damage coefficient ×%.2f") % float(command.damage_multiplier))
	if int(command.get("count",0)) > 0: lines.append(Inspect.t("数量 %d","Count %d") % int(command.count))
	if float(command.get("duration",0)) > 0: lines.append(Inspect.t("持续 %.1f 秒","Duration %.1f s") % float(command.duration))
	if float(command.get("cooldown",0)) > 0: lines.append(Inspect.t("招式冷却 %.1f 秒","Ability cooldown %.1f s") % float(command.cooldown))
	if float(command.get("range",0)) > 0: lines.append(Inspect.t("范围 %.0f","Range %.0f") % float(command.range))
	if float(command.get("radius",0)) > 0: lines.append(Inspect.t("半径 %.0f","Radius %.0f") % float(command.radius))
	if float(command.get("inner_radius",0)) > 0: lines.append(Inspect.t("内圈半径 %.0f","Inner radius %.0f") % float(command.inner_radius))
	if kind == "haste": lines.append(Inspect.t("移动速度 ×%.2f · 最多 %d 个目标","Movement speed ×%.2f · up to %d targets") % [float(command.get("multiplier",1)),int(command.get("max_targets",0))])
	if kind == "summon":
		lines.append(Inspect.t("召唤：","Summons: ")+MineStyle.content_text(Catalog.enemy(str(command.get("summon_enemy_id",""))),"name"))
		if float(command.get("hatch_delay",0)) > 0: lines.append(Inspect.t("孵化 %.1f 秒","Hatching %.1f s") % float(command.hatch_delay))
	if bool(command.get("landing_only",false)): lines.append(Inspect.t("仅落点造成伤害","Damage only at the landing point"))
	if float(command.get("weakpoint_duration",0)) > 0: lines.append(Inspect.t("弱点窗口 %.2f 秒","Weakpoint window %.2f s") % float(command.weakpoint_duration))
	var status: Dictionary = command.get("status",{})
	if not status.is_empty():
		var status_names := {"corrosion":["腐蚀","Corrosion"],"shock":["感电","Shock"],"slow":["减速","Slow"],"bleed":["流血","Bleed"],"burn":["灼烧","Burn"],"grievous":["重伤","Grievous"]}
		var status_pair: Array = status_names.get(str(status.get("id","")),[str(status.get("id","")),str(status.get("id",""))])
		lines.append(Inspect.t(str(status_pair[0]),str(status_pair[1]))+" · %.1f s" % float(status.get("duration",0)))
	return "\n".join(lines)

static func trait_text(signature: Dictionary) -> String:
	match str(signature.get("id","")):
		"capacitor_guard": return Inspect.t("有效命中获得最大生命 %.0f%% 的护盾，持续 %.1f 秒，冷却 %.1f 秒。","Confirmed hits grant a %.0f%% max-HP shield for %.1f s, with a %.1f s cooldown.") % [float(signature.guard_ratio)*100,float(signature.guard_seconds),float(signature.cooldown_seconds)]
		"venom_wound": return Inspect.t("有效命中追加 %.1f 秒腐蚀，强度为该次技能伤害的 %.0f%%。","Confirmed hits apply %.1f s of corrosion with power equal to %.0f%% of the skill's damage.") % [float(signature.status_seconds),float(signature.status_power_ratio)*100]
		"grave_drain": return Inspect.t("有效命中恢复该次技能伤害的 %.0f%%，上限为最大生命 %.0f%%，冷却 %.1f 秒。","Confirmed hits heal %.0f%% of skill damage, capped at %.0f%% max HP, with a %.1f s cooldown.") % [float(signature.heal_damage_ratio)*100,float(signature.heal_hp_cap)*100,float(signature.cooldown_seconds)]
		"blood_rage": return Inspect.t("生命不高于 %.0f%% 时，技能伤害 ×%.2f，移动速度 ×%.2f。","At or below %.0f%% HP, skill damage is ×%.2f and movement speed is ×%.2f.") % [float(signature.health_threshold)*100,float(signature.damage_multiplier),float(signature.move_multiplier)]
	return ""

static func role_label(role: String) -> String:
	var names := {"melee":["近战","Melee"],"ranged":["远程","Ranged"],"artillery":["炮击","Artillery"],"support":["支援","Support"],"summoner":["召唤","Summoner"],"healer":["治疗","Healer"],"tank":["重装","Tank"],"assassin":["突袭","Assassin"]}
	var pair: Array = names.get(role,["野怪","Enemy"])
	return Inspect.t(str(pair[0]),str(pair[1]))

static func difficulty_label(value: int) -> String:
	return "D%d · " % value+[Inspect.t("普通","Normal"),Inspect.t("进阶","Advanced"),Inspect.t("困难","Hard"),Inspect.t("险境","Perilous"),Inspect.t("极限","Extreme")][clampi(value,0,4)]

func _line(parent: Node, text: String, font_size: int = 15, tint: Color = MineStyle.INK) -> Label:
	var label := MineStyle.literal(parent,text,Vector2.ZERO,Vector2(394,0),font_size,tint)
	label.custom_minimum_size.x = 394
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
