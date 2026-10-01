extends RefCounted
## One compact visibility route per click. Only a changed obstruction or an
## authored displacement invalidates it; movement never searches every frame.

var room: Node2D
var path := PackedVector2Array()
var goal := Vector2(INF, INF)
var _walls: Array[Rect2] = []
var _replan_delay: float = 0.0
var route_searches: int = 0

func configure(host: Node2D) -> void:
	room = host
	cancel()

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
		path.remove_at(0)
	if path.is_empty():
		cancel()
		return Vector2.ZERO
	# Every proposed step still passes through room.move_actor. Refuse a stale
	# segment until a moved/broken prop has produced a new legal route.
	var geometry_changed: bool = _walls != room.obstructions
	var blocked: bool = not _segment_clear(from, path[0], radius)
	if geometry_changed or blocked:
		if _replan_delay > 0.0:
			return Vector2.ZERO
		if not _build(from, radius):
			return Vector2.ZERO
		_replan_delay = 0.25
	var offset: Vector2 = path[0] - from
	return offset.normalized() * minf(1.0, offset.length() / maxf(0.001, distance_budget))

func _build(from: Vector2, radius: float) -> bool:
	path.clear()
	_walls.assign(room.obstructions)
	route_searches += 1
	if not room.valid_ground(goal, radius):
		cancel()
		return false
	if _segment_clear(from, goal, radius):
		path.append(goal)
		return true
	var points: Array[Vector2] = [from, goal]
	var arena: Rect2 = room.ARENA.grow(-radius)
	for wall: Rect2 in _walls:
		for side: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
			var corner := Vector2(wall.position.x if side.x < 0 else wall.end.x, wall.position.y if side.y < 0 else wall.end.y)
			for margin: float in [4.0, 0.5]:
				var point: Vector2 = corner + side * (radius + margin)
				point = Vector2(clampf(point.x, arena.position.x, arena.end.x), clampf(point.y, arena.position.y, arena.end.y))
				if room.valid_ground(point, radius + 0.25):
					if not points.has(point): points.append(point)
					break
	var graph := AStar2D.new()
	for index: int in points.size():
		graph.add_point(index, points[index])
	for index: int in points.size():
		for next: int in range(index + 1, points.size()):
			if _segment_clear(points[index], points[next], radius):
				graph.connect_points(index, next)
	path = graph.get_point_path(0, 1)
	if path.size() < 2:
		cancel()
		return false
	path.remove_at(0)
	return true

func _segment_clear(from: Vector2, to: Vector2, radius: float) -> bool:
	if room.blocked_fraction(from, to, radius + 0.25) >= 1.0:
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
	if room.blocked_fraction(from, to) < 1.0:
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
