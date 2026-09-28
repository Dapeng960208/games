extends Node

const DifficultyProfiles = preload("res://scripts/combat/enemy_profiles.gd")
const ExpeditionScript = preload("res://scripts/world/expedition_controller.gd")
const ExpeditionPanel = preload("res://scripts/ui/expedition_panel.gd")
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_install_inputs()
	Words.initialize(Game.profile.get("settings",{}).get("language","zh_CN"))
	_apply_display()
	backdrop = Node2D.new()
	backdrop.set_script(load("res://scripts/ui/menu_backdrop.gd"))
	add_child(backdrop)
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
	show_menu()
	if Game.run != null and not Game.last_error.is_empty():
		_on_settlement_failed("abandoned")
	# Dedicated automation scripts load this scene and call the same public routes.

func _install_inputs() -> void:
	var keys := {"move_left":KEY_A,"move_right":KEY_D,"move_up":KEY_W,"move_down":KEY_S,"dash":KEY_SPACE,"skill_q":KEY_Q,"skill_f":KEY_F,"skill_ultimate":KEY_R,"interact":KEY_E,"relic_details":KEY_TAB,"expedition_map":KEY_M,"pause":KEY_ESCAPE}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action,event)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack",mouse)

	if not InputMap.has_action("skill_secondary"):
		InputMap.add_action("skill_secondary")
		var secondary := InputEventMouseButton.new()
		secondary.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("skill_secondary",secondary)

func _new_screen(next_route: String) -> void:
	_clear_modals()
	if is_instance_valid(screen):
		screen.queue_free()
	if is_instance_valid(hud):
		hud.queue_free()
		hud = null
	expedition_status = null
	route = next_route
	backdrop.visible = next_route != "run"
	backdrop.camp = next_route != "menu"
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)

func show_menu() -> void:
	_new_screen("menu")
	MineStyle.label(screen,"SUBTITLE",Vector2(88,94),Vector2(625,40),18,MineStyle.AMBER)
	MineStyle.label(screen,"TITLE",Vector2(84,149),Vector2(720,84),54,MineStyle.INK)
	MineStyle.label(screen,"TAGLINE",Vector2(88,246),Vector2(570,48),21,MineStyle.MUTED)
	var cont := MineStyle.button(screen,"CONTINUE",Vector2(88,337),Vector2(362,52),_continue_game)
	cont.disabled = not Game.has_profile
	var new_button := MineStyle.button(screen,"NEW_GAME",Vector2(88,405),Vector2(362,52),_request_new_profile)
	MineStyle.button(screen,"SETTINGS",Vector2(88,473),Vector2(362,52),show_settings)
	MineStyle.button(screen,"QUIT",Vector2(88,541),Vector2(362,52),_quit)
	if not Game.has_profile:
		MineStyle.label(screen,"NO_PROFILE",Vector2(474,344),Vector2(294,73),16,MineStyle.MUTED)
	MineStyle.label(screen,"PROTOTYPE",Vector2(88,620),Vector2(980,32),16,MineStyle.MUTED)
	_show_warning(screen, Vector2(500,548), Vector2(680,62))
	(new_button if cont.disabled else cont).grab_focus()

func _continue_game() -> void:
	if Game.run != null and not Game.expedition_snapshot().is_empty():
		_on_run_started()
	else:
		show_camp()

