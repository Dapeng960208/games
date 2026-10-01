class_name EnemySkillRuntime
extends Node2D
const Numerical = preload("res://config/numerical_rules.gd")
## Enemy-only execution. The brain owns the readable tell and locked aim; this
## node owns collision, finite effects and cancellation after the tell completes.
## Commands use frozen room-local Vector2 coordinates. Cone/arc angles are radians;
## projectile_angles, spread_degrees and ring_gap_degrees are explicitly degrees.
## Room owns spawn budget/rewards via spawn_enemy_summon/spawn_enemy_skill_anchor.
## Damage always enters the victim's receive_damage path before optional status.

const MAX_EFFECTS := 128
const MAX_ENEMIES := 18
const EPSILON := 0.00001
var room: Node2D
var jobs: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var motions: Array[Dictionary] = []
var supports: Array[Dictionary] = []
var visuals: Array[Dictionary] = []
var marks: Array[Dictionary] = []
var heal_receipts: Dictionary = {}
var summon_owners: Dictionary = {}
var biome_skill_cooldowns: Dictionary = {}
var _biome_clock: float = 0.0

func configure(host: Node2D) -> void:
	reset_room()
	room = host
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 1

func emit_skill(caster: Node2D, skill: Dictionary) -> void:
	if not _alive(caster) or not is_instance_valid(room) or _paused():
		return
	if str(_property(caster, "state", "")) in ["emerging", "spawning"]:
		return
	if active_effect_count() >= MAX_EFFECTS:
		return
	var command: Dictionary = skill.duplicate(true)
	command["owner"] = weakref(caster)
	command["owner_id"] = caster.get_instance_id()
	var actor_profile: Dictionary = _property(caster, "profile", {})
	command["ruleset_version"] = int(actor_profile.get("ruleset_version", Numerical.LEGACY))
	command["origin"] = command.get("origin", caster.position)
	var target: Variant = command.get("target", command.origin)
	if target is Node2D:
		target = target.position if is_instance_valid(target) else command.origin
	command["target"] = target if target is Vector2 else command.origin
	var direction: Vector2 = command.get("direction", (command.target - command.origin).normalized())
	command["direction"] = direction.normalized() if direction.length_squared() > EPSILON else Vector2.RIGHT
	var base_damage: float = float(command.get("damage", _property(caster, "contact_damage", _property(caster, "attack_damage", 12.0))))
	command["damage"] = maxf(0.0, base_damage) * maxf(0.0, float(command.get("damage_multiplier", 1.0)))
	var signature: Dictionary = _biome_signature(caster, command)
	command["biome_skill"] = signature
	if str(signature.get("id", "")) == "blood_rage" and _blood_rage_active(caster, signature):
		# Freeze the rage bonus with the rest of this attack. It never multiplies
		# again when a projectile hits or a lingering area ticks.
		command["damage"] *= float(signature.get("damage_multiplier", 1.2))
	if Numerical.is_v2(command): command["damage"] = Numerical.integer(float(command.damage))
	command["remaining"] = maxf(0.0, float(command.get("delay", 0.0)))
	if float(command.remaining) > 0.0:
		jobs.append(command)
	else:
		_execute(command)
	queue_redraw()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if delta <= 0.0 or _paused() or not is_instance_valid(room):
		return
	_biome_clock += delta
	for owner_id: int in biome_skill_cooldowns.keys():
		if not _alive(instance_from_id(owner_id)):
			biome_skill_cooldowns.erase(owner_id)
	var pending_jobs: Array[Dictionary] = jobs.duplicate()
	for shot: Dictionary in projectiles.duplicate():
		_tick_projectile(shot, delta)
	for motion: Dictionary in motions.duplicate():
		_tick_motion(motion, delta)
	for hazard: Dictionary in hazards.duplicate():
		_tick_hazard(hazard, delta)
	for support: Dictionary in supports.duplicate():
		if not _support_valid(support):
			_remove_support(support)
			continue
		support.remaining = float(support.remaining) - delta
		if float(support.remaining) <= EPSILON:
			if str(support.kind) == "counter":
				_release_counter(support)
			_remove_support(support)
	for visual: Dictionary in visuals.duplicate():
		visual.remaining = float(visual.remaining) - delta
		if float(visual.remaining) <= 0.0 or not _owner_alive(visual):
			visuals.erase(visual)
	for mark: Dictionary in marks.duplicate():
		mark.remaining = float(mark.remaining) - delta
		if float(mark.remaining) <= 0.0 or not _owner_alive(mark) or not _alive(_support_target(mark)):
			marks.erase(mark)
	for command: Dictionary in pending_jobs:
		if not _owner_alive(command) or (command.has("anchor_ref") and not _alive(_anchor(command))):
			if _owner_alive(command) and str(command.get("kind", "")) == "summon":
				_pod_disarmed(command)
			jobs.erase(command)
			_retire_anchor(command)
			continue
		command.remaining = float(command.remaining) - delta
		if float(command.remaining) <= EPSILON:
			jobs.erase(command)
			_retire_anchor(command)
			var previous_shots: Array[Dictionary] = projectiles.duplicate()
			var previous_areas: Array[Dictionary] = hazards.duplicate()
			var previous_motions: Array[Dictionary] = motions.duplicate()
			var overshoot: float = maxf(0.0, -float(command.remaining))
			_execute(command)
			# Only elapsed time after the tell belongs to a newly emitted effect.
			if overshoot > EPSILON:
				for shot: Dictionary in projectiles.duplicate():
					if not previous_shots.has(shot):
						_tick_projectile(shot, overshoot)
				for area: Dictionary in hazards.duplicate():
					if not previous_areas.has(area):
						_tick_hazard(area, overshoot)
				for motion: Dictionary in motions.duplicate():
					if not previous_motions.has(motion):
						_tick_motion(motion, overshoot)
	for owner_id: int in summon_owners.keys():
		if not _alive(instance_from_id(owner_id)):
			for reference: WeakRef in summon_owners[owner_id]:
				var summon: Node = reference.get_ref()
				if is_instance_valid(summon):
					summon.queue_free()
			summon_owners.erase(owner_id)
	queue_redraw()

func cancel_owner(caster: Node2D) -> void:
	if not is_instance_valid(caster):
		return
	var owner_id: int = caster.get_instance_id()
	for collection: Array in [jobs, projectiles, hazards, motions, supports, visuals, marks]:
		for effect: Dictionary in collection.duplicate():
			if int(effect.get("owner_id", 0)) == owner_id:
				collection.erase(effect)
				_retire_anchor(effect)
	if caster.has_meta("enemy_skill_motion"):
		caster.remove_meta("enemy_skill_motion")
	for summon_ref: WeakRef in summon_owners.get(owner_id, []):
		var summon: Node = summon_ref.get_ref()
		if is_instance_valid(summon):
			# A cancelled pod never leaves a rewarding corpse or a delayed attack.
			summon.queue_free()
	summon_owners.erase(owner_id)
	biome_skill_cooldowns.erase(owner_id)
	queue_redraw()

func cancel_displaced_motion(caster: Node2D) -> void:
	if not is_instance_valid(caster):
		return
	var owner_id: int = caster.get_instance_id()
	# Only body-driven motion is invalidated. Already committed projectiles,
	# ground spells and their delayed jobs keep their independent frozen origin.
	for command: Dictionary in jobs.duplicate():
		if int(command.get("owner_id", 0)) == owner_id and str(command.get("kind", "")) == "charge":
			jobs.erase(command)
	for motion: Dictionary in motions.duplicate():
		if int(motion.get("owner_id", 0)) == owner_id:
			_finish_motion(motion, false)
	queue_redraw()

