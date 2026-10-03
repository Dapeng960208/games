extends Node
## Production RoomController owns the renderer. No manual helper installation or GUI.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Candidate = preload("res://scripts/levels/b06/world/candidate.gd")

class RejectedEnvironment:
	extends Node2D
	func configure(_layout: Dictionary, tide: Node2D) -> bool:
		# Model a partial renderer failure after taking over the native water flag.
		tide.native_water_visual = true
		add_child(Node2D.new())
		return false

class ProbeRoom:
	extends "res://scripts/gameplay/world/room_controller.gd"
	var renderer_failure := ""
	var rejected_renderer: Node2D
	func _create_b06_environment(id: String) -> Node2D:
		if renderer_failure == "missing": return null
		if renderer_failure == "configure":
			rejected_renderer = RejectedEnvironment.new()
			return rejected_renderer
		return super._create_b06_environment(id)

var checks := 0
var failures := 0
var candidate_enabled := false

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error("B06 ENVIRONMENT LIFECYCLE: "+label)
	return ok

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if not Game.profile_path.contains("test_b06_environment_lifecycle") or OS.get_environment("GAMES_TEST_OUTPUT_DIR").is_empty():
		get_tree().quit(2)
		return
	candidate_enabled = Rules.chapter_enabled(6)
	check(int(Rules.parameters().implemented_chapters) == 6,"six released chapters")
	Game.run = null
	if not check(Game.new_profile() and Game.start_run({"expedition":true,"biome_id":"B01","seed":26062}),"isolated baseline"):
		_finish()
		return
	var baseline_profile := JSON.stringify(Game.profile)
	var baseline_route := JSON.stringify(Game.run.expedition)
	var room = RoomScene.instantiate()
	room.set_script(ProbeRoom)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var prior_environment: Node2D
	var prior_tide: Node2D
	var index := 0
	for context: Dictionary in Candidate.route():
		context = context.duplicate(true)
		context.merge({"node_index":-100-index,"difficulty":2,"seed":26062+index},true)
		var prepared: Dictionary = room.prepare_expedition_node(context)
		if not check(bool(prepared.get("valid",false)),"prepare "+str(context.room_id)): break
		room.apply_prepared_expedition_node(prepared)
		if index == 0: add_child(room) # Exercise real prepared-before-ready entry.
		await get_tree().process_frame
		check(not is_instance_valid(prior_environment),"previous renderer released before "+room.layout_id)
		check(not is_instance_valid(prior_tide),"previous tide released before "+room.layout_id)
		_assert_active(room,room.layout_id)
		var snapshot := _gameplay_snapshot(room)
		prior_environment = room.b06_environment
		room._configure_world_view()
		check(not is_instance_valid(prior_environment),"world-view reconfigure releases old renderer "+room.layout_id)
		check(_gameplay_snapshot(room) == snapshot,"world-view reconfigure is visual only "+room.layout_id)
		_assert_active(room,room.layout_id+" reconfigured")
		prior_environment = room.b06_environment
		prior_tide = room.b06_mechanics
		index += 1
	check(index == 7,"all seven authored rooms use continuous lifecycle")
	if candidate_enabled:
		_test_fallbacks(room)
		_test_prior_state(room)
		await _test_exit_reentry(room)
		# Returning to the production service-room path releases art and mechanics.
		prior_environment = room.b06_environment
		prior_tide = room.b06_mechanics
		var prepared: Dictionary = room.prepare_expedition_node({"room_id":"B06-SUPPLY","biome_id":"B06","role":"supply","difficulty":2,"seed":26062})
		check(bool(prepared.get("valid",false)),"service exit prepares")
		room.apply_prepared_expedition_node(prepared)
		check(not is_instance_valid(prior_environment) and not is_instance_valid(prior_tide),"service exit releases renderer and tide")
		_assert_fallback(room,"service room")
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup before free")
	room.free()
	await get_tree().process_frame
	# Fresh room entry after teardown uses no retained helper or visual state.
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var reload_context: Dictionary = Candidate.route()[0].duplicate(true)
	reload_context["node_index"] = -200
	var reload_prepared: Dictionary = room.prepare_expedition_node(reload_context)
	room.apply_prepared_expedition_node(reload_prepared)
	add_child(room)
	await get_tree().process_frame
	_assert_active(room,"fresh reload")
	prior_environment = room.b06_environment
	prior_tide = room.b06_mechanics
	check(await room.combat_audio.wait_for_cleanup(),"reload audio cleanup")
	room.queue_free()
	await get_tree().process_frame
	check(not is_instance_valid(prior_environment) and not is_instance_valid(prior_tide),"queued room deletion releases renderer and tide")
	check(JSON.stringify(Game.profile) == baseline_profile,"visual lifecycle preserves permanent profile")
	check(JSON.stringify(Game.run.expedition) == baseline_route,"visual lifecycle preserves production expedition")
	_finish()

func _layers(room: Node2D) -> Array:
	return [room.get_node("MineBackdrop"),room._floor_canvas,room._terrain_canvas,room._depth_canvas]

func _environment_count(room: Node2D) -> int:
	var count := 0
	for child: Node in room.get_children():
		if child.name == "B06Environment": count += 1
	return count

