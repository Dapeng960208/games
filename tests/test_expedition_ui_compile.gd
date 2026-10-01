extends SceneTree

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var paths := ["res://scripts/world/expedition_controller.gd","res://scripts/ui/expedition_panel.gd","res://scripts/ui/main.gd"]
	var errors := 0
	for path in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			errors += 1
			push_error("Cannot instantiate "+path)
	print("EXPEDITION_UI_COMPILE errors=",errors)
	quit(errors)
