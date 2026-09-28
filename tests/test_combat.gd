extends Node
## Isolated real-engine behavioral checks. Never writes the production profile.
## godot --headless --path . res://tests/test_combat.tscn -- --test-profile=user://test_combat/profile.json

const RoomScene = preload("res://scenes/room.tscn")
var room: MineRoom
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func quit(code: int) -> void:
	get_tree().quit(code)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func clear_actors() -> void:
	for enemy in room.enemies.get_children():
		enemy.free()
	for projectile in room.projectiles.get_children():
		projectile.free()
	room.gold_drops.clear()

func dummy(at := Vector2(650,350)) -> MineEnemy:
	var enemy := room.spawn_enemy(at)
	if enemy != null:
		enemy.state = &"chase"
	return enemy

func shot(at: Vector2, kind: StringName = &"primary") -> SparkProjectile:
	return room.spawn_projectile(at, Vector2.RIGHT, Balance.SHOT_DAMAGE if kind == &"primary" else Balance.SHOT_DAMAGE * Balance.SPLIT_RATIO, kind)

func _run() -> void:
	if not Game.profile_path.contains("test_combat"):
		push_error("Refusing non-test profile; pass -- --test-profile=user://test_combat/profile.json")
		quit(2)
		return
	for action in ["move_left","move_right","move_up","move_down","attack","dash","interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "fresh run starts")
	room = RoomScene.instantiate()
	get_tree().root.add_child(room)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	room.release_gate = false
	clear_actors()
	var start := room.player.position
	Input.action_press("move_right")
	room.player._physics_process(0.1)
	Input.action_release("move_right")
	check(room.player.position.x > start.x, "movement changes player world position")
	room.player.position = Vector2(500,350)
	check(room.player.fire(Vector2.RIGHT), "player fires real projectile")
	check(Game.run.shots == 1 and room.telemetry.shots == 1, "successful shots update real run")
	check(not room.player.fire(Vector2.RIGHT), "attack interval prevents same-frame firing")
	clear_actors()
	var target := dummy()
	var primary := shot(Vector2(610,350))
	primary._physics_process(0.1)
	check(is_equal_approx(target.health.current,40.0), "swept projectile collision damages enemy")
	primary.hit(target)
	check(is_equal_approx(target.health.current,40.0), "same projectile cannot hit twice")
	clear_actors()
	Game.run.relics.assign(["split"])
	target = dummy()
	primary = shot(Vector2(620,350))
	primary.hit(target)
	check(room.telemetry.split_spawned == 2, "split produces exactly two children")
	var child: SparkProjectile
	for candidate in room.projectiles.get_children():
		if candidate.source == &"child":
			child = candidate
	check(child != null and is_equal_approx(child.damage,8.0), "child damage is 40 percent of base")
	var second := dummy(Vector2(720,380))
	child.hit(second)
	check(is_equal_approx(second.health.current,52.0) and room.telemetry.split_spawned == 2, "child damages once without recursive split")
	clear_actors()
	Game.run.relics.assign(["ember"])
	target = dummy()
	primary = shot(Vector2(620,350))
	primary.hit(target)
	check(is_equal_approx(target.burn_remaining,3.0), "weapon hit applies three-second burn")
	target.tick_burn(1.0)
	check(is_equal_approx(target.health.current,37.0), "burn deals three damage per second")
	target.apply_burn()
	check(is_equal_approx(target.burn_remaining,3.0), "repeated burn refreshes duration")
	target.tick_burn(3.0)
	check(is_equal_approx(target.health.current,28.0) and room.telemetry.split_spawned == 2, "burn remains non-stacking and cannot trigger split")
	clear_actors()
	Game.run.relics.assign(["arc"])
	Game.run.shots = 0
	target = dummy()
	second = dummy(Vector2(710,350))
	var third := dummy(Vector2(650,430))
	var fourth := dummy(Vector2(760,420))
	for i in range(3):
		room.fire_from_player(Vector2.RIGHT)
	var fired := room.projectiles.get_children()
	check(not fired[0].arc_ready and not fired[1].arc_ready and fired[2].arc_ready, "only every third primary is arc-qualified")
	fired[2].hit(target)
	check(room.telemetry.arc_hits == 2, "arc hits at most two other targets")
	check(is_equal_approx(second.health.current,53) and is_equal_approx(third.health.current,53) and is_equal_approx(fourth.health.current,60), "arc uses 35 percent base damage and nearest targets")
	clear_actors()
	Game.run.relics.assign(["split","ember","arc"])
	target = dummy()
	primary = shot(Vector2(620,350))
	primary.arc_ready = true
	primary.trigger_budget = 0
	var split_before: int = room.telemetry.split_spawned
	primary.hit(target)
	check(room.telemetry.split_spawned == split_before and target.burn_remaining == 0, "exhausted trigger budget disables all secondary effects")
	var non_weapon := shot(Vector2(620,350), &"arc")
	var health_before := target.health.current
	non_weapon.hit(target)
	check(target.health.current == health_before and room.telemetry.split_spawned == split_before, "additional damage source cannot enter weapon trigger dispatcher")
	clear_actors()
	Game.run.relics.clear()
	target = dummy(room.player.position + Vector2(10,0))
	target.take_damage(60, &"primary")
	check(room.telemetry.kills == 1 and room.gold_drops.size() == 1, "lethal damage records kill and drops gold")
	room._update_gold(0.1)
	check(Game.run.gold == 17 and room.gold_drops.is_empty(), "gold pickup credits actual run once")
	var hp: float = Game.run.hp
	room.player.receive_damage(14,Vector2.ZERO)
	room.player.receive_damage(14,Vector2.ZERO)
	check(Game.run.hp == hp - 14, "hurt protection prevents simultaneous double damage")
	room.player.invulnerable = 0
	room.player.dash_remaining = 0.1
	check(not room.player.receive_damage(14,Vector2.ZERO), "dash grants invulnerability")
	room.player.dash_remaining = 0
	clear_actors()
	target = dummy(room.player.position + Vector2(40,0))
	target._physics_process(0.01)
	check(target.state == &"windup", "nearby enemy enters visible attack windup")
	var before_attack: float = Game.run.hp
	target._physics_process(Balance.ENEMY_WINDUP + 0.01)
	check(Game.run.hp == before_attack - Balance.ENEMY_DAMAGE and target.state == &"recovery", "enemy attack deals damage and enters recovery")
	clear_actors()
	Game.run.relics.clear()
	room.player.position = MineRoom.RELIC_POSITIONS.split
	room.interact()
	check(Game.run.relics.has("split"), "nearby interact picks up implemented relic")
	room.interact()
	check(Game.run.relics.size() == 1, "collected relic cannot be taken twice")
	room.player.position = MineRoom.EXIT_POSITION
	var events: Array[String] = []
	room.interaction_requested.connect(func(kind: String, _payload: Dictionary) -> void: events.append(kind))
	room.interact()
	check(events == ["extract"] and room.input_blocked, "nearby extraction requests confirmation and blocks gameplay input")
	room.set_input_blocked(false)
	room.release_gate = false
	Input.action_press("attack")
	room.set_input_blocked(true)
	room.set_input_blocked(false)
	room._physics_process(0.1)
	check(not room.controls_enabled(), "held attack stays blocked after resume")
	Input.action_release("attack")
	room._physics_process(0.1)
	check(room.controls_enabled(), "release enables subsequent fresh input")
	clear_actors()
	for i in range(Balance.MAX_PROJECTILES + 5):
		shot(Vector2(500,350))
	check(room.projectiles.get_child_count() == Balance.MAX_PROJECTILES, "projectile object cap is enforced")
	clear_actors()
	for i in range(Balance.MAX_ENEMIES + 5):
		dummy(Vector2(800,350))
	check(room.enemies.get_child_count() == Balance.MAX_ENEMIES, "enemy object cap is enforced")
	clear_actors()
	# Use the live SceneTree to prove pause freezes both character and projectile.
	target = dummy(Vector2(900,350))
	primary = shot(Vector2(500,350))
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = true
	var enemy_at := target.position
	var projectile_at := primary.position
	await get_tree().create_timer(0.08,true).timeout
	check(target.position == enemy_at and primary.position == projectile_at, "SceneTree pause freezes enemy and projectile")
	get_tree().paused = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	clear_actors()
	Game.finish_run("extracted")
	room.free()
	print("COMBAT TESTS: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)
