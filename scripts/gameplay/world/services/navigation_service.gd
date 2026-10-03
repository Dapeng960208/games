extends RefCounted
## Navigation behavior owned by this host.
## The host retains state and lifecycle; this service never owns its Node.
var host

func _init(context: Node) -> void:
	host = context

func valid_ground(at: Vector2, radius: float = 0.0) -> bool:
	if is_instance_valid(host.b09_mechanics) and host.b09_mechanics.blocks_ground(at,radius): return false
	if is_instance_valid(host.b05_mechanics) and host.b05_mechanics.blocks_ground(at,radius): return false
	if bool(host.layout.get("b06_candidate",false)) and is_instance_valid(host.enemy_skills) and host.enemy_skills.b06 != null and host.enemy_skills.b06.has_method("wall_blocks_point") and host.enemy_skills.b06.wall_blocks_point(at,radius): return false
	if not host.ground_polygon.is_empty() and not host.GroundBoundary.contains(host.ground_polygon, at, radius):
		return false
	if host.ground_polygon.is_empty() and at != host.clamp_actor(at, radius):
		return false
	for wall: Rect2 in host.obstructions:
		var nearest = Vector2(clampf(at.x, wall.position.x, wall.end.x), clampf(at.y, wall.position.y, wall.end.y))
		if wall.has_point(at) or nearest.distance_squared_to(at) < radius * radius:
			return false
	return true

func move_actor(from: Vector2, displacement: Vector2, radius: float) -> Vector2:
	var result: Vector2 = host.clamp_actor(from, radius)
	var steps: int = maxi(1, int(ceil(displacement.length() / 4.0)))
	var part: Vector2 = displacement / float(steps)
	for i in range(steps):
		var next: Vector2 = host.clamp_actor(result + part, radius)
		if host.valid_ground(next, radius):
			result = next
		else:
			# Approach the actual rounded contact first. Rejecting an entire 4px
			# step made equal diagonal inputs stop at different distances on each
			# axis, which the tracking camera exposed as a sudden corner snap.
			result = host._movement_contact(result, next, radius)
			var horizontal = Vector2(next.x, result.y)
			var vertical = Vector2(result.x, next.y)
			if host.valid_ground(horizontal, radius):
				result = horizontal
			if host.valid_ground(Vector2(result.x, vertical.y), radius):
				result.y = vertical.y
	return result

func _movement_contact(from: Vector2, to: Vector2, radius: float) -> Vector2:
	var clear: float = 0.0
	var blocked: float = 1.0
	for iteration: int in 12:
		var fraction: float = (clear + blocked) * 0.5
		if host.valid_ground(from.lerp(to, fraction), radius): clear = fraction
		else: blocked = fraction
	# Avoid subpixel creep while holding into an already-contacting surface.
	return from if from.distance_squared_to(from.lerp(to, clear)) < 0.000001 else from.lerp(to, clear)

func blocked_fraction(from: Vector2, to: Vector2, radius: float = 0.0) -> float:
	var result: float = host.GroundBoundary.clear_fraction(host.ground_polygon, from, to, radius) if not host.ground_polygon.is_empty() else 1.0
	if bool(host.layout.get("b06_candidate",false)) and is_instance_valid(host.enemy_skills) and host.enemy_skills.b06 != null and host.enemy_skills.b06.has_method("blocked_fraction"):
		result = minf(result,host.enemy_skills.b06.blocked_fraction(from,to,radius))
	var offset: Vector2 = to - from
	var allowed: Rect2 = host.ARENA.grow(-radius)
	if offset.x > 0.0: result = minf(result, (allowed.end.x - from.x) / offset.x)
	elif offset.x < 0.0: result = minf(result, (allowed.position.x - from.x) / offset.x)
	if offset.y > 0.0: result = minf(result, (allowed.end.y - from.y) / offset.y)
	elif offset.y < 0.0: result = minf(result, (allowed.position.y - from.y) / offset.y)
	var obstacles: Array[Rect2] = host.obstructions.duplicate()
	if is_instance_valid(host.b09_mechanics): obstacles.append_array(host.b09_mechanics.navigation_bounds())
	for wall: Rect2 in obstacles:
		var box: Rect2 = wall.grow(radius)
		var start: float = 0.0
		var finish: float = 1.0
		var intersects: bool = true
		for axis in range(2):
			if absf(offset[axis]) < 0.00001:
				if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
					intersects = false
					break
			else:
				var near: float = (box.position[axis] - from[axis]) / offset[axis]
				var far: float = (box.end[axis] - from[axis]) / offset[axis]
				start = maxf(start, minf(near, far))
				finish = minf(finish, maxf(near, far))
				if start > finish:
					intersects = false
					break
		if intersects and finish >= 0.0 and start <= 1.0:
			result = minf(result, maxf(0.0, start - 0.0001))
	return clampf(result, 0.0, 1.0)

