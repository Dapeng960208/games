extends Node
## Actual room collision, real objective host and real attackable task actors.
const RoomScene = preload("res://scenes/room.tscn")
const Objectives = preload("res://scripts/world/room_objectives.gd")
const Enemy = preload("res://scripts/combat/enemy.gd")
var room: MineRoom
var objectives: Node2D
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("B04 OBJECTIVE FAIL: " + description)

func fixture(id: String) -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hp = Game.run.max_hp
	room = RoomScene.instantiate()
	room.layout_id = id
	room.run_seed = 91705
	room.spawn_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	for actor in room.enemies.get_children():
		actor.free()
	objectives = room.get("objectives")
	if not is_instance_valid(objectives):
		objectives = Objectives.new()
		room.add_child(objectives)
	objectives.configure(room, room.layout, "branch")
	check(objectives.module != null and not objectives.is_complete(), id + " loads actual module and does not finish from enemy removal")
	check(not objectives.blocks_dash(), id + " preserves all hero movement skills")
	check(objectives.module.navigation_target().has("position"), id + " exposes next meaningful action as navigation target")
	for item: Dictionary in objectives.elements.values():
		if not str(item.asset).is_empty():
			check(objectives.textures.has(item.asset), id + " uses imported original prop " + item.asset)

func interact(id: String) -> bool:
	if not objectives.elements.has(id):
		check(false, "missing interaction " + id)
		return false
	room.player.position = objectives.element(id).position
	return objectives.interact(id, room.player)

func tick(seconds: float) -> void:
	for frame: int in ceili(seconds / .05):
		objectives.tick(.05)

func count_event(event_name: String) -> int:
	var result: int = 0
	for event: Dictionary in objectives.events:
		if event.name == event_name:
			result += 1
	return result

