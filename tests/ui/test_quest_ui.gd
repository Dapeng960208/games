extends SceneTree
## Authored L14 task text stays reachable through real HUD hover and click.
var checks := 0
var failures := 0
var game: Node
var room: Node2D
var hud: Control
var layer: CanvasLayer
var graphical := false

func _initialize() -> void:
	call_deferred("run_checks")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("QUEST_UI FAIL: "+message)

func frames(count: int = 2) -> void:
	for _index in count:
		await process_frame
		await physics_frame

func pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event,true)

func button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event,true)

func run_checks() -> void:
	for action in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_quest_ui"):
		push_error("Refusing quest UI tests without an isolated test_quest_ui profile")
		quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280,720)
	check(game.new_profile() and game.start_run(),"isolated real run")
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.layout_id = "L14"
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	for enemy in room.enemies.get_children(): enemy.free()
	var objectives: Node = load(AssetCatalog.resolve("res://scripts/gameplay/world/room_objectives.gd")).new()
	room.add_child(objectives)
	objectives.configure(room,room.layout,"branch")
	room.objectives = objectives
	room.objective_complete = false
	check(objectives.module != null,"production L14 mechanics configured")
	layer = CanvasLayer.new()
	root.add_child(layer)
	hud = load(AssetCatalog.resolve("res://scripts/presentation/hud/hud.gd")).new()
	hud.room = room
	hud.size = Vector2(1280,720)
	layer.add_child(hud)
	for locale in ["zh_CN","en"]:
		Words.set_locale(locale)
		hud.refresh()
		check(hud.objective_label.autowrap_mode == (TextServer.AUTOWRAP_WORD_SMART if locale == "en" else TextServer.AUTOWRAP_ARBITRARY),locale+" uses the actual locale wrapping rules")
		await frames()
		check(hud.objective_label.get_visible_line_count() == hud.objective_label.get_line_count(),locale+" standing L14 paints every shaped task line")
		check(hud.quest_panel.get_global_rect().end.y <= 586,locale+" standing task finishes above the skill row")
		var expected := "Lighting order changes cargo tracks and incoming enemy directions" if locale == "en" else "点灯顺序改变货轨与来敌方向"
		check(hud.quest_full_action.contains(expected),locale+" retains the complete authored L14 action")
		var point: Vector2 = hud.quest_button.get_global_rect().get_center()
		pointer(point)
		await frames()
		hud._update_tooltip()
		check(hud.tooltip_panel.visible and hud.tooltip_body.text.contains(expected),locale+" actual pointer hover exposes the final instruction")
		check(hud.tooltip_body.get_visible_line_count() == hud.tooltip_body.get_line_count(),locale+" native detail label paints every instruction line")
		var label: Label = hud.tooltip_body
		var measured: Vector2 = label.get_theme_font("font").get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,label.size.x,label.get_theme_font_size("font_size"))
		check(measured.y <= label.size.y+1 and Rect2(0,0,1280,720).encloses(hud.tooltip_panel.get_global_rect()),locale+" complete task details fit the viewport")
		button(point,true)
		await frames(1)
		check(hud.quest_button.has_focus() and hud.tooltip_panel.visible and hud.active_detail_slot == "quest",locale+" actual click focuses persistent quest details")
		check(hud._pointer_over_instruments(point),locale+" quest detail click blocks combat pointer input")
		button(point,false)
		if graphical:
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("res://artifacts/quest_L14_"+locale+"_1280.png") == OK,locale+" saved unmodified GPU quest detail capture")
		hud.quest_button.release_focus()
		hud.hovered_control = null
		hud.focused_control = null
		hud.last_hover_control = null
		hud.hover_grace = 0
		pointer(Vector2(640,360))
		await frames()
	# L21 reads its authentic objective module, so localization cannot fake a
	# shorter instruction or replace the live beam completion counter.
	var beam_room: Node2D = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	beam_room.layout_id = "L21"
	beam_room.spawn_enabled = false
	beam_room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(beam_room)
	for enemy in beam_room.enemies.get_children(): enemy.free()
	var beam_objectives: Node = load(AssetCatalog.resolve("res://scripts/gameplay/world/room_objectives.gd")).new()
	beam_room.add_child(beam_objectives)
	beam_objectives.configure(beam_room,beam_room.layout,"branch")
	beam_room.objectives = beam_objectives
	beam_room.objective_complete = false
	hud.room = beam_room
	Words.set_locale("zh_CN")
	hud.refresh()
	await frames()
	check(hud.quest_full_action == str(beam_objectives.status().text),"Chinese L21 action preserves authentic beam mechanics text")
	check(hud.objective_label.get_visible_line_count() == hud.objective_label.get_line_count(),"Chinese L21 paints its final inscription character")
	Words.set_locale("en")
	hud.refresh()
	await frames()
	check(hud.quest_full_action.contains("Inscriptions lit 0/2") and hud.quest_full_action.contains("keep the scene beam aimed at inscriptions"),"English L21 preserves live counter and full reflected beam requirement")
	check(hud.objective_label.get_visible_line_count() == hud.objective_label.get_line_count(),"English L21 paints every wrapped instruction line")
	var chinese := RegEx.new()
	chinese.compile("[一-龥]")
	check(chinese.search(hud.quest_full_action) == null,"English actual L21 task contains no untranslated Chinese")
	hud.room = room
	await beam_room.combat_audio.wait_for_cleanup()
	beam_room.free()
	await room.combat_audio.wait_for_cleanup()
	layer.free()
	room.free()
	game.finish_run("abandoned")
	await frames()
	print("QUEST_UI_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
