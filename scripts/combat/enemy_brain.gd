class_name EnemyBrain
extends RefCounted
## Deterministic enemy decisions. Damage, movement attacks and room objects belong
## to EnemySkillRuntime; this class never changes a health pool or actor position.

const SPAWN_GRACE: float = 0.8
const MIN_TELL: float = 0.55
const MIN_AREA_TELL: float = 0.8
const MIN_LOCK: float = 0.4
const AREA_BEHAVIORS: Array[String] = ["triple_acid_lob", "visible_burrow_strike", "spring_jump_ring", "limited_molten_stream", "cold_mist_patrol", "safe_disarm_ring"]
const RANGED_BEHAVIORS: Array[String] = ["locked_snipe_relocate", "triple_acid_lob", "rail_slide_pierce", "single_refraction_beam", "two_breakable_slow_lines"]
const SUPPORT_BEHAVIORS: Array[String] = ["consume_corpse_haste", "budgeted_pod_summon", "limited_heal_pulse", "visible_scan_mark", "finite_shield_network"]

var profile: Dictionary = {}
var parameters: Dictionary = {}
var behavior_id: String = "pick_sweep"
var mechanic_tier: int = 1
var phase: StringName = &"emerging"
var age: float = 0.0
var cycle: int = 0
var _remaining: float = SPAWN_GRACE
var _phase_duration: float = SPAWN_GRACE
var _sequence: Array[Dictionary] = []
var _stage: int = 0
var _telegraph: Dictionary = {}
var _cycle_target: Vector2 = Vector2.ZERO
var _cycle_direction: Vector2 = Vector2.RIGHT
var _cycle_origin: Vector2 = Vector2.ZERO
var _reposition_direction: Vector2 = Vector2.ZERO
var _repositioned: bool = false
var _counter_hits: int = 0
var _spent: bool = false
var _heal_pulses: int = 0
var _world_target_id: String = ""
var _utility_target: Vector2 = Vector2.ZERO
var _carried_damage: float = 0.0
var _steal_cooldown: float = 0.0
var _cover_ready_age: float = 0.0

func configure(definition: Dictionary) -> void:
	profile = definition.duplicate(true)
	parameters = profile.get("attack_parameters", {}).duplicate(true)
	behavior_id = str(profile.get("behavior_id", "pick_sweep"))
	mechanic_tier = clampi(int(profile.get("mechanic_tier", 1)), 1, 4)
	age = 0.0
	cycle = 0
	_stage = 0
	_sequence.clear()
	_telegraph.clear()
	_repositioned = false
	_spent = false
	_counter_hits = 0
	_heal_pulses = 0
	_world_target_id = ""
	_carried_damage = 0.0
	_steal_cooldown = 0.0
	_cover_ready_age = 0.0
	_set_phase(&"emerging", SPAWN_GRACE)

func current_telegraph() -> Dictionary:
	if phase != &"telegraph" and phase != &"locked":
		return {}
	var result: Dictionary = _telegraph.duplicate(true)
	result["phase"] = str(phase)
	result["locked"] = phase == &"locked"
	result["duration"] = _phase_duration
	result["progress"] = clampf(1.0 - _remaining / maxf(0.001, _phase_duration), 0.0, 1.0)
	return result

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if not is_instance_valid(actor):
		return
	actor.set("velocity", Vector2.ZERO)
	if not _alive(actor):
		_sequence.clear()
		_telegraph.clear()
		phase = &"dead"
		actor.set("state", phase)
		if behavior_id == "shadow_arc_leap":
			actor.set_meta("enemy_shadow_stealth", false)
		return
	var step: float = maxf(0.0, delta)
	age += step
	if actor.has_meta("enemy_cover_broken"):
		actor.remove_meta("enemy_cover_broken")
		_cover_ready_age = age + maxf(0.0, float(parameters.get("cover_rebuild_seconds", 8.0)))
	_steal_cooldown = maxf(0.0, _steal_cooldown - step)
	if behavior_id in ["steal_quest_object", "steal_scene_lamp"] and not _carrying(actor):
		_carried_damage = 0.0
	if actor.has_meta("enemy_pod_broken"):
		actor.remove_meta("enemy_pod_broken")
		_sequence.clear()
		_telegraph.clear()
		_set_phase(&"recovery", maxf(1.6, _recovery_seconds()))
	if actor.has_meta("enemy_pod_hatched"):
		var exposure: float = maxf(0.45, float(actor.get_meta("enemy_pod_hatched")))
		actor.remove_meta("enemy_pod_hatched")
		_sequence.clear()
		_telegraph.clear()
		_set_phase(&"recovery", maxf(exposure, _recovery_seconds()))
	if age < SPAWN_GRACE:
		_remaining = SPAWN_GRACE - age
		_publish(actor)
		return
	if not _alive(victim):
		_sequence.clear()
		_telegraph.clear()
		_set_phase(&"idle", 0.0)
		_publish(actor)
		return
	if _spent:
		_set_phase(&"spent", 0.0)
		_publish(actor)
		return
	if phase in [&"emerging", &"idle"]:
		_set_phase(&"chase", 0.0)
	_remaining = maxf(0.0, _remaining - step)
	match phase:
		&"chase":
			_chase(actor, victim)
		&"reposition":
			actor.set("velocity", _reposition_direction * _speed() * 1.3)
			if _remaining <= 0.0:
				_begin_cycle(actor, victim)
		&"telegraph":
			_refresh_geometry(actor, victim)
			actor.set("aim_direction", _telegraph.get("direction", Vector2.RIGHT))
			if _remaining <= 0.0:
				_set_phase(&"locked", _lock_seconds())
		&"locked":
			actor.set("aim_direction", _telegraph.get("direction", Vector2.RIGHT))
			var displaced_charge: bool = false
			if _telegraph.get("kind", "") == "charge":
				displaced_charge = actor.position.distance_to(_telegraph.get("origin", actor.position)) > 0.5
				var pending_knockback: Variant = _room_property(actor, "knockback")
				if pending_knockback is Vector2 and pending_knockback.length_squared() > 0.01:
					displaced_charge = true
			if displaced_charge:
				_sequence.clear()
				_telegraph.clear()
				_set_phase(&"recovery", _recovery_seconds())
			elif _remaining <= 0.0:
				_execute(actor)
		&"execute":
			if _remaining <= 0.0 and not actor.has_meta("enemy_skill_motion"):
				var recovery: float = _recovery_seconds()
				if actor.has_meta("enemy_charge_wall_stop"):
					actor.remove_meta("enemy_charge_wall_stop")
					_sequence.resize(_stage + 1)
					recovery = maxf(recovery, float(parameters.get("wall_stun_seconds", 1.2)))
				_set_phase(&"recovery", recovery)
		&"recovery":
			if _remaining <= 0.0:
				if _stage + 1 < _sequence.size():
					_stage += 1
					_begin_stage(actor, victim)
				else:
					cycle += 1
					_repositioned = false
					_sequence.clear()
					_telegraph.clear()
					if behavior_id == "safe_disarm_ring":
						_spent = true
						_set_phase(&"spent", 0.0)
					else:
						_set_phase(&"chase", 0.0)
	_publish(actor)

