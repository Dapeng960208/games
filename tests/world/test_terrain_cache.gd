extends Node
## Integration checks for retained terrain after real room utility/mechanism
## changes. Headless proves state and invalidation, not final raster appearance.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Props = preload("res://scripts/presentation/world/room_props.gd")
const Objectives = preload("res://scripts/gameplay/world/room_objectives.gd")
var room: RoomController
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TERRAIN CACHE FAIL: " + label)

func _tick_canvas_state() -> void:
	# Run the production room tick, including its cache invalidation call.
	# Actor AI/input remains disabled in this isolated geometry fixture.
	room._physics_process(0.0)

func _clear_enemies() -> void:
	for actor in room.enemies.get_children(): actor.free()

func _load(id: String) -> void:
	check(room.load_room_layout(id, 0, 40917), id + " loads the real seeded room")
	_clear_enemies()
	room.spawn_enabled = false
	room.release_gate = false
	_tick_canvas_state()

func _run() -> void:
	if not Game.profile_path.contains("test_terrain_cache"):
		get_tree().quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "interact", "attack", "dash"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.select_hero("CH03") and Game.start_run(), "isolated real player run")
	room = RoomScene.instantiate()
	room.layout_id = "L11"
	room.run_seed = 40917
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	_clear_enemies()
	room.spawn_enabled = false
	room.release_gate = false
	_tick_canvas_state()
	check(is_instance_valid(room._terrain_canvas) and is_instance_valid(room._floor_canvas), "static obstacle and dynamic floor canvases exist independently")
	var redraws: int = room.terrain_redraw_count
	for frame: int in 30: _tick_canvas_state()
	check(room.terrain_redraw_count == redraws, "unchanged production room ticks retain the obstacle draw list")

	var thin: Dictionary = room.enemy_props.target_for(room.player, "bite_breakable_wall")
	check(bool(thin.get("valid", false)), "real generated thin wall provides an approach target")
	if bool(thin.get("valid", false)):
		room.player.position = thin.position
		var rect: Rect2 = thin.rect
		var recipe_index: int = int(thin.recipe_index)
		check(room.enemy_props.utility(room.player, "bite_breakable_wall", {"range":200.0}).success, "production wall utility actually breaks the wall")
		_tick_canvas_state()
		check(not room.obstructions.has(rect) and bool(room.enemy_props.obstacle_recipes[recipe_index].destroyed), "broken wall loses its collision and rendered recipe together")
		check(room.terrain_redraw_count == redraws + 1 and room._terrain_geometry == room.obstructions, "wall break invalidates the retained terrain snapshot on the next production tick")
		redraws = room.terrain_redraw_count

	var replacement := Props.new()
	check(replacement.configure(room, room.enemy_props.effective_layout()), "same damaged geometry can configure a new prop owner")
	var old_props: Node2D = room.enemy_props
	room.add_child(replacement)
	room.enemy_props = replacement
	old_props.free()
	_tick_canvas_state()
	check(room.terrain_redraw_count == redraws + 1 and room._terrain_owner_id == replacement.get_instance_id(), "new prop owner refreshes terrain even when collision rectangles are identical")
	redraws = room.terrain_redraw_count
	_tick_canvas_state()
	check(room.terrain_redraw_count == redraws, "replacement owner is cached after its first submission")

	_load("L13")
	var movable: Dictionary = room.enemy_props.query_tag("movable")[0]
	var moved: bool = false
	redraws = room.terrain_redraw_count
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var approach: Vector2 = movable.position - direction * 130.0
		if not room.valid_ground(approach, Balance.PLAYER_RADIUS): continue
		room.player.position = approach
		var result: Dictionary = room.enemy_props.utility(room.player, "polarity_displacement", {"direction":direction, "travel_distance":20.0, "target_id":movable.id, "target":movable.position})
		if bool(result.success): moved = true; break
	check(moved, "real magnetic utility translates a generated fragment")
	_tick_canvas_state()
	var shifted: Dictionary = room.enemy_props._entity(movable.id)
	var recipe: Dictionary = room.enemy_props.obstacle_recipes[int(shifted.recipe_index)]
	check(shifted.position != movable.position and recipe.collision_rect == shifted.rect and room.obstructions.has(shifted.rect) and not room.obstructions.has(movable.rect), "translated fragment keeps art recipe and real collision congruent")
	check(room.terrain_redraw_count == redraws + 1 and room._terrain_geometry == room.obstructions, "same-count rectangle translation invalidates retained terrain")

	_load("L19")
	var lamp: Dictionary = room.enemy_props.target_for(room.player, "steal_scene_lamp")
	check(bool(lamp.get("valid", false)), "real room supplies a dynamic scene lamp")
	if bool(lamp.get("valid", false)):
		room.player.position = lamp.position
		redraws = room.terrain_redraw_count
		check(room.enemy_props.utility(room.player, "steal_scene_lamp", {"range":200.0, "duration":3.0}).success, "actual lamp utility activates floor darkness")
		_tick_canvas_state()
		check(not room.enemy_props.query_tag("dark_field").is_empty() and room.terrain_redraw_count == redraws, "dynamic floor shading changes without rebuilding static obstacle commands")

	_load("L02")
	var host := Objectives.new()
	room.add_child(host)
	host.configure(room, room.layout, "branch")
	room.player.position = Vector2(2500, 1500)
	redraws = room.terrain_redraw_count
	for frame: int in 160: host.tick(0.05)
	check(host.blockers.has("collapsed_bridge"), "actual escort mechanism closes its warned bridge")
	_tick_canvas_state()
	check(room.terrain_redraw_count == redraws + 1 and room._terrain_geometry == room.obstructions, "real bridge closure invalidates terrain alongside its separate objective overlay")
	redraws = room.terrain_redraw_count
	for frame: int in 100: host.tick(0.05)
	check(not host.blockers.has("collapsed_bridge"), "actual escort mechanism reopens the bridge")
	_tick_canvas_state()
	check(room.terrain_redraw_count == redraws + 1 and room._terrain_geometry == room.obstructions, "real bridge retraction invalidates terrain again")
	host.reset()
	host.free()

	_load("L05")
	var crossed_decoration: bool = false
	for decoration: Dictionary in room.layout.decoration_instances:
		var visual: Rect2 = decoration.visual_rect
		var start := Vector2(visual.position.x - Balance.PLAYER_RADIUS - 6.0, visual.get_center().y)
		var finish := Vector2(visual.end.x + Balance.PLAYER_RADIUS + 6.0, visual.get_center().y)
		if not room.valid_ground(start, Balance.PLAYER_RADIUS) or not room.valid_ground(finish, Balance.PLAYER_RADIUS): continue
		room.player.position = start
		for frame: int in 80:
			var distance: float = room.player.position.distance_to(finish)
			if distance < 0.01: break
			room.player.position = room.move_actor(room.player.position, room.player.position.direction_to(finish) * minf(4.0, distance), Balance.PLAYER_RADIUS)
		if room.player.position.distance_to(finish) < 0.01:
			check(not decoration.collision_rect.has_area() and not room.obstructions.has(decoration.collision_rect), "rendered edge decoration has no physical collider")
			check(room.enemy_props.obstacle_recipes.any(func(item: Dictionary) -> bool: return str(item.id) == str(decoration.id) and item.visual_rect == visual), "traversed decoration is actually present in the obstacle render recipe")
			crossed_decoration = true
			break
	check(crossed_decoration, "real player traverses completely across a decoration's rendered location")
	if is_instance_valid(room.combat_audio): await room.combat_audio.wait_for_cleanup()
	room.free()
	await get_tree().process_frame
	print("TERRAIN_CACHE_TESTS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
