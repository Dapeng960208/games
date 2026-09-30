class_name RoomLayouts
extends RefCounted
## Original, large-world, planar collision whiteboxes. No objective/AI implementation
## is implied. Pits are actual collision voids; bridge strips are gaps in those voids.
## Geometry uses world coordinates independently of the 1280x720 camera viewport.

const Catalog = preload("res://scripts/world/world_catalog.gd")
const ARENA := Rect2(0, 0, 2800, 1800)
const MAX_ACTOR_RADIUS := 24.0
const EPSILON := 0.01
const VOID_KINDS := ["mine_pit", "gear_gap", "suspended_void", "water_channel", "floating_platform_gap", "ventilation_shaft", "acid_reservoir", "gantry_void", "mirror_pool", "deep_rift", "echo_disc_gap"]
const LIQUID_KINDS := ["water_channel", "acid_reservoir", "mirror_pool"]
const BRIDGE_GAP_ROOMS := ["L02", "L13", "L23"]
const COMPACT_TERRAIN_MAX_SIZE := Vector2(240.0, 180.0)
static var _cache: Dictionary = {}

static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func build(room_id: String) -> Dictionary:
	if _cache.has(room_id):
		return _cache[room_id].duplicate(true)
	var definition: Dictionary = Catalog.room(room_id)
	var geometry: Dictionary = definition.get("geometry", {})
	if geometry.is_empty():
		return {}
	var layout: Dictionary = geometry.duplicate(true)
	layout["room_id"] = room_id
	layout["arena"] = _rect(geometry["arena"])
	layout["entry"] = _point(geometry["entry"])
	layout["exit"] = _point(geometry["exit"])
	for key: String in ["obstructions"]:
		var rectangles: Array[Rect2] = []
		for value: Array in geometry[key]:
			rectangles.append(_rect(value))
		layout[key] = rectangles
	_open_terrain_lanes(layout)
	for key: String in ["spawn_points", "objective_points", "topology_probes"]:
		var points: Array[Vector2] = []
		for value: Array in geometry.get(key, []):
			points.append(_point(value))
		layout[key] = points
	for key: String in ["interactables", "hazard_zones", "visual_markers", "encounter_zones", "dynamic_reservations"]:
		for item: Dictionary in layout.get(key, []):
			if item.has("position"):
				item["position"] = _point(item["position"])
			if item.has("center"):
				item["center"] = _point(item["center"])
			if item.has("rect"):
				item["rect"] = _rect(item["rect"])
			if item.has("spawn_points"):
				var spawns: Array[Vector2] = []
				for value: Array in item["spawn_points"]:
					spawns.append(_point(value))
				item["spawn_points"] = spawns
	layout["gameplay_implemented"] = false
	layout["dynamic_states_verified"] = false
	_cache[room_id] = layout
	return layout.duplicate(true)

static func _open_terrain_lanes(layout: Dictionary) -> void:
	# Retain each authored pit and its bridge arrangement, but give approaches
	# more shoulder room. Only remove terrain from the original rectangles:
	# this cannot obstruct an objective, spawn, or an existing traversable route.
	layout["authored_obstructions"] = layout.obstructions.duplicate()
	var kinds: Array = layout.get("obstruction_kinds", [])
	var arena: Rect2 = layout.arena
	var room_id: String = str(layout.room_id)
	var biome_id: String = str(Catalog.room(room_id).get("biome_id", ""))
	for index: int in layout.obstructions.size():
		if index >= kinds.size() or str(kinds[index]) not in VOID_KINDS: continue
		var original: Rect2 = layout.obstructions[index]
		if biome_id in ["B01", "B03", "B04"] and str(kinds[index]) not in LIQUID_KINDS and room_id not in BRIDGE_GAP_ROOMS:
			# Most dry scenery now forms a short island near its outer bank. The
			# center of the courtyard stays open, instead of stretching one tall
			# rectangle across the player's entire view. Every island remains
			# contained in its original obstacle, with its kind/index preserved.
			var size: Vector2 = (original.size * 0.5).min(COMPACT_TERRAIN_MAX_SIZE)
			var center: Vector2 = original.get_center()
			var position := Vector2(original.position.x if center.x <= arena.get_center().x else original.end.x - size.x,
				original.position.y if center.y <= arena.get_center().y else original.end.y - size.y)
			layout.obstructions[index] = Rect2(position, size)
			continue
		var margin: float = 96.0 if original.size.x > 550.0 and original.size.y > 650.0 else 28.0
		margin = minf(margin, minf(original.size.x, original.size.y) * 0.22)
		var start: Vector2 = original.position + Vector2(margin, margin)
		var finish: Vector2 = original.end - Vector2(margin, margin)
		# Terrain touching the arena boundary keeps that connection; widening a
		# bridge must not create an accidental bypass outside its bank.
		if is_equal_approx(original.position.x, arena.position.x): start.x = original.position.x
		if is_equal_approx(original.position.y, arena.position.y): start.y = original.position.y
		if is_equal_approx(original.end.x, arena.end.x): finish.x = original.end.x
		if is_equal_approx(original.end.y, arena.end.y): finish.y = original.end.y
		layout.obstructions[index] = Rect2(start, finish - start)

