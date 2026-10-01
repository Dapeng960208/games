extends Node
## Real MineBoss physics and EnemySkillRuntime acceptance checks.
## tools/test.ps1 -Suite boss_tactics -SkipImport -SkipRestart

const BossFixtures = preload("res://tests/test_first_four_bosses.gd")
const SkillFixtures = preload("res://tests/test_enemy_skills.gd")
const Profiles = preload("res://scripts/combat/boss_profiles.gd")
const Brain = preload("res://scripts/combat/boss_brain.gd")
const Runtime = preload("res://scripts/combat/enemy_skill_runtime.gd")
const IDS := ["BO01", "BO02", "BO03", "BO04"]
const ACTIONS := {"BO01":"solar_cross", "BO02":"acid_scatter", "BO03":"stitch_cage", "BO04":"crag_leap"}

class TacticalRoom extends BossFixtures.ThemeRoom:
	func navigation_direction(from: Vector2, to: Vector2, radius: float) -> Vector2:
		var direction: Vector2 = from.direction_to(to)
		return direction if blocked_fraction(from, from + direction * 12.0, radius) > 0.0 else Vector2.ZERO

class QuietPlayer extends "res://scripts/combat/player.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _draw() -> void: pass

class ReinforcementRoom extends "res://scripts/combat/room.gd":
	func _init() -> void:
		process_mode = Node.PROCESS_MODE_DISABLED
		for label: String in ["Enemies", "Projectiles"]:
			var container := Node2D.new()
			container.name = label
			add_child(container)
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _draw() -> void: pass

var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BOSS TACTICS FAIL: " + label)

func fixture(id: String, difficulty: int = 0, seed_value: int = 777) -> Dictionary:
	var host := TacticalRoom.new()
	host.layout = {"arena":SkillFixtures.RoomFixtureBase.ARENA}
	add_child(host)
	var player := SkillFixtures.ActorFixture.new()
	player.room = host
	player.health.reset(100000.0)
	player.position = Vector2(620,400)
	host.player = player
	host.add_child(player)
	host.recipients = [player]
	var runtime := Runtime.new()
	host.add_child(runtime)
	runtime.configure(host)
	host.enemy_skills = runtime
	var boss := BossFixtures.RecordedBoss.new()
	boss.room = host
	boss.position = Vector2(300,400)
	check(boss.configure_boss(id,difficulty,seed_value), id + " configures production actor")
	host.enemies.add_child(boss)
	return {"room":host, "boss":boss, "player":player, "runtime":runtime}

func add_recipient(sim: Dictionary, at: Vector2) -> Node2D:
	var actor := SkillFixtures.ActorFixture.new()
	actor.room = sim.room
	actor.health.reset(100000.0)
	actor.position = at
	sim.room.add_child(actor)
	sim.room.recipients.append(actor)
	return actor

func tick(sim: Dictionary, duration: float) -> void:
	var remaining: float = duration
	while remaining > 0.00001:
		var step: float = minf(0.02, remaining)
		sim.boss._physics_process(step)
		sim.runtime.advance(step)
		remaining -= step

func geometry(value: Dictionary) -> String:
	return var_to_str([value.get("origin"),value.get("target"),value.get("direction"),value.get("points",[]),value.get("paths",[]),value.get("targets",[])])

func locked_action(sim: Dictionary, action: String) -> Dictionary:
	var boss: Node2D = sim.boss
	var brain: BossBrain = boss.boss_brain
	brain._begin_action(boss, sim.player, action)
	var tell: Dictionary = brain.current_telegraph()
	check(not tell.is_empty() and str(tell.get("action_id", "")) == action, action + " begins its own real telegraph")
	if tell.is_empty(): return {}
	var old_position: Vector2 = boss.position
	var old_casts: int = boss.casts.size()
	tick(sim, float(tell.tell) - 0.04)
	check(boss.position == old_position and boss.velocity.is_zero_approx(), action + " stays still during readable tell")
	check(boss.casts.size() == old_casts and sim.player.hits.is_empty(), action + " produces no attack damage before tell")
	tick(sim, 0.06)
	var locked: Dictionary = brain.current_telegraph()
	check(bool(locked.get("locked",false)), action + " enters a visible locked dodge window")
	var frozen: String = geometry(locked)
	var target_before: Vector2 = sim.player.position
	sim.player.position += Vector2(0,70)
	tick(sim,0.02)
	check(geometry(brain.current_telegraph()) == frozen, action + " keeps all committed geometry after player movement")
	check(boss.position == old_position and boss.velocity.is_zero_approx(), action + " stays still while aim is locked")
	sim.player.position = target_before
	return locked

