class_name EnemyProfiles
extends RefCounted
## Pure authored progression: no Game singleton, save, hero level, or RNG reads.
## This resolves combat parameters; catalog gameplay completion remains separate.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const Palette = preload("res://scripts/combat/enemy_palette.gd")
const DATA_PATH := "res://data/enemy_progression.json"
const MIN_LEVEL := 1
const MAX_LEVEL := 20
const MAX_DIFFICULTY := 4
const ZONE_COUNT := 3
const ZONE_CAP := 6
const ROOM_CAP := 18
const MAX_MOVE_SPEED := 132.0
const TIER_THRESHOLDS := [1, 5, 10, 15]
const BASE_ZONE_TOTALS := [6, 6, 7]
const PROTECTIVE_IDS := ["M06", "M08", "M17", "M25", "M26", "M30", "M34"]
const FUNCTIONAL_SUPPORT_IDS := ["M09", "M19"]
# Multipliers sharpen the authored roles without replacing any prototype's
# attacks. Ordinary L20 still fits the existing 180 HP / 25 damage contract.
const MAX_BASE_DAMAGE := 16.9
const ARCHETYPE_STATS := {
	"tank":{"hp":1.02,"damage":0.90,"minimum_damage":0.0,"speed":0.92,"armor":1.0,"armor_bonus":8.0,"armor_per_tier":2.0,"resist_per_tier":1.0,"recovery":1.18},
	"caster":{"hp":0.86,"damage":1.16,"minimum_damage":0.0,"speed":0.98,"armor":0.5,"armor_bonus":0.0,"armor_per_tier":1.0,"resist_per_tier":2.0,"recovery":1.12},
	"assassin":{"hp":0.72,"damage":1.20,"minimum_damage":15.0,"speed":1.10,"armor":0.25,"armor_bonus":0.0,"armor_per_tier":0.5,"resist_per_tier":0.5,"recovery":1.0},
	"skirmisher":{"hp":1.0,"damage":1.0,"minimum_damage":0.0,"speed":1.0,"armor":1.0,"armor_bonus":0.0,"armor_per_tier":2.0,"resist_per_tier":1.0,"recovery":1.0},
	"support":{"hp":0.96,"damage":0.90,"minimum_damage":0.0,"speed":0.95,"armor":1.0,"armor_bonus":0.0,"armor_per_tier":1.0,"resist_per_tier":1.5,"recovery":1.12}
}
const REINFORCEMENT_POOLS := {
	"B01": ["M04", "M01", "M04"],
	"B02": ["M14", "M10", "M14"],
	"B03": ["M27", "M27", "M19"],
	"B04": ["M28"]
}
static var _data: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		_data = parsed