func reset_room() -> void:
	for effect: Dictionary in hazards + supports + jobs:
		var anchor: Node2D = _anchor(effect)
		if is_instance_valid(anchor):
			anchor.queue_free()
	for motion: Dictionary in motions:
		var caster: Node2D = _owner(motion)
		if is_instance_valid(caster) and caster.has_meta("enemy_skill_motion"):
			caster.remove_meta("enemy_skill_motion")
	for owner_id: int in summon_owners:
		for summon_ref: WeakRef in summon_owners[owner_id]:
			var summon: Node = summon_ref.get_ref()
			if is_instance_valid(summon):
				summon.queue_free()
	for collection: Array in [jobs, projectiles, hazards, motions, supports, visuals, marks]:
		collection.clear()
	heal_receipts.clear()
	summon_owners.clear()
	biome_skill_cooldowns.clear()
	_biome_clock = 0.0
	queue_redraw()

func active_effect_count() -> int:
	return jobs.size() + projectiles.size() + hazards.size() + motions.size() + supports.size() + visuals.size() + marks.size()

func has_motion(caster: Node2D) -> bool:
	return is_instance_valid(caster) and bool(caster.get_meta("enemy_skill_motion", false))

func movement_multiplier(target: Node2D) -> float:
	var multiplier: float = 1.0
	var signature: Dictionary = _biome_signature(target)
	if str(signature.get("id", "")) == "blood_rage" and _blood_rage_active(target, signature):
		multiplier = float(signature.get("move_multiplier", 1.18))
	for support: Dictionary in supports:
		if str(support.kind) == "haste" and _support_valid(support) and _support_target(support) == target:
			multiplier = maxf(multiplier, float(support.get("multiplier", 1.18)))
	return minf(multiplier, 1.35)

func consume_scan_mark(shooter: Node2D) -> float:
	if not _alive(shooter) or _paused():
		return 1.0
	for mark: Dictionary in marks.duplicate():
		if not _owner_alive(mark) or not _alive(_support_target(mark)) or float(mark.remaining) <= 0.0:
			marks.erase(mark)
			continue
		if _property(shooter, "zone_index", _property(shooter, "encounter_id", 0)) != _property(_owner(mark), "zone_index", _property(_owner(mark), "encounter_id", 0)):
			continue
		marks.erase(mark)
		return 0.85
	return 1.0

func filter_incoming_damage(target: Node2D, amount: float, kind: StringName, from_direction: Vector2) -> float:
	var result: float = maxf(0.0, amount)
	var target_profile: Dictionary = _property(target, "profile", {})
	for support: Dictionary in supports.duplicate():
		if not _support_valid(support) or _support_target(support) != target:
			continue
		if str(support.kind) == "counter" and amount > 0.0:
			support.hits = mini(int(support.get("hit_cap", 3)), int(support.get("hits", 0)) + 1)
			if int(support.hits) >= int(support.get("hit_cap", 3)):
				_release_counter(support)
				_remove_support(support)
		elif str(support.kind) == "guard" and result > 0.0:
			var mode: String = str(support.get("mode", "guard"))
			if mode in ["directional", "cover", "screen"]:
				var forward: Vector2 = support.direction
				var half_angle: float = clampf(float(support.get("angle", 1.9)) * 0.5, 0.0, PI)
				if from_direction.length_squared() < EPSILON or from_direction.normalized().dot(forward) > -cos(half_angle):
					continue
			if mode == "cover":
				if kind not in [&"primary", &"child"]:
					continue
				var plate: Node2D = _anchor(support)
				if not _alive(plate):
					_remove_support(support)
					continue
				var backwards: Vector2 = -from_direction.normalized()
				var distance_to_plane: float = (plate.position - target.position).dot(Vector2(support.direction)) / maxf(EPSILON, backwards.dot(Vector2(support.direction)))
				var crossing: Vector2 = target.position + backwards * distance_to_plane
				if absf((crossing - plate.position).dot(Vector2(support.direction).orthogonal())) > 60.0:
					continue
				var plate_health: Variant = _property(plate, "health", null)
				var blocked: float = minf(Numerical.integer(result) if Numerical.is_v2(target_profile) else result, float(_property(plate_health, "current", 0.0)))
				if blocked > 0.0:
					plate.call("take_damage", blocked, kind, from_direction)
					if Numerical.is_v2(target_profile):
						# Cover is an actual receiver, so a rejected plate packet
						# cannot manufacture absorption or a confirmed hero contact.
						var receipt: Dictionary = _property(plate, "last_damage_result", {})
						blocked = minf(blocked, maxf(0.0, float(receipt.get("hp_damage", 0.0)) + float(receipt.get("shield_damage", 0.0))))
					result = maxf(0.0, result - blocked)
				continue
			if mode == "screen":
				if kind not in [&"primary", &"child"]:
					continue
				support.charges = int(support.get("charges", 3)) - 1
				result = 0.0
				if int(support.charges) <= 0:
					_remove_support(support)
			else:
				var absorbed: float = minf(Numerical.integer(result) if Numerical.is_v2(target_profile) else result, float(support.get("amount", 0.0)))
				result = maxf(0.0, result - absorbed)
				support.amount = float(support.get("amount", 0.0)) - absorbed
				if float(support.amount) <= EPSILON:
					_remove_support(support)
	return result

func clear_target_guards(target: Node2D) -> int:
	# Arena shield counters remove real barrier support, including a shared
	# cover anchor's records, without cancelling attacks or unrelated buffs.
	var removed: int = 0
	var broken_anchors: Array[Node2D] = []
	for support: Dictionary in supports.duplicate():
		if str(support.get("kind", "")) == "guard" and _support_target(support) == target:
			var anchor: Node2D = _anchor(support)
			if is_instance_valid(anchor) and not broken_anchors.has(anchor):
				broken_anchors.append(anchor)
			_remove_support(support)
			removed += 1
	for support: Dictionary in supports.duplicate():
		if str(support.get("kind", "")) == "guard" and _anchor(support) in broken_anchors:
			_remove_support(support)
			removed += 1
	return removed

func _execute(command: Dictionary) -> void:
	if not _owner_alive(command):
		return
	match str(command.get("kind", "melee")):
		"melee":
			command["shape"] = command.get("shape", "cone")
			_strike(command)
			_flash(command)
		"projectile":
			_spawn_projectiles(command)
		"charge":
			_start_motion(command)
		"ground_area":
			_spawn_hazards(command)
		"pull":
			_pull(command)
			_flash(command)
		"guard", "haste", "heal", "counter":
			_support(command)
		"summon":
			_summon(command)
		"decoy":
			for index: int in range(clampi(int(command.get("count", 1)), 1, 2)):
				var decoy: Dictionary = command.duplicate()
				decoy["remaining"] = clampf(float(command.get("duration", 2.0)), 0.3, 4.0)
				decoy["decoy"] = true
				var offset: Vector2 = Vector2(command.direction).orthogonal() * (62.0 if index == 0 else -62.0)
				decoy["origin"] = room.move_actor(command.origin, offset, 14.0)
				decoy["shape"] = "cone"
				decoy["decoy_texture"] = _property(_owner(command), "body_texture", null)
				visuals.append(decoy)
		"utility":
			if str(command.get("action", "")) in ["scan_mark", "visible_scan_mark"]:
				_scan_mark(command)
			elif room.has_method("apply_enemy_utility"):
				room.call("apply_enemy_utility", _owner(command), command)

