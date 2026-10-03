extends RefCounted
## Frozen room geometry. Shallow water is walkable in every phase.
const PATH := "res://data/levels/b06/room_geometry.json"
const SCALE := preload("res://scripts/domain/world/fixed_room_layouts.gd").PLAYFIELD_SCALE
static var _data: Dictionary = {}
static func room(id: String) -> Dictionary:
	if _data.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(PATH)))
		if not value is Dictionary or value.get("version") != 1 or value.get("biome_id") != "B06": return {}
		_data = value
	return _data.get("rooms",{}).get(id,{}).duplicate(true)
static func world_point(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1])) * SCALE
static func points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value: Array in values: result.append(world_point(value))
	return result
static func polygon(id: String) -> PackedVector2Array:
	return points(room(id).get("walkable_polygon",[]))
static func patch_at(id: String, point: Vector2) -> String:
	if not point.is_finite(): return ""
	for patch: Dictionary in room(id).get("shallow_patches",[]):
		if Geometry2D.is_point_in_polygon(point,points(patch.polygon)): return str(patch.id)
	return ""
static func area(polygon_value: PackedVector2Array) -> float:
	var result := 0.0
	for index in polygon_value.size(): result += polygon_value[index].cross(polygon_value[(index+1)%polygon_value.size()])
	return absf(result)*0.5
static func validate(id: String) -> Array:
	var errors: Array = []
	var definition := room(id)
	if definition.is_empty(): return ["unknown room"]
	var floor_polygon := polygon(id)
	var wet_area := 0.0
	var patches: Array[PackedVector2Array] = []
	for patch: Dictionary in definition.shallow_patches:
		var shape := points(patch.polygon)
		if not Geometry2D.clip_polygons(shape,floor_polygon).is_empty(): errors.append("patch outside floor")
		wet_area += area(shape)
		patches.append(shape)
	if wet_area > area(floor_polygon)*0.65: errors.append("dry area below 35 percent")
	for route: Array in definition.dry_routes:
		var corridors := Geometry2D.offset_polyline(points(route),90.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
		for corridor: PackedVector2Array in corridors:
			if not Geometry2D.clip_polygons(corridor,floor_polygon).is_empty(): errors.append("route leaves floor")
			for patch: PackedVector2Array in patches:
				if not Geometry2D.intersect_polygons(corridor,patch).is_empty(): errors.append("wet main or gate approach")
	return errors
