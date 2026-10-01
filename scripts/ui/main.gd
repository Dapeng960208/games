extends Node

const DifficultyProfiles = preload("res://scripts/combat/enemy_profiles.gd")
const ExpeditionScript = preload("res://scripts/world/expedition_controller.gd")
const ExpeditionPanel = preload("res://scripts/ui/expedition_panel.gd")
const FieldEquipmentPanel = preload("res://scripts/ui/field_equipment_panel.gd")
const LootPickupPanel = preload("res://scripts/ui/loot_pickup_panel.gd")
var loot_flow_active := false
const RoutePlanner = preload("res://scripts/world/route_generator.gd")
const CampNavTile = preload("res://scripts/ui/illustrated_nav_tile.gd")
const CampArtwork = preload("res://scripts/ui/storybook_art.gd")
const Controls = preload("res://scripts/core/control_bindings.gd")
const BackpackPanel = preload("res://scripts/ui/backpack_panel.gd")
const DIFFICULTY_KEYS := ["DIFFICULTY_NORMAL","DIFFICULTY_CHALLENGING","DIFFICULTY_HARD","DIFFICULTY_SEVERE","DIFFICULTY_EXTREME"]

var backdrop: Node2D
var world: Node2D
var ui: Control
var screen: Control
var room: Node2D
var hud: Control
var route := "menu"
var modals: Array[Dictionary] = []
var pending_outcome := ""
var quit_after_result := false
var room_start_failed := false
var selected_difficulty: int = 0
var selected_biome := "B01"
var expedition: RefCounted
var expedition_status: Label
var expedition_action_pending := false
var music: Node
var music_tick := 0.0
var audio_sliders: Dictionary = {}
var demo_hero := "CH01"
var settings_tab := "general"
var pending_binding_action := ""
var binding_feedback: Label

const HERO_LOOPS := {
	"CH01":["破岩斧卫","贴身积累破势，重击打穿敌阵。","普攻 / Q 蓄势 → W 破阵","BREAKER","Build pressure up close, then break the line."],
	"CH02":["游走枪手","连续命中标记弱点，精确射击收割。","两次普攻 → 第三击 / 技能破绽","GUNNER","Mark a weak point with two hits. Consume it with a shot or skill."],
	"CH03":["共鸣术士","布置节点，蓄能后连锁引爆。","W 布点 → Q 充能 → E 引爆","RESONATOR","Place nodes, charge them, trigger a chain reaction."]
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_install_inputs()
	Words.initialize(Game.profile.get("settings",{}).get("language","zh_CN"))
	_apply_display()
	backdrop = Node2D.new()
	backdrop.set_script(load("res://scripts/ui/menu_backdrop.gd"))
	var backdrop_layer := CanvasLayer.new()
	backdrop_layer.name = "MenuBackground"
	backdrop_layer.layer = -1
	add_child(backdrop_layer)
	backdrop_layer.add_child(backdrop)
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = MineStyle.make_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	Game.run_started.connect(_on_run_started)
	Game.run_finished.connect(_on_run_finished)
	Game.settlement_failed.connect(_on_settlement_failed)
	if ResourceLoader.exists("res://scripts/audio/music_director.gd"):
		music = load("res://scripts/audio/music_director.gd").new()
		add_child(music)
		music.configure(Game)
	show_menu()
	if Game.run != null and not Game.last_error.is_empty():
		_on_settlement_failed("abandoned")
	# Dedicated automation scripts load this scene and call the same public routes.

func _install_inputs() -> void:
	Controls.install(Game.profile.get("settings", {}).get("controls", {}))

func _control_label(action: String) -> String:
	return Controls.label_for(action, Game.profile.get("settings", {}).get("controls", {}), Words.locale)

func _new_screen(next_route: String) -> void:
	_clear_modals()
	if is_instance_valid(screen):
		screen.queue_free()
	if is_instance_valid(hud):
		hud.queue_free()
		hud = null
	expedition_status = null
	route = next_route
	world.visible = next_route == "run"
	backdrop.visible = next_route != "run"
	backdrop.camp = next_route != "menu"
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)
	if next_route in ["result","room_error"]: _screen_shade(0.68)

func show_menu() -> void:
	_new_screen("menu")
	_screen_shade(0.06)
	var title_page := MineStyle.panel(screen,Vector2(66,83),Vector2(606,269))
	title_page.name = "MenuTitlePage"
	_camp_ui_icon(title_page,"workshop",Vector2(24,17),Vector2(39,39))
	MineStyle.literal(title_page,"ABYSS SALVAGER  /  CIRCUIT TRIAL",Vector2(78,26),Vector2(506,24),12,MineStyle.CYAN)
	MineStyle.label(title_page,"TITLE",Vector2(25,70),Vector2(557,80),52,MineStyle.INK)
	MineStyle.literal(title_page,_ex_text("借敌之力，重写战场。","TURN FIRE INTO YOUR WEAPON."),Vector2(29,160),Vector2(544,40),26,MineStyle.AMBER)
	MineStyle.literal(title_page,_ex_text("三个职业，三种连招。\n踏上阳光中的遗迹，开启你的远征。","Three heroes. Three combat styles.\nJourney through the sunlit ruins."),Vector2(29,208),Vector2(540,46),17,MineStyle.MUTED)
	var hero_id: String = Game.profile.get("selected_hero","CH01")
	MineStyle.hero_portrait(screen,hero_id,Vector2(733,116),Vector2(430,476)).name = "MenuHeroIllustration"
	var caption := MineStyle.panel(screen,Vector2(786,584),Vector2(338,65))
	MineStyle.literal(caption,MineStyle.content_text(ContentRegistry.hero(hero_id),"name"),Vector2(19,9),Vector2(304,31),25,MineStyle.INK)
	MineStyle.literal(caption,_ex_text("准备好，向着新的区域出发。","READY FOR THE NEXT JOURNEY."),Vector2(20,41),Vector2(302,18),11,MineStyle.CYAN)
	var demo := _camp_navigation(screen,Vector2(74,375),Vector2(420,72),_ex_text("完整技能试玩","FULL-SKILL TRIAL"),_ex_text("Lv.8 完整技能 · 独立试玩","Level 8 · All skills · Separate trial"),5,MineStyle.CYAN,show_demo_select,true)
	demo.name = "FullSkillDemo"
	demo.disabled = Game.run != null
	var cont := _camp_navigation(screen,Vector2(74,460),Vector2(420,66),Words.text("CONTINUE"),_ex_text("回到营地，继续你的旅程","Return to camp and continue"),4,Color("997244"),_continue_game)
	cont.disabled = not Game.has_profile
	_camp_navigation(screen,Vector2(74,542),Vector2(420,44),Words.text("NEW_GAME"),"",0,Color("997244"),_request_new_profile)
	MineStyle.button(screen,"SETTINGS",Vector2(74,606),Vector2(267,44),show_settings)
	MineStyle.button(screen,"QUIT",Vector2(355,606),Vector2(139,44),_quit)
	_show_warning(screen,Vector2(516,670),Vector2(684,25))
	(cont if demo.disabled else demo).grab_focus()
func _screen_shade(opacity: float) -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.965,0.922,0.828,clampf(opacity,0.0,0.86))
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	if route == "menu":
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1.0,0.96,0.85,0.98),Color(1.0,0.96,0.85,0.84),Color(1.0,0.96,0.85,0)])
		gradient.offsets = PackedFloat32Array([0.0,0.52,1.0])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill_from = Vector2.ZERO
		texture.fill_to = Vector2(1,0)
		var veil := TextureRect.new()
		veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		veil.texture = texture
		veil.size = Vector2(1020,720)
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(veil)

func show_demo_select() -> void:
	_new_screen("demo_select")
	_screen_shade(0.68)
	MineStyle.literal(screen,_ex_text("引雷试炼","CIRCUIT TRIAL"),Vector2(56,48),Vector2(750,62),40)
	MineStyle.literal(screen,_ex_text("选择你的战斗方式 · Lv.8 完整技能 · 独立试玩","CHOOSE YOUR COMBAT LOOP · LEVEL 8 · SEPARATE TRIAL"),Vector2(58,111),Vector2(1120,35),18,MineStyle.MUTED)
	for index in range(3):
		var id: String = ["CH01","CH02","CH03"][index]
		var hero: Dictionary = ContentRegistry.hero(id)
		var words: Array = HERO_LOOPS[id]
		var accent: Color = MineStyle.resource_color(str(hero.get("resource_type","rage")))
		var card := MineStyle.panel(screen,Vector2(56+index*396,166),Vector2(376,430))
		card.add_theme_stylebox_override("panel",MineStyle.box(MineStyle.PANEL,accent.lightened(0.28)))
		MineStyle.literal(card,"0"+str(index+1)+" / "+str(words[3]),Vector2(22,16),Vector2(332,28),15,accent)
		MineStyle.hero_portrait(card,id,Vector2(81,49),Vector2(215,218))
		MineStyle.literal(card,MineStyle.content_text(hero,"name")+" · "+_ex_text(str(words[0]),str(words[3])),Vector2(22,266),Vector2(332,38),24)
		MineStyle.literal(card,_ex_text(str(words[1]),str(words[4])),Vector2(22,314),Vector2(332,58),17,MineStyle.MUTED)
		var choose := MineStyle.button(card,"",Vector2(22,375),Vector2(332,44),func(): _start_demo(id))
		choose.name = "Demo_"+id
		choose.text = _ex_text("以此职业进入","ENTER TRIAL")
		MineStyle.primary(choose,accent)
		choose.disabled = Game.run != null
		if id == demo_hero: choose.grab_focus()
	MineStyle.literal(screen,_ex_text("右键移动 · 左键 / A 普攻 · Q W E R 技能 · 职业被动自动触发","RIGHT CLICK MOVE · LEFT CLICK / A ATTACK · Q W E R SKILLS · AUTOMATIC PASSIVE"),Vector2(56,616),Vector2(930,36),18,MineStyle.CYAN)
	MineStyle.button(screen,"BACK",Vector2(1028,626),Vector2(196,48),show_menu)

func _start_demo(hero_id: String) -> void:
	demo_hero = hero_id
	if not Game.start_demo(hero_id,selected_difficulty): _show_save_error()

func _continue_game() -> void:
	if Game.run != null and not Game.expedition_snapshot().is_empty():
		_on_run_started()
	else:
		show_camp()

