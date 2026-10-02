class_name BossProfiles
extends RefCounted
## Runtime combat values layered over the authored BO01-BO04 catalog entries.
## Bosses deliberately do not enter EnemyProfiles: they have their own scene,
## brain, completion contract and finite arena reinforcement plan.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const NumericalV2 = preload("res://scripts/combat/enemy_numerical_v2.gd")
const Palette = preload("res://scripts/combat/enemy_palette.gd")

const NAMES_EN := {
	"BO01": "Daybreak Clockwork Colossus",
	"BO02": "Amber Brood Queen",
	"BO03": "Stitched Mayor",
	"BO04": "Cragbreaker Chieftain",
}

const STATS := {
	"BO01": {"max_hp": 1450.0, "damage": 20.0, "armor": 18.0, "move_speed": 70.0, "attack_range": 680.0, "navigation_radius": 54.0},
	"BO02": {"max_hp": 1620.0, "damage": 18.0, "armor": 12.0, "move_speed": 64.0, "attack_range": 760.0, "navigation_radius": 60.0},
	"BO03": {"max_hp": 1480.0, "damage": 19.0, "armor": 10.0, "move_speed": 92.0, "attack_range": 900.0, "navigation_radius": 52.0},
	"BO04": {"max_hp": 1880.0, "damage": 21.0, "armor": 22.0, "move_speed": 58.0, "attack_range": 820.0, "navigation_radius": 62.0},
}

const LEVELS := {"BO01": 5, "BO02": 10, "BO03": 15, "BO04": 20}
const MAGIC_RESIST := {"BO01": 18.0, "BO02": 15.0, "BO03": 12.0, "BO04": 18.0}
const TACTICS := {
	"BO01": {"min_range":180.0, "max_range":260.0, "retreat_range":110.0, "orbit_weight":0.32, "chase_multiplier":1.2},
	"BO02": {"min_range":340.0, "max_range":480.0, "retreat_range":250.0, "orbit_weight":0.85, "chase_multiplier":1.05},
	"BO03": {"min_range":300.0, "max_range":420.0, "retreat_range":220.0, "orbit_weight":0.68, "chase_multiplier":1.1},
	"BO04": {"min_range":170.0, "max_range":280.0, "retreat_range":100.0, "orbit_weight":0.24, "chase_multiplier":1.45},
}

static func ids() -> Array[String]:
	var result: Array[String] = ["BO01", "BO02", "BO03", "BO04"]
	if int(preload("res://config/numerical_rules.gd").value("implemented_chapters",4)) >= 5: result.append("BO05")
	return result

static func resolve(boss_id: String, difficulty: int = 0, ruleset: int = 1, calibration: Variant = null) -> Dictionary:
	if boss_id == "BO05":
		return preload("res://scripts/combat/b05_enemy_skills.gd").boss_profile(difficulty) if ruleset == 2 else {}
	if ruleset == 2:
		var source := resolve(boss_id,0)
		if calibration != null: source["enemy_calibration_snapshot"] = calibration
		return NumericalV2.boss_profile(source,clampi(difficulty,0,4))
	if ruleset != 1: return {}
	if boss_id not in STATS:
		return {}
	var authored: Dictionary = Catalog.bosses().get(boss_id, {}).duplicate(true)
	if authored.is_empty():
		return {}
	var tier: int = clampi(difficulty, 0, 4)
	var result: Dictionary = STATS[boss_id].duplicate(true)
	result.merge(authored, true)
	result.merge({
		"enemy_id": boss_id,
		"boss_id": boss_id,
		"name_en": NAMES_EN[boss_id],
		"rank": "boss",
		"actor_kind": "boss",
		"enemy_level": mini(20, int(LEVELS[boss_id]) + tier * 2),
		"difficulty": tier,
		"behavior_id": "boss_" + boss_id.to_lower(),
		"effective_threat_cost": 0.0,
		"encounter_budget": float(authored.get("reinforcement_budget", 0)),
		"reserved_summon_count": 0,
		"reserved_summon_threat": 0.0,
		"visual_asset": "res://assets/bosses/" + boss_id + ".png",
		"visual_palette": Palette.family_for(boss_id),
		"gameplay_implemented": true,
	}, true)
	result.max_hp = float(STATS[boss_id].max_hp) * (1.0 + 0.16 * tier)
	result.damage = float(STATS[boss_id].damage) * (1.0 + 0.08 * tier)
	result.armor = float(STATS[boss_id].armor) + 3.0 * tier
	result["magic_resist"] = float(MAGIC_RESIST[boss_id]) + 3.0 * tier
	result.move_speed = float(STATS[boss_id].move_speed) * (1.0 + 0.045 * tier)
	result["tactics"] = TACTICS[boss_id].duplicate(true)
	result["clan"] = {"BO01":"construct", "BO02":"insect", "BO03":"zombie", "BO04":"orc"}[boss_id]
	result["damage_type"] = "magic" if boss_id in ["BO01", "BO02"] else "physical"
	# Pods reserve two real encounter slots, rather than bypassing the room's
	# ordinary allocation rules. These are finite attempts over the whole fight.
	result["brood_batch_limit"] = 3 if boss_id == "BO02" else 0
	result["grave_recall_limit"] = 2 if boss_id == "BO03" else 0
	if boss_id == "BO02":
		result["reserved_summon_count"] = 2
		result["reserved_summon_threat"] = 2.0
	result["reinforcement_waves"] = _reinforcement_waves(authored)
	return result

static func _reinforcement_waves(authored: Dictionary) -> Array[Dictionary]:
	var waves: Array[Dictionary] = [
		{"phase": 2, "members": [], "count": 0, "threat": 0},
		{"phase": 3, "members": [], "count": 0, "threat": 0},
	]
	for member: Dictionary in authored.get("arena", {}).get("reinforcements", []):
		var total: int = maxi(0, int(member.get("count", 0)))
		var first: int = int(ceil(float(total) * 0.5))
		var amounts: Array[int] = [first, total - first]
		var enemy_id: String = str(member.get("enemy_id", ""))
		var cost: int = int(Catalog.enemy(enemy_id).get("threat_cost", 0))
		for index: int in 2:
			if amounts[index] <= 0:
				continue
			waves[index].members.append({"enemy_id": enemy_id, "count": amounts[index]})
			waves[index].count = int(waves[index].count) + amounts[index]
			waves[index].threat = int(waves[index].threat) + amounts[index] * cost
	return waves

static func validate(profile: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var boss_id: String = str(profile.get("boss_id", ""))
	if (boss_id not in STATS and boss_id != "BO05") or profile.get("enemy_id", "") != boss_id:
		errors.append("Unknown boss identity")
	if profile.get("phase_thresholds", []) != [0.7, 0.35]:
		errors.append("Boss phase thresholds must be 70% and 35%")
	if str(profile.get("rank", "")) != "boss" or not bool(profile.get("immune_forced_movement", false)):
		errors.append("Boss rank/control contract is missing")
	var count: int = 0
	var threat: int = 0
	for wave: Dictionary in profile.get("reinforcement_waves", []):
		for member: Dictionary in wave.get("members", []):
			if str(Catalog.enemy(str(member.get("enemy_id", ""))).get("biome_id", "")) != str(profile.get("biome_id", "")):
				errors.append("Boss reinforcements must belong to its clan")
		count += int(wave.get("count", 0))
		threat += int(wave.get("threat", 0))
	if count > int(profile.get("reinforcement_cap", 0)):
		errors.append("Reinforcement count exceeds boss cap")
	if threat > int(profile.get("reinforcement_budget", 0)):
		errors.append("Reinforcement threat exceeds boss budget")
	return errors
