extends SceneTree
## Pure-content and budget acceptance. Executed skills are tested separately.
const Profiles = preload("res://scripts/domain/combat/enemy_profiles.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ENEMY PROFILE FAIL: " + description)

func _run() -> void:
	_boundaries_and_isolation()
	_all_levels()
	_encounters()
	_hero_independence()
	print("ENEMY_PROFILE_TESTS checks=" + str(checks) + " failures=" + str(failures) + " prototypes=54 levels=20 tiers=4")
	quit(0 if failures == 0 else 1)

func _boundaries_and_isolation() -> void:
	_check(Profiles.resolve("").is_empty() and Profiles.resolve("M55").is_empty() and Profiles.resolve("BO01").is_empty(), "unknown and boss IDs cannot become ordinary profiles")
	_check(Profiles.resolve("M01", -100)["enemy_level"] == 1, "negative level clamps to one")
	_check(Profiles.resolve("M01", 999)["enemy_level"] == 20, "oversize level clamps to twenty")
	_check(Profiles.resolve("M01", 20, "boss")["rank"] == "normal", "ordinary profile cannot invent boss rank")
	_check(Profiles.resolve("M01", 20)["rank"] == "normal", "level twenty does not silently promote to elite")
	var original: Dictionary = Profiles.resolve("M13", 15)
	var detached: Dictionary = Profiles.resolve("M13", 15)
	detached["attack_parameters"]["combo_angles"][0] = 999
	detached["mechanics"].clear()
	detached["behavior_graph"].clear()
	detached["summon_ownership"]["counts_toward_cap"] = false
	detached["scene_dependency_ids"].append("fake")
	_check(Profiles.resolve("M13", 15) == original, "nested profile parameters and metadata return independent deep copies")
	_check(Catalog.enemy("M13")["behavior_graph"].size() == 4 and Catalog.enemy("M13")["summon_ownership"]["counts_toward_cap"], "resolving never mutates original catalog")
	_check(Profiles.resolve("M01", 20)["effective_threat_cost"] == 4, "level twenty ordinary threat accounts for tier")
	_check(Profiles.resolve("M01", 20, "elite")["effective_threat_cost"] == 6, "elite base rounding precedes tier cost")
	_check(Profiles.resolve("M03", 20, "elite")["effective_threat_cost"] == 9, "odd base elite cost is ceil(ceil(3*1.5)*1.75)")
	_check(Profiles.encounter("unknown", 0).is_empty() and Profiles.encounter("L01", -1).is_empty() and Profiles.encounter("L01", 3).is_empty(), "unknown rooms and invalid zone indices fail closed")
	for service_id: String in Catalog.services():
		_check(Profiles.encounter(service_id, 0).is_empty(), service_id + " service does not receive a combat fallback")
	_check(Profiles.encounter("L01", 0, -50) == Profiles.encounter("L01", 0, 0), "negative difficulty clamps without changing encounter seed")
	_check(Profiles.encounter("L01", 0, 999) == Profiles.encounter("L01", 0, 4), "difficulty has five explicit tiers, zero through four")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://data/monsters/enemy_progression.json")))
	_check(source["profiles"].size() == 54, "exactly 54 authored ordinary progression definitions")
	var identities: Array[String] = []
	for id: String in Catalog.enemy_ids():
		var authored: Dictionary = source["profiles"][id]
		_check(authored["tiers"].size() == 4, id + " has four finite authored tiers")
		var identity: String = str(authored["tiers"][0]["add_mechanics"][0])
		_check(not identities.has(identity), id + " owns a distinct base mechanic")
		identities.append(identity)
		for tier: int in range(1, 4):
			var patch: Dictionary = authored["tiers"][tier]["parameters"]
			_check(not authored["tiers"][tier]["add_mechanics"].is_empty(), id + " tier " + str(tier + 1) + " adds a named mechanic")
			var changes_combat_decision: bool = false
			for key: String in patch:
				if key in ["combo_count", "combo_angles", "projectile_count", "projectile_angles", "path_mode", "hazard_offsets", "support_targets", "summon_count", "line_count", "max_active_hazards", "relocate_after_attacks", "shield_turn_degrees", "ring_gap_degrees", "exposure_seconds"]:
					changes_combat_decision = true
			_check(changes_combat_decision, id + " tier " + str(tier + 1) + " changes pattern, support, geometry, or counter window beyond HP/damage")

