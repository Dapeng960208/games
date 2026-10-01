class_name EnemyDifficulty
extends RefCounted
## Difficulty is independent of the finite level/tier ladder. The saved base
## makes repeated application safe for encounter plans, summons and restores.

const MAX_DIFFICULTY := 4
const SCALED_STATS := ["max_hp", "damage", "move_speed", "armor", "magic_resist", "recovery_seconds"]

static func apply(source: Dictionary, difficulty: int = 0) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	if source.is_empty() or str(source.get("enemy_id", "")).is_empty() or str(source.get("rank", "normal")) == "boss":
		return result
	var tier: int = clampi(difficulty, 0, MAX_DIFFICULTY)
	var base: Dictionary = source.get("difficulty_base_stats", {}).duplicate(true)
	if base.is_empty():
		for key: String in SCALED_STATS:
			base[key] = float(source.get(key, 0.0))
	result["difficulty_base_stats"] = base
	result["difficulty"] = tier
	result["max_hp"] = float(base.max_hp) * (1.0 + 0.12 * tier)
	result["damage"] = float(base.damage) * (1.0 + 0.10 * tier)
	result["move_speed"] = float(base.move_speed) * (1.0 + 0.04 * tier)
	result["armor"] = float(base.armor) + 2.0 * tier
	result["magic_resist"] = float(base.magic_resist) + 2.0 * tier
	var parameters: Dictionary = result.get("attack_parameters", {})
	var exposure: float = maxf(0.45, float(parameters.get("exposure_seconds", 0.45)))
	var recovery: float = maxf(exposure, float(base.recovery_seconds) / (1.0 + 0.035 * tier))
	result["recovery_seconds"] = recovery
	result["attack_cooldown_seconds"] = recovery
	parameters["recovery_seconds"] = recovery
	parameters["recovery"] = recovery
	result["attack_parameters"] = parameters
	return result
