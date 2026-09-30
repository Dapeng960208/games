class_name ProjectileVisualPath
extends RefCounted
## Frozen presentation coordinates only. No target references, homing, collision
## overrides or damage callbacks enter this path after the real shot is created.

const MAX_SCANNED_ACTORS := 64
const MAX_BODY_POINTS := 6
const BLEND_DISTANCE := 96.0
## A close target must not turn a level rifle into a steep ground shot. If the
## muzzle-to-body chord is too steep or changes apparent speed too much, retain
## a level barrel ray instead. This choice is frozen when the shot is created.
const MAX_GUN_AIM_ANGLE := PI / 6.0
const MIN_GUN_BODY_DISTANCE := 48.0
## Encloses the longest 28px needle tail, crystal shards and antialiased widths.
const DRAW_RADIUS := 32.0

static func snapshot(room: Node2D, origin: Vector2, direction: Vector2, distance: float, pierce: int, muzzle: Vector2, straight: bool = false) -> Dictionary:
	if not is_instance_valid(room) or not origin.is_finite() or not muzzle.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(distance) or distance <= 0.0:
		return {}
	var forward: Vector2 = direction.normalized()
	# Match the production projectile's wall radius and forward obstruction ray.
	var stop: float = distance * room.blocked_fraction(origin, origin + forward * distance, 2.0)
	if stop <= .001:
		if straight: return _straight_path(origin,forward,0.0,origin,forward,0,0,false,false)
		return {"origin":origin,"direction":forward,"stop_distance":0.0,"knots":[{"distance":0.0,"point":origin}],"candidate_count":0,"scanned":0}
	var candidates: Array[Dictionary] = []
	var scanned := 0
	for target: Node2D in room.enemies.get_children():
		if scanned >= MAX_SCANNED_ACTORS: break
		scanned += 1
		if not target.is_alive() or target.is_queued_for_deletion(): continue
		var relative: Vector2 = target.position - origin
		var along: float = relative.dot(forward)
		var radius: float = float(target.navigation_radius) + 4.0
		var closest: Vector2 = origin + forward * clampf(along,0.0,stop)
		var perpendicular_squared: float = relative.length_squared() - along * along
		if closest.distance_squared_to(target.position) > radius * radius or not room.has_line_of_sight(origin,target.position): continue
		var entry: float = maxf(0.0,along - sqrt(maxf(0.0,radius * radius - perpendicular_squared)))
		if entry >= stop: continue
		candidates.append({"distance":entry,"target":target})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var body_points: Array[Dictionary] = []
	var limit: int = 1 if straight else mini(MAX_BODY_POINTS,maxi(1,pierce+1))
	for candidate: Dictionary in candidates:
		if body_points.size() >= limit: break
		var at: float = maxf(.001,float(candidate.distance))
		if not body_points.is_empty() and at <= float(body_points[-1].distance)+.001: continue
		var target: Node2D = candidate.target
		var point: Vector2 = target.position + Vector2(0,target.body_bounds.end.y-target.body_bounds.size.y*.53)
		if target.has_method("impact_anchor"):
			var surface: Dictionary = target.impact_anchor(forward)
			if surface.get("anchor") is WeakRef and surface.get("local_offset") is Vector2:
				var visual: Object = surface.anchor.get_ref()
				if is_instance_valid(visual) and visual is Node2D:
					point = room.to_local(visual.to_global(surface.local_offset))
		# Store only the value snapshot. A moved/dead target never bends a shot.
		body_points.append({"distance":at,"point":point})
	if straight:
		return _gun_snapshot(room,origin,forward,stop,muzzle,body_points,scanned)
	var muzzle_offset: Vector2 = muzzle-origin
	# A rendered barrel beside a wall must not start on the other side of it.
	muzzle_offset *= room.blocked_fraction(origin,muzzle,2.0)
	var source_along: float = muzzle_offset.dot(forward)
	var first_along: float = stop if body_points.is_empty() else (Vector2(body_points[0].point)-origin).dot(forward)
	var capped_source: float = minf(source_along,minf(stop,first_along))
	muzzle_offset += forward * (capped_source-source_along)
	var knots: Array[Dictionary] = [{"distance":0.0,"point":origin+muzzle_offset}]
	var previous_along: float = capped_source
	for item: Dictionary in body_points:
		var offset: Vector2 = Vector2(item.point)-origin
		var projected: float = offset.dot(forward)
		var monotonic: float = clampf(projected,previous_along,stop)
		item.point = origin+offset+forward*(monotonic-projected)
		previous_along = monotonic
		knots.append(item)
	var last_distance: float = float(knots[-1].distance)
	var terminal: float = minf(stop,maxf(BLEND_DISTANCE,maxf(last_distance+BLEND_DISTANCE,previous_along+.001)))
	knots.append({"distance":terminal,"point":origin+forward*terminal})
	var plane_fallback: bool = false
	for index in range(1,knots.size()):
		if room.blocked_fraction(knots[index-1].point,knots[index].point,2.0) < 1.0:
			# The collider ray can pass beside a corner while an elevated display
			# chord crosses it. Never draw that chord through the obstacle.
			knots = [{"distance":0.0,"point":origin},{"distance":stop,"point":origin+forward*stop}]
			plane_fallback = true
			break
	return {"origin":origin,"direction":forward,"stop_distance":stop,"knots":knots,
		"candidate_count":body_points.size(),"scanned":scanned,"plane_fallback":plane_fallback}

