extends RefCounted
## Candidate-only adapter; authoritative geometry and designs remain separate.
const Content = preload("res://scripts/world/b05_content.gd")
const Geometry = preload("res://scripts/world/b05_room_geometry.gd")

static func biome() -> Dictionary:
	return {"biome_id":"B05","name":"繁花树庭","name_en":"Blooming Tree Court","race":"植灵族","race_en":"Plant spirits","room_ids":["L25","L26","L27","L28","L29","L30"],"enemy_ids":Content.enemy_ids(),"boss_id":"BO05","unlock_requires":"BO04","accent":"68ba8a","visual":"翡翠叶片、桃粉花冠与浅金木纹","candidate":true}

static func room(id: String) -> Dictionary:
	if id not in biome().room_ids: return {}
	var result := Content.room(id)
	var geometry := Geometry.room(id)
	var zones: Array = []
	for index in range(2 if id == "L25" else geometry.encounter_anchors.size()):
		zones.append({"id":id+"_encounter_"+str(index+1),"center":geometry.encounter_anchors[index],"concurrent_cap":6})
	var wave: Array = []
	for enemy_id: String in result.introduced_enemy_ids: wave.append({"enemy_id":enemy_id,"count":1})
	result.merge({"role_tags":["branch","objective","elite_objective"],"objective_id":"b05_root_network_"+id.to_lower(),"objective_count":0,"expedition_objective_count":0,"topology_id":"b05_frozen_"+id.to_lower(),"mechanic":result.encounter_text,"reference_wave":wave,"preview":{"objective":result.encounter_text,"risk":"根网与有限波次；保留安全侧路","reward":result.reward_bias_text},"geometry":{"encounter_zones":zones,"room_concurrent_cap":18},"candidate":true},true)
	return result

static func enemy(id: String) -> Dictionary:
	var result := Content.enemy(id)
	if result.is_empty(): return {}
	result.merge({"behavior_id":"b05_"+id.to_lower(),"behavior_graph":"b05_species_skills","role":result.profile,"visual_descriptor":result.silhouette,"tell":result.skills["0"].source_text,"counter":result.counter_and_drop_text,"silhouette_id":id,"telegraph_id":id+"_tell","drop_group":"B05","summon_ownership":"room_shared_capacity_no_rewards","damage_kind":"kinetic","status_applications":[],"threat_cost":2 if result.profile in ["S","T"] else 1},true)
	return result

static func boss() -> Dictionary:
	var result := Content.boss()
	result.merge({"phase_thresholds":[0.7,0.35],"reinforcement_cap":2,"reinforcement_budget":2,"arena":{"arena_id":"BO05_arena","name":"花冠王座","reinforcements":[]},"candidate":true},true)
	return result