func _assert_active(room: Node2D, label: String) -> void:
	check(is_instance_valid(room.b06_mechanics),label+" has real tide")
	if not candidate_enabled:
		_assert_fallback(room,label+" release gate")
		return
	if not check(is_instance_valid(room.b06_environment),label+" renderer attached by room"): return
	check(_environment_count(room) == 1,label+" exactly one renderer")
	check(room.b06_environment.get_parent() == room and room.b06_environment.tide == room.b06_mechanics,label+" renderer bound to room-owned tide")
	check(room.b06_mechanics.native_water_visual,label+" native-water ownership active")
	check(room.b06_environment.water_layers.size() == room.layout.b06_geometry.shallow_patches.size(),label+" all authored water patches present")
	for layer: Node2D in _layers(room): check(not layer.visible,label+" obsolete scenery hidden "+str(layer.name))
	for layer: CanvasItem in [room.player,room.enemies,room.projectiles,room.enemy_props,room.enemy_skills,room.enemy_telegraphs,room.b06_mechanics,room.interaction_overlay,room.impact_feedback,room.defeat_feedback,room.skill_input_feedback]:
		check(layer.visible,label+" gameplay layer preserved "+str(layer.name))
	check(is_instance_valid(room.objectives) and room.objectives.visible,label+" objective/mechanism UI remains visible")
	if room.layout_id == "BO06": check(is_instance_valid(room._boss_actor) and room._boss_actor.visible,label+" actual boss remains visible")

func _assert_fallback(room: Node2D, label: String) -> void:
	check(not is_instance_valid(room.b06_environment) and _environment_count(room) == 0,label+" no residual renderer")
	check(room._b06_previous_visibility.is_empty() and not is_instance_valid(room._b06_environment_tide),label+" no retained ownership")
	for layer: Node2D in _layers(room): check(layer.visible,label+" fallback visible "+str(layer.name))
	if is_instance_valid(room.b06_mechanics): check(not room.b06_mechanics.native_water_visual,label+" procedural water restored")

func _gameplay_snapshot(room: Node2D) -> Dictionary:
	return {"tide":room.b06_mechanics.checkpoint().duplicate(true),"ground":room.ground_polygon.duplicate(),"arena":room.ARENA,"obstructions":room.obstructions.duplicate(),"elapsed":room.elapsed,"difficulty":room.difficulty,"player":room.player.get_instance_id(),"position":room.player.position,"actors":room.enemies.get_children(),"projectiles":room.projectiles.get_children(),"input_blocked":room.input_blocked,"release_gate":room.release_gate,"pointer_release_gate":room.pointer_release_gate,"objectives":room.objectives.get_instance_id(),"profile":JSON.stringify(Game.profile),"run":Game.run.receipt().duplicate(true)}

func _test_fallbacks(room: Node2D) -> void:
	var original: Dictionary = room.layout.duplicate(true)
	for mutation: Dictionary in [{"room_id":"L31"},{"room_id":""},{"b06_candidate":false},{"biome_id":"B01"}]:
		room.layout = original.duplicate(true)
		room.layout.merge(mutation,true)
		room._configure_world_view()
		_assert_fallback(room,"unmatched layout "+str(mutation))
	room.layout = {}
	room._configure_world_view()
	_assert_fallback(room,"missing layout")
	room.layout = original
	var tide: Node2D = room.b06_mechanics
	room.b06_mechanics = null
	room._configure_world_view()
	_assert_fallback(room,"missing runtime")
	room.b06_mechanics = tide
	var original_id: String = tide.room_id
	tide.room_id = "L31"
	room._configure_world_view()
	_assert_fallback(room,"mismatched runtime")
	tide.room_id = original_id
	for failure: String in ["missing","configure"]:
		room.renderer_failure = failure
		var snapshot := _gameplay_snapshot(room)
		room._configure_world_view()
		_assert_fallback(room,failure+" renderer")
		check(not is_instance_valid(room.rejected_renderer),failure+" partially configured node released")
		check(_gameplay_snapshot(room) == snapshot,failure+" renderer does not mutate gameplay")
		room.renderer_failure = ""
		room._configure_world_view()
		_assert_active(room,failure+" retry")
		room._release_b06_environment()

func _test_prior_state(room: Node2D) -> void:
	room._release_b06_environment()
	var layers := _layers(room)
	for index in layers.size(): layers[index].visible = index % 2 == 0
	room.b06_mechanics.native_water_visual = true
	room._configure_world_view()
	room._release_b06_environment()
	check(room.b06_mechanics.native_water_visual,"release restores preexisting native-water true")
	for index in layers.size():
		check(layers[index].visible == (index % 2 == 0),"release restores exact prior visibility "+str(index))
		layers[index].show()
	room.b06_mechanics.native_water_visual = false
	room._configure_world_view()
	_assert_active(room,"restored defaults")

func _test_exit_reentry(room: Node2D) -> void:
	var renderer: Node2D = room.b06_environment
	var snapshot: Dictionary = room.b06_mechanics.checkpoint().duplicate(true)
	check(await room.combat_audio.wait_for_cleanup(),"audio cleanup before retained exit")
	remove_child(room)
	check(not is_instance_valid(renderer),"tree exit frees owned renderer synchronously")
	_assert_fallback(room,"retained tree exit")
	add_child(room)
	await get_tree().process_frame
	_assert_active(room,"retained tree reentry")
	check(room.b06_mechanics.checkpoint() == snapshot,"retained tree reentry preserves single tide clock")

func _finish() -> void:
	Game.run = null
	print("B06_ENVIRONMENT_LIFECYCLE candidate=",candidate_enabled," checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