func _spawn_projectiles(command: Dictionary) -> void:
	var count: int = clampi(int(command.get("count", 1)), 1, 5)
	var frozen_paths: Array = command.get("paths", [])
	if not frozen_paths.is_empty():
		count = clampi(frozen_paths.size(), 1, 5)
	var angles: Array = command.get("projectile_angles", [])
	for index: int in range(count):
		if active_effect_count() >= MAX_EFFECTS:
			break
		var angle_degrees: float = float(angles[index]) if index < angles.size() else (float(index) / maxf(1.0, float(count - 1)) - 0.5) * float(command.get("spread_degrees", 0.0))
		var shot: Dictionary = command.duplicate(true)
		shot["position"] = command.origin
		shot["direction"] = Vector2(command.direction).rotated(deg_to_rad(angle_degrees))
		shot["speed"] = clampf(float(command.get("speed", 420.0)), 40.0, 2400.0)
		shot["distance_left"] = clampf(float(command.get("range", 900.0)), 1.0, 1800.0)
		shot["remaining"] = clampf(float(command.get("lifetime", 5.0)), 0.05, 8.0)
		shot["hit_ids"] = []
		shot["radius"] = clampf(float(command.get("projectile_radius", command.get("radius", 5.0))), 2.0, 14.0)
		shot["pierce_left"] = 3 if command.get("pierce", false) is bool and bool(command.get("pierce", false)) else clampi(int(command.get("pierce", 0)), 0, 4)
		var points: Array = command.get("refraction_points", [])
		shot["waypoints"] = []
		if not points.is_empty():
			var origin: Vector2 = command.origin
			shot.waypoints = [origin + (Vector2(points[0]) - origin).rotated(deg_to_rad(angle_degrees)), origin + (Vector2(command.target) - origin).rotated(deg_to_rad(angle_degrees))]
		if index < frozen_paths.size() and frozen_paths[index] is Array:
			var path: Array = frozen_paths[index]
			if path.size() >= 2 and path[0] is Vector2 and path[1] is Vector2:
				shot.position = path[0]
				shot.direction = Vector2(path[0]).direction_to(path[1])
				shot.waypoints = path.slice(1, mini(3, path.size()))
				shot.distance_left = 0.0
				var previous: Vector2 = path[0]
				for point: Vector2 in shot.waypoints:
					shot.distance_left = float(shot.distance_left) + previous.distance_to(point)
					previous = point
		projectiles.append(shot)

func _tick_projectile(shot: Dictionary, delta: float) -> void:
	if not _owner_alive(shot):
		projectiles.erase(shot)
		return
	var step: float = minf(delta, float(shot.remaining))
	shot.remaining = maxf(0.0, float(shot.remaining) - delta)
	var travel: float = minf(float(shot.speed) * step, float(shot.distance_left))
	# One authored bend at most. Each leg is independently swept against walls.
	for leg: int in range(3):
		if travel <= EPSILON or not projectiles.has(shot):
			break
		var start: Vector2 = shot.position
		var distance: float = travel
		var waypoints: Array = shot.waypoints
		if not waypoints.is_empty():
			var waypoint: Vector2 = waypoints[0]
			distance = minf(distance, start.distance_to(waypoint))
			shot.direction = (waypoint - start).normalized()
		var end: Vector2 = start + Vector2(shot.direction) * distance
		var wall_fraction: float = _blocked(start, end, float(shot.radius))
		end = start.lerp(end, wall_fraction)
		var hits: Array[Dictionary] = _segment_targets(start, end, float(shot.radius), shot.hit_ids)
		var cursor: Vector2 = start
		for hit: Dictionary in hits:
			var hit_point: Vector2 = start.lerp(end, float(hit.t))
			if room.has_method("intercept_enemy_projectile") and room.intercept_enemy_projectile(cursor, hit_point, 1.0):
				projectiles.erase(shot)
				return
			var victim: Node2D = hit.target
			shot.hit_ids.append(victim.get_instance_id())
			_deal(victim, shot, start)
			if int(shot.pierce_left) <= 0:
				shot.position = start.lerp(end, float(hit.t))
				projectiles.erase(shot)
				return
			shot.pierce_left = int(shot.pierce_left) - 1
			cursor = hit_point
		if room.has_method("intercept_enemy_projectile") and room.intercept_enemy_projectile(cursor, end, 1.0001):
			projectiles.erase(shot)
			return
		shot.position = end
		shot.distance_left = float(shot.distance_left) - start.distance_to(end)
		travel -= distance
		if wall_fraction < 1.0 or float(shot.distance_left) <= EPSILON:
			projectiles.erase(shot)
			return
		if not waypoints.is_empty() and end.distance_to(waypoints[0]) <= 0.1:
			waypoints.pop_front()
			if waypoints.is_empty():
				projectiles.erase(shot)
				return
	if float(shot.remaining) <= EPSILON:
		projectiles.erase(shot)

func _start_motion(command: Dictionary) -> void:
	var caster: Node2D = _owner(command)
	var pending_knockback: Variant = _property(caster, "knockback", Vector2.ZERO)
	if caster.position.distance_squared_to(Vector2(command.origin)) > 0.25 or (pending_knockback is Vector2 and pending_knockback.length_squared() > 0.01) or (caster.has_method("has_pending_displacement") and caster.has_pending_displacement()):
		return
	for old: Dictionary in motions.duplicate():
		if int(old.owner_id) == caster.get_instance_id():
			motions.erase(old)
	var motion: Dictionary = command.duplicate(true)
	motion["start"] = caster.position
	motion["last_position"] = caster.position
	motion["elapsed"] = 0.0
	motion["travel_distance"] = clampf(float(command.get("travel_distance", command.get("range", 220.0))), 0.0, 600.0)
	var locked_distance: float = caster.position.distance_to(Vector2(command.target))
	if locked_distance > EPSILON:
		motion.travel_distance = minf(float(motion.travel_distance), locked_distance)
	var duration: float = float(command.get("duration", 0.0))
	if duration <= 0.0:
		duration = float(motion.travel_distance) / maxf(80.0, float(command.get("speed", 460.0)))
	motion["duration"] = clampf(duration, 0.1, 2.0)
	motion["hit_ids"] = []
	caster.set_meta("enemy_skill_motion", true)
	motions.append(motion)

func _tick_motion(motion: Dictionary, delta: float) -> void:
	var caster: Node2D = _owner(motion)
	if not _owner_alive(motion):
		_finish_motion(motion, false)
		return
	var pending_knockback: Variant = _property(caster, "knockback", Vector2.ZERO)
	if caster.position.distance_squared_to(Vector2(motion.last_position)) > 0.25 or (pending_knockback is Vector2 and pending_knockback.length_squared() > 0.01) or (caster.has_method("has_pending_displacement") and caster.has_pending_displacement()):
		# External displacement invalidates the already locked path. Cancelling
		# avoids snapping back or connecting an unannounced route to its endpoint.
		_finish_motion(motion, false)
		return
	var previous_time: float = float(motion.elapsed)
	motion.elapsed = minf(float(motion.duration), previous_time + delta)
	var mode: String = str(motion.get("path_mode", "line"))
	var radius: float = _radius(caster, 18.0)
	var steps: int = maxi(1, int(ceil(float(motion.travel_distance) * (float(motion.elapsed) - previous_time) / float(motion.duration) / 10.0)))
	var stopped: bool = false
	for step: int in range(1, steps + 1):
		var progress: float = lerpf(previous_time, float(motion.elapsed), float(step) / steps) / float(motion.duration)
		var direction: Vector2 = motion.direction
		var desired: Vector2 = Vector2(motion.start) + direction * float(motion.travel_distance) * progress
		if mode in ["arc", "leap"] or (mode == "burrow" and absf(float(motion.get("arc_height", 0.0))) > EPSILON):
			var bend: float = float(motion.get("arc_height", float(motion.travel_distance) * sin(float(motion.get("arc_angle", 0.65))) * 0.35))
			desired += direction.orthogonal() * sin(PI * progress) * bend
		var start: Vector2 = caster.position
		var fraction: float = _blocked(start, desired, radius)
		var safe_end: Vector2 = start.lerp(desired, fraction)
		caster.position = room.move_actor(start, safe_end - start, radius)
		motion.last_position = caster.position
		if not bool(motion.get("landing_only", false)) and (mode not in ["leap", "burrow"] or bool(motion.get("damage_along_path", false))):
			for hit: Dictionary in _segment_targets(start, caster.position, float(motion.get("radius", radius)), motion.hit_ids):
				var victim: Node2D = hit.target
				motion.hit_ids.append(victim.get_instance_id())
				_deal(victim, motion, start)
		if fraction < 1.0:
			caster.set_meta("enemy_charge_wall_stop", true)
			stopped = true
			break
	if stopped or float(motion.elapsed) >= float(motion.duration) - EPSILON:
		# A blocked leap never moves its warned landing blast to an unmarked wall.
		# Only completed travel reaches this bridge. Interrupted/cancelled motion
		# cannot claim a counter along the untravelled part of its locked path.
		# Curved motion cannot use its endpoint chord as travelled geometry.
		# The current barricade counter supports the actual straight charge only.
		if mode == "line" and room.has_method("notify_enemy_charge"):
			room.call("notify_enemy_charge", caster, Vector2(motion.start), caster.position)
		_finish_motion(motion, not stopped)

