extends RefCounted
## Explicit preview registration. This does not unlock Game's chapter catalog,
## grant rewards or claim the 18 species' authored active skills are implemented.
const Content = preload("res://scripts/world/b06_content.gd")
const Numbers = preload("res://scripts/combat/b06_enemy_numbers.gd")
static func route() -> Array:
	var result: Array = []
	for id: String in Content.room_ids():
		result.append({"room_id":id,"biome_id":"B06","b06_candidate":true,"role":"boss" if id == "BO06" else "branch","reward_enabled":false})
	return result
static func encounter_plan(id: String, zone: int, difficulty: int, calibration: Variant = null) -> Dictionary:
	var definition := Content.room(id)
	if definition.is_empty() or id == "BO06" or zone < 0 or zone > 1 or difficulty < 0 or difficulty > 4: return {}
	var waves: Array = []
	# Three finite dock waves TOTAL: zone zero has two, zone one has one.
	var count := 2 if id == "L36" and zone == 0 else 1
	for wave in count:
		var members: Array = []
		for enemy_id: String in definition.introduced_enemy_ids:
			var rank := "elite" if difficulty>=3 and zone==1 and Content.enemy(enemy_id).profile=="T" else "normal"
			var profile: Dictionary = preload("res://scripts/combat/b06_enemy_skills.gd").profile(enemy_id,int(definition.enemy_level),difficulty,rank,calibration)
			profile.merge({"zone_index":zone,"wave_index":wave,"encounter_budget":18,"encounter_budget_cost":1,"encounter_slot_cost":1,"effective_threat_cost":1,"reserved_summon_count":0,"reserved_summon_threat":0,"attack_parameters":{}},true)
			members.append(profile)
		waves.append(members)
	var total := 0
	for wave: Array in waves: total += wave.size()
	return {"room_id":id,"zone_index":zone,"biome_id":"B06","enemy_level":int(definition.enemy_level),"total_count":total,"initial_count":waves[0].size(),"completion_requires_all_waves":true,"waves":waves,"concurrent_threat_budget":18,"concurrent_cap":6,"reinforce_alive_threshold":0,"reinforce_threat_fraction":0.0,"reinforce_delay_seconds":3.0,"candidate_contact_only":true}
