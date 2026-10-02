extends RefCounted
## Frozen B05 placement shared by art and gameplay; no chapter registration.
const PATH := "res://data/b05_room_geometry.json"
const SCALE := 0.58
const SIZE := Vector2(2800,1800)
const PLACEMENT := Rect2(0.11,0.13,0.78,0.74)
static var _data: Dictionary = {}

static func room(id: String) -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary or parsed.get("version") != 1 or parsed.get("biome_id") != "B05": return {}
		_data = parsed
	return _data.get("rooms",{}).get(id,{}).duplicate(true)

static func world_point(point: Array) -> Vector2:
	return Vector2(float(point[0]),float(point[1])) * SCALE

static func image_point(point: Array, image_size: Vector2i) -> Vector2:
	return (PLACEMENT.position + Vector2(float(point[0]),float(point[1])) / SIZE * PLACEMENT.size) * Vector2(image_size)

static func polygon(id: String) -> PackedVector2Array:
	return _points(room(id).get("walkable_polygon",[]))

static func route(id: String, key: String = "main_route") -> PackedVector2Array:
	return _points(room(id).get(key,[]))

static func obstacles(id: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var definition: Dictionary = room(id)
	for cover: Dictionary in definition.get("low_cover",[]):
		var center := world_point(cover.position)
		var half := world_point(cover.footprint_blueprint) / 2.0
		result.append(PackedVector2Array([center-half,center+Vector2(half.x,-half.y),center+half,center+Vector2(-half.x,half.y)]))
	for well: Dictionary in definition.get("root_wells",[]):
		var footprint := PackedVector2Array()
		for index in range(32):
			footprint.append(world_point(well.position) + Vector2.from_angle(TAU * index / 32.0) * float(well.foot_radius_world))
		result.append(footprint)
	return result

## Full-width route validation, not merely checking waypoint centers.
static func route_is_clear(id: String, key: String, width_world: float) -> bool:
	if not is_finite(width_world) or width_world <= 0.0: return false
	var points := route(id,key)
	var floor_polygon := polygon(id)
	if points.size() < 2 or floor_polygon.size() < 3: return false
	var corridors := Geometry2D.offset_polyline(points,width_world / 2.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	if corridors.is_empty(): return false
	for corridor: PackedVector2Array in corridors:
		if not Geometry2D.clip_polygons(corridor,floor_polygon).is_empty(): return false
		for obstacle: PackedVector2Array in obstacles(id):
			if not Geometry2D.intersect_polygons(corridor,obstacle).is_empty(): return false
	return true

## Candidate active hazard polygons use WORLD coordinates. Keep the entire
## safe-route corridor clear and conservatively budget sum of clipped areas;
## overlap never permits an underestimated union. Call before hazard admission.
static func hazards_allowed(id: String, hazards: Array) -> bool:
	var definition := room(id)
	if definition.is_empty(): return false
	var floor_polygon := polygon(id)
	var safe_corridors := Geometry2D.offset_polyline(route(id,"safe_route"),float(definition.safe_route_width_world)/2.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	var total := 0.0
	for hazard: Variant in hazards:
		if not hazard is PackedVector2Array or hazard.size() < 3: return false
		for point: Vector2 in hazard:
			if not point.is_finite(): return false
		if Geometry2D.triangulate_polygon(hazard).is_empty(): return false
		for corridor: PackedVector2Array in safe_corridors:
			if not Geometry2D.intersect_polygons(hazard,corridor).is_empty(): return false
		for clipped: PackedVector2Array in Geometry2D.intersect_polygons(hazard,floor_polygon):
			total += _area(clipped)
	return total <= _area(floor_polygon) * float(definition.maximum_active_hazard_area_ratio)

static func _points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Array in values: result.append(world_point(point))
	return result

static func _area(points: PackedVector2Array) -> float:
	var result := 0.0
	for index in points.size():
		result += points[index].cross(points[(index+1)%points.size()])
	return absf(result)/2.0
