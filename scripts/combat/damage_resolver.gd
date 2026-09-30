class_name DamageResolver
extends RefCounted
## Pure damage arithmetic shared by player and enemies. The caller owns shields,
## health, crit RNG and trigger dispatch; this function never mutates its inputs.
const MAX_REDUCTION := 0.65

static func normalized_type(value: String) -> String:
	if value in ["magic", "spell", "arcane", "burn", "shock"]:
		return "magic"
	if value in ["true", "true_damage"]:
		return "true"
	return "physical"

static func resolve(amount: float, damage_type: String = "physical", attacker_stats: Dictionary = {}, defender_stats: Dictionary = {}, context: Dictionary = {}) -> Dictionary:
	var type := normalized_type(str(context.get("damage_type", damage_type)))
	var damage := maxf(0.0, amount) if is_finite(amount) else 0.0
	var immune := bool(defender_stats.get("invulnerable", false)) or bool(context.get("invulnerable", false))
	var resistance := 0.0
	var reduction := 0.0
	var critical := bool(context.get("critical", false))
	# Existing room strikes already contain their critical multiplier. New users
	# can explicitly pass already_critical=false to resolve an unmultiplied packet.
	if critical and not bool(context.get("already_critical", true)) and type != "true":
		damage *= clampf(float(attacker_stats.get("crit_multiplier", 1.5)), 1.0, 2.5)
	if type != "true":
		var resistance_key := "armor" if type == "physical" else "magic_resist"
		var penetration_key := "armor_penetration" if type == "physical" else "magic_penetration"
		var penetration := maxf(0.0, float(context.get(penetration_key, attacker_stats.get(penetration_key, 0.0))))
		var base_resistance: float = float(defender_stats.get(resistance_key, 0.0))
		if type == "physical": base_resistance *= clampf(float(context.get("armor_multiplier",1.0)),0.0,1.0)
		resistance = maxf(0.0, base_resistance - penetration)
		reduction = clampf(float(defender_stats.get("damage_reduction", 0.0)), 0.0, MAX_REDUCTION)
		damage *= 100.0 / (100.0 + resistance) * (1.0 - reduction)
	if immune:
		damage = 0.0
	return {"damage":damage,"damage_type":type,"resistance":resistance,"reduction":reduction,"immune":immune,"critical":critical}

static func healing(amount: float, grievous: bool = false) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	return amount * (0.6 if grievous else 1.0)
