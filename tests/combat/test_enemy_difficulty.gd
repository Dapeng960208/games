extends Node
## Difficulty grows beyond level 20 through real room spawns and skill damage.
## tools/test.ps1 -Suite enemy_difficulty -SkipImport

const Difficulty = preload("res://scripts/domain/combat/enemy_difficulty.gd")
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const BossScript = preload("res://scripts/gameplay/bosses/boss_actor.gd")
const BossProfilesScript = preload("res://scripts/domain/combat/boss_profiles.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const LEVELS := [1, 5, 10, 15, 20]
const GROWING_STATS := ["max_hp", "damage", "move_speed", "armor", "magic_resist"]
const SAFE_WINDOWS := ["tell_seconds", "locked_line_delay_seconds", "area_tell_seconds", "combo_gap_seconds", "exposure_seconds", "spawn_grace_seconds"]
var room: RoomController
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENEMY DIFFICULTY FAIL: " + label)


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.001, "%s (actual %.4f, expected %.4f)" % [label, actual, expected])


func _run() -> void:
	if not Game.profile_path.contains("test_enemy_difficulty"):
		push_error("Refusing a non-test enemy difficulty profile")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated production run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_all_profiles()
	_test_copy_and_reapplication()
	_fixture()
	_test_all_encounter_plans_and_spawns()
	_test_capped_level_real_waves()
	_test_direct_and_owned_spawns()
	_test_real_skill_damage()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "real mixer releases all test combat playback")
		room.free()
	Game.finish_run("abandoned")
	print("ENEMY DIFFICULTY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func _test_all_profiles() -> void:
	check(Catalog.enemy_ids().size() == 54, "all 54 authored enemy prototypes are present")
	for id: String in Catalog.enemy_ids():
		for rank_name: String in ["normal", "elite"]:
			for level: int in LEVELS:
				var base: Dictionary = Profiles.resolve(id, level, rank_name)
				var previous: Dictionary = {}
				for difficulty: int in range(5):
					var scaled: Dictionary = Difficulty.apply(base, difficulty)
					var label: String = "%s %s L%d D%d" % [id, rank_name, level, difficulty]
					check(int(scaled.difficulty) == difficulty and int(scaled.enemy_level) == level, label + " retains requested difficulty and independent level")
					near(float(scaled.max_hp), float(base.max_hp) * (1.0 + 0.12 * difficulty), label + " independent HP growth")
					near(float(scaled.damage), float(base.damage) * (1.0 + 0.10 * difficulty), label + " independent attack growth")
					near(float(scaled.move_speed), float(base.move_speed) * (1.0 + 0.04 * difficulty), label + " independent movement growth")
					near(float(scaled.armor), float(base.armor) + 2.0 * difficulty, label + " independent armor growth")
					near(float(scaled.magic_resist), float(base.magic_resist) + 2.0 * difficulty, label + " independent magic resistance growth")
					if not previous.is_empty():
						for stat: String in GROWING_STATS:
							check(float(scaled[stat]) > float(previous[stat]), label + " strictly increases " + stat + " even at the level cap")
					for window: String in SAFE_WINDOWS:
						near(float(scaled.attack_parameters[window]), float(base.attack_parameters[window]), label + " preserves " + window)
					check(not bool(scaled.attack_parameters.track_after_lock) and not bool(scaled.attack_parameters.spawn_can_damage), label + " preserves aim lock and harmless spawn grace")
					check(float(scaled.recovery_seconds) >= float(scaled.attack_parameters.exposure_seconds), label + " cadence cannot consume the counterattack exposure")
					near(float(scaled.attack_cooldown_seconds), float(scaled.recovery_seconds), label + " runtime cadence agrees with cooldown")
					near(float(scaled.attack_parameters.recovery_seconds), float(scaled.recovery_seconds), label + " actual brain receives difficulty cadence")
					previous = scaled


func _test_copy_and_reapplication() -> void:
	for id: String in Catalog.enemy_ids():
		var base: Dictionary = Profiles.resolve(id, 20, "elite")
		var original: String = var_to_str(base)
		var high: Dictionary = Difficulty.apply(base, 4)
		check(var_to_str(Difficulty.apply(high, 4)) == var_to_str(high), id + " applying the same difficulty twice is idempotent")
		for difficulty: int in range(5):
			check(Difficulty.apply(high, difficulty) == Difficulty.apply(base, difficulty), id + " changing difficulty recomputes from its base without compounding")
		check(Difficulty.apply(base, -10) == Difficulty.apply(base, 0), id + " negative difficulty clamps to zero")
		check(Difficulty.apply(base, 99) == high, id + " excessive difficulty clamps to four")
		high.attack_parameters.tell_seconds = -1.0
		high.difficulty_base_stats.max_hp = -1.0
		high.mechanics.append("test_mutation")
		if not high.get("biome_skill", {}).is_empty():
			high.biome_skill["id"] = "test_mutation"
		check(var_to_str(base) == original, id + " returned nested parameters, base stats and arrays do not mutate input")
	check(Difficulty.apply({}, 4).is_empty(), "legacy empty profile remains supported")
	var boss: Dictionary = BossProfilesScript.resolve("BO02", 4)
	check(Difficulty.apply(boss, 4) == boss, "ordinary difficulty helper does not compound the boss difficulty profile")


func _fixture() -> void:
	Game.run.hero_id = "CH02"
	Game.run.level = 8
	Game.run.loadout_snapshot = {}
	Game.run.equipment_snapshot = {}
	Game.run.stats = StatResolver.resolve("CH02", 8, {}, {})
	for stat: String in ["armor", "magic_resist", "damage_reduction", "equipment_damage_reduction", "crit_chance"]:
		Game.run.stats[stat] = 0.0
	Game.run.stats["max_hp"] = 100000.0
	Game.run.max_hp = 100000.0
	Game.run.hp = 100000.0
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.layout_id = "L01"
	room.run_seed = 41827
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	_clear_enemies()
	room.player.position = Vector2(1200, 800)


func _clear_enemies() -> void:
	room.enemy_skills.reset_room()
	for actor: Node in room.enemies.get_children():
		actor.free()
	for shot: Node in room.projectiles.get_children():
		shot.free()
	room.enemy_corpses.clear()


func _check_actor(actor: EnemyActor, expected: Dictionary, label: String) -> void:
	check(actor != null, label + " creates a real EnemyActor")
	if actor == null:
		return
	near(actor.health.maximum, float(expected.max_hp), label + " applies HP to actual health")
	near(actor.contact_damage, float(expected.damage), label + " applies skill/contact damage")
	near(actor.move_speed, float(expected.move_speed), label + " applies movement speed")
	near(actor.armor, float(expected.armor), label + " applies armor")
	near(actor.magic_resist, float(expected.magic_resist), label + " applies magic resistance")
	check(int(actor.profile.difficulty) == room.difficulty, label + " runtime inherits room difficulty")
	near(float(actor.brain.parameters.recovery_seconds), float(expected.recovery_seconds), label + " actual brain receives scaled cadence")


func _test_all_encounter_plans_and_spawns() -> void:
	check(Catalog.room_ids().size() == 24, "all 24 room layouts are exercised")
	for room_id: String in Catalog.room_ids():
		for zone: int in range(3):
			var previous_total: int = -1
			for difficulty: int in range(5):
				room.difficulty = difficulty
				var plan: Dictionary = Profiles.encounter_plan(room_id, zone, difficulty)
				var label: String = "%s Z%d D%d" % [room_id, zone, difficulty]
				check(not plan.is_empty(), label + " produces a finite encounter plan")
				if plan.is_empty():
					continue
				check(int(plan.total_count) > previous_total, label + " natural enemy total strictly increases")
				previous_total = int(plan.total_count)
				var counted: int = 0
				for batch: Array in plan.waves:
					for member: Dictionary in batch:
						counted += 1
						var base: Dictionary = Profiles.resolve(str(member.enemy_id), int(member.enemy_level), str(member.rank))
						var expected: Dictionary = Difficulty.apply(base, difficulty)
						for stat: String in GROWING_STATS:
							near(float(member[stat]), float(expected[stat]), label + " planned " + str(member.enemy_id) + " scales " + stat)
						check(int(member.difficulty) == difficulty, label + " all queued members retain difficulty")
					check(batch.size() <= 6, label + " each reinforcement batch respects the six-enemy zone cap")
				check(counted == int(plan.total_count), label + " cumulative total includes every queued batch")
				# Every room/zone/difficulty sends a pre-scaled member through
				# production spawn, detecting double application at that boundary.
				var member: Dictionary = plan.waves[0][0]
				var snapshot: String = var_to_str(member)
				var actor: EnemyActor = room.spawn_enemy(Vector2(900, 800), str(member.enemy_id), int(member.enemy_level), {"profile":member, "zone_index":zone})
				_check_actor(actor, member, label + " pre-scaled member")
				check(var_to_str(member) == snapshot, label + " real spawn leaves encounter plan immutable")
				if actor != null:
					check(actor.reward_enabled and actor.owner_enemy == null and actor.zone_index == zone, label + " natural actor retains rewards and zone")
					actor.free()


func _test_capped_level_real_waves() -> void:
	var capped_rooms: Array[String] = []
	for room_id: String in Catalog.room_ids():
		if str(Catalog.room(room_id).biome_id) == "B04":
			capped_rooms.append(room_id)
	check(capped_rooms.size() == 6, "six B04 rooms exercise the capped third encounter zone")
	for room_id: String in capped_rooms:
		var previous_hp: float = 0.0
		var previous_damage: float = 0.0
		for difficulty: int in [2, 3, 4]:
			room.difficulty = difficulty
			var plan: Dictionary = Profiles.encounter_plan(room_id, 2, difficulty)
			check(int(plan.enemy_level) == 20, room_id + " third zone caps at Lv20 from D2")
			var actual_total: int = 0
			var witness_hp: float = 0.0
			var witness_damage: float = 0.0
			for batch: Array in plan.waves:
				for member: Dictionary in batch:
					var actor: EnemyActor = room.spawn_enemy(Vector2(900 + actual_total * 2, 800), str(member.enemy_id), int(member.enemy_level), {"profile":member, "zone_index":2})
					_check_actor(actor, member, "%s capped third-zone D%d actual wave member" % [room_id, difficulty])
					if actor != null:
						actual_total += 1
						check(actor.enemy_level == 20, room_id + " real member retains level twenty")
						if actor.enemy_id == "M28" and actor.rank == "normal":
							witness_hp = actor.health.maximum
							witness_damage = actor.contact_damage
				check(room.enemies.get_child_count() == batch.size(), room_id + " complete capped wave materializes concurrently")
				_clear_enemies()
			check(actual_total == int(plan.total_count), room_id + " capped plan materializes every finite queued member")
			check(witness_hp > previous_hp and witness_damage > previous_damage, "%s capped M28 D%d actual HP and damage continue increasing" % [room_id, difficulty])
			previous_hp = witness_hp
			previous_damage = witness_damage


func _test_direct_and_owned_spawns() -> void:
	for difficulty: int in range(5):
		room.difficulty = difficulty
		_clear_enemies()
		var ordinary: EnemyActor = room.spawn_enemy(Vector2(900, 800), "M12", 20, {"zone_index":0})
		_check_actor(ordinary, Difficulty.apply(Profiles.resolve("M12", 20), difficulty), "D%d direct M12" % difficulty)
		if ordinary == null:
			continue
		var child: EnemyActor = room.spawn_enemy_summon(ordinary, "M14", Vector2(950, 800))
		_check_actor(child, Difficulty.apply(Profiles.resolve("M14", 20), difficulty), "D%d ordinary summon" % difficulty)
		if child != null:
			check(child.owner_enemy != null and child.owner_enemy.get_ref() == ordinary and not child.reward_enabled, "ordinary summon retains actual ownership and disables rewards")
			_no_reward_on_defeat(child, "ordinary summon")
		_clear_enemies()
		var boss: BossActor = BossScript.new()
		boss.room = room
		boss.position = Vector2(900, 800)
		check(boss.configure_boss("BO02", difficulty, 777), "D%d configures real summoning boss" % difficulty)
		room.enemies.add_child(boss)
		var boss_child: EnemyActor = room.spawn_enemy_summon(boss, "M14", Vector2(950, 800))
		_check_actor(boss_child, Difficulty.apply(Profiles.resolve("M14", boss.enemy_level), difficulty), "D%d boss summon" % difficulty)
		if boss_child != null:
			check(boss_child.owner_enemy != null and boss_child.owner_enemy.get_ref() == boss and not boss_child.reward_enabled, "boss summon retains actual ownership and disables rewards")
			_no_reward_on_defeat(boss_child, "boss summon")
		var reinforcement: EnemyActor = room.spawn_enemy(Vector2(950, 850), "M10", boss.enemy_level, boss.reinforcement_spawn_options())
		_check_actor(reinforcement, Difficulty.apply(Profiles.resolve("M10", boss.enemy_level), difficulty), "D%d boss reinforcement" % difficulty)
		if reinforcement != null:
			check(reinforcement.owner_enemy.get_ref() == boss and not reinforcement.reward_enabled, "boss reinforcement options keep ownership and no rewards")
			_no_reward_on_defeat(reinforcement, "boss reinforcement")
		_clear_enemies()


func _no_reward_on_defeat(actor: EnemyActor, label: String) -> void:
	var before: Array = [Game.run.kills, Game.run.hero_xp_gained, Game.run.gold, room.gold_drops.size(), room.enemy_corpses.size()]
	actor.take_damage(100000.0, &"equipment", Vector2.RIGHT, {"damage_type":"true"})
	check(not actor.is_alive(), label + " actually dies through production damage")
	check(before == [Game.run.kills, Game.run.hero_xp_gained, Game.run.gold, room.gold_drops.size(), room.enemy_corpses.size()], label + " death grants no kill, XP, gold or loot corpse")
	actor.free()


func _reset_player() -> void:
	room.player.status = CombatStatus.new()
	room.player._enemy_status_origins.clear()
	room.player.invulnerable = 0.0
	Game.run.hp = Game.run.max_hp
	Game.run.shield = 0.0


func _test_real_skill_damage() -> void:
	var previous_projectile: float = 0.0
	var previous_area: float = 0.0
	var previous_dot: float = 0.0
	for difficulty: int in range(5):
		room.difficulty = difficulty
		_clear_enemies()
		_reset_player()
		var shooter: EnemyActor = room.spawn_enemy(Vector2(900, 800), "M03", 20)
		check(shooter != null, "skill projectile caster spawns")
		if shooter == null:
			continue
		shooter.state = &"ready"
		var shot: Dictionary = shooter.brain._projectile({"count":1, "projectile_angles":[], "spread_degrees":0.0})
		shot["origin"] = shooter.position
		shot["target"] = room.player.position
		shooter.cast_enemy_skill(shot)
		check(room.enemy_skills.projectiles.size() == 1, "D%d actual brain command emits a real projectile" % difficulty)
		near(Game.run.hp, Game.run.max_hp, "projectile preserves its visible travel delay")
		for step: int in range(80):
			room.enemy_skills.advance(0.02)
			if Game.run.hp < Game.run.max_hp:
				break
		var projectile_damage: float = Game.run.max_hp - Game.run.hp
		near(projectile_damage, shooter.contact_damage * float(shot.damage_multiplier), "D%d actual projectile deals scaled damage" % difficulty)
		check(projectile_damage > previous_projectile, "D%d real projectile damage strictly increases" % difficulty)
		previous_projectile = projectile_damage
		_clear_enemies()
		_reset_player()
		var acid: EnemyActor = room.spawn_enemy(Vector2(900, 800), "M11", 20)
		check(acid != null, "skill ground-area caster spawns")
		if acid == null:
			continue
		acid.state = &"ready"
		var acid_commands: Array[Dictionary] = acid.brain._build_sequence()
		check(not acid_commands.is_empty() and acid_commands[0].kind == "ground_area" and acid_commands[0].status.id == "corrosion", "M11 actual authored sequence provides its acid ground area and DOT")
		if acid_commands.is_empty():
			continue
		var area: Dictionary = acid_commands[0].duplicate(true)
		area["origin"] = acid.position
		area["target"] = room.player.position
		area["targets"] = [room.player.position]
		acid.cast_enemy_skill(area)
		var area_damage: float = Game.run.max_hp - Game.run.hp
		near(area_damage, acid.contact_damage * float(area.damage_multiplier), "D%d actual landing area deals scaled damage" % difficulty)
		check(area_damage > previous_area, "D%d actual ground-area damage strictly increases" % difficulty)
		previous_area = area_damage
		check(room.player.status.has("corrosion"), "actual acid hit applies real player corrosion")
		if room.player.status.has("corrosion"):
			near(float(room.player.status.states.corrosion.power), area_damage, "DOT snapshots the scaled skill damage")
		# Remove the lingering area before advancing the real player, isolating
		# its first one-second status tick from repeat ground-area contacts.
		room.enemy_skills.reset_room()
		var before_dot: float = Game.run.hp
		room.player._physics_process(1.0)
		var dot_damage: float = before_dot - Game.run.hp
		near(dot_damage, area_damage * 0.08, "D%d actual player corrosion DOT deals scaled periodic damage" % difficulty)
		check(dot_damage > previous_dot, "D%d real DOT damage strictly increases" % difficulty)
		previous_dot = dot_damage
	_clear_enemies()