static func clear_for_actor(layout: Dictionary, position: Vector2, radius: float = MAX_ACTOR_RADIUS) -> bool:
	var arena: Rect2 = layout.get("arena", Rect2())
	if radius < 0.0 or not arena.grow(-radius).has_point(position):
		return false
	for obstacle: Rect2 in layout.get("obstructions", []):
		if obstacle.grow(radius + EPSILON).has_point(position):
			return false
	return true

static func segment_clear(layout: Dictionary, start: Vector2, finish: Vector2, radius: float = MAX_ACTOR_RADIUS) -> bool:
	if not clear_for_actor(layout, start, radius) or not clear_for_actor(layout, finish, radius):
		return false
	var obstacles: Array[Rect2] = []
	for obstacle: Rect2 in layout.get("obstructions", []):
		obstacles.append(obstacle.grow(radius + EPSILON))
	return _segment_clear(start, finish, obstacles)

static func _segment_clear(start: Vector2, finish: Vector2, obstacles: Array[Rect2]) -> bool:
	# Graph paths are orthogonal: no diagonal corner cutting or unswept teleport.
	if not is_equal_approx(start.x, finish.x) and not is_equal_approx(start.y, finish.y):
		return false
	for obstacle: Rect2 in obstacles:
		if is_equal_approx(start.x, finish.x):
			if start.x >= obstacle.position.x and start.x <= obstacle.end.x and maxf(start.y, finish.y) >= obstacle.position.y and minf(start.y, finish.y) <= obstacle.end.y:
				return false
		elif start.y >= obstacle.position.y and start.y <= obstacle.end.y and maxf(start.x, finish.x) >= obstacle.position.x and minf(start.x, finish.x) <= obstacle.end.x:
			return false
	return true

static func _free(position: Vector2, domain: Rect2, obstacles: Array[Rect2]) -> bool:
	if not domain.has_point(position):
		return false
	for obstacle: Rect2 in obstacles:
		if obstacle.has_point(position):
			return false
	return true

static func _axis(values: Array[float]) -> Array[float]:
	values.sort()
	var unique: Array[float] = []
	for value: float in values:
		if not unique.has(value):
			unique.append(value)
	var complete: Array[float] = unique.duplicate()
	for index: int in range(unique.size() - 1):
		complete.append((unique[index] + unique[index + 1]) * 0.5)
	complete.sort()
	return complete

static func _anchors(layout: Dictionary) -> Array:
	var anchors: Array = [{"id": "exit", "position": layout["exit"]}]
	for key: String in ["objective_points", "spawn_points", "topology_probes"]:
		for index: int in range(layout.get(key, []).size()):
			anchors.append({"id": key + "/" + str(index), "position": layout[key][index]})
	for index: int in range(layout.get("interactables", []).size()):
		anchors.append({"id": "interaction/" + str(index), "position": layout["interactables"][index]["position"]})
	for index: int in range(layout.get("encounter_zones", []).size()):
		anchors.append({"id": "encounter/" + str(index), "position": layout["encounter_zones"][index]["center"]})
		for spawn: int in range(layout["encounter_zones"][index].get("spawn_points", []).size()):
			anchors.append({"id": "encounter/" + str(index) + "/spawn/" + str(spawn), "position": layout["encounter_zones"][index]["spawn_points"][spawn]})
	return anchors

