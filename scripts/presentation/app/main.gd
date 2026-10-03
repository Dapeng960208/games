extends Node

const DifficultyProfiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const ExpeditionScript = preload("res://scripts/app/expedition_controller.gd")
const ExpeditionPanel = preload("res://scripts/presentation/screens/expedition_panel.gd")
const FieldEquipmentPanel = preload("res://scripts/presentation/equipment/field_equipment_panel.gd")
const LootPickupPanel = preload("res://scripts/presentation/equipment/loot_pickup_panel.gd")
var loot_flow_active := false
const RoutePlanner = preload("res://scripts/domain/world/route_generator.gd")
const CampNavTile = preload("res://scripts/presentation/components/illustrated_nav_tile.gd")
const CampArtwork = preload("res://scripts/infrastructure/assets/storybook_art.gd")
const Controls = preload("res://scripts/infrastructure/input/control_bindings.gd")
const BackpackPanel = preload("res://scripts/presentation/equipment/backpack_panel.gd")
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
var _shutdown_started := false
var room_start_failed := false
var selected_difficulty: int = 0
var selected_wish_slot: String = ""
var selected_biome := "B01"
var expedition: RefCounted
var expedition_status: Label
var expedition_action_pending := false
var music: Node
var music_tick := 0.0
var audio_sliders: Dictionary = {}
var demo_hero := "CH01"
var demo_branches := {"q":"", "ultimate":""}
var settings_tab := "general"
var pending_binding_action := ""
var binding_feedback: Label

const HERO_LOOPS := {
	"CH01":["破岩斧卫","贴身积累破势，重击打穿敌阵。","普攻 / Q 蓄势 → W 破阵","BREAKER","Build pressure up close, then break the line."],
	"CH02":["游走枪手","连续命中标记弱点，精确射击收割。","两次普攻 → 第三击 / 技能破绽","GUNNER","Mark a weak point with two hits. Consume it with a shot or skill."],
	"CH03":["共鸣术士","Q瞄准输出，W法晶自动攻击，E近身冰霜，R范围爆发。四技独立可用；交替施法额外回蓝。","四技独立：Q瞄准 / W法晶 / E冰霜 / R爆发；交替施法额外回蓝","RESONATOR","Use skills independently: Q aim, W auto-firing crystal, E close frost, R area burst. Alternating casts gives bonus mana."]
}

var _profiles_service = preload("res://scripts/presentation/app/services/profiles_service.gd").new(self)
var _camp_service = preload("res://scripts/presentation/app/services/camp_service.gd").new(self)
var _expedition_service = preload("res://scripts/presentation/app/services/expedition_service.gd").new(self)
var _settings_service = preload("res://scripts/presentation/app/services/settings_service.gd").new(self)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	preload("res://scripts/infrastructure/assets/equipment_art.gd").prefetch_owned(Game.profile.get("equipment",{}))
	get_tree().auto_accept_quit = false
	_install_inputs()
	Words.initialize(Game.profile.get("settings",{}).get("language","zh_CN"))
	_apply_display()
	backdrop = Node2D.new()
	backdrop.set_script(load(AssetCatalog.resolve("res://scripts/presentation/screens/menu_backdrop.gd")))
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
	ui.theme = GameStyle.make_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	Game.run_started.connect(_on_run_started)
	Game.run_finished.connect(_on_run_finished)
	Game.settlement_failed.connect(_on_settlement_failed)
	if ResourceLoader.exists(AssetCatalog.resolve("res://scripts/infrastructure/audio/music_director.gd")):
		music = load(AssetCatalog.resolve("res://scripts/infrastructure/audio/music_director.gd")).new()
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
	if next_route.begins_with("workshop_") or next_route == "codex":
		var footer := ColorRect.new()
		footer.position = Vector2(0,690)
		footer.size = Vector2(1280,30)
		footer.color = Color(GameStyle.PANEL,0.96)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(footer)
	if next_route in ["result","room_error"]: _screen_shade(0.68)

