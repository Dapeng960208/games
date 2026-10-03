class_name NumericalRules
extends RefCounted
## Versioned, opt-in rules. No global toggle changes an adventure in progress.
## data/rules/numerical.json is the sole runtime parameter source; docs are snapshots.
const LEGACY := 1
const V2 := 2
const PARAMETERS_PATH := "res://data/rules/numerical.json"
static var _parameters: Dictionary = {}

static func parameters() -> Dictionary:
	if _parameters.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(PARAMETERS_PATH)))
		assert(parsed is Dictionary, "Missing numerical rules configuration")
		_parameters = parsed
	return _parameters.duplicate(true)

## Candidate preview requires BOTH a debug flag and an explicitly isolated save.
## Experiment flags stay isolated; released chapters come from the shipped JSON.
static var _candidate_b05 := -1
static func b05_candidate_enabled() -> bool:
	if b06_candidate_enabled(): return true
	if _candidate_b05 < 0:
		_candidate_b05 = int(OS.has_feature("debug") and _candidate_arguments_valid(OS.get_cmdline_user_args()))
	return _candidate_b05 == 1

static func b06_candidate_enabled() -> bool:
	return OS.has_feature("debug") and _candidate_arguments_valid(OS.get_cmdline_user_args(),"b06")

## Chapter identity is independent of the highest authored level. The shipped
## first six chapters remain released when the final court is registered.
static func released_chapters() -> Array:
	return value("released_chapters", ["B01", "B02", "B03", "B04", "B05", "B06"])

static func chapter_enabled(chapter: Variant) -> bool:
	var chapter_id := ""
	if chapter is int and chapter >= 1 and chapter <= 10:
		chapter_id = "B%02d" % chapter
	elif chapter is String:
		chapter_id = chapter
	if chapter_id == "B10" and b05_candidate_enabled(): return false
	return chapter_id in released_chapters()

static func _candidate_arguments_valid(args: PackedStringArray, chapter: String = "b05") -> bool:
	if chapter not in ["b05","b06"] or not args.has("--candidate-"+chapter): return false
	if args.has("--candidate-b05") and args.has("--candidate-b06"): return false
	var paths: Array[String] = []
	for argument: String in args:
		if argument.begins_with("--test-profile="): paths.append(argument.trim_prefix("--test-profile="))
	if paths.size() != 1: return false
	var path := paths[0]
	if not path.begins_with("user://test_"+chapter+"_candidate/") or not path.ends_with(".json"): return false
	if "\\" in path or ":" in path.trim_prefix("user://"): return false
	for component: String in path.trim_prefix("user://").split("/"):
		if component in ["", ".", ".."]: return false
	return true

static func value(key: String, fallback: Variant = null) -> Variant:
	if key == "level_cap" and b05_candidate_enabled(): return 30
	if _parameters.is_empty(): parameters()
	var result: Variant = _parameters.get(key, fallback)
	return result.duplicate(true) if result is Dictionary or result is Array else result

static func versions() -> Dictionary:
	# Validation asks for these few constants frequently. Copy only this value,
	# retaining the detached public API without cloning the entire balance file.
	return value("versions")

static func default_ruleset() -> int:
	return V2

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
