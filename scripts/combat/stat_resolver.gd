class_name StatResolver
extends RefCounted
## Resolves permanent growth and owned equipment only. Conditional affixes and
## set procs are evaluated by combat events, never as unconditional stats here.

const Registry = preload("res://scripts/data/content_registry.gd")
const EQUIPMENT_CAPS: Dictionary = {"attack": 18.0, "max_hp": 150.0, "attack_speed": 0.60, "move_speed": 0.45, "cooldown_reduction": 0.30, "damage_bonus": 0.60, "damage_reduction": 0.35, "burn_damage": 0.60, "corrosion_damage_bonus": 0.60, "status_duration": 0.40}

static func resolve(hero_id: String, level: int, loadout: Dictionary, owned: Dictionary) -> Dictionary:
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
			# Flat equipment stats round once per upgraded item; ratios retain precision.
			if key in ["attack", "max_hp", "armor"]:
				amount = roundf(amount)
			contribution[key] = float(contribution.get(key, 0.0)) + amount
		var set_id := str(item.get("set_id", ""))
		if not set_id.is_empty():
			set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1
		equipped[slot] = id
	var raw_contribution := contribution.duplicate(true)
	contribution = clamp_equipment_contributions(contribution)
	var armor := maxf(0.0, float(definition.armor) + 6.0 * growth + float(contribution.get("armor", 0.0)))
	var equipment_dr := float(contribution.damage_reduction)
	var armor_dr := armor / (100.0 + armor)
	var stats: Dictionary = {
		"hero_id": hero_id,
		"level": clampi(level, 1, 20),
		"max_hp": float(definition.max_hp) * (1.0 + 0.20 * growth) + float(contribution.max_hp),
		"armor": armor,
		"attack": float(definition.attack) * (1.0 + 0.10 * growth) + float(contribution.attack),
		"attack_interval": float(definition.attack_interval) / (1.0 + float(contribution.attack_speed)),
		"range": float(definition.range),
		"move_speed": float(definition.move_speed) * (1.0 + float(contribution.move_speed)),
		"resource_max": float(definition.resource_max),
		"resource_regen": float(definition.resource_regen),
		"starting_resource": clampf(float(definition.starting_resource), 0.0, float(definition.resource_max)),
		"resource_type": str(definition.resource_type),
		"resource_name": str(definition.resource_name),
		"crit_chance": clampf(float(definition.get("crit_chance", 0.05)) + float(contribution.get("crit_chance", 0.0)), 0.0, 0.45),
		"crit_multiplier": float(definition.get("crit_multiplier", 1.5)),
		"cooldown_reduction": float(contribution.cooldown_reduction),
		"damage_bonus": float(contribution.damage_bonus),
		"damage_reduction": combined_damage_reduction(armor, equipment_dr),
		"armor_damage_reduction": armor_dr,
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
	return stats

## Shared caps are independent of current catalog values, so future temporary
## equipment modifiers cannot silently bypass them. Conditional damage must
## still join the direct-damage bucket only when its condition is satisfied.
static func clamp_equipment_contributions(amounts: Dictionary) -> Dictionary:
	var result := amounts.duplicate(true)
	for key in EQUIPMENT_CAPS:
		result[key] = clampf(float(amounts.get(key, 0.0)), 0.0, float(EQUIPMENT_CAPS[key]))
	result["crit_chance"] = clampf(float(amounts.get("crit_chance", 0.0)), 0.0, 0.45)
	return result

static func combined_damage_reduction(armor: float, equipment_reduction: float) -> float:
	var effective_armor := maxf(0.0, armor)
	var armor_reduction := effective_armor / (100.0 + effective_armor)
	return minf(0.55, 1.0 - (1.0 - armor_reduction) * (1.0 - clampf(equipment_reduction, 0.0, 0.35)))