func _run() -> void:
	check(Game.new_profile() and Game.start_run(), "isolated game run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_locks()
	_test_escort()
	_test_mirrors()
	_test_weaving()
	_test_lamps()
	_test_discs()
	if is_instance_valid(room.combat_audio):
		await room.combat_audio.wait_for_cleanup()
	room.free()
	print("OBJECTIVES_B04_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_locks() -> void:
	fixture("L19")
	check(interact("lock_2"), "player can choose third lock first")
	tick(.7)
	var progress: float = objectives.element("lock_2").progress
	room.player.position = room.layout.entry
	tick(.5)
	check(is_equal_approx(progress, objectives.element("lock_2").progress), "leaving retains dismantle work and cannot finish at distance")
	check(interact("lock_2"), "partly released lock can resume")
	tick(1.2)
	check(objectives.element("lock_2").done and objectives.module.order == [2], "actual hold completes chosen lock and changes wave shape")
	for index: int in [0, 1]:
		check(interact("lock_" + str(index)), "next physical lock starts")
		tick(1.85)
		check(objectives.hazards.size() <= 1, "only one resonance wave can occupy choke at once")
	check(objectives.is_complete() and objectives.module.order == [2, 0, 1], "three held locks complete in player-chosen order")
	fixture("L19")
	room.player.position = objectives.element("lock_0").position
	tick(2.05)
	check(objectives.hazards.size() == 1 and objectives.hazards[0].shape == "ring" and objectives.hazards[0].delay > .8, "unreleased lock creates a warned hollow ring")
	var before: float = objectives.module.clock
	get_tree().paused = true
	objectives.tick(1)
	get_tree().paused = false
	check(is_equal_approx(before, objectives.module.clock), "pausing freezes objective timers")

func _test_escort() -> void:
	fixture("L20")
	var start: Vector2 = objectives.element("escort_light").position
	tick(1)
	check(start.is_equal_approx(objectives.element("escort_light").position), "light waits for actual route interaction")
	check(interact("route_0") and interact("route_2") and objectives.module.route_index == 2, "latest route interaction selects actual destination")
	room.player.position = room.layout.exit
	tick(1)
	check(start.is_equal_approx(objectives.element("escort_light").position), "escort stops outside proximity")
	room.player.position = room.layout.entry
	room.elapsed = 1.0
	room.record_player_sound()
	objectives.on_player_sound(room.player.position, {"damage_source":"primary"})
	tick(.05)
	check(count_event("echo_lure") == 1 and objectives.element("attack_echo").active, "original attack makes one marker even with callback and polling")
	check(room.enemy_utility_target(null, "last_player_sound") == room.player.position, "M28 reads actual attack sound position")
	objectives.on_player_sound(room.player.position + Vector2(100, 0), {"damage_source":"burn","dot":true})
	check(count_event("echo_lure") == 1, "damage over time does not generate another lure")
	for frame: int in range(16000):
		if objectives.module.route_index < 0:
			interact("route_" + str(objectives.module.route_step % 3))
		room.player.position = objectives.element("escort_light").position
		objectives.tick(.1)
		if objectives.is_complete():
			break
	check(objectives.is_complete() and objectives.module.route_step == 4, "light navigates four chosen segments through real street collision")
	check(room.valid_ground(objectives.element("escort_light").position, 24), "escorted light remains outside walls")

func _test_mirrors() -> void:
	fixture("L21")
	tick(2)
	check(not objectives.is_complete(), "unaligned mirrors cannot auto-complete")
	for index: int in [0, 1]:
		check(interact("mirror_" + str(index)), "real rotation aligns local scene beam")
		tick(1.7)
		check(objectives.element("inscription_" + str(index)).done, "beam physically reaches inscription " + str(index))
	check(objectives.is_complete(), "both sustained scene beams calibrate mirror pool")

func _test_weaving() -> void:
	fixture("L22")
	check(objectives.targets.size() == 3 and objectives.blockers.size() == 3, "three actual cuttable line targets and collision strips exist: " + str(objectives.targets.keys()))
	check(interact("sound_shape_0") and interact("weave_column_0"), "matching shape installs physically")
	check(interact("sound_shape_1") and interact("weave_column_2"), "wrong shape produces recoverable action")
	check(objectives.completed_count == 1 and objectives.module.selected_shape == 1 and objectives.hazards.size() == 1, "wrong shape retains all progress and carried item")
	check(objectives.hazards[0].delay >= 1.0, "wrong pattern sweep warns before any damage")
	if objectives.targets.has("weave_knot_1"):
		var target: MineEnemy = objectives.targets["weave_knot_1"]
		check(target.take_damage(35.0, &"physical", Vector2.RIGHT, {"damage_source":"primary","original_basic":true}), "ordinary player attack damages real target actor")
		check(not objectives.blockers.has("weave_line_1") and count_event("weave_line_cut") == 1, "destroy callback removes actual blocking collision")
	check(interact("weave_column_1") and interact("sound_shape_2") and interact("weave_column_2"), "remaining shapes install without reset")
	check(objectives.is_complete() and objectives.blockers.is_empty(), "finished weave retracts all blocking lines")

func _test_lamps() -> void:
	fixture("L23")
	room.player.position = objectives.module.bridges[0]
	tick(8.4)
	check(objectives.module.warned_bridge == 0 and objectives.module.closed_bridge == -1, "dark bridge warns for 2.2 seconds and waits while player occupies it")
	room.player.position = room.layout.entry
	tick(.1)
	check(objectives.blockers.size() == 1, "vacated dark bridge actually retracts and leaves two crossings open")
	var bridge_valid: Dictionary = RoomLayouts.validate_layout(_current_layout())
	check(bool(bridge_valid.valid), "bridge state preserves routes to exit and all task anchors: " + str(bridge_valid))
	check(interact("lamp_0"), "first movable lamp can be picked up")
	check(objectives.module.navigation_target().position == objectives.element("lamp_receiver").position, "carried lamp navigation points to receiver rather than itself")
	room.player.position = room.layout.entry + Vector2(20, 0)
	tick(.1)
	check(Vector2(objectives.element("lamp_0").position).is_equal_approx(room.player.position), "carried lamp follows physical actor")
	check(interact("lamp_0"), "carried lamp can be dropped safely")
	var entity: Dictionary = objectives.module._lamp_entity(0)
	entity.position = Vector2(-100, -100)
	tick(.1)
	check(room.valid_ground(objectives.element("lamp_0").position, 14) and count_event("lamp_recovered") == 1, "lost lamp returns to a reachable actual stand")
	var thief = Enemy.new()
	thief.room = room
	thief.position = objectives.element("lamp_1").position
	thief.configure({"enemy_id":"M35","max_hp":50}, {"static_actor":true})
	room.enemies.add_child(thief)
	var stolen: Dictionary = room.enemy_props.utility(thief, "steal_scene_lamp", {"range":30.0,"duration":10.0})
	check(bool(stolen.get("success", false)), "production M35 utility steals registered objective lamp")
	tick(.1)
	check(int(objectives.module._lamp_entity(1).get("taken_by", 0)) == thief.get_instance_id(), "M35 owns actual lamp entity")
	room.enemy_props.return_stolen(thief)
	tick(.1)
	check(int(objectives.module._lamp_entity(1).get("taken_by", 0)) == 0 and room.valid_ground(objectives.element("lamp_1").position, 14), "returned stolen lamp recovers to safe stand")
	for index: int in [0, 1]:
		check(interact("lamp_" + str(index)) and interact("lamp_receiver"), "lamp reaches real exit receiver")
		tick(.1)
	check(objectives.completed_count == 2 and not objectives.is_complete(), "two exit beams offer explicit reduced-reward exit")
	check(interact("lamp_receiver") and objectives.is_complete() and objectives.quality == "reduced", "two-lamp exit is an actual choice")
	fixture("L23")
	for index: int in range(3):
		check(interact("lamp_" + str(index)) and interact("lamp_receiver"), "preserve lamp " + str(index))
		tick(.1)
	check(objectives.is_complete() and objectives.quality == "full", "three delivered lamps finish with full reward quality")

func _current_layout() -> Dictionary:
	var current: Dictionary = room.layout.duplicate(true)
	current.obstructions = room.obstructions
	# A temporarily retracted optional bridge is intentionally unavailable;
	# entry, exit, every objective and the two open bridge probes must remain.
	var open_probes: Array[Vector2] = []
	for probe: Vector2 in current.get("topology_probes", []):
		if RoomLayouts.clear_for_actor(current, probe):
			open_probes.append(probe)
	current.topology_probes = open_probes
	return current

func _test_discs() -> void:
	fixture("L24")
	check(objectives.element("sequence_record").always_label and objectives.status().text.contains("①圆 → ③三角 → ⑤菱"), "required sequence stays visible in world record and objective status")
	room.player.position = objectives.element("echo_disc_0").position
	tick(.1)
	room.player.position = objectives.element("echo_disc_1").position
	tick(.1)
	check(objectives.module.sequence_progress == 1 and not objectives.is_complete(), "wrong actual pressure disc preserves progress")
	room.player.position = objectives.element("echo_disc_2").position
	tick(.1)
	check(objectives.module.sequence_progress == 2, "next correct disc accepts without reset")
	var old_echo: bool = false
	for hazard: Dictionary in objectives.hazards:
		if Vector2(hazard.position).is_equal_approx(objectives.element("echo_disc_0").position) and hazard.delay > 1.0:
			old_echo = true
	check(old_echo, "correct step warns an echo at previous actual disc position")
	room.player.position = objectives.element("echo_disc_4").position
	tick(.1)
	check(objectives.is_complete() and objectives.completed_count == 3, "three pressure entries complete calibration")
