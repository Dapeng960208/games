extends RefCounted
## Candidate archive 15 only. Total critical multiplier, not bonus damage.
const DEFAULT_CHANCE := 0.25
const DEFAULT_MULTIPLIER := 2.0
const MAX_CHANCE := 1.0
const MAX_MULTIPLIER := 3.0
static func enabled(stats: Dictionary) -> bool:
	return int(stats.get("crit_policy_version", 0)) == 1 or int(stats.get("enemy_species_version", 0)) == 4
static func chance(stats: Dictionary, bonus: float = 0.0) -> float:
	return clampf(float(stats.get("crit_chance", DEFAULT_CHANCE)) + bonus, 0.0, MAX_CHANCE)
static func multiplier(stats: Dictionary, bonus: float = 0.0) -> float:
	return clampf(float(stats.get("crit_multiplier", DEFAULT_MULTIPLIER)) + bonus, 1.0, MAX_MULTIPLIER)
static func roll(seed_value: int, event_id: String, probability: float) -> bool:
	# Event-keyed RNG: no global random state, order dependence or JSON int64 loss.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + ":crit-v1:" + event_id) & 0x7fffffff
	return rng.randf() < clampf(probability, 0.0, MAX_CHANCE)
static func apply_player(stats: Dictionary, calibration: Dictionary) -> Dictionary:
	if int(calibration.get("version", 0)) != 15 or int(stats.get("ruleset_version", 1)) != 2: return stats
	var result := stats.duplicate(true)
	var gear: Dictionary = result.get("uncapped_equipment_contribution", result.get("equipment_contribution", {}))
	result["crit_policy_version"] = 1
	result["crit_chance"] = chance({}, float(gear.get("crit_chance", 0.0)) + float(result.get("hero_base", {}).get("talent_crit_chance", 0.0)))
	result["crit_multiplier"] = multiplier({}, float(gear.get("crit_multiplier", 0.0)))
	return result
static func freeze(command: Dictionary, stats: Dictionary, seed_value: int, event_id: String) -> Dictionary:
	var result := command.duplicate(true)
	if not enabled(stats): return result
	result["crit_policy_version"] = 1
	result["attacker_stats"] = {"crit_policy_version":1,"crit_chance":chance(stats),"crit_multiplier":multiplier(stats),"armor_penetration":float(stats.get("armor_penetration",0)),"magic_penetration":float(stats.get("magic_penetration",0))}
	result["crit_event_id"] = str(result.get("crit_event_id", event_id))
	if not result.has("critical"):
		result["critical"] = roll(seed_value, result.crit_event_id, chance(stats))
	result["already_critical"] = false
	return result