func show_camp() -> void:
	if room_start_failed and Game.run != null: return
	_new_screen("camp")
	_screen_shade(0.07)
	var hero_id: String = Game.profile.get("selected_hero","CH01")
	var hero: Dictionary = ContentRegistry.hero(hero_id)
	var stats: Dictionary = Game.selected_stats()
	var level: int = Game.hero_level(hero_id)
	var identity: Array = HERO_LOOPS.get(hero_id,HERO_LOOPS.CH01)
	var accent := MineStyle.resource_color(str(hero.get("resource_type","rage")))
	# The courtyard remains a vivid part of the screen. Paper is reserved for
	# information and interactions, with the illustrated hero in the landscape.
	var brand := MineStyle.panel(screen,Vector2(42,22),Vector2(344,79))
	brand.name = "CampBrand"
	_camp_ui_icon(brand,"workshop",Vector2(10,7),Vector2(62,62))
	MineStyle.literal(brand,"THE LANTERN WORKSHOP",Vector2(82,10),Vector2(244,21),11,MineStyle.CYAN)
	var brand_title := MineStyle.label(brand,"CAMP",Vector2(80,30),Vector2(246,39),20 if Words.locale == "en" else 29,MineStyle.INK)
	brand_title.name = "CampHeading"
	brand_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var bank := MineStyle.panel(screen,Vector2(998,24),Vector2(238,57))
	bank.name = "CampBank"
	_camp_ui_icon(bank,"gold",Vector2(10,6),Vector2(43,43))
	MineStyle.label(bank,"BANK_TOTAL",Vector2(62,11),Vector2(162,33),18,MineStyle.AMBER,{"gold":Game.profile.get("permanent_gold",0)})
	var portrait := MineStyle.hero_portrait(screen,hero_id,Vector2(28,116),Vector2(380,428))
	portrait.name = "CampHeroIllustration"
	var identity_plate := MineStyle.panel(screen,Vector2(42,505),Vector2(344,128))
	identity_plate.name = "CampHeroIdentity"
	MineStyle.literal(identity_plate,MineStyle.content_text(hero,"name"),Vector2(20,7),Vector2(210,40),30,MineStyle.INK)
	MineStyle.literal(identity_plate,"Lv."+str(level),Vector2(246,11),Vector2(78,35),22,accent).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MineStyle.literal(identity_plate,_ex_text(str(identity[0]),str(identity[3])),Vector2(21,48),Vector2(300,26),17,accent)
	MineStyle.literal(identity_plate,_ex_text("生命 %d   攻击 %.1f   护甲 %d","HP %d   ATK %.1f   ARM %d") % [int(stats.get("max_hp",100)),float(stats.get("attack",20)),int(stats.get("armor",0))],Vector2(21,78),Vector2(302,24),14,MineStyle.MUTED)
	MineStyle.literal(identity_plate,_ex_text(str(identity[2]),str(identity[4])),Vector2(21,105),Vector2(302,20),12,MineStyle.MUTED)
	var departure := MineStyle.panel(screen,Vector2(430,112),Vector2(806,196))
	departure.name = "CampDeparturePlan"
	_camp_ui_icon(departure,"route",Vector2(17,10),Vector2(48,48))
	MineStyle.literal(departure,_ex_text("下一站，向着阳光出发。","YOUR NEXT EXPEDITION."),Vector2(76,14),Vector2(706,39),27,MineStyle.INK)
	MineStyle.literal(departure,_ex_text("出发 Lv.%d · 预计 %d 站 / 目标、遗物、补给与首领","DEPARTURE LV.%d · %d STOPS / OBJECTIVES, RELICS & A BOSS") % [level,RoutePlanner.node_count_for_level(level)],Vector2(24,63),Vector2(758,28),15,MineStyle.MUTED)
	_build_biome_selector()
	var difficulty_hint := MineStyle.literal(screen,"",Vector2(454,264),Vector2(758,22),12,MineStyle.INK)
	difficulty_hint.name = "DepartureDifficultyHint"
	var difficulty_choice := OptionButton.new()
	difficulty_choice.name = "DepartureDifficulty"
	difficulty_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	difficulty_choice.position = Vector2(967,214)
	difficulty_choice.size = Vector2(245,44)
	difficulty_choice.add_theme_font_size_override("font_size",17)
	for index in DIFFICULTY_KEYS.size(): difficulty_choice.add_item(Words.text(DIFFICULTY_KEYS[index]),index)
	selected_difficulty = clampi(selected_difficulty,0,DifficultyProfiles.MAX_DIFFICULTY)
	difficulty_choice.select(selected_difficulty)
	screen.add_child(difficulty_choice)
	difficulty_choice.item_selected.connect(func(index: int):
		selected_difficulty = clampi(index,0,DifficultyProfiles.MAX_DIFFICULTY)
		_update_departure_difficulty_hint())
	_update_departure_difficulty_hint()
	var choices := [
		["heroes",_ex_text("英雄档案","HERO DOSSIERS"),_ex_text("选择伙伴 · 找到你的战斗风格","Choose a hero and a fighting style"),0,MineStyle.CYAN],
		["skills",_ex_text("技能修习","SKILL LEDGER"),_ex_text("查看连招 · 解锁新的能力","Learn combos and unlock abilities"),1,Color("9b574c")],
		["inventory",_ex_text("装备工坊","EQUIPMENT"),_ex_text("仓库配装 · 多选回收换金币","Loadout · Sell spare gear for gold"),2,Color("997244")],
		["shop",_ex_text("装备商城","EQUIPMENT SHOP"),_ex_text("六套新装备 · 整套购买或补齐","6 new sets · Buy or complete a set"),3,Color("657e4c")]
	]
	for index in choices.size():
		var entry: Array = choices[index]
		var mode: String = entry[0]
		var button := _camp_navigation(screen,Vector2(430+(index%2)*414,326+(index/2)*116),Vector2(392,100),entry[1],entry[2],entry[3],entry[4],func(): show_workshop(mode))
		button.name = "Open_"+mode
	var circuit := MineStyle.panel(screen,Vector2(430,574),Vector2(444,67))
	circuit.name = "CampCircuitHint"
	_camp_ui_icon(circuit,"state_shock",Vector2(10,6),Vector2(52,52))
	MineStyle.literal(circuit,_ex_text("职业被动 · 自动生效","HERO PASSIVE · AUTOMATIC"),Vector2(74,9),Vector2(348,24),17,MineStyle.CYAN)
	MineStyle.literal(circuit,_ex_text("四项技能搭配普攻   ·   在设置中开启自动普攻","Chain four skills with attacks · Auto attack in settings"),Vector2(74,37),Vector2(348,21),12,MineStyle.MUTED)
	circuit.tooltip_text = _ex_text("每位英雄拥有符合职业定位的独特被动；战斗中自动触发，无需额外操作。","Each hero has a unique role-based passive that triggers automatically in combat.")
	circuit.mouse_filter = Control.MOUSE_FILTER_PASS
	var depart := _camp_navigation(screen,Vector2(900,571),Vector2(336,82),_ex_text("开始远征","BEGIN EXPEDITION"),_ex_text("登上升降台 · 探索新的区域","Board the lift and explore"),4,MineStyle.CYAN,_start_run,true)
	depart.name = "Depart"
	var demo := _camp_navigation(screen,Vector2(430,658),Vector2(302,44),_ex_text("完整技能试玩","FULL-SKILL TRIAL"),"",5,Color("826647"),show_demo_select)
	demo.name = "FullSkillDemo"
	MineStyle.button(screen,"MAIN_MENU",Vector2(42,650),Vector2(164,44),show_menu)
	var camp_settings := MineStyle.button(screen,"SETTINGS",Vector2(218,650),Vector2(168,44),show_settings)
	camp_settings.name = "CampSettings"
	camp_settings.text = _ex_text("设置与操作","SETTINGS")
	camp_settings.size = Vector2(168,44)
	_show_warning(screen,Vector2(752,671),Vector2(478,25))
	depart.grab_focus()

func _camp_navigation(parent: Node, at: Vector2, extent: Vector2, title: String, subtitle: String, icon_index: int, accent: Color, action: Callable, prominent: bool = false) -> Button:
	var tile := CampNavTile.new()
	tile.position = at
	tile.size = extent
	tile.custom_minimum_size = Vector2(44,44)
	parent.add_child(tile)
	tile.configure(title,subtitle,icon_index,accent,prominent)
	tile.pressed.connect(action)
	return tile

func _camp_ui_icon(parent: Node, key: String, at: Vector2, extent: Vector2) -> Control:
	var art_id: String = {"workshop":"lantern","gold":"coin","route":"compass","state_shock":"circuit_orb"}.get(key,key)
	var painted: Texture2D = CampArtwork.texture(art_id)
	if painted != null:
		var illustration := TextureRect.new()
		illustration.texture = painted
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.position = at
		illustration.size = extent
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(illustration)
		return illustration
	var icon := Control.new()
	icon.set_script(load("res://scripts/ui/generated_ui_icon.gd"))
	icon.position = at
	icon.size = extent
	parent.add_child(icon)
	icon.configure(key)
	return icon
func _departure_enemy_count(difficulty: int) -> int:
	var total := 0
	var definition: Dictionary = WorldCatalog.biomes().get(selected_biome,{})
	var rooms: Array = definition.get("room_ids",[])
	var sample_room := str(rooms[0]) if not rooms.is_empty() else "L01"
	for zone in DifficultyProfiles.ZONE_COUNT:
		total += int(DifficultyProfiles.encounter_plan(sample_room,zone,difficulty).get("total_count",0))
	return total

func _update_departure_difficulty_hint() -> void:
	var hint: Label = screen.find_child("DepartureDifficultyHint",true,false)
	if hint == null: return
	var difficulty := clampi(selected_difficulty,0,DifficultyProfiles.MAX_DIFFICULTY)
	var definition: Dictionary = WorldCatalog.biomes().get(selected_biome,{})
	var rooms: Array = definition.get("room_ids",[])
	var sample_room := str(rooms[0]) if not rooms.is_empty() else "L01"
	var level := DifficultyProfiles.encounter_level(sample_room,0,difficulty)
	var enhancement: String = ["+0","+0–1","+1","+2","+3"][difficulty]
	var normal_drops := 2 if difficulty >= 2 else 1
	var boss_drops := 2+int(difficulty/2)
	var boss_boost := _ex_text("强化+1，上限+3","+1 boost, cap +3") if difficulty > 0 else _ex_text("强化+0","+0")
	hint.text = _ex_text("基础敌群 %d · 敌人Lv.%d · 本族掉落%d件 %s · 首领%d件 %s","BASE: %d foes · Enemy Lv.%d · Faction gear %d / %s · Boss %d / %s") % [_departure_enemy_count(difficulty),level,normal_drops,enhancement,boss_drops,boss_boost]
	hint.tooltip_text = _ex_text("基础敌数不含任务限量增援。敌人属性随等级成长。强化档次为现有掉落等级；重复装备按规则折算金币。","Base enemy count excludes limited objective reinforcements. Enemy stats grow with level. Enhancement is the current drop level; duplicate gear converts to gold.")
	hint.mouse_filter = Control.MOUSE_FILTER_PASS

