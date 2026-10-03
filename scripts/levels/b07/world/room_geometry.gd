extends RefCounted
## Purpose-built fixed sun-city geometry, independent of presentation textures.
## All authored arrays use 2800x1800 blueprint pixels; scale exactly once.
const Content = preload("res://scripts/levels/b07/world/content.gd")
const SCALE := 0.58
const SAFE_ROUTE_WIDTH := 180.0
const MIRROR_SAFE_RADIUS := 90.0

static func room(id: String) -> Dictionary:
	return Content.geometry(id)

static func world_point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) * SCALE

static func points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value: Array in values: result.append(world_point(value))
	return result

static func polygon(id: String) -> PackedVector2Array:
	return points(room(id).get("walkable_polygon", []))

static func mirror(id: String, mirror_id: String) -> Dictionary:
	for entry: Dictionary in room(id).get("mirrors", []):
		if str(entry.id) == mirror_id: return entry.duplicate(true)
	return {}

static func beam_path(id: String, mirror_id: String, state: int) -> PackedVector2Array:
	var definition := mirror(id, mirror_id)
	if definition.is_empty() or state not in range(3): return PackedVector2Array()
	return points(definition.states[state].path)

static func area(shape: PackedVector2Array) -> float:
	var result := 0.0
	for index in shape.size(): result += shape[index].cross(shape[(index + 1) % shape.size()])
	return absf(result) * 0.5

static func cover_rect(value: Array) -> Rect2:
	return Rect2(Vector2(float(value[0]), float(value[1])) * SCALE, Vector2(float(value[2]), float(value[3])) * SCALE)

static func protected_interaction(id: String, point: Vector2) -> bool:
	if not point.is_finite(): return false
	for entry: Dictionary in room(id).get("mirrors", []):
		if world_point(entry.position).distance_to(point) <= MIRROR_SAFE_RADIUS: return true
	return false

static func validate(id: String) -> Array:
	var errors: Array = []
	var definition := room(id)
	if definition.is_empty(): return ["unknown room"]
	var floor_shape := polygon(id)
	if floor_shape.size() < 3 or area(floor_shape) <= 0: return ["invalid walkable floor"]
	for key: String in ["entry", "exit"]:
		if not Geometry2D.is_point_in_polygon(world_point(definition[key]), floor_shape): errors.append(key + " outside floor")
	for route: Array in definition.safe_routes:
		for corridor: PackedVector2Array in Geometry2D.offset_polyline(points(route), SAFE_ROUTE_WIDTH * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			if not Geometry2D.clip_polygons(corridor, floor_shape).is_empty(): errors.append("safe route leaves floor")
			for cover: Dictionary in definition.stone_covers:
				var rect := cover_rect(cover.rect)
				var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
				if not Geometry2D.intersect_polygons(corridor, corners).is_empty(): errors.append("cover blocks safe route")
	for entry: Dictionary in definition.mirrors:
		var at := world_point(entry.position)
		if not Geometry2D.is_point_in_polygon(at, floor_shape): errors.append("mirror outside floor")
		for cover: Dictionary in definition.stone_covers:
			if cover_rect(cover.rect).grow(MIRROR_SAFE_RADIUS).has_point(at): errors.append("blocked mirror approach")
		if entry.states.size() != 3: errors.append("mirror state count")
		for state: Dictionary in entry.states:
			for point: Vector2 in points(state.path):
				if not Geometry2D.is_point_in_polygon(point, floor_shape): errors.append("beam leaves floor")
	for gate: Dictionary in definition.manual_gates:
		if not Geometry2D.is_point_in_polygon(world_point(gate.position), floor_shape): errors.append("manual gate outside floor")
	if int(definition.required_mirrors) < 1 or int(definition.required_mirrors) > definition.mirrors.size(): errors.append("unreachable mirror requirement")
	return errors