static func _gun_snapshot(room: Node2D, origin: Vector2, forward: Vector2, stop: float, muzzle: Vector2, body_points: Array[Dictionary], scanned: int) -> Dictionary:
	var muzzle_offset: Vector2 = (muzzle-origin)*room.blocked_fraction(origin,muzzle,2.0)
	var source_along: float = muzzle_offset.dot(forward)
	var first_along: float = stop if body_points.is_empty() else (Vector2(body_points[0].point)-origin).dot(forward)
	muzzle_offset += forward*(minf(source_along,minf(stop,first_along))-source_along)
	var source: Vector2 = origin+muzzle_offset
	var velocity: Vector2 = forward
	var body_locked := false
	if not body_points.is_empty():
		var first_distance: float = float(body_points[0].distance)
		var chord: Vector2 = Vector2(body_points[0].point)-source
		var rate: float = chord.length()/first_distance
		if first_distance >= MIN_GUN_BODY_DISTANCE and absf(forward.angle_to(chord)) <= MAX_GUN_AIM_ANGLE and rate >= .5 and rate <= 1.5:
			velocity = chord/first_distance
			body_locked = true
	# A rifle needle gets one line for its entire flight, including penetration.
	# If its visual height would put that line through cover, select a safe line
	# now; never bend it down to the floor later in the flight.
	var plane_fallback := false
	if room.blocked_fraction(source,source+velocity*stop,2.0) < 1.0:
		velocity = forward
		body_locked = false
		if room.blocked_fraction(source,source+velocity*stop,2.0) < 1.0:
			source = origin
			plane_fallback = true
	return _straight_path(origin,forward,stop,source,velocity,body_points.size(),scanned,plane_fallback,body_locked)

static func _straight_path(origin: Vector2, forward: Vector2, stop: float, source: Vector2, velocity: Vector2, candidates: int, scanned: int, plane_fallback: bool, body_locked: bool) -> Dictionary:
	return {"origin":origin,"direction":forward,"stop_distance":stop,
		"knots":[{"distance":0.0,"point":source},{"distance":stop,"point":source+velocity*stop}],
		"candidate_count":candidates,"scanned":scanned,"plane_fallback":plane_fallback,
		"straight":true,"display_source":source,"display_velocity":velocity,"body_locked":body_locked}

static func position_at(path: Dictionary, physical_position: Vector2) -> Vector2:
	if path.is_empty(): return physical_position
	var forward: Vector2 = path.direction
	var traveled: float = maxf(0.0,(physical_position-Vector2(path.origin)).dot(forward))
	if bool(path.get("straight",false)):
		return Vector2(path.display_source)+Vector2(path.display_velocity)*minf(traveled,float(path.stop_distance))
	var knots: Array = path.knots
	if knots.size() == 1: return knots[0].point
	for index in range(1,knots.size()):
		var end: Dictionary = knots[index]
		if traveled > float(end.distance): continue
		var start: Dictionary = knots[index-1]
		var progress: float = clampf((traveled-float(start.distance))/maxf(.001,float(end.distance)-float(start.distance)),0.0,1.0)
		return Vector2(start.point).lerp(end.point,progress)
	return physical_position

static func direction_at(path: Dictionary, physical_position: Vector2, fallback: Vector2) -> Vector2:
	if path.is_empty(): return fallback
	if bool(path.get("straight",false)):
		return Vector2(path.display_velocity).normalized()
	var forward: Vector2 = path.direction
	var tangent: Vector2 = position_at(path,physical_position+forward*.5)-position_at(path,physical_position-forward*.5)
	return tangent.normalized() if tangent.length_squared() > .00001 else fallback

static func draw_scale(room: Node2D, center: Vector2) -> float:
	if not is_instance_valid(room): return 0.0
	var arena: Rect2 = room.ARENA
	var clearance: float = minf(minf(center.x-arena.position.x,arena.end.x-center.x),minf(center.y-arena.position.y,arena.end.y-center.y))
	for box: Rect2 in room.obstructions:
		if box.has_point(center): return 0.0
		var nearest := Vector2(clampf(center.x,box.position.x,box.end.x),clampf(center.y,box.position.y,box.end.y))
		clearance = minf(clearance,center.distance_to(nearest))
	# A conservative disk bounds every tip/trail, for all eight display angles.
	# This also clips against newly moved cover without redirecting the flight.
	return clampf((clearance-.75)/DRAW_RADIUS,0.0,1.0)
