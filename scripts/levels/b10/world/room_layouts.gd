class_name B10RoomLayouts
extends RefCounted
## Production compiler for independent final-chapter room drawings.
const Geometry = preload("res://scripts/levels/b10/world/room_geometry.gd")
const Fixed = preload("res://scripts/domain/world/fixed_room_layouts.gd")

static func build(id: String, seed_value: int = 0) -> Dictionary:
	var definition := Geometry.room(id)
	if definition.is_empty(): return {}
	var encounters: Array = []
	for at: Array in definition.encounter_anchors:
		encounters.append({"center": at, "radius": 260})
	var source := {"id": id, "biome_id": "B10", "name": definition.name,
		"kind": "boss" if id == "BO10" else "combat", "entry": definition.entry,
		"exit": definition.exit, "route": definition.main_route,
		"beacons": [], "encounters": encounters, "objectives": [], "props": [],
		"decorations": [], "fixed_world_entities": [], "fixed_optional_rewards": []}
	if id == "BO10": source["boss"] = {"position": definition.boss_spawn}
	var result := Fixed._from_blueprint(source)
	result["seed"] = seed_value
	result["generation_version"] = 10
	result["b10_final"] = true
	result["b10_geometry"] = definition
	result["ground_polygon"] = Geometry.polygon(id)
	result["dragon_id"] = definition.dragon_id
	result["dragon_spawn"] = Geometry.world_point(definition.dragon_spawn)
	result["fixed_objective_count"] = 0
	result["dynamic_states_verified"] = true
	result["room_concurrent_cap"] = 6
	# Compact portals and destructible cores are dynamic actors, not floor blockers.
	result["scenery_anchors"] = []
	for anchor: Dictionary in definition.scenery_anchors:
		var mapped: Dictionary = anchor.duplicate(true)
		mapped["position"] = Geometry.world_point(anchor.position)
		mapped["ground_footprint"] = Geometry.world_point(anchor.ground_footprint)
		result.scenery_anchors.append(mapped)
	if id == "BO10":
		result.merge({"boss_id": "BO10", "arena_id": "BO10_arena",
			"phase_thresholds": [0.7, 0.35], "reinforcement_plan": [],
			"reinforcement_budget": 2, "reinforcement_cap": 2,
			"counterplay_order": [], "reinforcement_spawns": [], "fixed_counterplay_count": 0}, true)
	return result
