extends Node
## Real-room displacement contracts. Pure trajectory cases disable only target
## AI; actor health, defenses, damage, movement and collision remain production.
## Combat cases use the natural brain, its real lock timer and public hit APIs.

const RoomScene = preload("res://scenes/room.tscn")
const BossScript = preload("res://scripts/combat/boss.gd")
var room: MineRoom
var checks: int = 0
var failures: int = 0
var report: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CONTINUOUS KNOCKBACK: " + message)

func near(actual: float, expected: float, message: String, tolerance: float = 0.02) -> void:
	check(absf(actual - expected) <= tolerance, message + " actual=" + str(actual) + " expected=" + str(expected))

func fixture(id: String = "M01", distance: float = 160.0, rank: String = "normal", disabled: bool = true, extra: Dictionary = {}) -> MineEnemy:
	if is_instance_valid(room): room.free()
	Game.run = null
	check(Game.start_run(), "fresh isolated run")
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	room.combat_audio.audible = false
	room.enemy_skills.reset_room()
	for actor in room.enemies.get_children(): actor.free()
	for projectile in room.projectiles.get_children(): projectile.free()
	room.obstructions.clear()
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	var options: Dictionary = {"rank":rank}
	options.merge(extra, true)
	var enemy: MineEnemy = room.spawn_enemy(room.player.position + Vector2(distance, 0), id, 4, options)
	check(is_instance_valid(enemy), "natural enemy profile spawns " + id)
	if is_instance_valid(enemy): enemy.training_ai_disabled = disabled
	return enemy

func step(duration: float, quantum: float = 0.01, player_tick: bool = false) -> void:
	var elapsed: float = 0.0
	while elapsed + 0.000001 < duration:
		var delta: float = minf(quantum, duration - elapsed)
		if player_tick: room.player._physics_process(delta)
		for enemy in room.enemies.get_children():
			if enemy.is_alive(): enemy._physics_process(delta)
		room.enemy_skills.advance(delta)
		elapsed += delta

func lock(enemy: MineEnemy, kind: String) -> Dictionary:
	for frame in 1600:
		var tell: Dictionary = enemy.brain.current_telegraph()
		if bool(tell.get("locked", false)) and str(tell.get("kind", "")) == kind:
			return tell.duplicate(true)
		step(0.01)
	check(false, enemy.enemy_id + " naturally reaches locked " + kind)
	return {}

func trajectory_cases() -> void:
	for rank: String in ["normal", "elite"]:
		for rate: int in [30, 60, 144]:
			var enemy := fixture("M01", 160.0, rank)
			var start: Vector2 = enemy.position
			var hp: float = enemy.health.current
			var expected: float = 65.0 * (0.5 if rank == "elite" else 1.0)
			enemy.apply_knockback(Vector2.RIGHT, 65.0)
			check(enemy.position == start, rank + " " + str(rate) + " Hz skill hit does not teleport on the call frame")
			check(enemy.has_pending_displacement(), "valid skill push owns an unfinished trajectory")
			var positions: Array[float] = [0.0]
			var elapsed: float = 0.0
			while enemy.has_pending_displacement() and elapsed < 0.30:
				step(1.0 / float(rate), 1.0 / float(rate))
				elapsed += 1.0 / float(rate)
				positions.append(enemy.position.x - start.x)
			check(positions.size() >= 4, "visible skill recoil spans multiple physics frames at " + str(rate) + " Hz")
			check(positions[1] > 0.0 and positions[1] < expected, "first frame shows partial movement")
			for index: int in range(1, positions.size()):
				check(positions[index] >= positions[index - 1] - 0.001 and positions[index] <= expected + 0.02, "trajectory moves monotonically without overshoot")
			near(enemy.position.x - start.x, expected, "same authored final distance at " + str(rate) + " Hz")
			near(enemy.position.y, start.y, "horizontal push keeps lateral pivot")
			check(not enemy.has_pending_displacement(), "completed trajectory releases displacement ownership")
			check(elapsed >= 0.10 - 0.001 and elapsed <= 0.16 + 1.0 / float(rate) + 0.001, "displacement settles in the bounded reaction window")
			check(enemy.health.current == hp, "pure displacement does not fabricate damage")
			var finish: Vector2 = enemy.position
			step(0.20)
			check(enemy.position.is_equal_approx(finish), "completed trajectory leaves no residual drift")
			report.append({"case":"trajectory", "rank":rank, "rate":rate, "distance":finish.x - start.x, "seconds":elapsed, "samples":positions})
	var enemy := fixture()
	var start: Vector2 = enemy.position
	enemy.apply_knockback(Vector2.RIGHT, 65.0)
	var increments: Array[float] = []
	var previous: float = 0.0
	for index in 5:
		step(0.016)
		var traveled: float = enemy.position.x - start.x
		increments.append(traveled - previous)
		previous = traveled
	for index: int in range(1, increments.size()):
		check(increments[index] > 0.0 and increments[index] < increments[index - 1], "equal-duration samples decelerate after the initial impact")

