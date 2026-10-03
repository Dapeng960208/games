extends "res://scripts/presentation/app/main.gd"
## Reuse Main's combat detail, character and modal views, without its lifecycle.
const CandidateGate = preload("res://scripts/levels/b08/candidate_gate.gd")
const CandidateHUD = preload("res://scripts/levels/b08/presentation/hud_adapter.gd")
const CandidateBackpack = preload("res://scripts/levels/b08/presentation/hud_backpack.gd")
var candidate_finished := false
var candidate_run_id := ""

static func enabled_for(source_room: Node) -> bool:
	return CandidateGate.enabled() and OS.get_cmdline_user_args().has("--b08-existing-hud") and is_instance_valid(source_room) and str(source_room.layout_id) == "L43"

func _ready() -> void:
	if not enabled_for(room) or Game.run == null:
		queue_free()
		return
	name = "B08CombatUI"
	process_mode = Node.PROCESS_MODE_ALWAYS
	route = "run"
	candidate_run_id = Game.run.id
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = GameStyle.make_theme()
	layer.add_child(ui)
	hud = load(AssetCatalog.resolve("res://scenes/presentation/hud.tscn")).instantiate()
	hud.set_script(CandidateHUD)
	hud.room = room
	hud.relic_details_requested.connect(func():
		if not candidate_finished and modals.is_empty(): show_relics())
	hud.skill_details_requested.connect(func(slot: String):
		if not candidate_finished and modals.is_empty(): show_combat_details(slot))
	hud.inventory_requested.connect(show_backpack)
	ui.add_child(hud)
	Game.run_finished.connect(_on_run_finished)

func _on_run_finished(result: Dictionary) -> void:
	if str(result.get("run_id","")) != candidate_run_id: return
	candidate_finished = true
	close_panels()
	hud.show_finished(result)
	if is_instance_valid(room): room.set_input_blocked(true)

func show_backpack() -> void:
	if candidate_finished or Game.run == null or not is_instance_valid(room) or not modals.is_empty(): return
	var panel := _push_modal("",Vector2(1060,620))
	panel.name = "CombatBackpackModal"
	var backpack := CandidateBackpack.new()
	panel.add_child(backpack)
	backpack.configure(room,_pop_modal)
	backpack.find_child("CloseBackpack",true,false).grab_focus()

func close_panels() -> void:
	if not modals.is_empty(): _clear_modals()

func _input(event: InputEvent) -> void:
	if candidate_finished: return
	if event is InputEventKey and event.echo: return
	if _is_menu_cancel(event):
		if not modals.is_empty():
			get_viewport().set_input_as_handled()
			_pop_modal()
		return
	if not modals.is_empty() or Game.run == null: return
	if event.is_action_pressed("backpack"):
		get_viewport().set_input_as_handled()
		show_backpack()
	elif event.is_action_pressed("relic_details"):
		get_viewport().set_input_as_handled()
		show_combat_details()

func _process(_delta: float) -> void: pass
func _unhandled_input(_event: InputEvent) -> void: pass
func _notification(_what: int) -> void: pass
func _exit_tree() -> void:
	if not modals.is_empty(): get_tree().paused = false
