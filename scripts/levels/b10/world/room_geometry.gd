class_name B10RoomGeometry
extends RefCounted
## One authored coordinate system serves the painting, collision, portals and feet.
const PATH := "res://data/levels/b10/room_geometry.json"
const SCALE := 0.58
const BLUEPRINT_SIZE := Vector2(2800, 1800)
static var _data: Dictionary = {}
static var _loaded := false

static func room(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(PATH)))
		if value is Dictionary and value.get("version") == 1 and value.get("biome_id") == "B10":
			_data = value
		else:
			push_error("Invalid B10 room geometry")
	return _data.get("rooms", {}).get(id, {}).duplicate(true)

static func world_point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) * SCALE

static func points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value: Array in values:
		result.append(world_point(value))
	return result

static func polygon(id: String) -> PackedVector2Array:
	return points(room(id).get("walkable_polygon", []))

static func zone_at(id: String, at: Vector2) -> String:
	var definition := room(id)
	if not at.is_finite() or definition.is_empty(): return ""
	var coordinate := at.x / SCALE if definition.get("partition_axis", "x") == "x" else at.y / SCALE
	var index := 0
	for split: float in definition.get("partition_splits", []):
		if coordinate >= split: index += 1
	return id + ":zone:" + str(index)

static func anchor_clearance(id: String, at: Vector2) -> float:
	var floor_polygon := polygon(id)
	if not Geometry2D.is_point_in_polygon(at, floor_polygon): return -1.0
	var clearance := INF
	for index: int in floor_polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(at, floor_polygon[index], floor_polygon[(index + 1) % floor_polygon.size()])
		clearance = minf(clearance, closest.distance_to(at))
	return clearance

static func validate(id: String) -> Array:
	var errors: Array = []
	var definition := room(id)
	if definition.is_empty(): return ["Unknown B10 room"]
	var shape := polygon(id)
	if shape.size() < 3 or Geometry2D.triangulate_polygon(shape).is_empty():
		return ["Invalid B10 floor polygon"]
	var anchors: Array = [definition.entry, definition.exit, definition.dragon_spawn]
	for gate: Dictionary in definition.gates:
		anchors.append(gate.position)
		anchors.append(gate.destination)
		if not definition.gates.any(func(other: Dictionary) -> bool: return other.position == gate.destination and other.destination == gate.position and other.pair_id == gate.pair_id):
			errors.append("Unpaired star gate " + str(gate.id))
		if anchor_clearance(id, world_point(gate.position)) < 100.0:
			errors.append("Star gate landing area is too narrow " + str(gate.id))
	for core: Dictionary in definition.star_cores: anchors.append(core.position)
	for route: Array in definition.walk_routes:
		for index: int in range(route.size() - 1):
			var a := world_point(route[index])
			var b := world_point(route[index + 1])
			for sample: int in range(33):
				if anchor_clearance(id, a.lerp(b, float(sample) / 32.0)) < 90.0:
					errors.append("Walking route requires 180 world pixels of clearance")
					break
	for anchor: Array in anchors:
		if anchor_clearance(id, world_point(anchor)) < 30.0:
			errors.append("Required anchor outside connected floor clearance")
	# Every floor is convex, so clear endpoints guarantee continuous walking paths.
	for triangle_index: int in shape.size():
		var a := shape[triangle_index]
		var b := shape[(triangle_index + 1) % shape.size()]
		var c := shape[(triangle_index + 2) % shape.size()]
		if (b - a).cross(c - b) < -0.01:
			errors.append("Room floor must preserve a connected convex main court")
	return errors
