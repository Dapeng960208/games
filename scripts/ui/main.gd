extends Node

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
	var keys := {"move_left":KEY_A,"move_right":KEY_D,"move_up":KEY_W,"move_down":KEY_S,"dash":KEY_SPACE,"interact":KEY_E,"relic_details":KEY_TAB,"pause":KEY_ESCAPE}
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

func _new_screen(next_route: String) -> void:
	_clear_modals()
	if is_instance_valid(screen):
		screen.queue_free()
	if is_instance_valid(hud):
		hud.queue_free()
		hud = null
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
	var cont := MineStyle.button(screen,"CONTINUE",Vector2(88,337),Vector2(362,52),show_camp)
	cont.disabled = not Game.has_profile
	var new_button := MineStyle.button(screen,"NEW_GAME",Vector2(88,405),Vector2(362,52),_request_new_profile)
	MineStyle.button(screen,"SETTINGS",Vector2(88,473),Vector2(362,52),show_settings)
	MineStyle.button(screen,"QUIT",Vector2(88,541),Vector2(362,52),_quit)
	if not Game.has_profile:
		MineStyle.label(screen,"NO_PROFILE",Vector2(474,344),Vector2(294,73),16,MineStyle.MUTED)
	MineStyle.label(screen,"PROTOTYPE",Vector2(88,620),Vector2(980,32),16,MineStyle.MUTED)
	_show_warning(screen, Vector2(500,548), Vector2(680,62))
	(new_button if cont.disabled else cont).grab_focus()

func show_camp() -> void:
	_new_screen("camp")
	MineStyle.label(screen,"CAMP",Vector2(56,77),Vector2(800,60),36)
	MineStyle.label(screen,"CAMP_SUB",Vector2(58,137),Vector2(800,36),17,MineStyle.AMBER)
	var stock := MineStyle.panel(screen,Vector2(56,196),Vector2(366,199))
	MineStyle.label(stock,"WAREHOUSE",Vector2(24,18),Vector2(320,35),19,MineStyle.MUTED)
	MineStyle.label(stock,"BANK_VALUE",Vector2(24,61),Vector2(320,66),46,MineStyle.AMBER,{"gold":Game.profile.get("permanent_gold",0)})
	MineStyle.label(stock,"PROFILE_STATS",Vector2(24,146),Vector2(318,30),17,MineStyle.MUTED,{"runs":Game.profile.get("total_runs",0)})
	var discovered := MineStyle.panel(screen,Vector2(56,411),Vector2(366,170))
	MineStyle.label(discovered,"DISCOVERIES",Vector2(20,12),Vector2(322,35),18)
	for i in range(3):
		var id: String = ["split","ember","arc"][i]
		var found: bool = Game.profile.get("discoveries",[]).has(id)
		MineArt.relic(discovered,id,Vector2(12,49+i*34),Vector2(34,34),found)
		MineStyle.label(discovered,"RELIC_"+id.to_upper()+"_NAME",Vector2(52,51+i*34),Vector2(180,30),17,MineStyle.CYAN if found else MineStyle.MUTED)
		MineStyle.label(discovered,"DISCOVERED" if found else "UNDISCOVERED",Vector2(230,51+i*34),Vector2(120,30),16,MineStyle.GREEN if found else MineStyle.MUTED)
	MineStyle.label(screen,"LOADOUT",Vector2(461,196),Vector2(730,40),26)
	MineStyle.label(screen,"LOADOUT_NOTE",Vector2(462,242),Vector2(700,55),17,MineStyle.MUTED)
	var character_art := MineArt.texture("res://assets/characters/salvager.png")
	if character_art != null:
		var portrait := TextureRect.new()
		portrait.texture = character_art
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position = Vector2(964,138)
		portrait.size = Vector2(222,273)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(portrait)
	var note := MineStyle.panel(screen,Vector2(461,309),Vector2(380,271))
	MineStyle.label(note,"FIELD_NOTE",Vector2(22,10),Vector2(338,246),18)
	var rules := MineStyle.panel(screen,Vector2(867,419),Vector2(357,161))
	MineStyle.label(rules,"RULES",Vector2(18,12),Vector2(321,137),17,MineStyle.MUTED)
	MineStyle.button(screen,"MAIN_MENU",Vector2(56,606),Vector2(228,48),show_menu)
	MineStyle.button(screen,"SETTINGS",Vector2(300,606),Vector2(212,48),show_settings)
	var depart := MineStyle.button(screen,"START",Vector2(832,604),Vector2(392,52),_start_run)
	_show_warning(screen,Vector2(500,86),Vector2(710,55))
	depart.grab_focus()

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
	if not Game.start_run():
		_show_save_error()

func _on_run_started() -> void:
	pending_outcome = ""
	quit_after_result = false
	_new_screen("run")
	room = load("res://scenes/room.tscn").instantiate()
	world.add_child(room)
	room.interaction_requested.connect(_on_interaction)
	room.set_input_blocked(false)
	_build_hud()

func _build_hud() -> void:
	if is_instance_valid(hud):
		hud.queue_free()
	hud = load("res://scenes/hud.tscn").instantiate()
	hud.room = room
	hud.relic_details_requested.connect(func():
		if modals.is_empty():
			show_relics())
	ui.add_child(hud)
	if not modals.is_empty():
		ui.move_child(hud,0)

func _on_interaction(kind: String, _payload: Dictionary) -> void:
	if kind == "extract" and modals.is_empty():
		show_extraction()

func show_extraction() -> void:
	if Game.run == null:
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
	MineStyle.button(panel,"QUIT",Vector2(28,355),Vector2(512,52),func(): show_abandon(true))

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
	call_deferred("show_result",result)

func show_result(result: Dictionary) -> void:
	if is_instance_valid(room):
		room.queue_free()
		room = null
	_new_screen("result")
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
	elif old_route == "menu":
		show_menu()
	elif old_route == "result":
		show_result(Game.last_result)
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

func _sync_pause() -> void:
	var paused := Game.run != null and not modals.is_empty()
	get_tree().paused = paused
	if is_instance_valid(room):
		room.set_input_blocked(paused)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not modals.is_empty():
			_pop_modal()
		elif route == "run":
			show_pause()
		elif route == "camp" or route == "result":
			show_menu()
	elif event.is_action_pressed("relic_details") and route == "run" and modals.is_empty():
		get_viewport().set_input_as_handled()
		show_relics()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()

func _quit() -> void:
	if not modals.is_empty() and modals[-1].get("required",false):
		return
	if Game.run != null:
		show_abandon(true)
	else:
		get_tree().quit()