static func validate(room_id: String, radius: float = MAX_ACTOR_RADIUS) -> Dictionary:
	return validate_layout(build(room_id), radius)

static func validate_layout(layout: Dictionary, radius: float = MAX_ACTOR_RADIUS) -> Dictionary:
	var errors: Array = []
	var paths: Dictionary = {}
	var result: Dictionary = {"valid": false, "errors": errors, "paths": paths, "clearance_radius": radius, "dynamic_states_verified": false, "method": "inflated_obstacle_axis_arrangement"}
	if layout.is_empty() or not layout.has_all(["arena", "entry", "exit", "obstructions"]):
		errors.append("Unknown room or incomplete layout")
		return result
	var arena: Rect2 = layout["arena"]
	if radius <= 0.0 or arena.size.x <= radius * 2.0 or arena.size.y <= radius * 2.0:
		errors.append("Invalid actor radius or arena")
		return result
	var obstacles: Array[Rect2] = []
	for obstacle: Rect2 in layout["obstructions"]:
		if obstacle.size.x <= 0.0 or obstacle.size.y <= 0.0 or not arena.encloses(obstacle):
			errors.append("Obstacle outside arena or without area")
		obstacles.append(obstacle.grow(radius + EPSILON))
	var domain: Rect2 = arena.grow(-radius)
	var entry: Vector2 = layout["entry"]
	if not _free(entry, domain, obstacles):
		errors.append("Entry has insufficient clearance")
	var anchors: Array = _anchors(layout)
	for anchor: Dictionary in anchors:
		if not _free(anchor["position"], domain, obstacles):
			errors.append(str(anchor["id"]) + " has insufficient clearance")
	if not errors.is_empty():
		return result
	# Each inflated rectangle boundary partitions free space into orthogonal cells.
	# Include all literal anchor coordinates and each interval midpoint. Unlike a
	# nearest-grid-cell test, every returned path begins at the actual entry and
	# ends at the exact required point; every entire segment is clearance checked.
	var x_values: Array[float] = [domain.position.x, domain.end.x, entry.x]
	var y_values: Array[float] = [domain.position.y, domain.end.y, entry.y]
	for obstacle: Rect2 in obstacles:
		x_values.append(clampf(obstacle.position.x, domain.position.x, domain.end.x))
		x_values.append(clampf(obstacle.end.x, domain.position.x, domain.end.x))
		y_values.append(clampf(obstacle.position.y, domain.position.y, domain.end.y))
		y_values.append(clampf(obstacle.end.y, domain.position.y, domain.end.y))
	for anchor: Dictionary in anchors:
		x_values.append(anchor["position"].x)
		y_values.append(anchor["position"].y)
	var xs: Array[float] = _axis(x_values)
	var ys: Array[float] = _axis(y_values)
	var width: int = xs.size()
	var height: int = ys.size()
	var free_nodes := PackedByteArray()
	free_nodes.resize(width * height)
	for y: int in range(height):
		for x: int in range(width):
			free_nodes[y * width + x] = 1 if _free(Vector2(xs[x], ys[y]), domain, obstacles) else 0
	var parents := PackedInt32Array()
	parents.resize(width * height)
	parents.fill(-1)
	var start: int = ys.find(entry.y) * width + xs.find(entry.x)
	parents[start] = start
	var queue: Array[int] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var x: int = current % width
		var y: int = current / width
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nx: int = x + offset.x
			var ny: int = y + offset.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var next: int = ny * width + nx
			if parents[next] != -1 or free_nodes[next] == 0:
				continue
			if not _segment_clear(Vector2(xs[x], ys[y]), Vector2(xs[nx], ys[ny]), obstacles):
				continue
			parents[next] = current
			queue.append(next)
	for anchor: Dictionary in anchors:
		var position: Vector2 = anchor["position"]
		var target: int = ys.find(position.y) * width + xs.find(position.x)
		if parents[target] == -1:
			errors.append(str(anchor["id"]) + " is disconnected from the entry")
			continue
		var path: Array[Vector2] = []
		var node: int = target
		while node != start:
			path.append(Vector2(xs[node % width], ys[node / width]))
			node = parents[node]
		path.append(entry)
		path.reverse()
		paths[anchor["id"]] = path
	result["valid"] = errors.is_empty()
	result["graph_nodes"] = width * height
	result["reachable_graph_nodes"] = queue.size()
	return result
