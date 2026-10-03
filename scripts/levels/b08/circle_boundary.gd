extends RefCounted
## B08-only circular ground footprints in a simple outer ring minus hole rings.
## Rings keep their authored concavity; winding direction does not matter.
## Boundary tangency is legal, with only this world-unit rounding allowance.
const CLEARANCE_EPSILON := 0.001

static func contains(outer: PackedVector2Array, holes: Array, at: Vector2, radius: float = 0.0) -> bool:
	if not _valid_input(outer,holes,at,radius): return false
	return _contains_unchecked(outer,holes,at,radius)

## The whole swept circle must fit, including between the movement endpoints.
## In particular, neither a thin hole nor a concave tip can be skipped by steps.
static func segment_clear(outer: PackedVector2Array, holes: Array, from: Vector2, to: Vector2, radius: float = 0.0) -> bool:
	if not _valid_input(outer,holes,from,radius) or not to.is_finite(): return false
	if not _contains_unchecked(outer,holes,from,radius) or not _contains_unchecked(outer,holes,to,radius): return false
	if from == to: return true
	if not is_finite(from.distance_squared_to(to)): return false
	if not _segment_ring_clear(outer,from,to,radius): return false
	for hole: PackedVector2Array in holes:
		if not _segment_ring_clear(hole,from,to,radius): return false
	# At radius zero, zero boundary distance alone cannot distinguish crossing
	# from legal tangency. Test every interval split by exact boundary crossings.
	if radius <= CLEARANCE_EPSILON:
		return _center_segment_inside(outer,holes,from,to)
	return true

static func _valid_input(outer: PackedVector2Array, holes: Array, at: Vector2, radius: float) -> bool:
	if not at.is_finite() or not is_finite(radius) or radius < 0.0: return false
	if not _valid_ring(outer): return false
	for hole: Variant in holes:
		if not hole is PackedVector2Array or not _valid_ring(hole): return false
	return true

static func _valid_ring(ring: PackedVector2Array) -> bool:
	if ring.size() < 3: return false
	for point: Vector2 in ring:
		if not point.is_finite(): return false
	var twice_area := 0.0
	for index in ring.size():
		twice_area += (ring[index]-ring[0]).cross(ring[(index+1)%ring.size()]-ring[0])
	return is_finite(twice_area) and absf(twice_area) > CLEARANCE_EPSILON*CLEARANCE_EPSILON

static func _contains_unchecked(outer: PackedVector2Array, holes: Array, at: Vector2, radius: float) -> bool:
	var outer_distance := _point_ring_distance(outer,at)
	if not is_finite(outer_distance) or outer_distance+CLEARANCE_EPSILON < radius: return false
	if not Geometry2D.is_point_in_polygon(at,outer) and outer_distance > CLEARANCE_EPSILON: return false
	for hole: PackedVector2Array in holes:
		var hole_distance := _point_ring_distance(hole,at)
		if not is_finite(hole_distance) or hole_distance+CLEARANCE_EPSILON < radius: return false
		if Geometry2D.is_point_in_polygon(at,hole) and hole_distance > CLEARANCE_EPSILON: return false
	return true

static func _point_ring_distance(ring: PackedVector2Array, at: Vector2) -> float:
	var nearest := INF
	for index in ring.size():
		var closest := Geometry2D.get_closest_point_to_segment(at,ring[index],ring[(index+1)%ring.size()])
		nearest = minf(nearest,at.distance_to(closest))
	return nearest

static func _segment_ring_clear(ring: PackedVector2Array, from: Vector2, to: Vector2, radius: float) -> bool:
	for index in ring.size():
		var nearest := Geometry2D.get_closest_points_between_segments(from,to,ring[index],ring[(index+1)%ring.size()])
		var distance := nearest[0].distance_to(nearest[1])
		if not is_finite(distance) or distance+CLEARANCE_EPSILON < radius: return false
	return true

static func _center_segment_inside(outer: PackedVector2Array, holes: Array, from: Vector2, to: Vector2) -> bool:
	var cuts: Array[float] = [0.0,1.0]
	_append_crossings(cuts,outer,from,to)
	for hole: PackedVector2Array in holes: _append_crossings(cuts,hole,from,to)
	cuts.sort()
	for index in range(1,cuts.size()):
		var middle := from.lerp(to,(cuts[index-1]+cuts[index])*0.5)
		if not _contains_unchecked(outer,holes,middle,0.0): return false
	return true

static func _append_crossings(cuts: Array[float], ring: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	var travel := to-from
	var length_squared := travel.length_squared()
	for index in ring.size():
		var a := ring[index]
		var b := ring[(index+1)%ring.size()]
		var crossing: Variant = Geometry2D.segment_intersects_segment(from,to,a,b)
		if crossing is Vector2:
			cuts.append(clampf((crossing-from).dot(travel)/length_squared,0.0,1.0))
		# Collinear boundary segments may have no unique intersection. Their
		# endpoint projections also split any stretch travelled along the rim.
		cuts.append(clampf((a-from).dot(travel)/length_squared,0.0,1.0))
