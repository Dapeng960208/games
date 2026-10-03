extends RefCounted
## A simple ground outline shared by feet, clicks and swept attacks.
## Metadata is painted in image coordinates; WorldArt supplies world points.
static var _outline := PackedVector2Array()
static var _convex := true
static var _insets: Dictionary = {}

static func _prepare(points: PackedVector2Array) -> void:
	if points == _outline: return
	_outline = points.duplicate()
	_insets.clear()
	_convex = true
	for index: int in points.size():
		var edge := points[(index+1)%points.size()]-points[index]
		var next := points[(index+2)%points.size()]-points[(index+1)%points.size()]
		if edge.cross(next) < -0.001:
			_convex = false
			break

static func _inset(points: PackedVector2Array, radius: float) -> Array[PackedVector2Array]:
	_prepare(points)
	if not _insets.has(radius):
		# A room has a few actor/projectile radii; bound the cache for tool inputs.
		if _insets.size() >= 32: _insets.clear()
		_insets[radius] = Geometry2D.offset_polygon(points,-radius,Geometry2D.JOIN_ROUND) if radius > 0.0 else [points]
	var result: Array[PackedVector2Array] = []
	result.assign(_insets[radius])
	return result

static func bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var result := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points: result = result.expand(point)
	return result

static func contains(points: PackedVector2Array, at: Vector2, radius: float) -> bool:
	if points.size() < 3 or not at.is_finite() or not is_finite(radius) or radius < 0.0: return false
	_prepare(points)
	if not _convex:
		if not Geometry2D.is_point_in_polygon(at,points): return false
		for index: int in points.size():
			var nearest := Geometry2D.get_closest_point_to_segment(at,points[index],points[(index+1)%points.size()])
			if at.distance_to(nearest) < radius-0.001: return false
		return true
	for index: int in points.size():
		var edge: Vector2 = points[(index+1)%points.size()]-points[index]
		if edge.cross(at-points[index])/edge.length() < radius-0.001: return false
	return true

static func clamp_point(points: PackedVector2Array, at: Vector2, radius: float) -> Vector2:
	if contains(points, at, radius): return at
	if not _convex:
		var nearest := at
		var distance := INF
		for polygon: PackedVector2Array in _inset(points,radius+0.01):
			for index: int in polygon.size():
				var candidate := Geometry2D.get_closest_point_to_segment(at,polygon[index],polygon[(index+1)%polygon.size()])
				var squared := candidate.distance_squared_to(at)
				if squared < distance:
					nearest = candidate
					distance = squared
		return nearest
	var result: Vector2 = at
	# Project onto inset half-planes. The outlines are convex and have no narrow
	# acute corners, so a few passes also resolve simultaneous corner contacts.
	for iteration: int in 12:
		var changed := false
		for index: int in points.size():
			var edge: Vector2 = points[(index+1)%points.size()]-points[index]
			var normal := Vector2(-edge.y, edge.x).normalized()
			var missing: float = radius-normal.dot(result-points[index])
			if missing > 0.00001:
				result += normal*missing
				changed = true
		if not changed: break
	return result

static func clear_fraction(points: PackedVector2Array, from: Vector2, to: Vector2, radius: float) -> float:
	_prepare(points)
	if not _convex:
		if not contains(points,from,radius): return 0.0
		var displacement := to-from
		if displacement.is_zero_approx(): return 1.0
		var polygons := _inset(points,radius)
		var first := 1.0
		for polygon: PackedVector2Array in polygons:
			for index: int in polygon.size():
				var crossing: Variant = Geometry2D.segment_intersects_segment(from,to,polygon[index],polygon[(index+1)%polygon.size()])
				if crossing == null: continue
				var fraction := clampf((Vector2(crossing)-from).dot(displacement)/displacement.length_squared(),0,1)
				# A tangent or an inward start does not leave the walkable outline.
				var after := Vector2(crossing)+displacement.normalized()*0.02
				if polygons.any(func(shape: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(after,shape)): continue
				first = minf(first,fraction)
		return first
	var result := 1.0
	var offset: Vector2 = to-from
	for index: int in points.size():
		var edge: Vector2 = points[(index+1)%points.size()]-points[index]
		var normal := Vector2(-edge.y, edge.x).normalized()
		var speed: float = normal.dot(offset)
		if speed < -0.00001:
			result = minf(result, (normal.dot(from-points[index])-radius)/-speed)
	return clampf(result, 0.0, 1.0)
