class_name StatResolver
extends RefCounted
## Resolves permanent growth and owned equipment only. Conditional affixes and
## set procs are evaluated by combat events, never as unconditional stats here.

const Numerical = preload("res://config/numerical_rules.gd")
const FLAT_KEYS := ["attack", "ability_power", "max_hp", "armor", "magic_resist", "max_mana", "armor_penetration", "magic_penetration", "true_damage_bonus", "resource_max", "resource_regen", "starting_resource"]
const Registry = preload("res://scripts/data/content_registry.gd")
const EQUIPMENT_CAPS: Dictionary = {"attack": 45.0, "ability_power": 90.0, "max_hp": 220.0, "armor": 70.0, "magic_resist": 70.0, "max_mana": 150.0, "armor_penetration": 40.0, "magic_penetration": 40.0, "crit_multiplier": 1.0, "true_damage_bonus": 12.0, "attack_speed": 0.60, "move_speed": 0.45, "cooldown_reduction": 0.30, "damage_bonus": 0.60, "damage_reduction": 0.35, "burn_damage": 0.60, "corrosion_damage_bonus": 0.60, "status_duration": 0.40}

static func resolve(hero_id: String, level: int, loadout: Dictionary, owned: Dictionary, ruleset: int = Numerical.LEGACY) -> Dictionary:
	var definition: Dictionary = Registry.hero(hero_id)
	if definition.is_empty():
		return {}
	var growth := float(clampi(level, 1, 20) - 1) / 19.0
	var contribution: Dictionary = {}
	var set_counts: Dictionary = {}
	var equipped: Dictionary = {}
	for slot in Registry.SLOTS:
		var id := str(loadout.get(slot, ""))
		var item: Dictionary = Registry.equipment(id)
		if item.is_empty() or item.get("slot") != slot or not owned.has(id):
			continue
		var record: Variant = owned[id]
		if not record is Dictionary:
			continue
		var upgrade := clampi(int(record.get("level", record.get("upgrade_level", 0))), 0, 5)
		var multiplier := 1.0 + 0.1 * upgrade
		var base_stats: Dictionary = item.get("base_stats", {})
		for key in base_stats:
			var amount := float(base_stats[key]) * multiplier
			# Combat consumes fractional power, so small paid enhancements take
			# effect immediately. Preserve historical HP/mana capacity rounding:
			# old full-health/resource checkpoints must still fit the current cap.
			if ruleset == Numerical.V2 and key in FLAT_KEYS:
				amount = Numerical.scale(amount, ruleset)
			elif key in ["max_hp", "max_mana"]:
				amount = roundf(amount)
			contribution[key] = float(contribution.get(key, 0.0)) + amount
		var set_id := str(item.get("set_id", ""))
		if not set_id.is_empty():
			set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1
		equipped[slot] = id
	var raw_contribution := contribution.duplicate(true)
	contribution = clamp_equipment_contributions(contribution, ruleset)
	if ruleset == Numerical.V2:
		definition = definition.duplicate(true)
		for key in FLAT_KEYS:
			if definition.has(key): definition[key] = Numerical.scale(float(definition[key]), ruleset)
	var defense_scale: float = float(Numerical.value("resistance_denominator")) if ruleset == Numerical.V2 else 100.0
	var armor_growth: float = Numerical.scale(6.0, ruleset)
	var armor := maxf(0.0, float(definition.armor) + armor_growth * growth + float(contribution.get("armor", 0.0)))
	var equipment_dr := float(contribution.damage_reduction)
	var armor_dr := armor / (defense_scale + armor)
	var magic_resist := maxf(0.0, float(definition.get("magic_resist", 18.0 if hero_id == "CH03" else 12.0)) + armor_growth * growth + float(contribution.magic_resist))
	var is_mana := str(definition.resource_type) == "mana"
	var resource_max := float(definition.resource_max) + (float(contribution.max_mana) if is_mana else 0.0)
	var stats: Dictionary = {
		"hero_id": hero_id,
		"ruleset_version": ruleset,
		"level": clampi(level, 1, 20),
		"max_hp": float(definition.max_hp) * (1.0 + 0.20 * growth) + float(contribution.max_hp),
		"armor": armor,
		"magic_resist": magic_resist,
		"attack": float(definition.attack) * (1.0 + 0.10 * growth) + float(contribution.attack),
		"ability_power": float(definition.get("ability_power", 28.0 if hero_id == "CH03" else 0.0)) * (1.0 + 0.20 * growth) + float(contribution.ability_power),
		"armor_penetration": float(contribution.armor_penetration),
		"magic_penetration": float(contribution.magic_penetration),
		"true_damage_bonus": float(contribution.true_damage_bonus),
		"attack_interval": float(definition.attack_interval) / (1.0 + float(contribution.attack_speed)),
		"range": float(definition.range),
		"move_speed": float(definition.move_speed) * (1.0 + float(contribution.move_speed)),
		"resource_max": resource_max,
		"max_mana": resource_max if is_mana else 0.0,
		"resource_regen": float(definition.resource_regen),
		"starting_resource": resource_max if is_mana else clampf(float(definition.starting_resource), 0.0, resource_max),
		"resource_type": str(definition.resource_type),
		"resource_name": str(definition.resource_name),
		"crit_chance": clampf(float(definition.get("crit_chance", 0.05)) + float(contribution.get("crit_chance", 0.0)), 0.0, 0.75),
		"crit_multiplier": clampf(float(definition.get("crit_multiplier", 1.5)) + float(contribution.crit_multiplier), 1.0, 2.5),
		"cooldown_reduction": float(contribution.cooldown_reduction),
		"damage_bonus": float(contribution.damage_bonus),
		"damage_reduction": equipment_dr,
		"armor_damage_reduction": armor_dr,
		"magic_damage_reduction": magic_resist / (defense_scale + magic_resist),
		"equipment_damage_reduction": equipment_dr,
		"burn_damage": float(contribution.burn_damage),
		"corrosion_damage_bonus": float(contribution.corrosion_damage_bonus),
		"status_duration": float(contribution.status_duration),
		"attack_speed_bonus": float(contribution.attack_speed),
		"move_speed_bonus": float(contribution.move_speed),
		"sets": set_counts,
		"loadout": equipped,
		"equipment_contribution": contribution,
		"uncapped_equipment_contribution": raw_contribution,
	}
	if ruleset == Numerical.V2:
		for key in FLAT_KEYS:
			if stats.has(key): stats[key] = Numerical.integer(float(stats[key]))
		for key in FLAT_KEYS:
			if contribution.has(key): contribution[key] = Numerical.integer(float(contribution[key]))
	return stats

