extends Node
## Isolated real-engine behavioral checks. Never writes the production profile.
## godot --headless --path . res://tests/combat/test_combat.tscn -- --test-profile=user://test_combat/profile.json

const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
var room: RoomController
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

func dummy(at := Vector2(650,350)) -> EnemyActor:
	var enemy := room.spawn_enemy(at)
	if enemy != null:
		enemy.state = &"chase"
	return enemy

func shot(at: Vector2, kind: StringName = &"primary") -> ProjectileActor:
	return room.spawn_projectile(at, Vector2.RIGHT, Balance.SHOT_DAMAGE if kind == &"primary" else Balance.SHOT_DAMAGE * Balance.SPLIT_RATIO, kind)

func _run() -> void:
	if not Game.profile_path.contains("test_combat"):
		push_error("Refusing non-test profile; pass -- --test-profile=user://test_combat/profile.json")
		quit(2)
		return
	for action in ["move_left","move_right","move_up","move_down","attack","dash","interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.select_hero("CH02") and Game.start_run(), "fresh scout run starts")
	Game.run.stats = StatResolver.resolve("CH02", 1, {}, {})
	Game.run.loadout_snapshot.clear()
	Game.run.stats["crit_chance"] = 0.0
	room = RoomScene.instantiate()
	room.geometry_enabled = false # This suite isolates combat; heroes covers real walls.
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
	check(target.body_texture != null and target.body_texture.get_image().has_mipmaps(), "enemy body uses mipmapped sampling at battlefield scale")
	check(target.visible_status_ids().is_empty(), "enemy starts without false status icons")
	for id: String in ["burn", "shock", "chill", "corrosion"]:
		target.apply_status(id, 0.0, 0.5)
	check(target.visible_status_ids() == ["burn", "shock", "chill", "corrosion"], "only actually active states populate enemy icons")
	target.tick_statuses(0.51)
	check(target.visible_status_ids().is_empty(), "expired states remove their enemy icon")
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
	var child: ProjectileActor
	for candidate in room.projectiles.get_children():
		if candidate.source == &"child":
			child = candidate
	check(child != null and is_equal_approx(child.damage,9.6), "child damage is 40 percent of scout H")
	var second := dummy(Vector2(720,380))
	child.hit(second)
	check(is_equal_approx(second.health.current,50.4) and room.telemetry.split_spawned == 2, "child damages once without recursive split")
	clear_actors()
	Game.run.relics.assign(["ember"])
	target = dummy()
	primary = shot(Vector2(620,350))
	primary.hit(target)
	# Stable save alias "ember" now follows the selected profession. CH02's
	# published 倒钩弹芯 applies physical bleed; only CH03 gets magic burn.
	check(target.status.has("bleed") and not target.status.has("burn") and is_equal_approx(float(target.status.states.bleed.remaining),3.0), "scout weapon hit applies three-second bleed, not a mage burn")
	target.tick_statuses(1.0)
	check(is_equal_approx(target.health.current,37.6), "scout bleed snapshots 0.10 AD per full second")
	check(target.last_damage_context.damage_type == "physical" and target.last_damage_context.proc_depth == 1 and not target.last_damage_context.equipment_eligible and not target.last_damage_context.original_basic, "bleed retains physical derived-damage context")
	# Refresh through another real primary hit, not the legacy apply_burn helper.
	var refresh := shot(Vector2(620,350))
	refresh.hit(target)
	check(is_equal_approx(target.health.current,17.6) and is_equal_approx(float(target.status.states.bleed.remaining),3.0), "second weapon hit refreshes one bleed state to three seconds")
	Game.run.relics.assign(["split","ember","arc"])
	var dot_projectiles: int = room.projectiles.get_child_count()
	target.tick_statuses(3.0)
	check(is_equal_approx(target.health.current,10.4) and not target.status.has("bleed"), "refreshed bleed produces three single-strength ticks then expires")
	check(room.telemetry.split_spawned == 2 and room.telemetry.arc_hits == 0 and room.projectiles.get_child_count() == dot_projectiles, "bleed cannot recursively trigger either equipped split or tracking relic")
	clear_actors()
	Game.run.relics.assign(["arc"])
	Game.run.shots = 0
	target = dummy()
	target.health.reset(100.0) # Survive the later right-button mark cash-out.
	second = dummy(Vector2(710,350))
	var third := dummy(Vector2(650,430))
	var fourth := dummy(Vector2(760,420))
	for i in range(3):
		room.fire_from_player(Vector2.RIGHT)
	var fired := room.projectiles.get_children()
	check(not fired[0].arc_ready and not fired[1].arc_ready and fired[2].arc_ready, "only every third primary qualifies for the scout tracking relic")
	fired[2].hit(target)
	# CH02's 追猎准星 marks and adds 35% AD to the original victim. The old
	# universal two-neighbor lightning expectation contradicts its class design.
	check(room.telemetry.arc_hits == 1 and is_equal_approx(target.health.current,67.6), "scout tracking relic adds exactly one 35-percent AD packet to the original victim")
	check(is_equal_approx(second.health.current,60.0) and is_equal_approx(third.health.current,60.0) and is_equal_approx(fourth.health.current,60.0), "scout tracking relic never splashes nearby enemies")
	check(room.player.class_marks.has(target.get_instance_id()) and is_equal_approx(float(room.player.class_marks[target.get_instance_id()].remaining),4.0), "tracking relic grants its actual four-second class mark")
	check(target.last_damage_context.damage_type == "physical" and target.last_damage_context.proc_depth == 1 and not target.last_damage_context.equipment_eligible, "tracking bonus uses physical non-recursive damage")
	fired[2].hit(target)
	check(is_equal_approx(target.health.current,67.6) and room.telemetry.arc_hits == 1, "same primary cannot repeat its tracking damage")
	room.resolve_direct_hit(target,1.0,&"secondary","",0.0,Vector2.RIGHT)
	check(is_equal_approx(target.health.current,36.6) and not room.player.class_marks.has(target.get_instance_id()), "real right-button hit consumes the mark for one 125-percent AD bonus")
	room.resolve_direct_hit(target,1.0,&"secondary","",0.0,Vector2.RIGHT)
	check(is_equal_approx(target.health.current,35.6) and room.telemetry.arc_hits == 1, "consumed mark cannot pay again or re-enter its relic trigger")
	clear_actors()
	Game.run.relics.assign(["split","ember","arc"])
	target = dummy()
	primary = shot(Vector2(620,350))
	primary.arc_ready = true
	primary.trigger_budget = 0
	var split_before: int = room.telemetry.split_spawned
	primary.hit(target)
	check(room.telemetry.split_spawned == split_before and target.status.states.is_empty() and not room.player.class_marks.has(target.get_instance_id()), "exhausted trigger budget disables all class-specific secondary effects")
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
	check(is_equal_approx(Game.run.hp, hp - 14.0 * 100.0 / 108.0), "armor and hurt protection prevent simultaneous double damage")
	room.player.invulnerable = 0
	room.player.dash_remaining = 0.1
	room.player.dash_elapsed = 0.08
	check(not room.player.receive_damage(14,Vector2.ZERO), "dash grants invulnerability")
	room.player.dash_remaining = 0
	clear_actors()
	target = dummy(room.player.position + Vector2(40,0))
	target._physics_process(0.01)
	check(target.state == &"windup", "nearby enemy enters visible attack windup")
	var before_attack: float = Game.run.hp
	target._physics_process(Balance.ENEMY_WINDUP + 0.01)
	check(is_equal_approx(Game.run.hp, before_attack - 14.0 * 100.0 / 108.0) and target.state == &"recovery", "enemy attack deals mitigated damage and enters recovery")
	clear_actors()
	Game.run.relics.clear()
	room.player.position = RoomController.RELIC_POSITIONS.split
	room.interact()
	check(Game.run.relics.has("split"), "nearby interact picks up implemented relic")
	room.interact()
	check(Game.run.relics.size() == 1, "collected relic cannot be taken twice")
	room.player.position = RoomController.EXIT_POSITION
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
	room.player.cancel_actions()
	room.player.shot_cooldown = 0.0
	if not InputMap.has_action("skill_secondary"):
		InputMap.add_action("skill_secondary")
	var pointer_shots: int = room.telemetry.shots
	var pointer_at: Vector2 = room.player.position
	room.set_pointer_input_blocked(true)
	Input.action_press("attack")
	Input.action_press("skill_secondary")
	Input.action_press("move_right")
	room.player._physics_process(.02)
	check(room.telemetry.shots == pointer_shots and room.player.attack_buffer == 0.0, "HUD hover blocks mouse firing and clears queued shots")
	check(room.player.position.x > pointer_at.x, "HUD hover preserves keyboard movement")
	Input.action_release("move_right")
	room.set_pointer_input_blocked(false)
	room.player._physics_process(.02)
	check(room.telemetry.shots == pointer_shots, "leaving HUD while holding attack does not resume fire")
	Input.action_release("attack")
	room.player._physics_process(.02)
	check(not room.pointer_controls_enabled(), "held right button keeps pointer release gate closed")
	Input.action_release("skill_secondary")
	room.player._physics_process(.02)
	Input.action_press("attack")
	room.player._physics_process(.02)
	Input.action_release("attack")
	check(room.telemetry.shots == pointer_shots + 1, "fresh attack after both mouse buttons release fires once")
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
	check(await room.combat_audio.wait_for_cleanup(), "audio mixer releases all playback objects before exit")
	room.free()
	print("COMBAT TESTS: ",checks-failures,"/",checks," passed")
	quit(1 if failures else 0)
