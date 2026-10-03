class_name StatResolver
extends RefCounted
## Resolves permanent growth and owned equipment only. Conditional template
## traits and set procs are evaluated by combat events, never as flat stats here.

const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
const Numerical = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const FLAT_KEYS := ["attack", "ability_power", "max_hp", "armor", "magic_resist", "max_mana", "armor_penetration", "magic_penetration", "true_damage_bonus", "resource_max", "resource_regen", "starting_resource"]
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const EQUIPMENT_CAPS: Dictionary = {"attack": 45.0, "ability_power": 90.0, "max_hp": 220.0, "armor": 70.0, "magic_resist": 70.0, "max_mana": 150.0, "armor_penetration": 40.0, "magic_penetration": 40.0, "crit_multiplier": 1.0, "true_damage_bonus": 12.0, "attack_speed": 0.60, "move_speed": 0.45, "cooldown_reduction": 0.30, "damage_bonus": 0.60, "damage_reduction": 0.35, "burn_damage": 0.60, "corrosion_damage_bonus": 0.60, "status_duration": 0.40}

static func resolve(hero_id: String, level: int, loadout: Dictionary, owned: Dictionary, ruleset: int = Numerical.LEGACY, talents: Dictionary = {}, legacy_eligibility: bool = false, legacy_role_growth: bool = false) -> Dictionary:
	var definition: Dictionary = Registry.hero(hero_id)
	if definition.is_empty():
		return {}
	var growth := float(clampi(level, 1, 20) - 1) / 19.0
	var contribution: Dictionary = {}
	var set_counts: Dictionary = {}
	var equipped: Dictionary = {}
	var templates: Dictionary = {}
	if ruleset == Numerical.V2:
		var resolved := _instance_equipment(hero_id, level, loadout, owned, legacy_eligibility)
		if resolved.is_empty(): return {}
		contribution = resolved.contribution
		set_counts = resolved.set_counts
		equipped = resolved.loadout
		templates = resolved.templates
	else:
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
				if key in ["max_hp", "max_mana"]:
					amount = roundf(amount)
				contribution[key] = float(contribution.get(key, 0.0)) + amount
			var set_id := str(item.get("set_id", ""))
			if not set_id.is_empty():
				set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1
			equipped[slot] = id
	# The S06 health tier is one contribution to the shared life-ratio bucket,
	# regardless of whether four, six or eight pieces are worn.
	if ruleset == Numerical.V2 and int(set_counts.get("S06", 0)) >= 2:
		contribution["hp_ratio"] = float(contribution.get("hp_ratio", 0.0)) + 0.10
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
		var base := Progression.hero_base(Registry.hero(hero_id), level, talents, 0, legacy_role_growth)
		if base.is_empty(): return {}
		for key in ["attack", "ability_power", "max_hp", "armor", "magic_resist"]:
			stats[key] = int(base[key]) + int(contribution.get(key, 0))
		stats.level = int(base.level)
		stats["talents"] = talents.duplicate(true)
		stats["talent_points_available"] = int(base.talent_points_available)
		stats["hero_base"] = base
		stats.resource_max = int(base.resource_max) + (int(contribution.max_mana) if is_mana else 0)
		stats.max_mana = stats.resource_max if is_mana else 0
		stats.resource_regen = int(base.resource_regen)
		stats.starting_resource = stats.resource_max if is_mana else mini(int(base.starting_resource), int(stats.resource_max))
		stats["resource_regen_delay"] = float(base.resource_regen_delay)
		stats["equipment_templates"] = templates.duplicate(true)
		stats["hp_ratio"] = float(contribution.get("hp_ratio", 0.0))
		stats.max_hp = Numerical.integer(float(stats.max_hp) * (1.0 + float(stats.hp_ratio)))
		stats["resource_gain_bonus"] = float(contribution.get("resource_gain_bonus", 0.0))
		var caps: Dictionary = Numerical.value("caps")
		stats.crit_chance = minf(float(caps.crit_chance), float(stats.crit_chance) + float(base.talent_crit_chance))
		stats.attack_speed_bonus = minf(float(caps.attack_speed), float(contribution.attack_speed) + float(base.talent_attack_speed))
		stats.attack_interval = float(definition.attack_interval) / (1.0 + float(stats.attack_speed_bonus))
		stats.cooldown_reduction = minf(float(caps.cooldown_reduction), float(contribution.cooldown_reduction) + float(base.talent_cooldown_reduction))
		stats.armor_damage_reduction = float(stats.armor) / (defense_scale + float(stats.armor))
		stats.magic_damage_reduction = float(stats.magic_resist) / (defense_scale + float(stats.magic_resist))
		for key in FLAT_KEYS:
			if stats.has(key): stats[key] = Numerical.integer(float(stats[key]))
		for key in FLAT_KEYS:
			if contribution.has(key): contribution[key] = Numerical.integer(float(contribution[key]))
	# Explicit isolated numeric experiment only; never selected on normal launch.
	if hero_id=="CH03" and ruleset==Numerical.V2 and Numerical.b05_candidate_enabled() and "--mage-balance-candidate=1" in OS.get_cmdline_user_args():
		stats["mage_balance_candidate"]=1
		stats["mage_spell_power_multiplier"]=2.5
		stats.resource_regen=Numerical.integer(float(stats.resource_regen)*2.0)
	if hero_id=="CH01" and ruleset==Numerical.V2 and Numerical.b05_candidate_enabled() and "--warrior-balance-candidate=1" in OS.get_cmdline_user_args():
		stats["warrior_balance_candidate"]=1
		stats["warrior_skill_power_multiplier"]=1.20
	return stats

