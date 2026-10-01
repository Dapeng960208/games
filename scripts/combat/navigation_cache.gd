extends RefCounted
## Corner visibility graphs are geometry, not per-enemy/per-frame work.
## Keep exact collision radii and rebuild only when a prop moves/breaks or a
## room changes. Native AStar handles the repeated shortest-path searches.

var _walls: Array[Rect2] = []
var _arena := Rect2()
const GroundBoundary = preload("res://scripts/world/room_boundary.gd")
var _ground_polygon := PackedVector2Array()
var _graphs: Dictionary = {}
var graph_builds: int = 0
var route_searches: int = 0
var route_cache_hits: int = 0

func prepare(walls: Array[Rect2], arena: Rect2, radii: Array = [12.0, 14.0, 18.0, 24.0], ground: PackedVector2Array = PackedVector2Array()) -> void:
	_sync_geometry(walls, arena, ground)
	for radius: float in radii:
		_graph(radius)

func direction(from: Vector2, to: Vector2, radius: float, walls: Array[Rect2], arena: Rect2, ground: PackedVector2Array = PackedVector2Array()) -> Vector2:
	_sync_geometry(walls, arena, ground)
	var data: Dictionary = _graph(radius)
	var boxes: Array[Rect2] = data.boxes
	# A player can stand closer to cover than a larger enemy. Route to a legal
	# nearby attack position instead of searching forever for an impossible
	# endpoint inside the enemy's expanded collision rectangle.
	if not _point_clear(to,boxes,data.allowed):
		if data.requested_goal != to:
			data.requested_goal=to
			data.walkable_goal=_nearby_clear_point(to,from,boxes,data.allowed,radius)
		to=data.walkable_goal
		if not to.is_finite():
			return Vector2.ZERO
	# Movement uses rounded circle/rectangle corners. A separated enemy can
	# legally end in that round corner, inside the more conservative AStar box.
	# Step outward to its nearest legal graph point rather than become stuck.
	if not _point_clear(from,boxes,data.allowed):
		var escape: Vector2=_nearby_clear_point(from,to,boxes,data.allowed,radius)
		return from.direction_to(escape) if escape.is_finite() else Vector2.ZERO
	if _visible(from, to, boxes):
		return from.direction_to(to)
	# Nearby actors usually follow the same corner for several frames. Reuse
	# that corner only while both endpoint links are still clear. The tiny cells
	# do not snap movement and cannot let an actor cut through a prop.
	var key := Vector4i(floori(from.x / 24.0), floori(from.y / 24.0), floori(to.x / 24.0), floori(to.y / 24.0))
	var routes: Dictionary = data.routes
	if routes.has(key):
		var route: Dictionary = routes[key]
		var waypoint: Vector2 = route.waypoint
		var approach: Vector2=waypoint-route.origin
		# Some moving objectives steer at 5Hz. If they crossed the cached corner
		# between queries, never pull them back into a same-cell oscillation.
		var still_ahead: bool=(waypoint-from).dot(approach)>0.01
		if still_ahead and from.distance_squared_to(waypoint) > 64.0 and _visible(from, waypoint, boxes) and _visible(route.target, to, boxes):
			route_cache_hits += 1
			return from.direction_to(waypoint)
	var graph: AStar2D = data.graph
	# Only the moving endpoints change. Never connect through a stale obstacle:
	# the geometry sync above also runs for removals and in-place replacements.
	if graph.has_point(0):
		graph.remove_point(0)
	graph.add_point(0, from)
	var goal: Vector2 = data.goal
	if not graph.has_point(1) or goal.distance_squared_to(to) > 144.0 or not _visible(goal, to, boxes):
		if graph.has_point(1):
			graph.remove_point(1)
		graph.add_point(1, to)
		for id: int in range(2, data.points.size() + 2):
			if _visible(to, data.points[id - 2], boxes):
				graph.connect_points(1, id)
		data.goal = to
	for id: int in range(2, data.points.size() + 2):
		if _visible(from, data.points[id - 2], boxes):
			graph.connect_points(0, id)
	var path: PackedVector2Array = graph.get_point_path(0, 1)
	route_searches += 1
	if path.size() > 1:
		if routes.size() >= 512:
			routes.clear()
		routes[key] = {"waypoint":path[1],"target":to,"origin":from}
	return from.direction_to(path[1]) if path.size() > 1 else Vector2.ZERO

func _sync_geometry(walls: Array[Rect2], arena: Rect2, ground: PackedVector2Array) -> void:
	if _arena == arena and _walls == walls and _ground_polygon == ground:
		return
	_walls.assign(walls)
	_arena = arena
	_ground_polygon = ground
	_graphs.clear()

