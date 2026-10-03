extends Node
## Deterministic real-engine frames and a live-physics death check, with a test profile.

var app: Node
var room: Node2D
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ",description)
	if not condition:
		failures += 1

func frames(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func clear_room() -> void:
	room.process_mode = Node.PROCESS_MODE_DISABLED
	for enemy in room.enemies.get_children():
		enemy.free()
	for projectile in room.projectiles.get_children():
		projectile.free()
	room.effects.clear()
	room.gold_drops.clear()
	Game.run.relics.clear()
	room.player.position = Vector2(470,400)
	room.player.aim_direction = Vector2.RIGHT
	room.player.queue_redraw()
	room.queue_redraw()

func acquire(id: String) -> void:
	room.player.position = room.RELIC_POSITIONS[id]
	room.release_gate = false
	room.interact()
	check(Game.run.relics.has(id),"real station interaction equips " + id)
	room.player.position = Vector2(470,400)

func capture(filename: String) -> void:
	room.queue_redraw()
	for actor in room.enemies.get_children():
		actor.queue_redraw()
	await frames(2)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var frame := get_viewport().get_texture().get_image()
		check(frame.save_png("res://artifacts/"+filename+".png") == OK,"captured rendered frame " + filename)

func run_checks() -> void:
	if not Game.profile_path.contains("test_combat"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	Game.new_profile()
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	get_tree().root.add_child(app)
	# These combat frames target the original single-room relic stations.
	check(Game.start_run(),"start legacy room for combat rendering fixture")
	await frames(2)
	room = app.room
	room.spawn_enabled = false
	clear_room()
	acquire("split")
	var target: Node2D = room.spawn_enemy(Vector2(710,400))
	target.state = &"chase"
	room.spawn_enemy(Vector2(795,320)).state = &"chase"
	room.spawn_enemy(Vector2(805,470)).state = &"chase"
	room.fire_from_player(Vector2.RIGHT)
	var primary: Node2D = room.projectiles.get_child(0)
	primary._physics_process(0.30)
	check(room.telemetry.split_spawned == 2,"flight collision creates two real split children")
	for projectile in room.projectiles.get_children():
		if projectile.source == &"child":
			projectile._physics_process(0.07)
	await capture("relic_split")
	clear_room()
	acquire("ember")
	target = room.spawn_enemy(Vector2(710,400))
	target.state = &"chase"
	room.fire_from_player(Vector2.RIGHT)
	primary = room.projectiles.get_child(0)
	primary._physics_process(0.30)
	target.tick_burn(1.0)
	check(is_equal_approx(target.health.current,37.0) and target.burn_remaining > 0,"real flight applies visible burning and tick damage")
	await capture("relic_ember")
	clear_room()
	acquire("arc")
	Game.run.shots = 0
	target = room.spawn_enemy(Vector2(710,400))
	target.state = &"chase"
	room.spawn_enemy(Vector2(825,330)).state = &"chase"
	room.spawn_enemy(Vector2(830,465)).state = &"chase"
	for i in range(3):
		room.fire_from_player(Vector2.RIGHT)
		primary = room.projectiles.get_child(room.projectiles.get_child_count()-1)
		if i < 2:
			primary.free()
	primary._physics_process(0.30)
	check(room.telemetry.arc_hits == 2,"third primary collision creates real two-target arc")
	await capture("relic_arc")
	clear_room()
	for id in ["split","ember","arc"]:
		acquire(id)
	Game.run.shots = 2
	target = room.spawn_enemy(Vector2(710,400))
	target.state = &"chase"
	room.spawn_enemy(Vector2(795,320)).state = &"chase"
	room.spawn_enemy(Vector2(805,470)).state = &"chase"
	room.fire_from_player(Vector2.RIGHT)
	primary = room.projectiles.get_child(0)
	primary._physics_process(0.30)
	check(target.burn_remaining > 0 and room.projectiles.get_child_count() <= 3,"all three coexist within bounded source rules")
	await capture("relic_combined")
	# Use actual live physics at 8x simulation speed to complete a real flight kill.
	clear_room()
	room.player.position = Vector2(430,400)
	target = room.spawn_enemy(Vector2(690,400))
	target.state = &"chase"
	room.release_gate = false
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	Engine.time_scale = 8.0
	var stats: Dictionary = room.telemetry
	var kills_before: int = stats.kills
	for i in range(180):
		if stats.kills > kills_before:
			break
		if is_instance_valid(target):
			room.player.aim_direction = (target.position-room.player.position).normalized()
			room.player.fire(room.player.aim_direction)
		await get_tree().physics_frame
	check(stats.kills > kills_before,"live physics: actual firing, projectile travel and collisions kill enemy")
	if not room.gold_drops.is_empty():
		room.player.position = room.gold_drops[0].at
	await frames(2)
	check(Game.run.gold == 17,"live physics: dropped gold is collected")
	# A stationary player must eventually die to telegraphed enemy attacks.
	for at in [Vector2(620,400),Vector2(550,320),Vector2(550,480)]:
		room.spawn_enemy(at)
	room.player.invulnerable = 0
	for i in range(500):
		if Game.run == null:
			break
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	check(Game.run == null and Game.last_result.outcome == "death","live physics: pursuing enemies complete windups and kill player")
	check(Game.last_result.retained == 3 and Game.profile.permanent_gold == 3,"live death settles collected 17 gold as floor(20%)=3")
	await frames(3)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/live_combat_death.png")
	print("RENDERED COMBAT TESTS: ",checks-failures,"/",checks," passed; real renderer=",DisplayServer.get_name())
	get_tree().quit(1 if failures else 0)
