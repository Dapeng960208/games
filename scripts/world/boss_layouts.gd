class_name BossLayouts
extends RefCounted
## Four authored boss arenas. The returned value follows the ordinary room
## layout shape and adds boss_spawn/boss_counterplay/reinforcement_spawns for
## the boss host. All coordinates are room-local and deterministic by seed.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const ARENA := Rect2(0, 0, 2800, 1800)

static func build(boss_id: String, seed_value: int) -> Dictionary:
	if boss_id not in ["BO01", "BO02", "BO03", "BO04"]:
		return {}
	var authored: Dictionary = Catalog.bosses().get(boss_id, {})
	if authored.is_empty():
		return {}
	var layout: Dictionary
	match boss_id:
		"BO01": layout = _forge()
		"BO02": layout = _broodbed()
		"BO03": layout = _hangar()
		_: layout = _bell_court()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ boss_id.hash()
	var counter_order: Array = []
	for item: Dictionary in layout.interactables:
		counter_order.append(str(item.id))
	_shuffle(counter_order, rng)
	var reinforcement_spawns: Array = layout.spawn_points.duplicate()
	_shuffle(reinforcement_spawns, rng)
	layout.merge({
		"room_id": str(authored.arena.arena_id),
		"arena_id": str(authored.arena.arena_id),
		"boss_id": boss_id,
		"biome_id": str(authored.biome_id),
		"seed": seed_value,
		"generated": false,
		"gameplay_implemented": true,
		"dynamic_states_verified": true,
		"phase_thresholds": authored.phase_thresholds.duplicate(),
		"reinforcement_plan": authored.arena.reinforcements.duplicate(true),
		"reinforcement_budget": int(authored.reinforcement_budget),
		"reinforcement_cap": int(authored.reinforcement_cap),
		"counterplay_order": counter_order,
		"reinforcement_spawns": reinforcement_spawns,
		"reserved_paths": {},
		"buff_anchors": layout.topology_probes.duplicate(),
	}, true)
	layout["static_obstructions"] = layout.obstructions.duplicate()
	layout["static_obstruction_kinds"] = layout.obstruction_kinds.duplicate()
	layout["prop_instances"] = []
	return layout

static func _base(entry: Vector2, exit: Vector2, boss_spawn: Vector2) -> Dictionary:
	return {
		"arena": ARENA,
		"entry": entry,
		"exit": exit,
		"boss_spawn": boss_spawn,
		"obstructions": [],
		"obstruction_kinds": [],
		"spawn_points": [],
		"objective_points": [boss_spawn],
		"topology_probes": [],
		"interactables": [],
		"boss_counterplay": [],
		"hazard_zones": [],
		"visual_markers": [],
		"encounter_zones": [],
		"dynamic_reservations": [],
	}

static func _forge() -> Dictionary:
	var layout := _base(Vector2(230, 900), Vector2(2570, 900), Vector2(1400, 900))
	layout.spawn_points = [Vector2(520, 430), Vector2(2280, 430), Vector2(2280, 1370), Vector2(520, 1370)]
	layout.topology_probes = [Vector2(650, 900), Vector2(1400, 300), Vector2(2150, 900), Vector2(1400, 1500)]
	for index: int in 3:
		var at: Vector2 = [Vector2(940, 470), Vector2(1860, 470), Vector2(1400, 1390)][index]
		var item := {"id":"BO01:cooling_valve:"+str(index), "kind":"cooling_valve", "counter_id":"cooling_valve", "lane":index, "position":at, "available":true}
		layout.interactables.append(item)
		layout.boss_counterplay.append(item.duplicate(true))
	layout.visual_markers = [
		{"kind":"outer_ring", "center":Vector2(1400,900), "inner_radius":520.0, "radius":710.0},
		{"kind":"central_furnace", "center":Vector2(1400,900), "radius":130.0},
	]
	layout.dynamic_reservations = [{"id":"forge_core", "rect":Rect2(1190,690,420,420)}]
	return layout

static func _broodbed() -> Dictionary:
	var layout := _base(Vector2(250, 1450), Vector2(2550, 350), Vector2(1400, 900))
	layout.spawn_points = [Vector2(520, 390), Vector2(2250, 430), Vector2(2260, 1390), Vector2(540, 1320)]
	layout.topology_probes = [Vector2(900, 760), Vector2(1760, 670), Vector2(1830, 1170), Vector2(980, 1210), Vector2(1400, 900)]
	var knots: Array[Vector2] = [Vector2(1060,650), Vector2(1750,690), Vector2(1740,1160), Vector2(1050,1160)]
	for index: int in knots.size():
		var item := {"id":"BO02:root_knot:"+str(index), "kind":"root_knot", "counter_id":"root_knot", "lane":index, "position":knots[index], "breakable":true, "available":true}
		layout.interactables.append(item)
		layout.boss_counterplay.append(item.duplicate(true))
	layout.visual_markers = [
		{"kind":"dry_core", "center":Vector2(1400,900), "radius":250.0},
		{"kind":"lobe", "centers":[Vector2(900,480),Vector2(2050,620),Vector2(1850,1390),Vector2(650,1220)]},
	]
	layout.dynamic_reservations = [{"id":"dry_core", "rect":Rect2(1150,650,500,500)}]
	return layout