func on_damaged(actor: Node2D, context: Dictionary = {}) -> void:
	if not is_instance_valid(actor) or not _alive(actor):
		return
	if behavior_id in ["steal_quest_object", "steal_scene_lamp"] and _carrying(actor) and str(context.get("kind", "primary")) not in ["burn", "corrosion"]:
		_carried_damage += maxf(0.0, float(context.get("damage", 0.0)))
		var threshold: float = float(profile.get("max_hp", 60.0)) * (0.12 if bool(parameters.get("drop_on_stagger", false)) else 0.25)
		if _carried_damage >= threshold or (bool(parameters.get("drop_on_stagger", false)) and bool(context.get("stagger", false))):
			var props: Variant = _props(actor)
			if props is Object and props.has_method("return_stolen"):
				props.call("return_stolen", actor)
				_carried_damage = 0.0
				_steal_cooldown = 3.0
				_sequence.clear()
				_telegraph.clear()
				_set_phase(&"recovery", maxf(1.0, _recovery_seconds()))
				_publish(actor)
				return
	if behavior_id == "bounded_counter_stance" and phase == &"execute":
		var cap: int = clampi(int(parameters.get("counter_limit", 2)), 1, 4)
		_counter_hits = mini(_counter_hits + 1, cap)
		if _counter_hits >= cap:
			_remaining = minf(_remaining, 0.1)
		return
	# Readable support casts can be interrupted by ordinary direct attacks.
	if behavior_id in ["limited_heal_pulse", "budgeted_pod_summon", "finite_shield_network"] and phase in [&"telegraph", &"locked"] and bool(context.get("interrupt", true)):
		_sequence.clear()
		_telegraph.clear()
		_set_phase(&"recovery", maxf(0.9, _recovery_seconds()))
		_publish(actor)

func _alive(node: Node2D) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion() and (not node.has_method("is_alive") or bool(node.call("is_alive")))

func _set_phase(next: StringName, duration: float) -> void:
	phase = next
	_remaining = maxf(0.0, duration)
	_phase_duration = _remaining

func _publish(actor: Node2D) -> void:
	actor.set("state", phase)
	actor.set("state_time", _remaining)
	if behavior_id == "shadow_arc_leap":
		var props: Variant = _props(actor)
		actor.set_meta("enemy_shadow_stealth", props is Object and props.has_method("is_in_tag") and bool(props.call("is_in_tag", actor.position, "shallow_pool")) and phase in [&"chase", &"reposition"])

func _speed() -> float:
	return maxf(12.0, float(profile.get("move_speed", 96.0)))

func _range() -> float:
	return maxf(32.0, float(parameters.get("range", profile.get("attack_range", 90.0))))

func _radius() -> float:
	return maxf(12.0, float(parameters.get("radius", 64.0)))

func _lock_seconds() -> float:
	return maxf(MIN_LOCK, float(parameters.get("locked_line_delay_seconds", profile.get("locked_line_delay_seconds", 0.0))))

func _recovery_seconds() -> float:
	return maxf(0.45, maxf(float(parameters.get("recovery_seconds", profile.get("recovery_seconds", 0.9))), float(parameters.get("exposure_seconds", 0.0))))

func _room(actor: Node2D) -> Node:
	for property: Dictionary in actor.get_property_list():
		if property.get("name", "") == "room":
			var value: Variant = actor.get("room")
			return value as Node
	return null

func _navigation(actor: Node2D, target: Vector2) -> Vector2:
	var room: Node = _room(actor)
	if room != null and room.has_method("navigation_direction"):
		return room.call("navigation_direction", actor.position, target, float(profile.get("navigation_radius", 18.0)))
	return actor.position.direction_to(target)

func _can_see(actor: Node2D, target: Vector2) -> bool:
	var room: Node = _room(actor)
	return room == null or not room.has_method("has_line_of_sight") or bool(room.call("has_line_of_sight", actor.position, target))

