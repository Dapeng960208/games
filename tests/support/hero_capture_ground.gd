extends RefCounted
## Choose from the current mapped room, not the pre-0.58 blueprint coordinates.
static func find_lane(room: Node2D, reach: float = 155.0) -> Vector2:
	var bounds: Rect2=room.ARENA
	var candidates: Array[Vector2]=[]
	for y: int in range(ceili(bounds.position.y+reach),floori(bounds.end.y-reach),40):
		for x: int in range(ceili(bounds.position.x+reach),floori(bounds.end.x-reach),40):
			candidates.append(Vector2(x,y))
	var center:=bounds.get_center()
	candidates.sort_custom(func(a: Vector2,b: Vector2)->bool: return a.distance_squared_to(center)<b.distance_squared_to(center))
	for candidate: Vector2 in candidates:
		if not room.valid_ground(candidate,24.0): continue
		var valid:=true
		for index: int in 8:
			var endpoint:=candidate+Vector2.from_angle(index*PI/4.0)*reach
			if not room.valid_ground(endpoint,24.0) or room.blocked_fraction(candidate,endpoint,24.0)<.999:
				valid=false
				break
		if valid: return candidate
	return Vector2.ZERO
