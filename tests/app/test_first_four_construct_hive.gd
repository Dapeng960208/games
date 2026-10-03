extends SceneTree
## Focused lifetime, charge/counter and bounded hatch acceptance for B01/B02.
const Module = preload("res://scripts/levels/shared/first_four_construct_hive.gd")
var checks: int = 0
var failures: Array[String] = []

class ActorStub:
	extends Node2D
	var actor_kind: String = "enemy"
	var enemy_id: String = "M01"
	var rank: String = "normal"
	var navigation_radius: float = 24.0
	var alive: bool = true
	func is_alive() -> bool:
		return alive

class RoomStub:
	extends Node2D
	var player: Node2D = Node2D.new()
	var enemies: Node2D = Node2D.new()
	var allow_ground: bool = true
	var allow_route: bool = true
	var allow_allocation: bool = true
	var spawn_calls: Array[Dictionary] = []
	func _init() -> void:
		add_child(player)
		add_child(enemies)
		player.position = Vector2(1500, 1500)
	func valid_ground(_at: Vector2, _radius: float) -> bool:
		return allow_ground
	func blocked_fraction(_from: Vector2, _to: Vector2, _radius: float) -> float:
		return 1.0 if allow_route else 0.0
	func spawn_enemy(at: Vector2, id: String, level: int, options: Dictionary) -> Node2D:
		spawn_calls.append({"position": at, "id": id, "level": level, "options": options.duplicate()})
		if not allow_allocation:
			return null
		var actor: ActorStub = ActorStub.new()
		actor.enemy_id = id
		actor.position = at
		enemies.add_child(actor)
		return actor