func collision_cases() -> void:
	for geometry: String in ["wall", "arena_edge", "corner"]:
		var enemy := fixture()
		var direction: Vector2 = Vector2.RIGHT
		if geometry == "arena_edge":
			enemy.position.x = room.ARENA.end.x - enemy.navigation_radius - 22.0
		elif geometry == "corner":
			room.obstructions.assign([Rect2(enemy.position + Vector2(42, -18), Vector2(30, 120))])
			direction = Vector2(1.0, 0.5).normalized()
		else:
			room.obstructions.assign([Rect2(enemy.position + Vector2(42, -100), Vector2(20, 200))])
		var start: Vector2 = enemy.position
		check(room.valid_ground(start, enemy.navigation_radius), geometry + " fixture starts on valid ground")
		enemy.apply_knockback(direction, 90.0)
		check(enemy.position == start, geometry + " collision projection does not teleport")
		for frame in 30:
			step(0.01)
			check(room.valid_ground(enemy.position, enemy.navigation_radius), geometry + " every body position respects real room collision")
		check(not enemy.has_pending_displacement(), geometry + " blocked movement settles instead of accumulating an endless push")
		check(enemy.position.distance_to(start) < 90.0, geometry + " geometry limits total displacement")
		var finish: Vector2 = enemy.position
		step(0.20)
		check(enemy.position == finish, geometry + " resting at obstruction does not jitter")
		report.append({"case":geometry,"start":[start.x,start.y],"finish":[finish.x,finish.y]})