## Shared caps are independent of current catalog values, so future temporary
## equipment modifiers cannot silently bypass them. Conditional damage must
## still join the direct-damage bucket only when its condition is satisfied.
static func clamp_equipment_contributions(amounts: Dictionary, ruleset: int = Numerical.LEGACY) -> Dictionary:
	var result := amounts.duplicate(true)
	for key in EQUIPMENT_CAPS:
		result[key] = Numerical.integer(float(amounts.get(key, 0.0))) if ruleset == Numerical.V2 and key in FLAT_KEYS else clampf(float(amounts.get(key, 0.0)), 0.0, float(EQUIPMENT_CAPS[key]))
	result["crit_chance"] = clampf(float(amounts.get("crit_chance", 0.0)), 0.0, 0.75)
	return result

static func combined_damage_reduction(armor: float, equipment_reduction: float, ruleset: int = Numerical.LEGACY) -> float:
	var effective_armor := maxf(0.0, armor)
	var denominator: float = float(Numerical.value("resistance_denominator")) if ruleset == Numerical.V2 else 100.0
	var armor_reduction := effective_armor / (denominator + effective_armor)
	# Compatibility/display helper for physical damage only. Actual damage uses
	# DamageResolver and separates armor, magic resistance and universal reduction.
	return 1.0 - (1.0 - armor_reduction) * (1.0 - clampf(equipment_reduction, 0.0, 0.65))