func _graph(radius: float) -> Dictionary:
	if _graphs.has(radius):
		return _graphs[radius]
	var boxes: Array[Rect2] = []
	var points: Array[Vector2] = []
	var allowed: Rect2 = _arena.grow(-radius)
	for wall: Rect2 in _walls:
		boxes.append(wall.grow(radius))
	for wall: Rect2 in _walls:
		for side: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var corner:=Vector2(wall.position.x if side.x<0 else wall.end.x,wall.position.y if side.y<0 else wall.end.y)
			# Keep the comfortable 5px steering margin where it fits, but don't
			# delete a real narrow passage beside the arena or another obstacle.
			for margin: float in [5.0,0.25]:
				var point: Vector2=corner+side*(radius+margin)
				point=Vector2(clampf(point.x,allowed.position.x,allowed.end.x),clampf(point.y,allowed.position.y,allowed.end.y))
				if _point_clear(point,boxes,allowed):
					if not points.has(point): points.append(point)
					break
	var graph := AStar2D.new()
	graph.reserve_space(points.size() + 2)
	for index: int in points.size():
		graph.add_point(index + 2, points[index])
	for index: int in points.size():
		for next: int in range(index + 1, points.size()):
			if _visible(points[index], points[next], boxes):
				graph.connect_points(index + 2, next + 2)
	var data := {"graph":graph,"points":points,"boxes":boxes,"allowed":allowed,"goal":Vector2(INF,INF),"routes":{},"requested_goal":Vector2(INF,INF),"walkable_goal":Vector2(INF,INF)}
	_graphs[radius] = data
	graph_builds += 1
	return data

func _point_clear(point: Vector2, boxes: Array[Rect2], allowed: Rect2) -> bool:
	if not _ground_polygon.is_empty() and not GroundBoundary.contains(_ground_polygon, point, (_arena.size.x-allowed.size.x)*.5): return false
	if point.x<allowed.position.x or point.x>allowed.end.x or point.y<allowed.position.y or point.y>allowed.end.y:
		return false
	for box: Rect2 in boxes:
		if point.x>=box.position.x and point.x<=box.end.x and point.y>=box.position.y and point.y<=box.end.y:
			return false
	return true

func _nearby_clear_point(point: Vector2, preference: Vector2, boxes: Array[Rect2], allowed: Rect2, radius: float) -> Vector2:
	var candidates: Array[Vector2]=[Vector2(clampf(point.x,allowed.position.x,allowed.end.x),clampf(point.y,allowed.position.y,allowed.end.y))]
	if not _ground_polygon.is_empty(): candidates[0] = GroundBoundary.clamp_point(_ground_polygon, candidates[0], radius+.1)
	for box: Rect2 in boxes:
		if box.grow(0.01).has_point(point):
			candidates.append_array([Vector2(box.position.x-1.0,point.y),Vector2(box.end.x+1.0,point.y),Vector2(point.x,box.position.y-1.0),Vector2(point.x,box.end.y+1.0)])
	for offset: Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
		candidates.append(point+offset*(radius+6.0))
	var best := Vector2(INF,INF)
	var score: float=INF
	for candidate: Vector2 in candidates:
		if not _point_clear(candidate,boxes,allowed) or not _visible(point,candidate,_walls):
			continue
		var distance: float=point.distance_squared_to(candidate)+candidate.distance_squared_to(preference)*0.000001
		if distance<score:
			score=distance
			best=candidate
	return best

func _visible(from: Vector2, to: Vector2, boxes: Array[Rect2]) -> bool:
	# A boolean early-out slab query avoids calculating a fractional impact for
	# every wall, which the damage sweep still correctly does in MineRoom.
	var offset: Vector2 = to - from
	for box: Rect2 in boxes:
		var near: float = 0.0
		var far: float = 1.0
		if absf(offset.x) < 0.00001:
			if from.x < box.position.x or from.x > box.end.x:
				continue
		else:
			var first: float = (box.position.x - from.x) / offset.x
			var last: float = (box.end.x - from.x) / offset.x
			near = maxf(near, minf(first, last))
			far = minf(far, maxf(first, last))
			if near > far:
				continue
		if absf(offset.y) < 0.00001:
			if from.y < box.position.y or from.y > box.end.y:
				continue
		else:
			var first: float = (box.position.y - from.y) / offset.y
			var last: float = (box.end.y - from.y) / offset.y
			near = maxf(near, minf(first, last))
			far = minf(far, maxf(first, last))
			if near > far:
				continue
		return false
	return true