func _ex_text(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _build_biome_selector() -> void:
	var available: Array = ExpeditionScript.unlocked_biomes(Game.profile)
	if not available.has(selected_biome):
		selected_biome = "B01"
	var picker := OptionButton.new()
	picker.name = "DepartureBiome"
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.position = Vector2(454,214)
	picker.size = Vector2(495,44)
	picker.add_theme_font_size_override("font_size",17)
	var plans: Array[Dictionary] = WorldCatalog.region_plan()
	for index in plans.size():
		var definition: Dictionary = plans[index]
		var biome_id: String = definition.biome_id
		var implemented: bool = definition.implemented
		var locked := not available.has(biome_id)
		var status := _ex_text(" · 待开发"," · TODO") if not implemented else (_ex_text(" · 首领未解锁", " · Locked") if locked else "")
		picker.add_item(MineStyle.content_text(definition,"name",biome_id)+status,index)
		picker.set_item_disabled(index,not implemented or locked)
		picker.set_item_metadata(index,biome_id if implemented else "")
		var race_name := MineStyle.content_text(definition,"race","")
		var availability := _ex_text("已实现 · 可出发探索","Implemented · ready to explore")
		if not implemented:
			availability = _ex_text("待开发 · 仅展示计划，尚不能进入","TODO · roadmap only; this region cannot be entered")
		elif locked:
			availability = _ex_text("未解锁 · 击败前一区域首领并撤离后解锁","Locked · defeat the previous boss and extract to unlock")
		picker.get_popup().set_item_tooltip(index,race_name+"\n"+availability)
	picker.select(int(selected_biome.trim_prefix("B"))-1)
	picker.item_selected.connect(func(index: int):
		if index < 0 or index >= picker.item_count or picker.is_item_disabled(index): return
		var biome_id: String = str(picker.get_item_metadata(index))
		if WorldCatalog.biomes().has(biome_id):
			selected_biome = biome_id
			_update_departure_difficulty_hint())
	screen.add_child(picker)
	MineStyle.literal(screen,_ex_text("击败首领并撤离后开放下一区域", "Defeat the boss and extract to unlock the next area"),Vector2(454,286),Vector2(490,18),10,MineStyle.MUTED)
	var roadmap := MineStyle.literal(screen,_ex_text("12 个地区规划 · 4 个已实现 / 8 个待开发", "12 REGIONS PLANNED · 4 PLAYABLE / 8 TODO"),Vector2(953,286),Vector2(259,18),10,MineStyle.CYAN)
	roadmap.name = "CampRegionPlanSummary"
	roadmap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	roadmap.tooltip_text = _ex_text("前四个地区保留逐关解锁。其余八个地区仅作开发计划展示，尚不能进入。","The first four regions unlock in order. The other eight are roadmap entries and cannot be entered.")

func _build_expedition_status() -> void:
	if is_instance_valid(expedition_status):
		expedition_status.get_parent().queue_free()
	if expedition == null or not expedition.active() or not is_instance_valid(screen):
		return
	var map_button := MineStyle.button(screen,"",Vector2(988,16),Vector2(134,44),func():
		if modals.is_empty():
			show_expedition(false))
	map_button.name = "ExpeditionMapButton"
	expedition_status = MineStyle.literal(map_button,"",Vector2(10,7),Vector2(114,30),17,MineStyle.INK)
	expedition_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_instance_valid(hud): hud.place_route_button(map_button)
	_update_expedition_status()

func _update_expedition_status() -> void:
	if not is_instance_valid(expedition_status) or expedition == null or not expedition.active():
		return
	var key: String = Controls.label_for("expedition_map",Game.profile.get("settings",{}).get("controls",{}),Words.locale)
	expedition_status.text = _ex_text("路线  [", "Route  [") + key + "]"
	if is_instance_valid(hud): hud.place_route_button(expedition_status.get_parent())

func _expedition_node_count() -> int:
	if expedition == null: return 0
	return expedition.snapshot().get("route",{}).get("nodes",[]).size()

func _on_expedition_room_completed() -> void:
	_update_expedition_status()
	if expedition != null and expedition.active():
		call_deferred("_show_loot_pickup")

func _show_loot_pickup() -> void:
	if Game.run == null or expedition == null or not expedition.active() or not modals.is_empty(): return
	loot_flow_active = true
	for offer: Dictionary in expedition.snapshot().get("relic_offers", []):
		if str(offer.get("decision", "")).is_empty():
			_show_pending_expedition_offer()
			return
	var offers: Array = Game.pending_field_equipment()
	if offers.is_empty():
		loot_flow_active = false
		_show_pending_expedition_offer()
		return
	loot_flow_active = true
	var panel := _push_modal("", Vector2(840,574))
	panel.name = "LootPickupModal"
	var pickup := LootPickupPanel.new()
	pickup.size = panel.size
	panel.add_child(pickup)
	pickup.configure(offers)
	pickup.close_requested.connect(_pop_modal)
	pickup.inspect_requested.connect(func(drop_id: String):
		_pop_modal()
		_show_field_equipment({"drop_id":drop_id}))
	pickup.pack_requested.connect(func(drop_id: String):
		_choose_field_equipment(drop_id, "keep", str(expedition.snapshot().get("checkpoint_id", ""))))

func show_expedition(at_exit: bool = false) -> void:
	if expedition == null or not expedition.active() or Game.run == null:
		return
	var panel := _push_modal("",Vector2(1072,580))
	panel.name = "ExpeditionRouteModal"
	MineStyle.literal(panel,_ex_text("远征行图 · 本次 %d 站", "EXPEDITION ATLAS · %d STOPS") % _expedition_node_count(),Vector2(28,20),Vector2(1016,45),28,MineStyle.AMBER)
	var chart := ExpeditionPanel.new()
	chart.name = "ExpeditionRouteChart"
	chart.position = Vector2(28,78)
	chart.size = Vector2(1016,480)
	panel.add_child(chart)
	# M and the route button must honor their "choose the next room" prompt.
	# Completion is still the gate; an uncleared room remains preview-only.
	chart.configure(expedition, at_exit or expedition.current_complete())
	chart.close_requested.connect(_pop_modal)
	chart.choice_requested.connect(_advance_expedition)
	chart.early_extract_requested.connect(func():
		_pop_modal()
		show_extraction())

func _advance_expedition(room_id: String) -> void:
	if expedition_action_pending or expedition == null or not expedition.active() or not is_instance_valid(room):
		return
	var context: Dictionary = expedition.candidate(room_id)
	if context.is_empty():
		return
	var checkpoint_id: String = str(expedition.snapshot().get("checkpoint_id",""))
	expedition_action_pending = true
	# Preflight has no mutations. The scene is applied only after both committed
	# choice and next-entry receipt succeed, so a disk failure leaves this room.
	var prepared: Dictionary = room.prepare_expedition_node(context)
	if prepared.is_empty() or not bool(prepared.get("valid",false)):
		room.discard_prepared_expedition_node(prepared)
		expedition_action_pending = false
		_show_expedition_error(_ex_text("下一房未能载入，当前房间已保留。", "The next room could not be loaded. Your current room is intact."),func(): _advance_expedition(room_id))
		return
	if not Game.choose_expedition_node(int(context.node_index), room_id):
		room.discard_prepared_expedition_node(prepared)
		expedition_action_pending = false
		_show_expedition_error(Words.text(Game.last_error),func(): _advance_expedition(room_id))
		return
	var runtime: Dictionary = prepared.get("runtime",room.expedition_runtime_snapshot())
	if not Game.advance_expedition_node(runtime,checkpoint_id):
		room.discard_prepared_expedition_node(prepared)
		expedition_action_pending = false
		_show_expedition_error(Words.text(Game.last_error),func(): _advance_expedition(room_id))
		return
	# Entry transactions may materialize a paid next-room shield. Restore the
	# committed result, not the pre-purchase/pre-advance copy from preflight.
	prepared["runtime"] = Game.expedition_snapshot().get("runtime",runtime).duplicate(true)
	room.apply_prepared_expedition_node(prepared)
	expedition_action_pending = false
	_clear_modals()
	_update_expedition_status()
	room.set_input_blocked(false)
	call_deferred("_show_pending_expedition_offer")

func _show_expedition_error(message: String, retry: Callable, preserve_action: bool = false) -> void:
	var panel := _push_modal("ERROR_TITLE",Vector2(700,318))
	if message.is_empty():
		message = _ex_text("当前操作未能完成，进度与金币已保留。请重试。", "This action could not complete. Your progress and gold are unchanged. Please retry.")
	MineStyle.literal(panel,message,Vector2(28,85),Vector2(644,108),19,MineStyle.RED)
	MineStyle.button(panel,"RETRY",Vector2(28,226),Vector2(309,52),func():
		_pop_modal()
		retry.call()).grab_focus()
	MineStyle.button(panel,"BACK",Vector2(357,226),Vector2(315,52),func():
		if preserve_action:
			_pop_modal()
			return
		_clear_modals()
		_show_pending_expedition_offer()
		if modals.is_empty():
			show_expedition(true))

func _show_pending_expedition_offer() -> void:
	if Game.run == null or expedition == null or not expedition.active() or not modals.is_empty():
		return
	for offer: Dictionary in expedition.snapshot().get("relic_offers", []):
		if str(offer.get("decision", "")).is_empty():
			_show_expedition_relic(offer)
			return
	for offer: Dictionary in Game.pending_field_equipment():
		_show_field_equipment(offer)
		return

func _show_field_equipment(offer: Dictionary) -> void:
	var drop_id := str(offer.get("drop_id", ""))
	var preview: Dictionary = Game.preview_field_equipment(drop_id)
	if preview.is_empty():
		return
	# Bind the displayed comparison to this checkpoint, including every retry.
	var checkpoint_id := str(expedition.snapshot().get("checkpoint_id", ""))
	var panel := _push_modal("", Vector2(980,620))
	panel.name = "FieldEquipmentModal"
	modals[-1]["required"] = true
	var comparison := FieldEquipmentPanel.new()
	comparison.name = "FieldEquipmentComparison"
	comparison.size = panel.size
	panel.add_child(comparison)
	comparison.configure(preview)
	comparison.choice_requested.connect(func(decision: String): _choose_field_equipment(drop_id, decision, checkpoint_id))

func _choose_field_equipment(drop_id: String, decision: String, checkpoint_id: String) -> void:
	if expedition_action_pending or expedition == null or not expedition.active() or not is_instance_valid(room):
		return
	var comparison: Control = null
	for modal: Dictionary in modals:
		var candidate: Control = modal.node.find_child("FieldEquipmentComparison", true, false)
		if is_instance_valid(candidate): comparison = candidate
	if is_instance_valid(comparison):
		comparison.set_busy(true)
	expedition_action_pending = true
	var success: bool = Game.choose_field_equipment(drop_id, decision, room.expedition_runtime_snapshot(), checkpoint_id)
	expedition_action_pending = false
	if not success:
		if is_instance_valid(comparison): comparison.set_busy(false)
		_show_expedition_error(Words.text(Game.last_error), func(): _choose_field_equipment(drop_id, decision, checkpoint_id), true)
		return
	if not room.restore_expedition_runtime(expedition.snapshot().get("runtime", {})):
		if is_instance_valid(comparison): comparison.set_busy(false)
		_show_expedition_error(_ex_text("试装选择已保存，但角色状态恢复失败。重试会恢复同一选择，不会重复发放装备。", "Your fitting decision is saved, but character state could not be restored. Retry restores that choice without granting gear again."), func(): _choose_field_equipment(drop_id, decision, checkpoint_id), true)
		return
	_clear_modals()
	if is_instance_valid(hud):
		var item: Dictionary = ContentRegistry.equipment(str(Game.run.expedition.claimed_drop_ids.get(drop_id,{}).get("equipment_id","")))
		hud._queue_notification(_ex_text("已装备：", "Equipped: ")+MineStyle.content_text(item,"name") if decision == "equip" else _ex_text("已收进行囊：", "Packed: ")+MineStyle.content_text(item,"name"),3.5)
	if loot_flow_active: _show_loot_pickup()
	else: _show_pending_expedition_offer()

func show_expedition_service() -> void:
	if expedition == null or not expedition.active() or Game.run == null:
		return
	if expedition.current_node().get("role", "") == "supply":
		_show_expedition_supply()
	else:
		_show_pending_expedition_offer()
		if modals.is_empty():
			show_expedition(false)

func _relic_display(id: String, rank: int = 1) -> Dictionary:
	var legacy: String = {"RL01":"split", "RL02":"ember", "RL03":"arc"}.get(id, "")
	if ResourceLoader.exists("res://scripts/combat/class_relics.gd"):
		var biome: String = load("res://scripts/combat/race_relics.gd").biome_id(room)
		return load("res://scripts/combat/class_relics.gd").display(Game.run.hero_id if Game.run != null else str(Game.profile.get("selected_hero","CH01")),id,rank,biome)
	if not legacy.is_empty():
		return {"name":Words.text("RELIC_"+legacy.to_upper()+"_NAME"),"description":Words.text("RELIC_"+legacy.to_upper()+"_DESC"),"art":legacy}
	return {"name":id,"description":"","art":""}

func _relic_artwork(parent: Node, info: Dictionary, at: Vector2, extent: Vector2, fallback: String = "") -> void:
	var painted: Texture2D
	if info.get("texture") is Texture2D:
		painted = info.texture
	elif str(info.get("art","")).begins_with("res://"):
		painted = load(str(info.art)) as Texture2D
	if painted != null:
		var icon := TextureRect.new()
		icon.name = "RelicArtwork"
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = painted
		icon.position = at
		icon.size = extent
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(icon)
	else:
		var art_key := str(info.get("art",fallback))
		if not art_key.is_empty(): MineArt.relic(parent,art_key,at,extent)

func _show_expedition_relic(offer: Dictionary) -> void:
	var panel := _push_modal("",Vector2(1048,660))
	panel.name = "ExpeditionRelicModal"
	modals[-1]["required"] = true
	MineStyle.literal(panel,_ex_text("选一件遗物 · 塑造本局打法", "CHOOSE A RELIC · SHAPE THIS RUN"),Vector2(28,20),Vector2(992,47),28,MineStyle.AMBER)
	MineStyle.literal(panel,_ex_text("选择立即生效，只保留到本局结束。也可跳过并恢复 6% 最大生命。", "Choose an immediate effect for this run, or skip to recover 6% max health."),Vector2(28,80),Vector2(992,44),17,MineStyle.MUTED)
	var candidates: Array = offer.get("candidates",[])
	var cards: Array[Button] = []
	var card_height := 234.0
	for index in candidates.size():
		var id := str(candidates[index])
		var current_rank: int = int(expedition.snapshot().get("relic_levels",{}).get(id,0))
		var info := _relic_display(id,mini(2,current_rank+1))
		var card := MineStyle.button(panel,"",Vector2(28+index*336,140),Vector2(320,234),func(): _choose_expedition_relic(str(offer.offer_id),id))
		card.name = "RelicChoice_"+id
		cards.append(card)
		_relic_artwork(card,info,Vector2(116,12),Vector2(88,88),id)
		var title := MineStyle.literal(card,str(info.name)+(_ex_text(" · 升级"," · UPGRADE") if current_rank==1 else ""),Vector2(16,104),Vector2(288,0),22,MineStyle.CYAN)
		title.name = "RelicTitle"
		title.size.y = ceilf(title.get_minimum_size().y)
		var description := MineStyle.literal(card,str(info.description),Vector2(16,title.position.y+title.size.y+6),Vector2(288,0),16,MineStyle.INK)
		description.name = "RelicDescription"
		description.max_lines_visible = -1
		description.clip_text = false
		description.size.y = ceilf(description.get_minimum_size().y)
		card_height = maxf(card_height,description.position.y+description.size.y+16)
	for card: Button in cards: card.size.y = card_height
	panel.size.y = maxf(498,card_height+248)
	panel.position.y = (720-panel.size.y)/2
	var skip := MineStyle.button(panel,"",Vector2(678,140+card_height+28),Vector2(342,52),func(): _choose_expedition_relic(str(offer.offer_id),"skip"))
	skip.name = "SkipExpeditionRelic"
	skip.text = _ex_text("跳过 · 回复 6% 生命", "Skip · recover 6% health")
	skip.grab_focus()

func _choose_expedition_relic(offer_id: String, choice_id: String) -> void:
	if expedition_action_pending or not is_instance_valid(room):
		return
	expedition_action_pending = true
	var success: bool = Game.choose_run_relic(offer_id,choice_id,"",room.expedition_runtime_snapshot())
	expedition_action_pending = false
	if not success:
		_show_expedition_error(Words.text(Game.last_error),func(): _choose_expedition_relic(offer_id,choice_id))
		return
	if not room.restore_expedition_runtime(expedition.snapshot().get("runtime",{})):
		_show_expedition_error(_ex_text("遗物已保存，但角色状态恢复失败。重试不会重复发放。", "The relic decision is saved, but character state could not be restored. Retrying does not grant it again."),func(): _choose_expedition_relic(offer_id,choice_id))
		return
	_clear_modals()
	if loot_flow_active: _show_loot_pickup()
	else: _show_pending_expedition_offer()

func _show_expedition_supply() -> void:
	var panel := _push_modal("",Vector2(920,570))
	panel.name = "ExpeditionSupplyModal"
	MineStyle.literal(panel,_ex_text("矿下补给站", "UNDERGROUND SUPPLY"),Vector2(28,20),Vector2(864,45),30,MineStyle.AMBER)
	MineStyle.literal(panel,_ex_text("本局金币 ", "CARRIED GOLD ")+str(Game.run.gold)+_ex_text(" · 每项仅可购买一次", " · Each item can be bought once"),Vector2(28,81),Vector2(864,42),20,MineStyle.CYAN)
	var products := {"heal_small":["应急药剂 · 回复 15% 生命","Field dressing · heal 15%"], "heal_large":["维修包 · 回复 35% 生命","Repair kit · heal 35%"], "shield":["预备护盾 · 15%生命 · 承伤后4秒","Reserve shield · 15% HP · 4s after hit"], "amplify":["超频剂 · 后两战斗房攻击 +8%","Overclock · +8% for 2 rooms"], "scan":["勘测信标 · 显示具体敌群","Survey beacon · reveal enemies"], "mana":["共鸣液 · 回复法力","Resonance flask · restore mana"], "energy":["能量匣 · 回复能量","Energy cell · restore energy"]}
	var entries: Array = expedition.snapshot().get("supply_offers",[])
	var healing_purchased := false
	for entry: Dictionary in entries:
		if str(entry.get("product_id","")) in ["heal_small","heal_large"] and str(entry.get("decision","")) == "purchased":
			healing_purchased = true
	for index in entries.size():
		var offer: Dictionary = entries[index]
		var product := str(offer.get("product_id",""))
		var texts: Array = products.get(product,[product,product])
		var button := MineStyle.button(panel,"",Vector2(28+(index%2)*442,138+(index/2)*77),Vector2(422,64),func(): _buy_expedition_supply(str(offer.offer_id)))
		button.name = "Supply_"+product
		button.add_theme_font_size_override("font_size",16)
		var purchased := str(offer.get("decision","")).length()>0
		button.text = str(texts[1] if Words.locale == "en" else texts[0])+"\n"+(_ex_text("已购买", "Purchased") if purchased else str(offer.get("price",0))+_ex_text(" 金币", " gold"))
		if product == "shield":
			button.tooltip_text = _ex_text("下一战斗房预备15%最大生命护盾。首次吸收伤害才开始4秒倒计时；耗尽或离开该房间后失效。", "Reserve a shield worth 15% max HP for the next combat room. Its 4-second timer starts on the first absorbed hit. Ends when depleted or leaving that room.")
		button.disabled = purchased or Game.run.gold < int(offer.get("price",0))
		if product in ["heal_small","heal_large"]:
			button.disabled = button.disabled or healing_purchased or Game.run.hp >= Game.run.max_hp
		if product in ["mana","energy"]:
			button.disabled = button.disabled or str(Game.run.stats.get("resource_type","")) != product or Game.run.resource >= float(Game.run.stats.get("resource_max",0))
	MineStyle.button(panel,"BACK",Vector2(650,492),Vector2(242,48),_pop_modal).grab_focus()

func _buy_expedition_supply(offer_id: String) -> void:
	if expedition_action_pending or not is_instance_valid(room):
		return
	expedition_action_pending = true
	var success: bool = Game.purchase_run_supply(offer_id,room.expedition_runtime_snapshot())
	expedition_action_pending = false
	if not success:
		_show_expedition_error(Words.text(Game.last_error),func(): _buy_expedition_supply(offer_id))
		return
	if not room.restore_expedition_runtime(expedition.snapshot().get("runtime",{})):
		_show_expedition_error(_ex_text("补给交易已保存，但角色状态恢复失败。重试不会重复扣款。", "The purchase is saved, but character state could not be restored. Retrying will not charge again."),func(): _buy_expedition_supply(offer_id))
		return
	_clear_modals()
	_show_expedition_supply()

func _next_skill_level(level: int) -> String:
	for gate in [2,4,6,8,10,12,14,16,18,20]:
		if level < gate:
			return str(gate)
	return Words.text("LEVEL_MAX")

func show_workshop(page: String = "heroes") -> void:
	_new_screen("workshop_"+page)
	_screen_shade(0.68)
	var workshop := Control.new()
	workshop.name = "Workshop"
	workshop.set_script(load("res://scripts/ui/workshop_panel.gd"))
	workshop.app = self
	workshop.mode = page
	workshop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(workshop)

func _show_warning(parent: Node, at: Vector2, extent: Vector2) -> void:
	if not Game.storage_warning.is_empty():
		MineStyle.label(parent,"SAVED_WARNING",at,extent,16,MineStyle.RED,{"message":Words.text(Game.storage_warning)})

func _request_new_profile() -> void:
	if not Game.has_profile:
		_create_profile()
		return
	var panel := _push_modal("NEW_CONFIRM_TITLE",Vector2(650,338))
	MineStyle.label(panel,"NEW_CONFIRM_NOTE",Vector2(28,83),Vector2(594,112),19)
	MineStyle.button(panel,"CONFIRM_NEW",Vector2(28,222),Vector2(360,52),_create_profile)
	MineStyle.button(panel,"CANCEL",Vector2(409,222),Vector2(213,52),_pop_modal).grab_focus()

func _create_profile() -> void:
	if Game.new_profile():
		Words.set_locale(Game.profile.get("settings",{}).get("language","zh_CN"))
		show_camp()
	else:
		_show_save_error()

func _start_run() -> void:
	if not Game.start_run({"expedition":true,"biome_id":selected_biome,"difficulty":selected_difficulty}):
		_show_save_error()

func _on_run_started() -> void:
	loot_flow_active = false
	pending_outcome = ""
	quit_after_result = false
	room_start_failed = false
	expedition_action_pending = false
	expedition = ExpeditionScript.new(Game)
	_new_screen("run")
	room = _create_room()
	if not is_instance_valid(room):
		_fail_room_start()
		return
	room.difficulty = clampi(selected_difficulty,0,DifficultyProfiles.MAX_DIFFICULTY)
	if expedition.active():
		var first_context: Dictionary = expedition.current_context()
		var prepared: Dictionary = room.prepare_expedition_node(first_context)
		if prepared.is_empty() or not bool(prepared.get("valid",false)):
			room.discard_prepared_expedition_node(prepared)
			_fail_room_start()
			return
		room.apply_prepared_expedition_node(prepared)
	world.add_child(room)
	# _ready resolves the initial layout synchronously. Never attach gameplay
	# controls to a room whose player, geometry and supplies were not created.
	if not bool(room.get("configuration_ready")):
		_fail_room_start()
		return
	room.interaction_requested.connect(_on_interaction)
	room.room_completed.connect(_on_expedition_room_completed)
	if is_instance_valid(room.combat_audio):
		room.combat_audio.cue_played.connect(_on_combat_cue_played)
	room.set_input_blocked(false)
	_build_hud()
	if bool(Game.run.get("demo")) and expedition.current_index() == 0:
		call_deferred("_show_trial_brief")
	elif expedition.active():
		call_deferred("_show_pending_expedition_offer")

func _on_combat_cue_played(cue: String) -> void:
	if route == "run" and cue in ["impact", "heavy", "shield_hit", "shield_break"] and is_instance_valid(music):
		music.notify_impact(cue in ["heavy", "shield_break"])

func _show_trial_brief() -> void:
	if Game.run == null or not modals.is_empty(): return
	var panel := _push_modal("",Vector2(842,470))
	panel.name = "TrialBrief"
	var words: Array = HERO_LOOPS.get(Game.run.hero_id,HERO_LOOPS.CH01)
	MineStyle.literal(panel,_ex_text("轻松走位，流畅连招。","MOVE FREELY. CHAIN YOUR SKILLS."),Vector2(30,23),Vector2(782,47),31,MineStyle.CYAN)
	MineStyle.literal(panel,_ex_text(str(words[0])+" · "+str(words[2]),str(words[3])+" · "+str(words[4])),Vector2(30,88),Vector2(782,61),21,MineStyle.AMBER)
	var steps: Array = [
		_ex_text("01  右键移动","01  RIGHT-CLICK"),_ex_text("右键点击地面移动；按住可持续走位，鼠标指向决定技能方向。","Right-click the ground to move; hold to keep moving. Aim skills with the cursor."),
		_ex_text("02  四技连招","02  SKILLS / COMBO"),_ex_text("Q W E R 释放四项技能，左键或 A 普攻可穿插连招。","Use Q W E R for four skills. Weave left-click or A attacks into your combo."),
		_ex_text("03  自动被动","03  HERO / PASSIVE"),_ex_text("职业被动自动触发；设置中可开启自动普攻。","Your hero's passive triggers automatically. Enable auto attacks in settings.")]
	for index in range(3):
		MineStyle.literal(panel,str(steps[index*2]),Vector2(30,170+index*57),Vector2(176,35),18,MineStyle.CYAN)
		MineStyle.literal(panel,str(steps[index*2+1]),Vector2(211,170+index*57),Vector2(601,48),17,MineStyle.INK)
	MineStyle.literal(panel,_ex_text("默认：右键移动 · 左键 / A 普攻 · Q W E R 技能 · 空格闪避 · F 交互\n操作可自定义。按 M 选择关卡，B 打开背包。","Right-click move · Left-click / A attack · QWER skills · Space dodge · F interact\nCustomize in settings. M opens the map; B opens your backpack."),Vector2(30,350),Vector2(782,47),16,MineStyle.MUTED)
	var begin := MineStyle.button(panel,"",Vector2(534,405),Vector2(278,44),func():
		_pop_modal()
		_show_pending_expedition_offer())
	begin.text = _ex_text("开始试炼  →","BEGIN TRIAL  →")
	MineStyle.primary(begin)
	begin.grab_focus()

func _create_room() -> Node2D:
	return load("res://scenes/room.tscn").instantiate()

func _fail_room_start() -> void:
	room_start_failed = true
	if is_instance_valid(room):
		room.process_mode = Node.PROCESS_MODE_DISABLED
		room.hide()
		if room.get_parent() != null:
			room.get_parent().remove_child(room)
		room.queue_free()
		room = null
	_show_room_load_error()
	if expedition != null and expedition.active():
		# A saved expedition is a real checkpoint. A rendering/content load
		# failure must never turn it into an abandonment or delete its rewards.
		return
	# start_run already saved an activity receipt. The normal abandonment
	# transaction must clear it; failed writes retain the existing required retry.
	_settle("abandoned")

func _show_room_load_error() -> void:
	_new_screen("room_error")
	MineStyle.label(screen,"ROOM_LOAD_FAILED_TITLE",Vector2(88,152),Vector2(1052,64),36,MineStyle.RED)
	var message := MineStyle.label(screen,"ROOM_LOAD_FAILED_NOTE",Vector2(88,244),Vector2(960,100),22)
	message.name = "RoomLoadFailureMessage"
	if expedition != null and expedition.active():
		MineStyle.button(screen,"RETRY",Vector2(88,392),Vector2(390,56),_on_run_started).grab_focus()
		var leave := MineStyle.button(screen,"",Vector2(496,392),Vector2(480,56),func(): get_tree().quit())
		leave.name = "ExitWithCheckpoint"
		leave.text = _ex_text("退出 · 保留已保存远征", "Exit · keep saved expedition")
		return
	var return_button := MineStyle.button(screen,"RETURN_CAMP",Vector2(88,392),Vector2(390,56),_return_after_room_error)
	return_button.name = "RoomLoadReturnCamp"
	return_button.disabled = Game.run != null
	if not return_button.disabled:
		pending_outcome = ""
		return_button.grab_focus()

func _return_after_room_error() -> void:
	if Game.run != null:
		return
	room_start_failed = false
	show_camp()

func _build_hud() -> void:
	if is_instance_valid(hud):
		hud.queue_free()
	hud = load("res://scenes/hud.tscn").instantiate()
	hud.room = room
	hud.relic_details_requested.connect(func():
		if modals.is_empty():
			show_relics())
	hud.skill_details_requested.connect(func(slot: String):
		if modals.is_empty():
			show_combat_details(slot))
	hud.inventory_requested.connect(show_backpack)
	ui.add_child(hud)
	if not modals.is_empty():
		ui.move_child(hud,0)
	_build_expedition_status()

func show_backpack() -> void:
	if route != "run" or Game.run == null or not is_instance_valid(room) or not modals.is_empty(): return
	var panel := _push_modal("",Vector2(1060,620))
	panel.name = "CombatBackpackModal"
	var backpack := BackpackPanel.new()
	panel.add_child(backpack)
	backpack.configure(room, _pop_modal)
	backpack.equipment_changed.connect(func():
		if is_instance_valid(hud): hud.refresh())

func _on_interaction(kind: String, _payload: Dictionary) -> void:
	if not modals.is_empty():
		return
	if kind == "loot":
		_show_loot_pickup()
	elif kind in ["next", "early_extract"] and expedition != null and expedition.active():
		show_expedition(true)
	elif kind in ["relic_choice", "supply"] and expedition != null and expedition.active():
		show_expedition_service()
	elif kind == "extract":
		show_extraction()

func show_extraction() -> void:
	if Game.run == null:
		return
	if expedition != null and expedition.active() and not expedition.can_extract():
		show_expedition(false)
		return
	var panel := _push_modal("EXTRACT_TITLE",Vector2(676,357))
	MineStyle.label(panel,"EXTRACT_NOTE",Vector2(28,87),Vector2(620,147),20,MineStyle.INK,{"gold":Game.run.gold,"kept":Balance.death_keep(Game.run.gold)})
	MineStyle.button(panel,"CONFIRM_EXTRACT",Vector2(28,261),Vector2(366,52),func(): _settle("extracted"))
	MineStyle.button(panel,"CANCEL",Vector2(416,261),Vector2(232,52),_pop_modal).grab_focus()

func show_pause() -> void:
	if Game.run == null:
		return
	var panel := _push_modal("PAUSED",Vector2(568,455))
	MineStyle.label(panel,"PAUSED_NOTE",Vector2(28,76),Vector2(512,59),17,MineStyle.MUTED)
	MineStyle.button(panel,"RESUME",Vector2(28,151),Vector2(512,52),_pop_modal).grab_focus()
	MineStyle.button(panel,"RELICS",Vector2(28,219),Vector2(248,52),show_relics)
	MineStyle.button(panel,"SETTINGS",Vector2(292,219),Vector2(248,52),show_settings)
	MineStyle.button(panel,"ABANDON",Vector2(28,287),Vector2(512,52),show_abandon)
	MineStyle.button(panel,"QUIT",Vector2(28,355),Vector2(512,52),func():
		if expedition != null and expedition.active():
			show_expedition_exit()
		else:
			show_abandon(true))

func show_expedition_exit() -> void:
	if expedition == null or not expedition.active():
		return
	var panel := _push_modal("",Vector2(720,360))
	panel.name = "SaveExpeditionModal"
	_camp_ui_icon(panel,"route",Vector2(28,21),Vector2(72,72))
	MineStyle.literal(panel,_ex_text("封存这段旅程", "SEAL YOUR JOURNEY"),Vector2(122,28),Vector2(568,38),28,MineStyle.INK)
	MineStyle.literal(panel,_ex_text("保存远征并退出", "SAVE EXPEDITION AND EXIT"),Vector2(124,72),Vector2(550,26),14,MineStyle.CYAN)
	var note := _ex_text("当前位置是安全阶段。保存当前生命、资源与冷却，下次从这一站继续。", "This is a safe phase. Save health, resource and cooldowns and continue from this stop next time.")
	if not expedition.current_complete():
		note = _ex_text("当前房间尚未完成。下次从本房入口重打；本房未提交的金币与战利品不会保留。已完成房间的进度不受影响。", "This room is unfinished. Next time you restart at this room's entrance; uncommitted loot from this room is discarded. Earlier completed rooms are retained.")
	MineStyle.literal(panel,note,Vector2(36,118),Vector2(648,112),18,MineStyle.INK)
	var save := MineStyle.button(panel,"",Vector2(32,267),Vector2(408,54),_save_expedition_and_quit)
	save.name = "SaveExpeditionAndQuit"
	save.text = _ex_text("保存旅程 · 退出", "Save journey · Exit")
	MineStyle.primary(save)
	MineStyle.button(panel,"CANCEL",Vector2(458,267),Vector2(230,54),_pop_modal).grab_focus()

func _save_expedition_and_quit() -> void:
	if expedition == null or not expedition.active() or not is_instance_valid(room):
		return
	if expedition.current_complete():
		if not Game.save_expedition_checkpoint(room.expedition_runtime_snapshot()):
			_show_expedition_error(Words.text(Game.last_error),_save_expedition_and_quit)
			return
	# Combat keeps its already committed entrance receipt; it is never converted
	# into an abandonment settlement by a normal save-and-exit action.
	get_tree().quit()

func show_relics() -> void:
	if Game.run == null:
		return
	var panel := _push_modal("RELICS",Vector2(826,660))
	var cursor_y := 81.0
	if Game.run.relics.is_empty():
		MineStyle.label(panel,"NO_RELICS",Vector2(28,130),Vector2(770,92),22,MineStyle.MUTED)
	else:
		for i in range(Game.run.relics.size()):
			var info := _relic_display(str(Game.run.relics[i]),int(Game.expedition_snapshot().get("relic_levels",{}).get({"split":"RL01","ember":"RL02","arc":"RL03"}.get(Game.run.relics[i],Game.run.relics[i]),1)))
			_relic_artwork(panel,info,Vector2(26,cursor_y),Vector2(80,80),str(Game.run.relics[i]))
			var title := MineStyle.literal(panel,str(info.get("name","")),Vector2(120,cursor_y),Vector2(655,0),21,MineStyle.CYAN)
			title.size.y = ceilf(title.get_minimum_size().y)
			var description := MineStyle.literal(panel,str(info.get("description","")),Vector2(120,cursor_y+title.size.y+4),Vector2(655,0),17)
			description.size.y = ceilf(description.get_minimum_size().y)
			cursor_y += maxf(80,title.size.y+4+description.size.y)+18
	panel.size.y = maxf(472,cursor_y+76)
	panel.position.y = (720-panel.size.y)/2
	MineStyle.button(panel,"BACK",Vector2(558,panel.size.y-80),Vector2(240,52),_pop_modal).grab_focus()

func show_combat_details(slot: String = "q") -> void:
	if Game.run == null or not is_instance_valid(hud):
		return
	if slot == "progression":
		show_attributes()
		return
	if slot.begins_with("relic:"):
		show_relics()
		return
	var panel := _push_modal("COMBAT_LEDGER",Vector2(888,576))
	var chosen := slot if slot in ["q","secondary","f","ultimate","dash"] else "q"
	var body := RichTextLabel.new()
	body.name = "SkillDetailsBody"
	body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.position = Vector2(28,204)
	body.size = Vector2(832,229)
	body.add_theme_font_size_override("normal_font_size",17)
	body.scroll_active = true
	body.focus_mode = Control.FOCUS_ALL
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(body)
	var skill_title := MineStyle.label(panel,"",Vector2(28,132),Vector2(832,32),22,MineStyle.AMBER)
	var skill_values := MineStyle.label(panel,"",Vector2(28,168),Vector2(832,32),17,MineStyle.CYAN)
	var select_detail := func(which: String):
		var info: Dictionary = hud.skill_info(which)
		skill_title.text = str(info.name)+" / "+str(info.state)
		skill_values.text = str(info.summary)
		body.text = Words.text("HUD_BASE_DESCRIPTION")+"\n\n"+str(info.description)
		body.scroll_to_line(0)
	for i in range(5):
		var which: String = ["q","secondary","f","ultimate","dash"][i]
		var button := MineStyle.button(panel,_control_label(["skill_q","skill_secondary","skill_f","skill_ultimate","dash"][i]),Vector2(28+i*169,77),Vector2(156,44),func(): select_detail.call(which))
		button.name = "Detail_"+which
		button.tooltip_text = str(hud.skill_info(which).name)
	select_detail.call(chosen)
	MineStyle.label(panel,"HUD_WALLET_TOTAL",Vector2(28,445),Vector2(832,38),17,MineStyle.AMBER,{"gold":Game.run.gold,"kept":Balance.death_keep(Game.run.gold)})
	MineStyle.button(panel,"RELICS",Vector2(28,497),Vector2(250,50),show_relics)
	var attributes := MineStyle.button(panel,"",Vector2(294,497),Vector2(298,50),show_attributes)
	attributes.name = "CombatAttributes"
	attributes.text = _ex_text("角色属性","CHARACTER STATS")
	MineStyle.button(panel,"BACK",Vector2(610,497),Vector2(250,50),_pop_modal).grab_focus()

func show_attributes() -> void:
	if Game.run == null: return
	var panel := _push_modal("",Vector2(1020,620))
	panel.name = "CharacterAttributes"
	panel.set_script(null)
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var dossier: Control = load("res://scripts/ui/character_panel.gd").new()
	panel.add_child(dossier)
	dossier.configure(room,_pop_modal)

func show_abandon(exit_game: bool = false) -> void:
	if Game.run == null:
		return
	var panel := _push_modal("ABANDON_TITLE",Vector2(720,360))
	var retained := ProfileStore.retained_gold(Game.run.gold, "abandoned")
	MineStyle.label(panel,"ABANDON_NOTE",Vector2(28,87),Vector2(664,143),20,MineStyle.INK,{"gold":Game.run.gold,"kept":retained,"lost":Game.run.gold-retained})
	MineStyle.button(panel,"CONFIRM_ABANDON",Vector2(28,267),Vector2(432,52),func():
		quit_after_result = exit_game
		_settle("abandoned"))
	MineStyle.button(panel,"CANCEL",Vector2(479,267),Vector2(213,52),_pop_modal).grab_focus()

func _settle(outcome: String) -> void:
	pending_outcome = outcome
	Game.finish_run(outcome)

func _on_settlement_failed(outcome: String) -> void:
	pending_outcome = outcome
	call_deferred("_show_save_error")

func _on_run_finished(result: Dictionary) -> void:
	if bool(result.get("demo",false)):
		Words.set_locale(str(Game.profile.get("settings",{}).get("language","zh_CN")))
		_apply_display()
	if room_start_failed:
		call_deferred("_show_room_load_error")
	else:
		call_deferred("show_result",result)

func show_result(result: Dictionary) -> void:
	if is_instance_valid(room):
		room.queue_free()
		room = null
	_new_screen("result")
	expedition = null
	var outcome: String = result.get("outcome","death")
	var title: String = {"extracted":"EXTRACTED","death":"DEATH","abandoned":"ABANDONED"}.get(outcome,"DEATH")
	var accent := MineStyle.GREEN if outcome == "extracted" else MineStyle.RED
	MineStyle.label(screen,title,Vector2(86,105),Vector2(980,78),44,accent)
	if bool(result.get("demo",false)):
		MineStyle.literal(screen,_ex_text("试炼已结束 · 成长存档保持原样","TRIAL COMPLETE · YOUR PROGRESSION SAVE IS UNCHANGED"),Vector2(88,190),Vector2(1000,38),18,MineStyle.CYAN)
	else:
		MineStyle.label(screen,"SETTLED",Vector2(88,190),Vector2(800,38),18,MineStyle.MUTED)
	var data := [result.get("collected",result.get("gold",0)),result.get("retained",0),result.get("lost",0)]
	for i in range(3):
		var p := MineStyle.panel(screen,Vector2(88+i*246,265),Vector2(224,167))
		MineStyle.label(p,["COLLECTED","KEPT","LOST"][i],Vector2(21,16),Vector2(184,40),19,MineStyle.MUTED)
		var amount := MineStyle.label(p,"BANK_VALUE",Vector2(21,69),Vector2(184,74),46,MineStyle.AMBER if i == 1 else MineStyle.INK,{"gold":data[i]})
		amount.name = ["Collected","Retained","Lost"][i]
	var discoveries: Array = result.get("discoveries",result.get("new_discoveries",[]))
	MineStyle.label(screen,"RESULT_STATS",Vector2(88,447),Vector2(710,62),20,MineStyle.INK,{"kills":result.get("kills",0),"discoveries":discoveries.size()})
	var equipment_names: Array[String] = []
	for id: String in result.get("equipment_retained",[]):
		equipment_names.append(MineStyle.content_text(ContentRegistry.equipment(id),"name"))
	var equipment_receipt := _ex_text("本次没有带回新装备", "No new equipment extracted") if equipment_names.is_empty() else _ex_text("新装备已入库：", "Added to inventory: ")+" · ".join(equipment_names)
	var lost_items: int = result.get("equipment_lost",[]).size()
	if lost_items > 0: equipment_receipt = _ex_text("遗失 %d 件待带回装备 · 成功撤离后才能入库", "%d pending items lost · extract safely to keep equipment") % lost_items
	if bool(result.get("demo",false)): equipment_receipt = _ex_text("试玩奖励不写入正式库存", "Trial rewards do not enter your progression inventory")
	var loot_note := MineStyle.literal(screen,equipment_receipt,Vector2(88,512),Vector2(710,28),16,MineStyle.CYAN)
	loot_note.name = "ExtractedEquipmentReceipt"
	loot_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	loot_note.tooltip_text = equipment_receipt
	MineStyle.label(screen,"BANK_TOTAL",Vector2(88,544),Vector2(710,36),20,MineStyle.AMBER,{"gold":result.get("permanent_gold",0)})
	var hero_id: String = str(result.get("hero_id",Game.profile.get("selected_hero","CH01")))
	var field_xp: int = int(result.get("field_xp_gained",0))
	var dossier := MineStyle.panel(screen,Vector2(866,242),Vector2(326,368 if field_xp > 0 else 338))
	MineStyle.hero_portrait(dossier,hero_id,Vector2(52,12),Vector2(220,200))
	MineStyle.literal(dossier,MineStyle.content_text(ContentRegistry.hero(hero_id),"name"),Vector2(20,219),Vector2(286,36),24)
	MineStyle.label(dossier,"RESULT_HERO_XP",Vector2(20,267),Vector2(286,57),17,MineStyle.CYAN,{"xp":result.get("hero_xp_gained",0),"level":Game.hero_level(hero_id)})
	if field_xp > 0:
		var field_note := MineStyle.literal(dossier,_ex_text("含战斗积累 +%d 经验","Includes +%d field practice XP") % field_xp,Vector2(20,324),Vector2(286,28),16,MineStyle.AMBER)
		field_note.name = "FieldExperienceReceipt"
	MineStyle.button(screen,"RETURN_CAMP" if Game.has_profile else "MAIN_MENU",Vector2(88,586),Vector2(345,56),show_camp if Game.has_profile else show_menu).grab_focus()
	if bool(result.get("demo",false)):
		var again := MineStyle.button(screen,"",Vector2(451,586),Vector2(345,56),show_demo_select)
		again.text = _ex_text("换个职业再试","TRY ANOTHER HERO")
	else:
		var readout: Script = preload("res://scripts/ui/progression_readout.gd")
		var next_goal: String = readout.next_goal(hero_id,int(Game.profile.get("hero_xp",{}).get(hero_id,0)))
		var goal_label := MineStyle.literal(screen,_ex_text("下一目标：","NEXT GOAL: ")+next_goal,Vector2(88,658),Vector2(1104,30),17,MineStyle.CYAN)
		goal_label.name = "NextGrowthGoal"
	if quit_after_result:
		quit_after_result = false
		get_tree().quit()

func show_settings() -> void:
	var panel := _push_modal("SETTINGS",Vector2(880,644))
	panel.name = "SettingsPanel"
	audio_sliders.clear()
	var settings: Dictionary = Game.profile.get("settings",{})
	var general := MineStyle.button(panel,"",Vector2(28,82),Vector2(402,44),func(): _switch_settings_tab("general"))
	general.text = _ex_text("战斗与显示","COMBAT & DISPLAY")
	var controls := MineStyle.button(panel,"",Vector2(450,82),Vector2(402,44),func(): _switch_settings_tab("controls"))
	controls.name = "ControlBindingsTab"
	controls.text = _ex_text("操作与按键","CONTROLS & KEYS")
	MineStyle.selected(general if settings_tab == "general" else controls)
	if settings_tab == "controls":
		_build_control_settings(panel)
		return
	for index in range(3):
		var key: String = ["master_volume","music_volume","sfx_volume"][index]
		var title: String = [_ex_text("总音量","Master"),_ex_text("音乐","Music"),_ex_text("战斗音效","Combat SFX")][index]
		MineStyle.literal(panel,title,Vector2(28,151+index*54),Vector2(169,34),18)
		var slider := HSlider.new()
		slider.name = key
		slider.position = Vector2(208,153+index*54)
		slider.size = Vector2(544,32)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = float(settings.get(key,[1.0,0.55,0.85][index]))
		panel.add_child(slider)
		audio_sliders[key] = slider
		var number := MineStyle.literal(panel,str(roundi(slider.value*100))+"%",Vector2(772,151+index*54),Vector2(80,34),18,MineStyle.CYAN)
		var debounce := Timer.new()
		debounce.wait_time = 0.18
		debounce.one_shot = true
		panel.add_child(debounce)
		debounce.timeout.connect(func(): Game.set_setting(key,slider.value))
		slider.value_changed.connect(func(value: float):
			number.text = str(roundi(value*100))+"%"
			if is_instance_valid(music): music.set_mix(audio_sliders.master_volume.value,audio_sliders.music_volume.value,audio_sliders.sfx_volume.value)
			debounce.start())
	var language := MineStyle.button(panel,"",Vector2(28,328),Vector2(264,48),_toggle_language)
	language.text = _ex_text("语言：简体中文","Language: English")
	language.tooltip_text = _ex_text("点击切换为 English","Switch to 简体中文")
	language.grab_focus()
	var display := MineStyle.button(panel,"",Vector2(308,328),Vector2(264,48),_toggle_fullscreen)
	display.text = _ex_text("显示：全屏","Display: Fullscreen") if settings.get("fullscreen",false) else _ex_text("显示：窗口","Display: Windowed")
	var effects := MineStyle.button(panel,"",Vector2(588,328),Vector2(264,48),_toggle_fx)
	effects.text = _ex_text("特效：简化","Effects: Reduced") if settings.get("reduced_fx",false) else _ex_text("特效：完整","Effects: Full")
	var shake := MineStyle.button(panel,"",Vector2(28,392),Vector2(264,48),_toggle_camera_shake)
	shake.name = "CameraShakeSetting"
	shake.text = _ex_text("镜头震动：开启","Camera shake: On") if bool(settings.get("camera_shake",false)) else _ex_text("镜头震动：关闭","Camera shake: Off")
	var automatic := MineStyle.button(panel,"",Vector2(308,392),Vector2(264,48),func(): _toggle_combat_setting("auto_attack"))
	automatic.name = "AutoAttackSetting"
	automatic.text = _ex_text("自动普攻：开启","Auto attack: On") if bool(settings.get("auto_attack",false)) else _ex_text("自动普攻：关闭","Auto attack: Off")
	automatic.tooltip_text = _ex_text("自动攻击攻击范围内的敌人；移动与技能仍由你控制。","Automatically attack nearby enemies in reach. You control movement and skills.")
	var paths := MineStyle.button(panel,"",Vector2(588,392),Vector2(264,48),func(): _toggle_combat_setting("enemy_skill_paths"))
	paths.name = "EnemySkillPathsSetting"
	paths.text = _ex_text("敌技能路径：显示","Enemy paths: On") if bool(settings.get("enemy_skill_paths",true)) else _ex_text("敌技能路径：隐藏","Enemy paths: Off")
	paths.tooltip_text = _ex_text("隐藏野怪技能预警线与范围标记；技能伤害与判定不变。","Hide enemy warning lines and area markers. Damage and hit detection remain active.")
	MineStyle.literal(panel,_ex_text("默认：右键移动 / 按住走位，左键或 A 普攻，Q W E R 技能。\n「操作与按键」可自定义；A 分配给其他操作后不再触发普攻。\n关闭镜头震动可保持画面稳定；自动普攻可减轻连续操作。","Default: right-click / hold to move, left-click or A attack, Q W E R skills.\nCustomize in Controls & Keys. Assigning A elsewhere disables its attack alias.\nDisable camera shake for a steady view. Auto attacks ease repeated input."),Vector2(28,464),Vector2(824,84),17,MineStyle.MUTED)
	MineStyle.button(panel,"BACK",Vector2(612,566),Vector2(240,48),_pop_modal)

func _switch_settings_tab(next_tab: String) -> void:
	settings_tab = next_tab
	_pop_modal()
	show_settings()

func _build_control_settings(panel: Panel) -> void:
	MineStyle.literal(panel,_ex_text("点击按键按钮，再按新的键或鼠标按钮。重绑定即时生效并保存。","Select a binding, then press a new key or mouse button. Changes apply and save immediately."),Vector2(28,142),Vector2(824,45),16,MineStyle.MUTED)
	var labels := [
		_ex_text("点地移动","Click to move"), _ex_text("普通攻击","Basic attack"),
		_ex_text("技能一 · Q","Skill 1 · Q"), _ex_text("技能二 · W","Skill 2 · W"),
		_ex_text("技能三 · E","Skill 3 · E"), _ex_text("技能四 · R","Skill 4 · R"),
		_ex_text("闪避","Dodge"), _ex_text("交互","Interact"),
		_ex_text("向上移动","Move up"), _ex_text("向下移动","Move down"),
		_ex_text("向左移动","Move left"), _ex_text("向右移动","Move right")]
	for index in range(Controls.EDITABLE_ACTIONS.size()):
		var action: String = Controls.EDITABLE_ACTIONS[index]
		var origin := Vector2(28 + (index % 2) * 422, 192 + floori(float(index) / 2.0) * 50)
		MineStyle.literal(panel,str(labels[index]),origin + Vector2(0,7),Vector2(156,31),17)
		var binding := MineStyle.button(panel,"",origin + Vector2(158,0),Vector2(244,42),func(): _begin_control_binding(action))
		binding.name = "Bind_" + action
		binding.text = Controls.secondary_label(action, Game.profile.settings.get("controls", {}), Words.locale)
		binding.tooltip_text = _ex_text("点击更换主按键；Esc 取消。普攻备用 A 会在分配给其他操作时自动停用。","Click to change the primary binding; Esc cancels. The A attack alias is disabled when assigned to another action.")
	binding_feedback = MineStyle.literal(panel,_ex_text("职业被动自动触发。Tab 技能详情 · M 路线 · B 背包 · Esc 暂停。","Passives trigger automatically. Tab details · M map · B backpack · Esc pause."),Vector2(28,507),Vector2(824,44),15,MineStyle.MUTED)
	var reset := MineStyle.button(panel,"",Vector2(28,566),Vector2(264,48),_reset_control_bindings)
	reset.text = _ex_text("恢复默认按键","RESET CONTROLS")
	MineStyle.button(panel,"BACK",Vector2(612,566),Vector2(240,48),_pop_modal)

func _begin_control_binding(action: String) -> void:
	pending_binding_action = action
	var panel := _push_modal("",Vector2(646,244))
	panel.name = "ControlBindingCapture"
	MineStyle.literal(panel,_ex_text("按下新的键或鼠标按钮","PRESS A KEY OR MOUSE BUTTON"),Vector2(28,32),Vector2(590,42),25,MineStyle.AMBER)
	MineStyle.literal(panel,_ex_text("当前按键：","Current binding: ") + _control_label(action),Vector2(28,92),Vector2(590,36),20)
	MineStyle.literal(panel,_ex_text("单个键或鼠标左 / 右 / 中 / 侧键。Esc 取消。\n重复按键会提示冲突，请先调整已占用的操作。","Use one key, or left / right / middle / side mouse buttons. Esc cancels.\nConflicting bindings are rejected; change the existing action first."),Vector2(28,147),Vector2(590,67),16,MineStyle.MUTED)

func _capture_control_binding(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.pressed: return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		_pop_modal()
		return
	var binding := Controls.from_event(event)
	if binding.is_empty(): return
	var action := pending_binding_action
	var occupied := Controls.conflict(action, binding, Game.profile.settings.get("controls", {}))
	if not occupied.is_empty():
		_pop_modal()
		if is_instance_valid(binding_feedback):
			binding_feedback.text = _ex_text("按键已用于「%s」，请先修改该操作。","This binding is used by %s. Change that action first.") % _control_action_name(occupied)
			binding_feedback.add_theme_color_override("font_color", MineStyle.RED)
		return
	if not Game.set_control_binding(action, binding):
		_pop_modal()
		if not Game.last_error.is_empty(): _show_save_error()
		return
	_pop_modal()
	_switch_settings_tab("controls")

func _control_action_name(action: String) -> String:
	var names := {
		"click_move": ["点地移动", "Click to move"], "attack": ["普通攻击", "Basic attack"],
		"skill_q": ["技能一", "Skill 1"], "skill_secondary": ["技能二", "Skill 2"], "skill_f": ["技能三", "Skill 3"], "skill_ultimate": ["技能四", "Skill 4"],
		"dash": ["闪避", "Dodge"], "interact": ["交互", "Interact"],
		"move_up": ["向上移动", "Move up"], "move_down": ["向下移动", "Move down"], "move_left": ["向左移动", "Move left"], "move_right": ["向右移动", "Move right"],
		"relic_details": ["技能详情", "Skill details"], "expedition_map": ["路线", "Map"], "backpack": ["背包", "Backpack"], "pause": ["暂停", "Pause"]}
	return str(names.get(action, [action, action])[0 if Words.locale == "zh_CN" else 1])

func _reset_control_bindings() -> void:
	Game.set_setting("controls", {})
	if not Game.last_error.is_empty():
		_show_save_error()
		return
	_switch_settings_tab("controls")

func _toggle_combat_setting(key: String) -> void:
	Game.set_setting(key, not bool(Game.profile.get("settings", {}).get(key, key == "enemy_skill_paths")))
	if not Game.last_error.is_empty():
		_show_save_error()
		return
	_pop_modal()
	show_settings()

func _commit_audio_sliders() -> void:
	for key: String in audio_sliders:
		var slider: Variant = audio_sliders[key]
		if is_instance_valid(slider) and slider.is_visible_in_tree() and not is_equal_approx(float(Game.profile.get("settings",{}).get(key,-1)),float(slider.value)):
			Game.set_setting(key,float(slider.value))
	audio_sliders.clear()

func _process(delta: float) -> void:
	music_tick -= delta
	if music_tick > 0.0 or not is_instance_valid(music): return
	music_tick = 0.3
	var context := "camp"
	if route == "run" and is_instance_valid(room):
		context = "explore"
		if room.has_method("_living_enemy_count") and room._living_enemy_count() > 0: context = "combat"
		if not room.objective_complete and str(room.expedition_context.get("role","")) == "boss": context = "boss"
	music.set_context(context)

func _toggle_language() -> void:
	Game.set_setting("language","en" if Words.locale == "zh_CN" else "zh_CN")
	if not Game.last_error.is_empty():
		_show_save_error()
		return
	Words.set_locale(Game.profile.get("settings",{}).get("language","zh_CN"))
	# Rebuild the visible page and modal stack so no stale language survives.
	var old_route := route
	_clear_modals()
	if old_route == "camp":
		show_camp()
	elif old_route.begins_with("workshop_"):
		show_workshop(old_route.trim_prefix("workshop_"))
	elif old_route == "menu":
		show_menu()
	elif old_route == "result":
		show_result(Game.last_result)
	elif old_route == "room_error":
		_show_room_load_error()
	else:
		_build_hud()
		show_pause()
	show_settings()

func _toggle_fullscreen() -> void:
	Game.set_setting("fullscreen",not Game.profile.get("settings",{}).get("fullscreen",false))
	if not Game.last_error.is_empty():
		_show_save_error()
		return
	_apply_display()
	_pop_modal()
	show_settings()

func _apply_display() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if Game.profile.get("settings",{}).get("fullscreen",false) else DisplayServer.WINDOW_MODE_WINDOWED)

func _toggle_fx() -> void:
	Game.set_setting("reduced_fx",not Game.profile.get("settings",{}).get("reduced_fx",false))
	if not Game.last_error.is_empty():
		_show_save_error()
		return
	_pop_modal()
	show_settings()

func _toggle_camera_shake() -> void:
	Game.set_setting("camera_shake",not Game.profile.get("settings",{}).get("camera_shake",false))
	if not Game.last_error.is_empty():
		_show_save_error()
		return
	_pop_modal()
	show_settings()

func _show_save_error() -> void:
	var panel := _push_modal("ERROR_TITLE",Vector2(770,355))
	MineStyle.label(panel,"SAVE_ERROR",Vector2(28,77),Vector2(714,161),18,MineStyle.RED,{"error":Words.text(Game.last_error)})
	if Game.run != null and not pending_outcome.is_empty():
		modals[-1]["required"] = true
		MineStyle.button(panel,"RETRY",Vector2(28,269),Vector2(714,52),func():
			_clear_modals()
			_settle(pending_outcome)).grab_focus()
	else:
		MineStyle.button(panel,"BACK",Vector2(499,269),Vector2(243,52),_pop_modal).grab_focus()

func _push_modal(title: String, dimensions: Vector2) -> Panel:
	var previous_focus := get_viewport().gui_get_focus_owner()
	_set_screen_focus(false)
	if not modals.is_empty():
		modals[-1].node.visible = false
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.23,0.17,0.27,0.43)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var panel := MineStyle.panel(overlay,Vector2.ZERO,dimensions)
	_fit_modal(panel,dimensions)
	overlay.resized.connect(func(): _fit_modal(panel,dimensions))
	MineStyle.label(panel,title,Vector2(28,20),Vector2(dimensions.x-56,47),30,MineStyle.AMBER)
	modals.append({"node":overlay,"focus":previous_focus})
	_sync_pause()
	return panel

