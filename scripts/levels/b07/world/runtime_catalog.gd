extends RefCounted
## Runtime adapters preserve the authored identity, parameters and fixed map.
const Content = preload("res://scripts/levels/b07/world/content.gd")
const Geometry = preload("res://scripts/levels/b07/world/room_geometry.gd")

static func biome() -> Dictionary:
	return {"biome_id":"B07", "name":"金沙蜥城", "name_en":"Golden Sand Lizard City", "race":"蜥人", "race_en":"Lizardfolk", "room_ids":["L37","L38","L39","L40","L41","L42"], "enemy_ids":Content.enemy_ids(), "boss_id":"BO07", "unlock_requires":"BO06", "accent":"e8b950", "visual":"金沙阶梯城、青绿太阳盘、朱红布棚与绿松石壁画", "candidate":true}

static func room(id: String) -> Dictionary:
	if id not in biome().room_ids: return {}
	var result := Content.room(id)
	var geometry := Geometry.room(id)
	if result.is_empty() or geometry.is_empty(): return {}
	var zones: Array = []
	for index in geometry.encounter_anchors.size():
		zones.append({"id":id+"_encounter_"+str(index+1), "center":geometry.encounter_anchors[index], "concurrent_cap":6})
	var wave: Array = []
	for enemy_id: String in result.introduced_enemy_ids: wave.append({"enemy_id":enemy_id, "count":1})
	result.merge({"role_tags":["branch","objective","elite_objective"], "objective_id":"b07_mirror_"+id.to_lower(), "objective_count":0, "expedition_objective_count":0, "topology_id":"b07_fixed_"+id.to_lower(), "mechanic":result.encounter_text, "reference_wave":wave, "preview":{"objective":result.encounter_text, "risk":"三态镜完整预览；镜座和手动闸始终可达", "reward":result.reward_bias_text}, "geometry":{"encounter_zones":zones, "room_concurrent_cap":18}, "candidate":true}, true)
	return result

static func enemy(id: String) -> Dictionary:
	var result := Content.enemy(id)
	if result.is_empty(): return {}
	result.merge({"behavior_id":"b07_"+id.to_lower(), "behavior_graph":"b07_species_skills", "role":result.profile, "visual_descriptor":result.silhouette, "tell":result.skills["0"].source_text, "counter":result.counter_and_drop_text, "silhouette_id":id, "telegraph_id":id+"_tell", "drop_group":"B07", "summon_ownership":"room_shared_capacity_no_rewards", "damage_kind":"kinetic", "status_applications":[], "threat_cost":2 if result.profile in ["S","T"] else 1}, true)
	return result

static func boss() -> Dictionary:
	var result := Content.boss()
	result.merge({"phase_thresholds":[0.7,0.35], "reinforcement_cap":2, "reinforcement_budget":2, "arena":{"arena_id":"BO07_arena", "name":"日轮王台", "reinforcements":[]}, "candidate":true}, true)
	return result
