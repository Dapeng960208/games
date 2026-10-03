extends RefCounted
## Explicit candidate compiler; never inserted into the default chapter catalog.
const Geometry = preload("res://scripts/world/b06_room_geometry.gd")
const Fixed = preload("res://scripts/world/fixed_room_layouts.gd")
static func build(id: String, seed_value: int = 0) -> Dictionary:
	var definition := Geometry.room(id)
	if definition.is_empty(): return {}
	var encounters: Array = []
	for point: Array in definition.encounter_anchors: encounters.append({"center":point,"radius":220})
	var source := {"id":id,"biome_id":"B06","name":definition.name,"kind":"boss" if id == "BO06" else "combat","entry":definition.entry,"exit":definition.exit,"route":definition.main_route,"beacons":[],"encounters":encounters,"objectives":[],"props":[],"decorations":[],"fixed_world_entities":[],"fixed_optional_rewards":[]}
	if id == "BO06": source["boss"] = {"position":definition.boss_spawn}
	var result: Dictionary = Fixed._from_blueprint(source)
	result["seed"] = seed_value
	result["generation_version"] = 9
	result["b06_candidate"] = true
	result["b06_geometry"] = definition
	result["ground_polygon"] = Geometry.polygon(id)
	result["fixed_objective_count"] = 0
	result["dynamic_states_verified"] = false
	return result