func stacked_impulse_cases() -> void:
	var enemy := fixture()
	var start: Vector2 = enemy.position
	for hit in 24: enemy.apply_knockback(Vector2.RIGHT, 6.0)
	check(enemy.position == start, "24 simultaneous pushes never move synchronously")
	near(enemy.pending_displacement().x, 144.0, "overflow compaction preserves all unspent authored distance")
	step(0.12)
	near(enemy.position.x - start.x, 144.0, "more than sixteen same-direction pushes preserve final distance")
	check(not enemy.has_pending_displacement(), "same-frame overflow cannot extend original deadlines")

	enemy = fixture()
	start = enemy.position
	enemy.apply_knockback(Vector2.RIGHT, 40.0)
	enemy.apply_knockback(Vector2.LEFT, 40.0)
	check(enemy.pending_displacement().is_zero_approx(), "equal opposing pushes expose zero remaining net displacement")
	for frame in 14:
		step(0.01)
		check(enemy.position.is_equal_approx(start), "simultaneous opposing displacement cancels without oscillation")
	check(not enemy.has_pending_displacement(), "opposed pulses still retire at their deadlines")

	enemy = fixture()
	start = enemy.position
	enemy.apply_knockback(Vector2.RIGHT, 40.0)
	step(0.06)
	enemy.apply_knockback(Vector2.DOWN, 20.0)
	step(0.06)
	near(enemy.position.x - start.x, 40.0, "later perpendicular hit never refreshes the old pulse deadline")
	near(enemy.pending_displacement().x, 0.0, "old direction has no remaining distance at its original deadline")
	check(enemy.has_pending_displacement() and enemy.pending_displacement().y > 0.0, "later pulse keeps only its own remaining travel")
	step(0.06)
	near(enemy.position.y - start.y, 20.0, "later pulse retains its full independent distance")
	check(not enemy.has_pending_displacement(), "both staggered pulses finish without extended recoil")

	enemy = fixture()
	start = enemy.position
	for hit in 16: enemy.apply_knockback(Vector2.RIGHT, 4.0)
	step(0.04)
	for hit in 16: enemy.apply_knockback(Vector2.DOWN, 4.0)
	step(0.07)
	near(enemy.position.x - start.x, 64.0, "overflow merges preserve the earlier batch deadline")
	near(enemy.pending_displacement().x, 0.0, "overflow cannot keep an expired direction alive")
	check(enemy.pending_displacement().y > 0.0, "overflow leaves the later batch on its own original deadline")
	step(0.05)
	near(enemy.position.y - start.y, 64.0, "staggered overflow conserves all later distance")
	check(not enemy.has_pending_displacement(), "all overflow pulses expire without an immortal aggregate")

func confirmed_hit_cases() -> void:
	for mode: String in ["immune", "zero", "shield"]:
		var enemy := fixture()
		if mode == "immune": check(enemy.apply_status("invulnerable", 1.0, 1.0), "real invulnerability is active")
		if mode == "shield": check(enemy.apply_status("guard", 20.0, 1.0), "real finite guard is active")
		var start: Vector2 = enemy.position
		var hp: float = enemy.health.current
		var shield: float = enemy.status.shield()
		var accepted: bool = room.resolve_direct_hit(enemy, 0.0 if mode == "zero" else 5.0, &"secondary", "", 40.0, Vector2.RIGHT, {"equipment_eligible":false,"original_basic":false})
		check(accepted == (mode == "shield"), mode + " contact confirmation matches actual HP or shield consumption")
		check(enemy.health.current == hp, mode + " packet does not lose body health")
		check(enemy.has_pending_displacement() == (mode == "shield"), mode + " only confirmed contact commits skill displacement")
		check(enemy.position == start, mode + " real damage pipeline does not teleport target")
		if mode == "shield": check(enemy.status.shield() < shield, "pure absorption really consumes guard before the push")
		step(0.15)
		if mode == "shield":
			near(enemy.position.x - start.x, 40.0, "shield-only confirmed hit retains its entire authored push")
		else:
			check(enemy.position == start, mode + " rejected hit never moves target on later frames")

func immunity_and_primary_cases() -> void:
	var normal := fixture()
	var start: Vector2 = normal.position
	var hp: float = normal.health.current
	check(normal.take_damage(1.0, &"primary", Vector2.RIGHT), "real primary packet is accepted by a natural target")
	check(normal.health.current < hp and normal.knockback.length() > 0.0, "accepted basic retains the existing velocity recoil path")
	check(normal.position == start and not normal.has_pending_displacement(), "basic recoil is separate from the skill displacement trajectory")
	step(0.016)
	check(normal.position.x > start.x, "real basic recoil moves on subsequent physics frames")
	for kind: String in ["static", "boss"]:
		var actor: MineEnemy
		if kind == "static":
			actor = fixture("M01", 160.0, "normal", true, {"static_actor":true})
		else:
			var ordinary := fixture()
			ordinary.free()
			var boss: MineBoss = BossScript.new()
			boss.room = room
			check(boss.configure_boss("BO01", 0, 73017), "real boss uses its authored profile")
			boss.position = room.player.position + Vector2(200, 0)
			room.enemies.add_child(boss)
			boss.training_ai_disabled = true
			actor = boss
		start = actor.position
		hp = actor.health.current
		actor.apply_knockback(Vector2.RIGHT, 90.0)
		check(not actor.has_pending_displacement() and actor.position == start, kind + " rejects skill displacement")
		actor.take_damage(1.0, &"primary", Vector2.RIGHT)
		check(actor.health.current < hp, kind + " displacement immunity does not imply damage immunity")
		check(actor.knockback.is_zero_approx(), kind + " primary packet cannot accumulate velocity recoil")
		step(0.24)
		check(actor.position == start, kind + " remains planted through subsequent physics ticks")