func release_action(sim: Dictionary, action: String) -> Dictionary:
	var locked: Dictionary = locked_action(sim,action)
	if locked.is_empty(): return {}
	var old_casts: int = sim.boss.casts.size()
	tick(sim,float(sim.boss.boss_brain.state_time)+0.005)
	check(sim.boss.casts.size() == old_casts+1, action + " releases exactly one production cast")
	var snapshot: Dictionary = sim.boss.boss_brain.tactical_snapshot()
	check(snapshot.last_action == action and int(snapshot.actions_used.get(action,0)) == 1, action + " records actual executed action")
	return sim.boss.casts.back() if sim.boss.casts.size() > old_casts else {}

func recover(sim: Dictionary, duration: float = 12.0) -> void:
	var brain: BossBrain = sim.boss.boss_brain
	brain.state = &"recovery"
	brain.state_time = duration
	brain.state_duration = duration
	brain._recovery_elapsed = 0.28
	brain.command.clear()

func run_checks() -> void:
	var isolated: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test-profile=") and arg.contains("test_boss_tactics"): isolated = true
	if not isolated:
		push_error("This suite requires an isolated boss_tactics test profile")
		get_tree().quit(1)
		return
	if not Game.has_profile: Game.new_profile()
	check(Game.start_run(), "isolated combat run starts")
	await movement_checks()
	await skill_checks()
	await ring_aim_checks()
	await availability_checks()
	await deterministic_checks()
	await difficulty_checks()
	await reinforcement_checks()
	Game.finish_run("abandoned")
	print("BOSS TACTICS TESTS: ", checks-failures, "/", checks, " passed")
	get_tree().quit(1 if failures else 0)

func movement_checks() -> void:
	for id: String in IDS:
		var sim: Dictionary = fixture(id)
		var boss: Node2D = sim.boss
		var tactics: Dictionary = boss.profile.tactics
		check(float(tactics.min_range) < float(tactics.max_range), id + " has a finite preferred combat range")
		recover(sim)
		sim.player.position = boss.position + Vector2(600,0)
		var before: float = boss.position.distance_to(sim.player.position)
		tick(sim,0.24)
		check(boss.position.distance_to(sim.player.position) < before-3.0 and boss.boss_brain.tactical_snapshot().intent == "chase", id + " really walks toward a distant player")
		check(boss.state == &"reposition" and boss.boss_brain.state_name() == &"recovery", id + " uses locomotion pose while keeping recovery clock")
		boss.position = Vector2(300,400)
		sim.player.position = boss.position + Vector2((float(tactics.min_range)+float(tactics.max_range))*0.5,0)
		var start: Vector2 = boss.position
		tick(sim,0.2)
		check(absf(boss.position.y-start.y) > 4.0 and boss.boss_brain.tactical_snapshot().intent == "orbit", id + " actually circles at preferred distance")
		boss.position = Vector2(300,400)
		sim.player.position = boss.position + Vector2(60,0)
		before = boss.position.distance_to(sim.player.position)
		tick(sim,0.2)
		check(boss.position.distance_to(sim.player.position) > before+3.0 and boss.boss_brain.tactical_snapshot().intent == "retreat", id + " creates space when player is too close")
		boss.boss_brain._open_weakpoint(boss,"earned_opening",2.0)
		start = boss.position
		tick(sim,0.4)
		check(boss.position == start and boss.velocity.is_zero_approx(), id + " preserves stationary player counterattack window")
		sim.room.queue_free()
		await get_tree().process_frame
	# A distant target beyond every damaging action cannot trigger an empty hit.
	for id: String in IDS:
		var sim: Dictionary = fixture(id)
		if id == "BO02": sim.boss.boss_brain.brood_batches = 3
		if id == "BO04": sim.boss.boss_brain.drums_broken = true
		sim.player.position = Vector2(1600,400)
		sim.boss.boss_brain._begin_action(sim.boss,sim.player)
		check(sim.boss.boss_brain.current_telegraph().is_empty() and sim.boss.boss_brain.current_action.is_empty(), id + " skips all attacks against an out-of-range target")
		check(sim.boss.velocity.x > 0.0 and sim.boss.state == &"reposition", id + " immediately chases while waiting to enter skill range")
		var before: Vector2 = sim.boss.position
		tick(sim,0.3)
		check(sim.boss.position.x > before.x+3.0 and sim.boss.casts.is_empty(), id + " advances through real actor physics without an out-of-range cast")
		sim.room.queue_free()
		await get_tree().process_frame

