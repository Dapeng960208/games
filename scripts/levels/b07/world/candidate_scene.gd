extends Node
## Explicit development launcher only. Never enters the normal campaign route.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Traversal = preload("res://scripts/levels/b07/world/candidate_traversal.gd")
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
var room: Node2D
var traversal = Traversal.new()
var status: Label
var auto_start := true
var last_error := ""
func _ready() -> void:
	if not auto_start: return
	var hero := "CH01"
	var difficulty := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate-hero="): hero = argument.get_slice("=",1)
		if argument.begins_with("--candidate-difficulty="): difficulty = clampi(int(argument.get_slice("=",1)),0,4)
	if not start_candidate(hero,difficulty):
		push_error(last_error)
		get_tree().quit(2)

func start_candidate(hero: String, difficulty: int, build_hud: bool = true) -> bool:
	last_error = ""
	if not Rules.b07_candidate_enabled() or Game.profile_path != _profile_argument():
		last_error = "B07 requires --candidate-b07 and user://test_b07_candidate/...json"
		return false
	if is_instance_valid(room) or Game.run != null:
		last_error = "A candidate or another run is already active; finish it before starting."
		return false
	if hero not in ["CH01","CH02","CH03"] or difficulty not in range(5):
		last_error = "Invalid candidate hero or difficulty."
		return false
	if not Game.has_profile and not Game.new_profile():
		last_error = "Candidate profile creation failed: "+Game.last_error
		return false
	# Use the production class-selection transaction so CH02/CH03 never borrow
	# CH01's incompatible equipped instances. Only this explicit test path writes.
	if not Game.select_hero(hero):
		last_error = "Candidate hero selection failed: "+Game.last_error
		return false
	Game.profile.hero_xp[hero] = maxi(int(Game.profile.hero_xp[hero]),int(Progression.thresholds()[30]))
	# B07 owns its independent traversal; a hidden B01 expedition is wrong here.
	# The published route's Lv20 cap remains unchanged and correctly rejects31.
	if not Game.start_run():
		last_error = "Candidate run initialization failed: "+(Game.last_error if not Game.last_error.is_empty() else "invalid isolated profile or resolved stats")
		return false
	room = preload("res://scenes/gameplay/world/room.tscn").instantiate()
	var context: Dictionary = preload("res://scripts/levels/b07/world/candidate.gd").route()[0]
	context.merge({"difficulty":difficulty,"node_index":0,"seed":27007},true)
	var prepared: Dictionary = room.prepare_expedition_node(context)
	if not prepared.get("valid",false):
		last_error = "Candidate room preparation failed: "+str(prepared.get("error","unknown"))
		room.free()
		room = null
		return false
	room.apply_prepared_expedition_node(prepared)
	add_child(room)
	if not traversal.configure(room,difficulty,27007):
		last_error = "Candidate traversal initialization rejected the isolated run."
		return false
	traversal.node_index = 0
	if build_hud:
		var canvas := CanvasLayer.new()
		add_child(canvas)
		var hud := preload("res://scripts/presentation/hud/hud.gd").new()
		hud.room = room
		canvas.add_child(hud)
		status = Label.new()
		status.position = Vector2(16,174)
		status.add_theme_font_size_override("font_size",16)
		canvas.add_child(status)
	room.set_input_blocked(false)
	return true

func _profile_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="): return argument.trim_prefix("--test-profile=")
	return ""
func _process(_delta: float) -> void:
	if not is_instance_valid(status) or not is_instance_valid(room): return
	status.text = "B07 DEVELOPMENT BLOCKOUT · gear/art/full balance pending\nF: rotate mirror 0.6s | gold: reveal | teal: next state\n" + str(room.layout_id) + (" · gate open" if room.b07_mechanics.state.gate_open else " · light altar or use gate after combat")
	if Game.run == null or Game.run.hp <= 0: status.text += "\nDefeated. Restart this isolated scene to retry."
	if traversal.finished: status.text += "\nCandidate complete. No campaign rewards or unlocks."