func immediate_melee_cases() -> void:
	for mode: String in ["strong", "small", "blocked"]:
		var enemy := fixture("M01", 60.0, "normal", false)
		var tell := lock(enemy, "melee")
		if tell.is_empty(): continue
		step(maxf(0.0, enemy.state_time - 0.005), 0.001)
		check(str(enemy.state) == "locked", "hit is placed in the actual last locked frame")
		if mode == "blocked":
			room.obstructions.assign([Rect2(enemy.position + Vector2(enemy.navigation_radius + 2.0, -100), Vector2(20, 200))])
		var start: Vector2 = enemy.position
		var hp: float = Game.run.hp
		enemy.apply_knockback(Vector2.RIGHT, 8.0 if mode == "small" else 65.0)
		check(enemy.position == start, mode + " late push is still animated")
		if mode == "strong":
			check(str(enemy.state) == "recovery" and enemy.brain.current_telegraph().is_empty(), "reachable strong push immediately cancels locked melee before delayed position changes")
		else:
			check(str(enemy.state) == "locked", mode + " insufficient reachable displacement preserves the committed melee")
		step(0.06)
		check((Game.run.hp < hp) == (mode != "strong"), mode + " actual release damage follows the displacement cancellation decision")
		report.append({"case":"late_melee_" + mode,"damage":hp - Game.run.hp,"state":str(enemy.state),"distance":enemy.position.distance_to(start)})

func charge_and_independent_cases() -> void:
	for id: String in ["M02", "M04"]:
		var enemy := fixture(id, 160.0, "normal", false)
		var tell := lock(enemy, "charge")
		if tell.is_empty(): continue
		var start: Vector2 = enemy.position
		var hp: float = Game.run.hp
		enemy.apply_knockback(Vector2.DOWN, 3.0)
		check(enemy.position == start and str(enemy.state) == "recovery", id + " even small effective push immediately cancels locked line/leap")
		check(enemy.brain.current_telegraph().is_empty(), id + " cancelled charge clears its danger shape")
		step(0.46)
		check(not room.enemy_skills.has_motion(enemy) and Game.run.hp == hp, id + " cancelled charge never starts or lands later")
	for entry: Array in [["M03", "projectile"], ["M11", "ground_area"]]:
		var enemy := fixture(str(entry[0]), 220.0, "normal", false)
		var tell := lock(enemy, str(entry[1]))
		if tell.is_empty(): continue
		enemy.apply_knockback(Vector2.DOWN, 65.0)
		check(str(enemy.state) == "locked", str(entry[0]) + " independent attack retains its locked command during push")
		step(0.42)
		var collection: Array = room.enemy_skills.projectiles if entry[1] == "projectile" else room.enemy_skills.hazards
		check(not collection.is_empty(), str(entry[0]) + " independent attack still releases from its frozen command")
		var count: int = collection.size()
		enemy.apply_knockback(Vector2.UP, 40.0)
		check(collection.size() == count, str(entry[0]) + " later push does not delete released independent effects")