func _all_levels() -> void:
	for id: String in Catalog.enemy_ids():
		var base: Dictionary = Catalog.enemy(id)
		var prior_hp: float = 0.0
		var prior_damage: float = 0.0
		for level: int in range(1, 21):
			var value: Dictionary = Profiles.resolve(id, level)
			var parameters: Dictionary = value["attack_parameters"]
			var label: String = id + " L" + str(level)
			var expected_tier: int = 1 if level < 5 else (2 if level < 10 else (3 if level < 15 else 4))
			_check(value["enemy_level"] == level and value["mechanic_tier"] == expected_tier, label + " resolves level and correct tier")
			_check(value["mechanics"].size() == expected_tier, label + " adds exactly one finite mechanic per tier")
			_check(value["behavior_id"] == base["behavior_id"] and value["threat_cost"] == base["threat_cost"], label + " preserves prototype and base budget")
			_check(value["gameplay_implemented"] == base["gameplay_implemented"] and value["progression_scope"] == "authored_parameters_only", label + " progression does not overclaim gameplay completion")
			_check(value["max_hp"] > prior_hp and value["damage"] > prior_damage, label + " bounded growth is stronger than preceding level")
			_check(value["max_hp"] <= 180.0 and value["damage"] <= 25.0 and value["move_speed"] <= 132.0 and value["armor"] <= 24.0, label + " bounded ordinary stats")
			_check(float(parameters["tell_seconds"]) >= float(base["minimum_tell_seconds"]), label + " preserves catalog tell floor")
			_check(float(parameters["locked_line_delay_seconds"]) >= 0.4 and not parameters["track_after_lock"], label + " locked line is stationary for reaction window")
			_check(float(parameters["area_tell_seconds"]) >= 0.8 and float(parameters["combo_gap_seconds"]) >= 0.55, label + " area and numbered followup tells remain readable")
			_check(float(value["recovery_seconds"]) >= 0.45 and float(parameters["exposure_seconds"]) >= 0.45 and value["recovery_seconds"] >= parameters["exposure_seconds"], label + " preserves counterattack window")
			_check(not parameters["spawn_can_damage"] and parameters["spawn_grace_seconds"] >= 0.8, label + " spawning cannot deal immediate damage")
			_check(parameters["combo_count"] <= 3 and parameters["projectile_count"] <= 3 and parameters["max_active_hazards"] <= 2 and parameters["support_targets"] <= 3, label + " action counts remain bounded")
			_check(value["attack_range"] == parameters["range"] and value["recovery_seconds"] == parameters["recovery"] and parameters["hazard_cap"] == parameters["max_active_hazards"], label + " runtime aliases agree")
			if level in [5, 10, 15]:
				_check(parameters != Profiles.resolve(id, level - 1)["attack_parameters"], label + " tier boundary changes executable parameters")
			var elite: Dictionary = Profiles.resolve(id, level, "elite")
			_check(elite["rank"] == "elite" and elite["max_hp"] > value["max_hp"] and elite["effective_threat_cost"] > value["effective_threat_cost"], label + " explicit elite remains separate and costs more")
			if id == "M36":
				var elite_ring: Dictionary = elite["attack_parameters"]
				_check(elite["mechanics"].has("elite_ring_safe_gap") and not elite["mechanics"].has("elite_marked_aftershock"), label + " elite ring declares its actual single-discharge affix")
				var declares_aftershock: bool = false
				for key: String in elite_ring:
					declares_aftershock = declares_aftershock or key.begins_with("elite_aftershock")
				_check(not declares_aftershock and elite_ring["detonate_count"] == 1 and not elite_ring["death_explosion"], label + " elite cannot declare an unexecuted second blast")
				_check(elite_ring["ring_gap_degrees"] >= 50.0 and elite_ring["fuse_seconds"] >= 1.6 and elite_ring["radius"] >= 95.0, label + " elite single ring has a visible safe gap and extended fuse")
			else:
				_check(elite["attack_parameters"]["elite_aftershock_tell_seconds"] >= 0.8 and elite["mechanics"].has("elite_marked_aftershock"), label + " elite gets one readable authored affix")
			_check(value["mechanic_tier"] <= 4, label + " tier growth stops at four")
			prior_hp = float(value["max_hp"])
			prior_damage = float(value["damage"])
		_check(Profiles.resolve(id, 20)["attack_parameters"] == Profiles.resolve(id, 1000)["attack_parameters"], id + " excess levels cannot accumulate more mechanics")
	for level: int in range(1, 21):
		_check(Profiles.resolve("M11", level)["attack_parameters"]["max_active_hazards"] == 2, "M11 keeps at most two acid pools")
		var summon: Dictionary = Profiles.resolve("M12", level)["attack_parameters"]
		_check(summon["summon_cap"] == 2 and not summon["summon_rewards"] and summon["reserve_summon_budget"], "M12 keeps finite reserved unrewarding summons")
		_check(Profiles.resolve("M17", level)["attack_parameters"]["heal_limit_per_target"] == 2 and Profiles.resolve("M17", level)["attack_parameters"]["exclude_support_recipients"], "M17 has per-wave per-target cap and no mutual support loop")
		_check(Profiles.resolve("M31", level)["attack_parameters"]["refraction_count"] == 1, "M31 never gains infinite reflections")
		_check(Profiles.resolve("M33", level)["attack_parameters"]["line_count"] <= 2, "M33 never exceeds two breakable lines")
		_check(not Profiles.resolve("M36", level)["attack_parameters"]["death_explosion"] and Profiles.resolve("M36", level)["attack_parameters"]["detonate_count"] == 1, "M36 safe disarm remains single discharge")

