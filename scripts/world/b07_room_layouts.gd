extends RefCounted
## Fixed, purpose-built gameplay layout. Formal chapter art is not supplied here.
const Geometry = preload("res://scripts/world/b07_room_geometry.gd")
const Fixed = preload("res://scripts/world/fixed_room_layouts.gd")

static func build(id: String, seed_value: int = 0) -> Dictionary:
	var definition := Geometry.room(id)
	if definition.is_empty(): return {}
	var encounters: Array = []
	for point: Array in definition.encounter_anchors: encounters.append({"center":point, "radius":220})
	var source := {"id":id, "biome_id":"B07", "name":definition.name, "kind":"boss" if id == "BO07" else "combat", "entry":definition.entry, "exit":definition.exit, "route":definition.main_route, "side_route":definition.get("secondary_route", []), "beacons":[], "encounters":encounters, "objectives":[], "props":[], "decorations":[], "fixed_world_entities":[], "fixed_optional_rewards":[]}
	if id == "BO07": source["boss"] = {"position":definition.boss_spawn}
	var result: Dictionary = Fixed._from_blueprint(source)
	result["seed"] = seed_value
	result["generation_version"] = 10
	result["b07_candidate"] = true
	result["b07_geometry"] = definition
	result["ground_polygon"] = Geometry.polygon(id)
	result["fixed_objective_count"] = 0
	result["dynamic_states_verified"] = false
	result["formal_art_status"] = "not_included"
	for mirror: Dictionary in definition.mirrors:
		result.interactables.append({"id":str(mirror.id), "position":Geometry.world_point(mirror.position), "kind":"b07_mirror", "label":"转动引光镜", "label_en":"Turn sun mirror", "interaction_seconds":0.6, "required":false, "implemented":true})
	for gate: Dictionary in definition.manual_gates:
		result.interactables.append({"id":str(gate.id), "position":Geometry.world_point(gate.position), "kind":"b07_manual_gate", "label":"开启手动闸", "label_en":"Open manual gate", "required":false, "implemented":true})
	for cover: Dictionary in definition.stone_covers:
		var rect := Geometry.cover_rect(cover.rect)
		result.obstructions.append(rect)
		result.obstruction_kinds.append("b07_low_stone")
		result.static_obstructions.append(rect)
		result.static_obstruction_kinds.append("b07_low_stone")
	if id == "BO07":
		result["boss_counterplay"] = result.interactables.duplicate(true)
		result["fixed_counterplay_count"] = result.interactables.size()
	return result