func show_camp() -> void:
	if room_start_failed and Game.run != null:
		return
	_new_screen("camp")
	var hero_id: String = Game.profile.get("selected_hero","CH01")
	var hero: Dictionary = ContentRegistry.hero(hero_id)
	var stats: Dictionary = Game.selected_stats()
	var level: int = Game.hero_level(hero_id)
	MineStyle.label(screen,"WORKSHOP_KICKER",Vector2(40,28),Vector2(950,28),16,MineStyle.AMBER)
	MineStyle.label(screen,"CAMP",Vector2(40,62),Vector2(800,55),36)
	MineStyle.label(screen,"BANK_TOTAL",Vector2(902,49),Vector2(338,42),23,MineStyle.AMBER,{"gold":Game.profile.get("permanent_gold",0)})
	var dossier := MineStyle.panel(screen,Vector2(40,132),Vector2(362,472))
	MineStyle.label(dossier,"ACTIVE_DOSSIER",Vector2(20,15),Vector2(320,28),16,MineStyle.MUTED)
	MineStyle.hero_portrait(dossier,hero_id,Vector2(41,46),Vector2(280,265))
	MineStyle.literal(dossier,MineStyle.content_text(hero,"name"),Vector2(20,313),Vector2(320,40),28)
	MineStyle.literal(dossier,MineStyle.content_text(hero,"class_name")+" / Lv."+str(level),Vector2(20,354),Vector2(320,28),18,MineStyle.AMBER)
	MineStyle.label(dossier,"DOSSIER_STATS",Vector2(20,389),Vector2(322,63),17,MineStyle.MUTED,{"hp":int(stats.get("max_hp",100)),"damage":"%.1f" % float(stats.get("attack",20)),"armor":int(stats.get("armor",0))})
	MineStyle.label(screen,"CAMP_SUB",Vector2(438,133),Vector2(788,35),18,MineStyle.CYAN)
	MineStyle.literal(screen,_ex_text("每次远征 8 站 · 分支目标、补给与区域首领", "8 stops per expedition · branching objectives, supplies and an area boss"),Vector2(438,178),Vector2(780,35),19)
	_build_biome_selector()
	var choices := [["HERO_DOSSIERS","heroes"],["SKILL_LEDGER","skills"],["EQUIPMENT_BENCH","inventory"],["SUPPLY_CATALOG","shop"]]
	for i in range(choices.size()):
		var item: Array = choices[i]
		var button := MineStyle.button(screen,item[0],Vector2(438+(i%2)*402,272+(i/2)*88),Vector2(386,64),func(): show_workshop(item[1]))
		button.name = "Open_"+item[1]
		if item[1] in ["inventory","shop"]:
			var symbol := Control.new()
			symbol.set_script(load("res://scripts/ui/generated_ui_icon.gd"))
			symbol.position = Vector2(14,12)
			symbol.size = Vector2(40,40)
			button.add_child(symbol)
			symbol.configure("workshop" if item[1] == "inventory" else "loot")
	var brief := MineStyle.panel(screen,Vector2(438,460),Vector2(788,144))
	MineStyle.label(brief,"NEXT_SKILL",Vector2(22,12),Vector2(450,36),20,MineStyle.AMBER,{"level":_next_skill_level(level)})
	MineStyle.label(brief,"RESOURCE_"+str(hero.get("resource_type","rage")).to_upper()+"_RULE",Vector2(22,55),Vector2(450,69),17,MineStyle.MUTED)
	MineStyle.label(brief,"DEPARTURE_DIFFICULTY",Vector2(510,10),Vector2(252,27),17,MineStyle.AMBER)
	var difficulty_choice := OptionButton.new()
	difficulty_choice.name = "DepartureDifficulty"
	difficulty_choice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	difficulty_choice.position = Vector2(510,42)
	difficulty_choice.size = Vector2(252,44)
	difficulty_choice.custom_minimum_size = Vector2(252,44)
	difficulty_choice.add_theme_font_size_override("font_size",18)
	for index in DIFFICULTY_KEYS.size():
		difficulty_choice.add_item(Words.text(DIFFICULTY_KEYS[index]),index)
	selected_difficulty = clampi(selected_difficulty,0,DifficultyProfiles.MAX_DIFFICULTY)
	difficulty_choice.select(selected_difficulty)
	brief.add_child(difficulty_choice)
	var count_note := MineStyle.literal(brief,_ex_text("8 站 · 5 场目标战 + 首领", "8 stops · 5 objectives + boss"),Vector2(510,94),Vector2(252,40),16,MineStyle.MUTED)
	count_note.name = "DepartureEnemyCount"
	difficulty_choice.item_selected.connect(func(index: int):
		selected_difficulty = clampi(index,0,DifficultyProfiles.MAX_DIFFICULTY))
	MineStyle.button(screen,"MAIN_MENU",Vector2(40,634),Vector2(194,48),show_menu)
	MineStyle.button(screen,"SETTINGS",Vector2(250,634),Vector2(242,48),show_settings)
	var depart := MineStyle.button(screen,"START",Vector2(824,634),Vector2(402,48),_start_run)
	depart.name = "Depart"
	_show_warning(screen,Vector2(510,638),Vector2(292,43))
	depart.grab_focus()

