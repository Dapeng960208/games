extends RefCounted
## Candidate-only adapter; authoritative geometry and designs remain separate.
const Content = preload("res://scripts/world/b06_content.gd")
const Geometry = preload("res://scripts/world/b06_room_geometry.gd")

static func biome() -> Dictionary:
	return {"biome_id":"B06","name":"琉潮珊城","name_en":"Tidal Coral City","race":"海族","race_en":"Sea folk","room_ids":["L31","L32","L33","L34","L35","L36"],"enemy_ids":Content.enemy_ids(),"boss_id":"BO06","unlock_requires":"BO05","accent":"59c9de","visual":"日照浅海、珊瑚街巷与珍珠白贝桥","candidate":true}

static func room(id: String) -> Dictionary:
	if id not in biome().room_ids: return {}
	var result := Content.room(id)
	var geometry := Geometry.room(id)
	var zones: Array = []
	for index in range(geometry.encounter_anchors.size()):
		zones.append({"id":id+"_encounter_"+str(index+1),"center":geometry.encounter_anchors[index],"concurrent_cap":6})
	var wave: Array = []
	for enemy_id: String in result.introduced_enemy_ids: wave.append({"enemy_id":enemy_id,"count":1})
	result.merge({"role_tags":["branch","objective","elite_objective"],"objective_id":"b06_tide_"+id.to_lower(),"objective_count":0,"expedition_objective_count":0,"topology_id":"b06_frozen_"+id.to_lower(),"mechanic":result.encounter_text,"reference_wave":wave,"preview":{"objective":result.encounter_text,"risk":"固定潮汐与有限波次；全周期保留干地路线","reward":result.reward_bias_text},"geometry":{"encounter_zones":zones,"room_concurrent_cap":18},"candidate":true},true)
	return result

static func enemy(id: String) -> Dictionary:
	var result := Content.enemy(id)
	if result.is_empty(): return {}
	result.merge({"behavior_id":"b06_"+id.to_lower(),"behavior_graph":"b06_species_skills","role":result.profile,"visual_descriptor":result.silhouette,"tell":result.skills["0"].source_text,"counter":result.counter_and_drop_text,"silhouette_id":id,"telegraph_id":id+"_tell","drop_group":"B06","summon_ownership":"room_shared_capacity_no_rewards","damage_kind":"kinetic","status_applications":[],"threat_cost":2 if result.profile in ["S","T"] else 1},true)
	return result

static func boss() -> Dictionary:
	var result := Content.boss()
	result.merge({"phase_thresholds":[0.7,0.4],"reinforcement_cap":2,"reinforcement_budget":2,"arena":{"arena_id":"BO06_arena","name":"行走堡垒湾","reinforcements":[]},"candidate":true},true)
	return result
