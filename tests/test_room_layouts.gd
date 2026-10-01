extends SceneTree
## Static, physical large-room whitebox acceptance; no dynamic-objective claim.
const Layouts = preload("res://scripts/world/room_layouts.gd")
const Catalog = preload("res://scripts/world/world_catalog.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _physical_point_clear(layout: Dictionary, point: Vector2, radius: float) -> bool:
	# Independent circle-vs-rectangle contact check, rather than the validator's
	# conservative square inflation. The actual disk cannot penetrate an obstacle.
	var arena: Rect2 = layout["arena"]
	if point.x - radius < arena.position.x or point.y - radius < arena.position.y or point.x + radius > arena.end.x or point.y + radius > arena.end.y:
		return false
	for obstacle: Rect2 in layout["obstructions"]:
		var nearest := Vector2(clampf(point.x, obstacle.position.x, obstacle.end.x), clampf(point.y, obstacle.position.y, obstacle.end.y))
		if point.distance_squared_to(nearest) < radius * radius:
			return false
	return true

func _canonical_shape(layout: Dictionary) -> String:
	# Reject reflected or rotated copies. Normalize the arena before comparing
	# the eight symmetries; authored feature probes check meaningful topology too.
	var variants: Array[String] = []
	var arena: Rect2 = layout["arena"]
	for rotation: int in range(4):
		for reflect: bool in [false, true]:
			var rectangles: Array[String] = []
			for obstacle: Rect2 in layout["obstructions"]:
				var corners: Array[Vector2] = [obstacle.position, obstacle.position + Vector2(obstacle.size.x, 0), obstacle.end, obstacle.position + Vector2(0, obstacle.size.y)]
				var low := Vector2(INF, INF)
				var high := Vector2(-INF, -INF)
				for corner: Vector2 in corners:
					var p: Vector2 = (corner - arena.position) / arena.size
					if reflect:
						p.x = 1.0 - p.x
					for turn: int in range(rotation):
						p = Vector2(1.0 - p.y, p.x)
					low = low.min(p)
					high = high.max(p)
				rectangles.append("%.4f,%.4f,%.4f,%.4f" % [low.x, low.y, high.x - low.x, high.y - low.y])
			rectangles.sort()
			variants.append(";".join(rectangles))
	variants.sort()
	return variants[0]

func _fixture(obstacles: Array[Rect2]) -> Dictionary:
	return {"arena": Rect2(0, 0, 400, 300), "entry": Vector2(50, 150), "exit": Vector2(350, 150), "obstructions": obstacles}

func _run() -> void:
	_check(Layouts.build("unknown").is_empty(), "Unknown room produces no fake fallback layout")
	_check(not Layouts.validate("unknown")["valid"], "Unknown room fails navigation")
	_check(not Layouts.validate_layout({})["valid"], "Incomplete layout fails navigation")
	_check(not Layouts.validate_layout(_fixture([]), -1.0)["valid"], "Invalid actor radius is rejected")
	var sealed: Dictionary = _fixture([Rect2(175, 0, 50, 300)])
	_check(not Layouts.validate_layout(sealed)["valid"], "A wall across the full arena cannot be teleported through")
	var narrow: Dictionary = _fixture([Rect2(175, 0, 50, 130), Rect2(175, 170, 50, 130)])
	_check(not Layouts.validate_layout(narrow)["valid"], "40px passage rejects a 48px actor")
	var wide: Dictionary = _fixture([Rect2(175, 0, 50, 105), Rect2(175, 195, 50, 105)])
	_check(Layouts.validate_layout(wide)["valid"], "90px bridge is genuinely traversable")
	_check(not Layouts.segment_clear(sealed, Vector2(50, 150), Vector2(350, 150)), "A direct movement segment cannot cross a wall")
	var blocked_target: Dictionary = _fixture([Rect2(310, 110, 80, 80)])
	_check(not Layouts.validate_layout(blocked_target)["valid"], "Blocked literal exit is rejected, not snapped to free ground")
	var blocked_nested_spawn: Dictionary = _fixture([Rect2(170, 100, 60, 50)])
	blocked_nested_spawn["encounter_zones"] = [{"center": Vector2(80, 80), "spawn_points": [Vector2(190, 125)]}]
	_check(not Layouts.validate_layout(blocked_nested_spawn)["valid"], "Nested encounter spawns are checked independently of the flattened list")
	var detached: Dictionary = Layouts.build("L01")
	detached["obstructions"].clear()
	detached["encounter_zones"][0]["spawn_points"].clear()
	_check(not Layouts.build("L01")["obstructions"].is_empty(), "Geometry cache returns deep copies")
	_check(not Layouts.build("L01")["encounter_zones"][0]["spawn_points"].is_empty(), "Nested encounter data returns deep copies")
	var maximum_radius: float = 24.0
	for enemy_id: String in Catalog.enemy_ids():
		maximum_radius = maxf(maximum_radius, float(Catalog.enemy(enemy_id)["navigation_radius"]))
	_check(maximum_radius == Layouts.MAX_ACTOR_RADIUS, "Validator covers the largest authored ordinary enemy radius")
	var shapes: Dictionary = {}
	var total_paths: int = 0
	for room_id: String in Catalog.room_ids():
		var layout: Dictionary = Layouts.build(room_id)
		_check(layout.get("arena", Rect2()) == Rect2(0, 0, 2800, 1800), room_id + " actual large world arena")
		_check(layout["entry"].distance_to(layout["exit"]) >= 1200.0, room_id + " entry and exit have meaningful travel distance")
		_check(layout["obstructions"].size() >= 3, room_id + " physical terrain is populated")
		for index: int in layout.obstructions.size():
			var original: Rect2 = layout.authored_obstructions[index]
			_check(original.encloses(layout.obstructions[index]), room_id + " lane widening only removes occupied ground")
			if layout.obstruction_kinds[index] in Layouts.VOID_KINDS:
				_check(layout.obstructions[index].get_area() < original.get_area(), room_id + " pit shoulders have more walking clearance")
				if str(Catalog.room(room_id).biome_id) in ["B01", "B03", "B04"] and layout.obstruction_kinds[index] not in Layouts.LIQUID_KINDS and room_id not in Layouts.BRIDGE_GAP_ROOMS:
					_check(layout.obstructions[index].size.x <= original.size.x * 0.5 + 0.01 and layout.obstructions[index].size.y <= original.size.y * 0.5 + 0.01, room_id + " dry terrain occupies at most half the original width and height")
					_check(layout.obstructions[index].size.x <= 240.0 and layout.obstructions[index].size.y <= 180.0, room_id + " dry terrain is a short scenery island")
		for i: int in range(layout["obstructions"].size()):
			var first: Rect2 = layout["obstructions"][i]
			for j: int in range(i + 1, layout["obstructions"].size()):
				var second: Rect2 = layout["obstructions"][j]
				var x_overlap: float = minf(first.end.x, second.end.x) - maxf(first.position.x, second.position.x)
				var y_overlap: float = minf(first.end.y, second.end.y) - maxf(first.position.y, second.position.y)
				if y_overlap > 0.01 and x_overlap < -0.01:
					_check(-x_overlap >= 72.0, room_id + " facing walls do not leave unintended narrow horizontal slits")
				if x_overlap > 0.01 and y_overlap < -0.01:
					_check(-y_overlap >= 72.0, room_id + " facing walls do not leave unintended narrow vertical slits")
		_check(layout["objective_points"].size() >= int(Catalog.room(room_id)["objective_count"]), room_id + " retains all authored objective locations")
		_check(layout["encounter_zones"].size() >= 3, room_id + " has three spread encounter regions")
		_check(layout["room_concurrent_cap"] == 18, room_id + " preserves concurrent enemy cap")
		_check(not layout["gameplay_implemented"] and not layout["mechanism_implemented"] and not layout["dynamic_states_verified"], room_id + " does not overclaim objective or dynamic gameplay")
		_check(not layout["visual_markers"].is_empty() and not layout["dynamic_reservations"].is_empty(), room_id + " preserves topology visuals and future phase contracts")
		for i: int in range(layout["encounter_zones"].size()):
			var zone: Dictionary = layout["encounter_zones"][i]
			_check(zone["spawn_points"].size() >= 2 and zone["concurrent_cap"] == 6, room_id + " local encounter spawn alternatives")
			for j: int in range(i + 1, layout["encounter_zones"].size()):
				_check(zone["center"].distance_to(layout["encounter_zones"][j]["center"]) >= 500.0, room_id + " encounter regions are spatially distinct")
		var signature: String = _canonical_shape(layout)
		_check(not shapes.has(signature), room_id + " is not a rotated or reflected duplicate collision template")
		shapes[signature] = room_id
		var report: Dictionary = Layouts.validate_layout(layout, maximum_radius)
		_check(report["valid"], room_id + " all static anchors connected: " + str(report["errors"]))
		_check(report["paths"].has("exit"), room_id + " has an explicit physical route to exit")
		for path_id: String in report["paths"]:
			var path: Array = report["paths"][path_id]
			total_paths += 1
			_check(path[0] == layout["entry"], room_id + " path begins at literal entry")
			for step: int in range(1, path.size()):
				var start: Vector2 = path[step - 1]
				var finish: Vector2 = path[step]
				_check(is_equal_approx(start.x, finish.x) or is_equal_approx(start.y, finish.y), room_id + " path never cuts diagonally through a corner")
				var count: int = maxi(1, int(ceil(start.distance_to(finish) / 12.0)))
				var physically_clear: bool = true
				for sample: int in range(count + 1):
					if not _physical_point_clear(layout, start.lerp(finish, float(sample) / float(count)), maximum_radius):
						physically_clear = false
						break
				_check(physically_clear, room_id + " returned path can move a physical 48px actor")
		if room_id in ["L01", "L03", "L05", "L06", "L08", "L11", "L15", "L22"]:
			var ring: Array = layout["topology_probes"]
			for i: int in range(ring.size()):
				_check(Layouts.segment_clear(layout, ring[i], ring[(i + 1) % ring.size()]), room_id + " outer ring has continuous clear edges")
		if room_id in ["L10", "L13", "L19", "L24"]:
			_check(layout["collision_plane_count"] == 1 and not str(layout["projection_note"]).is_empty(), room_id + " layered projection limitations are explicit")
		if room_id in ["L14", "L20"]:
			_check(not Layouts.segment_clear(layout, layout["entry"], layout["exit"]), room_id + " winding main route cannot collapse into a straight aisle")
		if room_id == "L14":
			var shortcuts: Array = layout["topology_probes"]
			_check(Layouts.segment_clear(layout, shortcuts[3], shortcuts[4]), "L14 north shortcut is a real separate passage")
			_check(Layouts.segment_clear(layout, shortcuts[5], shortcuts[6]), "L14 south shortcut is a real separate passage")
		print("ROOM_LAYOUT " + room_id + " obstacles=" + str(layout["obstructions"].size()) + " reachable=" + str(report["paths"].size()) + " valid=" + str(report["valid"]))
	var bridge: Dictionary = Layouts.build("L02")
	for index: int in 2:
		_check(bridge.obstructions[index].get_area() < bridge.authored_obstructions[index].get_area() * 0.60, "L02 large pit occupies under 60% of its former area")
	var beacon_court: Dictionary = Layouts.build("L05")
	_check(Layouts.segment_clear(beacon_court, Vector2(700,900), Vector2(2100,900), 24.0), "L05 central courtyard has a continuous 1400px horizontal route")
	_check(Layouts.segment_clear(beacon_court, Vector2(1400,520), Vector2(1400,1280), 24.0), "L05 central courtyard has a continuous 760px vertical route")
	_check(shapes.size() == 24, "24 independent collision layouts")
	print("ROOM_LAYOUT_TESTS checks=" + str(checks) + " failures=" + str(failures) + " layouts=" + str(shapes.size()) + " validated_paths=" + str(total_paths))
	quit(0 if failures == 0 else 1)
