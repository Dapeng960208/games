extends SceneTree
## Focused verification of the approved controls and native HUD reflow.

var failures := 0
var checks := 0
var hud: Control
var room: Node2D
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HUD_LAYOUT: "+message)

func frames() -> void:
	for i in 3:
		await process_frame
		await physics_frame

func _run() -> void:
	game = root.get_node("Game")
	if not game.profile_path.contains("test_hud_controls_layout"):
		quit(2)
		return
	check(game.new_profile() and game.start_run(),"isolated live hero")
	room = load("res://scenes/room.tscn").instantiate()
	room.layout_seed = 146556
	room.spawn_enabled = false
	root.add_child(room)
	await frames()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var layer := CanvasLayer.new()
	root.add_child(layer)
	hud = load("res://scenes/hud.tscn").instantiate()
	hud.room = room
	layer.add_child(hud)
	await frames()
	var pressed := [false]
	hud.inventory_requested.connect(func(): pressed[0] = true)
	hud.inventory_button.pressed.emit()
	check(pressed[0],"backpack button emits its dedicated action")
	check(hud.skill_slots[0].key == "Q" and hud.skill_slots[1].key == "W" and hud.skill_slots[2].key == "E" and hud.skill_slots[3].key == "R","live skill keys use Q W E R")
	check(hud.passive_panel.visible and not hud.passive_title.text.is_empty() and hud.passive_state.text.contains("/"),"live passive displays its name and stacks")
	check(not hud.passive_hint.text.is_empty(),"passive includes a trigger explanation")
	var binding := {"skill_secondary":{"type":"key","code":KEY_T}}
	game.set_setting("controls",binding)
	hud.refresh()
	check(hud.skill_slots[1].key == "T","skill key follows a remapped binding")
	game.set_setting("auto_attack",true)
	hud.refresh()
	check(hud.attack_label.text.contains("开启"),"auto attack display reads the live setting")
	game.set_setting("controls",{})
	for dimensions in [Vector2i(820,600),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = dimensions
		root.content_scale_size = dimensions
		hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await frames()
		hud.refresh()
		var bounds := Rect2(Vector2.ZERO,Vector2(dimensions))
		var contained := true
		for rectangle: Rect2 in hud.coverage_rects(): contained = contained and bounds.encloses(rectangle)
		check(contained,"all standing instruments fit "+str(dimensions))
		check(not hud.passive_panel.get_rect().intersects(hud.skill_dock.get_rect()),"passive and skills do not overlap "+str(dimensions))
		check(not hud.equipment_actions.get_rect().intersects(hud.skill_dock.get_rect()),"backpack and skills do not overlap "+str(dimensions))
		check(not hud.quest_panel.get_rect().intersects(hud.equipment_actions.get_rect()) and not hud.quest_panel.get_rect().intersects(hud.skill_dock.get_rect()),"quest stays clear of bottom controls "+str(dimensions))
		check(hud.route_button_rect().end.x <= dimensions.x and hud.route_button_rect().end.y <= dimensions.y,"reserved route control fits "+str(dimensions))
		if DisplayServer.get_name() != "headless" and dimensions.x != 1920:
			hud.set_process(false)
			hud.hovered_control = null
			hud.focused_control = null
			hud.last_hover_control = null
			hud.hover_grace = 0.0
			hud.tooltip_panel.hide()
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			check(frame.save_png("res://artifacts/hud_controls_"+str(dimensions.x)+".png") == OK,"saved actual HUD screenshot")
			hud.set_process(true)
	hud.passive_button.grab_focus()
	hud._update_tooltip()
	check(hud.tooltip_panel.visible and hud.tooltip_body.text.contains(hud.passive_state.text),"passive details expose current state")
	layer.free()
	room.free()
	game.run = null
	await frames()
	print("HUD_CONTROLS_LAYOUT_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
