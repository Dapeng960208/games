extends Node
## Focused production controls: actual right/left mouse + A alias, held routes
## and UI release gates. Production physics owns the movement and strikes.

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

func mouse(button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = mouse_at
	event.global_position = mouse_at
	event.pressed = pressed
	Input.parse_input_event(event)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _run() -> void:
	if not Game.profile_path.contains("test_new_controls"):
		get_tree().quit(2)
		return
	get_tree().create_timer(40.0).timeout.connect(func(): push_error("Controls timeout"); get_tree().quit(1))
	AudioServer.set_bus_mute(0, true)
	check(Game.new_profile() and Game.start_run(), "isolated real run")
	Bindings.install()
	check(InputMap.action_get_events("click_move")[0] is InputEventMouseButton and InputMap.action_get_events("click_move")[0].button_index == MOUSE_BUTTON_RIGHT, "right mouse is default movement")
	check(InputMap.action_get_events("attack")[0] is InputEventMouseButton and InputMap.action_get_events("attack")[0].button_index == MOUSE_BUTTON_LEFT, "left mouse is default ordinary attack")
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
	mouse(MOUSE_BUTTON_RIGHT, true)
	await frames()
	mouse(MOUSE_BUTTON_RIGHT, false)
	check(room.player.click_navigation.is_active(), "actual right mouse starts route")
	check(room.player.click_navigation.path.size() >= 3, "route turns around blocking prop")
	var searches: int = room.player.click_navigation.route_searches
	await frames(210)
	check(room.player.position.distance_to(Vector2(750,350)) <= 4.0, "automatic walking reaches clicked ground without crossing wall")
	check(room.player.click_navigation.route_searches == searches, "unchanged route never re-searches per frame")
	check(int(room.telemetry.shots) == 0, "right-click movement produces no attack or W skill")
	check(room.player.abilities.cast_serial == 0, "right-click movement never invokes a skill")
	room.player.position = Vector2(430,350)
	aim(Vector2(750,350))
	mouse(MOUSE_BUTTON_RIGHT, true)
	await frames()
	searches = room.player.click_navigation.route_searches
	await frames(12)
	check(room.player.click_navigation.route_searches == searches, "holding right mouse with stable target reuses cached route")
	aim(Vector2(800,350))
	await frames()
	check(room.player.click_navigation.route_searches == searches + 1, "held target movement of 50px updates path")
	aim(Vector2(850,350))
	await frames()
	check(room.player.click_navigation.route_searches == searches + 1, "held replanning respects 0.16 second interval")
	await frames(12)
	check(room.player.click_navigation.route_searches == searches + 2 and room.player.click_navigation.goal.distance_to(Vector2(850,350)) < 1, "latest held cursor becomes next destination after interval")
	aim(Vector2(860,350))
	await frames(12)
	check(room.player.click_navigation.route_searches == searches + 2, "10px cursor jitter does not re-search")
	mouse(MOUSE_BUTTON_RIGHT, false)
	room.player.clear_movement_target()
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
	mouse(MOUSE_BUTTON_LEFT, true)
	await frames()
	mouse(MOUSE_BUTTON_LEFT, false)
	await frames(9)
	check(int(room.telemetry.shots) == 1 and target.health.current < 10000.0, "actual left mouse commits ordinary attack against pointed enemy")
	check(not room.player.click_navigation.is_active(), "left mouse attack never creates a walk route")
	await press("skill_secondary")
	await frames(14)
	check(room.player.abilities.cast_serial == 1 and float(room.player.cooldowns.secondary) > 0.0, "mapped W skill chains after the basic hit")
	room.player.cancel_actions()
	room.player.shot_cooldown = 0.0
	var before_alias_shots: int = int(room.telemetry.shots)
	key(KEY_A, true)
	await frames()
	key(KEY_A, false)
	await frames(9)
	check(int(room.telemetry.shots) == before_alias_shots + 1, "actual A key remains alternate ordinary attack")
	room.player.cancel_actions()
	room.player.shot_cooldown = 0.0
	room.pointer_input_blocked = true
	mouse(MOUSE_BUTTON_LEFT, true)
	key(KEY_A, true)
	await frames(2)
	before_alias_shots = int(room.telemetry.shots)
	room.pointer_input_blocked = false
	room.pointer_release_gate = false
	mouse(MOUSE_BUTTON_LEFT, false)
	await frames(2)
	check(room.player.attack_input_held() and room.player._attack_release_required and int(room.telemetry.shots) == before_alias_shots, "HUD capture stays gated while A alias remains held after mouse release")
	key(KEY_A, false)
	await frames(2)
	check(not room.player.attack_input_held() and not room.player._attack_release_required, "releasing both attack aliases reopens gate")
	room.pointer_input_blocked = true
	mouse(MOUSE_BUTTON_RIGHT, true)
	await frames(2)
	room.pointer_input_blocked = false
	room.pointer_release_gate = false
	await frames(12)
	check(not room.player.click_navigation.is_active(), "held movement captured by HUD cannot leak after overlay closes")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await frames(2)
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
