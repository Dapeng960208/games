extends SceneTree
## Read-only catalog exporter. Run in an empty project with NO autoloads.
## -- <absolute repository root> <absolute JSON destination>
## Extract the runtime functions verbatim; stubs supply only preview context.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected repository root and JSON destination")
		quit(2)
		return
	var root := args[0].replace("\\", "/").trim_suffix("/")
	var source := FileAccess.get_file_as_string(root + "/scripts/combat/hero_abilities.gd")
	var heroes: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "/data/heroes.json"))
	if source.is_empty() or not heroes is Dictionary:
		push_error("Missing preview sources")
		quit(2)
		return
	var wrapper := "extends RefCounted\nvar owner_player: Node2D\nvar Game = {\"run\":null}\nvar ContentRegistry\nfunc hero_key() -> String:\n\treturn \"CH01\"\n"
	wrapper += _function(source, "spec") + _function(source, "_branch") + _function(source, "_apply_branch") + _function(source, "_timeline")
	var script := GDScript.new()
	script.source_code = wrapper
	var error := script.reload()
	if error != OK:
		push_error("Cannot compile verbatim skill preview functions: " + str(error))
		quit(3)
		return
	var registry := PreviewRegistry.new()
	registry.heroes = heroes
	var helper: RefCounted = script.new()
	helper.set("ContentRegistry", registry)
	var rows: Array[Dictionary] = []
	for hero: String in ["CH01", "CH02", "CH03"]:
		for level: int in range(1, 21):
			for slot: String in ["q", "secondary", "f", "ultimate"]:
				var choices: Array[String] = [""]
				if (slot == "q" and level >= 18) or (slot == "ultimate" and level >= 20):
					choices.append_array(["A", "B"])
				for branch: String in choices:
					var stats := {"branches":{slot:branch}, "cooldown_reduction":0.0}
					var spec: Dictionary = helper.call("spec", slot, hero, level, stats)
					var timeline: Array = helper.call("_timeline", spec)
					rows.append({"hero":hero, "level":level, "slot":slot, "branch":branch, "spec":spec, "timeline":timeline})
	var result := {"format":1, "method":"verbatim spec/_branch/_apply_branch/_timeline in empty no-autoload project", "rows":rows}
	var output := FileAccess.open(args[1], FileAccess.WRITE)
	if output == null:
		push_error("Cannot open output: " + str(FileAccess.get_open_error()))
		quit(4)
		return
	output.store_string(JSON.stringify(result, "\t", true, true) + "\n")
	output.close()
	print("BUFF_SKILL_EXPORT rows=" + str(rows.size()) + " OK")
	quit(0)

func _function(source: String, name: String) -> String:
	var result := ""
	var collecting := false
	for line: String in source.split("\n"):
		if line.begins_with("func ") or line.begins_with("static func "):
			if collecting:
				break
			collecting = line.begins_with("func " + name + "(")
		if collecting:
			result += line + "\n"
	return result

class PreviewRegistry:
	extends RefCounted
	var heroes: Dictionary = {}
	func hero(id: String) -> Dictionary:
		return heroes.get(id, {})