func _world_target(actor: Node2D, action: String, fallback: Vector2) -> Vector2:
	var room: Node = _room(actor)
	if action == "socket_shield_recharge":
		action = "socket_recharge"
	if action == "consume_corpse_haste":
		var corpses: Variant = _room_property(room, "enemy_corpses")
		var zone: Variant = _room_property(actor, "zone_index")
		var nearest: Vector2 = fallback
		var distance: float = INF
		if corpses is Array:
			for corpse: Dictionary in corpses:
				var point: Vector2 = corpse.get("at", fallback)
				if (zone == null or int(corpse.get("zone", -1)) == int(zone)) and actor.position.distance_to(point) < distance:
					distance = actor.position.distance_to(point)
					nearest = point
		return nearest
	# The legacy room convenience hook returns only a point. Prefer the props
	# query for world objects so their stable identity survives the whole tell.
	if room != null and room.has_method("enemy_utility_target") and (action == "last_player_sound" or _props(actor) == null):
		var value: Variant = room.call("enemy_utility_target", actor, action)
		if value is Vector2:
			return value
		if value is Dictionary and value.get("valid", false):
			_world_target_id = str(value.get("id", ""))
			return value.get("position", fallback)
	var props: Variant = _props(actor)
	if props is Object and props.has_method("target_for"):
		var target: Dictionary = props.call("target_for", actor, action)
		if target.get("valid", false):
			_world_target_id = str(target.get("id", ""))
			return target.get("position", fallback)
	return fallback

func _props(actor: Node2D) -> Variant:
	var room: Node = _room(actor)
	var props: Variant = _room_property(room, "enemy_props")
	return props if props != null else _room_property(room, "room_props")

func _carrying(actor: Node2D) -> bool:
	var props: Variant = _props(actor)
	return props is Object and props.has_method("carried_by") and bool(props.call("carried_by", actor))

func _has_shield(actor: Node2D) -> bool:
	var status: Variant = _room_property(actor, "status")
	return status is Object and status.has_method("shield") and float(status.call("shield")) > 0.0

func _room_property(room: Node, key: String) -> Variant:
	if room != null:
		for property: Dictionary in room.get_property_list():
			if str(property.name) == key:
				return room.get(key)
	return null

func _chase(actor: Node2D, victim: Node2D) -> void:
	var target: Vector2 = victim.position
	if behavior_id == "steal_quest_object" and _carrying(actor):
		target = _world_target(actor, "return_to_nest", actor.position)
		if actor.position.distance_to(target) > 22.0:
			actor.set("aim_direction", actor.position.direction_to(target))
			actor.set("velocity", _navigation(actor, target) * _speed())
			return
		if actor.position.distance_to(victim.position) > _range():
			return
		target = victim.position
	elif behavior_id in ["steal_quest_object", "bite_breakable_wall", "steal_scene_lamp", "polarity_displacement"] or (behavior_id == "socket_shield_recharge" and not _has_shield(actor)):
		target = _world_target(actor, behavior_id, target)
	elif behavior_id == "consume_corpse_haste":
		target = _world_target(actor, behavior_id, target)
	var offset: Vector2 = target - actor.position
	var direction: Vector2 = offset.normalized() if offset.length_squared() > 0.01 else Vector2.RIGHT
	var distance: float = offset.length()
	actor.set("aim_direction", direction)
	var trigger: float = _range() + 14.0
	if not _world_target_id.is_empty() and behavior_id in ["steal_quest_object", "bite_breakable_wall", "steal_scene_lamp", "socket_shield_recharge", "polarity_displacement"]:
		trigger = maxf(24.0, _range() - 4.0)
	if SUPPORT_BEHAVIORS.has(behavior_id):
		trigger = maxf(trigger, float(parameters.get("support_radius", 240.0)))
	var preferred: float = float(parameters.get("preferred_range", _range() * 0.72))
	if RANGED_BEHAVIORS.has(behavior_id) and distance < preferred * 0.65 and not _repositioned and float(parameters.get("sidestep_distance", 0.0)) <= 0.0:
		# Retreat once, then commit even if the player keeps approaching.
		_repositioned = true
		_reposition_direction = -direction * 0.65
		_set_phase(&"reposition", 0.35)
		return
	elif distance > trigger or not _can_see(actor, target):
		var approach: Vector2 = _navigation(actor, target)
		if behavior_id in ["sidestep_thrust", "solid_ring_decoy", "shadow_arc_leap"]:
			approach = (approach + direction.orthogonal() * (0.38 if cycle % 2 == 0 else -0.38)).normalized()
		elif behavior_id == "cold_mist_patrol":
			approach = (approach + direction.orthogonal() * 0.65).normalized()
		elif behavior_id == "last_sound_charge":
			approach *= 0.6
		actor.set("velocity", approach * _speed())
		return
	if distance <= trigger and _can_see(actor, target):
		actor.set("velocity", Vector2.ZERO)
		var sidestep: float = float(parameters.get("sidestep_distance", 0.0))
		var relocation_interval: int = maxi(1, int(parameters.get("relocate_after_attacks", 2)))
		var needs_side_step: bool = sidestep > 0.0 or behavior_id in ["sidestep_thrust", "rail_slide_pierce", "solid_ring_decoy"] or (behavior_id == "locked_snipe_relocate" and cycle > 0 and cycle % relocation_interval == 0) or (behavior_id == "cold_mist_patrol" and cycle > 0)
		if needs_side_step and not _repositioned:
			_repositioned = true
			_reposition_direction = direction.orthogonal() * (1.0 if cycle % 2 == 0 else -1.0)
			_set_phase(&"reposition", maxf(0.2, sidestep / (_speed() * 1.3)) if sidestep > 0.0 else 0.35)
		else:
			_begin_cycle(actor, victim)

func _begin_cycle(actor: Node2D, victim: Node2D) -> void:
	_cycle_origin = actor.position
	if actor.has_meta("enemy_charge_wall_stop"):
		actor.remove_meta("enemy_charge_wall_stop")
	_world_target_id = ""
	_cycle_target = victim.position
	_utility_target = victim.position
	if behavior_id == "last_sound_charge":
		_cycle_target = _world_target(actor, "last_player_sound", victim.position)
	elif behavior_id in ["steal_quest_object", "bite_breakable_wall", "steal_scene_lamp", "polarity_displacement"]:
		if not _carrying(actor):
			_utility_target = _world_target(actor, behavior_id, victim.position)
	elif behavior_id == "socket_shield_recharge" and not _has_shield(actor):
		_utility_target = _world_target(actor, behavior_id, victim.position)
	_cycle_direction = actor.position.direction_to(_cycle_target)
	if _cycle_direction.length_squared() < 0.01:
		_cycle_direction = Vector2.RIGHT
	_sequence = _build_sequence()
	_stage = 0
	_counter_hits = 0
	_begin_stage(actor, victim)

