extends RefCounted
## The B05 compiler consumes frozen geometry; it never moves a route to fit art.
const Geometry = preload("res://scripts/world/b05_room_geometry.gd")
const Fixed = preload("res://scripts/world/fixed_room_layouts.gd")
const Content = preload("res://scripts/world/b05_content.gd")

static func build(id: String, seed_value: int = 0) -> Dictionary:
	var definition := Geometry.room(id)
	if definition.is_empty(): return {}
	var authored := Content.room(id)
	var encounters: Array = []
	for point: Array in definition.get("encounter_anchors",[]).slice(0,2 if id == "L25" else 3):
		encounters.append({"center":point,"radius":220})
	var source := {"id":id,"biome_id":"B05","name":definition.name,"kind":"combat","entry":definition.entry,"exit":definition.exit,"route":definition.main_route,"side_route":definition.get("root_approach_route",[]),"beacons":[definition.beacon_anchor] if definition.has("beacon_anchor") else [],"encounters":encounters,"objectives":[],"props":[],"decorations":[],"fixed_world_entities":[],"fixed_optional_rewards":[]}
	if id == "BO05":
		source.kind = "boss"
		source["boss"] = {"position":definition.get("boss_spawn",[1400,800])}
	var result: Dictionary = Fixed._from_blueprint(source)
	result["seed"] = seed_value
	result["generation_version"] = 8
	result["b05_geometry"] = definition.duplicate(true)
	result["ground_polygon"] = Geometry.polygon(id)
	result["b05_content"] = authored.duplicate(true)
	result["dynamic_states_verified"] = false
	result["fixed_objective_count"] = 0
	result["b05_art_ready"] = bool(definition.art.get("ready",false))
	# Root wells use circular collision in the mechanism host. These static
	# rectangles describe only the authored low cover, never sprite alpha.
	for cover: Dictionary in definition.get("low_cover",[]):
		var center := Geometry.world_point(cover.position)
		var size := Geometry.world_point(cover.footprint_blueprint)
		result.obstructions.append(Rect2(center-size*0.5,size))
		result.obstruction_kinds.append("b05_low_cover")
	for values: Array in definition.get("voids",[]):
		result.obstructions.append(Rect2(Geometry.world_point([values[0],values[1]]),Geometry.world_point([values[2],values[3]])))
		result.obstruction_kinds.append("b05_gap")
	for bridge: Dictionary in definition.get("bridges",[]):
		if bool(bridge.get("open",false)): continue
		var values: Array=bridge.blocked_rect_blueprint
		result.obstructions.append(Rect2(Geometry.world_point([values[0],values[1]]),Geometry.world_point([values[2],values[3]])))
		result.obstruction_kinds.append("b05_bridge:"+str(bridge.id))
	result.static_obstructions = result.obstructions.duplicate()
	result.static_obstruction_kinds = result.obstruction_kinds.duplicate()
	return result