func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	return host.blocked_fraction(from, to) >= 1.0

func navigation_direction(from: Vector2, to: Vector2, radius: float) -> Vector2:
	if is_instance_valid(host.b09_mechanics):
		var obstacles: Array[Rect2] = host.obstructions.duplicate()
		obstacles.append_array(host.b09_mechanics.navigation_bounds())
		return host._navigation_cache.direction(from,to,radius,obstacles,host.ARENA,host.ground_polygon)
	if is_instance_valid(host.b05_mechanics):
		var navigation_obstacles: Array[Rect2] = host.obstructions.duplicate()
		navigation_obstacles.append_array(host.b05_mechanics.navigation_bounds())
		return host._navigation_cache.direction(from,to,radius,navigation_obstacles,host.ARENA,host.ground_polygon)
	var walls: Array[Rect2] = host.obstructions
	if bool(host.layout.get("b06_candidate",false)) and is_instance_valid(host.enemy_skills) and host.enemy_skills.b06 != null and host.enemy_skills.b06.has_method("navigation_obstructions"):
		walls = host.obstructions.duplicate()
		walls.append_array(host.enemy_skills.b06.navigation_obstructions())
	return host._navigation_cache.direction(from, to, radius, walls, host.ARENA, host.ground_polygon)

func navigation_target() -> Dictionary:
	if host.player == null:
		return {}
	if not host.expedition_context.is_empty():
		var role: String = str(host.expedition_context.get("role",""))
		if bool(host.layout.get("b09_candidate",false)) and host.objective_complete: return {"position":host.exit_position,"title":"霜晶宫廷已清理 · 前往出口","kind":"next"}
		if role == "entrance": return {"position":host.exit_position,"title":"完成整备后前往第一处矿区 · M 查看路线","kind":"next"}
		if role == "supply": return {"position":host.layout.get("service_position",host.exit_position),"title":"购买补给，或前往下一站","kind":"supply"}
		if host.objective_rewarded: return {"position":host.exit_position,"title":"领取成长奖励，继续远征" if role != "boss" else "首领已击败 · 前往撤离井","kind":"next" if role != "boss" else "extract"}
		if is_instance_valid(host.objectives) and not host.objectives.is_complete():
			return host.objectives.navigation_target()
	if not host.objective_complete:
		if host._living_enemy_count() > 0:
			var closest: EnemyActor = null
			for enemy in host.enemies.get_children():
				if enemy.actor_kind != "objective" and enemy.is_alive() and (closest == null or enemy.position.distance_squared_to(host.player.position) < closest.position.distance_squared_to(host.player.position)):
					closest = enemy
			if closest != null:
				return {"position":closest.position,"title":"清理遭遇区域","name_en":"Clear the encounter","kind":"encounter"}
		for index in host.encounter_progress:
			var progress: Dictionary = host.encounter_progress[index]
			if int(progress.next_wave) < progress.plan.waves.size():
				var directive: Dictionary = host.objectives.encounter_directive(index) if is_instance_valid(host.objectives) else {}
				return {"position":directive.get("position",host.encounter_zones[index].center),"title":"准备迎接增援","name_en":"Prepare for reinforcements","kind":"encounter"}
		for index in host.encounter_zones.size():
			if not host.activated_encounters.has(index):
				return {"position":host.encounter_zones[index].center,"title":"探索下一矿区","name_en":"Explore the next sector","kind":"objective"}
	return {"position":host.exit_position,"title":"撤离升降井","name_en":"Extraction lift","kind":"extract"}
