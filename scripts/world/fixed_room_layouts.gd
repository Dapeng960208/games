class_name FixedRoomLayouts
extends RefCounted
## Approved room drawings own scene placement; seeds only vary combat/rewards.
const Catalog = preload("res://scripts/world/world_catalog.gd")
const PATH := "res://data/fixed_rooms.json"
# Drawing coordinates stay authored; build() returns the compact runtime arena.
const ARENA := Rect2(0, 0, 2800, 1800)
const PLAYFIELD_SCALE := 0.58
const MIN_PROP_VISUAL := Vector2(96, 80)
const MAX_FOOTPRINT := Vector2(120, 75)
static var _data: Dictionary = {}
static var _loaded := false
static var _layouts: Dictionary = {}

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if value is Dictionary: _data = value
	else: push_error("Invalid fixed room blueprints: " + PATH)

static func room_ids() -> Array:
	_ensure_loaded()
	var ids: Array = _data.get("rooms", {}).keys()
	ids.sort()
	return ids

static func blueprint(room_id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("rooms", {}).get(room_id, {}).duplicate(true)

static func region(biome_id: String) -> Dictionary:
	_ensure_loaded()
	return _data.get("regions", {}).get(biome_id, {}).duplicate(true)

static func build(room_id: String, seed_value: int = 0) -> Dictionary:
	if not _layouts.has(room_id):
		var source: Dictionary = blueprint(room_id)
		if source.is_empty(): return {}
		_layouts[room_id] = _from_blueprint(source)
	var result: Dictionary = _layouts[room_id].duplicate(true)
	result["seed"] = seed_value
	return result

static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _points(values: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for value: Array in values: result.append(_point(value))
	return result

static func _from_blueprint(source: Dictionary) -> Dictionary:
	var room_id: String = str(source.id)
	var biome_id: String = str(source.biome_id)
	var region_data: Dictionary = region(biome_id)
	var objective_points: Array[Vector2] = []
	var interactables: Array[Dictionary] = []
	for index: int in source.get("objectives", []).size():
		var target: Dictionary = source.objectives[index]
		var at: Vector2 = _point(target.position)
		objective_points.append(at)
		interactables.append({"id":room_id+"_objective_"+str(index+1), "position":at,
			"label":str(target.name), "kind":"faction_objective", "required":true, "implemented":true})
	var route: Array[Vector2] = _points(source.get("route", []))
	var side_route: Array[Vector2] = _points(source.get("side_route", []))
	var layout: Dictionary = {
		"room_id":room_id, "blueprint_room_id":room_id, "biome_id":biome_id,
		"arena":ARENA, "entry":_point(source.entry), "exit":_point(source.exit),
		"fixed_layout":true, "fixed_layout_version":int(_data.get("version", 1)),
		"generated":false, "generation_version":7, "generation_attempts":0,
		"generation_fallback_used":false, "reserved_clearance_radius":24.0,
		"name":str(source.name), "story":str(source.get("story", "")), "motif":str(source.get("motif", "")),
		"edge_design":region_data.get("edge_design", {}).duplicate(true), "edge_variant":str(source.get("edge_variant", "")),
		"fixed_region":region_data, "fixed_room":source.duplicate(true),
		"obstructions":[], "obstruction_kinds":[], "static_obstructions":[], "static_obstruction_kinds":[],
		"prop_instances":[], "decoration_instances":[], "objective_points":objective_points,
		"fixed_objective_count":objective_points.size(), "interactables":interactables,
		"buff_anchors":_points(source.get("beacons", [])), "topology_probes":route+side_route,
		"reserved_paths":{"main":route, "side":side_route}, "fixed_routes":{"main":route, "side":side_route},
		"spawn_points":[], "encounter_zones":[], "hazard_zones":[], "visual_markers":[],
		"dynamic_reservations":[], "fixed_world_entities":[], "fixed_optional_rewards":[],
		"collision_plane_count":1, "room_concurrent_cap":18, "gameplay_implemented":true,
		"dynamic_states_verified":true, "landmark_count":1,
	}
	var open_zone: Array = source.get("open_zone", [])
	if open_zone.size() == 4:
		layout["open_zone"] = Rect2(float(open_zone[0]), float(open_zone[1]), float(open_zone[2]), float(open_zone[3]))
		layout.dynamic_reservations.append({"id":room_id+":combat_clearing", "rect":layout.open_zone})
	_add_props(layout, source)
	_add_encounters(layout, source)
	for original: Dictionary in source.get("fixed_world_entities", []):
		var entity: Dictionary = original.duplicate(true)
		entity["position"] = _point(original.position)
		layout.fixed_world_entities.append(entity)
	for original: Dictionary in source.get("fixed_optional_rewards", []):
		var reward: Dictionary = original.duplicate(true)
		reward["position"] = _point(original.position)
		layout.fixed_optional_rewards.append(reward)
	if str(source.get("kind", "combat")) == "boss":
		layout["boss_spawn"] = _point(source.boss.position)
		layout["boss_counterplay"] = []
		layout.interactables = []
		layout.objective_points = [layout.boss_spawn]
		for original: Dictionary in source.get("runtime_counterplays", []):
			var counter: Dictionary = original.duplicate(true)
			counter["position"] = _point(original.position)
			layout.interactables.append(counter)
			layout.boss_counterplay.append(counter.duplicate(true))
		layout["fixed_counterplay_count"] = layout.boss_counterplay.size()
	var compact: Dictionary = _compact_playfield(layout)
	preload("res://scripts/world/room_presentation.gd").apply_scenery(compact)
	return compact

static func _compact_playfield(blueprint_layout: Dictionary) -> Dictionary:
	# Transform the complete runtime tree once, creating fresh containers. Paths
	# share source arrays before this pass; in-place scaling would multiply those
	# aliases twice. Original JSON and the embedded drawing metadata stay intact.
	var layout: Dictionary = _scaled_runtime(blueprint_layout)
	layout["blueprint_arena"] = ARENA
	layout["layout_scale"] = PLAYFIELD_SCALE
	for key: String in ["prop_instances", "decoration_instances"]:
		for prop: Dictionary in layout.get(key, []):
			var size: Vector2 = Vector2(prop.visual_size).max(MIN_PROP_VISUAL)
			var collision: Rect2 = prop.collision_rect
			var at: Vector2 = prop.position
			var bottom: float = collision.end.y if collision.has_area() else at.y
			prop["visual_size"] = size
			prop["visual_rect"] = Rect2(Vector2(at.x-size.x*.5, bottom-size.y), size)
	return layout

static func _scaled_runtime(value: Variant, field: String = "") -> Variant:
	if field in ["fixed_room", "fixed_region", "edge_design"]:
		return value.duplicate(true) if value is Dictionary or value is Array else value
	if value is Vector2:
		return value*PLAYFIELD_SCALE
	if value is Rect2:
		return Rect2(value.position*PLAYFIELD_SCALE, value.size*PLAYFIELD_SCALE)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: String in value:
			result[key] = _scaled_runtime(value[key], key)
		return result
	if value is Array:
		# duplicate() retains Array[Vector2]/Array[Rect2] element types.
		var result: Array = value.duplicate()
		for index: int in result.size(): result[index] = _scaled_runtime(value[index], field)
		return result
	if (value is float or value is int) and field in ["radius", "inner_radius", "activation_distance", "minimum_player_spawn_distance"]:
		return float(value)*PLAYFIELD_SCALE
	return value

static func _add_props(layout: Dictionary, source: Dictionary) -> void:
	var solids := 0
	for index: int in source.get("props", []).size():
		var original: Dictionary = source.props[index]
		var solid: bool = bool(original.get("solid", false)) and solids < 4
		var at: Vector2 = _point(original.position)
		var footprint: Vector2 = _point(original.get("size", [100, 70])).min(MAX_FOOTPRINT)
		var size: Vector2 = Vector2(maxf(120, footprint.x*1.65), maxf(125, footprint.y*2.3)) if solid else _point(original.get("size", [150, 110]))
		var collision: Rect2 = Rect2(at-footprint*0.5, footprint) if solid else Rect2(at, Vector2.ZERO)
		var bottom: float = collision.end.y if solid else at.y
		var item: Dictionary = {"id":str(layout.room_id)+":fixed_prop:"+str(index),
			"asset":str(layout.biome_id)+"_prop_"+str(original.key), "prop_key":str(original.key),
			"name":str(original.get("name", "")), "position":at, "visual_size":size,
			"visual_rect":Rect2(Vector2(at.x-size.x*0.5, bottom-size.y), size),
			"collision_rect":collision, "kind":"independent_prop" if solid else "fixed_decoration",
			"tags":["solid", "fixed_prop", str(layout.biome_id)] if solid else ["decoration", "non_solid", "fixed_prop", str(layout.biome_id)],
			"rotation":0.0, "fixed":true}
		if solid:
			solids += 1
			layout.prop_instances.append(item)
			layout.obstructions.append(collision)
			layout.obstruction_kinds.append("independent_prop")
		else:
			layout.decoration_instances.append(item)
	var landmark: Dictionary = source.get("landmark", {})
	if not landmark.is_empty():
		var at: Vector2 = _point(landmark.position)
		var size := Vector2(280, 220)
		layout.decoration_instances.append({"id":str(layout.room_id)+":fixed_landmark", "asset":str(layout.biome_id)+"_prop_"+str(landmark.key),
			"prop_key":str(landmark.key), "name":str(landmark.get("name", "")), "position":at,
			"visual_size":size, "visual_rect":Rect2(at-Vector2(size.x*.5, size.y), size), "collision_rect":Rect2(at, Vector2.ZERO),
			"kind":"fixed_landmark", "tags":["decoration", "non_solid", "fixed_landmark", str(layout.biome_id)], "rotation":0.0, "fixed":true})

static func _add_encounters(layout: Dictionary, source: Dictionary) -> void:
	var definition: Dictionary = Catalog.room(str(source.id))
	var authored_zones: Array = definition.get("geometry", {}).get("encounter_zones", [])
	for index: int in source.get("encounters", []).size():
		var encounter: Dictionary = source.encounters[index]
		var center: Vector2 = _point(encounter.center)
		var zone: Dictionary = authored_zones[index].duplicate(true) if index < authored_zones.size() else {}
		var spawns: Array[Vector2] = []
		# Preserve the three-spawn wave contract; the director owns the members.
		for offset: Vector2 in [Vector2(-130, 85), Vector2(130, -85), Vector2(0, 160)]:
			spawns.append((center+offset).clamp(Vector2(90, 90), ARENA.end-Vector2(90, 90)))
		zone.merge({"id":str(source.id)+"_encounter_"+str(index+1), "name":str(encounter.get("name", "")),
			"center":center, "radius":float(encounter.get("radius", 220.0)), "spawn_points":spawns,
			"activation_distance":float(zone.get("activation_distance", 520.0)),
			"minimum_player_spawn_distance":float(zone.get("minimum_player_spawn_distance", 360.0)),
			"concurrent_cap":int(zone.get("concurrent_cap", 6)), "implemented":true}, true)
		layout.encounter_zones.append(zone)
		layout.spawn_points.append_array(spawns)