func _begin_stage(actor: Node2D, victim: Node2D) -> void:
	if _stage >= _sequence.size():
		_set_phase(&"recovery", _recovery_seconds())
		return
	_telegraph = _sequence[_stage].duplicate(true)
	_telegraph["stage"] = _stage
	_telegraph["stage_count"] = _sequence.size()
	var area: bool = AREA_BEHAVIORS.has(behavior_id) or _telegraph.get("kind", "") == "ground_area" or _telegraph.get("landing_shape", "") in ["circle", "ring"]
	var tell: float = maxf(MIN_AREA_TELL if area else MIN_TELL, float(parameters.get("tell_seconds", profile.get("minimum_tell_seconds", MIN_TELL))))
	if behavior_id == "safe_disarm_ring":
		tell = maxf(tell, float(parameters.get("fuse_seconds", 1.3)))
	if _stage > 0:
		tell = maxf(tell, float(parameters.get("hazard_stagger_seconds", 0.0)))
	_telegraph["telegraph_seconds"] = tell
	if RANGED_BEHAVIORS.has(behavior_id):
		var runtime: Variant = _room_property(_room(actor), "enemy_skills")
		if runtime is Object and runtime.has_method("consume_scan_mark"):
			tell = maxf(MIN_AREA_TELL if area else MIN_TELL, tell * float(runtime.call("consume_scan_mark", actor)))
			_telegraph["telegraph_seconds"] = tell
	_telegraph["locked_seconds"] = _lock_seconds()
	_set_phase(&"telegraph", tell)
	if behavior_id == "shadow_arc_leap":
		actor.set_meta("enemy_shadow_stealth", false)
	_refresh_geometry(actor, victim)

func _refresh_geometry(actor: Node2D, victim: Node2D) -> void:
	if _telegraph.is_empty():
		return
	var target: Vector2 = victim.position if bool(_telegraph.get("track", true)) else _cycle_target
	if _telegraph.get("action", "") in ["steal_quest_object", "bite_breakable_wall", "steal_scene_lamp", "socket_recharge", "polarity_displacement"]:
		target = _utility_target
	var origin: Vector2 = actor.position
	var direction: Vector2 = origin.direction_to(target)
	if bool(_telegraph.get("fixed_cycle_direction", false)):
		direction = _cycle_direction
	if direction.length_squared() < 0.01:
		direction = _cycle_direction
	direction = direction.rotated(deg_to_rad(float(_telegraph.get("aim_offset", 0.0))))
	var length: float = float(_telegraph.get("range", _range()))
	var kind: String = str(_telegraph.get("kind", "melee"))
	if kind == "charge":
		var travel: float = minf(origin.distance_to(target), float(_sequence[_stage].get("travel_distance", length)))
		_telegraph["travel_distance"] = travel
		_telegraph["duration"] = maxf(0.1, travel / maxf(50.0, float(_telegraph.get("speed", 290.0))))
		target = origin + direction * travel
		if bool(_telegraph.get("requires_stealth_terrain", false)):
			var props: Variant = _props(actor)
			_telegraph["terrain_stealth"] = props is Object and props.has_method("is_in_tag") and bool(props.call("is_in_tag", origin, "shallow_pool"))
	elif kind == "melee" or kind == "pull" or str(_telegraph.get("shape", "")) == "cone":
		target = origin + direction * length
	elif kind == "summon":
		target = origin + direction * 55.0
	elif kind in ["heal", "haste", "guard", "counter", "decoy"]:
		target = origin
	elif str(_telegraph.get("center", "target")) == "self":
		target = origin
	else:
		target = origin + direction * minf(origin.distance_to(target), length)
	_telegraph["origin"] = origin
	_telegraph["direction"] = direction
	_telegraph["target"] = target
	_telegraph["target_position"] = target
	if kind == "utility":
		_telegraph["target_id"] = _world_target_id
		if _telegraph.get("action", "") in ["steal_quest_object", "bite_breakable_wall", "steal_scene_lamp", "socket_recharge", "polarity_displacement"]:
			_telegraph["target"] = _utility_target
			_telegraph["target_position"] = _utility_target
	var origin_offset: Array = _telegraph.get("origin_offset", [])
	if origin_offset.size() >= 2:
		origin += Vector2(float(origin_offset[0]), float(origin_offset[1])).rotated(direction.angle())
		_telegraph["origin"] = origin
	var offsets: Array = _telegraph.get("target_offsets", [])
	if not offsets.is_empty():
		var targets: Array[Vector2] = []
		for offset: Variant in offsets:
			var point: Vector2 = Vector2.ZERO
			if offset is Vector2:
				point = offset
			elif offset is Array and offset.size() >= 2:
				point = Vector2(float(offset[0]), float(offset[1]))
			targets.append(target + point.rotated(direction.angle()))
		_telegraph["targets"] = targets
	if bool(_telegraph.get("refraction", false)):
		var bend: Vector2 = origin + direction * length * 0.55
		var outgoing: Vector2 = direction.rotated(deg_to_rad(float(parameters.get("refraction_degrees", 45.0))))
		_telegraph["refraction_points"] = [bend]
		_telegraph["target"] = bend + outgoing * length * 0.45
		_telegraph["points"] = [origin, bend, _telegraph["target"]]
	if kind == "charge":
		var mode: String = str(_telegraph.get("path_mode", "line"))
		var travel: float = float(_telegraph.get("travel_distance", 0.0))
		var bend: float = float(_telegraph.get("arc_height", travel * sin(float(_telegraph.get("arc_angle", 0.65))) * 0.35)) if mode in ["arc", "leap", "burrow"] else 0.0
		var points: Array[Vector2] = []
		for index: int in range(17):
			var progress: float = float(index) / 16.0
			points.append(origin + direction * travel * progress + direction.orthogonal() * sin(PI * progress) * bend)
		_telegraph["points"] = points
	var combo_directions: Array[Vector2] = []
	var sequence_shapes: Array[String] = []
	for item: Dictionary in _sequence:
		combo_directions.append(_cycle_direction.rotated(deg_to_rad(float(item.get("aim_offset", 0.0)))))
		sequence_shapes.append(str(item.get("shape", "cone")))
	_telegraph["combo_directions"] = combo_directions
	_telegraph["sequence_shapes"] = sequence_shapes
	normalize_geometry(_telegraph)

