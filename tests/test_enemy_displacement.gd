extends Node
## Controlled real-scene regression. The production player, enemy brain and
## skill runtime advance at 10 ms; no actor HP, damage or defense is overridden.
const RoomScene = preload("res://scenes/room.tscn")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
var room: MineRoom
var checks: int = 0
var failures: int = 0
var report: Array[Dictionary] = []
var baseline: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ENEMY DISPLACEMENT: " + message)

func fixture(id: String = "M01", distance: float = 60.0, rank: String = "normal") -> MineEnemy:
	if is_instance_valid(room): room.free()
	Game.run = null
	check(Game.start_run(), "fresh natural-health run")
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	room.enemy_skills.reset_room()
	for actor in room.enemies.get_children(): actor.free()
	for projectile in room.projectiles.get_children(): projectile.free()
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	# Resource setup only: one right-click costs 30 while a normal run starts at 20.
	Game.restore_resource(20.0)
	return room.spawn_enemy(room.player.position + Vector2(distance, 0), id, 4, {"rank":rank})

func step(duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed + 0.000001 < duration:
		var delta: float = minf(0.01, duration - elapsed)
		room.player._physics_process(delta)
		for enemy in room.enemies.get_children():
			if enemy.is_alive(): enemy._physics_process(delta)
		room.enemy_skills.advance(delta)
		elapsed += delta

func lock(enemy: MineEnemy, kind: String) -> Dictionary:
	for frame in 1600:
		var tell: Dictionary = enemy.brain.current_telegraph()
		if bool(tell.get("locked", false)) and str(tell.get("kind", "")) == kind: return tell.duplicate(true)
		step(0.01)
	check(false, enemy.enemy_id + " reaches the real locked " + kind + " phase")
	return {}

func snapshot(enemy: MineEnemy, frozen: Dictionary, hp_before: float) -> Dictionary:
	var moved: Dictionary = frozen.duplicate(true)
	moved.origin = enemy.position
	return {"hero_level":Game.run.level, "hero_attack":room.player.attack_power(), "hero_hp_before":hp_before,
		"hero_hp_after":Game.run.hp, "hero_damage":hp_before - Game.run.hp,
		"enemy_id":enemy.enemy_id, "enemy_hp":enemy.health.current, "enemy_max_hp":enemy.health.maximum,
		"frozen_origin":[frozen.origin.x, frozen.origin.y], "enemy_position":[enemy.position.x, enemy.position.y],
		"displacement":enemy.position.distance_to(frozen.origin), "phase":str(enemy.state),
		"inside_frozen_swing":room.enemy_skills.shape_contains(frozen, room.player.position, Balance.PLAYER_RADIUS),
		"inside_body_swing":room.enemy_skills.shape_contains(moved, room.player.position, Balance.PLAYER_RADIUS),
		"recovery_remaining":enemy.state_time, "authored_recovery":enemy.brain._recovery_seconds()}

func actual_hammer_repro() -> void:
	# The ordinary Lv4 variant naturally dies to this default-equipped sweep.
	# Its authored elite variant survives and receives the normal 50% push rule.
	var enemy := fixture("M01", 60.0, "elite")
	var frozen := lock(enemy, "melee")
	if frozen.is_empty(): return
	var hp_before: float = Game.run.hp
	check(room.player.cast_skill("secondary", enemy.position), "real CH01 secondary starts during the enemy lock")
	step(0.20)
	check(enemy.is_alive() and enemy.health.current < enemy.health.maximum, "natural M01 survives the actual hammer damage")
	check(enemy.position.distance_to(frozen.origin) > 0.0 and enemy.position.distance_to(frozen.origin) < 32.0, "the hammer release starts continuous movement before spending its 32.5 unit elite push")
	check(str(enemy.state) == "recovery" and enemy.brain.current_telegraph().is_empty(), "committing a reachable strong push cancels the locked melee before the body reaches its endpoint")
	step(0.14)
	check(is_equal_approx(enemy.position.distance_to(frozen.origin), 32.5) and not enemy.has_pending_displacement(), "the elite hammer push spends exactly its natural 32.5 units across multiple frames")
	step(0.08)
	var result := snapshot(enemy, frozen, hp_before)
	result["case"] = "actual_hammer_while_locked"
	report.append(result)
	print("DISPLACEMENT_REPRO ", JSON.stringify(result))
	if baseline:
		check(float(result.hero_damage) > 0.0 and bool(result.inside_frozen_swing) and not bool(result.inside_body_swing), "before fix: displaced body misses but frozen old-origin melee damages the player")
	else:
		check(float(result.hero_damage) == 0.0 and str(enemy.state) == "recovery", "large real hammer displacement cancels the pending swing without ghost damage")
		check(enemy.brain.current_telegraph().is_empty(), "cancelled melee clears its old dangerous shape")
		check(enemy.state_time >= enemy.brain._recovery_seconds() - 0.26, "cancelled melee receives its original authored recovery window")

func displacement_cases() -> void:
	for distance in [0.0, 8.0, 35.0]:
		var enemy := fixture()
		var frozen := lock(enemy, "melee")
		if frozen.is_empty(): continue
		var hp_before: float = Game.run.hp
		# Public displacement API isolates the threshold from damage and death.
		if distance > 0.0: enemy.apply_knockback(Vector2.RIGHT, distance)
		check(enemy.position.is_equal_approx(frozen.origin), "a committed push does not teleport its body: " + str(distance))
		if distance >= 28.0: check(str(enemy.state) == "recovery", "a reachable substantial push interrupts immediately before movement starts")
		step(0.42)
		var result := snapshot(enemy, frozen, hp_before)
		result["case"] = "displacement_" + str(distance)
		report.append(result)
		check((hp_before > Game.run.hp) == (distance < 28.0), "normal/small shifts still execute; substantial displacement cancels: " + str(distance))
		if distance >= 28.0: check(str(enemy.state) == "recovery", "cancelled swing enters recovery")

func independent_skills() -> void:
	for entry in [["M03", "projectile", 220.0], ["M11", "ground_area", 220.0]]:
		var enemy := fixture(entry[0], entry[2])
		var frozen := lock(enemy, entry[1])
		if frozen.is_empty(): continue
		enemy.apply_knockback(Vector2.DOWN, 65.0)
		step(0.42)
		var effects: Array = room.enemy_skills.projectiles if entry[1] == "projectile" else room.enemy_skills.hazards
		check(not effects.is_empty(), entry[0] + " retains its locked independent skill after displacement")
		var count_before: int = effects.size()
		enemy.apply_knockback(Vector2.UP, 40.0)
		step(0.05)
		check(effects.size() == count_before, entry[0] + " already released effects are not cancelled by later displacement")
		if not effects.is_empty(): check(Vector2(effects[0].origin).is_equal_approx(frozen.origin) or entry[1] == "ground_area", entry[0] + " preserves original locked projectile origin")

func paused_case() -> void:
	var enemy := fixture()
	var frozen := lock(enemy, "melee")
	if frozen.is_empty(): return
	enemy.apply_knockback(Vector2.RIGHT, 8.0)
	var at: Vector2 = enemy.position
	var pending: Vector2 = enemy.pending_displacement()
	var remaining: float = enemy.state_time
	var hp: float = Game.run.hp
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = true
	await get_tree().create_timer(0.06, true).timeout
	check(enemy.position == at and enemy.state_time == remaining and Game.run.hp == hp, "actual scene pause neither advances nor cancels a pending melee")
	check(enemy.pending_displacement() == pending, "actual scene pause preserves all unspent continuous push distance")
	get_tree().paused = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	step(0.18)
	var traveled: float = enemy.position.distance_to(at)
	# Vector2 uses float32 world coordinates: at x=1160 one representable step
	# is about 0.000122 units, exceeding is_equal_approx's relative epsilon at 8.
	check(absf(traveled - 8.0) <= 0.001 and not enemy.has_pending_displacement(), "the paused push resumes and finishes its original distance without a teleport; actual=" + str(traveled) + " pending=" + str(enemy.pending_displacement()) + " state=" + str(enemy.state))

func _run() -> void:
	if not Game.profile_path.contains("test_enemy_displacement"):
		get_tree().quit(2)
		return
	baseline = OS.get_environment("ENEMY_DISPLACEMENT_BASELINE") == "1"
	check(Game.new_profile() and Game.start_run(), "isolated profile and normal CH01 run")
	check(Game.grant_hero_xp(30, "displacement-fixture"), "unlock secondary with normal progression")
	check(Game.run.level == 2 and Game.run.hero_id == "CH01", "level-two CH01 uses resolved default stats and equipment")
	actual_hammer_repro()
	if not baseline:
		displacement_cases()
		independent_skills()
		await paused_case()
	var path := "res://artifacts/enemy_displacement_before.json" if baseline else "res://artifacts/enemy_displacement_after.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"Fixed 10ms production player/enemy/runtime ticks in a real room. Normal CH01 Lv2/default equipment and resolved enemy Lv4 HP/defense/damage; only isolated profile, initial positions, empty geometry and +20 resource setup. No health, damage, defense or invulnerability override.", "checks":checks,"failures":failures,"cases":report}, "\t"))
	file.close()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("ENEMY DISPLACEMENT ", "BEFORE " if baseline else "AFTER ", checks - failures, "/", checks)
	get_tree().quit(0 if failures == 0 else 1)
