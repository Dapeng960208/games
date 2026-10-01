class_name DamageResolver
extends RefCounted
## Pure damage arithmetic shared by player and enemies. The caller owns shields,
## health, crit RNG and trigger dispatch; this function never mutates its inputs.
const MAX_REDUCTION := 0.65
const Rules = preload("res://config/numerical_rules.gd")

static func normalized_type(value: String) -> String:
	if value in ["magic", "spell", "arcane", "burn", "shock"]:
		return "magic"
	if value in ["true", "true_damage"]:
		return "true"
	return "physical"

static func resolve(amount: float, damage_type: String = "physical", attacker_stats: Dictionary = {}, defender_stats: Dictionary = {}, context: Dictionary = {}) -> Dictionary:
	# Only an explicit attack context or the receiving actor selects new units.
	# An attacker with new stats cannot silently upgrade a legacy defender.
	var ruleset: int = int(context.get("ruleset_version", defender_stats.get("ruleset_version", Rules.LEGACY)))
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
		damage = float(Rules.amount(damage, ruleset))
	if type != "true":
		var resistance_key := "armor" if type == "physical" else "magic_resist"
		var penetration_key := "armor_penetration" if type == "physical" else "magic_penetration"
		var penetration := maxf(0.0, float(context.get(penetration_key, attacker_stats.get(penetration_key, 0.0))))
		var base_resistance: float = float(defender_stats.get(resistance_key, 0.0))
		if type == "physical": base_resistance *= clampf(float(context.get("armor_multiplier",1.0)),0.0,1.0)
		resistance = maxf(0.0, base_resistance - penetration)
		reduction = clampf(float(defender_stats.get("damage_reduction", 0.0)), 0.0, MAX_REDUCTION)
		var denominator: float = float(Rules.value("resistance_denominator")) if ruleset == Rules.V2 else 100.0
		damage *= denominator / (denominator + resistance) * (1.0 - reduction)
	if ruleset == Rules.V2:
		# Ordinary enemy weakpoints run after defense. Keep that multiplier before
		# the integer boundary so the caller never rounds an intermediate packet.
		damage *= maxf(0.0, float(context.get("post_defense_multiplier", 1.0)))
	if immune:
		damage = 0.0
	return {"damage":Rules.amount(damage, ruleset),"damage_type":type,"resistance":resistance,"reduction":reduction,"immune":immune,"critical":critical}

static func healing(amount: float, grievous: bool = false, ruleset: int = Rules.LEGACY) -> Variant:
	if not is_finite(amount) or amount <= 0.0:
		return Rules.amount(0.0, ruleset)
	return Rules.amount(amount * (0.6 if grievous else 1.0), ruleset)
