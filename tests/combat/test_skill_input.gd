extends Node
## Input regression fixture: real mapped keyboard/mouse presses and automatic
## player physics, with a stationary training target. No manual player ticks.

const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
var stage: SubViewport
var room: RoomController
var target: EnemyActor
var events: Array[Dictionary] = []
var checks := 0
var failures := 0
var mouse_at := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SKILL INPUT FAIL: " + label)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func aim(at: Vector2) -> void:
	mouse_at = room.get_canvas_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = mouse_at
	motion.global_position = mouse_at
	stage.push_input(motion, true)

func input(action: String, pressed: bool) -> void:
	# parse_input_event updates the Input action state consumed by production
	# physics. Pointer position is independently local to our SubViewport.
	var source: InputEvent = InputMap.action_get_events(action)[0]
	var event: InputEvent = source.duplicate()
	if event is InputEventMouseButton:
		event.position = mouse_at
		event.global_position = mouse_at
		event.pressed = pressed
	elif event is InputEventKey:
		event.pressed = pressed
		event.echo = false
	Input.parse_input_event(event)

func release_all() -> void:
	for action: String in ["attack", "skill_q", "skill_secondary", "skill_f", "skill_ultimate", "dash"]:
		input(action, false)

func observe(slot: String, reason: String, details: Dictionary) -> void:
	events.append({"slot":slot, "reason":reason, "details":details.duplicate(true),
		"hp":target.health.current if is_instance_valid(target) else 0.0,
		"shots":int(room.telemetry.shots), "shot_cooldown":room.player.shot_cooldown,
		"resource":Game.run.resource if Game.run != null else -1.0})

func count_reason(reason: String, slot: String = "") -> int:
	var count := 0
	for event: Dictionary in events:
		if event.reason == reason and (slot.is_empty() or event.slot == slot):
			count += 1
	return count

func event_for(reason: String, slot: String = "") -> Dictionary:
	for event: Dictionary in events:
		if event.reason == reason and (slot.is_empty() or str(event.slot) == slot):
			return event
	return {}

func fixture(hero: String = "CH01", level: int = 8) -> void:
	get_tree().paused = false
	release_all()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	Game.run.hero_id = hero
	Game.run.level = level
	Game.run.stats = StatResolver.resolve(hero, level, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	stage.add_child(room)
	room.set_physics_process(false)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	room.camera.set_physics_process(false)
	room.combat_audio.audible = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430, 350)
	room.player.skill_input_feedback.connect(observe)
	target = room.spawn_enemy(Vector2(490, 350), "M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	aim(target.position)
	# Asset/audio prewarming is synchronous on the first fixture. Let its
	# startup catch-up physics drain before measuring a 120 ms input window.
	await frames(6)
	events.clear()
	check(room.player.aim_direction.dot(Vector2.RIGHT) > .99, "engine local pointer sets production aim")

func press_skill(slot: String) -> void:
	input("skill_" + slot, true)
	await frames(1)
	input("skill_" + slot, false)

func start_basic() -> void:
	input("attack", true)
	await frames(1)
	check(Input.is_action_pressed("attack"), "mapped left mouse is held in Input singleton")
	check(room.player.attack_remaining > 0.0 and not room.player.attack_resolved, "normal physics starts committed hammer windup")

func test_held_basic(slot: String, during_windup: bool) -> void:
	await fixture()
	await start_basic()
	if not during_windup:
		await frames(8)
		check(room.player.attack_resolved and room.player.shot_cooldown > 0.0, "basic strike resolves before recovery input")
	var cost: float = room.player.skill_definition(slot).cost
	await press_skill(slot)
	if during_windup:
		check(count_reason("queued", slot) == 1 and not room.player.buffered_skill.is_empty(), "windup press is visibly queued once: " + slot)
		check(room.player.abilities.cast_serial == 0 and target.health.current == 10000.0, "queue cannot cancel basic damage windup or cast early")
	await frames(10)
	var accepted: Dictionary = event_for("accepted", slot)
	check(count_reason("accepted", slot) == 1, "held basic yields exactly one requested skill: " + slot)
	check(not accepted.is_empty() and float(accepted.hp) < 10000.0, "real basic damage occurs before skill acceptance")
	check(not accepted.is_empty() and int(accepted.shots) == 1 and float(accepted.shot_cooldown) > 0.0, "queued skill beats second held basic without resetting basic cooldown")
	check(not accepted.is_empty() and is_equal_approx(float(accepted.resource), 100.0 - cost), "skill spends cost once after hit")
	check(room.player.buffered_skill.is_empty(), "accepted input leaves no delayed request")
	await frames(45)
	input("attack", false)
	check(count_reason("accepted", slot) == 1 and int(room.telemetry.shots) >= 2, "held basic resumes but skill does not repeat")
	check(float(room.player.cooldowns[slot]) > 0.0, "accepted skill owns real cooldown")
	check(count_reason("queued") == 1 if during_windup else count_reason("queued") <= 1, "windup buffers once and the brief contact recovery never duplicates its follow-up")

func test_fifo() -> void:
	await fixture()
	await start_basic()
	await press_skill("q")
	await press_skill("secondary")
	check(room.player.buffered_skill.get("slot", "") == "q" and room.player.combo_queue.size() == 2, "two deliberate skill presses preserve their input order")
	await frames(38)
	release_all()
	check(count_reason("accepted", "q") == 1 and count_reason("accepted", "secondary") == 1, "basic chains into Q and then one right-click skill")
	check(float(room.player.cooldowns.q) > 0.0 and float(room.player.cooldowns.secondary) > 0.0 and room.player.abilities.cast_serial == 2, "both actual skills retain their committed cooldowns")

func test_failures() -> void:
	await fixture("CH01", 1)
	await press_skill("secondary")
	check(count_reason("locked") == 1 and room.player.last_cast_error == "locked", "locked input explains failure")
	check(event_for("locked").details.unlock == 2 and event_for("locked").details.level == 1, "locked feedback provides unlock values")
	check(Game.run.resource == 100.0 and room.player.abilities.cast_serial == 0, "locked input commits nothing")
	await fixture()
	Game.run.resource = 0.0
	await press_skill("q")
	check(count_reason("resource") == 1 and event_for("resource").details.cost == 20.0, "resource failure reports actual cost")
	check(Game.run.resource == 0.0 and room.player.cooldowns.q == 0.0, "resource failure does not charge or start cooldown")
	await fixture()
	await press_skill("q")
	await press_skill("secondary")
	check(count_reason("busy") == 1 and room.player.buffered_skill.is_empty(), "input before the bounded Q follow-up window rejects explicitly")
	await frames(30)
	await press_skill("q")
	check(count_reason("cooldown") == 1 and event_for("cooldown").details.remaining > 0.0, "cooldown failure carries remaining time")
	await fixture()
	await start_basic()
	check(not room.player.cast_skill("q", target.position) and room.player.buffered_skill.is_empty(), "public cast_skill false has no hidden delayed request")
	release_all()
	check(room.player.last_cast_error == "busy" and event_for("busy").details.cause == "attack_windup", "API windup guard updates unified failure")
	await fixture("CH03")
	aim(room.player.position + Vector2(500, 0))
	await press_skill("secondary")
	check(count_reason("invalid_ground") == 1 and event_for("invalid_ground").details.cause == "out_of_range", "ground cast distinguishes excessive range")
	check(room.player.abilities.last_failure == "invalid_ground" and event_for("invalid_ground").details.range == 220.0, "legacy ground error remains compatible and reports range")
	check(Game.run.resource == 100.0 and room.player.cooldowns.secondary == 0.0, "out of range commits nothing")
	events.clear()
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(Vector2(470, 320), Vector2(70, 70))])
	aim(Vector2(500, 350))
	await press_skill("secondary")
	check(count_reason("invalid_ground") == 1 and event_for("invalid_ground").details.cause == "blocked_ground", "blocked surface gets different cause from range")
	check(Game.run.resource == 100.0 and room.player.cooldowns.secondary == 0.0, "blocked surface commits nothing")

