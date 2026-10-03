extends Node
## Real host, authored geometry, real EnemyActor targets and player hit pipeline.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Host = preload("res://scripts/gameplay/world/room_objectives.gd")
const Layouts = preload("res://scripts/domain/world/room_layouts.gd")
const Module = preload("res://scripts/levels/b02/world/objectives.gd")
const Generator = preload("res://scripts/gameplay/world/room_generator.gd")
const Props = preload("res://scripts/presentation/world/room_props.gd")
const Coordinator = preload("res://scripts/app/expedition_controller.gd")
var room: RoomController
var host: Node2D
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fixture(id: String, hero: String = "CH01", seed_value: int = -1) -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hero_id = hero
	Game.run.stats = StatResolver.resolve(hero, 1, {}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.loadout_snapshot.clear()
	Game.run.max_hp = 1000.0
	Game.run.hp = 1000.0
	Game.run.shield = 0.0
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.combat_audio.audible = false
	room.spawn_enabled = false
	room.input_blocked = true
	room.release_gate = false
	for enemy in room.enemies.get_children():
		enemy.free()
	room.layout = Generator.generate(id,seed_value) if seed_value >= 0 else Layouts.build(id)
	room.layout_id = id
	room.obstructions.assign(room.layout.obstructions)
	room.geometry_enabled = true
	room._navigation_cache.prepare(room.obstructions, room.ARENA)
	room.player.position = room.layout.entry
	if seed_value >= 0:
		if is_instance_valid(room.enemy_props):
			room.enemy_props.free()
		room.enemy_props = Props.new()
		room.add_child(room.enemy_props)
		check(room.enemy_props.configure(room,room.layout), id + " configures real generated props")
	host = Host.new()
	room.add_child(host)
	room.objectives = host
	host.configure(room, room.layout)
	check(host.module != null and host.module.get_script() == Module, id + " loads the real B02 objective module")
	check(not host.finished, id + " does not complete on room entry or enemy clearance")

func go(id: String) -> void:
	room.player.position = host.element(id).position

func use(id: String) -> bool:
	go(id)
	return host.interact(id, room.player)

func step(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.00001:
		var delta: float = minf(remaining, 0.1)
		host.tick(delta)
		remaining -= delta

func attack(id: String, amount: float = 20.0) -> void:
	var target: EnemyActor = host.element(id).get("target_actor")
	check(is_instance_valid(target) and target.is_alive(), id + " is a real living attack target")
	if not is_instance_valid(target) or not target.is_alive():
		return
	room.player.position = host.safe_point(target.position + Vector2(55.0, 0.0))
	room.player.original_hit(target, amount, &"primary")

func destroy(id: String) -> void:
	var target: EnemyActor = host.element(id).get("target_actor")
	var count: int = 0
	while is_instance_valid(target) and target.is_alive() and count < 20:
		attack(id)
		count += 1
	check(is_instance_valid(target) and not target.is_alive(), id + " breaks through repeated original basic-hit damage")

func fire_at(id: String) -> void:
	var target: EnemyActor = host.element(id).target_actor
	room.player.position = host.safe_point(target.position-Vector2(72.0,0.0),18.0)
	var before: float = target.health.current
	room.player.aim_direction = room.player.position.direction_to(target.position)
	check(room.player.fire(room.player.aim_direction), "hero starts its real primary attack against task prop")
	if str(Game.run.hero_id) == "CH01":
		room.player._tick_attack(.14)
	else:
		for frame: int in 20:
			for projectile in room.projectiles.get_children():
				if not projectile.is_queued_for_deletion(): projectile._physics_process(.016)
	check(target.health.current < before, str(Game.run.hero_id) + " primary windup/projectile collision reaches the real objective target")

func events_named(name: String) -> int:
	var count: int = 0
	for event: Dictionary in host.events:
		if str(event.name) == name:
			count += 1
	return count

func run_checks() -> void:
	if not Game.profile_path.contains("test_objectives_b02"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated real-player B02 run starts")
	_test_filters()
	_test_pressure_mushrooms()
	_test_real_pods()
	_test_fans()
	_test_research_walls()
	_test_acid()
	_test_reflood_retry()
	_test_pause_and_early_drain()
	_test_generated_mechanisms()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "B02 test audio has no pending playback")
		room.free()
	print("B02 OBJECTIVES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_filters() -> void:
	fixture("L07")
	check(not use("water_wheel") and host.completed_count == 0, "wheel cannot turn empty interaction into task progress")
	check(use("filter_0") and host.blocks_dash(), "actual filter pickup suppresses dash")
	check(not use("filter_1"), "cannot carry two filters")
	go("carry_drop")
	check(host.interact("carry_drop", room.player) and not host.blocks_dash(), "E safely drops carried filter and restores dash")
	check(not bool(host.element("filter_0").done) and bool(host.element("filter_0").active), "dropped filter remains recoverable")
	check(use("filter_0"), "dropped filter can be picked up again")
	check(str(host.navigation_target().id) == "water_wheel", "carried filter navigation points to delivery, not the drop action")
	go("water_wheel")
	step(0.1)
	check(str(room.nearby_interaction().id) == "water_wheel", "nearby E prioritizes the wheel over the carried drop action")
	room.input_blocked = false
	room.interact()
	room.input_blocked = true
	check(host.completed_count == 1 and not host.blocks_dash(), "real nearby selection and room E action deliver the first filter")
	check(not use("water_wheel") and host.completed_count == 1, "delivery cannot be duplicated")
	for index: int in [1,2]:
		check(use("filter_%d" % index) and use("water_wheel"), "remaining filter requires pickup and transport")
	check(host.finished and host.completed_count == 3 and not host.blocks_dash(), "three delivered filters complete the water wheel")
	fixture("L07")
	var bridge: Rect2 = host.module.state.bridges[1]
	room.player.position = bridge.get_center()
	step(7.2)
	check(events_named("root_bridge_switched") == 0 and not host.blockers.has("root_bridge_1"), "occupied span postpones bridge retraction")
	room.player.position = room.layout.entry
	step(0.2)
	check(events_named("root_bridge_switched") == 1, "bridge changes once occupants leave")
	check(host.blockers.size() >= 1, "bridge switching changes actual collision instead of only a label")
	check(not (host.blockers.has("root_bridge_0") and host.blockers.has("root_bridge_1")), "western crossing always keeps one bridge open")
	var thief: EnemyActor = room.spawn_enemy(host.element("filter_0").position)
	thief.enemy_id = "M16"
	thief.state = &"chase"
	var previous: Vector2 = host.element("filter_0").position
	step(0.6)
	check(Vector2(host.element("filter_0").position) == previous and host.element("filter_0").has("beam_to"), "thief gives a visible one-second suction warning before moving filter")
	step(1.0)
	var dragged: float = Vector2(host.element("filter_0").position).distance_to(previous)
	check(dragged > 10.0 and dragged < 115.0 and not host.element("filter_0").done, "thief visibly drags filter at bounded speed instead of teleporting")
	check(use("filter_0") and host.module.state.thefts.is_empty(), "filter remains pickable during theft and pickup cancels suction")
	check(use("carry_drop"), "rescued filter can be safely put down")
	step(8.1)
	thief.position = host.element("filter_0").position
	previous = host.element("filter_0").position
	step(1.5)
	thief.take_damage(10000.0, &"primary")
	step(0.1)
	check(Vector2(host.element("filter_0").position).distance_to(previous) < 1.0 and host.module.state.thefts.is_empty(), "killing thief returns the complete filter to its original safe point")

func _test_pressure_mushrooms() -> void:
	fixture("L08")
	check(not use("mushroom_0"), "closed mushroom cannot be collected by E spam")
	step(0.4)
	check(not host.element("mushroom_0").opened, "short pressure does not instantly open mushroom")
	step(0.5)
	check(host.element("mushroom_0").opened, "standing on the real platform opens its cap")
	room.player.position = room.layout.entry
	step(0.6)
	check(not host.element("mushroom_0").opened and not host.blockers.has("platform_edge_0"), "leaving releases pressure and restores platform edge")
	for index: int in 3:
		go("mushroom_%d" % index)
		step(0.9)
		check(host.interact("mushroom_%d" % index, room.player), "pressed mushroom can be harvested")
	check(host.finished and host.completed_count == 3, "three pressure-gated harvests complete L08")
	fixture("L08")
	var cloud_before: Vector2 = host.element("drifting_cloud_0").position
	step(2.0)
	check(Vector2(host.element("drifting_cloud_0").position).distance_to(cloud_before) > 20.0, "spore cloud actually drifts")
	check(not host.hazards.is_empty() and float(host.hazards[0].damage) > 0.0, "drifting cloud creates a real delayed damage region")
	for hazard: Dictionary in host.hazards:
		check(float(hazard.radius) < 100.0, "cloud cannot fill the room or outer route")

func _test_real_pods() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		fixture("L09", hero)
		check(not use("main_pod_0") and host.completed_count == 0, hero + " cannot interact-complete an attack target")
		step(.1)
		check(events_named("main_pod_resonance") == 1 and not room.combat_audio.audible, "main pod schedules its resonant audio clue through the muted real audio pool")
		attack("decoy_0")
		check(host.hazards.size() == 1 and float(host.hazards[0].delay) >= 0.8, "false pod warns before its real spore damage")
		attack("decoy_0")
		check(host.hazards.size() == 1 and host.completed_count == 0, "same-frame false-pod hits neither spam warnings nor count as objectives")
		check(host.element("main_pod_0").pattern != host.element("decoy_0").pattern, "main and false pods have non-color identifying patterns")
		fire_at("main_pod_0")
		destroy("main_pod_0")
		check(host.completed_count == 1 and not host.finished, hero + " first basic-attack target preserves second requirement")
		destroy("main_pod_1")
		check(host.finished and host.completed_count == 2, hero + " basic attacks can complete both real main pods without skills")

func _test_fans() -> void:
	fixture("L10")
	go("fan_0")
	var direction: Vector2 = host.element("fan_0").direction
	var light: EnemyActor = room.spawn_enemy(room.player.position + direction * 95.0)
	light.navigation_radius = 16.0
	light.state = &"chase"
	var heavy: EnemyActor = room.spawn_enemy(room.player.position + direction * 120.0)
	heavy.navigation_radius = 38.0
	heavy.state = &"chase"
	var light_before: Vector2 = light.position
	var heavy_before: Vector2 = heavy.position
	var cloud_before: Vector2 = host.element("fan_cloud_0").position
	check(host.interact("fan_0", room.player), "fan can be started in a player-selected order")
	step(2.0)
	check((light.position-light_before).dot(direction) > 10.0 and heavy.position == heavy_before, "directional wind moves light enemies but leaves heavy enemies in place")
	check((Vector2(host.element("fan_cloud_0").position)-cloud_before).dot(direction) > 10.0, "same directional wind displaces the spore cloud")
	step(2.1)
	check(host.element("fan_0").phase == "overload", "running fan enters a readable interruptible overload")
	var progress: float = host.element("fan_0").progress
	check(use("fan_0") and host.element("fan_0").phase == "cooldown", "E interrupts overload before damage is scheduled")
	step(0.9)
	check(is_equal_approx(float(host.element("fan_0").progress), progress), "interruption preserves earned purification progress")
	check(events_named("fan_overload_recoverable") == 0, "timely interruption avoids overload burst")
	for index: int in 3:
		var id: String = "fan_%d" % index
		var attempts: int = 0
		while not bool(host.element(id).done) and attempts < 5:
			if host.element(id).phase == "idle":
				use(id)
			step(4.0)
			if host.element(id).phase == "overload":
				use(id)
			step(1.0)
			attempts += 1
	check(host.finished and host.completed_count == 3, "restartable fans complete by actual operating time")

func _test_research_walls() -> void:
	_research_expedition_fixture()
	check(not use("research_0"), "intact nursery prevents package pickup")
	var wall_count: int = room.obstructions.size()
	var wall: Rect2 = host.element("thin_wall_0").wall_rect
	destroy("thin_wall_0")
	check(room.obstructions.size() == wall_count-1 and not room.obstructions.has(wall), "basic attacks remove the authored wall from actual collision")
	check(not host.layout.obstructions.has(wall), "wall removal also updates the objective navigation layout")
	step(2.6)
	check(not host.hazards.is_empty() and str(host.hazards[0].get("kind", "")) == "connected_gutter", "opened wall creates telegraphed acid in a newly connected gutter")
	destroy("research_nest_2")
	check(not use("research_2") and host.completed_count == 0 and events_named("optional_research_recovered") == 0, "opening the optional nursery does not bypass required objectives or award an early package")
	check(not host.element("research_2").done, "early optional research attempt preserves the package")
	for index: int in 2:
		destroy("research_nest_%d" % index)
		check(use("research_%d" % index), "opened nursery exposes a real recoverable package")
	check(host.finished and host.completed_count == 2, "two required research packages open completion")
	check(not host.module.state.has("gnaw"), "task module does not invent a second M18 bite damage budget")
	check(not use("research_2"), "required objectives alone cannot claim the optional package before the room commits clear")
	_commit_research_clear()
	check(use("research_2") and host.completed_count == 2 and events_named("optional_research_recovered") == 1, "cleared expedition grants the optional package without inflating its required count")
	check(not use("research_2") and events_named("optional_research_recovered") == 1, "claimed optional research cannot repeat its reward event")
	_research_expedition_fixture()
	for index: int in 2:
		destroy("research_nest_%d" % index)
		use("research_%d" % index)
	check(host.finished and not host.element("research_2").done, "required completion leaves the optional package intact")
	_commit_research_clear()
	destroy("research_nest_2")
	check(use("research_2") and events_named("optional_research_recovered") == 1 and host.completed_count == 2, "third optional package remains obtainable after the exit opens")
	check(not Game.finish_run("abandoned").is_empty() and Game.start_run(), "restore isolated legacy fixture after real research expedition")

func _research_expedition_fixture() -> void:
	if is_instance_valid(room):
		room.free()
	if Game.run != null:
		check(not Game.finish_run("abandoned").is_empty(), "close previous isolated run before research expedition")
	check(Game.new_profile() and Game.start_run(), "start legitimate biome-unlock setup run")
	check(Game.record_boss_defeat("BO01") and not Game.finish_run("extracted").is_empty(), "previous boss receipt unlocks the research biome")
	check(Game.start_run({"expedition": true, "biome_id": "B02", "seed": 41827}), "research fixture starts a normal B02 expedition")
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.use_generated_layout = false
	var coordinator = Coordinator.new(Game)
	var prepared: Dictionary = room.prepare_expedition_node(coordinator.current_context())
	check(bool(prepared.get("valid", false)), "prepare committed B02 entrance")
	room.apply_prepared_expedition_node(prepared)
	add_child(room)
	room.combat_audio.audible = false
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers", []):
		check(Game.choose_run_relic(str(offer.offer_id), "skip", "", room.expedition_runtime_snapshot()), "resolve entrance offer through its real transaction")
	var state: Dictionary = Game.expedition_snapshot()
	check(Game.choose_expedition_node(1, "L11"), "choose research room from the legal seeded branch")
	check(Game.advance_expedition_node(room.expedition_runtime_snapshot(), str(state.checkpoint_id)), "commit research node entry before constructing its objectives")
	prepared = room.prepare_expedition_node(coordinator.current_context())
	check(bool(prepared.get("valid", false)), "prepare authored research room")
	room.apply_prepared_expedition_node(prepared)
	room.spawn_enabled = false
	room.input_blocked = true
	host = room.objectives
	check(room.layout_id == "L11" and host.module.get_script() == Module and not host.finished, "real research room owns the committed expedition node")

func _commit_research_clear() -> void:
	check(host.finished, "research completion requires both recovered packages")
	for enemy in room.enemies.get_children():
		if enemy.actor_kind != "objective" and enemy.is_alive():
			enemy.take_damage(1000000.0, &"test", Vector2.ZERO, {"damage_type": "true"})
	check(room._living_enemy_count() == 0, "real damage clears every living encounter actor")
	room._tick_expedition(.016)
	check(room.objective_rewarded and Game.expedition_snapshot().phase == "cleared", "room and Game commit the actual cleared checkpoint before optional loot")

func _test_acid() -> void:
	fixture("L12")
	var before: float = host.module.state.levels[0]
	check(not use("reaction_0") and host.completed_count == 0, "reactor interaction cannot substitute for flowing acid")
	check(use("sluice_0"), "player opens a real sluice")
	step(1.0)
	check(float(host.module.state.levels[0]) < before and float(host.module.state.levels[1]) > 0.65, "opening sluice conserves transfer into the downstream reservoir")
	check(float(host.element("reaction_0").progress) > 0.0 and not host.finished, "acid flow actually charges its reaction tank")
	for index: int in [1,2,3]:
		check(use("sluice_%d" % index), "additional sluice is independently switchable")
	step(6.0)
	check(host.finished and host.completed_count == 2 and host.quality == "full", "actual flow neutralizes both waste tanks")

func _test_pause_and_early_drain() -> void:
	fixture("L12")
	check(use("sluice_0"), "pause fixture has an open sluice")
	var levels: Array = host.module.state.levels.duplicate()
	get_tree().paused = true
	host.tick(5.0)
	check(host.module.state.levels == levels and not use("drain_all"), "pause freezes water and rejects controls")
	get_tree().paused = false
	check(use("drain_all"), "emergency drain is available without any skill or objective count")
	step(4.0)
	check(host.finished and host.quality == "reduced" and host.completed_count < 2, "early drainage is an explicit lower-yield completion path")
	check(room.obstructions.is_empty(), "drained pool floors become genuinely walkable")
	check(room.valid_ground(Vector2(1400.0,900.0), 18.0), "central dry ring remains safe and accessible")

func _test_reflood_retry() -> void:
	fixture("L12")
	check(use("sluice_1"), "independent downstream sluice can drain its reservoir first")
	step(2.9)
	check(bool(host.module.state.dry[1]), "drained downstream pool exposes a traversable floor")
	check(use("sluice_1") and use("sluice_0"), "closing downstream and opening upstream begins a genuine refill")
	# A newly required route point can reject reflooding even after actors leave.
	# This exercises expensive topology refusal, not the cheap occupied check.
	var reservoir: Rect2 = host.module.state.pool_rects[1]
	host.layout.objective_points.append(reservoir.get_center())
	step(3.2)
	var retry: float = host.module.state.surface_retry[1]
	check(retry > host.module.clock and bool(host.module.state.dry[1]) and not host.blockers.has("acid_pool_1"), "unreachable reflood is refused and schedules a bounded retry")
	step(.2)
	check(is_equal_approx(float(host.module.state.surface_retry[1]),retry), "reflood refusal does not rebuild the topology graph each tick")

func _test_generated_mechanisms() -> void:
	for seed_value: int in [713,20260928]:
		for id: String in ["L07","L08","L09","L10","L11","L12"]:
			fixture(id,"CH02",seed_value)
			var destination: Dictionary = host.navigation_target()
			check(destination.has("id") and room.valid_ground(destination.position,18.0), id + " generated navigation chooses a reachable task action")
			check(not str(destination.get("id", "")).contains("cloud") and not str(destination.get("id", "")).contains("level"), id + " navigation ignores helper art")
			if id == "L07":
				check(use("filter_0"), "generated carry pickup remains reachable")
				go("water_wheel")
				step(.1)
				check(str(room.nearby_interaction().get("id", "")) == "water_wheel", "generated E selection chooses delivery over carried drop")
				room.input_blocked = false
				room.interact()
				check(host.completed_count == 1, "generated nearby room E actually delivers")
			elif id == "L11":
				var walls: Array = []
				var solid_count: int = room.obstructions.size()
				for element: Dictionary in host.elements.values():
					if str(element.id).begins_with("thin_wall_"): walls.append(element)
				var expected: int = room.layout.obstruction_kinds.count("breakable_wall")
				check(walls.size() == expected and expected > 0 and expected < solid_count, "generated task targets exactly tagged thin walls, never fungi and rocks")
				var selected: Dictionary = walls[0]
				var wall_actor: EnemyActor = selected.target_actor
				var gnawer: EnemyActor = room.spawn_enemy(selected.position)
				gnawer.enemy_id = "M18"
				gnawer.state = &"chase"
				var entity_id: String = ""
				for entity: Dictionary in room.enemy_props.query_tag("thin_wall"):
					if entity.rect == selected.wall_rect: entity_id = str(entity.id)
				check(not entity_id.is_empty(), "task target corresponds to a real breakable RoomProps entity")
				step(2.0)
				check(not selected.done, "proximity alone cannot bypass M18's real bite skill")
				var bite: Dictionary = room.enemy_props.utility(gnawer,"bite_breakable_wall",{"target_id":entity_id,"range":120.0,"breakable_wall_cap":1})
				check(bool(bite.get("success",false)), "real M18 prop bite removes the selected thin wall")
				step(.1)
				check(selected.done and wall_actor.is_queued_for_deletion() and events_named("thin_wall_external_bite_synced") == 1, "objective synchronizes real external bite and removes its obsolete attack target")
				check(room.obstructions.size() == solid_count-1 and not host.layout.obstructions.has(selected.wall_rect), "external bite keeps room and task collision layouts synchronized")
				var capped: Dictionary = room.enemy_props.utility(gnawer,"bite_breakable_wall",{"range":9999.0,"breakable_wall_cap":1})
				check(not bool(capped.get("success",false)) and str(capped.get("reason","")) == "wall_break_cap", "objective sync preserves M18's original one-wall cap")
			elif id == "L12":
				var solids: Array = room.obstructions.duplicate()
				check(host.module.state.pool_rects.size() == 4, "generated acid controls only the four reservoirs")
				for rectangle: Rect2 in host.module.state.pool_rects: solids.erase(rectangle)
				check(use("drain_all"), "generated early-drain control remains reachable")
				step(4.0)
				check(host.finished and room.obstructions.size() == solids.size(), "generated drainage opens reservoir floors without deleting unrelated props")
				for rectangle: Rect2 in solids:
					check(room.obstructions.has(rectangle), "generated solid prop survives acid drainage")