## V2 ownership and slot identity are validated before aggregating anything.
## Saved instance rolls already use the complete formula and authored v2 units;
## never add template base_stats or rescale these values a second time.
static func _instance_equipment(hero_id: String, level: int, loadout: Dictionary, owned: Dictionary, legacy_eligibility: bool = false) -> Dictionary:
	var contribution: Dictionary = {}
	var set_counts: Dictionary = {}
	var equipped: Dictionary = {}
	var templates: Dictionary = {}
	var seen: Dictionary = {}
	var slots: Array = Registry.slots(Numerical.V2)
	for slot: Variant in loadout:
		if not slot is String or slot not in slots or not loadout[slot] is String:
			return {}
	for slot: String in slots:
		var instance_id: String = loadout.get(slot, "")
		if instance_id.is_empty(): continue
		if seen.has(instance_id) or not owned.has(instance_id) or not owned[instance_id] is Dictionary:
			return {}
		var record: Dictionary = owned[instance_id]
		if str(record.get("instance_id", "")) != instance_id or not Instances.validate(record).is_empty():
			return {}
		if not Instances.can_equip(record, hero_id, level, legacy_eligibility): return {}
		var template_id: String = record.template_id
		var item: Dictionary = Registry.equipment(template_id, Numerical.V2)
		if item.is_empty() or str(item.get("slot", "")) != slot: return {}
		var values: Dictionary = Instances.stats(record)
		if values.is_empty(): return {}
		for key: String in values:
			if key in FLAT_KEYS:
				contribution[key] = int(contribution.get(key, 0)) + int(values[key])
			else:
				contribution[key] = float(contribution.get(key, 0.0)) + float(values[key])
		var set_id: String = str(item.get("set_id", ""))
		if not set_id.is_empty(): set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1
		seen[instance_id] = true
		equipped[slot] = instance_id
		templates[slot] = template_id
	return {"contribution":contribution, "set_counts":set_counts, "loadout":equipped, "templates":templates}

## Shared caps are independent of current catalog values, so future temporary
## equipment modifiers cannot silently bypass them. Conditional damage must
## still join the direct-damage bucket only when its condition is satisfied.
static func clamp_equipment_contributions(amounts: Dictionary, ruleset: int = Numerical.LEGACY) -> Dictionary:
	var result := amounts.duplicate(true)
	var limits: Dictionary = Numerical.value("caps") if ruleset == Numerical.V2 else {}
	for key in EQUIPMENT_CAPS:
		var cap_key: String = "equipment_damage_reduction" if key == "damage_reduction" else str(key)
		var limit: float = float(limits.get(cap_key, EQUIPMENT_CAPS[key]))
		# crit_multiplier is an increment; its final base+gear cap is separate.
		if key == "crit_multiplier": limit = 1.0
		result[key] = Numerical.integer(float(amounts.get(key, 0.0))) if ruleset == Numerical.V2 and key in FLAT_KEYS else clampf(float(amounts.get(key, 0.0)), 0.0, limit)
	result["crit_chance"] = clampf(float(amounts.get("crit_chance", 0.0)), 0.0, 0.75)
	if ruleset == Numerical.V2:
		for key in ["hp_ratio", "resource_gain_bonus"]:
			result[key] = clampf(float(amounts.get(key, 0.0)), 0.0, float(limits[key]))
	return result

static func combined_damage_reduction(armor: float, equipment_reduction: float, ruleset: int = Numerical.LEGACY) -> float:
	var effective_armor := maxf(0.0, armor)
	var denominator: float = float(Numerical.value("resistance_denominator")) if ruleset == Numerical.V2 else 100.0
	var armor_reduction := effective_armor / (denominator + effective_armor)
	# Compatibility/display helper for physical damage only. Actual damage uses
	# DamageResolver and separates armor, magic resistance and universal reduction.
	return 1.0 - (1.0 - armor_reduction) * (1.0 - clampf(equipment_reduction, 0.0, 0.65))