func skill_checks() -> void:
	var solar: Dictionary = fixture("BO01")
	var solar_command: Dictionary = release_action(solar,"solar_cross")
	check(solar_command.get("kind") == "ground_area" and solar_command.get("shape") == "line" and solar_command.get("paths",[]).size() == 2, "solar cross warns two distinct electric lines")
	check(solar.runtime.hazards.size() == 2, "solar cross creates two real persistent line hazards")
	if solar.runtime.hazards.size() == 2:
		var first: Dictionary = solar.runtime.hazards[0]
		var second: Dictionary = solar.runtime.hazards[1]
		check(absf(Vector2(first.direction).dot(Vector2(second.direction))) < 0.01, "electric cross executes orthogonal geometry rather than duplicate traces")
		var first_line: Array = first.points
		var second_line: Array = second.points
		var first_actor: Node2D = add_recipient(solar,Vector2(first_line[0]).lerp(Vector2(first_line[1]),0.2))
		var second_actor: Node2D = add_recipient(solar,Vector2(second_line[0]).lerp(Vector2(second_line[1]),0.2))
		tick(solar,0.7)
		check(first_actor.hits.size() == 1 and second_actor.hits.size() == 1, "each solar cross arm independently deals real runtime damage")
		check(solar.player.hits.size() == 2 and solar.player.statuses.size() == 2, "cross center takes real electric damage from both warned lines")
	solar.room.queue_free()
	await get_tree().process_frame
	var acid: Dictionary = fixture("BO02")
	var acid_tell: Dictionary = locked_action(acid,"acid_scatter")
	var splashes: Array[Node2D] = [acid.player]
	for point: Vector2 in acid_tell.get("targets",[]).slice(1): splashes.append(add_recipient(acid,point))
	tick(acid,float(acid.boss.boss_brain.state_time)+0.005)
	check(acid.boss.casts.size() == 1 and acid_tell.get("targets",[]).size() == 3 and acid.runtime.hazards.size() == 2, "acid scatter lands three circles and retains only two pools")
	for splash: Node2D in splashes:
		check(splash.hits.size() == 1 and splash.statuses.size() == 1, "each separate warned acid landing causes real corrosion damage")
	tick(acid,0.75)
	check(splashes[0].hits.size() == 1 and splashes[1].hits.size() == 2 and splashes[2].hits.size() == 2, "oldest acid impact ends while two newest pools continue damage")
	acid.room.queue_free()
	await get_tree().process_frame
	var stitch: Dictionary = fixture("BO03")
	var stitch_command: Dictionary = release_action(stitch,"stitch_cage")
	check(stitch_command.get("kind") == "projectile" and stitch_command.get("paths",[]).size() == 3 and stitch.runtime.projectiles.size() == 3, "stitch cage creates three real separately warned threads")
	var paths: Array = stitch_command.get("paths",[])
	if paths.size() == 3:
		check(paths[0].size() == 3 and paths[1].size() == 3 and paths[2].size() == 3 and paths[0][1] != paths[1][1] and paths[1][1] != paths[2][1], "stitch threads have executable distinct bends")
		check(paths[0].back() == stitch.player.position and paths[1].back() == stitch.player.position and paths[2].back() == stitch.player.position, "stitch warning endpoints match the actual convergence point")
	tick(stitch,1.35)
	check(stitch.player.hits.size() == 3 and stitch.player.statuses.size() == 3 and stitch.runtime.projectiles.is_empty(), "all three stitched paths converge into real finite runtime hits")
	stitch.room.queue_free()
	await get_tree().process_frame
	var leap: Dictionary = fixture("BO04")
	var bystander: Node2D = add_recipient(leap,Vector2(450,400))
	var leap_command: Dictionary = release_action(leap,"crag_leap")
	check(leap_command.get("path_mode") == "leap" and bool(leap_command.get("landing_only",false)) and is_equal_approx(float(leap_command.get("radius",0.0)),110.0), "crag leap has its own landing-only large impact geometry")
	check(leap.runtime.has_motion(leap.boss) and leap.player.hits.is_empty() and bystander.hits.is_empty(), "leap starts actual controlled motion with no release or path damage")
	var moved: Vector2 = leap.boss.position
	leap.boss._physics_process(0.05)
	check(leap.boss.position == moved and leap.boss.velocity.is_zero_approx(), "ordinary boss navigation cannot steal active runtime leap movement")
	leap.runtime.advance(0.25)
	check(leap.boss.position.x > moved.x and leap.player.hits.is_empty() and bystander.hits.is_empty(), "leap travels through bystanders without hidden contact hit")
	tick(leap,0.6)
	check(not leap.runtime.has_motion(leap.boss) and leap.player.hits.size() == 1 and bystander.hits.is_empty(), "leap delivers exactly one real circular landing hit")
	check(leap.boss.boss_brain.weakpoint_open() and leap.boss.boss_brain.weakpoint == "landed_warchief", "successful landing opens authored counterattack window")
	moved = leap.boss.position
	tick(leap,0.3)
	check(leap.boss.position == moved and leap.boss.velocity.is_zero_approx(), "landed chieftain remains still during its weakness")
	leap.room.queue_free()
	await get_tree().process_frame
	var boundary: Dictionary = fixture("BO01")
	boundary.player.position = Vector2(80,80)
	var boundary_command: Dictionary = release_action(boundary,"solar_cross")
	for path: Array in boundary_command.get("paths",[]):
		check(SkillFixtures.RoomFixtureBase.ARENA.has_point(path[0]) and SkillFixtures.RoomFixtureBase.ARENA.has_point(path[1]), "boundary-target cross keeps both hazard endpoints in arena")
	tick(boundary,0.7)
	check(boundary.player.hits.size() == 2, "boundary-target cross still lands both real electric lines")
	boundary.room.queue_free()
	await get_tree().process_frame

