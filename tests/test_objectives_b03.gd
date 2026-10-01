extends Node
## Pure mechanism acceptance on the authored room anchors, through interact/tick.
const Module = preload("res://scripts/world/objectives_b03.gd")
const Layouts = preload("res://scripts/world/room_layouts.gd")
const Generator = preload("res://scripts/world/room_generator.gd")
const HostScript = preload("res://scripts/world/room_objectives.gd")
const RoomScene = preload("res://scenes/room.tscn")
var checks := 0
var failures: Array[String] = []

class PlayerStub:
	extends Node2D
	var dash_remaining := 0.0

class TargetStub:
	extends Node2D
	var owner_host
	var objective_id := ""
	var hp := 32.0
	func take_damage(amount: float) -> void:
		hp -= amount
		owner_host.module.on_target_hit(objective_id, {"damage": amount})
		if hp <= 0:
			owner_host.element(objective_id).destroyed = true
			owner_host.module.on_target_destroyed(objective_id)

class HostStub:
	extends RefCounted
	var room_id := ""
	var layout: Dictionary
	var role := "branch"
	var elapsed := 0.0
	var elements: Dictionary = {}
	var completed_count := 0
	var required_count := 3
	var quality := "full"
	var message := ""
	var ambient_darkness := 0.0
	var module
	var actor := PlayerStub.new()
	var finished := false
	var blockers: Dictionary = {}
	var hazards: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var targets: Array[Node2D] = []
	var enemy_positions: Array[Vector2] = []
	var blocker_calls := 0
	var displacement_count := 0
	func setup(id: String) -> void:
		room_id = id
		layout = Layouts.build(id)
		actor.position = layout.entry
		module = Module.new()
		module.configure(self)
	func cleanup() -> void:
		for target in targets:
			if is_instance_valid(target) and not target.is_queued_for_deletion(): target.free()
		actor.free()
		module.host = null
		module = null
	func point(index: int) -> Vector2: return layout.objective_points[index]
	func add_element(id: String, at: Vector2, label: String, kind: String, asset: String, extra: Dictionary = {}) -> Dictionary:
		var item := {"id": id, "position": safe_point(at), "label": label, "kind": kind, "asset": asset, "done": false, "progress": 0.0, "active": true, "interactive": true, "required": true, "description": ""}
		item.merge(extra, true)
		elements[id] = item
		return item
	func element(id: String) -> Dictionary: return elements.get(id, {})
	func player() -> Node2D: return actor
	func near(at: Vector2, distance: float = 86.0) -> bool: return actor.position.distance_to(at) <= distance
	func set_done(id: String) -> void:
		if bool(elements[id].done): return
		elements[id].done = true
		elements[id].progress = 1.0
		if bool(elements[id].required): completed_count += 1
	func finish(next_quality: String = "full") -> void:
		finished = true
		quality = next_quality
	func safe_point(at: Vector2, radius: float = 26.0) -> Vector2:
		if Layouts.clear_for_actor(layout, at, radius): return at
		for distance in range(32, 577, 32):
			for step in 16:
				var candidate := at + Vector2.RIGHT.rotated(TAU * float(step) / 16.0) * distance
				if Layouts.clear_for_actor(layout, candidate, radius): return candidate
		return layout.entry
	func move_element(id: String, toward: Vector2, speed: float, delta: float) -> bool:
		var current: Vector2 = elements[id].position
		var next := current.move_toward(toward, speed * delta)
		if Layouts.clear_for_actor(layout, next, 24): elements[id].position = next
		return Vector2(elements[id].position).distance_to(toward) <= 12
	func displace(target: Node2D, displacement: Vector2) -> void:
		if target == actor and actor.dash_remaining > 0: return
		displacement_count += 1
		var next := target.position + displacement
		if Layouts.clear_for_actor(layout, next, 18): target.position = next
	func add_hazard(at: Vector2, radius: float, damage: float, delay: float = 1.0, duration: float = .25, extra: Dictionary = {}) -> Dictionary:
		var result := {"position": at, "radius": radius, "damage": damage, "delay": delay, "duration": duration}
		result.merge(extra, true)
		hazards.append(result)
		return result
	func add_target(id: String, at: Vector2, hp: float, asset: String, label: String, extra: Dictionary = {}) -> Dictionary:
		var item := add_element(id, at, label, "target", asset, extra)
		item.interactive = false
		item["attackable"] = true
		var target := TargetStub.new()
		target.owner_host = self
		target.objective_id = id
		target.hp = hp
		target.position = item.position
		item["target_actor"] = target
		targets.append(target)
		return item
	func set_blocker(id: String, rect: Rect2, active: bool = true) -> bool:
		blocker_calls += 1
		if not active:
			remove_blocker(id)
			return true
		if rect.grow(30).has_point(actor.position): return false
		var candidate: Dictionary = layout.duplicate(true)
		for blocker_id in blockers:
			if blocker_id != id: candidate.obstructions.append(blockers[blocker_id])
		candidate.obstructions.append(rect)
		var probes: Array[Vector2] = []
		for probe: Vector2 in candidate.get("topology_probes", []):
			var blocked := false
			for obstruction: Rect2 in candidate.obstructions:
				if obstruction.grow(26).has_point(probe): blocked = true
			if not blocked: probes.append(probe)
		candidate.topology_probes = probes
		if not bool(Layouts.validate_layout(candidate).valid): return false
		blockers[id] = rect
		return true
	func remove_blocker(id: String) -> void: blockers.erase(id)
	func enemies_near(at: Vector2, radius: float) -> Array:
		var result: Array = []
		for enemy in enemy_positions:
			if at.distance_to(enemy) <= radius: result.append(enemy)
		return result
	func event(event_name: String, data: Dictionary = {}) -> void:
		var item := data.duplicate()
		item["name"] = event_name
		events.append(item)
		if event_name == "light_powered": ambient_darkness = float(data.ambient_darkness)
	func advance(seconds: float) -> void:
		var remaining := seconds
		while remaining > .0001:
			var step := minf(.1, remaining)
			elapsed += step
			module.tick(step)
			for item: Dictionary in elements.values():
				var target = item.get("target_actor")
				if is_instance_valid(target): target.position = item.position
			remaining -= step

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_arms()
	_test_lights()
	_test_magnets()
	_test_reactors()
	_test_conveyors()
	_test_cargo()
	_test_generated_bridges()
	await _test_real_host()
	print("B03 objective acceptance: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_generated_bridges() -> void:
	for seed_value in [1, 17, 40917, 987001]:
		var host := HostStub.new()
		host.room_id = "L13"
		host.layout = Generator.generate("L13", seed_value)
		host.actor.position = host.layout.entry
		host.module = Module.new()
		host.module.configure(host)
		check(host.blockers.size() == 2, "L13 generated seed %d keeps C detour with both bridge gates" % seed_value)
		check(Vector2(host.element("bridge_0").position).is_equal_approx(Vector2(1154.05, 708.2)), "L13 blocks authored crossing rather than arbitrary floor")
		host.cleanup()

func _real_interact(controller: Node2D, id: String, offset := Vector2.ZERO) -> bool:
	var item: Dictionary = controller.element(id)
	controller.room.player.position = item.get("interaction_position", item.position) if offset.is_zero_approx() else Vector2(item.position) + offset
	return controller.interact(id, controller.room.player)

func _real_tick(controller: Node2D, seconds: float) -> void:
	for index in ceili(seconds / .05): controller.tick(.05)

func _test_real_host() -> void:
	var game: Node = get_tree().root.get_node("Game")
	check(game.new_profile() and game.start_run(), "production B03 fixture starts isolated run")
	if game.run == null: return
	for id in ["L13", "L14", "L15", "L16", "L17", "L18"]:
		var room: Node2D = RoomScene.instantiate()
		room.layout_id = id
		room.run_seed = 40917
		room.spawn_enabled = false
		room.process_mode = Node.PROCESS_MODE_DISABLED
		get_tree().root.add_child(room)
		await get_tree().process_frame
		for enemy in room.enemies.get_children(): enemy.free()
		var controller: Node2D = room.get("objectives")
		if not is_instance_valid(controller):
			controller = HostScript.new()
			room.add_child(controller)
		controller.configure(room, room.layout, "branch")
		check(controller.module != null, id + " real host loads production module")
		check(controller.navigation_target().has("position"), id + " real host exposes actual task navigation")
		match id:
			"L13":
				check(controller.blockers.size() == 2, "L13 production generated geometry accepts both bridge gates")
				for index in 2:
					check(_real_interact(controller, "arm_%d" % index), "L13 production arms accept interaction")
					_real_tick(controller, 9.5)
				check(controller.blockers.is_empty(), "L13 production calibrated bridges physically reopen")
			"L14":
				for index in [2, 0, 1]:
					check(_real_interact(controller, "battery_%d" % index), "L14 production battery pickup")
					check(_real_interact(controller, "lamp_%d" % index), "L14 production lamp receives battery")
				check(is_zero_approx(controller.ambient_darkness), "L14 production host consumes lamp darkness event")
			"L15":
				for frame in 600:
					for index in 2:
						var cart: Dictionary = controller.element("cart_%d" % index)
						if not bool(cart.done) and int(cart.polarity) < 0:
							_real_interact(controller, "magnet_%d" % index)
					controller.tick(.05)
					if controller.is_complete(): break
			"L16":
				for index in 3:
					check(_real_interact(controller, "valve_%d" % index), "L16 production valve interaction")
					_real_tick(controller, 6)
			"L17":
				var initial: Vector2 = controller.element("part_0").position
				_real_tick(controller, 2)
				check(Vector2(controller.element("part_0").position).distance_to(initial) > 30, "L17 production navigation moves actual cargo target")
				check(controller.blockers.size() == 4, "L17 production accepts four rotation blockers")
				check(_real_interact(controller, "cover_0"), "L17 production rotates physical shield from clear flank")
				check(_real_interact(controller, "cover_0"), "L17 production rotation is reversible from same safe control")
				for index in 3:
					check(_real_interact(controller, "part_%d" % index), "L17 production target can be carried")
					check(_real_interact(controller, "assembly_table"), "L17 production component delivery")
			"L18":
				var flying: Dictionary = controller.element(str(controller.module._cargo_id))
				check(flying.target_actor.is_alive(), "L18 production cargo has real combat health")
				check(flying.target_actor.take_damage(40, &"primary", Vector2.ZERO, {"equipment_eligible": false}), "L18 ordinary attack really destroys cargo")
				check(str(controller.module._cargo_phase) == "falling", "L18 real death callback starts warned landing")
				for index in 3:
					room.player.position = room.layout.entry
					_real_tick(controller, 16)
					var landing: int = controller.module._cargo_landing
					check(landing >= 0 and _real_interact(controller, "landing_%d" % landing), "L18 production landing safe and recoverable")
				check(controller.blockers.size() == 3, "L18 production leaves three usable cover blockers")
		check(controller.is_complete(), id + " production host finishes by actual interaction and time")
		check(controller.completed_count == (2 if id in ["L13", "L15"] else 3), id + " production required progress matches only actual goals")
		room.free()
		await get_tree().process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func fixture(id: String) -> HostStub:
	var host := HostStub.new()
	host.setup(id)
	check(not host.module.blocks_dash(), id + " never locks class mobility")
	check(not host.module.status_text().is_empty(), id + " has readable instruction")
	check(host.module.navigation_target().has("position"), id + " offers actual current task navigation")
	for item: Dictionary in host.elements.values():
		check(Layouts.clear_for_actor(host.layout, item.position, 24), id + " safe authored placement " + str(item.id))
	check(not host.finished and host.completed_count == 0, id + " starts incomplete")
	return host

func interact(host: HostStub, id: String, offset: Vector2 = Vector2(0, 68)) -> bool:
	host.actor.position = host.element(id).position + offset
	return host.module.interact(id, host.actor)

func count_events(host: HostStub, event_name: String) -> int:
	var count := 0
	for item in host.events:
		if str(item.name) == event_name: count += 1
	return count

func _test_arms() -> void:
	var host := fixture("L13")
	check(host.blockers.size() == 2, "L13 both short couplers are valid real blockers")
	check(interact(host, "arm_0"), "L13 starts channel through E")
	host.advance(3.3)
	check(int(host.element("arm_0").steps) == 1, "L13 first physical calibration step saved")
	host.advance(1.0)
	host.enemy_positions.append(host.element("arm_0").position)
	host.advance(.1)
	check(int(host.element("arm_0").steps) == 1 and float(host.element("arm_0").partial) < .2, "L13 interruption resets only active step")
	host.advance(4.0)
	check(bool(host.element("arm_0").offline), "L13 repeated coupler damage enters repairable shutdown")
	host.enemy_positions.clear()
	check(interact(host, "arm_0"), "L13 repair via E")
	host.advance(2.2)
	check(not bool(host.element("arm_0").offline), "L13 coupler repair succeeds")
	check(interact(host, "arm_0"), "L13 resume preserves previous steps")
	host.advance(6.5)
	check(host.completed_count == 1 and not host.blockers.has("arm_gate_0"), "L13 calibrated arm opens physical gate")
	check(interact(host, "arm_1"), "L13 second arm independent")
	host.actor.position = host.layout.entry
	host.advance(10)
	check(host.completed_count == 1, "L13 unattended arm does not auto complete")
	host.actor.position = host.element("arm_1").position + Vector2(0, 65)
	host.advance(9.5)
	check(host.finished and host.completed_count == 2, "L13 both arms complete through real time")
	check(count_events(host, "arm_calibrated") == 2, "L13 two bridge events")
	host.cleanup()

func _test_lights() -> void:
	var host := fixture("L14")
	check(not interact(host, "lamp_0"), "L14 cannot light without physical battery")
	check(host.ambient_darkness > 0, "L14 starts with actual background setting")
	var order := [2, 0, 1]
	for index in order:
		check(interact(host, "battery_%d" % index), "L14 picks battery %d" % index)
		check(str(host.module.navigation_target().title).begins_with("应急灯"), "L14 carrying battery points to lamp")
		check(not interact(host, "battery_%d" % ((index + 1) % 3)), "L14 carry capacity one")
		host.actor.position = host.element("lamp_%d" % index).position + Vector2(0, 68)
		host.advance(.2)
		check(Vector2(host.element("battery_%d" % index).position).distance_to(host.actor.position) < 40, "L14 carried battery follows actor")
		check(interact(host, "lamp_%d" % index), "L14 installs carried battery")
		host.advance(3.5)
	check(host.finished and host.completed_count == 3, "L14 completion by three transported batteries")
	var actual: Array[int] = []
	for item in host.events:
		if str(item.name) == "light_powered":
			actual.append(int(item.index))
			check(Vector2(item.encounter_direction).length() > .9, "L14 encounter direction event real vector")
	check(actual == [2, 0, 1], "L14 preserves player selected lamp order")
	check(is_zero_approx(host.ambient_darkness), "L14 all lamps restore contrast")
	check(not host.hazards.is_empty(), "L14 powered cargo rails activate timed hazard")
	for hazard in host.hazards: check(float(hazard.delay) >= .8, "L14 rail fully warned")
	host.cleanup()

func _test_magnets() -> void:
	var host := fixture("L15")
	var original: Vector2 = host.element("cart_0").position
	host.advance(3.1)
	check(not interact(host, "magnet_0"), "L15 locked arrows cannot change mid-warning")
	host.actor.position = original + Vector2(0, 70)
	host.actor.dash_remaining = 1.0
	var dash_origin := host.actor.position
	host.advance(1.0)
	check(host.actor.position == dash_origin, "L15 magnetic pulse preserves started dash")
	host.actor.dash_remaining = 0
	host.advance(1.0)
	check(Vector2(host.element("cart_0").position).distance_to(host.point(0)) < original.distance_to(host.point(0)), "L15 attraction physically moves cart")
	var closer: Vector2 = host.element("cart_0").position
	host.advance(4.0)
	check(Vector2(host.element("cart_0").position).distance_to(host.point(0)) > closer.distance_to(host.point(0)), "L15 alternating repulsion physically pushes cart back")
	for step in 160:
		for index in 2:
			var cart: Dictionary = host.element("cart_%d" % index)
			if not bool(cart.done) and int(cart.polarity) < 0:
				interact(host, "magnet_%d" % index)
		host.advance(.25)
		if host.finished: break
	check(host.finished and host.completed_count == 2, "L15 two carts dock by actual pulse movement")
	check(count_events(host, "magnet_pulse") >= 6, "L15 completion includes multiple scheduled pulses")
	check(count_events(host, "cart_docked") == 2, "L15 real docking events")
	for hazard in host.hazards: check(float(hazard.delay) >= .8, "L15 electric board warned")
	host.cleanup()

func _test_reactors() -> void:
	var host := fixture("L16")
	check(not interact(host, "valve_1"), "L16 sequential reactor order enforced")
	host.advance(11)
	check(bool(host.element("reactor_0").offline), "L16 real elapsed heat causes shutdown")
	check(not host.finished, "L16 overheat does not falsely finish")
	check(interact(host, "reactor_0"), "L16 starts repair")
	host.advance(2.2)
	check(not bool(host.element("reactor_0").offline), "L16 overheat repair restores operation")
	for index in 3:
		if bool(host.element("reactor_%d" % index).offline):
			check(interact(host, "reactor_%d" % index), "L16 later reactor repair")
			host.advance(2.2)
		var before: float = host.element("reactor_%d" % index).temperature
		check(interact(host, "valve_%d" % index), "L16 opens corresponding valve")
		host.advance(1)
		check(float(host.element("reactor_%d" % index).temperature) < before, "L16 valve actually cools its reactor")
		host.advance(6)
		check(host.completed_count == index + 1, "L16 cooling and stability channel completes reactor")
	check(host.finished and count_events(host, "reactor_stabilized") == 3, "L16 all stabilized through time and valves")
	check(host.quality == "repaired", "L16 repair outcome retained")
	check(not host.hazards.is_empty(), "L16 overheating emits steam warning")
	host.cleanup()

func _test_conveyors() -> void:
	var host := fixture("L17")
	check(host.blockers.size() == 4, "L17 four rotating covers preserve required authored paths")
	var original: Vector2 = host.element("part_0").position
	var calls := host.blocker_calls
	host.advance(2)
	check(Vector2(host.element("part_0").position).distance_to(original) > 80, "L17 real part moves along conveyor")
	check(host.blocker_calls == calls, "L17 moving parts do not rebuild navigation per frame")
	check(host.targets.size() == 3, "L17 moving cargo are actual hittable targets")
	check(Vector2(host.element("part_0").target_actor.position).is_equal_approx(host.element("part_0").position), "L17 hitbox follows goods")
	var cover: Dictionary = host.element("cover_0")
	var before: Rect2 = host.blockers.cover_0
	host.actor.position = cover.interaction_position
	check(host.module.interact("cover_0", host.actor), "L17 rotate cover from safe flank")
	check(host.blockers.cover_0 != before and bool(cover.vertical), "L17 cover rotates real obstruction")
	check(not interact(host, "cover_0", Vector2.ZERO), "L17 occupied cover cannot rotate into player")
	host.element("part_1").target_actor.take_damage(40)
	check(bool(host.element("part_1").broken) and not bool(host.element("part_1").destroyed), "L17 broken cargo remains recoverable")
	for index in 3:
		check(interact(host, "part_%d" % index), "L17 picks conveyor part")
		check(str(host.module.navigation_target().title).contains("装配台"), "L17 carrying part points to delivery table")
		check(host.completed_count == index, "L17 pickup alone does not count delivery")
		host.actor.position = host.element("assembly_table").position + Vector2(0, 68)
		host.advance(.2)
		check(interact(host, "assembly_table"), "L17 delivers at assembly table")
	check(host.finished and host.completed_count == 3, "L17 three physical deliveries finish")
	check(host.quality == "repaired", "L17 damaged set provides reduced completion outcome")
	host.cleanup()

func _test_cargo() -> void:
	var host := fixture("L18")
	check(host.targets.size() == 1, "L18 aircraft is a real damage target")
	check(interact(host, "crane_console"), "L18 selects next interception slot")
	check(str(host.element("crane_console").phase).contains("2"), "L18 console changes intended lane")
	check(not interact(host, "landing_1"), "L18 cannot collect before landing")
	host.actor.position = host.layout.entry
	host.advance(6.4)
	check(not host.hazards.is_empty() and not bool(host.element("landing_1").captured), "L18 crane crossing starts warning before fall")
	check(float(host.hazards[0].delay) >= 1.2, "L18 landing warning meets area window")
	host.actor.position = host.element("landing_1").position
	host.advance(2)
	check(not bool(host.element("landing_1").captured), "L18 crate waits while hero occupies landing")
	host.actor.position = host.element("landing_1").position + Vector2(0, 80)
	host.advance(.2)
	check(bool(host.element("landing_1").captured) and host.blockers.has("cargo_cover_1"), "L18 falling cargo becomes actual safe cover")
	check(str(host.module.navigation_target().title).contains("回收"), "L18 landed crate points to approachable recovery spot")
	check(interact(host, "landing_1", Vector2(0, 80)), "L18 recovers landed cargo")
	check(host.completed_count == 1 and host.targets.size() == 2, "L18 recovery spawns next loop")
	# Ordinary damage can intercept early; no class skill or exact timing needed.
	host.element(str(host.module._cargo_id)).target_actor.take_damage(40)
	check(str(host.module._cargo_phase) == "falling", "L18 ordinary attack shoots down next aircraft")
	host.actor.position = host.layout.entry
	host.advance(1.5)
	var shot_index: int = host.module._cargo_landing
	check(interact(host, "landing_%d" % shot_index, Vector2(0, 80)), "L18 shot cargo recoverable after warning")
	host.actor.position = host.layout.entry
	host.advance(16)
	var final_index: int = host.module._cargo_landing
	check(interact(host, "landing_%d" % final_index, Vector2(0, 80)), "L18 persistent console choice captures final cargo")
	check(host.finished and host.completed_count == 3, "L18 three actual interceptions and recoveries complete")
	check(host.blockers.size() == 3, "L18 all recovered cargo retain cover")
	check(count_events(host, "cargo_intercepted") == 3, "L18 all landing sequences explicitly recorded")
	host.cleanup()