class HostStub:
	extends RefCounted
	var room: RoomStub = RoomStub.new()
	var elements: Dictionary = {}
	var target_health: Dictionary = {}
	var required_count: int = 0
	var completed_count: int = 0
	var finished: bool = false
	var events: Array[Dictionary] = []
	var counters: Array[Dictionary] = []
	var module
	func setup(biome: String, variant: int, count: int) -> void:
		module = Module.new()
		module.configure(self, biome, variant, count)
	func cleanup() -> void:
		if is_instance_valid(room):
			room.free()
		module.host = null
		module = null
	func player() -> Node2D:
		return room.player
	func combat_objective_point(index: int, _count: int) -> Vector2:
		return Vector2(300 + index * 550, 400)
	func combat_objective_label(_index: int, fallback: String) -> String:
		return fallback
	func combat_objective_asset(_index: int, fallback: String) -> String:
		return fallback
	func interaction_key() -> String:
		return "E"
	func safe_point(at: Vector2, _radius: float = 26.0) -> Vector2:
		return at
	func add_element(id: String, at: Vector2, label: String, kind: String, asset: String, extra: Dictionary = {}) -> Dictionary:
		var item: Dictionary = {"id": id, "position": at, "label": label, "kind": kind, "asset": asset, "done": false, "progress": 0.0, "active": true, "interactive": true, "required": true}
		item.merge(extra, true)
		elements[id] = item
		return item
	func add_target(id: String, at: Vector2, hp: float, asset: String, label: String, extra: Dictionary = {}) -> Dictionary:
		var item: Dictionary = add_element(id, at, label, "target", asset, extra)
		item["interactive"] = false
		item["attackable"] = true
		target_health[id] = hp
		return item
	func element(id: String) -> Dictionary:
		return elements.get(id, {})
	func near(at: Vector2, distance: float) -> bool:
		return player().position.distance_to(at) <= distance
	func set_done(id: String) -> void:
		if bool(elements[id].done):
			return
		elements[id].done = true
		elements[id].progress = 1.0
		completed_count += 1
	func finish() -> void:
		finished = true
	func event(name: String, data: Dictionary = {}) -> void:
		var recorded: Dictionary = data.duplicate()
		recorded["name"] = name
		events.append(recorded)
	func combat_actors() -> Array:
		var result: Array = []
		for actor: ActorStub in room.enemies.get_children():
			if actor.is_alive() and not actor.is_queued_for_deletion() and actor.actor_kind != "objective":
				result.append(actor)
		return result
	func combat_counter_effect(actor: Node2D, kind: String, duration: float = 6.0) -> void:
		counters.append({"id": actor.enemy_id, "kind": kind, "duration": duration})
	func add_enemy(id: String, at: Vector2, kind: String = "enemy", rank: String = "normal") -> ActorStub:
		var actor: ActorStub = ActorStub.new()
		actor.enemy_id = id
		actor.position = at
		actor.actor_kind = kind
		actor.rank = rank
		room.enemies.add_child(actor)
		return actor
	func event_count(name: String) -> int:
		var count: int = 0
		for event: Dictionary in events:
			if str(event.name) == name:
				count += 1
		return count
	func total_hatched() -> int:
		var count: int = 0
		for item: Dictionary in elements.values():
			count += int(item.get("spawned_total", 0))
		return count
	func retire_brood(amount: int = 100) -> void:
		var retired: int = 0
		for actor: ActorStub in room.enemies.get_children():
			if bool(actor.get_meta(Module.BROOD_META, false)) and actor.alive and retired < amount:
				actor.alive = false
				retired += 1

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	_test_variants()
	_test_conduits()
	_test_brood_budget()
	_test_brood_failures_and_lifetime()
	_test_nest_destruction()
	print("FirstFour construct/hive: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_variants() -> void:
	for variant: int in 6:
		var count: int = 3 if variant in [1, 3, 5] else 2
		for biome: String in ["B01", "B02"]:
			var host: HostStub = HostStub.new()
			host.setup(biome, variant, count)
			check(host.required_count == count and host.elements.size() == count, "%s variant %d has the requested objective count" % [biome, variant])
			check(not host.module.blocks_dash() and host.module.encounter_directive(0).is_empty(), "Combat objectives preserve dash and encounter composition")
			if biome == "B02":
				check(is_equal_approx(float(host.target_health.brood_nest_0), 80.0 + variant * 10.0), "Nest health follows its variant")
				check(not bool(host.element("brood_nest_0").interactive) and bool(host.element("brood_nest_0").attackable), "Nests are attackable and never E interactables")
			host.cleanup()

func _test_conduits() -> void:
	var host: HostStub = HostStub.new()
	host.setup("B01", 0, 2)
	var item: Dictionary = host.element("solar_conduit_0")
	host.add_enemy("M01", item.position + Vector2(50, 0))
	host.add_enemy("M02", item.position + Vector2(70, 0), "enemy", "elite")
	host.add_enemy("M03", item.position + Vector2(500, 0))
	host.add_enemy("M10", item.position + Vector2(60, 0))
	host.add_enemy("BO01", item.position + Vector2(70, 0), "boss")
	host.player().position = item.position
	host.module.tick(2.0)
	check(float(item.progress) == 0.0, "Conduits never charge before E")
	check(host.module.interact("solar_conduit_0", host.player()), "E starts conduit charging")
	host.module.tick(0.7)
	check(is_equal_approx(float(item.progress), 0.7 / 1.6), "Charging advances only by elapsed near time")
	host.player().position += Vector2(120, 0)
	host.module.tick(8.0)
	check(is_equal_approx(float(item.progress), 0.7 / 1.6) and not bool(item.done), "Leaving retains progress without charging")
	host.player().position = item.position
	host.module.tick(0.9)
	check(bool(item.done) and host.completed_count == 1 and not host.finished, "Returning completes the 1.6-second charge and leaves other objectives required")
	check(host.counters.size() == 2 and host.counters[0].kind == "solar_conduit" and host.counters[0].duration == 6.0, "Only nearby ordinary/elite same-biome constructs receive the 6-second counter")
	var pulses: int = host.event_count("solar_conduit_pulse")
	host.module.tick(4.9)
	check(host.event_count("solar_conduit_pulse") == pulses, "Charged conduit pulse cannot repeat before five seconds")
	host.module.tick(0.1)
	check(host.event_count("solar_conduit_pulse") == pulses + 1, "Charged conduit emits its next pulse at five seconds")
	host.player().position = host.element("solar_conduit_1").position
	check(host.module.interact("solar_conduit_1", host.player()), "Remaining conduit can be activated independently")
	host.module.tick(1.6)
	check(host.finished and host.completed_count == 2 and host.combat_actors().size() == 5, "Objective completion preserves living combat actors")
	pulses = host.event_count("solar_conduit_pulse")
	host.module.tick(5.0)
	check(host.event_count("solar_conduit_pulse") > pulses, "Charged pillars keep countering during remaining combat")
	check(host.module.status_text().contains("2/2") and host.module.status_text_en().contains("2/2"), "Both locales report current completion counts")
	host.cleanup()

func _test_brood_budget() -> void:
	var host: HostStub = HostStub.new()
	host.setup("B02", 1, 3)
	host.module.tick(7.99)
	check(host.room.spawn_calls.is_empty(), "Nests wait eight seconds before their first add")
	host.module.tick(0.01)
	check(host.total_hatched() == 3 and host.module._live_brood_count() == 3, "Each of three nests hatches only one add per interval")
	for spawn: Dictionary in host.room.spawn_calls:
		check(str(spawn.id) == "M10" and not bool(spawn.options.reward_enabled) and int(spawn.options.zone_index) == -1, "Brood adds use a real small B02 prototype without rewards or zone slots")
	host.module.tick(7.99)
	check(host.total_hatched() == 3, "Nests cannot hatch a second add early")
	host.module.tick(0.01)
	check(host.total_hatched() == 4 and host.module._live_brood_count() == 4, "Concurrent objective adds are capped at four across the room")
	host.retire_brood(1)
	host.module.tick(1.0)
	check(host.total_hatched() == 5 and host.module._live_brood_count() == 4, "A dead add releases the live cap without retaining an enemy reference")
	host.retire_brood()
	host.module.tick(1.0)
	check(host.total_hatched() == 6, "Deferred nests hatch after the room cap clears")
	host.module.tick(60.0)
	check(host.total_hatched() == 6, "Every nest permanently stops after two successful adds")
	host.cleanup()

func _test_brood_failures_and_lifetime() -> void:
	var host: HostStub = HostStub.new()
	host.setup("B02", 0, 2)
	host.room.allow_ground = false
	host.module.tick(8.0)
	check(host.room.spawn_calls.is_empty() and host.total_hatched() == 0, "Blocked ground consumes no allocation or hatch budget")
	host.room.allow_ground = true
	host.room.allow_route = false
	host.module.tick(1.0)
	check(host.room.spawn_calls.is_empty() and host.total_hatched() == 0, "A valid but unreachable patch of ground cannot hatch an add")
	host.room.allow_route = true
	host.room.allow_allocation = false
	host.module.tick(1.0)
	check(host.room.spawn_calls.size() == 2 and host.total_hatched() == 0, "Allocation failures consume no successful hatch budget")
	host.module.tick(0.5)
	check(host.room.spawn_calls.size() == 2, "Failed allocation retries are delayed")
	host.room.allow_allocation = true
	host.module.tick(0.5)
	check(host.total_hatched() == 2, "Successful retry counts only the real spawned actors")
	root.add_child(host.room)
	paused = true
	var before: float = host.module.clock
	host.module.tick(20.0)
	check(host.module.clock == before and host.total_hatched() == 2, "Paused rooms advance neither hatch clocks nor adds")
	paused = false
	host.finished = true
	host.module.tick(20.0)
	check(host.total_hatched() == 2, "Finished objective hosts never produce more brood adds")
	host.room.free()
	host.module.tick(20.0)
	check(host.total_hatched() == 2, "A retired room cannot produce adds or dereference freed actors")
	host.cleanup()

func _test_nest_destruction() -> void:
	var host: HostStub = HostStub.new()
	host.setup("B02", 0, 2)
	var item: Dictionary = host.element("brood_nest_0")
	host.add_enemy("M10", item.position + Vector2(80, 0))
	host.add_enemy("M11", item.position + Vector2(600, 0))
	host.add_enemy("M01", item.position + Vector2(80, 0))
	host.player().position = item.position
	check(not host.module.interact("brood_nest_0", host.player()), "E cannot bypass brood nest attacks")
	host.module.on_target_destroyed("brood_nest_0")
	check(bool(item.done) and bool(item.destroyed) and host.completed_count == 1, "Real nest destruction marks its objective complete")
	check(host.counters.size() == 1 and host.counters[0].kind == "brood_egg" and host.counters[0].duration == 6.0, "Nest destruction opens only nearby B02 weakpoints for six seconds")
	host.module.on_target_destroyed("brood_nest_0")
	check(host.completed_count == 1 and host.counters.size() == 1, "Repeated destruction callbacks cannot award completion twice")
	host.player().position = Vector2(1500, 1500)
	host.module.tick(8.0)
	check(int(item.spawned_total) == 0 and host.total_hatched() == 1, "Destroyed nests permanently stop spawning while other nests remain alive")
	host.module.on_target_destroyed("brood_nest_1")
	check(host.finished and host.completed_count == 2, "All destroyed nests finish the objective")
	host.module.tick(60.0)
	check(host.total_hatched() == 1 and host.module.navigation_target().is_empty(), "Completion has no further hatches or unfinished navigation targets")
	host.cleanup()
