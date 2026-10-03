class_name AssetCatalog
extends RefCounted
## Logical resource IDs are independent of physical directories and filenames.
## The registry is the only routing table; it never scans or creates fallback art.
const INDEX := "res://assets/manifest.json"
static var _resources: Dictionary = {}

static func resolve(path: String) -> String:
	if not path.begins_with("asset://"):
		return path
	if _resources.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if data is Dictionary:
			_resources = data.get("resources", {})
	var key := path.trim_prefix("asset://").to_lower()
	if _resources.has(key):
		return str(_resources[key])
	if key.ends_with(".import"):
		return resolve(path.trim_suffix(".import")) + ".import"
	# Missing optional entries are tested with file_exists before fallback selection.
	return "res://assets/__missing__/" + key

static func boss_body(boss_id: String) -> String:
	if boss_id == "BO05":
		return "asset://bosses/b05_poses_v1/BO05_idle-native.png"
	if boss_id == "BO06":
		return "asset://b06_native_v1/boss/BO06_idle-native-v4.png"
	return "asset://ui/refactor_v1/codex/" + boss_id + ".png"

static func resources() -> Dictionary:
	resolve("asset://__index__")
	return _resources.duplicate(true)

static func directories(logical_path: String) -> Array[String]:
	var prefix := logical_path.trim_prefix("asset://").to_lower().trim_suffix("/") + "/"
	var result: Array[String] = []
	for key: String in resources():
		if not key.begins_with(prefix): continue
		var relative := key.trim_prefix(prefix)
		if not relative.contains("/"): continue
		var child := relative.get_slice("/", 0)
		if child not in result: result.append(child)
	result.sort()
	return result
