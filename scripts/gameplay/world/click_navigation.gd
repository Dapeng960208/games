extends RefCounted
## One compact visibility route per click. Only a changed obstruction or an
## authored displacement invalidates it; movement never searches every frame.

var room: Node2D
var path := PackedVector2Array()
var goal := Vector2(INF, INF)
var _walls: Array[Rect2] = []
var _replan_delay: float = 0.0
var route_searches: int = 0
var graph_builds: int = 0
var _graph: AStar2D
var _points: Array[Vector2] = []
var _cached_walls: Array[Rect2] = []
var _cached_arena := Rect2()
var _cached_ground := PackedVector2Array()
var _cached_radius: float = -1.0
var _boxes: Array[Rect2] = []
var _visibility: RefCounted = preload("res://scripts/gameplay/world/navigation_cache.gd").new()

func configure(host: Node2D) -> void:
	room = host
	cancel()
	_graph = null
	_points.clear()
	_cached_walls.clear()
	_cached_arena = Rect2()
	_cached_ground.clear()
	_cached_radius = -1.0
	_boxes.clear()

func cancel() -> void:
	path.clear()
	goal = Vector2(INF, INF)
	_walls.clear()
	_replan_delay = 0.0

func is_active() -> bool:
	return not path.is_empty()

func request(from: Vector2, target: Vector2, radius: float) -> bool:
	cancel()
	if not is_instance_valid(room) or not from.is_finite() or not target.is_finite() or not room.valid_ground(target, radius):
		return false
	goal = target
	return _build(from, radius)

func motion(from: Vector2, distance_budget: float, radius: float, delta: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	_replan_delay = maxf(0.0, _replan_delay - delta)
	while not path.is_empty() and from.distance_squared_to(path[0]) <= 9.0:
		# A nearby corner can be skipped only when its next segment is legal.
		# Otherwise the bounded step below reaches that corner without cutting it.
		if path.size() > 1 and not _segment_clear(from, path[1], radius):
			break
		path.remove_at(0)
	if path.is_empty():
		cancel()
		return Vector2.ZERO
	# Every proposed step still passes through room.move_actor. Refuse a stale
	# segment until a moved/broken prop has produced a new legal route.
	var geometry_changed: bool = _walls != _current_walls() or _cached_arena != room.ARENA or _cached_ground != room.ground_polygon or _cached_radius != radius
	var blocked: bool = not geometry_changed and not _segment_clear(from, path[0], radius)
	if geometry_changed or blocked:
		if _replan_delay > 0.0:
			return Vector2.ZERO
		if not _build(from, radius):
			return Vector2.ZERO
		_replan_delay = 0.25
	var offset: Vector2 = path[0] - from
	return offset.normalized() * minf(1.0, offset.length() / maxf(0.001, distance_budget))

func _current_walls() -> Array[Rect2]:
	var walls: Array[Rect2] = room.obstructions.duplicate()
	if is_instance_valid(room.b09_mechanics): walls.append_array(room.b09_mechanics.navigation_bounds())
	if is_instance_valid(room.b05_mechanics): walls.append_array(room.b05_mechanics.navigation_bounds())
	if bool(room.layout.get("b06_candidate", false)) and is_instance_valid(room.enemy_skills) and room.enemy_skills.b06 != null and room.enemy_skills.b06.has_method("navigation_obstructions"):
		walls.append_array(room.enemy_skills.b06.navigation_obstructions())
	return walls

func _sync_geometry(radius: float) -> void:
	var arena: Rect2 = room.ARENA
	var ground: PackedVector2Array = room.ground_polygon
	if _cached_walls == _walls and _cached_arena == arena and _cached_ground == ground and _cached_radius == radius:
		return
	_cached_walls.assign(_walls)
	_cached_arena = arena
	_cached_ground = ground.duplicate()
	_cached_radius = radius
	_graph = null
	_points.clear()
	_boxes.clear()
	for wall: Rect2 in _walls: _boxes.append(wall.grow(radius + 0.25))

func _build(from: Vector2, radius: float) -> bool:
	path.clear()
	_walls.assign(_current_walls())
	_sync_geometry(radius)
	route_searches += 1
	if not room.valid_ground(goal, radius):
		cancel()
		return false
	if _segment_clear(from, goal, radius):
		path.append(goal)
		return true
	if _graph == null:
		_build_graph(radius)
	# Only click endpoints change; retain all fixed corner-to-corner links.
	for endpoint: int in [0, 1]:
		if _graph.has_point(endpoint): _graph.remove_point(endpoint)
	_graph.add_point(0, from)
	_graph.add_point(1, goal)
	for index: int in _points.size():
		if _segment_clear(from, _points[index], radius): _graph.connect_points(0, index + 2)
		if _segment_clear(goal, _points[index], radius): _graph.connect_points(1, index + 2)
	path = _graph.get_point_path(0, 1)
	if path.size() < 2:
		cancel()
		return false
	path.remove_at(0)
	return true

func _build_graph(radius: float) -> void:
	var arena: Rect2 = room.ARENA.grow(-radius)
	for wall: Rect2 in _walls:
		for side: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			var corner := Vector2(wall.position.x if side.x < 0 else wall.end.x, wall.position.y if side.y < 0 else wall.end.y)
			for margin: float in [4.0, 0.5]:
				var point: Vector2 = corner + side * (radius + margin)
				point = Vector2(clampf(point.x, arena.position.x, arena.end.x), clampf(point.y, arena.position.y, arena.end.y))
				if room.valid_ground(point, radius + 0.25):
					if not _points.has(point): _points.append(point)
					break
	_graph = AStar2D.new()
	_graph.reserve_space(_points.size() + 2)
	for index: int in _points.size(): _graph.add_point(index + 2, _points[index])
	for index: int in _points.size():
		for next: int in range(index + 1, _points.size()):
			if _segment_clear(_points[index], _points[next], radius): _graph.connect_points(index + 2, next + 2)
	graph_builds += 1

func _segment_clear(from: Vector2, to: Vector2, radius: float) -> bool:
	if _visibility._visible(from, to, _boxes) and room.blocked_fraction(from, to, radius + 0.25) >= 1.0:
		return true
	# Actual movement has rounded circle/rectangle contact. The conservative
	# square graph may contain a legal player clicked immediately beside a
	# corner. Check just these endpoint cases against the real circle clearance
	# so a new click can escape it, without relaxing other graph links.
	var rounded_endpoint: bool = false
	for wall: Rect2 in _walls:
		if wall.grow(radius + 0.25).has_point(from) or wall.grow(radius + 0.25).has_point(to):
			rounded_endpoint = true
			break
	if not rounded_endpoint or not room.valid_ground(from, radius) or not room.valid_ground(to, radius):
		return false
	if room.blocked_fraction(from, to) < 1.0 or not _visibility._visible(from, to, _walls):
		return false
	var offset: Vector2 = to - from
	var length_squared: float = offset.length_squared()
	# A swept circle outside a rectangle can touch only an endpoint/edge or a
	# corner. Endpoints are validated above; corner-to-segment distances give
	# exact rounded clearance without sampling an entire long route per frame.
	for wall: Rect2 in _walls:
		for corner: Vector2 in [wall.position, Vector2(wall.end.x, wall.position.y), wall.end, Vector2(wall.position.x, wall.end.y)]:
			var fraction: float = clampf((corner - from).dot(offset) / maxf(0.00001, length_squared), 0.0, 1.0)
			if corner.distance_squared_to(from + offset * fraction) < radius * radius:
				return false
	return true