func ring_aim_checks() -> void:
	for test_case: Dictionary in [{"id":"BO02", "action":"crown_open", "phase":3, "distance":180.0}, {"id":"BO04", "action":"resonance_ring", "phase":1, "distance":220.0}, {"id":"BO04", "action":"heart_crack", "phase":3, "distance":220.0}]:
		var sim: Dictionary = fixture(str(test_case.id))
		sim.boss.boss_brain.phase = int(test_case.phase)
		sim.boss.health.current = sim.boss.health.maximum * (0.34 if int(test_case.phase) == 3 else 1.0)
		sim.player.position = sim.boss.position + Vector2(float(test_case.distance), 0.0)
		var locked: Dictionary = locked_action(sim, str(test_case.action))
		var safe_actor: Node2D = add_recipient(sim, sim.boss.position + Vector2(locked.direction) * float(test_case.distance))
		check(sim.runtime.shape_contains(locked, sim.player.position, 12.0), str(test_case.action) + " aims its dangerous arc at the warned player")
		check(not sim.runtime.shape_contains(locked, safe_actor.position, 12.0), str(test_case.action) + " preserves its explicit side escape arc")
		tick(sim, float(sim.boss.boss_brain.state_time) + 0.005)
		check(sim.player.hits.size() == 1 and safe_actor.hits.is_empty(), str(test_case.action) + " deals real front damage while its warned safe gap stays safe")
		sim.room.queue_free()
		await get_tree().process_frame