func runtime_motion_cases() -> void:
	for pending: bool in [false, true]:
		var enemy := fixture("M04", 160.0, "normal", false)
		step(0.81)
		enemy.training_ai_disabled = true
		var origin: Vector2 = enemy.position
		var target: Vector2 = origin + Vector2.RIGHT * 240.0
		var charge: Dictionary = {"kind":"charge","origin":origin,"target":target,"direction":Vector2.RIGHT,"range":240.0,"duration":0.8,"radius":30.0,"path_mode":"leap","landing_only":true,"delay":0.3 if pending else 0.0}
		enemy.cast_enemy_skill(charge)
		enemy.cast_enemy_skill({"kind":"projectile","origin":origin,"target":target,"direction":Vector2.RIGHT,"range":600.0,"speed":100.0,"radius":6.0})
		check(room.enemy_skills.jobs.size() == 1 if pending else room.enemy_skills.has_motion(enemy), "public command creates delayed or active owned charge")
		check(room.enemy_skills.projectiles.size() == 1, "same owner has a separately released projectile")
		if not pending: room.enemy_skills.advance(0.1)
		var at_hit: Vector2 = enemy.position
		enemy.apply_knockback(Vector2.DOWN, 20.0)
		check(not room.enemy_skills.has_motion(enemy), "effective push immediately releases active body-motion ownership")
		check(room.enemy_skills.jobs.is_empty(), "effective push removes a pending charge job synchronously")
		check(room.enemy_skills.projectiles.size() == 1, "motion cancellation preserves the independent projectile of the same owner")
		step(0.40)
		near(enemy.position.x, at_hit.x, "cancelled charge never snaps back onto the old path")
		near(enemy.position.y - at_hit.y, 20.0, "cancelled charge permits the actual recoil trajectory")
		check(not room.enemy_skills.has_motion(enemy) and room.enemy_skills.jobs.is_empty(), "cancelled motion cannot revive when original delay elapses")

func clocks_and_pause_cases() -> void:
	var enemy := fixture("M01", 160.0, "normal", false)
	check(enemy.apply_status("burn", 4.0, 2.0), "real status API applies finite burn")
	step(0.95)
	var age: float = enemy.brain.age
	var clock_before: float = enemy.status.clock
	var hp: float = enemy.health.current
	enemy.apply_knockback(Vector2.RIGHT, 65.0)
	step(0.10)
	near(enemy.brain.age - age, 0.10, "brain clock continues while body is being pushed", 0.001)
	near(enemy.status.clock - clock_before, 0.10, "status clock continues during displacement", 0.001)
	check(enemy.health.current < hp, "natural burn tick still deals damage during the displacement interval")
	check(enemy.has_pending_displacement(), "clock assertions overlap an unfinished trajectory")
	var at_pause: Vector2 = enemy.position
	age = enemy.brain.age
	clock_before = enemy.status.clock
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = true
	await get_tree().create_timer(0.05, true).timeout
	check(enemy.position == at_pause and enemy.brain.age == age and enemy.status.clock == clock_before, "actual scene pause freezes movement and game clocks together")
	get_tree().paused = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	step(0.10)
	check(not enemy.has_pending_displacement(), "paused trajectory completes after normal resume")

func _run() -> void:
	if not Game.profile_path.contains("test_continuous_knockback"):
		get_tree().quit(2)
		return
	check(Game.new_profile(), "isolated test profile created")
	trajectory_cases()
	collision_cases()
	stacked_impulse_cases()
	confirmed_hit_cases()
	immunity_and_primary_cases()
	immediate_melee_cases()
	charge_and_independent_cases()
	runtime_motion_cases()
	await clocks_and_pause_cases()
	var file := FileAccess.open("res://artifacts/continuous_knockback.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"method":"Production MineRoom, MineEnemy, MineBoss, brain, status and skill runtime. Natural resolved HP/defense/damage. Pure trajectory fixtures disable only AI; natural locked-combat cases keep AI active. Manual physics quanta isolate 30/60/144 Hz trajectories and last-lock-frame cancellation; this is not natural encounter balance or visual-quality evidence.","checks":checks,"failures":failures,"cases":report}, "\t"))
		file.close()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("CONTINUOUS KNOCKBACK ", checks - failures, "/", checks)
	get_tree().quit(0 if failures == 0 else 1)
