class_name B10Content
extends RefCounted
## The final chapter owns its stable identities; scenery and combat stay separate.
const DATA_PATH := "res://data/levels/b10/content.json"
static var _data: Dictionary = {}
static var _loaded := false

static func catalog() -> Dictionary:
	if not _loaded:
		_loaded = true
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(DATA_PATH)))
		if value is Dictionary and value.get("biome_id") == "B10" and value.get("schema_version") == 1:
			_data = value
		else:
			push_error("Invalid B10 content catalog")
	return _data.duplicate(true)

static func room(id: String) -> Dictionary:
	return catalog().get("rooms", {}).get(id, {}).duplicate(true)

static func room_ids() -> Array:
	return catalog().get("room_ids", []).duplicate()

static func enemy_ids() -> Array:
	return catalog().get("enemy_ids", []).duplicate()

static func validate() -> Array:
	var errors: Array = []
	var data := catalog()
	if data.get("runtime_enabled") != true or data.get("progression", {}).get("final_chapter") != true:
		errors.append("B10 must be the enabled final chapter")
	if room_ids() != ["L55", "L56", "L57", "L58", "L59", "L60", "BO10"]:
		errors.append("B10 must own six dragon rooms and the final arena")
	if enemy_ids().size() != 18:
		errors.append("B10 requires 18 ordinary identities")
	for index: int in range(7):
		var id := "L%02d" % (55 + index) if index < 6 else "BO10"
		var value := room(id)
		if value.get("room_id") != id or value.get("biome_id") != "B10":
			errors.append(id + " invalid identity")
		if value.get("dragon_id") != ("B10-D%02d" % (index + 1) if index < 6 else "BO10"):
			errors.append(id + " missing independent dragon")
		if index < 6 and value.get("introduced_enemy_ids", []).size() != 3:
			errors.append(id + " must introduce three ordinary species")
	return errors