static func resolve(enemy_id: String, enemy_level: int = 1, rank: String = "normal") -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = Catalog.enemy(enemy_id)
	var authored: Dictionary = _data.get("profiles", {}).get(enemy_id, {})
	if result.is_empty() or authored.is_empty():
		return {}
	var level: int = clampi(enemy_level, MIN_LEVEL, MAX_LEVEL)
	var tier: int = 1
	for threshold: int in TIER_THRESHOLDS:
		if level >= threshold:
			tier = TIER_THRESHOLDS.find(threshold) + 1
	var resolved_rank: String = "elite" if rank == "elite" else "normal"
	var parameters: Dictionary = {}
	var mechanics: Array[String] = []
	var descriptions: Array[String] = []
	for step: Dictionary in authored.get("tiers", []):
		if int(step.get("tier", 1)) > tier:
			break
		parameters.merge(step.get("parameters", {}).duplicate(true), true)
		for mechanic: String in step.get("add_mechanics", []):
			if not mechanics.has(mechanic):
				mechanics.append(mechanic)
		descriptions.append(str(step.get("description", "")))
	var stats: Dictionary = authored.get("base_stats", {})
	var rules: Dictionary = _data.get("level_rules", {})
	var archetype: String = str(result.get("archetype","skirmisher"))
	if not ARCHETYPE_STATS.has(archetype): archetype = "skirmisher"
	var identity: Dictionary = ARCHETYPE_STATS[archetype]
	var hp_scale: float = 1.0 + float(level - 1) * float(rules.get("hp_per_level", 0.055))
	var damage_scale: float = 1.0 + float(level - 1) * float(rules.get("damage_per_level", 0.025))
	if resolved_rank == "elite":
		hp_scale *= float(rules.get("elite_hp_multiplier", 1.2))
		damage_scale *= float(rules.get("elite_damage_multiplier", 1.12))
		if enemy_id == "M36":
			# One discharge is this prototype's counterplay contract, including elites.
			# A wider single ring preserves a visible escape gap and longer fuse.
			mechanics.append("elite_ring_safe_gap")
			parameters["ring_gap_degrees"] = maxf(50.0, float(parameters.get("ring_gap_degrees", 0.0)))
			parameters["fuse_seconds"] = maxf(1.6, float(parameters.get("fuse_seconds", 1.3)))
			parameters["radius"] = maxf(95.0, float(parameters.get("radius", 85.0)))
		else:
			mechanics.append("elite_marked_aftershock")
			parameters["elite_aftershock"] = true
			parameters["elite_aftershock_tell_seconds"] = 0.8
			parameters["elite_aftershock_width"] = 20.0
			parameters["elite_aftershock_duration"] = 0.35
			parameters["elite_aftershock_damage_multiplier"] = 0.35
	_enforce_safety(enemy_id, result, parameters)
	# High levels recover slightly faster only from the role's added delay.
	# Authored exposure, telegraph and followup windows are never compressed.
	var cadence_scale: float = maxf(1.0,float(identity.recovery)-float(level-1)*0.005)
	var recovery: float = maxf(float(stats.get("recovery_seconds", 0.9)), float(parameters["recovery_seconds"]))*cadence_scale
	parameters["recovery_seconds"] = recovery
	parameters["recovery"] = recovery
	parameters["attack_range"] = float(parameters.get("range", stats.get("attack_range", 68.0)))
	parameters["preferred_range"] = float(parameters["attack_range"]) * (0.78 if str(result.get("role", "")) in ["ranged", "artillery", "support", "summoner", "healer"] else 1.0)
	parameters["hazard_cap"] = int(parameters.get("max_active_hazards", 0))
	parameters["summon_cap"] = int(parameters.get("summon_cap", 0))
	if enemy_id == "M08":
		# Its existing shield bash slows briefly; no extra generic tank ability.
		parameters["bash_slow_multiplier"] = 0.82-float(tier-1)*0.02
		parameters["bash_slow_seconds"] = 0.65+float(tier-1)*0.10
	if enemy_id == "M11":
		# Teach one visible acid landing before introducing the authored triangle
		# and zigzag combinations. The two-active-pool budget remains unchanged.
		parameters["lob_count"] = mini(3,tier)
	result["archetype"] = archetype
	result["clan"] = {"B01":"construct", "B02":"insect", "B03":"zombie", "B04":"orc"}.get(str(result.get("biome_id", "")), "")
	result["visual_palette"] = Palette.family_for(enemy_id, result)
	result["damage_type"] = str(result.get("damage_type","physical"))
	result["enemy_level"] = level
	result["mechanic_tier"] = tier
	result["rank"] = resolved_rank
	result["max_hp"] = float(stats.get("max_hp", 60.0)) * float(identity.hp) * hp_scale
	result["damage"] = minf(MAX_BASE_DAMAGE,maxf(float(identity.minimum_damage),float(stats.get("damage", 14.0))*float(identity.damage))) * damage_scale
	result["move_speed"] = minf(MAX_MOVE_SPEED, float(stats.get("move_speed", 96.0)) * float(identity.speed) * (1.0 + float(level - 1) * float(rules.get("speed_per_level", 0.006))))
	result["armor"] = minf(24.0, float(stats.get("armor", 0.0))*float(identity.armor)+float(identity.armor_bonus)+float(tier-1)*float(identity.armor_per_tier))
	result["magic_resist"] = minf(32.0,float(result.get("magic_resist",0.0))+float(tier-1)*float(identity.resist_per_tier)+(4.0 if resolved_rank=="elite" else 0.0))
	result["attack_range"] = float(parameters["attack_range"])
	result["recovery_seconds"] = recovery
	result["attack_cooldown_seconds"] = recovery # The actual brain recovery between attacks.
	result["attack_parameters"] = parameters
	result["mechanics"] = mechanics
	result["tier_descriptions"] = descriptions
	result["progression_implemented"] = true
	result["progression_scope"] = "authored_parameters_only"
	result["scene_dependency_ids"] = authored.get("scene_dependency_ids", []).duplicate(true)
	# Base catalog threat stays unchanged. Elite rounding happens BEFORE tier cost.
	var base_cost: int = int(result.get("threat_cost", 1))
	if resolved_rank == "elite":
		base_cost = int(ceil(float(base_cost) * 1.5))
	result["effective_threat_cost"] = int(ceil(float(base_cost) * (1.0 + float(tier - 1) * 0.25)))
	return result