func _finish_motion(motion: Dictionary, impact: bool) -> void:
	var caster: Node2D = _owner(motion)
	motions.erase(motion)
	if not is_instance_valid(caster):
		return
	if caster.has_meta("enemy_skill_motion"):
		caster.remove_meta("enemy_skill_motion")
	if impact and (str(motion.get("path_mode", "line")) in ["leap", "burrow"] or bool(motion.get("landing_only", false))):
		var landing: Dictionary = motion.duplicate()
		landing["origin"] = caster.position
		landing["target"] = caster.position
		landing["shape"] = motion.get("landing_shape", "circle")
		_strike(landing)
		_flash(landing)

func _spawn_hazards(command: Dictionary) -> void:
	var points: Array = command.get("targets", [command.get("target", command.origin)])
	var cap: int = clampi(int(command.get("max_active_hazards", command.get("max_count", 2))), 1, 2)
	for point: Vector2 in points.slice(0, 3):
		var area: Dictionary = command.duplicate(true)
		if str(command.get("shape", "circle")) in ["circle", "ring"]:
			area["origin"] = point
		area["shape"] = command.get("shape", "circle")
		area["remaining"] = clampf(float(command.get("duration", 0.0)), 0.0, 8.0)
		if float(area.remaining) <= 0.0:
			_strike(area)
			_flash(area)
			continue
		if bool(command.get("lob", false)):
			# All three authored landing splashes resolve after the brain's tell;
			# only the two newest pools persist after their impacts.
			_strike(area)
			_flash(area)
		var owned: Array[Dictionary] = []
		for old: Dictionary in hazards:
			if int(old.owner_id) == int(command.owner_id):
				owned.append(old)
		while owned.size() >= cap:
			_remove_hazard(owned.pop_front())
		if bool(command.get("breakable", false)) or str(command.get("behavior_id", "")) == "two_breakable_slow_lines":
			var line: Array[Vector2] = _line_segment(area)
			area.origin = line[0]
			var endpoint: Vector2 = line[1]
			endpoint = Vector2(area.origin).lerp(endpoint, _blocked(area.origin, endpoint, 12.0))
			var anchor: Node2D = _spawn_anchor(area, endpoint, _anchor_health(command, float(command.get("anchor_health", 24.0))), "hazard_endpoint")
			if not is_instance_valid(anchor):
				continue
			area["anchor_ref"] = weakref(anchor)
			area["range"] = Vector2(area.origin).distance_to(anchor.position)
			area["points"] = [area.origin, anchor.position]
		area["tick_interval"] = clampf(float(command.get("tick_interval", 0.65)), 0.35, 2.0)
		area["next_tick"] = float(area.tick_interval)
		hazards.append(area)

func _tick_hazard(area: Dictionary, delta: float) -> void:
	if not _owner_alive(area) or (area.has("anchor_ref") and not _alive(_anchor(area))):
		_remove_hazard(area)
		return
	var step: float = minf(delta, float(area.remaining))
	area.remaining = maxf(0.0, float(area.remaining) - delta)
	area.next_tick = float(area.next_tick) - step
	# Bounded lifetimes and intervals keep a stalled frame finite.
	while float(area.next_tick) <= EPSILON:
		_strike(area)
		area.next_tick = float(area.next_tick) + float(area.tick_interval)
	if float(area.remaining) <= EPSILON:
		_remove_hazard(area)

func _strike(command: Dictionary) -> Array[Node2D]:
	var struck: Array[Node2D] = []
	for victim: Node2D in _targets():
		var origin: Vector2 = _line_segment(command)[0] if str(command.get("shape", "")) == "line" else Vector2(command.origin)
		if shape_contains(command, victim.position, _radius(victim, 12.0)) and _line_clear(origin, victim.position):
			if _deal(victim, command, origin):
				struck.append(victim)
	return struck

func shape_contains(command: Dictionary, point: Vector2, actor_radius: float = 0.0) -> bool:
	var origin: Vector2 = command.get("origin", Vector2.ZERO)
	var direction: Vector2 = command.get("direction", Vector2.RIGHT)
	var offset: Vector2 = point - origin
	var shape: String = str(command.get("shape", "circle"))
	var radius: float = maxf(0.0, float(command.get("radius", command.get("range", 70.0))))
	if shape == "line":
		var line: Array[Vector2] = _line_segment(command)
		return _segment_distance(point, line[0], line[1]) <= float(command.get("width", radius)) * 0.5 + actor_radius
	if shape == "cone":
		var reach: float = float(command.get("range", radius))
		if offset.length() > reach + actor_radius:
			return false
		if offset.length() <= actor_radius:
			return true
		var half_angle: float = clampf(float(command.get("angle", 1.8)) * 0.5, 0.0, PI)
		return absf(direction.angle_to(offset)) <= half_angle + asin(minf(1.0, actor_radius / maxf(actor_radius, offset.length())))
	if shape == "ring":
		var inner: float = maxf(0.0, float(command.get("inner_radius", radius * 0.48)))
		var interval: Vector2 = _ring_interval(command)
		var relative_angle: float = fposmod(offset.angle() - interval.x, TAU)
		if interval.y - interval.x < TAU - EPSILON and relative_angle > interval.y - interval.x + EPSILON:
			return false
		return offset.length() <= radius + actor_radius and offset.length() >= maxf(0.0, inner - actor_radius)
	return offset.length() <= radius + actor_radius

func _damage_source_context(command: Dictionary) -> Dictionary:
	var owner_profile: Dictionary = _property(_owner(command), "profile", {})
	var source_id: String = str(owner_profile.get("enemy_id", owner_profile.get("boss_id", command.get("boss_id", ""))))
	var english: bool = TranslationServer.get_locale().begins_with("en")
	return {"source_id":source_id, "source_name":str(owner_profile.get("name_en" if english else "name", source_id)), "attack_id":str(command.get("action_id", command.get("behavior_id", owner_profile.get("behavior_id", ""))))}

