extends RefCounted
const Content = preload("res://scripts/levels/b09/world/content.gd")
const Fixed = preload("res://scripts/domain/world/fixed_room_layouts.gd")
const Art = preload("res://scripts/infrastructure/assets/world_art.gd")
static func build(id: String, seed_value: int = 0) -> Dictionary:
	var definition := Content.room(id)
	if definition.is_empty(): return {}
	var encounters: Array=[]
	for point: Array in definition.encounter_anchors: encounters.append({"center":point,"radius":220})
	var source := {"id":id,"biome_id":"B09","name":definition.name,"kind":"boss" if id=="BO09" else "combat","entry":definition.entry,"exit":definition.exit,"route":definition.main_route,
		"side_route":definition.get("side_route",[]),"beacons":[],"encounters":encounters,"objectives":[],"props":[],"decorations":[],"fixed_world_entities":[],"fixed_optional_rewards":[]}
	if id=="BO09": source["boss"]={"position":definition.boss_spawn}
	var result: Dictionary=Fixed._from_blueprint(source)
	# The same placement transform owns the painting, boundary and camera.
	# Keep source geometry as the compatibility boundary only if art is absent.
	var ground := Art.environment_ground_polygon(result.arena,"B09",id)
	if ground.is_empty(): ground=Content.polygon(definition.walkable_polygon)
	result.merge({"seed":seed_value,"generation_version":9,"b09_candidate":true,"ground_polygon":ground,"fixed_objective_count":0,"dynamic_states_verified":false},true)
	var walls: Array[Rect2]=[]
	for value: Array in definition.obstructions: walls.append(Content.rect(value))
	result["obstructions"]=walls
	result["obstruction_kinds"]=[]
	return result

static func encounter_plan(id: String, zone: int, difficulty: int) -> Dictionary:
	var definition := Content.room(id)
	if definition.is_empty() or id=="BO09" or zone not in [0,1] or difficulty not in range(5): return {}
	var waves: Array=[]
	for wave in (2 if id=="L54" and zone==0 else 1):
		var members: Array=[]
		for enemy_id: String in definition.introduced_enemy_ids:
			var rank := "elite" if difficulty>=3 and zone==1 and Content.enemy(enemy_id).profile=="T" else "normal"
			var profile: Dictionary=preload("res://scripts/levels/b09/combat/skills.gd").profile(enemy_id,int(definition.enemy_level),difficulty,rank)
			profile.merge({"zone_index":zone,"wave_index":wave},true)
			members.append(profile)
		waves.append(members)
	return {"room_id":id,"zone_index":zone,"biome_id":"B09","enemy_level":definition.enemy_level,"total_count":waves.size()*3,"initial_count":3,"completion_requires_all_waves":true,"waves":waves,
		"concurrent_threat_budget":18,"concurrent_cap":6,"reinforce_alive_threshold":0,"reinforce_threat_fraction":0.0,"reinforce_delay_seconds":3.0}
