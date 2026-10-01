class_name BossLayouts
extends RefCounted
## Four authored boss arenas. The returned value follows the ordinary room
## layout shape and adds boss_spawn/boss_counterplay/reinforcement_spawns for
## the boss host. Coordinates come from the approved drawings and never change by seed.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const FixedLayouts = preload("res://scripts/world/fixed_room_layouts.gd")

static func build(boss_id: String, seed_value: int) -> Dictionary:
	if boss_id not in ["BO01", "BO02", "BO03", "BO04"]:
		return {}
	var authored: Dictionary = Catalog.bosses().get(boss_id, {})
	if authored.is_empty():
		return {}
	var layout: Dictionary = FixedLayouts.build(boss_id, seed_value)
	if layout.is_empty(): return {}
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
	}, true)
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