func _deal(victim: Node2D, command: Dictionary, origin: Vector2) -> bool:
	if not _alive(victim) or not _owner_alive(command) or not victim.has_method("receive_damage"):
		return false
	var accepted: bool = false
	if float(command.get("damage", 0.0)) > 0.0:
		if victim.has_method("class_status"):
			var owner_profile: Dictionary = _property(_owner(command),"profile",{})
			var kind: String = str(command.get("damage_type",owner_profile.get("damage_type",owner_profile.get("damage_kind","physical"))))
			if kind in ["electric","thermal","arcane","toxic","cold"]: kind = "magic"
			var visual_kind: String = str(command.get("damage_kind", owner_profile.get("damage_kind", kind)))
			var context: Dictionary = _damage_source_context(command)
			context.merge({"damage_type":kind, "damage_kind":visual_kind}, true)
			accepted = bool(victim.receive_damage(float(command.damage),origin,context))
		else:
			accepted = bool(victim.receive_damage(float(command.damage), origin))
	else:
		accepted = not (victim.has_method("dash_protected") and victim.dash_protected()) and float(_property(victim, "invulnerable", 0.0)) <= 0.0
	if accepted and victim.has_method("receive_enemy_status"):
		var status_value: Variant = command.get("status", {})
		var state: Dictionary = status_value.duplicate() if status_value is Dictionary else {"id":str(status_value)}
		if state.is_empty() and float(command.get("slow", 0.0)) > 0.0:
			state = {"id":"slow", "magnitude":float(command.slow), "duration":0.8}
		if not str(state.get("id", "")).is_empty():
			state["power"] = state.get("power", float(command.get("damage", 0.0)))
			state["origin"] = origin
			state.merge(_damage_source_context(command), true)
			victim.call("receive_enemy_status", state)
	if accepted and float(command.get("damage", 0.0)) > 0.0:
		_apply_biome_hit(victim, command, origin)
	return accepted

func _biome_signature(caster: Node2D, command: Dictionary = {}) -> Dictionary:
	if not _alive(caster) or bool(caster.get_meta("enemy_skill_anchor", false)) or str(_property(caster, "rank", "normal")) == "boss" or str(_property(caster, "actor_kind", "enemy")) != "enemy":
		return {}
	var profile: Dictionary = _property(caster, "profile", {})
	return command.get("biome_skill", profile.get("biome_skill", {})).duplicate(true)

func _blood_rage_active(caster: Node2D, signature: Dictionary) -> bool:
	var health: Variant = _property(caster, "health", null)
	var maximum: float = float(_property(health, "maximum", 0.0))
	return _alive(caster) and maximum > 0.0 and float(_property(health, "current", maximum)) / maximum <= float(signature.get("health_threshold", 0.5))

func _apply_biome_hit(victim: Node2D, command: Dictionary, origin: Vector2) -> void:
	var caster: Node2D = _owner(command)
	var signature: Dictionary = _biome_signature(caster, command)
	var id: String = str(signature.get("id", ""))
	if id.is_empty() or id == "blood_rage":
		return
	if id == "venom_wound":
		# Existing acid attacks already deliver a full corrosion packet. A bite
		# can carry its authored slow and venom together, without overwriting it.
		var primary_status: Variant = command.get("status", {})
		var primary_id: String = str(primary_status.get("id", "")) if primary_status is Dictionary else str(primary_status)
		if primary_id != str(signature.get("status_id", "corrosion")) and victim.has_method("receive_enemy_status"):
			var status_context: Dictionary = _damage_source_context(command)
			status_context.merge({"id":signature.get("status_id", "corrosion"), "duration":float(signature.get("status_seconds", 1.8)), "power":float(command.damage) * float(signature.get("status_power_ratio", 0.55)), "origin":origin}, true)
			victim.call("receive_enemy_status", status_context)
		return
	var owner_id: int = caster.get_instance_id()
	if _biome_clock < float(biome_skill_cooldowns.get(owner_id, -1.0)):
		return
	var health: Variant = _property(caster, "health", null)
	var maximum: float = float(_property(health, "maximum", 0.0))
	if maximum <= 0.0:
		return
	var triggered: bool = false
	if id == "capacitor_guard":
		var status: Variant = _property(caster, "status", null)
		if status is Object and status.has_method("grant_guard"):
			triggered = bool(status.call("grant_guard", maximum * float(signature.get("guard_ratio", 0.08)), float(signature.get("guard_seconds", 1.5)), "biome:capacitor", maximum))
	elif id == "grave_drain" and caster.has_method("heal"):
		var amount: float = minf(maximum * float(signature.get("heal_hp_cap", 0.06)), float(command.damage) * float(signature.get("heal_damage_ratio", 0.25)))
		triggered = float(caster.call("heal", amount)) > 0.0
	if triggered:
		biome_skill_cooldowns[owner_id] = _biome_clock + float(signature.get("cooldown_seconds", 4.0))
		var feedback: Dictionary = command.duplicate()
		feedback.merge({"shape":"ring", "origin":caster.position, "radius":29.0, "inner_radius":24.0}, true)
		_flash(feedback, Color("96dce7") if id == "capacitor_guard" else Color("b7db94"))

func _pull(command: Dictionary) -> void:
	var area: Dictionary = command.duplicate()
	area["shape"] = command.get("shape", "line")
	var cooldown: float = maxf(0.0, float(command.get("displacement_cooldown", 0.0)))
	var receipts: Variant = _property(room, "enemy_props", null)
	for victim: Node2D in _strike(area):
		if cooldown > 0.0 and (not is_instance_valid(receipts) or not receipts.has_method("displacement_ready") or not receipts.has_method("record_displacement") or not bool(receipts.call("displacement_ready", victim))):
			continue
		var direction: Vector2 = (Vector2(command.origin) - victim.position).normalized()
		if bool(command.get("repel", false)):
			direction = -direction
		var distance: float = clampf(float(command.get("pull_distance", command.get("distance", 65.0))), 0.0, 100.0)
		var displacement: Vector2 = direction * distance
		var radius: float = _radius(victim, 12.0)
		displacement *= _blocked(victim.position, victim.position + displacement, radius)
		var previous_position: Vector2 = victim.position
		victim.position = room.move_actor(victim.position, displacement, radius)
		if cooldown > 0.0 and previous_position.distance_squared_to(victim.position) > EPSILON:
			receipts.call("record_displacement", victim, cooldown)

