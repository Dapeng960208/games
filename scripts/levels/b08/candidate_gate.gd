extends RefCounted
## B08 is independent of B07 and never changes the published chapter count.
static func valid_arguments(args: PackedStringArray) -> bool:
	if not args.has("--candidate-b08"): return false
	var paths: Array[String] = []
	for argument: String in args:
		if argument.begins_with("--candidate-") and argument != "--candidate-b08": return false
		if argument.begins_with("--test-profile="): paths.append(argument.trim_prefix("--test-profile="))
	if paths.size() != 1: return false
	var path := paths[0]
	if not path.begins_with("user://test_b08_candidate/") or not path.ends_with(".json"): return false
	if "\\" in path or ":" in path.trim_prefix("user://"): return false
	for component: String in path.trim_prefix("user://").split("/"):
		if component in ["", ".", ".."]: return false
	return true

static func enabled() -> bool:
	return OS.has_feature("debug") and valid_arguments(OS.get_cmdline_user_args())