func _encounters() -> void:
	var found_summoner: bool = false
	var found_elite: bool = false
	# Independent acceptance fixtures: expected natural actors over ALL batches.
	var expected_zone_counts: Array = [
		[[9,9,10], [10,10,12], [12,12,13], [13,13,14], [14,14,16]],
		[[10,10,12], [12,12,13], [13,13,14], [14,14,16], [16,16,17]],
		[[12,12,13], [13,13,14], [14,14,16], [16,16,17], [17,17,19]],
		[[13,13,14], [14,14,16], [16,16,17], [17,17,19], [19,19,20]]
	]
	var expected_budgets: Array = [
		[[10,12,14], [12,14,16], [14,16,18], [16,18,20], [18,20,22]],
		[[14,16,18], [16,18,20], [18,20,22], [20,22,24], [22,24,26]],
		[[18,20,22], [20,22,24], [22,24,26], [24,26,26], [26,26,26]],
		[[22,24,26], [24,26,26], [26,26,26], [26,26,26], [26,26,26]]
	]
	var allowed_fillers: Dictionary = {"B01": ["M01","M04"], "B02": ["M10","M14"], "B03": ["M27","M19"], "B04": ["M28"]}
	_check(Profiles.encounter_plan("unknown", 0).is_empty() and Profiles.encounter_plan("L01", 3).is_empty(), "invalid plans fail closed")
	for room_id: String in Catalog.room_ids():
		var room: Dictionary = Catalog.room(room_id)
		var biome: int = int(str(room["biome_id"]).trim_prefix("B"))
		var authored_ids: Array[String] = []
		for reference: Dictionary in room["reference_wave"]:
			authored_ids.append(str(reference["enemy_id"]))
		for difficulty: int in range(5):
			var room_count: int = 0
			var total_elites: int = 0
			for zone: int in range(3):
				var label: String = room_id + " D" + str(difficulty) + " Z" + str(zone)
				var plan: Dictionary = Profiles.encounter_plan(room_id, zone, difficulty)
				_check(not plan.is_empty(), label + " has a finite combat plan")
				if plan.is_empty():
					continue
				var waves: Array = plan["waves"]
				_check(plan == Profiles.encounter_plan(room_id, zone, difficulty), label + " deterministic without mutable RNG")
				_check(Profiles.encounter(room_id, zone, difficulty) == waves[0] and Profiles.encounter_waves(room_id, zone, difficulty) == waves, label + " compatibility only spawns first batch")
				_check(waves.size() >= 2 and plan["wave_count"] == waves.size(), label + " contains real queued reinforcement batches")
				_check(plan["total_count"] == expected_zone_counts[biome - 1][difficulty][zone], label + " reaches independently authored density target")
				_check(plan["concurrent_threat_budget"] == expected_budgets[biome - 1][difficulty][zone], label + " exposes exact concurrent threat budget")
				_check(plan["concurrent_cap"] == 6 and plan["room_cap"] == 18, label + " distinguishes concurrent caps from cumulative actors")
				_check(plan["reinforce_alive_threshold"] == 2 and plan["reinforce_threat_fraction"] == 0.3 and plan["reinforce_delay_seconds"] == 3.0, label + " reinforcements wait for low live pressure and real elapsed time")
				_check(plan["spawn_grace_seconds"] >= 0.8 and plan["minimum_player_spawn_distance"] >= 360.0 and plan["completion_requires_all_waves"], label + " safe emergence and queued-wave completion contract")
				var zone_count: int = 0
				var zone_threat: int = 0
				var support_count: int = 0
				var functional_count: int = 0
				var summoner_count: int = 0
				var seen_specials: Array[String] = []
				var first_summon_seats: int = 0
				for wave_index: int in range(waves.size()):
					var group: Array = waves[wave_index]
					var spent: int = 0
					var occupancy: int = 0
					var specialists: int = 0
					_check(not group.is_empty() and (wave_index == 0 or group.size() <= 3), label + " later batches contain one to three actors")
					for member: Dictionary in group:
						var id: String = str(member["enemy_id"])
						spent += int(member["encounter_budget_cost"])
						occupancy += 1 + int(member["reserved_summon_count"])
						_check(member["enemy_level"] == mini(20, 1 + (biome - 1) * 4 + zone * 2 + difficulty * 2), label + " level comes from area and chosen difficulty")
						_check(member["biome_id"] == room["biome_id"] and (authored_ids.has(id) or allowed_fillers[room["biome_id"]].has(id)), label + " uses reference specialists or same-biome reinforcement pool")
						_check(member["encounter_budget_cost"] == member["effective_threat_cost"] + member["reserved_summon_threat"] and member["encounter_slot_cost"] == 1 + member["reserved_summon_count"], label + " reserves summon threat and seats before spawn")
						_check(member["wave_index"] == wave_index and member["zone_index"] == zone, label + " members identify their queued batch")
						if not allowed_fillers[room["biome_id"]].has(id):
							specialists += 1
							_check(not seen_specials.has(id), label + " never duplicates its high-pressure specialist")
							seen_specials.append(id)
						if id in ["M06", "M08", "M17", "M25", "M26", "M30", "M34"]:
							support_count += 1
						if id in ["M09", "M19"]:
							functional_count += 1
						if member["rank"] == "elite":
							total_elites += 1
							found_elite = true
							_check(wave_index > 0 and zone > 0 and difficulty >= 2, label + " elite belongs to a later explicit reinforcement")
						if id == "M12":
							found_summoner = true
							summoner_count += 1
							_check(member["reserved_summon_count"] == 2 and member["reserved_summon_threat"] == 2 * Profiles.resolve("M14", member["enemy_level"])["effective_threat_cost"], "summoner reserves both matching-level children")
						if wave_index == 0:
							first_summon_seats += int(member["reserved_summon_count"])
					_check(spent <= plan["concurrent_threat_budget"] and occupancy <= 6, label + " each batch fits live caps including unborn summons")
					_check(specialists <= 1, label + " fills density with ordinary units instead of copied strong units")
					zone_count += group.size()
					zone_threat += spent
				_check(plan["initial_count"] >= 5 - first_summon_seats, label + " first screen is materially denser than old two-three actors")
				_check(zone_count == plan["total_count"] and zone_threat == plan["total_threat"], label + " displayed totals exactly equal executable queue")
				_check(support_count <= 1 and functional_count <= 1 and summoner_count <= 1, label + " support limits apply across all future batches")
				room_count += zone_count
			_check(total_elites <= 2, room_id + " full room has at most two elites across all zones and waves")
			var expected_room_counts: Array = [[28,32,37,40,44], [32,37,40,44,49], [37,40,44,49,53], [40,44,49,53,58]]
			_check(room_count == expected_room_counts[biome - 1][difficulty], room_id + " exact cumulative room count grows by difficulty")
	_check(found_summoner and found_elite, "budget acceptance actually exercises summons and elite selection")
	_check(Profiles.encounter_level("L01", 0) == 1 and Profiles.encounter_level("L07", 0) == 5 and Profiles.encounter_level("L13", 0) == 9 and Profiles.encounter_level("L19", 0) == 13, "four area starting levels are visible and fixed")
	_check(_wave_sizes(Profiles.encounter_plan("L01", 0, 0)) == [5,3,1] and _wave_sizes(Profiles.encounter_plan("L01", 2, 0)) == [5,3,2], "L01 ordinary adds finite reinforcement batches")
	_check(_wave_sizes(Profiles.encounter_plan("L01", 0, 4)) == [6,3,3,2] and _wave_sizes(Profiles.encounter_plan("L01", 2, 4)) == [6,3,3,3,1], "L01 highest difficulty independently expected batch sizes")
	var first: Dictionary = Profiles.encounter_plan("L01", 0)
	var snapshot: Dictionary = first.duplicate(true)
	first["waves"][1][0]["attack_parameters"]["combo_angles"].clear()
	first["composition"].clear()
	_check(Profiles.encounter_plan("L01", 0) == snapshot, "caller cannot mutate nested future batches or their displayed composition")

func _wave_sizes(plan: Dictionary) -> Array:
	var result: Array = []
	for batch: Array in plan.get("waves", []):
		result.append(batch.size())
	return result

func _hero_independence() -> void:
	var game: Node = root.get_node_or_null("Game")
	_check(game != null, "project Game autoload available for real hero-level independence test")
	if game == null:
		return
	var saved: Dictionary = game.profile.duplicate(true)
	game.profile["hero_xp"] = {"CH01": 0, "CH02": 0, "CH03": 0}
	_check(game.hero_level("CH01") == 1, "fixture uses actual permanent hero level one")
	var low: Dictionary = Profiles.encounter_plan("L19", 1, 1)
	var low_profile: Dictionary = Profiles.resolve("M31", 10)
	game.profile["hero_xp"] = {"CH01": 3600, "CH02": 3600, "CH03": 3600}
	_check(game.hero_level("CH01") == 20, "fixture uses actual permanent hero level twenty")
	_check(Profiles.encounter_plan("L19", 1, 1) == low and Profiles.resolve("M31", 10) == low_profile, "permanent hero growth does not secretly scale enemy stats, totals, wave queues, or budgets")
	game.profile = saved