func _departure_enemy_count(difficulty: int) -> int:
	var total := 0
	for zone in DifficultyProfiles.ZONE_COUNT:
		total += int(DifficultyProfiles.encounter_plan("L01",zone,difficulty).get("total_count",0))
	return total

func _ex_text(zh: String, en: String) -> String:
	return en if Words.locale == "en" else zh

func _build_biome_selector() -> void:
	var available: Array = ExpeditionScript.unlocked_biomes(Game.profile)
	if not available.has(selected_biome):
		selected_biome = "B01"
	var picker := OptionButton.new()
	picker.name = "DepartureBiome"
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.position = Vector2(438,219)
	picker.size = Vector2(386,44)
	picker.add_theme_font_size_override("font_size",17)
	for index in range(4):
		var biome_id: String = "B%02d" % (index+1)
		var definition: Dictionary = WorldCatalog.biomes().get(biome_id,{})
		var locked := not available.has(biome_id)
		picker.add_item(str(definition.get("name",biome_id))+(_ex_text(" · 首领未解锁", " · Locked") if locked else ""),index)
		picker.set_item_disabled(index,locked)
	picker.select(int(selected_biome.trim_prefix("B"))-1)
	picker.item_selected.connect(func(index: int): selected_biome = "B%02d" % (index+1))
	screen.add_child(picker)
	MineStyle.literal(screen,_ex_text("击败首领并撤离后开放下一区域", "Defeat the boss and extract to unlock the next area"),Vector2(838,224),Vector2(385,35),15,MineStyle.MUTED)

func _build_expedition_status() -> void:
	if is_instance_valid(expedition_status):
		expedition_status.get_parent().queue_free()
	if expedition == null or not expedition.active() or not is_instance_valid(screen):
		return
	var map_button := MineStyle.button(screen,"",Vector2(1030,77),Vector2(234,44),func():
		if modals.is_empty():
			show_expedition(false))
	map_button.name = "ExpeditionMapButton"
	expedition_status = MineStyle.literal(map_button,"",Vector2(10,7),Vector2(214,30),17,MineStyle.AMBER)
	_update_expedition_status()

func _update_expedition_status() -> void:
	if not is_instance_valid(expedition_status) or expedition == null or not expedition.active():
		return
	expedition_status.text = _ex_text("远征 ", "ROUTE ") + str(expedition.current_index()+1)+" / 8    [M]"

func _on_expedition_room_completed() -> void:
	_update_expedition_status()
	if expedition != null and expedition.active():
		call_deferred("_show_pending_expedition_offer")

func show_expedition(at_exit: bool = false) -> void:
	if expedition == null or not expedition.active() or Game.run == null:
		return
	var panel := _push_modal("",Vector2(1072,580))
	panel.name = "ExpeditionRouteModal"
	MineStyle.literal(panel,_ex_text("矿井路线 · 每次远征 8 站", "MINE ROUTE · 8 STOPS"),Vector2(28,20),Vector2(1016,45),28,MineStyle.AMBER)
	var chart := ExpeditionPanel.new()
	chart.name = "ExpeditionRouteChart"
	chart.position = Vector2(28,78)
	chart.size = Vector2(1016,480)
	panel.add_child(chart)
	chart.configure(expedition, at_exit)
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

