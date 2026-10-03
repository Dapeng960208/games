extends Node
## Real production screens, four regions and persisted comfort controls.
## Captures are evidence of the implementation, not the earlier concept art.

const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
var app: Node
var checks := 0
var failures := 0
var measurements: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()
	get_tree().create_timer(90.0).timeout.connect(func(): push_error("Storybook suite timed out"); get_tree().quit(1))

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("STORYBOOK: " + label)

func frames(count: int = 3) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func capture(name: String) -> void:
	await frames(3)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var frame: Image = get_viewport().get_texture().get_image()
	check(not frame.is_empty(), "nonempty production frame " + name)
	check(frame.save_png("res://artifacts/storybook_" + name + ".png") == OK, "saved " + name)

func _run() -> void:
	if not Game.profile_path.contains("test_storybook_rebuild"):
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280,720)
	check(Game.new_profile(), "isolated profile")
	check(not bool(Game.profile.settings.get("camera_shake", true)), "new profile defaults to stable camera")
	Game.set_setting("camera_shake", true)
	check(bool(Game.profile.settings.camera_shake), "camera switch accepted by production setting API")
	Game.set_setting("camera_shake", "invalid")
	check(bool(Game.profile.settings.camera_shake), "invalid camera switch value cannot alter saved preference")
	Game.set_setting("camera_shake", false)
	var store := ProfileStore.new(Game.profile_path)
	var document: Dictionary = store.load_document()
	check(not bool(document.get("profile", {}).get("settings", {}).get("camera_shake", true)), "stable camera preference survives persisted reload")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	await capture("menu_1280")
	app.show_camp()
	await capture("camp_1280")
	app.show_settings()
	check(not app.screen.find_children("CameraShakeSetting", "Button", true, false).is_empty() or not app.ui.find_children("CameraShakeSetting", "Button", true, false).is_empty(), "camera comfort setting is discoverable")
	await capture("settings_1280")
	app._pop_modal()
	app.show_workshop("heroes")
	await capture("workshop_1280")
	app.show_camp()
	check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":146556}), "actual expedition starts")
	await frames(4)
	app._clear_modals()
	check(is_instance_valid(app.room) and is_instance_valid(app.hud), "production combat room and HUD installed")
	if not is_instance_valid(app.room) or not is_instance_valid(app.hud):
		get_tree().quit(1)
		return
	var room: Node2D = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	for item: Dictionary in [
		{"id":"L05","at":Vector2(1848,1075),"enemies":["M01","M03","M06"]},
		{"id":"L09","at":Vector2(1400,900),"enemies":["M10","M11","M17"]},
		{"id":"L14","at":Vector2(1400,900),"enemies":["M19","M21","M25"]},
		{"id":"L21","at":Vector2(1400,900),"enemies":["M28","M31","M35"]}
	]:
		# Deterministic visual fixtures enter through the same production
		# preparation/install path as a committed expedition node. Direct
		# load_room_layout only builds geometry and has no objective host.
		var context: Dictionary = {"room_id":item.id,"role":"branch","biome_id":Catalog.room(item.id).biome_id,"node_index":1,"node_count":6,"difficulty":0,"seed":146556,"phase":"combat","expedition":true}
		var prepared: Dictionary = room.prepare_expedition_node(context)
		check(bool(prepared.get("valid",false)), "actual task room prepares " + item.id)
		if not bool(prepared.get("valid",false)):
			room.discard_prepared_expedition_node(prepared)
			continue
		room.apply_prepared_expedition_node(prepared)
		for actor in room.enemies.get_children(): actor.free()
		room.player.position = room.objectives.safe_point(item.at, Balance.PLAYER_RADIUS)
		room.player.aim_direction = Vector2.RIGHT
		check(room.valid_ground(room.player.position,Balance.PLAYER_RADIUS), "showcase point is real walkable ground " + item.id)
		var offsets := [Vector2(-270,-145),Vector2(300,-135),Vector2(270,125)]
		for index in item.enemies.size():
			var at: Vector2 = room.objectives.safe_point(room.player.position + offsets[index],32)
			var enemy: Node2D = room.spawn_enemy(at,item.enemies[index])
			check(is_instance_valid(enemy), "actual authored monster " + item.enemies[index])
			if is_instance_valid(enemy):
				enemy.set_physics_process(false)
				enemy.set_process(false)
		room.camera.follow_target()
		room.camera.force_update_scroll()
		room.player.queue_redraw()
		# This fixture freezes simulation after installation. Apply the normal
		# foreground fade once so captures reflect the live game's visibility.
		for body: Node in room.find_children("*", "Node2D", true, false):
			if body.get_script() != null and body.get_script().resource_path == "res://scripts/presentation/world/room_depth_sprite.gd":
				body._physics_process(0.25)
		room.objectives.sync_body_layer()
		app.hud.refresh()
		check(room.layout.prop_instances.size() >= 4 and room.layout.prop_instances.size() <= 8, "sparse solid obstacle budget " + item.id)
		check(bool(Layouts.validate_layout(room.layout).valid), "required routes remain connected " + item.id)
		check(room.get_node("MineBackdrop").floor_texture != null, "new floor artwork loaded " + item.id)
		await capture(item.id + "_1280")
		if item.id == "L05":
			get_window().size = Vector2i(1920,1080)
			await capture("L05_1920")
			get_window().size = Vector2i(1280,720)
		app.show_combat_details("q")
		await capture(item.id + "_details_1280")
		app._pop_modal()
	app.show_expedition()
	await capture("route_1280")
	app._pop_modal()
	app.show_attributes()
	await capture("attributes_1280")
	app._pop_modal()
	app._toggle_language()
	check(Words.locale == "en" and Game.profile.settings.language == "en", "real language action updates locale and saved setting")
	app._clear_modals()
	await frames(3)
	var cjk := RegEx.new()
	cjk.compile("[\\x{4e00}-\\x{9fff}]")
	check(cjk.search(app.hud.region_label.text) == null, "real English HUD region title is localized")
	await capture("english_1280")
	app._toggle_language()
	check(Words.locale == "zh_CN" and Game.profile.settings.language == "zh_CN", "real language action restores Chinese")
	app._clear_modals()
	app.set_process(false)
	if is_instance_valid(app.music):
		check(await app.music.wait_for_cleanup(), "production music playback releases before test exit")
	app.free()
	await frames(2)
	print("STORYBOOK REBUILD: ",checks," checks; ",failures," failures; renderer=",DisplayServer.get_name())
	get_tree().quit(0 if failures==0 else 1)
