extends Node
var app: Node
var room: RoomController
var checks: int = 0
var failures: int = 0
func _ready() -> void:
	call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	room.player.queue_redraw()
	room.queue_redraw()
	room.camera.follow_target()
	room.camera.force_update_scroll()
	await frame()
	await frame()
	if DisplayServer.get_name() != "headless":
		var image: Image = get_viewport().get_texture().get_image()
		check(image.save_png("res://artifacts/" + name + ".png") == OK, "actual world screenshot saved")
func _run() -> void:
	if not Game.profile_path.contains("test_world_visual"):
		get_tree().quit(2)
		return
	check(Game.new_profile(), "isolated profile")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	check(Game.start_run(), "actual main game run starts")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	check(room.get_node("MineBackdrop").floor_texture != null, "original floor source loaded as texture")
	room.player.position = Vector2(570,930)
	room.player.aim_direction = Vector2.RIGHT
	await capture("world_mine_entrance")
	room.player.position = room.relic_positions.split + Vector2(45,0)
	room.player.aim_direction = Vector2.LEFT
	await capture("world_station_focus")
	room.release_gate = false
	room.interact()
	await capture("world_station_equipped")
	room.player.position = Vector2(1500,1160)
	room.player.aim_direction = Vector2.RIGHT
	await capture("world_floor_seams")
	print("WORLD VISUAL: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