static func normalize_geometry(command: Dictionary) -> void:
	# This is the final geometry contract shared by warning and execution. Call
	# only after all origin offsets have been applied, then freeze at lock time.
	var origin: Vector2 = command.get("origin", Vector2.ZERO)
	var direction: Vector2 = command.get("direction", Vector2.RIGHT)
	direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	command["direction"] = direction
	var kind: String = str(command.get("kind", ""))
	var shape: String = str(command.get("shape", ""))
	if shape == "line":
		var radius: float = maxf(0.0, float(command.get("projectile_radius", command.get("radius", 0.0))))
		command["width"] = float(command.get("width", radius * 2.0 if kind in ["projectile", "charge"] else radius))
	if shape == "line" and kind != "charge" and not bool(command.get("refraction", false)):
		var endpoint: Vector2 = origin + direction * float(command.get("range", 0.0))
		command["target"] = endpoint
		command["target_position"] = endpoint
		command["points"] = [origin, endpoint]
	if kind == "projectile":
		var base_path: Array = command.get("points", [origin, command.get("target", origin)])
		var angles: Array = command.get("projectile_angles", [])
		var count: int = clampi(int(command.get("count", 1)), 1, 5)
		var paths: Array = []
		for index: int in range(count):
			var angle: float = float(angles[index]) if index < angles.size() else (float(index) / maxf(1.0, float(count - 1)) - 0.5) * float(command.get("spread_degrees", 0.0))
			var path: Array[Vector2] = []
			for point: Vector2 in base_path:
				path.append(origin + (point - origin).rotated(deg_to_rad(angle)))
			paths.append(path)
		command["paths"] = paths
	if shape == "ring" or str(command.get("landing_shape", "")) == "ring":
		var gap: float = deg_to_rad(clampf(float(command.get("ring_gap_degrees", 0.0)), 0.0, 180.0))
		command["ring_start"] = direction.angle() + gap * 0.5
		command["ring_end"] = direction.angle() + TAU - gap * 0.5
	command["geometry_version"] = 1

func _execute(actor: Node2D) -> void:
	if not _alive(actor) or _telegraph.is_empty():
		return
	var command: Dictionary = _telegraph.duplicate(true)
	command["delay"] = 0.0
	command["locked"] = true
	command["counter_hits"] = _counter_hits
	if command.get("kind", "") == "guard" and command.get("mode", "") == "cover":
		if age < _cover_ready_age:
			_set_phase(&"recovery", _recovery_seconds())
			return
		_cover_ready_age = age + maxf(0.0, float(parameters.get("cover_rebuild_seconds", 8.0)))
	if command.get("kind", "") == "utility":
		var action: String = str(command.get("action", ""))
		var props: Variant = _props(actor)
		if action in ["steal_quest_object", "steal_scene_lamp", "socket_recharge", "bite_breakable_wall"] and props is Object and props.has_method("target_for") and str(command.get("target_id", "")).is_empty():
			_set_phase(&"recovery", _recovery_seconds())
			return
		if (action in ["steal_quest_object", "steal_scene_lamp"] and (_carrying(actor) or _steal_cooldown > 0.0)) or (action == "socket_recharge" and _has_shield(actor)):
			_set_phase(&"recovery", _recovery_seconds())
			return
	if command.get("kind", "") == "heal":
		if _heal_pulses >= mini(2, int(parameters.get("support_charges", 2))):
			_set_phase(&"recovery", _recovery_seconds())
			return
		_heal_pulses += 1
	if actor.has_method("cast_enemy_skill"):
		actor.call("cast_enemy_skill", command)
		if command.get("action", "") == "polarity_displacement":
			var displacement: Dictionary = command.duplicate(true)
			displacement["kind"] = "pull"
			displacement["damage_multiplier"] = 0.0
			displacement["pull_distance"] = minf(35.0, float(command.get("travel_distance", 35.0)))
			displacement["repel"] = command.get("polarity", "pull") == "push"
			actor.call("cast_enemy_skill", displacement)
	var duration: float = 0.1
	if command.get("kind", "") == "charge":
		duration = maxf(0.15, float(command.get("travel_distance", 100.0)) / maxf(50.0, float(command.get("speed", 280.0))))
	elif command.get("kind", "") == "counter":
		duration = maxf(0.3, float(command.get("duration", 1.0)))
	_set_phase(&"execute", duration)

func _skill(kind: String, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"kind": kind, "behavior_id": behavior_id, "enemy_id": profile.get("enemy_id", ""),
		"shape": "cone" if kind == "melee" else "circle", "range": _range(), "radius": _radius(),
		"angle": deg_to_rad(90.0), "damage_multiplier": float(parameters.get("damage_multiplier", 1.0)),
		"duration": 0.0, "track": true, "damage_kind": profile.get("damage_kind", "kinetic"),
		"exposure_seconds": float(parameters.get("exposure_seconds", 0.0)),
	}
	for key: Variant in options:
		result[key] = options[key]
	return result