static func _enforce_safety(enemy_id: String, base: Dictionary, parameters: Dictionary) -> void:
	parameters["tell_seconds"] = maxf(float(base.get("minimum_tell_seconds", 0.55)), float(parameters.get("tell_seconds", 0.65)))
	parameters["locked_line_delay_seconds"] = maxf(0.4, maxf(float(base.get("locked_line_delay_seconds", 0.0)), float(parameters.get("locked_line_delay_seconds", 0.4))))
	parameters["area_tell_seconds"] = maxf(0.8, float(parameters.get("area_tell_seconds", 0.8)))
	parameters["combo_gap_seconds"] = maxf(0.55, float(parameters.get("combo_gap_seconds", 0.55)))
	parameters["exposure_seconds"] = maxf(0.45, float(parameters.get("exposure_seconds", 0.9)))
	parameters["recovery_seconds"] = maxf(float(parameters["exposure_seconds"]), maxf(0.45, float(parameters.get("recovery_seconds", 0.9))))
	parameters["combo_count"] = clampi(int(parameters.get("combo_count", 1)), 1, 3)
	parameters["projectile_count"] = clampi(int(parameters.get("projectile_count", 1)), 1, 3)
	parameters["support_targets"] = clampi(int(parameters.get("support_targets", 0)), 0, 3)
	parameters["support_charges"] = clampi(int(parameters.get("support_charges", 0)), 0, 2)
	parameters["max_active_hazards"] = clampi(int(parameters.get("max_active_hazards", 0)), 0, 2)
	parameters["spawn_grace_seconds"] = maxf(0.8, float(parameters.get("spawn_grace_seconds", 0.8)))
	parameters["track_after_lock"] = false
	parameters["spawn_can_damage"] = false
	if enemy_id == "M12":
		parameters["summon_cap"] = mini(2, int(parameters.get("summon_cap", 2)))
		parameters["summon_count"] = clampi(int(parameters.get("summon_count", 1)), 1, 2)
		parameters["summon_rewards"] = false
		parameters["reserve_summon_budget"] = true
	if enemy_id in ["M17", "M30"]:
		parameters["exclude_support_recipients"] = true
	if enemy_id == "M17":
		parameters["heal_limit_per_target"] = 2
	if enemy_id == "M31":
		parameters["refraction_count"] = 1
	if enemy_id == "M33":
		parameters["line_count"] = clampi(int(parameters.get("line_count", 1)), 1, 2)
	if enemy_id == "M36":
		parameters["detonate_count"] = 1
		parameters["death_explosion"] = false

static func encounter_level(room_id: String, zone_index: int, difficulty: int = 0) -> int:
	var definition: Dictionary = Catalog.room(room_id)
	if definition.is_empty() or zone_index < 0 or zone_index >= ZONE_COUNT:
		return 0
	var biome_index: int = int(str(definition.get("biome_id", "B01")).trim_prefix("B"))
	return clampi(1 + (biome_index - 1) * 4 + zone_index * 2 + clampi(difficulty, 0, MAX_DIFFICULTY) * 2, MIN_LEVEL, MAX_LEVEL)

