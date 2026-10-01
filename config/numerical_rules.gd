class_name NumericalRules
extends RefCounted
## Versioned, opt-in rules. No global toggle changes an adventure in progress.
## data/numerical_v2.json is the sole runtime parameter source; docs are snapshots.
const LEGACY := 1
const V2 := 2
const PARAMETERS_PATH := "res://data/numerical_v2.json"
static var _parameters: Dictionary = {}

static func parameters() -> Dictionary:
	if _parameters.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARAMETERS_PATH))
		assert(parsed is Dictionary, "Missing numerical rules configuration")
		_parameters = parsed
	return _parameters.duplicate(true)

static func value(key: String, fallback: Variant = null) -> Variant:
	return parameters().get(key, fallback)

static func versions() -> Dictionary:
	return parameters()["versions"].duplicate(true)

static func default_ruleset() -> int:
	return V2 if bool(value("runtime_enabled", false)) else LEGACY

static func is_v2(snapshot: Dictionary) -> bool:
	return int(snapshot.get("ruleset_version", LEGACY)) == V2

static func frozen_versions(ruleset: int = LEGACY) -> Dictionary:
	if ruleset == V2:
		var result := versions()
		result["ruleset_version"] = V2
		result["scale_version"] = int(result.scale)
		return result
	return {"ruleset_version":LEGACY, "equipment_instance":0, "reward_policy":1, "optional_chest_receipt":1, "scale_version":1}
