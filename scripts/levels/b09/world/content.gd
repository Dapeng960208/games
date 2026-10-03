extends RefCounted
## B09 authored identities. Candidate execution does not open missing B07/B08.
static var _content: Dictionary = {}
static var _geometry: Dictionary = {}

static func data() -> Dictionary:
	if _content.is_empty():
		_content = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://data/levels/b09/content.json")))
	return _content

static func enemy(id: String) -> Dictionary:
	return data().enemies.get(id, {}).duplicate(true)

static func room(id: String) -> Dictionary:
	if _geometry.is_empty():
		_geometry = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://data/levels/b09/room_geometry.json")))
	return _geometry.rooms.get(id, {}).duplicate(true)

static func room_ids() -> Array:
	return ["L49", "L50", "L51", "L52", "L53", "L54", "BO09"]

static func point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1])) * 0.58

static func rect(value: Array) -> Rect2:
	return Rect2(point(value.slice(0, 2)), point(value.slice(2, 4)))

static func polygon(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value: Array in values: result.append(point(value))
	return result
