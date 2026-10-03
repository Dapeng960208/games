extends RefCounted
## Damage school selects defense only. This policy selects the offensive stat.
const Crit = preload("res://scripts/domain/combat/crit_policy.gd")
static func source(command: Dictionary, profile: Dictionary) -> String:
	if command.has("power_source"): return str(command.power_source)
	var basic := str(command.get("ability_id", "")).ends_with(":basic") or bool(command.get("original_basic", false))
	return "ability_power" if Crit.enabled(profile) and str(profile.get("primary_role", "")) == "caster" and not basic else "attack"
static func base_share(command: Dictionary, profile: Dictionary) -> float:
	if source(command, profile) != "ability_power" or bool(command.get("derived", false)) or int(command.get("stage", 0)) > 0: return 0.0
	var count := maxi(1, int(command.get("count", 1)))
	count *= maxi(1, command.get("targets", [0]).size())
	count *= maxi(1, int(command.get("max_target_hits", 1)))
	if float(command.get("duration", 0.0)) > 0.0 and str(command.get("kind", "")) in ["ground_area", "hazard", "beam"]:
		count *= maxi(1, int(ceil(float(command.duration) / maxf(0.35, float(command.get("tick_interval", 0.65))))) + 1)
	return clampf(float(command.get("spell_base_share", 1.0 / float(count))), 0.0, 1.0 / float(count))
static func amount(command: Dictionary, profile: Dictionary, coefficient: float) -> float:
	if source(command, profile) == "ability_power":
		return float(profile.get("ability_power", 0)) * coefficient + float(profile.get("skill_base_power", 0)) * base_share(command, profile) if coefficient > 0.0 else 0.0
	return float(profile.get("damage", profile.get("attack", 0))) * coefficient
static func stamp(command: Dictionary, profile: Dictionary) -> void:
	if not Crit.enabled(profile): return
	command["power_source"] = source(command, profile)
	command["spell_base_share"] = base_share(command, profile)
