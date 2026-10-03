extends RefCounted
## Authored B09 identities. The shared acquisition generator owns random rolls.
const PATH := "res://data/levels/b09/equipment.json"
static var _data: Dictionary = {}

static func catalog() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary: return {}
		_data = parsed
	return _data.duplicate(true)

static func equipment_ids() -> Array:
	var ids: Array = catalog().get("equipment", {}).keys()
	ids.sort()
	return ids

static func equipment(id: String) -> Dictionary:
	return catalog().get("equipment", {}).get(id, {}).duplicate(true)

static func sets() -> Dictionary:
	return catalog().get("sets", {}).duplicate(true)

static func validate() -> Array[String]:
	var errors: Array[String] = []
	if equipment_ids().size() != 35 or sets().size() != 4: errors.append("B09 requires 35 templates and four sets.")
	for id: String in equipment_ids():
		var item := equipment(id)
		if item.id != id or item.race_id != "B09" or item.slot not in ["weapon", "head", "chest", "hands", "legs", "feet", "ring", "charm"]: errors.append(id+": invalid identity/slot.")
		if item.base_stats != {} or item.main_coefficient != 1.0: errors.append(id+": duplicate stat budget.")
		if item.allowed_heroes.is_empty() or item.power_types.is_empty(): errors.append(id+": missing qualification.")
	return errors
