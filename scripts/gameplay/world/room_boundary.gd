extends RefCounted
## A single convex ground outline shared by feet, clicks and swept attacks.
## Metadata is painted in image coordinates; WorldArt supplies world points.

static func bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var result := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points: result = result.expand(point)
	return result

static func contains(points: PackedVector2Array, at: Vector2, radius: float) -> bool:
	for index: int in points.size():
		var edge: Vector2 = points[(index+1)%points.size()]-points[index]
		if edge.cross(at-points[index])/edge.length() < radius-0.001: return false
	return true

static func clamp_point(points: PackedVector2Array, at: Vector2, radius: float) -> Vector2:
	if contains(points, at, radius): return at
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
	var result := 1.0
	var offset: Vector2 = to-from
	for index: int in points.size():
		var edge: Vector2 = points[(index+1)%points.size()]-points[index]
		var normal := Vector2(-edge.y, edge.x).normalized()
		var speed: float = normal.dot(offset)
		if speed < -0.00001:
			result = minf(result, (normal.dot(from-points[index])-radius)/-speed)
	return clampf(result, 0.0, 1.0)