func _fit_modal(panel: Control, dimensions: Vector2) -> void:
	if not is_instance_valid(panel): return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var fit: float = minf(1.0,minf((viewport_size.x-32.0)/dimensions.x,(viewport_size.y-32.0)/dimensions.y))
	panel.scale = Vector2.ONE * maxf(.4,fit)
	panel.position = (viewport_size-dimensions*panel.scale)*.5

func _pop_modal() -> void:
	if modals.is_empty():
		return
	if modals[-1].get("required",false):
		return
	pending_binding_action = ""
	_commit_audio_sliders()
	var removed: Dictionary = modals.pop_back()
	removed.node.queue_free()
	if not modals.is_empty():
		modals[-1].node.visible = true
	else:
		_set_screen_focus(true)
	if is_instance_valid(removed.focus) and removed.focus.is_visible_in_tree():
		removed.focus.grab_focus()
	_sync_pause()

func _clear_modals() -> void:
	pending_binding_action = ""
	_commit_audio_sliders()
	for entry in modals:
		entry.node.queue_free()
	modals.clear()
	_set_screen_focus(true)
	_sync_pause()

func _set_screen_focus(enabled: bool) -> void:
	if is_instance_valid(screen):
		for control in screen.find_children("*","BaseButton",true,false):
			control.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if is_instance_valid(hud):
		hud.set_interaction_enabled(enabled)