func _support(command: Dictionary) -> void:
	var caster: Node2D = _owner(command)
	var kind: String = str(command.kind)
	if kind == "haste" and bool(command.get("require_corpse", false)):
		if not room.has_method("consume_enemy_corpse") or not bool(room.call("consume_enemy_corpse", caster, float(command.get("radius", 180.0)))):
			return
	var candidates: Array[Node2D] = []
	var container: Node = _property(room, "enemies", null)
	var plate: Node2D = null
	if kind == "guard" and str(command.get("mode", "")) == "cover":
		var plate_at: Vector2 = caster.position + Vector2(command.direction) * 42.0
		if _blocked(caster.position, plate_at, 12.0) < 1.0:
			return
		plate = _spawn_anchor(command, plate_at, _anchor_health(command, float(command.get("anchor_health", command.get("cover_hp", command.get("amount", 35.0))))), "weld_cover")
		if not is_instance_valid(plate):
			return
		var plate_health: Variant = _property(plate, "health", null)
		if plate_health is Object and plate_health.has_signal("depleted"):
			plate_health.connect("depleted", _cover_disarmed.bind(weakref(caster)), CONNECT_ONE_SHOT)
	if kind == "counter" or str(command.get("mode", "")) in ["directional", "screen", "socket"]:
		candidates.append(caster)
	elif is_instance_valid(container):
		for ally: Node in container.get_children():
			if ally is Node2D and _alive(ally) and ally.position.distance_to(caster.position) <= float(command.get("radius", 200.0)) and _line_clear(caster.position, ally.position):
				if bool(ally.get_meta("enemy_skill_anchor", false)):
					continue
				if ally == caster and bool(command.get("exclude_self", false)):
					continue
				if bool(command.get("exclude_support_recipients", false)) and ally != caster:
					var ally_profile: Dictionary = _property(ally, "profile", {})
					if str(ally_profile.get("role", "")) == "support":
						continue
				if is_instance_valid(plate) and ((ally.position - plate.position).dot(Vector2(command.direction)) >= 0.0 or absf((ally.position - plate.position).dot(Vector2(command.direction).orthogonal())) > 90.0):
					continue
				# Support networks cannot mutually recharge another same-kind support.
				if ally != caster and str(_property(ally, "enemy_id", "")) == str(_property(caster, "enemy_id", "")) and not str(_property(caster, "enemy_id", "")).is_empty():
					continue
				if kind == "heal":
					var ally_health: Variant = _property(ally, "health", null)
					var receipt: String = str(_property(room, "wave", 0)) + ":" + str(ally.get_instance_id())
					if ally_health == null or float(ally_health.current) >= float(ally_health.maximum) or int(heal_receipts.get(receipt, 0)) >= clampi(int(command.get("max_receives", command.get("per_target_limit", 2))), 1, 2):
						continue
				candidates.append(ally)
	candidates.sort_custom(func(a: Node2D, b: Node2D) -> bool: return caster.position.distance_squared_to(a.position) < caster.position.distance_squared_to(b.position))
	var target_limit: int = clampi(int(command.get("max_targets", command.get("support_targets", command.get("target_count", 3)))), 1, 3)
	for target: Node2D in candidates.slice(0, target_limit):
		var health: Variant = _property(target, "health", null)
		var maximum: float = float(_property(health, "maximum", 100.0))
		if kind == "heal":
			var key: String = str(_property(room, "wave", 0)) + ":" + str(target.get_instance_id())
			if health == null or int(heal_receipts.get(key, 0)) >= clampi(int(command.get("max_receives", command.get("per_target_limit", 2))), 1, 2):
				continue
			var before: float = float(health.current)
			var heal_amount: float = minf(maximum * 0.15, float(command.get("amount", maximum * float(command.get("heal_ratio", 0.1)))))
			if target.has_method("heal"): target.heal(heal_amount)
			else: health.current = minf(maximum, before + heal_amount)
			if float(health.current) > before:
				heal_receipts[key] = int(heal_receipts.get(key, 0)) + 1
		else:
			for old: Dictionary in supports.duplicate():
				if int(old.owner_id) == int(command.owner_id) and str(old.kind) == kind and _support_target(old) == target:
					_remove_support(old)
			var support: Dictionary = command.duplicate()
			support["target_ref"] = weakref(target)
			support["remaining"] = clampf(float(command.get("duration", 3.0)), 0.2, 6.0)
			support["amount"] = clampf(float(command.get("amount", maximum * float(command.get("shield_ratio", 0.2)))), 0.0, maximum * 0.35)
			if Numerical.is_v2(command):
				support["amount"] = mini(Numerical.integer(float(support.amount)), int(floor(maximum * 0.35)))
			support["charges"] = clampi(int(command.get("charges", 3)), 1, 4)
			support["hit_cap"] = clampi(int(command.get("hit_cap", 3)), 1, 4)
			support["hits"] = 0
			support["multiplier"] = clampf(float(command.get("multiplier", command.get("haste_multiplier", 1.18))), 1.0, 1.35)
			if is_instance_valid(plate):
				support["anchor_ref"] = weakref(plate)
			supports.append(support)
	if is_instance_valid(plate) and candidates.is_empty():
		plate.queue_free()
	_flash(command, Color("93d6aa"))

func _release_counter(support: Dictionary) -> void:
	if not _owner_alive(support) or not bool(support.get("auto_release", true)):
		return
	var command: Dictionary = support.duplicate()
	command["kind"] = "melee"
	command["shape"] = "cone"
	command["origin"] = _owner(support).position
	command["remaining"] = maxf(0.95, float(support.get("counter_release_delay", 0.95)))
	command["range"] = command.get("range", 140.0)
	command["angle"] = command.get("angle", 1.3)
	jobs.append(command)

func _scan_mark(command: Dictionary) -> void:
	var area: Dictionary = command.duplicate()
	area["shape"] = command.get("shape", "cone")
	for target: Node2D in _targets():
		if _property(room, "player", null) != null and target != _property(room, "player", null):
			continue
		if not shape_contains(area, target.position, _radius(target, 12.0)) or not _line_clear(area.origin, target.position):
			continue
		if target.has_method("dash_protected") and target.dash_protected():
			continue
		# One readable mark per room. Refreshes cannot stack shooter acceleration.
		marks.clear()
		var mark: Dictionary = command.duplicate()
		mark["target_ref"] = weakref(target)
		mark["remaining"] = clampf(float(command.get("duration", 3.0)), 0.5, 4.0)
		marks.append(mark)
		_flash(area, Color("f4dc84"))
		break

func _summon(command: Dictionary) -> void:
	if not room.has_method("spawn_enemy_summon"):
		return
	if float(command.get("hatch_delay", 0.0)) > 0.0:
		_spawn_pods(command)
		return
	var caster: Node2D = _owner(command)
	var owner_id: int = caster.get_instance_id()
	var owned: Array = summon_owners.get(owner_id, [])
	for reference: WeakRef in owned.duplicate():
		if not _alive(reference.get_ref()):
			owned.erase(reference)
	var cap: int = clampi(int(command.get("max_alive", 2)), 1, 2)
	var container: Node = _property(room, "enemies", null)
	var count: int = mini(clampi(int(command.get("count", 1)), 1, 2), cap - owned.size())
	for index: int in range(count):
		if not _owner_alive(command) or (is_instance_valid(container) and _live_child_count(container) >= MAX_ENEMIES):
			break
		var at: Vector2 = command.get("target", caster.position)
		at += Vector2(0.0, float(index) * 34.0)
		var summon: Node2D = room.call("spawn_enemy_summon", caster, "M14", at)
		if is_instance_valid(summon):
			owned.append(weakref(summon))
			var exposure: float = maxf(0.0, float(command.get("exposure_after_hatch", 0.0)))
			if exposure > 0.0:
				caster.set_meta("enemy_pod_hatched", exposure)
	summon_owners[owner_id] = owned
	_flash(command, Color("aac987"))

func _spawn_pods(command: Dictionary) -> void:
	var caster: Node2D = _owner(command)
	var owner_id: int = caster.get_instance_id()
	var occupied: int = 0
	for reference: WeakRef in summon_owners.get(owner_id, []):
		if _alive(reference.get_ref()):
			occupied += 1
	for pending: Dictionary in jobs:
		if str(pending.get("kind", "")) == "summon" and int(pending.owner_id) == owner_id:
			occupied += int(pending.get("count", 1))
	var count: int = mini(clampi(int(command.get("count", 1)), 1, 2), clampi(int(command.get("max_alive", 2)), 1, 2) - occupied)
	var supplied_points: Variant = command.get("targets", [])
	var points: Array = supplied_points if supplied_points is Array else []
	for index: int in range(count):
		var at: Vector2 = points[index] if index < points.size() and points[index] is Vector2 else Vector2(command.target) + Vector2(command.direction).orthogonal() * ((float(index) - float(count - 1) * 0.5) * 46.0)
		var anchor: Node2D = _spawn_anchor(command, at, float(command.get("pod_health", 22.0)), "summon_pod")
		if not is_instance_valid(anchor):
			continue
		var hatch: Dictionary = command.duplicate()
		hatch["count"] = 1
		hatch["origin"] = at
		hatch["target"] = at
		hatch["hatch_delay"] = 0.0
		hatch["remaining"] = clampf(float(command.get("hatch_delay", 1.2)), 0.8, 2.5)
		hatch["anchor_ref"] = weakref(anchor)
		hatch["radius"] = 24.0
		var pod_health: Variant = _property(anchor, "health", null)
		if pod_health is Object and pod_health.has_signal("depleted"):
			pod_health.connect("depleted", _pod_disarmed.bind(hatch), CONNECT_ONE_SHOT)
		jobs.append(hatch)

