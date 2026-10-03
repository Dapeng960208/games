extends Node
## Narrow GPU evidence: a natural production first wave, then updated pool art.
var checks: int = 0
var failures: int = 0
var room: RoomController

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)

func _frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	room.camera.follow_target()
	room.camera.force_update_scroll()
	room.queue_redraw()
	room.enemy_props.queue_redraw()
	await _frame()
	await _frame()
	if DisplayServer.get_name() != "headless":
		check(get_viewport().get_texture().get_image().save_png("res://artifacts/"+name+".png")==OK,"saved "+name)

func _run() -> void:
	if not Game.profile_path.contains("test_room_props_followup_render"):
		get_tree().quit(2)
		return
	check(Game.new_profile(),"isolated real profile")
	var app: Node = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	check(Game.start_run(),"actual production run starts")
	room = app.room
	check(room.layout_id=="L01","production entrance is L01")
	check(room.activated_encounters.has(0),"production _ready/_update_encounters activates first region")
	check(room._living_enemy_count()==5,"production first wave naturally contains five enemies")
	var entered_at: Vector2 = room.player.position
	# Normal input and room/enemy physics run for one second. No enemy placement,
	# substitute profile, manual actor construction or cleared crowd is involved.
	room.release_gate = false
	Input.action_press("move_right")
	for frame_index: int in range(60):
		await get_tree().physics_frame
	Input.action_release("move_right")
	room.process_mode = Node.PROCESS_MODE_DISABLED
	check(room.player.position.x>entered_at.x+100,"player genuinely walks into the first region")
	check(room._living_enemy_count()==5,"all five first-wave enemies remain in the natural simulation")
	check(room.camera.zoom.is_equal_approx(Vector2(.85,.85)),"normal production camera scale")
	var enemy_report: Array = []
	for enemy: EnemyActor in room.enemies.get_children():
		if enemy.is_alive():
			enemy_report.append({"enemy_id":enemy.profile.enemy_id,"position":[enemy.position.x,enemy.position.y]})
	var report: FileAccess = FileAccess.open(AssetCatalog.resolve("res://artifacts/room_encounter_L01.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"source":"productionfirstwave","elapsed_physics_frames":60,"seed":room.layout_seed,"player":[room.player.position.x,room.player.position.y],"zoom":.85,"enemies":enemy_report},"\t"))
	await _capture("room_encounter_L01")
	room.spawn_enabled = false
	check(room.load_room_layout("L21",-1,8441),"real L21 room loads")
	room.player.position = Vector2(460,890)
	if not room.valid_ground(room.player.position,24):
		room.player.position = room.enemy_props.props[0].position
	await _capture("room_props_L21")
	print("ROOM_PROPS_FOLLOWUP_RENDER: %d checks; %d failures; productionfirstwave=%d" % [checks,failures,enemy_report.size()])
	get_tree().quit(0 if failures==0 else 1)