func _sync_pause() -> void:
	var paused := Game.run != null and not modals.is_empty()
	get_tree().paused = paused
	if is_instance_valid(room):
		room.set_input_blocked(paused)

func _input(event: InputEvent) -> void:
	if not pending_binding_action.is_empty():
		_capture_control_binding(event)
		return
	if event.is_action_pressed("expedition_map") and route == "run" and modals.is_empty() and expedition != null and expedition.active():
		get_viewport().set_input_as_handled()
		show_expedition(false)
		return
	if event.is_action_pressed("backpack") and route == "run" and modals.is_empty():
		get_viewport().set_input_as_handled()
		show_backpack()
		return
	# Handle Tab before GUI focus traversal: combat details owns a paused modal.
	if event.is_action_pressed("relic_details") and route == "run" and modals.is_empty():
		get_viewport().set_input_as_handled()
		show_combat_details()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not modals.is_empty():
			_pop_modal()
		elif route == "run":
			show_pause()
		elif route.begins_with("workshop_"):
			show_camp()
		elif route in ["camp","result","demo_select"]:
			show_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()

func _quit() -> void:
	if room_start_failed and Game.run != null:
		if expedition != null and expedition.active():
			get_tree().quit()
		return
	if not modals.is_empty() and modals[-1].get("required",false):
		return
	if Game.run != null:
		if expedition != null and expedition.active():
			show_expedition_exit()
		else:
			show_abandon(true)
	else:
		get_tree().quit()