static func encounter_budget(room_id: String, zone_index: int, difficulty: int = 0) -> int:
	var definition: Dictionary = Catalog.room(room_id)
	if definition.is_empty() or zone_index < 0 or zone_index >= ZONE_COUNT:
		return 0
	var biome_index: int = int(str(definition.get("biome_id", "B01")).trim_prefix("B"))
	return mini(26, 10 + (biome_index - 1) * 4 + zone_index * 2 + clampi(difficulty, 0, MAX_DIFFICULTY) * 2)

static func encounter(room_id: String, zone_index: int, difficulty: int = 0) -> Array[Dictionary]:
	# Compatibility means the first batch, never every future batch at once.
	var result: Array[Dictionary] = []
	var plan: Dictionary = encounter_plan(room_id, zone_index, difficulty)
	if not plan.is_empty():
		result.assign(plan["waves"][0])
	return result

static func encounter_waves(room_id: String, zone_index: int, difficulty: int = 0) -> Array:
	return encounter_plan(room_id, zone_index, difficulty).get("waves", []).duplicate(true)

static func _encounter_member(id: String, level: int, rank: String, zone: int, difficulty: int, budget: int, wave_index: int) -> Dictionary:
	var profile: Dictionary = resolve(id, level, rank)
	if profile.is_empty():
		return {}
	var reserve_count: int = int(profile["attack_parameters"].get("summon_cap", 0))
	var reserve_threat: int = 0
	if reserve_count > 0:
		reserve_threat = int(resolve(str(profile["attack_parameters"].get("summon_enemy_id", "M14")), level).get("effective_threat_cost", 0)) * reserve_count
	profile["zone_index"] = zone
	profile["wave_index"] = wave_index
	profile["encounter_budget"] = budget
	profile["encounter_budget_cost"] = int(profile["effective_threat_cost"]) + reserve_threat
	profile["encounter_slot_cost"] = 1 + reserve_count
	profile["reserved_summon_count"] = reserve_count
	profile["reserved_summon_threat"] = reserve_threat
	profile["encounter_protective_support"] = id in PROTECTIVE_IDS
	profile["encounter_functional_support"] = id in FUNCTIONAL_SUPPORT_IDS
	profile["difficulty"] = difficulty
	return profile

