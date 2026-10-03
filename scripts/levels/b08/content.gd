extends RefCounted
const PATH := "res://data/levels/b08/content.json"
static var _data: Dictionary = {}
static func catalog() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and parsed.get("version") == 1 and parsed.get("biome_id") == "B08": _data = parsed
	return _data.duplicate(true)
static func room(id: String) -> Dictionary: return catalog().get("rooms",{}).get(id,{}).duplicate(true)
static func enemy(id: String) -> Dictionary: return catalog().get("enemies",{}).get(id,{}).duplicate(true)
static func room_ids() -> Array: return catalog().get("rooms",{}).keys()
