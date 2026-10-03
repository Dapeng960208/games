extends RefCounted
## L43 candidate ground uses one concave outer ring and its authored cloud hole.
const Circle=preload("res://scripts/levels/b08/circle_boundary.gd")
var outer := PackedVector2Array()
var holes: Array=[]
var entry := Vector2.ZERO
var bounds := Rect2()

func configure(outline: PackedVector2Array, openings: Array, entry_point: Vector2) -> bool:
	# Reject invalid topology once, before any runtime circle or path query.
	# Failed reconfiguration cannot leave an older floor active.
	outer=PackedVector2Array(); holes=[]; bounds=Rect2(); entry=Vector2.ZERO
	if not _simple_ring(outline): return false
	for index in openings.size():
		var hole: Variant=openings[index]
		if not hole is PackedVector2Array or not _simple_ring(hole): return false
		if not Geometry2D.is_point_in_polygon(hole[0],outline) or _rings_touch(outline,hole): return false
		for previous in index:
			var other: PackedVector2Array=openings[previous]
			if _rings_touch(hole,other) or Geometry2D.is_point_in_polygon(hole[0],other) or Geometry2D.is_point_in_polygon(other[0],hole): return false
	if not Circle.contains(outline,openings,entry_point,40): return false
	outer=outline.duplicate()
	for hole: PackedVector2Array in openings: holes.append(hole.duplicate())
	entry=entry_point
	bounds=Rect2(outer[0],Vector2.ZERO)
	for point: Vector2 in outer: bounds=bounds.expand(point)
	return true

func _simple_ring(ring: PackedVector2Array) -> bool:
	if ring.size()<3: return false
	for point: Vector2 in ring:
		if not point.is_finite(): return false
	var twice_area:=0.0
	var epsilon_squared: float=Circle.CLEARANCE_EPSILON*Circle.CLEARANCE_EPSILON
	for index in ring.size():
		var a:=ring[index]
		var b:=ring[(index+1)%ring.size()]
		var c:=ring[(index+2)%ring.size()]
		if a.distance_squared_to(b)<=epsilon_squared: return false
		# Adjacent edges share a vertex, but cannot double back over each other.
		if a.distance_squared_to(Geometry2D.get_closest_point_to_segment(a,b,c))<=epsilon_squared or c.distance_squared_to(Geometry2D.get_closest_point_to_segment(c,a,b))<=epsilon_squared: return false
		twice_area+=(a-ring[0]).cross(b-ring[0])
		for other in range(index+2,ring.size()):
			if index==0 and other==ring.size()-1: continue
			if _edges_touch(a,b,ring[other],ring[(other+1)%ring.size()]): return false
	return is_finite(twice_area) and absf(twice_area)>epsilon_squared

func _rings_touch(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for index in first.size():
		for other in second.size():
			if _edges_touch(first[index],first[(index+1)%first.size()],second[other],second[(other+1)%second.size()]): return true
	return false

func _edges_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var closest:=Geometry2D.get_closest_points_between_segments(a,b,c,d)
	return closest[0].distance_squared_to(closest[1])<=Circle.CLEARANCE_EPSILON*Circle.CLEARANCE_EPSILON

func contains(at: Vector2, radius: float=0.0) -> bool:
	return Circle.contains(outer,holes,at,radius)

func segment_clear(from: Vector2, to: Vector2, radius: float=0.0) -> bool:
	return Circle.segment_clear(outer,holes,from,to,radius)

func blocked_fraction(from: Vector2, to: Vector2, radius: float=0.0) -> float:
	if not contains(from,radius) or not to.is_finite(): return 0.0
	if segment_clear(from,to,radius): return 1.0
	# Whole-prefix validity is monotone even when a long path re-enters ground.
	var low:=0.0
	var high:=1.0
	for _step in 18:
		var middle: float=(low+high)*0.5
		if segment_clear(from,from.lerp(to,middle),radius): low=middle
		else: high=middle
	return low

func move(from: Vector2, offset: Vector2, radius: float) -> Vector2:
	if not contains(from,radius) or not offset.is_finite(): return from
	var result:=from
	var steps:=maxi(1,ceili(offset.length()/6.0))
	var step:=offset/steps
	for _index in steps:
		var target:=result+step
		if segment_clear(result,target,radius): result=target
		elif segment_clear(result,result+Vector2(step.x,0),radius): result.x+=step.x
		elif segment_clear(result,result+Vector2(0,step.y),radius): result.y+=step.y
	return result

func clamp_point(at: Vector2, radius: float) -> Vector2:
	if contains(at,radius): return at
	if not at.is_finite() or not is_finite(radius) or radius<0: return entry
	var closest:=entry
	var distance:=INF
	var rings: Array=[outer]
	rings.append_array(holes)
	for ring: PackedVector2Array in rings:
		for index in ring.size():
			var a: Vector2=ring[index]
			var b: Vector2=ring[(index+1)%ring.size()]
			var foot:=Geometry2D.get_closest_point_to_segment(at,a,b)
			var normal: Vector2=(b-a).normalized().orthogonal()*(radius+.01)
			for point: Vector2 in [foot+normal,foot-normal,a+a.direction_to(at)*(radius+.01)]:
				var separation:=point.distance_squared_to(at)
				if separation<distance and contains(point,radius): closest=point; distance=separation
	# Exact circular validation also checks any corner-projection candidate.
	if not contains(closest,radius): return at
	return closest