func availability_checks() -> void:
	for id: String in IDS:
		var sim: Dictionary = fixture(id)
		var sequence: Array = Brain.SEQUENCES[id][1]
		for action: String in sequence: sim.boss.boss_brain._action_ready_at[action] = 100.0
		check(sim.boss.boss_brain._select_action(sim.boss,sim.player,sequence).is_empty(), id + " respects every still-active skill cooldown")
		sim.boss.boss_brain.command = {"action_id":"stale_command"}
		sim.boss.boss_brain._begin_action(sim.boss,sim.player)
		check(sim.boss.boss_brain.state_name() == &"recovery" and sim.boss.boss_brain.command.is_empty(), id + " clears stale commands and waits without cooldown fallback")
		tick(sim,0.6)
		check(sim.boss.casts.is_empty() and not sim.boss.velocity.is_zero_approx(), id + " keeps moving while cooldowns forbid casting")
		check(sim.boss.boss_brain._build_action(sim.boss,sim.player,"unknown_action").is_empty(), id + " rejects undefined actions without generic fallback hit")
		sim.room.queue_free()
		await get_tree().process_frame
	var queen: Dictionary = fixture("BO02")
	queen.boss.boss_brain.brood_batches = 3
	check(not queen.boss.boss_brain._action_available(queen.boss,"brood_eggs"), "queen skips exhausted egg batches during normal AI selection")
	queen.boss.boss_brain.brood_batches = 0
	queen.room.spawn_enemy_summon(queen.boss,"M14",Vector2(200,200))
	queen.room.spawn_enemy_summon(queen.boss,"M14",Vector2(200,250))
	check(not queen.boss.boss_brain._action_available(queen.boss,"brood_eggs"), "queen does not spend another summon action with two living owned adds")
	queen.room.queue_free()
	await get_tree().process_frame
	var mayor: Dictionary = fixture("BO03")
	check(not mayor.boss.boss_brain._action_available(mayor.boss,"grave_recall"), "mayor never wastes a resurrection cast with no real dead add receipt")
	for index: int in 5:
		mayor.boss.boss_brain._begin_action(mayor.boss,mayor.player)
		check(mayor.boss.boss_brain.current_action != "grave_recall", "normal mayor choice skips unavailable grave recall")
	var fallen: Node2D = mayor.room.spawn_enemy_summon(mayor.boss, "M27", Vector2(200,200))
	fallen.health.damage(1000.0)
	check(mayor.boss.notify_reinforcement_death(fallen), "mayor records a real receipt for availability-cap check")
	fallen.queue_free()
	await get_tree().process_frame
	mayor.room.spawn_enemy_summon(mayor.boss, "M27", Vector2(200,200))
	mayor.room.spawn_enemy_summon(mayor.boss, "M27", Vector2(200,250))
	check(not mayor.boss.boss_brain._action_available(mayor.boss, "grave_recall"), "mayor preserves resurrection budget while two living owned adds fill its cap")
	mayor.room.queue_free()
	await get_tree().process_frame

func deterministic_checks() -> void:
	for id: String in IDS:
		var first: Dictionary = fixture(id,0,9031)
		var second: Dictionary = fixture(id,0,9031)
		var first_sequence: Array[String] = []
		var second_sequence: Array[String] = []
		for index: int in 6:
			for sim: Dictionary in [first,second]:
				sim.player.position = Vector2(620,360+index*9)
				sim.boss.boss_brain.elapsed = float(index)*8.0
				sim.boss.boss_brain._begin_action(sim.boss,sim.player)
				if sim == first: first_sequence.append(sim.boss.boss_brain.current_action)
				else: second_sequence.append(sim.boss.boss_brain.current_action)
				if not sim.boss.boss_brain.command.is_empty(): sim.boss.boss_brain._execute(sim.boss)
		check(first_sequence == second_sequence, id + " produces identical action choices for the same seed and player inputs")
		check(first_sequence.size() == 6 and first_sequence.any(func(action: String) -> bool: return action == ACTIONS[id]), id + " normal adaptive selection actually uses its new exclusive action")
		check(first_sequence.slice(1).any(func(action: String) -> bool: return action != first_sequence[0]), id + " normal AI uses multiple different available skills")
		first.runtime.reset_room()
		second.runtime.reset_room()
		first.boss.position = Vector2(300,400)
		second.boss.position = Vector2(300,400)
		for sim: Dictionary in [first,second]:
			sim.player.position = Vector2(620,400)
			sim.boss.boss_brain._close_weakpoint(sim.boss)
			recover(sim)
			tick(sim,0.2)
		check(first.boss.position.is_equal_approx(second.boss.position), id + " orbit and pursuit motion is deterministic under identical seed")
		first.room.queue_free()
		second.room.queue_free()
		await get_tree().process_frame

