extends Node
## Actual MineRoom/EnemyBrain/EnemySkillRuntime integration. Only timing and
## fixture health/positions are controlled; enemy decisions are never stubbed.

const RoomScene = preload("res://scenes/room.tscn")
const Sampler = preload("res://scripts/ui/texture_sampler.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const Art = preload("res://scripts/combat/enemy_art.gd")
const TIER_LEVELS: Array[int] = [1, 5, 10, 15]
const FIXTURE_SEED: int = 41827
const L01_LEVELS: Array[int] = [1, 3, 5]
const L01_BUDGETS: Array[int] = [10, 12, 14]
const L01_WAVES: Array = [
	[["M08", "M04", "M01", "M04", "M04"], ["M07"]],
	[["M07", "M01", "M04", "M04", "M01"], ["M08"]],
	[["M08", "M04", "M04", "M01", "M04"], ["M07", "M04"]]
]
const L01_WAVE_COSTS: Array = [[8, 3], [9, 3], [13, 6]]
var room: MineRoom
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ENEMY INTEGRATION FAIL: " + description)


func near(actual: float, expected: float, description: String) -> void:
	check(absf(actual - expected) < 0.001, "%s (actual %.4f, expected %.4f)" % [description, actual, expected])


func fixture(layout_id: String = "", seed_value: int = FIXTURE_SEED) -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hero_id = "CH02"
	Game.run.level = 8
	Game.run.loadout_snapshot = {}
	Game.run.equipment_snapshot = {}
	Game.run.stats = StatResolver.resolve("CH02", 8, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.stats["armor"] = 0.0
	Game.run.stats["damage_reduction"] = 0.0
	Game.run.stats["equipment_damage_reduction"] = 0.0
	# A durable unarmored real player isolates enemy timelines from run death.
	Game.run.stats["max_hp"] = 1000.0
	Game.run.max_hp = 1000.0
	Game.run.hp = 1000.0
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = not layout_id.is_empty()
	room.layout_id = "L01" if layout_id.is_empty() else layout_id
	room.run_seed = seed_value
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	clear_enemies()
	room.activated_encounters.clear()
	room.encounter_progress.clear()
	room.wave = 0
	room.objective_complete = false
	room.gold_drops.clear()
	room.player.position = Vector2(1200, 800)
	room.player.aim_direction = Vector2.LEFT


func clear_enemies() -> void:
	room.enemy_skills.reset_room()
	for actor: Node in room.enemies.get_children():
		actor.free()
	for shot: Node in room.projectiles.get_children():
		shot.free()
	room.enemy_corpses.clear()


func live_actors() -> Array[MineEnemy]:
	var result: Array[MineEnemy] = []
	for actor: MineEnemy in room.enemies.get_children():
		if actor.is_alive() and not actor.is_queued_for_deletion():
			result.append(actor)
	return result


func anchors(kind: String = "") -> Array[MineEnemy]:
	var result: Array[MineEnemy] = []
	for actor: MineEnemy in live_actors():
		if actor.static_actor and (kind.is_empty() or str(actor.get_meta("enemy_skill_anchor_kind", "")) == kind):
			result.append(actor)
	return result


func summons(caster: MineEnemy) -> Array[MineEnemy]:
	var result: Array[MineEnemy] = []
	for actor: MineEnemy in live_actors():
		if not actor.static_actor and actor.owner_enemy != null and actor.owner_enemy.get_ref() == caster:
			result.append(actor)
	return result


func step(duration: float) -> void:
	var elapsed: float = 0.0
	while elapsed + 0.00001 < duration and Game.run != null:
		var delta: float = minf(0.025, duration - elapsed)
		room.player._physics_process(delta)
		for actor: MineEnemy in live_actors():
			actor._physics_process(delta)
		room.enemy_skills._physics_process(delta)
		if is_instance_valid(room.enemy_props):
			room.enemy_props.update(delta)
		elapsed += delta


func until(predicate: Callable, maximum: float) -> bool:
	var elapsed: float = 0.0
	while elapsed < maximum:
		if bool(predicate.call()):
			return true
		step(0.025)
		elapsed += 0.025
	return bool(predicate.call())


func tick_player_projectiles(duration: float = 0.2) -> void:
	var elapsed: float = 0.0
	while elapsed < duration:
		for shot: Node in room.projectiles.get_children():
			if not shot.is_queued_for_deletion():
				shot._physics_process(0.01)
		elapsed += 0.01


func _run() -> void:
	if not Game.profile_path.contains("test_enemy_integration"):
		push_error("Refusing a non-test enemy integration profile")
		get_tree().quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated real run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_legacy_spawn()
	_test_all_live_profiles()
	_test_real_attack_timing()
	_test_production_encounters()
	_test_high_difficulty_density()
	await _test_reinforcement_timing_and_pause()
	_test_summon_reservations()
	_test_generated_run_seeds()
	_test_room_and_zone_caps()
	_test_m12_pods_summons_and_rewards()
	_test_m33_projectile_and_area_disarm()
	_test_m06_breakable_cover()
	_test_m16_stable_loot_and_room_cleanup()
	if is_instance_valid(room):
		# This fixture advances combat synchronously, then quits on the same
		# frame as the final kill. Observe real mixer cleanup before shutdown;
		# stop/free alone can leave AudioStreamPlaybackWAV pending for one tick.
		check(await room.combat_audio.wait_for_cleanup(), "final fixture releases every tracked mixer playback before immediate process exit")
		check(room.combat_audio.pending_playback_count() == 0, "no prior or current room playback remains alive after cleanup")
		room.free()
	print("ENEMY INTEGRATION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_legacy_spawn() -> void:
	fixture()
	var legacy: MineEnemy = room.spawn_enemy(Vector2(900, 800))
	check(legacy != null, "legacy spawn_enemy(at) produces a real enemy")
	near(legacy.health.maximum, 60.0, "legacy fixture retains exactly 60 HP")
	near(legacy.armor, 0.0, "legacy fixture retains zero armor")
	check(legacy.enemy_id.is_empty() and legacy.profile.is_empty() and legacy.brain == null, "legacy caller does not silently acquire a new prototype or AI")
	check(legacy.body_texture != null, "legacy texture remains available")


func _test_all_live_profiles() -> void:
	fixture()
	for index: int in range(1, 37):
		var id: String = "M%02d" % index
		for tier_index: int in TIER_LEVELS.size():
			var level: int = TIER_LEVELS[tier_index]
			var actor: MineEnemy = room.spawn_enemy(Vector2(900, 800), id, level, {"zone_index": 0})
			var label: String = "%s level %d" % [id, level]
			check(actor != null, label + " spawns through MineRoom")
			if actor == null:
				continue
			check(actor.enemy_id == id and actor.enemy_level == level and actor.rank == "normal", label + " keeps requested identity, level and ordinary rank")
			check(int(actor.profile.mechanic_tier) == tier_index + 1 and actor.brain != null and int(actor.brain.mechanic_tier) == tier_index + 1, label + " real brain receives the correct authored tier")
			check(actor.profile.behavior_id == actor.brain.behavior_id and actor.brain.profile != {}, label + " real brain receives its distinct behavior")
			near(actor.health.maximum, float(actor.profile.max_hp), label + " profile HP reaches actual health component")
			near(actor.navigation_radius, float(actor.profile.navigation_radius), label + " profile collision radius reaches actual navigation")
			check(room.valid_ground(actor.position, actor.navigation_radius), label + " actual spawn is legal for its body radius")
			var body: Dictionary = Art.entry_for(id)
			check(not body.is_empty() and actor.body_texture == body.texture and actor.body_region == body.region and actor.body_visual.body_frame().source_family == Art.FAMILY, label + " uses its actual painted clan body and measured region")
			actor._physics_process(0.4)
			room.enemy_skills._physics_process(0.4)
			check(actor.state == &"emerging" and room.enemy_skills.active_effect_count() == 0, label + " first half of spawn grace produces no skill effects")
			actor._physics_process(0.425)
			room.enemy_skills._physics_process(0.425)
			check(float(actor.brain.age) >= 0.8 and actor.state != &"emerging", label + " actual physics enters its brain after spawn grace")
			actor.free()
			room.enemy_skills.reset_room()
	var base: MineEnemy = room.spawn_enemy(Vector2(900, 800), "M01", 1)
	near(base.health.maximum, 60.0, "M01 level one authored HP is independently 60")
	base.free()
	var grown: MineEnemy = room.spawn_enemy(Vector2(900, 800), "M01", 15)
	near(grown.health.maximum, 106.2, "M01 level fifteen independently follows 60*(1+14*0.055)")
	check(int(grown.brain.parameters.combo_count) == 3, "M01 tier four has a real three-strike brain")


func _test_real_attack_timing() -> void:
	fixture()
	room.player.position = Vector2(970, 800)
	var melee: MineEnemy = room.spawn_enemy(Vector2(920, 800), "M01", 1)
	step(0.79)
	near(Game.run.hp, 1000.0, "real M01 cannot damage during 0.79 second spawn grace")
	check(until(func() -> bool: return melee.state == &"locked", 2.0), "M01 actual brain reaches a locked readable windup")
	near(Game.run.hp, 1000.0, "locked M01 has not prematurely applied melee damage")
	check(until(func() -> bool: return Game.run.hp < 1000.0, 1.0), "actual brain executes melee through real player receive_damage")
	near(Game.run.hp, 986.0, "one real M01 level-one strike deals exactly 14 to the unarmored fixture")
	fixture()
	room.player.position = Vector2(1200, 800)
	room.spawn_enemy(Vector2(900, 800), "M03", 1)
	check(until(func() -> bool: return not room.enemy_skills.projectiles.is_empty(), 4.0), "M03 actual brain creates a scheduled projectile")
	near(Game.run.hp, 1000.0, "M03 projectile creation does not apply instant remote damage")
	check(until(func() -> bool: return Game.run.hp < 1000.0, 2.0), "real enemy runtime advances projectile into player")
	near(Game.run.hp, 987.0, "M03 level-one projectile deals exactly 13 to the unarmored fixture")
	fixture()
	room.player.position = Vector2(1200, 800)
	room.spawn_enemy(Vector2(900, 800), "M03", 15)
	check(until(func() -> bool: return room.enemy_skills.projectiles.size() == 3, 6.0), "M03 tier-four actual physics emits the authored three-projectile fan")
	near(Game.run.hp, 1000.0, "tier-four projectile fan still observes actual travel time")
	check(until(func() -> bool: return Game.run.hp < 1000.0, 2.0), "tier-four real projectile reaches the unarmored fixture")
	near(Game.run.hp, 982.45, "M03 level-fifteen projectile independently deals 13*(1+14*0.025)=17.55")


func _test_production_encounters() -> void:
	var first: Array = []
	for hero_level: int in [1, 20]:
		fixture("L01")
		Game.run.level = hero_level
		room.difficulty = 0
		room.spawn_enabled = true
		var observed: Array = []
		var total: int = 0
		for zone: int in range(3):
			room.player.position = room.encounter_zones[zone].center
			room._physics_process(0.0)
			for batch: int in range(2):
				var ids: Array[String] = []
				var levels: Array[int] = []
				var cost: float = 0.0
				for actor: MineEnemy in live_actors():
					ids.append(actor.enemy_id)
					levels.append(actor.enemy_level)
					cost += actor.threat_cost
					check(actor.zone_index == zone and actor.rank == "normal", "L01 production assigns current zone and ordinary rank")
					check(actor.enemy_level == L01_LEVELS[zone], "L01 production levels remain fixed at 1/3/5")
					near(float(actor.profile.encounter_budget), float(L01_BUDGETS[zone]), "L01 authored zone budget reaches real enemies")
					check(actor.position.distance_to(room.player.position) >= 359.99, "real generated-room wave spawns at least 360 pixels away")
				check(ids == L01_WAVES[zone][batch], "L01 zone %d wave %d exact real members at hero level %d" % [zone, batch, hero_level])
				near(cost, float(L01_WAVE_COSTS[zone][batch]), "L01 independently authored wave threat cost")
				check(ids.size() <= 6 and live_actors().size() <= 18 and cost <= L01_BUDGETS[zone], "L01 production respects zone, room and threat caps")
				observed.append([ids, levels, cost])
				total += ids.size()
				defeat_all()
				room._physics_process(0.0)
				if batch == 0:
					check(not room.objective_complete and not room._encounters_exhausted(), "clearing first batch cannot finish a pending reinforcement plan")
					check(room.activated_encounters.size() == zone + 1, "pending reinforcement prevents early next-region activation")
					room._physics_process(2.999)
					check(live_actors().is_empty() and int(room.encounter_progress[zone].next_wave) == 1, "actual empty zone remains pending before three seconds")
					room._physics_process(0.001)
					check(int(room.encounter_progress[zone].next_wave) == 2, "actual room advances the queued batch only at three seconds")
			check(room.objective_complete == (zone == 2), "real objective completes only after every zone and its last batch die")
		check(total == 19 and room._encounters_exhausted(), "L01 actual three-zone clearing spawns exactly nineteen finite natural enemies")
		if hero_level == 1:
			first = observed.duplicate(true)
		else:
			check(observed == first, "hero level twenty does not secretly scale L01 enemies")


func defeat_all() -> void:
	for actor: MineEnemy in live_actors():
		actor.take_damage(actor.health.current * (1.0 + actor.armor / 100.0) + 1000.0, &"equipment")


func _test_high_difficulty_density() -> void:
	for scenario: Dictionary in [
		{"room_id":"L01","total":31,"zones":[10,10,11]},
		{"room_id":"L19","total":40,"zones":[13,13,14]}
	]:
		var id: String = str(scenario.room_id)
		fixture(id)
		room.difficulty = 4
		room.spawn_enabled = true
		var total: int = 0
		for zone: int in range(3):
			room.player.position = room.encounter_zones[zone].center
			room._physics_process(0.0)
			check(room.encounter_progress.has(zone), "%s difficulty four activates actual zone %d" % [id,zone])
			if not room.encounter_progress.has(zone):
				break
			var plan: Dictionary = room.encounter_progress[zone].plan
			var zone_total: int = 0
			check(plan.waves.size() >= 2, "%s high difficulty uses finite queued reinforcements" % id)
			for batch: int in plan.waves.size():
				var living: Array[MineEnemy] = live_actors()
				check(not living.is_empty() and living.size() == plan.waves[batch].size(), "%s zone %d batch %d materializes its entire pending batch" % [id,zone,batch])
				var commitment: Dictionary = room._zone_commitments(zone)
				check(room._zone_actor_count(zone) <= 6 and int(commitment.slots) <= 6, "%s every high-difficulty batch stays within six actual and reserved zone seats" % id)
				check(living.size() <= 18 and room._room_committed_slots() <= 18, "%s every high-difficulty batch stays within eighteen actual and reserved room seats" % id)
				check(float(commitment.threat) <= float(plan.concurrent_threat_budget), "%s every high-difficulty batch respects its simultaneous threat budget" % id)
				for actor: MineEnemy in living:
					check(actor.zone_index == zone and actor.owner_enemy == null and actor.reward_enabled, "%s density total counts actual natural enemies in the correct zone" % id)
					check(actor.position.distance_to(room.player.position) >= 359.99, "%s every high-difficulty spawn keeps the full 360-pixel warning distance" % id)
					check(room.valid_ground(actor.position,actor.navigation_radius), "%s high-difficulty spawn is legal in the real generated layout" % id)
				zone_total += living.size()
				# Density acceptance removes cleared real nodes; the separate attack
				# cases exercise death/reward/AI, so this avoids replaying combat here.
				clear_enemies()
				room._physics_process(0.0)
				if batch + 1 < plan.waves.size():
					check(not room.objective_complete and int(room.encounter_progress[zone].next_wave) == batch + 1, "%s high-difficulty objective stays pending between batches" % id)
					room._physics_process(2.99)
					check(live_actors().is_empty(), "%s later high-difficulty batch does not arrive before three eligible seconds" % id)
					room._physics_process(0.01)
					check(int(room.encounter_progress[zone].next_wave) == batch + 2, "%s real room issues the next high-difficulty batch at three seconds" % id)
			check(zone_total == int(scenario.zones[zone]), "%s zone %d has independent expected cumulative natural count %d" % [id,zone,int(scenario.zones[zone])])
			total += zone_total
		check(total == int(scenario.total), "%s difficulty four actual full-room natural enemy total is exactly %d" % [id,int(scenario.total)])
		check(room._encounters_exhausted() and room.objective_complete and live_actors().is_empty(), "%s highest-difficulty encounter completes after its finite final batch is cleared" % id)


func _test_reinforcement_timing_and_pause() -> void:
	fixture("L01")
	room.spawn_enabled = true
	room.player.position = room.encounter_zones[0].center
	room._physics_process(0.0)
	var support: MineEnemy
	var fighter: MineEnemy
	for actor: MineEnemy in live_actors():
		if actor.enemy_id == "M08":
			support = actor
		elif actor.enemy_id == "M01":
			fighter = actor
		else:
			actor.free()
	check(support != null and fighter != null, "timing fixture keeps two real first-batch enemies")
	room._physics_process(4.0)
	near(float(room.encounter_progress[0].reinforce_elapsed), 0.0, "two survivors with threat five fail the thirty-percent budget condition")
	fighter.free()
	room._physics_process(2.0)
	near(float(room.encounter_progress[0].reinforce_elapsed), 2.0, "one threat-three survivor starts the real reinforcement countdown")
	var blocker: MineEnemy = room.spawn_enemy(support.position + Vector2(70, 0), "M04", 1, {"zone_index":0})
	check(blocker != null, "real low-threat interruption actor enters the existing zone")
	room._physics_process(0.1)
	near(float(room.encounter_progress[0].reinforce_elapsed), 0.0, "losing threat eligibility resets rather than banks the prior two seconds")
	if blocker != null:
		blocker.free()
	room._physics_process(2.99)
	check(int(room.encounter_progress[0].next_wave) == 1, "interrupted window must earn a fresh continuous three seconds")
	var before: float = float(room.encounter_progress[0].reinforce_elapsed)
	# Use the actual scheduler, not a hand-called paused callback: production
	# MineRoom is PAUSABLE and the test runner remains ALWAYS while awaiting.
	room.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = true
	await get_tree().create_timer(3.1, true, false, true).timeout
	near(float(room.encounter_progress[0].reinforce_elapsed), before, "over three real paused seconds contribute no reinforcement time")
	check(int(room.encounter_progress[0].next_wave) == 1 and live_actors().size() == 1, "paused scheduler neither spawns reinforcements nor runs enemy AI")
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	room._physics_process(0.01)
	check(int(room.encounter_progress[0].next_wave) == 2 and live_actors().size() == 2, "unpausing resumes the remaining one hundredth second exactly")


func _summoner_definition() -> Dictionary:
	var plan: Dictionary = Profiles.encounter_plan("L09", 0, 0)
	for batch: Array in plan.waves:
		for definition: Dictionary in batch:
			if str(definition.enemy_id) == "M12":
				return definition.duplicate(true)
	return {}


func _test_summon_reservations() -> void:
	fixture()
	var definition: Dictionary = _summoner_definition()
	check(not definition.is_empty() and int(definition.get("reserved_summon_count",0)) == 2, "real L09 production profile reserves two level-five hatchling seats")
	if definition.is_empty():
		return
	var caster: MineEnemy = room.spawn_enemy(Vector2(1000,800), "M12", 5, {"profile":definition,"zone_index":0})
	check(caster != null, "production summoner profile configures a real actor")
	var commitment: Dictionary = room._zone_commitments(0)
	check(int(commitment.slots) == 3, "one actual mother commits three zone seats before any pod exists")
	near(float(commitment.threat), 9.0, "level-five mother reserves independent five-plus-two-plus-two threat")
	var filler: Dictionary = Profiles.resolve("M04",1)
	check(room._can_spawn_encounter_wave(0,[filler,filler,filler],14.0), "exact six committed zone seats are allowed")
	check(not room._can_spawn_encounter_wave(0,[filler,filler,filler,filler],14.0), "seventh committed zone seat is rejected before pods materialize")
	check(not room._can_spawn_encounter_wave(0,[filler],9.0), "reserved summon threat blocks a batch even with only one live actor")
	check(until(func() -> bool: return anchors("summon_pod").size() == 2,5.0), "reserved production M12 actually creates both owned pods")
	commitment = room._zone_commitments(0)
	check(live_actors().size() == 3 and int(commitment.slots) == 3, "real pods consume reserved seats without double counting")
	near(float(commitment.threat),9.0,"two cheap actual pods retain the full future hatchling threat reservation")
	check(until(func() -> bool: return summons(caster).size() == 2,2.0), "reserved production pods become actual M14 enemies")
	commitment = room._zone_commitments(0)
	check(live_actors().size() == 3 and int(commitment.slots) == 3, "actual hatched summons replace reserved seats exactly")
	near(float(commitment.threat),9.0,"hatched actors replace reserved threat exactly")
	fixture()
	caster = room.spawn_enemy(Vector2(1000,800),"M12",5,{"profile":definition,"zone_index":0})
	for index: int in range(14):
		check(room.spawn_enemy(Vector2(300+index*40,500),"M04",1) != null,"global reservation fixture creates real unzoned actor")
	check(live_actors().size() == 15,"global fixture has fifteen living actors plus two future hatchlings")
	check(room._can_spawn_encounter_wave(1,[filler],14.0),"eighteenth globally committed seat remains available")
	check(not room._can_spawn_encounter_wave(1,[filler,filler],14.0),"cross-zone wave cannot consume the nineteenth seat reserved for a future summon")
	check(room.spawn_enemy(Vector2(1600,500),"M04",1,{"zone_index":1}) != null,"last unreserved global seat accepts a real actor")
	check(room.spawn_enemy_summon(caster,"M14",Vector2(1050,850)) != null and room.spawn_enemy_summon(caster,"M14",Vector2(1100,850)) != null,"both actual summons can materialize in their preserved global seats")
	check(live_actors().size() == 18 and not room._can_spawn_encounter_wave(2,[filler],14.0),"eighteen real actors including summons reject all further wave actors")


func _test_generated_run_seeds() -> void:
	fixture("L01",-1)
	var original_run_id: String = Game.run.id
	var saved_seed: int = room.layout_seed
	var saved_props: Array = room.layout.prop_instances.duplicate(true)
	check(room.use_generated_layout and bool(room.layout.get("generated",false)),"ordinary MineRoom now uses real RoomGenerator output by default")
	check(saved_seed == (hash(original_run_id)&0x7fffffff) and saved_seed == room.run_seed,"default layout seed comes from the actual run identity")
	check(room.load_room_layout("L01",0) and room.layout_seed == saved_seed and room.layout.prop_instances == saved_props,"same room reload in one run reproduces generated prop instances exactly")
	check(room.load_room_layout("L13",0) and room.layout_seed == saved_seed,"changing room preserves the saved run seed")
	check(room.load_room_layout("L01",0) and room.layout.prop_instances == saved_props,"returning to the room restores the identical generated layout")
	check(room.load_room_layout("L01",0,73019) and room.layout_seed == 73019,"explicit test seed overrides this generated layout")
	var explicit_props: Array = room.layout.prop_instances.duplicate(true)
	check(room.load_room_layout("L01",0,73019) and room.layout.prop_instances == explicit_props,"same explicit test seed yields identical real room generation")
	check(room.run_seed == saved_seed and room.load_room_layout("L01",0) and room.layout.prop_instances == saved_props,"explicit test seed does not overwrite the saved production run seed")
	room.free()
	check(not Game.finish_run("abandoned").is_empty() and Game.start_run(),"seed integration creates a second real run through the save controller")
	if Game.run == null:
		return
	fixture("L01",-1)
	check(Game.run.id != original_run_id and room.layout_seed != saved_seed,"new real run receives a different production layout seed")
	check(room.layout.prop_instances != saved_props,"new run seed produces a different physical prop arrangement")


func _test_room_and_zone_caps() -> void:
	fixture()
	for index: int in range(6):
		check(room.spawn_enemy(Vector2(400 + index * 40, 500), "M01", 1, {"zone_index": 0}) != null, "zone accepts authored occupancy through six")
	check(room.spawn_enemy(Vector2(700, 500), "M01", 1, {"zone_index": 0}) == null, "zone rejects seventh live actor")
	for index: int in range(12):
		check(room.spawn_enemy(Vector2(800 + index * 40, 600), "M01", 1) != null, "room accepts live occupancy through eighteen")
	check(live_actors().size() == 18 and room.spawn_enemy(Vector2(1500, 600), "M01", 1) == null, "room rejects nineteenth live actor")


func _test_m12_pods_summons_and_rewards() -> void:
	fixture()
	var caster: MineEnemy = room.spawn_enemy(Vector2(1000, 800), "M12", 5, {"zone_index": 0})
	check(until(func() -> bool: return anchors("summon_pod").size() == 2, 5.0), "real tier-two M12 creates two breakable hatch pods")
	var pods: Array[MineEnemy] = anchors("summon_pod")
	for pod: MineEnemy in pods:
		check(not pod.reward_enabled and pod.static_actor and pod.owner_enemy.get_ref() == caster, "actual hatch pod is static, owned and unrewarding")
		near(pod.health.maximum, 18.0, "actual hatch pod has authored 18 HP")
	check(until(func() -> bool: return summons(caster).size() == 2, 2.0), "real runtime hatches two M14 actors")
	for child: MineEnemy in summons(caster):
		check(child.enemy_id == "M14" and child.enemy_level == 5 and not child.reward_enabled, "actual M14 inherits summoner level and cannot reward farming")
	step(8.0)
	check(summons(caster).size() == 2 and anchors("summon_pod").is_empty(), "successive AI cycles never exceed two owned summons or add extra pods")
	check(room.spawn_enemy_summon(caster, "M14", Vector2(1300, 850)) == null, "room independently rejects third owned summon")
	var child: MineEnemy = summons(caster)[0] if not summons(caster).is_empty() else null
	var kills: int = Game.run.kills
	var drops: int = room.gold_drops.size()
	if child != null:
		child.take_damage(child.health.current * (1.0 + child.armor / 100.0) + 1.0, &"equipment")
		check(Game.run.kills == kills and room.gold_drops.size() == drops, "killing real summoned actor awards neither kill reward nor gold")
	var owner_id: int = caster.get_instance_id()
	caster.take_damage(caster.health.current * (1.0 + caster.armor / 100.0) + 1.0, &"equipment")
	room.enemy_skills._physics_process(0.01)
	check(not room.enemy_skills.summon_owners.has(owner_id), "owner death clears runtime summon ownership immediately")
	for actor: MineEnemy in room.enemies.get_children():
		if actor.owner_enemy != null:
			check(actor.is_queued_for_deletion() or not actor.is_alive(), "owner death retires every live owned entity")
	fixture()
	caster = room.spawn_enemy(Vector2(1000, 800), "M12", 1, {"zone_index": 0})
	caster.profile["encounter_budget"] = caster.threat_cost
	check(room.spawn_enemy_summon(caster, "M14", Vector2(1150, 800)) == null, "real summon cannot exceed its zone threat budget")
	check(room.spawn_enemy_skill_anchor(caster, Vector2(1100, 800), 18.0) == null, "real hatch anchor also requires remaining zone threat budget")
	step(5.0)
	check(summons(caster).is_empty() and anchors().is_empty() and room.enemy_skills.jobs.is_empty(), "budget-exhausted real M12 leaves no unbudgeted pods or delayed hatch jobs")
	fixture()
	caster = room.spawn_enemy(Vector2(1000, 800), "M12", 15, {"zone_index": 0})
	check(until(func() -> bool: return anchors("summon_pod").size() == 2, 5.0), "M12 tier-four actual AI creates its two disarmable pods")
	pods = anchors("summon_pod")
	if not pods.is_empty():
		var pod: MineEnemy = pods[0]
		var before_kills: int = Game.run.kills
		# Tier-four pods sit close behind the mother; approach from outside so
		# this test shoots the pod first rather than a legitimate body blocker.
		var outward: Vector2 = caster.position.direction_to(pod.position)
		room.player.position = pod.position + outward * 65.0
		room.player.aim_direction = -outward
		room.player.shot_cooldown = 0.0
		check(room.player.fire(-outward), "real player shoots an actual pending hatch pod")
		tick_player_projectiles()
		check(not pod.is_alive(), "player projectile disarms the real pending hatch pod")
		check(Game.run.kills == before_kills and room.gold_drops.is_empty(), "disarmed real hatch pod produces neither kill reward nor gold")
		near(caster.armor, 0.0, "tier-four pod disarm removes its authored ten armor, clamped at zero")
		room.enemy_skills._physics_process(0.01)
		check(until(func() -> bool: return summons(caster).size() == 1, 2.0), "only the intact pod hatches after actual player disarm")


func _test_m33_projectile_and_area_disarm() -> void:
	fixture()
	var caster: MineEnemy = room.spawn_enemy(Vector2(1000, 800), "M33", 5)
	check(until(func() -> bool: return not anchors("hazard_endpoint").is_empty(), 6.0), "M33 real AI deploys a breakable line endpoint")
	var nodes: Array[MineEnemy] = anchors("hazard_endpoint")
	if nodes.is_empty():
		return
	var endpoint: MineEnemy = nodes[0]
	near(endpoint.health.maximum, 16.0, "real M33 endpoint has authored 16 HP")
	room.player.position = endpoint.position + Vector2(0, 60)
	room.player.aim_direction = Vector2.UP
	room.player.shot_cooldown = 0.0
	var kills: int = Game.run.kills
	check(room.player.fire(Vector2.UP), "player's actual ranged primary fires at endpoint")
	tick_player_projectiles()
	check(not endpoint.is_alive(), "real player projectile destroys M33 endpoint")
	room.enemy_skills._physics_process(0.01)
	check(Game.run.kills == kills and room.gold_drops.is_empty(), "endpoint destruction yields no farming reward")
	check(room.enemy_skills.hazards.is_empty(), "destroying only existing endpoint immediately removes its slow line")
	room.player.position = Vector2(1200, 800)
	check(until(func() -> bool: return not anchors("hazard_endpoint").is_empty(), 5.0), "M33 subsequent authored stage creates next endpoint")
	nodes = anchors("hazard_endpoint")
	if not nodes.is_empty():
		endpoint = nodes[0]
		var victims: Array = room.strike_area(endpoint.position, 24.0, 30.0, &"skill", "", 0.0, Vector2.ZERO, 360.0, false)
		check(victims.has(endpoint) and not endpoint.is_alive(), "real strike_area can destroy a second endpoint")
	step(8.0)
	check(room.enemy_skills.hazards.size() <= 2 and anchors("hazard_endpoint").size() <= 2, "M33 repeated real cycles stay within two line/endpoint cap")
	check(caster.is_alive(), "endpoint destruction does not require killing the caster")


func _test_m06_breakable_cover() -> void:
	fixture()
	room.player.position = Vector2(1140, 800)
	var caster: MineEnemy = room.spawn_enemy(Vector2(1000, 800), "M06", 1)
	check(until(func() -> bool: return not anchors("weld_cover").is_empty(), 5.0), "M06 real brain constructs an actual cover actor")
	var covers: Array[MineEnemy] = anchors("weld_cover")
	if covers.is_empty():
		return
	var cover: MineEnemy = covers[0]
	near(cover.health.maximum, 28.0, "M06 real cover has authored 28 HP")
	check(cover.actor_kind == "cover" and cover.static_actor and not cover.reward_enabled, "cover is shootable static unrewarding world entity")
	var caster_hp: float = caster.health.current
	room.player.position = cover.position + Vector2(70, 0)
	room.player.aim_direction = Vector2.LEFT
	room.player.shot_cooldown = 0.0
	check(room.player.fire(Vector2.LEFT), "real player primary fires toward welding cover")
	tick_player_projectiles()
	check(cover.health.current < 28.0 and cover.is_alive(), "first actual shot damages the cover instead of phasing through")
	near(caster.health.current, caster_hp, "cover absorbs front projectile before caster")
	room.player.shot_cooldown = 0.0
	check(room.player.fire(Vector2.LEFT), "second actual projectile fires")
	tick_player_projectiles()
	check(not cover.is_alive(), "second actual shot breaks the finite cover")
	room.enemy_skills._physics_process(0.01)
	check(room.enemy_skills.supports.is_empty(), "breaking cover removes its damage-filter support")
	check(room.gold_drops.is_empty(), "destroying cover never creates gold")


func _test_m16_stable_loot_and_room_cleanup() -> void:
	fixture("L07")
	var entry: Vector2 = room.layout.entry
	room.player.position = entry + Vector2(0, 400)
	var thief: MineEnemy = room.spawn_enemy(entry, "M16", 1)
	room.gold_drops.append({"at":entry + Vector2(30, 0), "amount":17, "age":0.0})
	room.gold_drops.append({"at":entry + Vector2(90, 0), "amount":29, "age":0.0})
	var loot: Array = room.enemy_props.query_tag("recoverable_loot")
	check(loot.size() == 2 and str(loot[0].id) != str(loot[1].id), "actual ground drops receive distinct stable props IDs")
	var selected_id: String = str(loot[0].id)
	check(until(func() -> bool: return thief.state == &"locked", 4.0), "M16 actual AI locks its recoverable loot target")
	var locked: Dictionary = thief.brain.current_telegraph()
	check(str(locked.get("target_id", "")) == selected_id, "M16 telegraph retains the selected stable ground-loot ID")
	room.gold_drops.reverse()
	check(until(func() -> bool: return room.enemy_props.carried_by(thief), 2.0), "real enemy utility steals loot even after drop-array order changes")
	var carried: Array = room.enemy_props.stolen.get(thief.get_instance_id(), [])
	check(carried.size() == 1 and str(carried[0].drop.get("_room_prop_id", "")) == selected_id and int(carried[0].drop.amount) == 17, "stable ID resolves original 17-gold drop, not stale array index")
	check(room.gold_drops.size() == 1 and int(room.gold_drops[0].amount) == 29, "unselected actual drop remains on the floor")
	thief.take_damage(thief.health.current + 1.0, &"equipment")
	room.enemy_props.update(0.05)
	room.enemy_props.update(0.05)
	var restored: int = 0
	for drop: Dictionary in room.gold_drops:
		if str(drop.get("_room_prop_id", "")) == selected_id:
			restored += 1
			check(int(drop.amount) == 17, "real thief death returns original amount intact")
	check(restored == 1 and room.enemy_props.stolen.is_empty(), "death and subsequent props ticks return stolen loot exactly once")
	for effect: String in ["damage", "guard", "haste"]:
		# Beacon functions are random, so choose this fixture's three functions
		# explicitly while preserving the actual spawned positions/controller.
		var ordinal: int = ["damage", "guard", "haste"].find(effect)
		var supply: Dictionary = room.enemy_props.props[ordinal]
		supply.merge(RoomProps.BUFFS[effect].duplicate(true), true)
		supply.merge({"effect":effect,"used":false,"available":true,"cooldown":0.0,"remaining":0.0,"armed":true}, true)
		room.player.position = supply.position
		room.enemy_props.update(0.01)
		check(bool(supply.used) and room.enemy_props.buffs.has(effect), "actual room beacon grants " + effect + " on approach before transition")
	check(room.enemy_props.active_buffs().size() == 3 and Game.run.shield > 0.0, "all three real room buff sources are active")
	clear_enemies()
	# Keep the authored room/props but choose a known open actor pair for effects.
	var caster: MineEnemy = room.spawn_enemy(entry, "M12", 1)
	room.player.position = caster.position + Vector2(70, 0)
	check(until(func() -> bool: return not room.enemy_skills.jobs.is_empty(), 5.0), "transition fixture contains a real pending hatch before switching rooms")
	var before_nodes: Array[MineEnemy] = live_actors()
	check(room.load_room_layout("L13", 0), "real load_room_layout enters B03")
	check(room.enemy_skills.active_effect_count() == 0 and room.enemy_skills.summon_owners.is_empty(), "room transition clears every runtime job/projectile/hazard/support/mark")
	check(room.enemy_props.active_buffs().is_empty() and room.enemy_props.stolen.is_empty(), "room transition clears old room buffs and stolen registry")
	check(not room.player.status.guards.has("room_prop:guard") and is_zero_approx(Game.run.shield), "room transition removes prior prop guard rather than leaving hidden shield")
	check(room.gold_drops.is_empty(), "room transition clears old ground gold")
	for actor: MineEnemy in before_nodes:
		check(actor.is_queued_for_deletion(), "room transition retires prior enemy and skill anchor actors")
	var sockets: Array = room.enemy_props.query_tag("shield_socket")
	check(not sockets.is_empty() and str(sockets[0].id).begins_with("L13:shield_socket:"), "B03 authored socket gets the new room's stable identity")