func _pod_disarmed(command: Dictionary) -> void:
	if bool(command.get("pod_disarmed", false)) or not _owner_alive(command):
		return
	var anchor: Node2D = _anchor(command)
	var health: Variant = _property(anchor, "health", null)
	var armor_loss: float = maxf(0.0, float(command.get("pod_break_armor_loss", 0.0)))
	# Deletion/cancellation is not a successful player disarm. Only a depleted
	# live pod may expose its mother, and this job is removed immediately after it.
	if armor_loss <= 0.0 or not bool(_property(health, "dead", false)):
		return
	command["pod_disarmed"] = true
	var caster: Node2D = _owner(command)
	if _property(caster, "armor", null) != null:
		caster.set("armor", maxf(0.0, float(caster.get("armor")) - armor_loss))
	caster.set_meta("enemy_pod_broken", true)

func _cover_disarmed(caster_ref: WeakRef) -> void:
	var caster: Node2D = caster_ref.get_ref()
	if _alive(caster):
		caster.set_meta("enemy_cover_broken", true)

func _targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	var candidates: Array = []
	if room.has_method("enemy_skill_targets"):
		candidates = room.call("enemy_skill_targets")
	else:
		candidates.append(_property(room, "player", null))
		if is_inside_tree():
			for node: Node in get_tree().get_nodes_in_group("hero_deployments"):
				if _property(node, "room", null) == room and str(_property(node, "kind", "")) == "node":
					candidates.append(node)
	for target: Variant in candidates:
		if target is Node2D and _alive(target) and target.has_method("receive_damage") and not result.has(target):
			result.append(target)
	return result

func _segment_targets(start: Vector2, end: Vector2, radius: float, ignored: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var segment: Vector2 = end - start
	for target: Node2D in _targets():
		if target.get_instance_id() in ignored:
			continue
		var combined_radius: float = radius + _radius(target, 12.0)
		var offset: Vector2 = start - target.position
		var a: float = segment.length_squared()
		var b: float = 2.0 * offset.dot(segment)
		var c: float = offset.length_squared() - combined_radius * combined_radius
		var discriminant: float = b * b - 4.0 * a * c
		var t: float = -1.0
		if c <= 0.0:
			t = 0.0
		elif a > EPSILON and discriminant >= 0.0:
			t = (-b - sqrt(discriminant)) / (2.0 * a)
		if t >= 0.0 and t <= 1.0 and _line_clear(start, target.position):
			result.append({"target":target,"t":t})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) < float(b.t))
	return result

func _support_valid(support: Dictionary) -> bool:
	if not _owner_alive(support) or not _alive(_support_target(support)) or float(support.get("remaining", 0.0)) <= 0.0:
		return false
	if support.has("anchor_ref") and not _alive(_anchor(support)):
		return false
	if str(support.get("mode", "")) == "cover":
		var offset: Vector2 = _support_target(support).position - _anchor(support).position
		if offset.dot(Vector2(support.direction)) >= 0.0 or absf(offset.dot(Vector2(support.direction).orthogonal())) > 90.0:
			return false
	if str(support.get("mode", "")) == "network":
		return _owner(support).position.distance_to(_support_target(support).position) <= float(support.get("radius", 200.0)) and _line_clear(_owner(support).position, _support_target(support).position)
	return true

func _support_target(support: Dictionary) -> Node2D:
	var reference: WeakRef = support.get("target_ref")
	return reference.get_ref() as Node2D if reference != null else null

func _spawn_anchor(command: Dictionary, at: Vector2, hit_points: float, anchor_kind: String) -> Node2D:
	if not room.has_method("spawn_enemy_skill_anchor"):
		return null
	var container: Node = _property(room, "enemies", null)
	if is_instance_valid(container) and _live_child_count(container) >= MAX_ENEMIES:
		return null
	var anchor: Node2D = room.call("spawn_enemy_skill_anchor", _owner(command), at, hit_points, anchor_kind)
	if is_instance_valid(anchor):
		anchor.set_meta("enemy_skill_anchor", true)
		anchor.set_meta("enemy_skill_anchor_kind", anchor_kind)
		anchor.set_meta("enemy_skill_anchor_direction", command.direction)
		if anchor_kind == "weld_cover" and _property(anchor, "actor_kind", null) != null:
			anchor.set("actor_kind", "cover")
	return anchor

func _anchor(effect: Dictionary) -> Node2D:
	var reference: WeakRef = effect.get("anchor_ref")
	return reference.get_ref() as Node2D if reference != null else null

func _remove_hazard(effect: Dictionary) -> void:
	hazards.erase(effect)
	_retire_anchor(effect)

func _remove_support(effect: Dictionary) -> void:
	supports.erase(effect)
	_retire_anchor(effect)

func _retire_anchor(effect: Dictionary) -> void:
	var anchor: Node2D = _anchor(effect)
	if not is_instance_valid(anchor):
		return
	for active: Dictionary in hazards + supports + jobs:
		if _anchor(active) == anchor:
			return
	anchor.queue_free()

func _owner(command: Dictionary) -> Node2D:
	var reference: WeakRef = command.get("owner")
	return reference.get_ref() as Node2D if reference != null else null

func _owner_alive(command: Dictionary) -> bool:
	return _alive(_owner(command))

func _alive(node: Variant) -> bool:
	return is_instance_valid(node) and node is Node and not node.is_queued_for_deletion() and (not node.has_method("is_alive") or bool(node.is_alive()))

func _property(object: Variant, key: String, fallback: Variant) -> Variant:
	if not is_instance_valid(object) or not object is Object:
		return fallback
	for entry: Dictionary in object.get_property_list():
		if str(entry.name) == key:
			return object.get(key)
	return fallback

func _radius(actor: Node2D, fallback: float) -> float:
	var default_radius: float = Balance.PLAYER_RADIUS if is_instance_valid(room) and actor == _property(room, "player", null) else fallback
	return float(_property(actor, "collision_radius", _property(actor, "navigation_radius", default_radius)))

func _blocked(start: Vector2, end: Vector2, radius: float) -> float:
	return clampf(float(room.blocked_fraction(start, end, radius)), 0.0, 1.0) if room.has_method("blocked_fraction") else 1.0

func _line_clear(start: Vector2, end: Vector2) -> bool:
	return _blocked(start, end, 0.0) >= 1.0 - EPSILON

func _paused() -> bool:
	return is_inside_tree() and get_tree().paused

func _live_child_count(container: Node) -> int:
	var count: int = 0
	for child: Node in container.get_children():
		if _alive(child):
			count += 1
	return count

func _segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment: Vector2 = end - start
	var t: float = clampf((point - start).dot(segment) / maxf(segment.length_squared(), EPSILON), 0.0, 1.0)
	return point.distance_to(start + segment * t)

func _line_segment(command: Dictionary) -> Array[Vector2]:
	var start: Vector2 = command.get("origin", Vector2.ZERO)
	var direction: Vector2 = command.get("direction", Vector2.RIGHT)
	var end: Vector2 = start + direction * float(command.get("range", 200.0))
	var points: Array = command.get("points", [])
	if points.size() >= 2 and points[0] is Vector2 and points[1] is Vector2:
		start = points[0]
		end = points[1]
	return [start, start.lerp(end, _blocked(start, end, 0.0))]

func _ring_interval(command: Dictionary) -> Vector2:
	if command.has("ring_start") and command.has("ring_end"):
		var start: float = float(command.ring_start)
		return Vector2(start, start + clampf(float(command.ring_end) - start, 0.0, TAU))
	var direction: Vector2 = command.get("direction", Vector2.RIGHT)
	var gap: float = deg_to_rad(clampf(float(command.get("ring_gap_degrees", 0.0)), 0.0, 180.0))
	var start: float = direction.angle() + gap * 0.5
	return Vector2(start, start + TAU - gap)

