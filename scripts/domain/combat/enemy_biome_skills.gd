class_name EnemyBiomeSkills
extends RefCounted
## Region traits extend, rather than replace, the 36 authored attack patterns.
## The runtime snapshots damage from the resolved actor, so poison and rage use
## the same level/difficulty growth as the original skill.

const SIGNATURES := {
	"B01": {"id":"capacitor_guard", "name":"蓄能护盾", "name_en":"Capacitor Ward", "guard_ratio":0.08, "guard_seconds":1.5, "cooldown_seconds":4.0},
	"B02": {"id":"venom_wound", "name":"毒蚀伤口", "name_en":"Venom Wound", "status_id":"corrosion", "status_seconds":1.8, "status_power_ratio":0.55},
	"B03": {"id":"grave_drain", "name":"墓火汲取", "name_en":"Grave Drain", "heal_damage_ratio":0.25, "heal_hp_cap":0.06, "cooldown_seconds":3.0},
	"B04": {"id":"blood_rage", "name":"半血狂怒", "name_en":"Blood Rage", "health_threshold":0.5, "damage_multiplier":1.20, "move_multiplier":1.18},
}

static func apply(profile: Dictionary) -> void:
	var signature: Dictionary = SIGNATURES.get(str(profile.get("biome_id", "")), {})
	if signature.is_empty():
		return
	profile["biome_skill"] = signature.duplicate(true)
	profile["biome_skill_name"] = signature.name
	profile["biome_skill_name_en"] = signature.name_en
