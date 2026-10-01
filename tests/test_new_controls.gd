extends Node
## Focused production controls: mapped click/A/W, legal routes and auto-hit gates.

const RoomScene = preload("res://scenes/room.tscn")
const Bindings = preload("res://scripts/core/control_bindings.gd")
var stage: SubViewport
var room: MineRoom
var checks := 0
var failures := 0
var mouse_at := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("NEW CONTROLS: " + label)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func aim(at: Vector2) -> void:
	mouse_at = room.get_canvas_transform() * at
	var event := InputEventMouseMotion.new()
	event.position = mouse_at
	event.global_position = mouse_at
	stage.push_input(event, true)

func mapped(action: String, pressed: bool) -> void:
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate()
	if event is InputEventMouseButton:
		event.position = mouse_at
		event.global_position = mouse_at
		event.pressed = pressed
	else:
		event.pressed = pressed
		event.echo = false
	Input.parse_input_event(event)

func press(action: String) -> void:
	mapped(action, true)
	await frames()
	mapped(action, false)

func _run() -> void:
	if not Game.profile_path.contains("test_new_controls"):
		get_tree().quit(2)
		return
	get_tree().create_timer(40.0).timeout.connect(func(): push_error("Controls timeout"); get_tree().quit(1))
	AudioServer.set_bus_mute(0, true)
	check(Game.new_profile() and Game.start_run(), "isolated real run")
	Bindings.install()
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.handle_input_locally = true
	add_child(stage)
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	stage.add_child(room)
	room.set_physics_process(false)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	room.camera.set_physics_process(false)
	room.combat_audio.audible = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(430, 350)
	Game.run.level = 8
	Game.run.stats = StatResolver.resolve("CH01", 8, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.resource = 100.0
	await frames(6)
	room.obstructions.assign([Rect2(570,280,80,150)])
	aim(Vector2(750,350))
	await press("click_move")
	check(room.player.click_navigation.is_active(), "left mouse starts route")
	check(room.player.click_navigation.path.size() >= 3, "route turns around blocking prop")
	var searches: int = room.player.click_navigation.route_searches
	await frames(210)
	check(room.player.position.distance_to(Vector2(750,350)) <= 4.0, "automatic walking reaches clicked ground without crossing wall")
	check(room.player.click_navigation.route_searches == searches, "unchanged route never re-searches per frame")
	check(int(room.telemetry.shots) == 0, "left-click movement produces no attack")
	check(not room.player.request_move(Vector2(600,350)) and not room.player.click_navigation.is_active(), "invalid ground cancels movement instead of walking into wall")
	room.player.position = Vector2(560,270)
	check(room.valid_ground(room.player.position, Balance.PLAYER_RADIUS), "rounded prop corner is real legal ground")
	check(room.player.request_move(Vector2(430,350)), "new click can escape a rounded prop corner")
	await frames(75)
	check(room.player.position.distance_to(Vector2(430,350)) <= 4.0, "corner click reaches destination without sticking")
	room.obstructions.clear()
	room.player.position = Vector2(430,350)
	var target: MineEnemy = room.spawn_enemy(Vector2(490,350), "M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	aim(target.position)
	await press("attack")
	await frames(9)
	check(int(room.telemetry.shots) == 1 and target.health.current < 10000.0, "mapped A commits and resolves ordinary attack")
	await press("skill_secondary")
	await frames(14)
	check(room.player.abilities.cast_serial == 1 and float(room.player.cooldowns.secondary) > 0.0, "mapped W skill chains after the basic hit")
	room.player.cancel_actions()
	room.player.shot_cooldown = 0.0
	# The chained sweep legitimately pushes its victim outside melee range.
	# Use a fresh nearby training target for the automatic aim assertion.
	target.free()
	target = room.spawn_enemy(Vector2(490,350), "M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	Game.profile.settings["auto_attack"] = true
	aim(Vector2(250,350))
	var hp_before: float = target.health.current
	var at: Vector2 = room.player.position
	await frames(12)
	check(target.health.current < hp_before, "automatic melee targets enemy even when mouse faces away")
	check(room.player.position == at, "automatic attack does not start chasing")
	room.player.cancel_actions()
	room.player.shot_cooldown = 0.0
	room.obstructions.assign([Rect2(460,320,12,60)])
	check(room.player.auto_attack_target() == null, "automatic attack ignores enemy behind cover")
	var shots: int = int(room.telemetry.shots)
	await frames(12)
	check(int(room.telemetry.shots) == shots, "cover prevents automatic ordinary attack")
	room.obstructions.clear()
	room.pointer_input_blocked = true
	check(not room.player.request_move(Vector2(800,350)), "HUD pointer capture rejects walking command")
	await frames(12)
	check(int(room.telemetry.shots) == shots, "HUD pointer capture suppresses automatic attack")
	room.pointer_input_blocked = false
	room.pointer_release_gate = false
	Game.profile.settings["auto_attack"] = false
	room.player.request_move(Vector2(800,350))
	get_tree().paused = true
	check(not room.player.click_navigation.is_active(), "pause clears stale click route")
	get_tree().paused = false
	await frames()
	var before_move: Vector2 = room.player.position
	mapped("move_up", true)
	await frames(12)
	mapped("move_up", false)
	check(room.player.position.y < before_move.y - 15.0, "optional mapped directional movement works")
	room.player.request_move(Vector2(800,350))
	check(room.player.start_dash(Vector2.RIGHT) and not room.player.click_navigation.is_active(), "dash cancels stale click route")
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await frames(2)
	print("NEW CONTROLS ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
