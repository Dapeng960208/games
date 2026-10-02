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
	if _parameters.is_empty(): parameters()
	var result: Variant = _parameters.get(key, fallback)
	return result.duplicate(true) if result is Dictionary or result is Array else result

static func versions() -> Dictionary:
	# Validation asks for these few constants frequently. Copy only this value,
	# retaining the detached public API without cloning the entire balance file.
	return value("versions")

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

## Round only at a defined combat boundary, never intermediate products.
static func integer(number: float) -> int:
	return maxi(0, int(floor(number + 0.5))) if is_finite(number) else 0

static func amount(number: float, ruleset: int = LEGACY) -> Variant:
	return integer(number) if ruleset == V2 else maxf(0.0, number)

## Only call for authored legacy combat units, not already-scaled values.
static func scale(number: float, ruleset: int = LEGACY) -> Variant:
	return integer(number * float(value("combat_scale"))) if ruleset == V2 else number

static func derived_budget(raw_packet: float, ruleset: int = LEGACY) -> Variant:
	return int(integer(raw_packet) * 6 / 5) if ruleset == V2 else raw_packet * 1.2

## Fractions belong to time accumulation, never to spendable resource.
static func accumulate(number: float, remainder: float) -> Dictionary:
	var total := maxf(0.0, number) + maxf(0.0, remainder)
	var whole := int(floor(total + 0.000000001))
	return {"whole":whole, "remainder":maxf(0.0, total - whole)}
