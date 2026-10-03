extends Node
## Explicit development launcher only. Never enters the normal campaign route.
const Rules = preload("res://config/numerical_rules.gd")
const Traversal = preload("res://scripts/world/b07_candidate_traversal.gd")
const Progression = preload("res://scripts/core/hero_progression.gd")
var room: Node2D
var traversal = Traversal.new()
var status: Label
func _ready() -> void:
	if not Rules.b07_candidate_enabled() or Game.profile_path != _profile_argument():
		push_error("B07 requires --candidate-b07 and user://test_b07_candidate/...json")
		get_tree().quit(2)
		return
	var hero := "CH01"
	var difficulty := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate-hero="): hero = argument.get_slice("=",1)
		if argument.begins_with("--candidate-difficulty="): difficulty = clampi(int(argument.get_slice("=",1)),0,4)
	if hero not in ["CH01","CH02","CH03"]: get_tree().quit(2); return
	if not Game.has_profile and not Game.new_profile(): get_tree().quit(2); return
	Game.run = null
	Game.profile.selected_hero = hero
	Game.profile.hero_xp[hero] = Progression.thresholds()[30]
	if not Game.start_run({"expedition":true,"biome_id":"B01","difficulty":difficulty,"seed":27007}):
		push_error(Game.last_error)
		get_tree().quit(2)
		return
	room = preload("res://scenes/room.tscn").instantiate()
	var context: Dictionary = preload("res://scripts/world/b07_candidate.gd").route()[0]
	context.merge({"difficulty":difficulty,"node_index":0,"seed":27007},true)
	var prepared: Dictionary = room.prepare_expedition_node(context)
	if not prepared.get("valid",false): push_error(str(prepared)); get_tree().quit(2); return
	room.apply_prepared_expedition_node(prepared)
	add_child(room)
	if not traversal.configure(room,difficulty,27007): get_tree().quit(2); return
	traversal.node_index = 0
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var hud := preload("res://scripts/ui/hud.gd").new()
	hud.room = room
	canvas.add_child(hud)
	status = Label.new()
	status.position = Vector2(16,174)
	status.add_theme_font_size_override("font_size",16)
	canvas.add_child(status)
	room.set_input_blocked(false)
func _profile_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="): return argument.trim_prefix("--test-profile=")
	return ""
func _process(_delta: float) -> void:
	if not is_instance_valid(status) or not is_instance_valid(room): return
	status.text = "B07 DEVELOPMENT BLOCKOUT · gear/art/full balance pending\nF: rotate mirror 0.6s | gold: reveal | teal: next state\n" + str(room.layout_id) + (" · gate open" if room.b07_mechanics.state.gate_open else " · light altar or use gate after combat")
	if Game.run == null or Game.run.hp <= 0: status.text += "\nDefeated. Restart this isolated scene to retry."
	if traversal.finished: status.text += "\nCandidate complete. No campaign rewards or unlocks."