static func encounter_plan(room_id: String, zone_index: int, difficulty: int = 0) -> Dictionary:
	var definition: Dictionary = Catalog.room(room_id)
	if definition.is_empty() or zone_index < 0 or zone_index >= ZONE_COUNT:
		return {}
	var zones: Array = definition.get("geometry", {}).get("encounter_zones", [])
	if zones.size() != ZONE_COUNT:
		return {}
	var normalized_difficulty: int = clampi(difficulty, 0, MAX_DIFFICULTY)
	var biome_id: String = str(definition.get("biome_id", ""))
	if not REINFORCEMENT_POOLS.has(biome_id):
		return {}
	var biome: int = int(biome_id.trim_prefix("B"))
	var level: int = encounter_level(room_id, zone_index, normalized_difficulty)
	var budget: int = encounter_budget(room_id, zone_index, normalized_difficulty)
	var cap: int = mini(ZONE_CAP, int(zones[zone_index].get("concurrent_cap", ZONE_CAP)))
	if cap < 1:
		return {}
	var target_total: int = int(BASE_ZONE_TOTALS[zone_index]) + biome - 1 + normalized_difficulty
	var initial_slots: int = mini(cap, 6 if normalized_difficulty >= 2 or biome >= 3 else 5)
	var pool: Array = REINFORCEMENT_POOLS[biome_id]
	var specials: Array[String] = []
	for member: Dictionary in definition.get("reference_wave", []):
		var id: String = str(member.get("enemy_id", ""))
		if not pool.has(id) and not specials.has(id) and Catalog.enemy(id).get("biome_id", "") == biome_id:
			specials.append(id)
	var waves: Array = []
	var used_specials: Array[String] = []
	var used_ids: Dictionary = {}
	var protected_used: bool = false
	var functional_used: bool = false
	var elite_used: bool = false
	var total_count: int = 0
	var total_threat: int = 0
	var summon_reservations: int = 0
	var special_cursor: int = zone_index
	var filler_cursor: int = zone_index
	# Every successful iteration adds natural actors. The finite target replaces
	# the old policy of splitting a single 5-8 actor reference wave over a huge room.
	for wave_index: int in range(target_total):
		if total_count >= target_total:
			break
		var batch: Array[Dictionary] = []
		var slots: int = 0
		var spent: int = 0
		var slot_limit: int = initial_slots if wave_index == 0 else cap
		var requested: int = mini(target_total - total_count, initial_slots if wave_index == 0 else 3)
		# One authored special per batch, and each special at most once per zone.
		# Protection and scan/bell support limits apply across ALL its batches.
		for offset: int in range(specials.size()):
			var id: String = specials[(special_cursor + offset) % specials.size()]
			if used_specials.has(id) or (id in PROTECTIVE_IDS and protected_used) or (id in FUNCTIONAL_SUPPORT_IDS and functional_used):
				continue
			var profile: Dictionary = _encounter_member(id, level, "normal", zone_index, normalized_difficulty, budget, wave_index)
			if int(profile["encounter_slot_cost"]) > slot_limit or int(profile["encounter_budget_cost"]) > budget:
				continue
			# Only zones 1 and 2 may allocate one elite each, independent of call order.
			# Their small reinforcement batch keeps the initial screen readable.
			if wave_index > 0 and not elite_used and zone_index > 0 and normalized_difficulty >= 2 and definition.get("role_tags", []).has("elite_objective") and id not in ["M12", "M36"]:
				var elite: Dictionary = _encounter_member(id, level, "elite", zone_index, normalized_difficulty, budget, wave_index)
				if int(elite["encounter_budget_cost"]) <= budget:
					profile = elite
					elite_used = true
			batch.append(profile)
			slots += int(profile["encounter_slot_cost"])
			spent += int(profile["encounter_budget_cost"])
			used_specials.append(id)
			used_ids[id] = int(used_ids.get(id, 0)) + 1
			protected_used = protected_used or id in PROTECTIVE_IDS
			functional_used = functional_used or id in FUNCTIONAL_SUPPORT_IDS
			special_cursor += offset + 1
			break
		while batch.size() < requested and slots < slot_limit:
			var filler: Dictionary = {}
			for offset: int in range(pool.size()):
				var id: String = str(pool[(filler_cursor + offset) % pool.size()])
				if id in FUNCTIONAL_SUPPORT_IDS and functional_used:
					continue
				var candidate: Dictionary = _encounter_member(id, level, "normal", zone_index, normalized_difficulty, budget, wave_index)
				if spent + int(candidate["encounter_budget_cost"]) > budget:
					continue
				filler = candidate
				filler_cursor += offset + 1
				break
			if filler.is_empty():
				break
			batch.append(filler)
			slots += int(filler["encounter_slot_cost"])
			spent += int(filler["encounter_budget_cost"])
			var filler_id: String = str(filler["enemy_id"])
			used_ids[filler_id] = int(used_ids.get(filler_id, 0)) + 1
			functional_used = functional_used or filler_id in FUNCTIONAL_SUPPORT_IDS
		if batch.is_empty():
			return {}
		waves.append(batch)
		total_count += batch.size()
		total_threat += spent
		for member: Dictionary in batch:
			summon_reservations += int(member["reserved_summon_count"])
	return {
		"room_id": room_id, "zone_index": zone_index, "biome_id": biome_id,
		"enemy_level": level, "difficulty": normalized_difficulty,
		"waves": waves, "wave_count": waves.size(), "initial_count": waves[0].size(),
		"total_count": total_count, "target_count": target_total, "total_threat": total_threat,
		"reserved_summon_count": summon_reservations, "composition": used_ids,
		"concurrent_cap": cap, "room_cap": ROOM_CAP, "concurrent_threat_budget": budget,
		"reinforce_alive_threshold": 2, "reinforce_threat_fraction": 0.3,
		"reinforce_delay_seconds": 3.0, "spawn_grace_seconds": 0.8,
		"minimum_player_spawn_distance": 360.0,
		"completion_requires_all_waves": true, "hero_level_scaling": false
	}
