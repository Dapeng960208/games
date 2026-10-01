extends Node
## Real main/HUD/modal integration and captures of the approved scene direction.
var app: Node
var checks := 0
var failures := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func(): push_error("Approved UI capture timed out"); get_tree().quit(1))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("APPROVED_UI: "+message)

func frames(count: int = 3) -> void:
	for i: int in count:
		await get_tree().process_frame
		await get_tree().physics_frame

func capture(label: String) -> void:
	await frames()
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var frame := get_viewport().get_texture().get_image()
	frame.save_png("res://artifacts/approved_"+label+".png")

func _run() -> void:
	if not Game.profile_path.contains("test_approved_ui"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated profile")
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	check(Game.start_demo("CH01"),"real full-skill trial starts")
	await frames(5)
	app._clear_modals()
	check(is_instance_valid(app.room) and is_instance_valid(app.hud),"main installs world and HUD")
	var room: Node2D = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	room.release_gate = false
	room.pointer_release_gate = false
	room.player.request_move(room.player.position+Vector2(120,0))
	app.show_backpack()
	check(get_tree().paused and room.input_blocked,"backpack pauses and blocks gameplay")
	check(not room.player.click_navigation.is_active(),"opening backpack cancels the old movement path")
	check(app.ui.find_child("BackpackPanel",true,false)!=null,"real backpack is in the modal")
	await capture("backpack_1280")
	var modal: Control = app.ui.find_child("CombatBackpackModal",true,false)
	check(get_viewport().get_visible_rect().encloses(modal.get_global_rect()),"backpack stays inside the viewport")
	app._pop_modal()
	await frames()
	check(not get_tree().paused and not room.input_blocked,"closing backpack resumes gameplay")
	for index: int in 4:
		var biome := "B%02d" % (index+1)
		var id: String = ["L02","L09","L13","L21"][index]
		var prepared: Dictionary = room.prepare_expedition_node({"room_id":id,"role":"branch","biome_id":biome,
			"node_index":1,"node_count":6,"difficulty":0,"seed":146556,"phase":"combat","expedition":true})
		check(bool(prepared.get("valid",false)),"actual fixed room prepares "+id)
		if not bool(prepared.get("valid",false)): continue
		room.apply_prepared_expedition_node(prepared)
		for actor: Node in room.enemies.get_children(): actor.free()
		room.player.position = Vector2(1400,900)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		app.hud.refresh()
		await capture(biome+"_center_1280")
		room.player.position = Vector2(1000,180)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await capture(biome+"_north_1280")
		room.player.position = Vector2(2610,1620)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await capture(biome+"_southeast_1280")
	# Wide and taller windows use the same screen HUD and modal APIs.
	for extent: Vector2i in [Vector2i(1920,1080),Vector2i(1280,900)]:
		get_window().size = extent
		await frames()
		app.show_backpack()
		modal = app.ui.find_child("CombatBackpackModal",true,false)
		check(get_viewport().get_visible_rect().encloses(modal.get_global_rect()),"modal fits "+str(extent))
		await capture("backpack_"+str(extent.x)+"x"+str(extent.y))
		app._pop_modal()
	app.set_process(false)
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free()
	Game.run = null
	await frames(2)
	print("APPROVED_UI_RESULT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