func test_cleanup() -> void:
	for mode: String in ["cancel", "dash", "block", "pause", "death", "pointer"]:
		await fixture()
		await start_basic()
		await press_skill("secondary" if mode == "pointer" else "q")
		check(not room.player.buffered_skill.is_empty(), mode + " fixture has real pending input")
		release_all()
		match mode:
			"cancel": room.player.cancel_actions()
			"dash":
				input("dash", true)
				await frames(1)
				input("dash", false)
				await press_skill("q")
				check(count_reason("dashing") == 1 and room.player.last_cast_error == "dashing", "dash input rejects skills with feedback")
			"block": room.set_input_blocked(true)
			"pause":
				get_tree().paused = true
				check(room.player.buffered_skill.is_empty(), "pause notification clears without running player physics")
				get_tree().paused = false
			"death": Game.run.hp = 0.0
			"pointer": room.set_pointer_input_blocked(true)
		await frames(15)
		check(room.player.buffered_skill.is_empty() and room.player.abilities.cast_serial == 0, mode + " discards request without late release")
		check(room.player.cooldowns.q == 0.0 and room.player.cooldowns.secondary == 0.0, mode + " discarded request never charges cooldown")
		if mode == "death": Game.run.hp = Game.run.max_hp
	await fixture()
	await start_basic()
	await press_skill("q")
	var saved_player: HeroActor = room.player
	room.remove_child(saved_player)
	check(saved_player.buffered_skill.is_empty(), "leaving room tree clears pending request")
	saved_player.free()
	release_all()

func run_checks() -> void:
	if not Game.profile_path.contains("test_skill_input"):
		get_tree().quit(2)
		return
	get_tree().create_timer(60.0).timeout.connect(func(): push_error("Skill input fixture timeout"); get_tree().quit(1))
	AudioServer.set_bus_mute(0, true)
	var input_installer: Node = load(AssetCatalog.resolve("res://scripts/presentation/app/main.gd")).new()
	input_installer._install_inputs()
	input_installer.free()
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.handle_input_locally = true
	stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(stage)
	check(Game.new_profile() and Game.start_run(), "isolated skill input profile starts")
	for slot: String in ["q", "secondary"]:
		await test_held_basic(slot, true)
		await test_held_basic(slot, false)
	await test_fifo()
	await test_failures()
	await test_cleanup()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	await frames(2)
	print("SKILL INPUT ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