func show_menu() -> void:
	_new_screen("menu")
	_screen_shade(0.03)
	var title_page := GameStyle.panel(screen,Vector2(36,24),Vector2(430,662))
	title_page.name = "MenuTitlePage"
	var emblem := TextureRect.new()
	if ResourceLoader.exists(AssetCatalog.resolve("asset://ui/refactor_v1/decor/compass_emblem.png")):
		emblem.texture = load(AssetCatalog.resolve("asset://ui/refactor_v1/decor/compass_emblem.png"))
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.position = Vector2(170,12)
	emblem.size = Vector2(90,90)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_page.add_child(emblem)
	GameStyle.literal(title_page,"ABYSS SALVAGER",Vector2(35,111),Vector2(360,25),14,GameStyle.AMBER).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(title_page,"TITLE",Vector2(20,146),Vector2(390,70),40 if Words.locale == "zh_CN" else 35).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.literal(title_page,_ex_text("借敌之力，重写战场。","TURN FIRE INTO YOUR WEAPON"),Vector2(25,221),Vector2(380,32),18,GameStyle.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.divider(title_page,Vector2(44,270),342)
	var cont := GameStyle.button(title_page,"CONTINUE",Vector2(30,294),Vector2(370,56),_continue_game)
	cont.name = "ContinueJourney"
	cont.text = _continue_button_text()
	cont.disabled = not Game.has_profile
	GameStyle.primary(cont)
	var trial := GameStyle.button(title_page,"",Vector2(30,364),Vector2(370,50),show_demo_select)
	trial.name = "FullSkillDemo"
	trial.text = _ex_text("完整技能试玩", "FULL-SKILL TRIAL")
	trial.disabled = Game.run != null
	var profile_button := GameStyle.button(title_page,"",Vector2(30,428),Vector2(370,50),show_profile)
	profile_button.name = "OpenProfile"
	profile_button.text = _ex_text("存档与英雄档案", "SAVE & HERO PROFILE")
	GameStyle.button(title_page,"NEW_GAME",Vector2(30,492),Vector2(370,44),_request_new_profile)
	GameStyle.button(title_page,"SETTINGS",Vector2(30,554),Vector2(222,44),show_settings)
	GameStyle.button(title_page,"QUIT",Vector2(266,554),Vector2(134,44),_quit)
	GameStyle.literal(title_page,_ex_text("Enter 确认  ·  Esc 返回", "ENTER CONFIRM  ·  ESC BACK"),Vector2(30,617),Vector2(370,24),12,GameStyle.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hero_id: String = Game.profile.get("selected_hero","CH01")
	GameStyle.hero_portrait(screen,hero_id,Vector2(692,114),Vector2(440,452)).name = "MenuHeroIllustration"
	var hero_card := GameStyle.panel(screen,Vector2(692,574),Vector2(440,94))
	GameStyle.literal(hero_card,GameStyle.content_text(ContentRegistry.hero(hero_id),"name"),Vector2(24,12),Vector2(306,34),26)
	GameStyle.literal(hero_card,"Lv."+str(Game.hero_level(hero_id)),Vector2(336,16),Vector2(80,30),21,GameStyle.CYAN)
	GameStyle.literal(hero_card,_ex_text("三个职业，三种连招。开启你的远征。","THREE HEROES. THREE STYLES. YOUR JOURNEY."),Vector2(24,56),Vector2(392,22),12,GameStyle.MUTED)
	_show_warning(screen,Vector2(666,690),Vector2(566,20))
	(cont if Game.has_profile else trial).grab_focus()

func show_profile() -> void:
	_profiles_service.show_profile()

func _request_delete_profile() -> void:
	_profiles_service._request_delete_profile()

func show_recycle_bin() -> void:
	_profiles_service.show_recycle_bin()

func _recycle_remaining(entry: Dictionary) -> String:
	return _profiles_service._recycle_remaining(entry)

func _request_restore_profile(entry_id: String) -> void:
	_profiles_service._request_restore_profile(entry_id)

func show_codex() -> void:
	_new_screen("codex")
	_screen_shade(0.12)
	var codex := load(AssetCatalog.resolve("res://scripts/presentation/screens/monster_codex.gd")).new() as Control
	codex.name = "MonsterCodex"
	screen.add_child(codex)
	codex.configure(show_camp)

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
	GameStyle.literal(screen,_ex_text("引雷试炼","CIRCUIT TRIAL"),Vector2(56,48),Vector2(750,62),40)
	GameStyle.literal(screen,_ex_text("选择你的战斗方式 · Lv.8 完整技能 · 独立试玩","CHOOSE YOUR COMBAT LOOP · LEVEL 8 · SEPARATE TRIAL"),Vector2(58,111),Vector2(1120,35),18,GameStyle.MUTED)
	for index in range(3):
		var id: String = ["CH01","CH02","CH03"][index]
		var hero: Dictionary = ContentRegistry.hero(id)
		var words: Array = HERO_LOOPS[id]
		var accent: Color = GameStyle.resource_color(str(hero.get("resource_type","rage")))
		var card := GameStyle.panel(screen,Vector2(56+index*396,166),Vector2(376,462))
		card.add_theme_stylebox_override("panel",GameStyle.box(GameStyle.PANEL,accent.lightened(0.28)))
		GameStyle.literal(card,"0"+str(index+1)+" / "+str(words[3]),Vector2(22,16),Vector2(332,28),15,accent)
		GameStyle.hero_portrait(card,id,Vector2(81,49),Vector2(215,218))
		GameStyle.literal(card,GameStyle.content_text(hero,"name")+" · "+_ex_text(str(words[0]),str(words[3])),Vector2(22,266),Vector2(332,38),24)
		GameStyle.literal(card,_ex_text(str(words[1]),str(words[4])),Vector2(22,314),Vector2(332,58),13 if id == "CH03" else 17,GameStyle.MUTED)
		var choose := GameStyle.button(card,"",Vector2(22,369),Vector2(332,44),func(): _start_demo(id))
		choose.name = "Demo_"+id
		choose.text = _ex_text("Lv.8 · 完整技能试玩","LV.8 · FULL-SKILL TRIAL")
		GameStyle.primary(choose,accent)
		choose.disabled = Game.run != null
		if id == demo_hero: choose.grab_focus()
		var branches := GameStyle.button(card,"",Vector2(22,416),Vector2(332,44),func(): _show_demo_branches(id))
		branches.name = "DemoBranches_"+id
		branches.text = _ex_text("Lv.20 · 分支预览与试玩", "LV.20 · PREVIEW BRANCHES")
		branches.add_theme_font_size_override("font_size",15)
		branches.disabled = Game.run != null
	GameStyle.literal(screen,_current_control_summary(),Vector2(56,622),Vector2(945, 70),15,GameStyle.CYAN)
	GameStyle.button(screen,"BACK",Vector2(1028,650),Vector2(196,48),show_menu)

func _start_demo(hero_id: String, preview_branches: bool = false) -> void:
	demo_hero = hero_id
	if not Game.start_demo(hero_id,selected_difficulty,demo_branches if preview_branches else {},preview_branches): _show_save_error()

func _show_demo_branches(hero_id: String, reset: bool = true) -> void:
	if reset: demo_branches = {"q":"", "ultimate":""}
	demo_hero = hero_id
	var panel := _push_modal("",Vector2(1048,650))
	panel.name = "DemoBranchPreview"
	GameStyle.literal(panel,_ex_text("分支预览 · 独立 Lv.20 试玩", "BRANCH PREVIEW · SEPARATE LEVEL-20 TRIAL"),Vector2(28,23),Vector2(992,45),27,GameStyle.AMBER)
	GameStyle.literal(panel,_ex_text("现在即可尝试另一种打法。不会解锁正式存档；正式分支仍在 18 / 20 级开放。", "Try another play style now. Your save stays unchanged; permanent branches still unlock at levels 18 / 20."),Vector2(28,80),Vector2(992,49),17,GameStyle.MUTED)
	var hero: Dictionary = ContentRegistry.hero(hero_id)
	for row: int in 2:
		var slot := "q" if row == 0 else "ultimate"
		var action := "skill_q" if row == 0 else "skill_ultimate"
		var gate := "18" if row == 0 else "20"
		GameStyle.literal(panel,_control_action_name(action)+" · "+_control_label(action),Vector2(28,137+row*204),Vector2(684,31),21,GameStyle.CYAN)
		var standard := GameStyle.button(panel,"",Vector2(770,135+row*204),Vector2(250,32),func(): _select_demo_branch(hero_id,slot,""))
		standard.text = _ex_text("标准技能", "STANDARD SKILL")
		standard.name = "DemoBranch_"+slot+"_standard"
		if str(demo_branches[slot]).is_empty(): GameStyle.selected(standard)
		for index: int in 2:
			var choice := "A" if index == 0 else "B"
			var info: Dictionary = hero.branches[gate][choice]
			var card := GameStyle.button(panel,"",Vector2(28+index*504,176+row*204),Vector2(488,155),func(): _select_demo_branch(hero_id,slot,choice))
			card.name = "DemoBranch_"+slot+"_"+choice
			if demo_branches[slot] == choice: GameStyle.selected(card)
			GameStyle.literal(card,choice+" · "+GameStyle.content_text(info,"name"),Vector2(17,9),Vector2(454,30),20,GameStyle.AMBER)
			var detail := GameStyle.literal(card,_current_skill_text(GameStyle.content_text(info,"description")),Vector2(17,43),Vector2(454,105),15)
			detail.tooltip_text = detail.text
	var begin := GameStyle.button(panel,"",Vector2(628,580),Vector2(392,46),func(): _start_demo(hero_id,true))
	begin.name = "StartBranchTrial"
	begin.text = _ex_text("以所选分支进入试玩", "TRY SELECTED BRANCHES")
	GameStyle.primary(begin)
	GameStyle.button(panel,"BACK",Vector2(28,580),Vector2(228,46),_pop_modal).grab_focus()

func _select_demo_branch(hero_id: String, slot: String, choice: String) -> void:
	demo_branches[slot] = choice
	_pop_modal()
	_show_demo_branches(hero_id,false)

func _current_skill_text(value: String) -> String:
	var matcher := RegEx.new()
	matcher.compile("(?<![A-Za-z])[QWER](?![A-Za-z])|空格")
	var actions := {"Q":"skill_q", "W":"skill_secondary", "E":"skill_f", "R":"skill_ultimate", "空格":"dash"}
	var matches := matcher.search_all(value)
	for index: int in range(matches.size()-1,-1,-1):
		var match_item: RegExMatch = matches[index]
		value = value.substr(0,match_item.get_start())+_control_label(actions[match_item.get_string()])+value.substr(match_item.get_end())
	return value

func _current_control_summary() -> String:
	var skills: Array[String] = []
	for action: String in ["skill_q","skill_secondary","skill_f","skill_ultimate"]: skills.append(_control_label(action))
	var attack := Controls.secondary_label("attack",Game.profile.settings.get("controls",{}),Words.locale)
	return _ex_text("移动 %s · 普攻 %s · 技能 %s\n闪避 %s · 交互 %s · 路线 %s · 背包 %s · 详情 %s · 暂停 %s", "Move %s · Attack %s · Skills %s\nDodge %s · Interact %s · Map %s · Backpack %s · Details %s · Pause %s") % [_control_label("click_move"),attack," / ".join(skills),_control_label("dash"),_control_label("interact"),_control_label("expedition_map"),_control_label("backpack"),_control_label("relic_details"),_control_label("pause")]


func _has_resumable_expedition() -> bool:
	return Game.run != null and not Game.expedition_snapshot().is_empty()

func _continue_button_text() -> String:
	return _ex_text("继续远征","Continue expedition") if _has_resumable_expedition() else _ex_text("返回营地","Return to camp")

func _continue_game() -> void:
	if _has_resumable_expedition():
		_on_run_started()
	else:
		show_camp()

func show_camp() -> void:
	_camp_service.show_camp()

func _camp_navigation(parent: Node, at: Vector2, extent: Vector2, title: String, subtitle: String, icon_index: int, accent: Color, action: Callable, prominent: bool = false) -> Button:
	return _camp_service._camp_navigation(parent, at, extent, title, subtitle, icon_index, accent, action, prominent)

func _camp_ui_icon(parent: Node, key: String, at: Vector2, extent: Vector2) -> Control:
	return _camp_service._camp_ui_icon(parent, key, at, extent)

func _departure_enemy_count(difficulty: int) -> int:
	return _camp_service._departure_enemy_count(difficulty)

func _update_departure_difficulty_hint() -> void:
	_camp_service._update_departure_difficulty_hint()

func _ex_text(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _build_biome_selector() -> void:
	_camp_service._build_biome_selector()

func _build_expedition_status() -> void:
	_expedition_service._build_expedition_status()

func _update_expedition_status() -> void:
	_expedition_service._update_expedition_status()

func _expedition_node_count() -> int:
	return _expedition_service._expedition_node_count()

func _on_expedition_room_completed() -> void:
	_expedition_service._on_expedition_room_completed()

func _show_loot_pickup() -> void:
	_expedition_service._show_loot_pickup()

func show_expedition(at_exit: bool = false) -> void:
	_expedition_service.show_expedition(at_exit)

func _advance_expedition(room_id: String) -> void:
	_expedition_service._advance_expedition(room_id)

func _show_expedition_error(message: String, retry: Callable, preserve_action: bool = false) -> void:
	_expedition_service._show_expedition_error(message, retry, preserve_action)

func _show_pending_expedition_offer() -> void:
	_expedition_service._show_pending_expedition_offer()

func _show_field_equipment(offer: Dictionary) -> void:
	_expedition_service._show_field_equipment(offer)

func _choose_field_equipment(drop_id: String, decision: String, checkpoint_id: String) -> void:
	_expedition_service._choose_field_equipment(drop_id, decision, checkpoint_id)

func show_expedition_service() -> void:
	_expedition_service.show_expedition_service()

func _relic_display(id: String, rank: int = 1) -> Dictionary:
	var legacy: String = {"RL01":"split", "RL02":"ember", "RL03":"arc"}.get(id, "")
	if ResourceLoader.exists(AssetCatalog.resolve("res://scripts/domain/combat/class_relics.gd")):
		var biome: String = load(AssetCatalog.resolve("res://scripts/domain/combat/race_relics.gd")).biome_id(room)
		return load(AssetCatalog.resolve("res://scripts/domain/combat/class_relics.gd")).display(Game.run.hero_id if Game.run != null else str(Game.profile.get("selected_hero","CH01")),id,rank,biome,Game.run.ruleset_version() if Game.run != null else int(Game.profile.get("ruleset_version",1)))
	if not legacy.is_empty():
		return {"name":Words.text("RELIC_"+legacy.to_upper()+"_NAME"),"description":Words.text("RELIC_"+legacy.to_upper()+"_DESC"),"art":legacy}
	return {"name":id,"description":"","art":""}

func _relic_artwork(parent: Node, info: Dictionary, at: Vector2, extent: Vector2, fallback: String = "") -> void:
	var painted: Texture2D
	if info.get("texture") is Texture2D:
		painted = info.texture
	elif str(info.get("art","")).begins_with("res://"):
		painted = load(AssetCatalog.resolve(str(info.art))) as Texture2D
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
		if not art_key.is_empty(): GameArtwork.relic(parent,art_key,at,extent)

func _show_expedition_relic(offer: Dictionary) -> void:
	_expedition_service._show_expedition_relic(offer)

func _amount(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value,round(value)) else str(snappedf(value,0.1))

func _request_relic_skip(offer_id: String, force_review: bool = false) -> void:
	if Game.run == null: return
	var gain := minf(maxf(0.0,Game.run.max_hp-Game.run.hp),Game.run.max_hp*0.06)
	if gain > 0.0 and not force_review:
		_choose_expedition_relic(offer_id,"skip")
		return
	var panel := _push_modal("",Vector2(690,320))
	panel.name = "ConfirmRelicSkip"
	GameStyle.literal(panel,_ex_text("确认放弃这次遗物？", "GIVE UP THIS RELIC OPPORTUNITY?"),Vector2(28,24),Vector2(634,45),25,GameStyle.AMBER)
	GameStyle.literal(panel,_ex_text("生命已满，本次跳过不会恢复生命。你仍可刻意跳过，但这次遗物机会会永久消耗。", "Health is full, so skipping restores no health. You may deliberately skip, but this relic opportunity will be consumed permanently.") if gain <= 0.0 else _ex_text("当前没有可选遗物。跳过将恢复 %s 生命并消耗本次机会。", "No relics are available. Skipping restores %s HP and consumes this opportunity.") % _amount(gain),Vector2(28,93),Vector2(634,111),19)
	var actions := GameStyle.action_pair(panel,"","BACK",234,func(): _choose_expedition_relic(offer_id,"skip"),_pop_modal)
	var confirm: Button = actions[0]
	confirm.name = "ConfirmZeroBenefitSkip"
	confirm.text = _ex_text("仍然跳过", "SKIP ANYWAY")
	actions[1].grab_focus()

func _choose_expedition_relic(offer_id: String, choice_id: String) -> void:
	_expedition_service._choose_expedition_relic(offer_id, choice_id)

func _show_expedition_supply() -> void:
	_expedition_service._show_expedition_supply()

func _supply_disabled_reason(offer: Dictionary, healing_purchased: bool) -> String:
	var product := str(offer.get("product_id",""))
	if not str(offer.get("decision","")).is_empty(): return _ex_text("已购买", "Purchased")
	if product in ["heal_small","heal_large"]:
		if healing_purchased: return _ex_text("已选择另一治疗 · 本次不能再买", "Other heal chosen · unavailable this rest")
		if Game.run.hp >= Game.run.max_hp: return _ex_text("生命已满 · 无恢复收益", "Full health · no healing benefit")
	if Game.run.gold < int(offer.get("price",0)): return _ex_text("金币不足 · 需要 %d", "Not enough gold · needs %d") % int(offer.get("price",0))
	var buffs: Dictionary = Game.run.expedition.get("temporary_buffs",{})
	if product == "shield" and buffs.has("pending_supply_shield"): return _ex_text("已备有下一房护盾", "Next-room shield already prepared")
	if product == "amplify" and buffs.has("amplify"): return _ex_text("攻击增幅仍在生效", "Attack boost is already active")
	if product == "scan":
		var missing := false
		for index: int in RoutePlanner.scan_indices(Game.run.expedition.route):
			if index not in Game.run.expedition.scan_nodes: missing = true
		if not missing: return _ex_text("可勘测节点已全部揭示", "All surveyable rooms already revealed")
	return ""

func _prepare_safe_resources() -> void:
	if expedition_action_pending or not is_instance_valid(room): return
	var checkpoint := str(expedition.snapshot().get("checkpoint_id",""))
	expedition_action_pending = true
	var success: bool = Game.prepare_safe_resources(room.expedition_runtime_snapshot(),checkpoint)
	expedition_action_pending = false
	if not success:
		_show_expedition_error(Words.text(Game.last_error),_prepare_safe_resources)
		return
	if not room.restore_expedition_runtime(expedition.snapshot().get("runtime",{})):
		_show_expedition_error(_ex_text("整备已保存，但角色状态恢复失败。重试不会花费金币。", "Preparation is saved, but character state could not be restored. Retry will not spend gold."),_prepare_safe_resources)
		return
	_clear_modals()
	_show_expedition_supply()

func _buy_expedition_supply(offer_id: String) -> void:
	_expedition_service._buy_expedition_supply(offer_id)

func _next_skill_level(level: int) -> String:
	for gate in [2,4,6,8,10,12,14,16,18,20]:
		if level < gate:
			return str(gate)
	return Words.text("LEVEL_MAX")

func show_workshop(page: String = "heroes") -> void:
	_new_screen("workshop_"+page)
	_screen_shade(0.12)
	var workshop := Control.new()
	workshop.name = "Workshop"
	workshop.set_script(load(AssetCatalog.resolve("res://scripts/presentation/equipment/workshop_panel.gd")))
	workshop.app = self
	workshop.mode = page
	workshop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(workshop)
	_show_warning(screen,Vector2(840,695),Vector2(408,20))

func _show_warning(parent: Node, at: Vector2, extent: Vector2) -> void:
	if not Game.storage_warning.is_empty():
		var message := Words.text(Game.storage_warning)
		var backing := GameStyle.panel(parent,at,extent)
		backing.name = "StorageWarningBacking"
		backing.add_theme_stylebox_override("panel",GameStyle.box(GameStyle.PAPER_LIGHT,GameStyle.AMBER,1))
		var notice := LinkButton.new()
		notice.name = "StorageWarningNotice"
		notice.position = Vector2(8,0)
		notice.size = extent-Vector2(16,0)
		notice.text = _ex_text("档案提示 · 查看详情","Save notice · View details")
		notice.tooltip_text = message
		notice.add_theme_font_size_override("font_size",13)
		notice.add_theme_color_override("font_color",GameStyle.INK)
		backing.add_child(notice)
		notice.pressed.connect(func():
			var modal := _push_modal(_ex_text("档案提示","Save notice"),Vector2(760,330))
			modal.name = "StorageWarningDetails"
			var detail := GameStyle.literal(modal,message,Vector2(28,92),Vector2(704,144),17,GameStyle.INK)
			detail.name = "StorageWarningFullText"
			GameStyle.button(modal,"BACK",Vector2(470,258),Vector2(262,44),_pop_modal))
		return
	var capacity: Dictionary = Game.storage_capacity()
	if capacity.is_empty(): return
	var remaining_bytes := int(capacity.get("remaining_bytes",0))
	var remaining_receipts := int(capacity.get("remaining_transactions",0))
	var v2: bool = int(Game.profile.get("ruleset_version",1)) == 2
	var tight := (not v2 and remaining_receipts <= 64) or remaining_bytes < 262144
	if not tight: return
	var note := GameStyle.literal(parent,(_ex_text("存档空间偏低：", "Low save space: ") if tight else _ex_text("存档余量：", "Save room: "))+_ex_text("%s KiB · %d 条收据", "%s KiB · %d receipts") % [_amount(remaining_bytes/1024.0),remaining_receipts],at,extent,13,GameStyle.RED if tight else GameStyle.MUTED)
	if v2: note.text = (_ex_text("存档空间偏低：", "Low save space: ") if tight else _ex_text("存档余量：", "Save room: "))+_amount(remaining_bytes/1024.0)+" KiB"
	note.name = "StorageCapacityHint"
	note.tooltip_text = _ex_text("当前剩余 %d 字节与 %d 条交易收据。存档写入前检查容量，空间不足时保留旧档并提示。", "%d bytes and %d transaction receipts remain. Capacity is checked before writes; insufficient space preserves the previous save and reports an error.") % [remaining_bytes,remaining_receipts]
	if v2: note.tooltip_text = _ex_text("剩余 %d 字节。新实例与交易不按模板数量截断；空间不足时整笔拒绝，不删除旧装备或收据。", "%d bytes remain. New instances and transactions are not capped by template count; a full save rejects the whole operation without deleting equipment or receipts.") % remaining_bytes

func _request_new_profile() -> void:
	if not Game.has_profile:
		_create_profile()
		return
	var panel := _push_modal("NEW_CONFIRM_TITLE",Vector2(760,390))
	GameStyle.label(panel,"NEW_CONFIRM_NOTE",Vector2(28,83),Vector2(704,192),18)
	GameStyle.action_pair(panel,"CONFIRM_NEW","CANCEL",302,_create_profile,_pop_modal)[1].grab_focus()

func _create_profile() -> void:
	if Game.new_profile():
		Words.set_locale(Game.profile.get("settings",{}).get("language","zh_CN"))
		show_camp()
	else:
		_show_save_error()

func _start_run() -> void:
	if int(Game.profile.get("ruleset_version",1)) == 2:
		if not modals.is_empty(): return
		var panel: Panel = _push_modal("",Vector2(640,350))
		panel.name = "DepartureWishDialog"
		GameStyle.literal(panel,_ex_text("本次远征 · 愿望部位","THIS EXPEDITION · WISH SLOT"),Vector2(24,21),Vector2(592,43),24,GameStyle.AMBER)
		GameStyle.literal(panel,_ex_text("该部位在本族合法池可用时有50%机会选中；不指定则在合法部位均分。结果随本次远征冻结。","When available in this faction's pool, the wish slot gets a 50% selection chance. None distributes evenly over legal slots. This choice is frozen for the trip."),Vector2(24,77),Vector2(592,96),16,GameStyle.INK)
		var options: Array = [""]+Game.equipment_slots()
		var choice := OptionButton.new()
		choice.name = "DepartureWishSlot"
		choice.position = Vector2(24,184); choice.size = Vector2(592,43)
		for slot: String in options: choice.add_item(_ex_text("不指定","No preference") if slot.is_empty() else Words.text("SLOT_"+slot.to_upper()))
		choice.select(maxi(0,options.find(selected_wish_slot)))
		choice.item_selected.connect(func(index: int): selected_wish_slot = str(options[index]))
		panel.add_child(choice)
		var begin := GameStyle.button(panel,"",Vector2(28,273),Vector2(284,48),func():
			_pop_modal()
			_start_run_with_wish())
		begin.name = "ConfirmWishDeparture"; begin.text = _ex_text("确认出发","Begin expedition")
		GameStyle.primary(begin)
		GameStyle.button(panel,"BACK",Vector2(328,273),Vector2(284,48),_pop_modal).name = "CancelWishDeparture"
		return
	_start_run_with_wish()

func _start_run_with_wish() -> void:
	var options: Dictionary = {"expedition":true,"biome_id":selected_biome,"difficulty":selected_difficulty}
	if int(Game.profile.get("ruleset_version",1)) == 2: options["wish_slot"] = selected_wish_slot
	if not Game.start_run(options): _show_save_error()

func _on_run_started() -> void:
	# Resume/reload can re-enter Main while the previous room still exists.
	# Retire it before creating its replacement, including owned visual layers.
	if is_instance_valid(hud):
		hud.set_process(false)
		hud.hide()
	if is_instance_valid(room):
		room.process_mode = Node.PROCESS_MODE_DISABLED
		room.hide()
		if room.get_parent()!=null: room.get_parent().remove_child(room)
		room.queue_free()
		room = null
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
	GameStyle.literal(panel,_ex_text("轻松走位，流畅连招。","MOVE FREELY. CHAIN YOUR SKILLS."),Vector2(30,23),Vector2(782,47),31,GameStyle.CYAN)
	GameStyle.literal(panel,_ex_text(str(words[0])+" · "+_current_skill_text(str(words[2])),str(words[3])+" · "+str(words[4])),Vector2(30,88),Vector2(782,61),21,GameStyle.AMBER)
	var steps: Array = [
		_ex_text("01  移动 / 瞄准","01  MOVE / AIM"),_ex_text("用 %s 点击地面或按住走位；鼠标指向决定技能方向。","Use %s on the ground or hold to move. Aim skills with the cursor.") % _control_label("click_move"),
		_ex_text("02  四技连招","02  SKILLS / COMBO"),_ex_text("用 %s 释放四项技能，用 %s 普攻穿插连招。","Use %s for four skills. Weave %s basic attacks into your combo.") % [_current_skill_text("Q / W / E / R"),Controls.secondary_label("attack",Game.profile.settings.get("controls",{}),Words.locale)],
		_ex_text("03  自动被动","03  HERO / PASSIVE"),_ex_text("职业被动自动触发；设置中可开启自动普攻。","Your hero's passive triggers automatically. Enable auto attacks in settings.")]
	for index in range(3):
		GameStyle.literal(panel,str(steps[index*2]),Vector2(30,170+index*57),Vector2(176,35),18,GameStyle.CYAN)
		GameStyle.literal(panel,str(steps[index*2+1]),Vector2(211,170+index*57),Vector2(601,48),17,GameStyle.INK)
	GameStyle.literal(panel,_current_control_summary(),Vector2(30,350),Vector2(782, 50),14,GameStyle.MUTED)
	var begin := GameStyle.button(panel,"",Vector2(534,405),Vector2(278,44),func():
		_pop_modal()
		_show_pending_expedition_offer())
	begin.text = _ex_text("开始试炼  →","BEGIN TRIAL  →")
	GameStyle.primary(begin)
	begin.grab_focus()

func _create_room() -> Node2D:
	return load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()

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
	GameStyle.label(screen,"ROOM_LOAD_FAILED_TITLE",Vector2(88,152),Vector2(1052,64),36,GameStyle.RED)
	var message := GameStyle.label(screen,"ROOM_LOAD_FAILED_NOTE",Vector2(88,244),Vector2(960,100),22)
	message.name = "RoomLoadFailureMessage"
	if expedition != null and expedition.active():
		GameStyle.button(screen,"RETRY",Vector2(88,392),Vector2(390,56),_on_run_started).grab_focus()
		var leave := GameStyle.button(screen,"",Vector2(496,392),Vector2(480,56),_shutdown_after_audio_cleanup)
		leave.name = "ExitWithCheckpoint"
		leave.text = _ex_text("退出 · 保留已保存远征", "Exit · keep saved expedition")
		return
	var return_button := GameStyle.button(screen,"RETURN_CAMP",Vector2(88,392),Vector2(390,56),_return_after_room_error)
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
	hud = load(AssetCatalog.resolve("res://scenes/presentation/hud.tscn")).instantiate()
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
	Game.run.backpack_opens += 1
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
	GameStyle.label(panel,"EXTRACT_NOTE",Vector2(28,87),Vector2(620,147),20,GameStyle.INK,{"gold":Game.run.gold,"kept":Balance.death_keep(Game.run.gold)})
	GameStyle.action_pair(panel,"CONFIRM_EXTRACT","CANCEL",261,func(): _settle("extracted"),_pop_modal)[1].grab_focus()

func show_pause() -> void:
	if Game.run == null:
		return
	var panel := _push_modal("PAUSED",Vector2(568,455))
	GameStyle.label(panel,"PAUSED_NOTE",Vector2(28,76),Vector2(512,59),17,GameStyle.MUTED)
	GameStyle.button(panel,"RESUME",Vector2(28,151),Vector2(512,52),_pop_modal).grab_focus()
	GameStyle.button(panel,"RELICS",Vector2(28,219),Vector2(248,52),show_relics)
	GameStyle.button(panel,"SETTINGS",Vector2(292,219),Vector2(248,52),show_settings)
	GameStyle.button(panel,"ABANDON",Vector2(28,287),Vector2(512,52),show_abandon)
	GameStyle.button(panel,"QUIT",Vector2(28,355),Vector2(512,52),func():
		if expedition != null and expedition.active():
			show_expedition_exit()
		else:
			show_abandon(true))

func show_expedition_exit() -> void:
	_expedition_service.show_expedition_exit()

func _save_expedition_and_quit() -> void:
	if expedition == null or not expedition.active() or not is_instance_valid(room):
		return
	if expedition.current_complete():
		if not Game.save_expedition_checkpoint(room.expedition_runtime_snapshot()):
			_show_expedition_error(Words.text(Game.last_error),_save_expedition_and_quit)
			return
	# Combat keeps its already committed entrance receipt; it is never converted
	# into an abandonment settlement by a normal save-and-exit action.
	_shutdown_after_audio_cleanup()

func show_relics() -> void:
	if Game.run == null:
		return
	var panel := _push_modal("RELICS",Vector2(826,660))
	panel.name = "RelicCollectionModal"
	var scroll := ScrollContainer.new()
	scroll.name = "RelicCollectionScroll"
	scroll.position = Vector2(28,81)
	scroll.size = Vector2(770,485)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	panel.add_child(scroll)
	var flow := VBoxContainer.new()
	flow.custom_minimum_size.x = 746
	flow.add_theme_constant_override("separation",18)
	scroll.add_child(flow)
	if Game.run.relics.is_empty():
		GameStyle.label(flow,"NO_RELICS",Vector2.ZERO,Vector2(746,92),22,GameStyle.MUTED,{"key":_control_label("interact")})
	else:
		for i in range(Game.run.relics.size()):
			var info := _relic_display(str(Game.run.relics[i]),int(Game.expedition_snapshot().get("relic_levels",{}).get({"split":"RL01","ember":"RL02","arc":"RL03"}.get(Game.run.relics[i],Game.run.relics[i]),1)))
			var row := Control.new()
			row.name = "RelicEntry_"+str(i)
			flow.add_child(row)
			_relic_artwork(row,info,Vector2.ZERO,Vector2(80,80),str(Game.run.relics[i]))
			var title := GameStyle.literal(row,str(info.get("name","")),Vector2(92,0),Vector2(654,0),21,GameStyle.CYAN)
			title.size.y = ceilf(title.get_minimum_size().y)
			var description := GameStyle.literal(row,str(info.get("description","")),Vector2(92,title.size.y+4),Vector2(654,0),17)
			description.size.y = ceilf(description.get_minimum_size().y)
			row.custom_minimum_size = Vector2(746,maxf(80,title.size.y+4+description.size.y))
	GameStyle.button(panel,"BACK",Vector2(558,584),Vector2(240,52),_pop_modal).grab_focus()

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
	var skill_title := GameStyle.label(panel,"",Vector2(28,132),Vector2(832,32),22,GameStyle.AMBER)
	var skill_values := GameStyle.label(panel,"",Vector2(28,168),Vector2(832,32),17,GameStyle.CYAN)
	var select_detail := func(which: String):
		var info: Dictionary = hud.skill_info(which)
		skill_title.text = str(info.name)+" / "+str(info.state)
		skill_values.text = str(info.summary)
		body.text = Words.text("HUD_BASE_DESCRIPTION")+"\n\n"+str(info.description)+"\n\n"+_shield_rule_summary()+"\n\n"+_ex_text("同名状态保留较强效果。弱刷新不会降低强度或延长时间；等强刷新只会延长，不会缩短。较强效果替换后，旧弱效果不会恢复。", "For the same status, the stronger effect wins. A weaker refresh changes neither power nor duration; equal power may extend but never shorten it. A replaced weaker effect does not return.")
		body.scroll_to_line(0)
	for i in range(5):
		var which: String = ["q","secondary","f","ultimate","dash"][i]
		var button := GameStyle.button(panel,_control_label(["skill_q","skill_secondary","skill_f","skill_ultimate","dash"][i]),Vector2(28+i*169,77),Vector2(156,44),func(): select_detail.call(which))
		button.name = "Detail_"+which
		button.tooltip_text = str(hud.skill_info(which).name)
	select_detail.call(chosen)
	GameStyle.label(panel,"HUD_WALLET_TOTAL",Vector2(28,445),Vector2(832,38),17,GameStyle.AMBER,{"gold":Game.run.gold,"kept":Balance.death_keep(Game.run.gold)})
	GameStyle.button(panel,"RELICS",Vector2(28,497),Vector2(250,50),show_relics)
	var attributes := GameStyle.button(panel,"",Vector2(294,497),Vector2(298,50),show_attributes)
	attributes.name = "CombatAttributes"
	attributes.text = _ex_text("角色属性","CHARACTER STATS")
	GameStyle.button(panel,"BACK",Vector2(610,497),Vector2(250,50),_pop_modal).grab_focus()

func _shield_rule_summary() -> String:
	var rule := _ex_text("护盾规则：多个来源共享最大容量；吸收伤害会同时减少所有来源。", "Shield rule: overlapping sources share the largest capacity; absorbed damage reduces every source.")
	if not is_instance_valid(room) or not is_instance_valid(room.player) or not room.player.has_method("shield_summary"): return rule
	var summary: Dictionary = room.player.shield_summary()
	return rule+_ex_text("\n当前有效容量 %s · 已记录实际吸收 %s\n计时来源最长剩余 %s 秒；预备来源首次吸收后最长 %s 秒。容量随各来源到期变化。", "\nCurrent effective capacity %s · Recorded actual absorption %s\nTimed sources: up to %s seconds left; reserves: up to %s seconds after first absorption. Capacity changes as sources expire.") % [_amount(float(summary.get("effective_capacity",0.0))),_amount(float(summary.get("total_absorbed",0.0))),_amount(float(summary.get("active_coverage_seconds",0.0))),_amount(float(summary.get("prepared_coverage_seconds",0.0)))]

func show_attributes() -> void:
	if Game.run == null: return
	var panel := _push_modal("",Vector2(1248,640))
	panel.name = "CharacterAttributes"
	panel.set_script(null)
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var dossier: Control = load(AssetCatalog.resolve("res://scripts/presentation/screens/character_panel.gd")).new()
	panel.add_child(dossier)
	dossier.configure(room,_pop_modal)

func show_abandon(exit_game: bool = false) -> void:
	if Game.run == null:
		return
	var panel := _push_modal("ABANDON_TITLE",Vector2(720,360))
	var retained := ProfileStore.retained_gold(Game.run.gold, "abandoned")
	GameStyle.label(panel,"ABANDON_NOTE",Vector2(28,87),Vector2(664,143),20,GameStyle.INK,{"gold":Game.run.gold,"kept":retained,"lost":Game.run.gold-retained})
	var actions := GameStyle.action_pair(panel,"CONFIRM_ABANDON","CANCEL",267,func():
		quit_after_result = exit_game
		_settle("abandoned"),_pop_modal)
	actions[1].grab_focus()

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
	if quit_after_result:
		quit_after_result = false
		# Settlement is already durable. Keep the room/audio owner alive until
		# the mixer releases its playback instead of queuing it for deletion.
		_shutdown_after_audio_cleanup()
		return
	if is_instance_valid(room):
		room.queue_free()
		room = null
	_new_screen("result")
	expedition = null
	if preload("res://scripts/presentation/components/finale_artwork.gd").completed_result(result):
		preload("res://scripts/presentation/components/finale_artwork.gd").show_result(self,result)
		return
	var outcome: String = result.get("outcome","death")
	var title: String = {"extracted":"EXTRACTED","death":"DEATH","abandoned":"ABANDONED"}.get(outcome,"DEATH")
	var accent := GameStyle.GREEN if outcome == "extracted" else GameStyle.RED
	GameStyle.label(screen,title,Vector2(86,105),Vector2(980,78),44,accent)
	if bool(result.get("demo",false)):
		GameStyle.literal(screen,_ex_text("试炼已结束 · 成长存档保持原样","TRIAL COMPLETE · YOUR PROGRESSION SAVE IS UNCHANGED"),Vector2(88,190),Vector2(756,56),17,GameStyle.CYAN)
	else:
		GameStyle.label(screen,"SETTLED",Vector2(88,190),Vector2(800,38),18,GameStyle.MUTED)
	if outcome == "death":
		var death_review: Dictionary = result.get("death_review",{})
		var learn := GameStyle.button(screen,"",Vector2(866,189),Vector2(326,44),func(): _show_death_review(death_review))
		learn.name = "ReviewDeath"
		learn.text = _ex_text("查看致死原因与最近伤害", "REVIEW RECENT DAMAGE")
		learn.add_theme_font_size_override("font_size",15)
	var data := [result.get("collected",result.get("gold",0)),result.get("retained",0),result.get("lost",0)]
	for i in range(3):
		var p := GameStyle.panel(screen,Vector2(88+i*246,265),Vector2(224,167))
		GameStyle.label(p,["COLLECTED","KEPT","LOST"][i],Vector2(21,16),Vector2(184,40),19,GameStyle.MUTED)
		var amount := GameStyle.label(p,"BANK_VALUE",Vector2(21,69),Vector2(184,74),46,GameStyle.AMBER if i == 1 else GameStyle.INK,{"gold":data[i]})
		amount.name = ["Collected","Retained","Lost"][i]
	var discoveries: Array = result.get("discoveries",result.get("new_discoveries",[]))
	GameStyle.label(screen,"RESULT_STATS",Vector2(88,447),Vector2(710,62),20,GameStyle.INK,{"kills":result.get("kills",0),"discoveries":discoveries.size()})
	var equipment_names: Array[String] = []
	for id: String in result.get("equipment_retained",[]):
		equipment_names.append(GameStyle.content_text(ContentRegistry.equipment(id),"name"))
	var equipment_receipt := _ex_text("本次没有带回新装备", "No new equipment extracted") if equipment_names.is_empty() else _ex_text("新装备已入库：", "Added to inventory: ")+" · ".join(equipment_names)
	var lost_items: int = result.get("equipment_lost",[]).size()
	if lost_items > 0: equipment_receipt = _ex_text("遗失 %d 件待带回装备 · 成功撤离后才能入库", "%d pending items lost · extract safely to keep equipment") % lost_items
	if bool(result.get("demo",false)): equipment_receipt = _ex_text("试玩奖励不写入正式库存", "Trial rewards do not enter your progression inventory")
	var loot_note := GameStyle.literal(screen,equipment_receipt,Vector2(88,512),Vector2(710,28),16,GameStyle.CYAN)
	loot_note.name = "ExtractedEquipmentReceipt"
	loot_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	loot_note.tooltip_text = equipment_receipt
	GameStyle.label(screen,"BANK_TOTAL",Vector2(88,544),Vector2(710,36),20,GameStyle.AMBER,{"gold":result.get("permanent_gold",0)})
	var hero_id: String = str(result.get("hero_id",Game.profile.get("selected_hero","CH01")))
	var field_xp: int = int(result.get("field_xp_gained",0))
	var dossier := GameStyle.panel(screen,Vector2(866,242),Vector2(326,368 if field_xp > 0 else 338))
	GameStyle.hero_portrait(dossier,hero_id,Vector2(52,12),Vector2(220,200))
	GameStyle.literal(dossier,GameStyle.content_text(ContentRegistry.hero(hero_id),"name"),Vector2(20,219),Vector2(286,36),24)
	GameStyle.label(dossier,"RESULT_HERO_XP",Vector2(20,267),Vector2(286,57),17,GameStyle.CYAN,{"xp":result.get("hero_xp_gained",0),"level":Game.hero_level(hero_id)})
	if field_xp > 0:
		var field_note := GameStyle.literal(dossier,_ex_text("含战斗积累 +%d 经验","Includes +%d field practice XP") % field_xp,Vector2(20,324),Vector2(286,28),16,GameStyle.AMBER)
		field_note.name = "FieldExperienceReceipt"
	GameStyle.button(screen,"RETURN_CAMP" if Game.has_profile else "MAIN_MENU",Vector2(88,586),Vector2(345,56),show_camp if Game.has_profile else show_menu).grab_focus()
	if bool(result.get("demo",false)):
		var again := GameStyle.button(screen,"",Vector2(451,586),Vector2(345,56),show_demo_select)
		again.text = _ex_text("换个职业再试","TRY ANOTHER HERO")
	else:
		var readout: Script = preload("res://scripts/presentation/hud/progression_readout.gd")
		var next_goal: String = readout.next_goal(hero_id,int(Game.profile.get("hero_xp",{}).get(hero_id,0)))
		var goal_label := GameStyle.literal(screen,_ex_text("下一目标：","NEXT GOAL: ")+next_goal,Vector2(88,658),Vector2(1104,30),17,GameStyle.CYAN)
		goal_label.name = "NextGrowthGoal"

func _show_death_review(review: Dictionary) -> void:
	var panel := _push_modal("",Vector2(1000,650))
	panel.name = "DeathReviewModal"
	GameStyle.literal(panel,_ex_text("死亡复盘 · 最近 15 秒 / 最多 12 次伤害", "DEATH REVIEW · LAST 15 SECONDS / UP TO 12 EVENTS"),Vector2(28,22),Vector2(944,43),26,GameStyle.AMBER)
	var lethal: Dictionary = review.get("lethal_event",{})
	var summary := _ex_text("没有可用的致死记录；不会推测攻击来源。", "No lethal event was recorded; the attack source is unknown.") if lethal.is_empty() else _ex_text("致死一击：", "LETHAL EVENT: ")+_death_event_text(lethal,float(lethal.get("elapsed",0.0)))
	var cause := GameStyle.literal(panel,summary,Vector2(28,78),Vector2(944,72),18,GameStyle.RED)
	cause.name = "DeathCause"
	var lesson := GameStyle.literal(panel,_death_mechanic_note(lethal),Vector2(28,157),Vector2(944,72),17,GameStyle.INK)
	lesson.name = "DeathMechanicNote"
	var scroll := ScrollContainer.new()
	scroll.name = "RecentDamageEvents"
	scroll.position = Vector2(28,241)
	scroll.size = Vector2(944,257)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",11)
	scroll.add_child(list)
	var events: Array = review.get("recent_events",[])
	var reference := float(lethal.get("elapsed",0.0))
	for index: int in range(events.size()-1,-1,-1):
		var event: Dictionary = events[index]
		var line := GameStyle.literal(list,_death_event_text(event,reference),Vector2.ZERO,Vector2(912,0),16,GameStyle.INK)
		line.custom_minimum_size.x = 900
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.name = "DamageEvent_"+str(index)
	var shield_note := _ex_text("本局护盾实际吸收 %s。重叠护盾只取最大容量；吸收伤害会同时减少每个来源。", "Shields actually absorbed %s in this run. Overlapping shields share the largest capacity; absorption reduces every source.") % _amount(float(review.get("total_absorbed",0.0)))
	GameStyle.literal(panel,shield_note,Vector2(28,512),Vector2(944,55),16,GameStyle.MUTED)
	GameStyle.button(panel,"BACK",Vector2(722,584),Vector2(250,44),_pop_modal).grab_focus()

func _death_event_text(event: Dictionary, reference: float) -> String:
	var kind := str(event.get("kind","direct"))
	var category := _ex_text("直接伤害", "Direct damage")
	if kind == "dot": category = _ex_text("持续伤害", "Damage over time")
	elif kind == "shock": category = _ex_text("感电追击", "Shock follow-up")
	var source := str(event.get("source_name",""))
	if source.is_empty(): source = str(event.get("source_id",""))
	if source.is_empty(): source = _ex_text("未知来源", "Unknown source")
	var damage_type := str(event.get("damage_type",""))
	var type_names := {"physical":["物理", "physical"], "magic":["魔法", "magic"], "true":["真实", "true"]}
	if type_names.has(damage_type): damage_type = _ex_text(type_names[damage_type][0],type_names[damage_type][1])
	var age := maxf(0.0,reference-float(event.get("elapsed",reference)))
	var text := _ex_text("前 %s 秒 · %s / %s · %s", "%ss before death · %s / %s · %s") % [_amount(age),category,damage_type,source]
	var attack := str(event.get("attack_id",""))
	if not attack.is_empty(): text += " · "+attack
	text += _ex_text("\n生命 -%s（%s → %s） · 护盾吸收 %s", "\nHP -%s (%s → %s) · Shield absorbed %s") % [_amount(float(event.get("hp_loss",0.0))),_amount(float(event.get("hp_before",0.0))),_amount(float(event.get("hp_after",0.0))),_amount(float(event.get("shield_absorbed",0.0)))]
	var states: Array[String] = []
	for state: String in event.get("key_states",[]): states.append(_death_state_name(state))
	if not states.is_empty(): text += _ex_text(" · 状态：", " · States: ")+", ".join(states)
	return text

func _death_state_name(state: String) -> String:
	var names := {"burn":["燃烧", "Burn"], "bleed":["流血", "Bleed"], "corrosion":["腐蚀", "Corrosion"], "shock":["感电", "Shock"], "chill":["寒冷", "Chill"], "grievous":["重伤", "Grievous"], "slow":["减速", "Slow"], "damage_reduction":["减伤", "Damage reduction"], "brace_guard":["战吼减伤", "Guard reduction"], "invulnerable":["无敌", "Invulnerable"], "dash":["闪避", "Dodge"]}
	return _ex_text(names[state][0],names[state][1]) if names.has(state) else state

func _death_mechanic_note(event: Dictionary) -> String:
	if event.is_empty(): return _ex_text("下一局可结合敌人预警与状态倒计时观察；此处只显示实际记录，不推测反制操作。", "Watch enemy warnings and status timers on your next run. This review shows recorded evidence only.")
	var status := str(event.get("status",""))
	if status == "burn": return _ex_text("燃烧会持续造成魔法伤害。躲开最初攻击后仍需留意燃烧倒计时与剩余生命。", "Burn continues dealing magic damage. After avoiding further attacks, check its timer and your remaining health before re-engaging.")
	if status == "bleed": return _ex_text("流血会持续造成物理伤害。避开后续攻击并不结束流血；重新接敌前查看剩余时间与生命。", "Bleed continues dealing physical damage. Avoiding the next hit does not end it; check the timer and health before re-engaging.")
	if status == "corrosion": return _ex_text("腐蚀会降低护甲并持续造成物理伤害。状态持续时要同时留意后续直接攻击与持续掉血。", "Corrosion lowers armor and deals physical damage over time. While it remains active, account for both follow-up attacks and its damage ticks.")
	if status == "shock" or event.get("kind") == "shock": return _ex_text("感电会在后续命中时触发额外雷击。被施加感电后，留意下一次攻击预警与闪避时机。", "Shock triggers extra lightning on a subsequent hit. After Shock is applied, watch the next attack warning and your dodge timing.")
	if event.get("kind") == "dot": return _ex_text("记录为持续伤害，但没有明确效果名称；请结合当时状态与剩余生命查看，不推测未记录的机制。", "Damage over time was recorded, but its effect is unknown. Check the recorded states and remaining health; an unrecorded mechanism cannot be inferred.")
	return _ex_text("本次记录为直接攻击。对照下方攻击来源、当时状态与护盾吸收，观察同类敌人的出手预警。", "This was a direct attack. Compare the recorded source, active states and shield absorption with that enemy's attack warning.")

func show_settings() -> void:
	_settings_service.show_settings()

func _layout_settings_atlas(panel: Panel, general: Button, controls: Button) -> void:
	for child: Node in panel.get_children():
		if child is Control and child != general and child != controls and not child is ColorRect:
			child.position.x += 200
			if child.position.y == 20: child.size.x -= 200
	general.position = Vector2(24,102)
	general.size = Vector2(168,58)
	general.text = _ex_text("游戏与显示","GAME & DISPLAY")
	general.add_theme_font_size_override("font_size",14)
	controls.position = Vector2(24,178)
	controls.size = Vector2(168,58)
	controls.text = _ex_text("操作与按键","CONTROLS")
	controls.add_theme_font_size_override("font_size",14)
	GameStyle.tab(general,settings_tab == "general")
	GameStyle.tab(controls,settings_tab == "controls")
	GameStyle.literal(panel,_ex_text("设置即时保存","CHANGES AUTOSAVE"),Vector2(24,564),Vector2(168,44),12,GameStyle.MUTED)
	var line := ColorRect.new()
	line.position = Vector2(208,96)
	line.size = Vector2(1,518)
	line.color = Color(GameStyle.COPPER,0.3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)

func _switch_settings_tab(next_tab: String) -> void:
	settings_tab = next_tab
	_pop_modal()
	show_settings()

func _build_control_settings(panel: Panel) -> void:
	GameStyle.literal(panel,_ex_text("点击按键按钮，再按新的键或鼠标按钮。重绑定即时生效并保存。","Select a binding, then press a new key or mouse button. Changes apply and save immediately."),Vector2(28,142),Vector2(824,45),16,GameStyle.MUTED)
	for index in range(Controls.EDITABLE_ACTIONS.size()):
		var action: String = Controls.EDITABLE_ACTIONS[index]
		var origin := Vector2(28 + (index % 2) * 422, 183 + floori(float(index) / 2.0) * 39)
		GameStyle.literal(panel,_control_action_name(action),origin + Vector2(0,5),Vector2(156,29),15)
		var binding := GameStyle.button(panel,"",origin + Vector2(158,0),Vector2(244,36),func(): _begin_control_binding(action))
		binding.name = "Bind_" + action
		binding.add_theme_font_size_override("font_size",15)
		binding.text = Controls.secondary_label(action, Game.profile.settings.get("controls", {}), Words.locale)
		binding.tooltip_text = _ex_text("点击更换主按键；Esc 取消。普攻备用 A 会在分配给其他操作时自动停用。","Click to change the primary binding; Esc cancels. The A attack alias is disabled when assigned to another action.")
	binding_feedback = GameStyle.literal(panel,_ex_text("所有按键均可自定义；Esc 始终可以取消或返回。普攻备用 A 被占用后自动停用。","All actions can be remapped. Esc always cancels or returns. Assigning A elsewhere disables its attack alias."),Vector2(28,550),Vector2(824,36),13,GameStyle.MUTED)
	var reset := GameStyle.button(panel,"",Vector2(28,588),Vector2(264,44),_reset_control_bindings)
	reset.text = _ex_text("恢复默认按键","RESET CONTROLS")
	GameStyle.button(panel,"BACK",Vector2(612,588),Vector2(240,44),_pop_modal)

func _begin_control_binding(action: String) -> void:
	pending_binding_action = action
	var panel := _push_modal("",Vector2(646,314))
	panel.name = "ControlBindingCapture"
	GameStyle.literal(panel,_ex_text("按下新的键或鼠标按钮","PRESS A KEY OR MOUSE BUTTON"),Vector2(28,32),Vector2(590,42),25,GameStyle.AMBER)
	GameStyle.literal(panel,_ex_text("当前按键：","Current binding: ") + _control_label(action),Vector2(28,92),Vector2(590,36),20)
	GameStyle.literal(panel,_ex_text("单个键或鼠标左 / 右 / 中 / 侧键。Esc 取消。\n重复按键会提示冲突，请先调整已占用的操作。","Use one key, or left / right / middle / side mouse buttons. Esc cancels.\nConflicting bindings are rejected; change the existing action first."),Vector2(28,147),Vector2(590,67),16,GameStyle.MUTED)
	GameStyle.button(panel,"CANCEL",Vector2(418,244),Vector2(200,44),_pop_modal)

func _capture_control_binding(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton) or not event.pressed: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not modals.is_empty():
		var capture_panel: Control = modals[-1].node.find_child("ControlBindingCapture",true,false)
		if capture_panel != null:
			for button: Node in capture_panel.find_children("*","Button",true,false):
				if button.get_global_rect().has_point(event.position): return
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
			binding_feedback.add_theme_color_override("font_color", GameStyle.RED)
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
		"dash": ["闪避", "Dodge"], "reload": ["装填", "Reload"], "interact": ["交互", "Interact"],
		"move_up": ["向上移动", "Move up"], "move_down": ["向下移动", "Move down"], "move_left": ["向左移动", "Move left"], "move_right": ["向右移动", "Move right"],
		"ui_cancel": ["安全取消（Esc）", "safe cancel (Esc)"], "relic_details": ["技能详情", "Skill details"], "expedition_map": ["路线", "Map"], "backpack": ["背包", "Backpack"], "pause": ["暂停", "Pause"]}
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
	preload("res://scripts/infrastructure/assets/equipment_art.gd").finish_prefetches()
	if _shutdown_started: return
	music_tick -= delta
	if music_tick > 0.0 or not is_instance_valid(music): return
	music_tick = 0.3
	var context := "camp"
	if route == "workshop_craft": context = "craft"
	elif route in ["workshop_upgrade", "workshop_recycle"]: context = "forge"
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
	elif old_route == "codex":
		show_codex()
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
	var restore_conflict := Game.last_error == "STORAGE_RECYCLE_CONFLICT"
	var panel := _push_modal("RESTORE_CONFLICT_TITLE" if restore_conflict else "ERROR_TITLE",Vector2(770,355))
	if restore_conflict:
		panel.name = "RestoreConflictError"
		GameStyle.label(panel,"STORAGE_RECYCLE_CONFLICT",Vector2(28,77),Vector2(714,161),18,GameStyle.RED).name = "RestoreConflictExplanation"
	else:
		GameStyle.label(panel,"SAVE_ERROR",Vector2(28,77),Vector2(714,161),18,GameStyle.RED,{"error":Words.text(Game.last_error)})
	if Game.run != null and not pending_outcome.is_empty():
		modals[-1]["required"] = true
		GameStyle.button(panel,"RETRY",Vector2(28,269),Vector2(714,52),func():
			_clear_modals()
			_settle(pending_outcome)).grab_focus()
	else:
		GameStyle.button(panel,"BACK",Vector2(499,269),Vector2(243,52),_pop_modal).grab_focus()

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
	shade.color = Color(0.16,0.23,0.20,0.46)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var panel := GameStyle.panel(overlay,Vector2.ZERO,dimensions)
	_fit_modal(panel,dimensions)
	overlay.resized.connect(func(): _fit_modal(panel,dimensions))
	GameStyle.label(panel,title,Vector2(28,20),Vector2(dimensions.x-56,47),30,GameStyle.INK)
	GameStyle.divider(panel,Vector2(28,72),dimensions.x-56)
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
	if _is_menu_cancel(event):
		_unhandled_input(event)
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

func _is_menu_cancel(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE): return true
	if not event.is_action_pressed("pause"): return false
	# A mouse-bound pause must not eat every ordinary menu click. Escape stays
	# available inside menus regardless of the gameplay Pause binding.
	return not event is InputEventMouseButton or (route == "run" and modals.is_empty())

func _unhandled_input(event: InputEvent) -> void:
	if _is_menu_cancel(event):
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
	if _shutdown_started: return
	if room_start_failed and Game.run != null:
		if expedition != null and expedition.active():
			_shutdown_after_audio_cleanup()
		return
	if not modals.is_empty() and modals[-1].get("required",false):
		return
	if Game.run != null:
		if expedition != null and expedition.active():
			show_expedition_exit()
		else:
			show_abandon(true)
	else:
		_shutdown_after_audio_cleanup()

func _shutdown_after_audio_cleanup() -> void:
	if _shutdown_started: return
	if Game.has_method("retry_skill_save") and not Game.retry_skill_save():
		_show_expedition_error(Words.text(Game.last_error),_shutdown_after_audio_cleanup)
		return
	_shutdown_started = true
	# This is reached only after the existing save/settlement/confirmation
	# gates. Freeze the scene so input or Main's music updater cannot restart
	# playback while the existing bounded mixer-cleanup methods yield.
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	if is_instance_valid(ui): ui.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true
	if is_instance_valid(room): room.set_input_blocked(true)
	var audio: Node = room.get("combat_audio") if is_instance_valid(room) else null
	if is_instance_valid(music): music.stop_all()
	if is_instance_valid(audio): audio.stop_all()
	if is_instance_valid(music) and not await music.wait_for_cleanup():
		push_warning("Music playback did not finish cleanup before the shutdown timeout.")
	if is_instance_valid(audio) and not await audio.wait_for_cleanup():
		push_warning("Combat playback did not finish cleanup before the shutdown timeout.")
	get_tree().quit()