static func _hangar() -> Dictionary:
	var layout := _base(Vector2(240, 900), Vector2(2560, 900), Vector2(1400, 900))
	layout.spawn_points = [Vector2(610, 410), Vector2(2190, 410), Vector2(2190, 1390), Vector2(610, 1390)]
	layout.topology_probes = [Vector2(720,900), Vector2(1400,340), Vector2(2080,900), Vector2(1400,1460)]
	var towers: Array[Vector2] = [Vector2(700,380),Vector2(2100,380),Vector2(2100,1420),Vector2(700,1420)]
	for index: int in towers.size():
		var item := {"id":"BO03:fuse_box:"+str(index), "kind":"fuse_box", "counter_id":"fuse_box", "lane":index, "position":towers[index], "breakable":true, "available":true}
		layout.interactables.append(item)
		layout.boss_counterplay.append(item.duplicate(true))
	layout.visual_markers = [
		{"kind":"runway", "points":[Vector2(420,900),Vector2(2380,900)]},
		{"kind":"runway", "points":[Vector2(1400,220),Vector2(1400,1580)]},
		{"kind":"runway", "points":[Vector2(610,330),Vector2(2190,1470)]},
		{"kind":"runway", "points":[Vector2(2190,330),Vector2(610,1470)]},
	]
	layout.dynamic_reservations = [{"id":"landing_core", "rect":Rect2(1160,660,480,480)}]
	return layout

static func _bell_court() -> Dictionary:
	var layout := _base(Vector2(230, 900), Vector2(2570, 900), Vector2(1400, 900))
	layout.spawn_points = [Vector2(500, 480), Vector2(2300, 480), Vector2(2300, 1320), Vector2(500, 1320)]
	layout.topology_probes = [Vector2(780,520), Vector2(2020,520), Vector2(2020,1280), Vector2(780,1280), Vector2(1400,900)]
	var bells: Array[Vector2] = [Vector2(920,430),Vector2(1880,430),Vector2(1880,1370),Vector2(920,1370)]
	for index: int in bells.size():
		var item := {"id":"BO04:edge_bell:"+str(index), "kind":"edge_bell", "counter_id":"edge_bell", "lane":index, "position":bells[index], "breakable":true, "available":true}
		layout.interactables.append(item)
		layout.boss_counterplay.append(item.duplicate(true))
	layout.visual_markers = [
		{"kind":"inner_ring", "center":Vector2(1400,900), "inner_radius":230.0, "radius":430.0},
		{"kind":"outer_ring", "center":Vector2(1400,900), "inner_radius":570.0, "radius":760.0},
		{"kind":"bridge", "points":[Vector2(1400,470),Vector2(1400,330)]},
		{"kind":"bridge", "points":[Vector2(1830,900),Vector2(2040,900)]},
		{"kind":"bridge", "points":[Vector2(1400,1330),Vector2(1400,1480)]},
		{"kind":"bridge", "points":[Vector2(970,900),Vector2(760,900)]},
	]
	layout.dynamic_reservations = [{"id":"bell_heart", "rect":Rect2(1190,690,420,420)}]
	return layout

static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value

static func validate(layout: Dictionary, clearance: float = 30.0) -> Array[String]:
	var errors: Array[String] = []
	if not layout.has_all(["arena", "entry", "exit", "boss_spawn", "obstructions", "obstruction_kinds", "interactables", "spawn_points"]):
		errors.append("Incomplete boss layout")
		return errors
	var arena: Rect2 = layout.arena
	for key: String in ["entry", "exit", "boss_spawn"]:
		if not arena.grow(-clearance).has_point(layout[key]):
			errors.append(key + " is outside the arena clearance")
	for point: Vector2 in [layout.entry, layout.exit, layout.boss_spawn] + layout.spawn_points + layout.topology_probes:
		for obstacle: Rect2 in layout.obstructions:
			if obstacle.grow(clearance).has_point(point):
				errors.append("Required point intersects boss terrain")
	if layout.obstructions.size() != layout.obstruction_kinds.size():
		errors.append("Obstacle recipes are misaligned")
	if layout.interactables.size() != layout.boss_counterplay.size():
		errors.append("Counterplay descriptors are misaligned")
	return errors