func _show_expedition_error(message: String, retry: Callable) -> void:
	var panel := _push_modal("ERROR_TITLE",Vector2(700,318))
	if message.is_empty():
		message = _ex_text("当前操作未能完成，进度与金币已保留。请重试。", "This action could not complete. Your progress and gold are unchanged. Please retry.")
	MineStyle.literal(panel,message,Vector2(28,85),Vector2(644,108),19,MineStyle.RED)
	MineStyle.button(panel,"RETRY",Vector2(28,226),Vector2(309,52),func():
		_pop_modal()
		retry.call()).grab_focus()
	MineStyle.button(panel,"BACK",Vector2(357,226),Vector2(315,52),func():
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

func show_expedition_service() -> void:
	if expedition == null or not expedition.active() or Game.run == null:
		return
	if expedition.current_node().get("role", "") == "supply":
		_show_expedition_supply()
	else:
		_show_pending_expedition_offer()
		if modals.is_empty():
			show_expedition(false)

func _relic_display(id: String) -> Dictionary:
	var legacy: String = {"RL01":"split", "RL02":"ember", "RL03":"arc"}.get(id, "")
	if not legacy.is_empty():
		return {"name":Words.text("RELIC_"+legacy.to_upper()+"_NAME"),"description":Words.text("RELIC_"+legacy.to_upper()+"_DESC"),"art":legacy}
	return {"name":id,"description":"","art":""}

func _show_expedition_relic(offer: Dictionary) -> void:
	var panel := _push_modal("",Vector2(1048,498))
	panel.name = "ExpeditionRelicModal"
	modals[-1]["required"] = true
	MineStyle.literal(panel,_ex_text("选一件遗物 · 塑造本局打法", "CHOOSE A RELIC · SHAPE THIS RUN"),Vector2(28,20),Vector2(992,47),28,MineStyle.AMBER)
	MineStyle.literal(panel,_ex_text("选择立即生效，只保留到本局结束。也可跳过并恢复 6% 最大生命。", "Choose an immediate effect for this run, or skip to recover 6% max health."),Vector2(28,80),Vector2(992,44),17,MineStyle.MUTED)
	var candidates: Array = offer.get("candidates",[])
	for index in candidates.size():
		var id := str(candidates[index])
		var info := _relic_display(id)
		var current_rank: int = int(expedition.snapshot().get("relic_levels",{}).get(id,0))
		var card := MineStyle.button(panel,"",Vector2(28+index*336,140),Vector2(320,234),func(): _choose_expedition_relic(str(offer.offer_id),id))
		card.name = "RelicChoice_"+id
		if not str(info.art).is_empty():
			MineArt.relic(card,str(info.art),Vector2(116,12),Vector2(88,88))
		MineStyle.literal(card,str(info.name)+(" · II" if current_rank==1 else " · I"),Vector2(16,104),Vector2(288,37),22,MineStyle.CYAN)
		MineStyle.literal(card,str(info.description),Vector2(16,146),Vector2(288,74),16,MineStyle.INK)
	var skip := MineStyle.button(panel,"",Vector2(678,410),Vector2(342,52),func(): _choose_expedition_relic(str(offer.offer_id),"skip"))
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
	_show_pending_expedition_offer()

func _show_expedition_supply() -> void:
	var panel := _push_modal("",Vector2(920,570))
	panel.name = "ExpeditionSupplyModal"
	MineStyle.literal(panel,_ex_text("矿下补给站", "UNDERGROUND SUPPLY"),Vector2(28,20),Vector2(864,45),30,MineStyle.AMBER)
	MineStyle.literal(panel,_ex_text("本局金币 ", "CARRIED GOLD ")+str(Game.run.gold)+_ex_text(" · 每项仅可购买一次", " · Each item can be bought once"),Vector2(28,81),Vector2(864,42),20,MineStyle.CYAN)
	var products := {"heal_small":["应急药剂 · 回复 15% 生命","Field dressing · heal 15%"], "heal_large":["维修包 · 回复 35% 生命","Repair kit · heal 35%"], "shield":["下房护盾 · 15% 生命 / 4 秒","Next battle · 15% shield for 4s"], "amplify":["超频剂 · 后两战斗房攻击 +8%","Overclock · +8% for 2 rooms"], "scan":["勘测信标 · 显示具体敌群","Survey beacon · reveal enemies"], "mana":["共鸣液 · 回复法力","Resonance flask · restore mana"], "energy":["能量匣 · 回复能量","Energy cell · restore energy"]}
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
	room.set_input_blocked(false)
	_build_hud()
	if expedition.active():
		call_deferred("_show_pending_expedition_offer")

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
	ui.add_child(hud)
	if not modals.is_empty():
		ui.move_child(hud,0)
	_build_expedition_status()

func _on_interaction(kind: String, _payload: Dictionary) -> void:
	if not modals.is_empty():
		return
	if kind in ["next", "early_extract"] and expedition != null and expedition.active():
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
	MineStyle.literal(panel,_ex_text("保存远征并退出", "SAVE EXPEDITION AND EXIT"),Vector2(28,20),Vector2(664,48),28,MineStyle.AMBER)
	var note := _ex_text("当前位置是安全阶段。保存当前生命、资源与冷却，下次从这一站继续。", "This is a safe phase. Save health, resource and cooldowns and continue from this stop next time.")
	if not expedition.current_complete():
		note = _ex_text("当前房间尚未完成。下次从本房入口重打；本房未提交的金币与战利品不会保留。已完成房间的进度不受影响。", "This room is unfinished. Next time you restart at this room's entrance; uncommitted loot from this room is discarded. Earlier completed rooms are retained.")
	MineStyle.literal(panel,note,Vector2(28,88),Vector2(664,137),21,MineStyle.INK)
	var save := MineStyle.button(panel,"",Vector2(28,267),Vector2(414,52),_save_expedition_and_quit)
	save.name = "SaveExpeditionAndQuit"
	save.text = _ex_text("确认保存并退出", "Save and exit")
	MineStyle.button(panel,"CANCEL",Vector2(462,267),Vector2(230,52),_pop_modal).grab_focus()

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
	var panel := _push_modal("RELICS",Vector2(826,472))
	if Game.run.relics.is_empty():
		MineStyle.label(panel,"NO_RELICS",Vector2(28,130),Vector2(770,92),22,MineStyle.MUTED)
	else:
		for i in range(Game.run.relics.size()):
			var key: String = "RELIC_"+Game.run.relics[i].to_upper()
			MineArt.relic(panel,Game.run.relics[i],Vector2(26,81+i*99),Vector2(80,80))
			MineStyle.label(panel,key+"_NAME",Vector2(120,81+i*99),Vector2(655,32),21,MineStyle.CYAN)
			MineStyle.label(panel,key+"_DESC",Vector2(120,114+i*99),Vector2(655,65),17)
	MineStyle.button(panel,"BACK",Vector2(558,389),Vector2(240,52),_pop_modal).grab_focus()

func show_combat_details(slot: String = "q") -> void:
	if Game.run == null or not is_instance_valid(hud):
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
		var button := MineStyle.button(panel,["Q","RMB","F","R","SPACE"][i],Vector2(28+i*169,77),Vector2(156,44),func(): select_detail.call(which))
		button.name = "Detail_"+which
		button.tooltip_text = str(hud.skill_info(which).name)
	select_detail.call(chosen)
	MineStyle.label(panel,"HUD_WALLET_TOTAL",Vector2(28,445),Vector2(832,38),17,MineStyle.AMBER,{"gold":Game.run.gold,"kept":Balance.death_keep(Game.run.gold)})
	MineStyle.button(panel,"RELICS",Vector2(28,497),Vector2(250,50),show_relics)
	MineStyle.button(panel,"BACK",Vector2(610,497),Vector2(250,50),_pop_modal).grab_focus()

func show_abandon(exit_game: bool = false) -> void:
	if Game.run == null:
		return
	var panel := _push_modal("ABANDON_TITLE",Vector2(720,360))
	var retained := Balance.death_keep(Game.run.gold)
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
	MineStyle.label(screen,"SETTLED",Vector2(88,190),Vector2(800,38),18,MineStyle.MUTED)
	var data := [result.get("collected",result.get("gold",0)),result.get("retained",0),result.get("lost",0)]
	for i in range(3):
		var p := MineStyle.panel(screen,Vector2(88+i*246,265),Vector2(224,167))
		MineStyle.label(p,["COLLECTED","KEPT","LOST"][i],Vector2(21,16),Vector2(184,40),19,MineStyle.MUTED)
		var amount := MineStyle.label(p,"BANK_VALUE",Vector2(21,69),Vector2(184,74),46,MineStyle.AMBER if i == 1 else MineStyle.INK,{"gold":data[i]})
		amount.name = ["Collected","Retained","Lost"][i]
	var discoveries: Array = result.get("discoveries",result.get("new_discoveries",[]))
	MineStyle.label(screen,"RESULT_STATS",Vector2(88,469),Vector2(710,91),20,MineStyle.INK,{"kills":result.get("kills",0),"discoveries":discoveries.size()})
	MineStyle.label(screen,"BANK_TOTAL",Vector2(88,544),Vector2(710,36),20,MineStyle.AMBER,{"gold":result.get("permanent_gold",0)})
	var hero_id: String = str(result.get("hero_id",Game.profile.get("selected_hero","CH01")))
	var dossier := MineStyle.panel(screen,Vector2(866,242),Vector2(326,338))
	MineStyle.hero_portrait(dossier,hero_id,Vector2(52,12),Vector2(220,200))
	MineStyle.literal(dossier,MineStyle.content_text(ContentRegistry.hero(hero_id),"name"),Vector2(20,219),Vector2(286,36),24)
	MineStyle.label(dossier,"RESULT_HERO_XP",Vector2(20,267),Vector2(286,57),17,MineStyle.CYAN,{"xp":result.get("hero_xp_gained",0),"level":Game.hero_level(hero_id)})
	MineStyle.button(screen,"RETURN_CAMP",Vector2(88,586),Vector2(345,56),show_camp).grab_focus()
	if quit_after_result:
		quit_after_result = false
		get_tree().quit()

func show_settings() -> void:
	var panel := _push_modal("SETTINGS",Vector2(810,523))
	MineStyle.label(panel,"CONTROLS",Vector2(28,78),Vector2(754,125),18,MineStyle.MUTED)
	MineStyle.button(panel,"LANGUAGE",Vector2(28,222),Vector2(754,52),_toggle_language).grab_focus()
	MineStyle.button(panel,"FULLSCREEN_ON" if Game.profile.get("settings",{}).get("fullscreen",false) else "FULLSCREEN_OFF",Vector2(28,290),Vector2(754,52),_toggle_fullscreen)
	MineStyle.button(panel,"FX_ON" if Game.profile.get("settings",{}).get("reduced_fx",false) else "FX_OFF",Vector2(28,358),Vector2(754,52),_toggle_fx)
	MineStyle.button(panel,"BACK",Vector2(542,445),Vector2(240,52),_pop_modal)

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
	shade.color = Color(0.015,0.025,0.035,0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var panel := MineStyle.panel(overlay,(Vector2(1280,720)-dimensions)/2,dimensions)
	MineStyle.label(panel,title,Vector2(28,20),Vector2(dimensions.x-56,47),30,MineStyle.AMBER)
	modals.append({"node":overlay,"focus":previous_focus})
	_sync_pause()
	return panel

func _pop_modal() -> void:
	if modals.is_empty():
		return
	if modals[-1].get("required",false):
		return
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
	if event.is_action_pressed("expedition_map") and route == "run" and modals.is_empty() and expedition != null and expedition.active():
		get_viewport().set_input_as_handled()
		show_expedition(false)
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
		elif route == "camp" or route == "result":
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