func difficulty_checks() -> void:
	for id: String in IDS:
		var damage: Array[float] = []
		for difficulty: int in [0,4]:
			var sim: Dictionary = fixture(id,difficulty)
			var action: String = ACTIONS[id]
			release_action(sim,action)
			tick(sim,0.7 if id != "BO03" else 1.35)
			check(not sim.player.hits.is_empty(), id + " difficulty " + str(difficulty) + " exclusive skill deals actual damage")
			damage.append(float(sim.player.hits[0].amount) if not sim.player.hits.is_empty() else 0.0)
			sim.room.queue_free()
			await get_tree().process_frame
		check(damage[1] > damage[0] and damage[0] > 0.0, id + " hard difficulty increases actual received exclusive-skill damage")

func reinforcement_checks() -> void:
	for id: String in IDS:
		var damage_by_tier: Array[float] = []
		for difficulty: int in [0,4]:
			var host := ReinforcementRoom.new()
			host.difficulty = difficulty
			host.fx_font = ThemeDB.fallback_font
			host.geometry_enabled = false
			host.layout = {"arena":Rect2(0,0,2800,1800), "spawn_points":[Vector2(1700,500),Vector2(1700,700)]}
			add_child(host)
			var player := QuietPlayer.new()
			player.position = Vector2(900,900)
			host.player = player
			host.add_child(player)
			var runtime := Runtime.new()
			host.add_child(runtime)
			runtime.configure(host)
			host.enemy_skills = runtime
			var boss := BossFixtures.RecordedBoss.new()
			boss.room = host
			boss.position = Vector2(1200,900)
			check(boss.configure_boss(id,difficulty,412), id + " reinforcement host configures actual boss")
			host.enemies.add_child(boss)
			host._boss_actor = boss
			boss.boss_phase_started(2,0.69)
			check(boss.reinforcement_status().pending == 1, id + " phase change queues one real reinforcement request")
			var requests: Array = boss._reinforcement_queue.duplicate(true)
			var expected_count: int = 0
			for request: Dictionary in requests:
				for member: Dictionary in request.members:
					expected_count += int(member.count)
					check(int(member.get("level",0)) == int(Profiles.LEVELS[id]), id + " queued member carries its biome level before difficulty growth")
			host._update_boss_encounter()
			var minions: Array = host.enemies.get_children().filter(func(actor: Node) -> bool: return actor != boss)
			check(minions.size() == expected_count and boss.reinforcement_status().pending == 0, id + " real room drains queue into actual reinforcement actors")
			var mean_damage: float = 0.0
			for minion: Node2D in minions:
				check(minion.enemy_level == mini(20,int(Profiles.LEVELS[id])+difficulty*2), id + " actual room-spawned reinforcement has correct difficulty level")
				check(minion.owner_enemy.get_ref() == boss and not minion.reward_enabled and int(minion.profile.difficulty) == difficulty, id + " actual reinforcement inherits owner and room difficulty")
				mean_damage += float(minion.contact_damage)
			damage_by_tier.append(mean_damage/maxf(1.0,float(minions.size())))
			host._update_boss_encounter()
			check(host.enemies.get_child_count() == expected_count+1, id + " drained phase queue cannot duplicate reinforcements")
			host.queue_free()
			await get_tree().process_frame
		check(damage_by_tier[1] > damage_by_tier[0] and damage_by_tier[0] > 0.0, id + " real phase reinforcements deal more contact and skill base damage on hard difficulty")