func _charge(path: String, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _skill("charge", {
		"shape": "line", "path_mode": path, "travel_distance": float(parameters.get("lunge_distance", _range())),
		"speed": float(parameters.get("charge_speed", 290.0)), "radius": 20.0, "track": false,
		"expose_on_wall": true, "landing_only": path in ["leap", "burrow"],
	})
	for key: Variant in options:
		result[key] = options[key]
	return result

func _status(id: String, duration: float = 2.0) -> Dictionary:
	return {"id": id, "duration": duration, "magnitude": 0.8}

func _projectile(options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _skill("projectile", {
		"shape": "line", "count": clampi(int(parameters.get("projectile_count", 1)), 1, 5),
		"projectile_angles": parameters.get("projectile_angles", []),
		"spread_degrees": float(parameters.get("spread_degrees", 0.0)),
		"speed": float(parameters.get("projectile_speed", 340.0)), "radius": 6.0,
	})
	for key: Variant in options:
		result[key] = options[key]
	return result

func _hazard(options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _skill("ground_area", {
		"duration": minf(6.0, float(parameters.get("hazard_duration", 2.5))),
		"max_active_hazards": clampi(int(parameters.get("max_active_hazards", 2)), 1, 2),
		"max_count": 2, "tick_interval": 0.65,
	})
	for key: Variant in options:
		result[key] = options[key]
	return result

func _support(kind: String, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = _skill(kind, {
		"radius": float(parameters.get("support_radius", 240.0)),
		"range": float(parameters.get("support_radius", 240.0)),
		"max_targets": clampi(int(parameters.get("support_targets", 2)), 1, 3),
		"support_targets": clampi(int(parameters.get("support_targets", 2)), 1, 4),
		"charges": clampi(int(parameters.get("support_charges", 1)), 1, 4),
		"support_charges": clampi(int(parameters.get("support_charges", 1)), 1, 4),
		"duration": minf(5.0, float(parameters.get("buff_duration", 3.0))),
		"exclude_same_behavior": true,
		"exclude_self": kind in ["heal", "haste"],
	})
	for key: Variant in options:
		result[key] = options[key]
	return result

func _build_sequence() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var combos: int = clampi(int(parameters.get("combo_count", 1)), 1, 3)
	var angles: Array = parameters.get("combo_angles", [0.0])
	var offsets: Array = parameters.get("hazard_offsets", [])
	var arc: float = deg_to_rad(float(parameters.get("arc_degrees", 65.0)))
	match behavior_id:
		"pick_sweep":
			if float(parameters.get("lunge_distance", 0.0)) > 0.0:
				result.append(_charge("line", {"damage_multiplier": 0.0, "radius": 12.0}))
			_append_swings(result, combos, {"angle": deg_to_rad(115.0)})
		"locked_charge":
			result.append(_charge("line", {"radius": 23.0, "wall_stun_seconds": float(parameters.get("wall_stun_seconds", 1.2))}))
			_append_swings(result, combos - 1, {"angle": deg_to_rad(70.0), "range": 72.0, "fixed_cycle_direction": true}, 1)
		"locked_snipe_relocate":
			result.append(_projectile({"pierce": false, "radius": 5.0}))
		"shell_sting_leap":
			result.append(_charge("leap", {"landing_shape": "cone", "angle": deg_to_rad(35.0), "radius": 26.0, "arc_height": 0.0}))
			_append_swings(result, combos - 1, {"shape": "line", "angle": deg_to_rad(24.0), "range": 80.0, "radius": 12.0}, 1)
		"arc_roll_expose":
			if mechanic_tier >= 2 and cycle % 2 == 1:
				arc = -arc
			result.append(_charge("arc", {"arc_angle": arc, "radius": 28.0}))
			_append_swings(result, combos - 1, {"angle": deg_to_rad(95.0), "range": 78.0, "fixed_cycle_direction": true}, 1)
		"deploy_weld_cover":
			if age >= _cover_ready_age:
				result.append(_support("guard", {"mode": "cover", "duration": 3.0, "cover_hp": float(parameters.get("cover_hp", 28.0)), "anchor_health": float(parameters.get("cover_hp", 28.0)), "cover_rebuild_seconds": float(parameters.get("cover_rebuild_seconds", 8.0)), "angle": deg_to_rad(float(parameters.get("guard_arc_degrees", 100.0)))}))
			_append_swings(result, combos, {"angle": deg_to_rad(45.0), "status": _status("burn")})
		"hook_tether":
			result.append(_skill("pull", {"shape": "line", "radius": 12.0, "requires_hit": true, "pull_distance": minf(85.0, float(parameters.get("pull_distance", 70.0)))}))
			_append_swings(result, combos - 1, {"range": 75.0, "angle": deg_to_rad(75.0), "fixed_cycle_direction": true}, 1)
		"rotate_rivet_shield":
			result.append(_skill("guard", {"mode": "directional", "duration": float(parameters.get("guard_duration", 2.5)), "shield_ratio": minf(0.35, float(parameters.get("guard_ratio", 0.45))), "angle": deg_to_rad(float(parameters.get("guard_arc_degrees", 100.0))), "charges": 3, "aim_offset": float(parameters.get("shield_turn_degrees", 0.0))}))
			_append_swings(result, combos, {"angle": deg_to_rad(95.0), "fixed_cycle_direction": true})
		"consume_corpse_haste":
			result.append(_support("haste", {"require_corpse": true, "consume_corpse": true, "multiplier": 1.0 + float(parameters.get("haste_ratio", 0.15))}))
			if combos > 1:
				_append_swings(result, combos, {"angle": deg_to_rad(100.0), "range": 62.0})
		"sidestep_thrust":
			_append_swings(result, combos, {"shape": "line", "angle": deg_to_rad(22.0), "radius": 12.0})
		"triple_acid_lob":
			if offsets.is_empty():
				offsets = [[0.0, -46.0], [18.0, 0.0], [0.0, 46.0]]
			for offset: Variant in offsets.slice(0, 3):
				var landing: Array = offset.duplicate()
				if bool(parameters.get("alternate_pattern", false)) and cycle % 2 == 1:
					landing[1] = -float(landing[1])
				result.append(_hazard({"target_offsets": [landing], "lob": true, "status": _status("corrosion"), "max_active_hazards": 2}))
		"budgeted_pod_summon":
			result.append(_support("summon", {"enemy_id": "M14", "count": mini(2, int(parameters.get("summon_count", 1))), "max_alive": 2, "summon_cap": 2, "breakable": true, "reserve_budget": true, "hatch_delay": float(parameters.get("pod_hatch_seconds", 1.4)), "pod_health": float(parameters.get("pod_hp", 18.0)), "pod_break_armor_loss": float(parameters.get("pod_break_armor_loss", 0.0)), "exposure_after_hatch": float(parameters.get("exposure_seconds", 1.6)) if mechanic_tier >= 4 else 0.0, "target_offsets": offsets}))
		"cross_scissor":
			_append_swings(result, combos, {"shape": "line", "angle": deg_to_rad(35.0), "radius": 17.0, "fixed_cycle_direction": true, "track": false})
		"sticky_hop":
			result.append(_charge("leap", {"landing_shape": "circle", "radius": _radius(), "arc_height": 0.0}))
			result.append(_hazard({"center": "self", "radius": _radius(), "target_offsets": offsets, "damage_multiplier": 0.0, "status": _status("slow", 0.8)}))
			_append_swings(result, combos - 1, {"shape": "line", "radius": 10.0, "range": 58.0, "angle": deg_to_rad(30.0)}, 1)
		"visible_burrow_strike":
			result.append(_charge("burrow", {"visible_path": true, "landing_shape": "circle", "radius": _radius(), "speed": 180.0, "arc_angle": deg_to_rad(float(parameters.get("arc_degrees", 0.0))), "arc_height": float(parameters.get("lunge_distance", 170.0)) * sin(deg_to_rad(float(parameters.get("arc_degrees", 0.0)))) * 0.35}))
			_append_swings(result, combos - 1, {"range": 82.0, "angle": deg_to_rad(105.0), "fixed_cycle_direction": true}, 1)
		"steal_quest_object":
			result.append(_skill("utility", {"action": "steal_quest_object", "track": false, "carry_limit": 1, "return_intact": true}))
			_append_swings(result, combos, {"range": 60.0, "angle": deg_to_rad(55.0), "fixed_cycle_direction": true})
		"limited_heal_pulse":
			if _heal_pulses < mini(2, int(parameters.get("support_charges", 2))):
				result.append(_support("heal", {"heal_ratio": float(parameters.get("heal_ratio", 0.08)), "max_receives": 2, "exclude_self": true, "exclude_support_recipients": true}))
			else:
				result.append(_skill("melee", {"angle": deg_to_rad(160.0), "range": 58.0, "damage_multiplier": 0.6}))
			if combos > 1:
				_append_swings(result, combos, {"angle": deg_to_rad(65.0), "range": 68.0})
		"bite_breakable_wall":
			result.append(_skill("utility", {"action": "bite_breakable_wall", "breakable_wall_cap": int(parameters.get("breakable_wall_cap", 1)), "track": false}))
			_append_swings(result, combos, {"angle": deg_to_rad(125.0), "fixed_cycle_direction": true})
		"visible_scan_mark":
			for index: int in range(combos):
				result.append(_skill("utility", {"action": "scan_mark", "shape": "cone", "angle": deg_to_rad(float(parameters.get("spread_degrees", 50.0))), "aim_offset": _angle(angles, index, 0.0), "duration": float(parameters.get("mark_duration", 2.5)), "support_targets": 1, "lock_multiplier": 0.85, "minimum_lock_seconds": MIN_LOCK}))
		"rail_slide_pierce":
			result.append(_projectile({"pierce": int(parameters.get("projectile_pierces", 1)), "radius": 5.0}))
		"spring_jump_ring":
			result.append(_charge("leap", {"landing_shape": "ring", "radius": _radius(), "inner_radius": _radius() * 0.3, "status": _status("shock"), "arc_height": 0.0}))
			_append_swings(result, combos - 1, {"range": 80.0, "angle": deg_to_rad(65.0), "status": _status("shock"), "fixed_cycle_direction": true}, 1)
		"limited_molten_stream":
			for index: int in range(combos):
				result.append(_hazard({"shape": "cone", "angle": deg_to_rad(45.0), "aim_offset": _angle(angles, index, 0.0), "status": _status("burn")}))
			if not offsets.is_empty():
				result.append(_hazard({"shape": "line", "radius": 16.0, "origin_offset": offsets.back(), "aim_offset": float(parameters.get("arc_degrees", 30.0)) * (-1.0 if mechanic_tier >= 3 else 1.0), "status": _status("burn")}))
		"polarity_displacement":
			for index: int in range(combos):
				result.append(_skill("utility", {"action": "polarity_displacement", "shape": "cone", "angle": deg_to_rad(80.0), "aim_offset": _angle(angles, index, 0.0), "polarity": "pull" if (cycle + index) % 2 == 0 else "push", "travel_distance": minf(35.0, float(parameters.get("pull_distance", 35.0))), "displacement_cooldown": float(parameters.get("displacement_cooldown", 3.0)), "player_pull": true, "preserve_dash": true}))
		"cold_mist_patrol":
			result.append(_hazard({"status": _status("chill"), "target_offsets": offsets, "slow": float(parameters.get("slow_ratio", 0.2))}))
			_append_swings(result, combos - 1, {"range": 95.0, "angle": deg_to_rad(65.0), "status": _status("chill")}, 1)
		"socket_shield_recharge":
			result.append(_skill("utility", {"action": "socket_recharge", "guard_ratio": float(parameters.get("guard_ratio", 0.3)), "shield_ratio": float(parameters.get("guard_ratio", 0.3)), "track": false, "duration": float(parameters.get("recharge_seconds", 1.6)), "only_if_depleted": true}))
			_append_swings(result, combos, {"angle": deg_to_rad(80.0), "status": _status("shock")})
		"finite_projectile_screen":
			result.append(_skill("guard", {"mode": "screen", "duration": float(parameters.get("screen_seconds", 1.0)), "charges": int(parameters.get("screen_projectile_cap", 2)), "angle": deg_to_rad(float(parameters.get("guard_arc_degrees", 90.0))), "aim_offset": float(parameters.get("shield_turn_degrees", 0.0)), "radius": 42.0}))
			_append_swings(result, combos, {"angle": deg_to_rad(45.0), "range": 85.0})
		"numbered_two_beat_sweep":
			for index: int in range(combos):
				result.append(_skill("melee", {"shape": "line" if index == 0 else "cone", "angle": deg_to_rad(35.0 if index == 0 else 120.0), "radius": 18.0, "aim_offset": _angle(angles, index, 0.0), "beat": index + 1, "fixed_cycle_direction": true, "track": false}))
		"last_sound_charge":
			result.append(_charge("line", {"target_last_sound": true, "radius": 14.0, "speed": 320.0}))
			_append_swings(result, combos - 1, {"angle": deg_to_rad(45.0), "range": 52.0, "track": false, "fixed_cycle_direction": true}, 1)
		"solid_ring_decoy":
			result.append(_skill("decoy", {"count": 1, "duration": 2.5, "radius": 70.0, "damage_multiplier": 0.0, "breakable_hits": 1, "solid_owner_ring": true}))
			_append_swings(result, combos, {"angle": deg_to_rad(60.0), "fixed_cycle_direction": true})
		"finite_shield_network":
			result.append(_support("guard", {"mode": "network", "charges": mini(2, int(parameters.get("support_charges", 2))), "shield_ratio": float(parameters.get("guard_ratio", 0.18)), "break_on_range": true, "exclude_self": true, "exclude_support_recipients": true}))
			if combos > 1:
				_append_swings(result, combos, {"angle": deg_to_rad(70.0), "range": 70.0, "damage_multiplier": 0.65})
		"single_refraction_beam":
			result.append(_projectile({"refraction": true, "max_reflections": 1, "pierce": true, "status": _status("chill"), "radius": 7.0}))
		"shadow_arc_leap":
			result.append(_charge("arc", {"landing_only": true, "landing_shape": "circle", "arc_angle": arc, "requires_stealth_terrain": true, "radius": 36.0, "speed": 240.0}))
			_append_swings(result, combos - 1, {"angle": deg_to_rad(100.0), "range": 70.0}, 1)
		"two_breakable_slow_lines":
			var lines: int = clampi(int(parameters.get("line_count", 1)), 1, 2)
			for index: int in range(lines):
				result.append(_hazard({"shape": "line", "radius": 9.0, "damage_multiplier": 0.0, "status": _status("slow", 0.8), "breakable": true, "anchor_health": float(parameters.get("line_node_hp", 16.0)), "max_active_hazards": 2, "aim_offset": _angle(angles, index, -25.0 if index == 0 else 25.0), "origin_offset": offsets[index] if index < offsets.size() else [], "track": false}))
		"bounded_counter_stance":
			result.append(_skill("counter", {"duration": float(parameters.get("counter_stance_seconds", 1.2)), "hit_cap": int(parameters.get("counter_limit", 2)), "angle": deg_to_rad(float(parameters.get("guard_arc_degrees", 100.0))), "aim_offset": float(parameters.get("shield_turn_degrees", 0.0)), "auto_release": false, "track": false, "fixed_cycle_direction": true}))
			_append_swings(result, combos, {"shape": "line", "radius": 20.0, "angle": deg_to_rad(45.0), "track": false, "fixed_cycle_direction": true})
		"steal_scene_lamp":
			result.append(_skill("utility", {"action": "steal_scene_lamp", "track": false, "radius": float(parameters.get("dark_field_radius", 110.0)), "duration": 5.0, "return_intact": true, "keep_telegraphs_visible": true, "carry_limit": 1}))
			_append_swings(result, combos, {"angle": deg_to_rad(105.0), "range": 70.0, "fixed_cycle_direction": true})
		"safe_disarm_ring":
			result.append(_hazard({"shape": "ring", "center": "self", "duration": 0.0, "radius": _radius(), "inner_radius": 0.0, "ring_gap_degrees": float(parameters.get("ring_gap_degrees", 0.0)), "single_use": true, "cancel_on_death": true, "status": _status("shock")}))
		_:
			result.append(_skill("melee"))
	if bool(parameters.get("elite_aftershock", false)) and behavior_id != "safe_disarm_ring":
		result.append(_hazard({"shape": "line", "radius": float(parameters.get("elite_aftershock_width", 20.0)), "duration": float(parameters.get("elite_aftershock_duration", 0.35)), "tick_interval": 0.35, "damage_multiplier": float(parameters.get("elite_aftershock_damage_multiplier", 0.35)), "track": false, "fixed_cycle_direction": true}))
	return result

func _append_swings(result: Array[Dictionary], count: int, options: Dictionary, angle_start: int = 0) -> void:
	var angles: Array = parameters.get("combo_angles", [0.0])
	for index: int in range(maxi(0, count)):
		var swing: Dictionary = options.duplicate(true)
		swing["aim_offset"] = _angle(angles, index + angle_start, 0.0)
		result.append(_skill("melee", swing))

func _angle(values: Array, index: int, fallback: float) -> float:
	var value: float = float(values[index]) if index < values.size() else fallback
	return -value if bool(parameters.get("alternate_pattern", false)) and cycle % 2 == 1 else value