func _flash(command: Dictionary, tint: Color = Color("ffab69")) -> void:
	var visual: Dictionary = command.duplicate()
	visual["remaining"] = 0.22
	visual["color"] = command.get("fx_color",tint)
	visuals.append(visual)

func _draw() -> void:
	if not is_instance_valid(room):
		return
	# The runtime is also used by deterministic SceneTree tests before global
	# autoload names are registered. Read the optional UI setting at draw time.
	var controller: Node = get_node_or_null("/root/Game")
	var settings: Dictionary = _property(controller, "profile", {}).get("settings", {})
	if bool(settings.get("enemy_skill_paths", true)):
		for command: Dictionary in jobs:
			_draw_shape(command, Color(1.0, 0.44, 0.27, 0.2), Color("ffc481"))
	for area: Dictionary in hazards:
		var color: Color = area.get("fx_color",Color("ef936b"))
		_draw_shape(area,Color(color,.16) if area.has("boss_id") else Color(.92,.35,.2,.23),color)
	for visual: Dictionary in visuals:
		if bool(visual.get("decoy", false)):
			var at: Vector2 = visual.origin
			_draw_shape(visual, Color(0.54, 0.76, 0.86, 0.09), Color(0.72, 0.9, 0.94, 0.28))
			var texture: Texture2D = visual.get("decoy_texture")
			if texture != null:
				draw_texture_rect(texture, Rect2(at + Vector2(-28.0, -40.0), Vector2(56.0, 56.0)), false, Color(0.66, 0.83, 0.95, 0.3))
			else:
				draw_colored_polygon(PackedVector2Array([at+Vector2(-19,5),at+Vector2(-10,-30),at+Vector2(12,-34),at+Vector2(21,5)]), Color(0.54,0.76,0.86,0.22))
			draw_arc(at, 24.0, 0, TAU, 28, Color(0.72, 0.9, 0.94, 0.35), 1.0, true)
			if _owner_alive(visual):
				draw_arc(_owner(visual).position, 25.0, 0, TAU, 28, Color("f2dcb0"), 3.5, true)
		else:
			var color: Color = visual.get("color", Color("ffab69"))
			_draw_shape(visual, Color(color, 0.12), Color(color, 0.7))
			preload("res://scripts/combat/boss_skill_presentation.gd").draw_impact(self,visual,bool(settings.get("reduced_fx",false)))
	for shot: Dictionary in projectiles:
		var at: Vector2 = shot.position
		var direction: Vector2 = shot.direction
		var color: Color = shot.get("fx_color",Color("fc9065"))
		draw_line(at - direction * 17.0, at, color, 5.0, true)
		draw_circle(at, float(shot.radius), Color("fff0bc"))
		if shot.has("boss_id") and not bool(settings.get("reduced_fx",false)):
			preload("res://scripts/combat/boss_skill_presentation.gd").draw_glyph(self,str(shot.boss_id),at,float(shot.radius)+3,color,0)
	for mark: Dictionary in marks:
		var marked: Node2D = _support_target(mark)
		if _alive(marked):
			var at: Vector2 = marked.position + Vector2(0.0, -42.0)
			draw_polyline(PackedVector2Array([at + Vector2(-8.0, -6.0), at, at + Vector2(8.0, -6.0)]), Color("ffe489"), 3.0, true)
	for support: Dictionary in supports:
		if not _support_valid(support):
			continue
		var target: Node2D = _support_target(support)
		var color := Color("8ddcbd") if str(support.kind) != "counter" else Color("ffc983")
		if str(support.get("mode", "")) == "cover":
			var side: Vector2 = Vector2(support.direction).orthogonal() * 60.0
			draw_line(_anchor(support).position - side, _anchor(support).position + side, Color("bedcba"), 6.0, true)
		elif str(support.get("mode", "")) in ["directional", "screen"]:
			var facing: Vector2 = support.direction
			var half_angle: float = clampf(float(support.get("angle", 1.9)) * 0.5, 0.0, PI)
			draw_arc(target.position, 31.0, facing.angle() - half_angle, facing.angle() + half_angle, 18, color, 4.0, true)
		else:
			draw_arc(target.position, 29.0, 0, TAU, 24, Color(color, 0.8), 2.0, true)
		if str(support.get("mode", "")) == "network":
			draw_line(_owner(support).position, target.position, Color(color, 0.55), 2.0, true)

func _draw_shape(command: Dictionary, fill: Color, edge: Color) -> void:
	var origin: Vector2 = command.get("origin", Vector2.ZERO)
	var shape: String = str(command.get("shape", "circle"))
	var direction: Vector2 = command.get("direction", Vector2.RIGHT)
	var radius: float = maxf(1.0, float(command.get("radius", command.get("range", 70.0))))
	if shape == "line":
		var line: Array[Vector2] = _line_segment(command)
		origin = line[0]
		var end: Vector2 = line[1]
		if end.distance_squared_to(origin) <= EPSILON:
			return
		var half_width: Vector2 = origin.direction_to(end).orthogonal() * float(command.get("width", radius)) * 0.5
		var polygon := PackedVector2Array([origin - half_width, end - half_width, end + half_width, origin + half_width])
		draw_colored_polygon(polygon, fill)
		polygon.append(polygon[0])
		draw_polyline(polygon, edge, 1.5, true)
		return
	var start_angle: float = 0.0
	var sweep: float = TAU
	if shape == "cone":
		sweep = clampf(float(command.get("angle", 1.8)), 0.0, TAU)
		start_angle = direction.angle() - sweep * 0.5
		radius = float(command.get("range", radius))
	var inner: float = maxf(0.0, float(command.get("inner_radius", radius * 0.48))) if shape == "ring" else 0.0
	if shape == "ring":
		var interval: Vector2 = _ring_interval(command)
		start_angle = interval.x
		sweep = interval.y - interval.x
	var segments: int = 40
	var boundary := PackedVector2Array()
	for index: int in range(segments + 1):
		var ray := Vector2.from_angle(start_angle + sweep * float(index) / segments)
		var end: Vector2 = origin + ray * radius
		boundary.append(origin.lerp(end, _blocked(origin, end, 0.0)))
	for index: int in range(segments):
		var ray_a := Vector2.from_angle(start_angle + sweep * float(index) / segments)
		var ray_b := Vector2.from_angle(start_angle + sweep * float(index + 1) / segments)
		var inner_a: Vector2 = origin + ray_a * minf(inner, origin.distance_to(boundary[index]))
		var inner_b: Vector2 = origin + ray_b * minf(inner, origin.distance_to(boundary[index + 1]))
		if inner <= EPSILON:
			if absf((boundary[index] - origin).cross(boundary[index + 1] - origin)) > 0.01:
				draw_colored_polygon(PackedVector2Array([origin, boundary[index], boundary[index + 1]]), fill)
		elif origin.distance_to(boundary[index]) > inner + EPSILON and origin.distance_to(boundary[index + 1]) > inner + EPSILON:
			draw_colored_polygon(PackedVector2Array([inner_a, boundary[index], boundary[index + 1], inner_b]), fill)
	draw_polyline(boundary, edge, 1.5, true)
	if shape == "ring":
		draw_arc(origin, inner, start_angle, start_angle + sweep, segments, edge, 1.5, true)
	elif shape == "cone":
		draw_line(origin, boundary[0], edge, 1.5, true)
		draw_line(origin, boundary[-1], edge, 1.5, true)

## Authored durability is legacy units until the S09 command producer stamps scale10.
func _anchor_health(command: Dictionary, authored: float) -> float:
	var version := int(command.get("ruleset_version", Numerical.LEGACY))
	var scaled: float = authored if int(command.get("scale_version", 1)) == 10 else Numerical.scale(authored, version)
	return clampf(scaled, Numerical.scale(1.0, version), Numerical.scale(80.0, version))
