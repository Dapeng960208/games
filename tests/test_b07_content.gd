extends SceneTree
## Pure B07 authored-data, geometry and shared numerical-contract checks.
## Parent runs this under the shared Godot lock with isolated userdata.
const Content = preload("res://scripts/world/b07_content.gd")
const Geometry = preload("res://scripts/world/b07_room_geometry.gd")
const Numbers = preload("res://scripts/combat/b07_enemy_numbers.gd")
const Calibration = preload("res://scripts/combat/enemy_calibration.gd")
const Species = preload("res://scripts/combat/enemy_species_policy.gd")
const BossPolicy = preload("res://scripts/combat/boss_progression_policy.gd")
var failures: Array = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func same_numbers(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size(): return false
	for index in expected.size():
		if float(actual[index]) != float(expected[index]): return false
	return true

func _initialize() -> void:
	check(Content.validate().is_empty(), "content validation: " + str(Content.validate()))
	var data := Content.catalog()
	check(not data.is_empty(), "catalog loads")
	if data.is_empty():
		finish()
		return
	check(Content.enemy_ids().size() == 18, "18 independent B07 identities")
	check(Content.room_ids() == ["L37","L38","L39","L40","L41","L42","BO07"], "six rooms and boss arena")
	check(Content.enemy("B06-M01").is_empty() and Content.room("L36").is_empty(), "foreign identities rejected")
	check(same_numbers(data.progression.zone_levels, [31,33,35]) and data.progression.previous_boss == "BO06", "progression prerequisites")
	check(data.mechanics.sun_mirror.state_count == 3 and data.mechanics.sun_mirror.interaction_seconds == .6, "three-state channel")
	check(data.mechanics.camouflage.minimum_body_opacity >= .35 and data.mechanics.camouflage.actual_damage_reveal_seconds == 3, "visible camouflage contract")
	check(data.mechanics.sunscale.frontal_angle_degrees == 120 and data.mechanics.sunscale.player_damage_reflection == false, "bounded sunscale defense")
	check(Content.room("L42").wave_count == 3, "L42 finite three waves")
	var copy := Content.enemy("B07-M01")
	copy.raw_stats.max_hp = 1
	check(Content.enemy("B07-M01").raw_stats.max_hp == 78, "deep-copy enemy contract")
	for id: String in Content.room_ids():
		check(Geometry.validate(id).is_empty(), id + " valid protected geometry: " + str(Geometry.validate(id)))
		var geometry := Geometry.room(id)
		if geometry.is_empty(): continue
		check(Geometry.polygon(id).size() >= 3 and Geometry.area(Geometry.polygon(id)) > 0, id + " walkable polygon")
		check(geometry.safe_route_width >= 180 and geometry.puzzle_beam_player_damage == 0, id + " safe route/light")
		check(geometry.manual_gates.size() == (0 if id == "BO07" else 2), id + " manual fallback on both sides")
		for mirror: Dictionary in geometry.mirrors:
			check(mirror.states.size() == 3 and mirror.initial_state == 0, id + " three fixed directions")
			check(geometry.altar.id in mirror.states[1].targets, id + " altar alignment")
			for state in range(3):
				var beam := Geometry.beam_path(id, mirror.id, state)
				check(beam.size() >= 2 and beam[0] == Geometry.world_point(mirror.position), id + " scaled fixed beam")
			check(Geometry.protected_interaction(id, Geometry.world_point(mirror.position)), id + " mirror exclusion radius")
	check(same_numbers(Geometry.room("L37").mirrors[0].position, [980,630]), "documented L37 35/35 mirror")
	check(same_numbers(Geometry.room("L37").altar.position, [1904,630]), "documented L37 68/35 disc")
	check(same_numbers(Geometry.room("L39").mirrors[0].position, [700,1170]) and same_numbers(Geometry.room("L39").mirrors[1].position, [2100,540]), "documented L39 mirrors")
	check(Geometry.room("BO07").mirrors.size() == 4 and Geometry.room("BO07").required_mirrors == 2, "boss four mirrors any two")
	var snapshot := Calibration.archived(15)
	for id: String in Content.enemy_ids():
		var authored := Content.enemy(id)
		for difficulty in range(5):
			check(Content.skills_for_difficulty(id, difficulty).size() == (1 if difficulty < 2 else 2 if difficulty < 4 else 3), id + " cumulative skills")
		for level: int in Numbers.LEVELS:
			var previous_hp := 0
			var previous_attack := 0
			for difficulty in range(5):
				var normal := Numbers.ordinary(id, level, difficulty, "normal", snapshot, 4)
				var elite := Numbers.ordinary(id, level, difficulty, "elite", snapshot, 4)
				check(not normal.is_empty() and not elite.is_empty(), id + " shared species resolves")
				if normal.is_empty() or elite.is_empty(): continue
				check(normal.enemy_id == id and normal.chapter == 7 and normal.enemy_level == level and normal.biome_id == "B07", id + " chapter identity")
				check(normal.max_hp > previous_hp and normal.damage > previous_attack, id + " fixed D growth")
				check(elite.max_hp > normal.max_hp and elite.damage > normal.damage, id + " elite factor")
				var archetype: String = {"F":"skirmisher","R":"skirmisher","C":"caster","S":"support","A":"assassin","T":"tank"}[authored.profile]
				var shared := Species.stats(id, authored.raw_stats, archetype, level, 7, difficulty, "normal")
				for field: String in ["max_hp","damage","armor","magic_resist","ability_power","skill_base_power"]:
					check(normal.get(field) == shared.get(field), id + " single shared factor " + field)
				check(Numbers.skill_damage(normal, 0) == 0, id + " harmless packet")
				var saved: Dictionary = JSON.parse_string(JSON.stringify(normal))
				check(Numbers.skill_damage(saved, 100) == Numbers.skill_damage(normal, 100), id + " numerical snapshot roundtrip")
				previous_hp = int(normal.max_hp)
				previous_attack = int(normal.damage)
	var previous_boss_hp := 0
	for difficulty in range(5):
		var boss := Numbers.boss(difficulty, snapshot, 4)
		check(not boss.is_empty(), "BO07 resolves D%d" % difficulty)
		if boss.is_empty(): continue
		check(boss.enemy_id == "BO07" and boss.boss_id == "BO07" and boss.enemy_level == 35 and boss.chapter == 7, "BO07 runtime identity")
		check(boss.max_hp > previous_boss_hp, "BO07 D growth")
		var policy := BossPolicy.stats(7, difficulty)
		var earlier := BossPolicy.stats(6, difficulty)
		for field: String in ["max_hp","damage","armor","magic_resist"]:
			check(boss.get(field) == policy.get(field), "BO07 shared boss field " + field)
			check(float(boss.get(field, 0)) > float(earlier.get(field, 0)), "B06 to B07 monotonic " + field)
		check(Numbers.skill_damage(boss, 120) > 0, "BO07 valid damage packet")
		previous_boss_hp = int(boss.max_hp)
	var legacy := Numbers.boss(0, {}, 1)
	check(legacy.get("max_hp") == 27864 and legacy.get("damage") == 559, "documented authored boss arithmetic")
	check(Numbers.ordinary("B06-M01", 31, 0, "normal", snapshot, 4).is_empty(), "reject previous chapter resolver ID")
	check(Numbers.ordinary("B07-M01", 32, 0, "normal", snapshot, 4).is_empty(), "reject unauthored room level")
	check(Numbers.boss(5, snapshot, 4).is_empty(), "reject unsupported D")
	var malformed := data.duplicate(true)
	malformed.runtime_enabled = true
	check(not Content.validate_data(malformed).is_empty(), "reader cannot enable chapter")
	malformed = data.duplicate(true)
	malformed.enemies["B07-M01"].raw_stats.max_hp = -1
	check(not Content.validate_data(malformed).is_empty(), "reject invalid raw stat")
	malformed = data.duplicate(true)
	malformed.room_geometry.L37.mirrors[0].states.pop_back()
	check(not Content.validate_data(malformed).is_empty(), "reject two-state mirror")
	finish()

func finish() -> void:
	for failure: String in failures: push_error(failure)
	print("B07 content/geometry/numbers: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
