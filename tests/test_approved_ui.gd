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
	var visual := preload("res://scripts/combat/hero_visual.gd")
	var height: float = preload("res://scripts/combat/presentation_metrics.gd").HERO_BODY_HEIGHT
	for hero: String in ["CH01","CH02","CH03"]:
		for bank: String in ["front","back"]:
			var consistent := true
			for pose: Dictionary in [{"phase":"idle","slot":"basic"},{"phase":"release","slot":"basic"},{"phase":"release","slot":"secondary"},{"phase":"release","slot":"f"}]:
				pose["progress"] = 0.5
				var frame: Dictionary = visual.presentation_frame_info(hero,bank,pose,30.0,false)
				consistent = consistent and not frame.is_empty() and is_equal_approx(float(frame.get("body_height",0)),height) and frame.get("anchors",{}).get("foot") == Vector2(0,8)
			var walk: Dictionary = visual.walk_frame_info(hero,bank,40.0)
			if not walk.is_empty(): consistent = consistent and is_equal_approx(float(walk.body_height),height)
			check(consistent,hero+" "+bank+" idle/walk/attack/skill share anatomy scale and feet")
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
		for actor: Node in room.enemies.get_children():
			if actor.actor_kind != "objective": actor.free()
		var authored_arena: Rect2 = room.layout.arena
		room.player.position = room.clamp_actor(authored_arena.get_center()+Vector2(0,120), Balance.PLAYER_RADIUS)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		app.hud.refresh()
		await capture(biome+"_center_1280")
		room.player.position = room.clamp_actor(authored_arena.position+authored_arena.size*Vector2(.36,.10), Balance.PLAYER_RADIUS)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		await capture(biome+"_north_1280")
		room.player.position = room.clamp_actor(authored_arena.position+authored_arena.size*Vector2(.94,.91), Balance.PLAYER_RADIUS)
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
	get_window().size = Vector2i(1280,720)
	await frames()
	await capture_interface_pages()
	app.set_process(false)
	if is_instance_valid(app.music): await app.music.wait_for_cleanup()
	app.free()
	Game.run = null
	await frames(2)
	print("APPROVED_UI_RESULT checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func capture_interface_pages() -> void:
	# Visual sweep uses the real routes and read-only modals. It never confirms a
	# purchase, exit, profile reset or loss of the user's save (profile is isolated).
	app.show_pause()
	await capture("pause")
	app._clear_modals()
	app.show_combat_details()
	await capture("skill_details")
	app._clear_modals()
	app.show_attributes()
	await capture("attributes")
	app._clear_modals()
	app.settings_tab = "general"
	app.show_settings()
	await capture("settings")
	app._clear_modals()
	app.settings_tab = "controls"
	app.show_settings()
	await capture("controls")
	app._clear_modals()
	app.show_abandon()
	await capture("abandon")
	app._clear_modals()
	app.show_camp()
	await capture("camp")
	for page: String in ["heroes","skills","inventory","shop","upgrade"]:
		app.show_workshop(page)
		await capture("workshop_"+page)
	app.show_demo_select()
	await capture("hero_select")
	app.show_menu()
	await capture("menu")
	app._request_new_profile()
	await capture("new_profile")
	app._clear_modals()
	Game.finish_run("abandoned")
	await frames()
	app.selected_biome = "B01"
	app._start_run()
	await frames()
	await capture("relic_offer")
	app._clear_modals()
	if is_instance_valid(app.room): app.room.process_mode = Node.PROCESS_MODE_DISABLED
	app.show_expedition_exit()
	await capture("save_exit")
	app._clear_modals()
	app.show_expedition()
	await capture("route")
	app._clear_modals()
	Words.set_locale("en")
	app.show_expedition_exit()
	await capture("save_exit_en")
	app._clear_modals()
	Words.set_locale("zh_CN")
