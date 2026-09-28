class_name BossBrain
extends RefCounted
## Deterministic three-phase boss state machine. It produces the same frozen
## command dictionaries consumed by EnemySkillRuntime and drawn by MineRoom.
## Arena objects call apply_arena_counter(); the host actor owns phase cleanup,
## finite reinforcement requests and the completion signal.

const EPSILON := 0.00001
const SEQUENCES := {
	"BO01": {1:["hammer_fan", "ladle_drag"], 2:["hammer_fan", "slag_lane", "ladle_drag"], 3:["hammer_fan", "ladle_drag", "back_heat"]},
	"BO02": {1:["root_fork", "spore_pod"], 2:["root_fork", "root_link", "spore_pod"], 3:["root_fork", "spore_pod", "crown_open"]},
	"BO03": {1:["glide", "capacitor_burst"], 2:["runway_pair", "capacitor_burst", "glide"], 3:["runway_pair", "sweep_land", "capacitor_burst"]},
	"BO04": {1:["resonance_ring", "sound_blade"], 2:["replay_path", "resonance_ring", "sound_blade"], 3:["alternating_ring", "replay_path", "heart_crack"]},
}

var definition: Dictionary = {}
var boss_id: String = ""
var phase: int = 1
var state: StringName = &"emerging"
var state_time: float = 0.8
var state_duration: float = 0.8
var action_index: int = 0
var current_action: String = ""
var command: Dictionary = {}
var weakpoint: String = ""
var weakpoint_time: float = 0.0
var _pending_weakpoint: String = ""
var _pending_weakpoint_time: float = 0.0
var _pending_weakpoint_duration: float = 0.0
var elapsed: float = 0.0
var stopped: bool = false
var _rng := RandomNumberGenerator.new()
var _lane_cursor: int = 0
var _disabled_lane: int = -1
var _disabled_lane_uses: int = 0
var _broken_roots: Array[int] = []
var _used_fuses: Array[int] = []
var _broken_bells: Array[int] = []
var _trail_history: Array[Vector2] = []
var _sample_time: float = 0.0
var _ring_toggle: bool = false

func configure(next_definition: Dictionary, seed_value: int = 0) -> void:
	definition = next_definition.duplicate(true)
	boss_id = str(definition.get("boss_id", definition.get("enemy_id", "")))
	phase = 1
	state = &"emerging"
	state_time = 0.8
	state_duration = state_time
	action_index = 0
	current_action = ""
	command.clear()
	weakpoint = ""
	weakpoint_time = 0.0
	_pending_weakpoint = ""
	_pending_weakpoint_time = 0.0
	_pending_weakpoint_duration = 0.0
	elapsed = 0.0
	stopped = false
	_lane_cursor = 0
	_disabled_lane = -1
	_disabled_lane_uses = 0
	_broken_roots.clear()
	_used_fuses.clear()
	_broken_bells.clear()
	_trail_history.clear()
	_sample_time = 0.0
	_ring_toggle = false
	_rng.seed = (seed_value if seed_value != 0 else boss_id.hash() ^ 0xB055)

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or delta <= 0.0 or not is_instance_valid(actor) or not _alive(victim):
		return
	elapsed += delta
	_sample_victim(victim, delta)
	_update_weakpoint(actor, delta)
	var next_phase: int = _phase_for_ratio(_health_ratio(actor))
	while phase < next_phase:
		phase += 1
		_enter_phase(actor)
	if state == &"phase_shift":
		state_time -= delta
		_set_actor_state(actor, &"recovery")
		if state_time <= 0.0:
			_begin_action(actor, victim)
		return
	if state == &"emerging":
		state_time -= delta
		_set_actor_state(actor, &"emerging")
		if state_time <= 0.0:
			_begin_action(actor, victim)
		return
	if state == &"telegraph":
		state_time -= delta
		if bool(command.get("tracks_target", true)):
			_retarget(actor, victim)
		_set_actor_state(actor, &"telegraph")
		if state_time <= 0.0:
			command = _freeze_geometry(actor, command)
			state = &"locked"
			state_time = maxf(0.24, float(command.get("lock", 0.32)))
			state_duration = state_time
		return
	if state == &"locked":
		state_time -= delta
		_set_actor_state(actor, &"locked")
		if state_time <= 0.0:
			_execute(actor)
		return
	if state == &"recovery":
		state_time -= delta
		_set_actor_state(actor, &"recovery")
		if state_time <= 0.0:
			_begin_action(actor, victim)

func current_telegraph() -> Dictionary:
	if state not in [&"telegraph", &"locked"] or command.is_empty():
		return {}
	var result: Dictionary = command.duplicate(true)
	result["locked"] = state == &"locked"
	result["progress"] = clampf(1.0 - state_time / maxf(EPSILON, state_duration), 0.0, 1.0)
	result["boss_id"] = boss_id
	result["phase"] = phase
	return result

func phase_index() -> int:
	return phase

func state_name() -> StringName:
	return state

func weakpoint_open() -> bool:
	return not weakpoint.is_empty() and weakpoint_time > 0.0

func incoming_damage_multiplier() -> float:
	return 1.35 if weakpoint_open() else 1.0

func on_damaged(actor: Node2D, context: Dictionary) -> void:
	# Bosses never use a generic stagger meter. An explicit interrupt only works
	# during an authored weakpoint window and converts its remainder to recovery.
	if not weakpoint_open() or not bool(context.get("interrupt", context.get("force_interrupt", false))):
		return
	_close_weakpoint(actor)
	command.clear()
	state = &"recovery"
	state_time = maxf(state_time, 1.25)
	state_duration = state_time
	_set_actor_state(actor, &"recovery")

func apply_arena_counter(counter_id: String, payload: Dictionary = {}) -> bool:
	var parsed: Dictionary = _parse_counter(counter_id, payload)
	var kind: String = str(parsed.kind)
	var lane: int = int(parsed.lane)
	match boss_id:
		"BO01":
			if kind != "cooling_valve" or lane < 0 or lane > 2:
				return false
			_disabled_lane = lane
			_disabled_lane_uses = 2
			if current_action == "slag_lane" and int(command.get("lane_index", -1)) == lane and state in [&"telegraph",&"locked"]:
				# The valve visibly extinguishes the warned lane instead of letting
				# an already selected direction hit through its arena counter.
				command.clear()
				state = &"recovery"
				state_time = 0.8
				state_duration = state_time
			return true
		"BO02":
			if kind != "root_knot" or lane < 0 or lane > 3 or lane in _broken_roots:
				return false
			_broken_roots.append(lane)
			if current_action == "root_fork" and state in [&"telegraph",&"locked"]:
				_remove_last_live_path()
			return true
		"BO03":
			if kind != "fuse_box" or lane < 0 or lane > 3 or lane in _used_fuses:
				return false
			_used_fuses.append(lane)
			_disabled_lane = lane
			_disabled_lane_uses = 1
			if current_action == "runway_pair" and state in [&"telegraph",&"locked"]:
				var lanes: Array = command.get("lane_indices", [])
				var path_index: int = lanes.find(lane)
				if path_index >= 0 and command.get("paths", []).size() > 1:
					command.paths.remove_at(path_index)
					lanes.remove_at(path_index)
					command.count = command.paths.size()
					_disabled_lane = -1
					_disabled_lane_uses = 0
			return true
		"BO04":
			if kind != "edge_bell" or lane < 0 or lane > 3 or lane in _broken_bells:
				return false
			_broken_bells.append(lane)
			if current_action == "replay_path" and state in [&"telegraph",&"locked"]:
				_remove_last_live_path()
			return true
	return false

func counter_snapshot() -> Dictionary:
	return {
		"disabled_lane": _disabled_lane,
		"disabled_lane_uses": _disabled_lane_uses,
		"broken_roots": _broken_roots.duplicate(),
		"used_fuses": _used_fuses.duplicate(),
		"broken_bells": _broken_bells.duplicate(),
	}

func combat_snapshot() -> Dictionary:
	return {
		"boss_id": boss_id,
		"phase": phase,
		"state": str(state),
		"action": current_action,
		"weakpoint": weakpoint,
		"weakpoint_remaining": weakpoint_time,
		"telegraph": current_telegraph(),
		"counters": counter_snapshot(),
	}

func stop(actor: Node2D = null) -> void:
	stopped = true
	command.clear()
	if is_instance_valid(actor):
		_close_weakpoint(actor)

func _enter_phase(actor: Node2D) -> void:
	command.clear()
	action_index = 0
	current_action = ""
	_close_weakpoint(actor)
	state = &"phase_shift"
	state_time = 0.9
	state_duration = state_time
	if actor.has_method("boss_phase_started"):
		actor.call("boss_phase_started", phase, _health_ratio(actor))

func _begin_action(actor: Node2D, victim: Node2D) -> void:
	var sequence: Array = SEQUENCES.get(boss_id, {}).get(phase, [])
	if sequence.is_empty():
		state = &"recovery"
		state_time = 1.0
		return
	current_action = str(sequence[action_index % sequence.size()])
	action_index += 1
	command = _build_action(actor, victim, current_action)
	if command.is_empty():
		state = &"recovery"
		state_time = 0.35
		state_duration = state_time
		return
	_retarget(actor, victim)
	state = &"telegraph"
	state_time = maxf(0.55, float(command.get("tell", 0.8)))
	state_duration = state_time
	_set_actor_state(actor, &"telegraph")

func _execute(actor: Node2D) -> void:
	var released: Dictionary = command.duplicate(true)
	if actor.has_method("cast_enemy_skill"):
		actor.call("cast_enemy_skill", released)
	var opening: float = maxf(0.0, float(released.get("weakpoint_duration", 0.0)))
	if opening > 0.0:
		var opening_delay: float = maxf(0.0, float(released.get("weakpoint_delay", 0.0)))
		if opening_delay > 0.0:
			_pending_weakpoint = str(released.get("weakpoint_id", current_action))
			_pending_weakpoint_time = opening_delay
			_pending_weakpoint_duration = opening
		else:
			_open_weakpoint(actor, str(released.get("weakpoint_id", current_action)), opening)
	state = &"recovery"
	state_time = maxf(0.45, maxf(float(released.get("recovery", 1.0)), float(released.get("weakpoint_delay", 0.0)) + opening))
	state_duration = state_time
	command.clear()
	_set_actor_state(actor, &"recovery")

func _build_action(actor: Node2D, victim: Node2D, action: String) -> Dictionary:
	var origin: Vector2 = actor.position
	var target: Vector2 = victim.position
	var direction: Vector2 = origin.direction_to(target)
	if direction.length_squared() <= EPSILON:
		direction = Vector2.RIGHT
	var base := {"action_id":action, "behavior_id":"boss_"+boss_id.to_lower(), "origin":origin, "target":target, "direction":direction, "tracks_target":true}
	match action:
		"hammer_fan":
			base.merge({"kind":"melee", "shape":"cone", "range":255.0, "angle":1.85, "damage_multiplier":1.15, "tell":0.78, "lock":0.34, "recovery":1.0})
		"ladle_drag":
			base.merge({"kind":"ground_area", "shape":"line", "range":680.0, "width":58.0, "duration":3.2, "tick_interval":0.65, "max_active_hazards":2, "damage_multiplier":0.38, "status":{"id":"burn", "duration":2.4}, "tell":0.85, "lock":0.36, "recovery":1.05})
		"slag_lane":
			var lane: int = _next_lane(3)
			var lane_direction: Vector2 = Vector2.RIGHT.rotated(lane * TAU / 3.0)
			base.merge({"kind":"ground_area", "shape":"line", "range":740.0, "width":82.0, "duration":3.8, "tick_interval":0.7, "max_active_hazards":2, "damage_multiplier":0.34, "status":{"id":"burn", "duration":2.6}, "direction":lane_direction, "target":origin+lane_direction*740.0, "lane_index":lane, "tracks_target":false, "tell":0.92, "lock":0.4, "recovery":1.0})
		"back_heat":
			var safe: Vector2 = -direction
			base.merge({"kind":"ground_area", "shape":"ring", "target":origin, "radius":285.0, "inner_radius":105.0, "ring_gap_degrees":92.0, "direction":safe, "duration":0.0, "damage_multiplier":1.0, "weakpoint_id":"furnace_back", "weakpoint_duration":2.1, "tracks_target":true, "tell":1.0, "lock":0.42, "recovery":2.1})
		"root_fork":
			var fork_count: int = maxi(1, 3 - mini(2, _broken_roots.size()))
			var paths: Array = _fork_paths(origin, target, fork_count)
			base.merge({"kind":"projectile", "shape":"line", "paths":paths, "count":paths.size(), "width":24.0, "speed":390.0, "projectile_radius":10.0, "damage_multiplier":0.62, "status":{"id":"corrosion", "duration":2.8}, "tracks_target":true, "tell":0.9, "lock":0.38, "recovery":1.0})
		"spore_pod":
			base.merge({"kind":"ground_area", "shape":"circle", "targets":[target], "radius":105.0, "duration":3.3, "tick_interval":0.65, "max_active_hazards":2, "lob":true, "damage_multiplier":0.42, "status":{"id":"corrosion", "duration":3.0}, "tell":0.88, "lock":0.4, "recovery":1.15})
		"root_link":
			var root_lane: int = _next_available(4, _broken_roots)
			var root_direction: Vector2 = Vector2.RIGHT.rotated(root_lane * PI * 0.5 + PI * 0.25)
			base.merge({"kind":"ground_area", "shape":"line", "range":720.0, "width":68.0, "duration":2.8, "tick_interval":0.7, "damage_multiplier":0.36, "status":{"id":"corrosion", "duration":2.6}, "direction":root_direction, "target":origin+root_direction*720.0, "lane_index":root_lane, "tracks_target":false, "tell":0.9, "lock":0.38, "recovery":1.0})
		"crown_open":
			base.merge({"kind":"ground_area", "shape":"ring", "target":origin, "radius":260.0, "inner_radius":110.0, "ring_gap_degrees":78.0, "damage_multiplier":0.9, "duration":0.0, "weakpoint_id":"open_crown", "weakpoint_duration":2.35, "tell":0.95, "lock":0.42, "recovery":2.35})
		"glide":
			base.merge({"kind":"charge", "shape":"line", "range":570.0, "travel_distance":570.0, "width":72.0, "radius":36.0, "speed":510.0, "damage_multiplier":1.0, "tell":0.82, "lock":0.4, "recovery":1.15})
		"capacitor_burst":
			base.merge({"kind":"projectile", "shape":"line", "range":880.0, "count":4, "projectile_angles":[-27.0,-9.0,9.0,27.0], "width":18.0, "speed":560.0, "projectile_radius":8.0, "damage_multiplier":0.58, "status":{"id":"shock", "duration":2.6}, "tell":0.9, "lock":0.38, "recovery":1.05})
		"runway_pair":
			var runway_lanes: Array[int] = _select_runway_lanes(2)
			var runway_paths: Array = _runway_paths(origin, direction, runway_lanes)
			base.merge({"kind":"projectile", "shape":"line", "paths":runway_paths, "lane_indices":runway_lanes, "count":runway_paths.size(), "width":30.0, "speed":720.0, "projectile_radius":12.0, "damage_multiplier":0.66, "status":{"id":"shock", "duration":2.4}, "tracks_target":true, "tell":0.95, "lock":0.42, "recovery":1.15})
		"sweep_land":
			base.merge({"kind":"charge", "shape":"line", "path_mode":"leap", "arc_height":0.0, "range":620.0, "travel_distance":620.0, "width":144.0, "radius":72.0, "speed":600.0, "damage_along_path":true, "landing_shape":"circle", "landing_only":false, "damage_multiplier":0.92, "tell":1.0, "lock":0.45, "recovery":3.3, "weakpoint_id":"landed_core", "weakpoint_delay":1.05, "weakpoint_duration":2.2})
		"resonance_ring":
			base.merge(_ring_command(origin, direction, false))
		"sound_blade":
			base.merge({"kind":"projectile", "shape":"line", "range":840.0, "count":1, "width":32.0, "speed":690.0, "projectile_radius":12.0, "damage_multiplier":0.84, "status":{"id":"shock", "duration":2.0}, "tell":0.82, "lock":0.36, "recovery":0.95})
		"replay_path":
			var replay_paths: Array = _replay_paths(victim.position, 2 if phase == 2 else 4)
			base.merge({"kind":"projectile", "shape":"line", "paths":replay_paths, "count":replay_paths.size(), "width":28.0, "speed":470.0, "projectile_radius":11.0, "damage_multiplier":0.62, "tracks_target":false, "tell":1.05, "lock":0.45, "recovery":1.25})
		"alternating_ring":
			_ring_toggle = not _ring_toggle
			base.merge(_ring_command(origin, direction, _ring_toggle))
		"heart_crack":
			base.merge({"kind":"ground_area", "shape":"ring", "target":origin, "radius":315.0, "inner_radius":145.0, "ring_gap_degrees":105.0, "damage_multiplier":0.88, "duration":0.0, "weakpoint_id":"cracked_heart", "weakpoint_duration":2.8, "tell":1.05, "lock":0.45, "recovery":2.8})
	return base

func _ring_command(origin: Vector2, direction: Vector2, outer: bool) -> Dictionary:
	var radius: float = 520.0 if outer else 310.0
	var inner: float = 350.0 if outer else 135.0
	return {"kind":"ground_area", "shape":"ring", "target":origin, "radius":radius, "inner_radius":inner, "ring_gap_degrees":82.0, "direction":direction, "duration":0.0, "damage_multiplier":0.88, "tell":0.95, "lock":0.42, "recovery":1.1}

func _retarget(actor: Node2D, victim: Node2D) -> void:
	if command.is_empty():
		return
	command.origin = actor.position
	var direction: Vector2 = actor.position.direction_to(victim.position)
	if direction.length_squared() > EPSILON:
		command.direction = -direction if current_action == "back_heat" else direction
	var shape: String = str(command.get("shape", ""))
	if shape == "ring":
		command.target = actor.position
	else:
		command.target = victim.position
	match current_action:
		"root_fork":
			command.paths = _fork_paths(actor.position, victim.position, int(command.get("count", 1)))
		"runway_pair":
			var lanes: Array[int] = []
			lanes.assign(command.get("lane_indices", []))
			command.paths = _runway_paths(actor.position, Vector2(command.direction), lanes)
		"spore_pod":
			command.targets = [victim.position]
	if shape == "line" and command.get("paths", []).is_empty():
		var reach: float = float(command.get("range", actor.position.distance_to(victim.position)))
		if str(command.get("kind", "")) == "charge":
			reach = minf(reach, actor.position.distance_to(victim.position))
		command.target = actor.position + Vector2(command.direction) * reach
		command.points = [actor.position, command.target]

func _freeze_geometry(actor: Node2D, source: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result.origin = actor.position
	var direction: Vector2 = result.get("direction", Vector2.RIGHT)
	if direction.length_squared() <= EPSILON:
		direction = Vector2.RIGHT
	result.direction = direction.normalized()
	var kind: String = str(result.get("kind", ""))
	var shape: String = str(result.get("shape", ""))
	if kind == "charge":
		var distance: float = minf(float(result.get("travel_distance", result.get("range", 0.0))), result.origin.distance_to(Vector2(result.target)))
		result.travel_distance = distance
		result.target = result.origin + result.direction * distance
	if shape == "line" and result.get("paths", []).is_empty():
		var reach: float = float(result.get("travel_distance", 0.0)) if kind == "charge" else float(result.get("range", result.origin.distance_to(Vector2(result.target))))
		result.target = result.origin + result.direction * reach
		result.points = [result.origin, result.target]
	if shape == "ring":
		var gap: float = deg_to_rad(clampf(float(result.get("ring_gap_degrees", 0.0)), 0.0, 180.0))
		result.ring_start = result.direction.angle() + gap * 0.5
		result.ring_end = float(result.ring_start) + TAU - gap
	result.erase("tracks_target")
	return result

func _fork_paths(origin: Vector2, target: Vector2, count: int) -> Array:
	var direction: Vector2 = origin.direction_to(target)
	if direction.length_squared() <= EPSILON:
		direction = Vector2.RIGHT
	var reach: float = minf(760.0, maxf(330.0, origin.distance_to(target) + 180.0))
	var spread_values: Array = [0.0] if count <= 1 else ([-0.22,0.22] if count == 2 else [-0.28,0.0,0.28])
	var paths: Array = []
	for spread: float in spread_values:
		var end_direction: Vector2 = direction.rotated(spread)
		var bend: Vector2 = origin + end_direction * reach * 0.48 + end_direction.orthogonal() * signf(spread) * 55.0
		paths.append([origin, bend, origin + end_direction * reach])
	return paths

func _select_runway_lanes(count: int) -> Array[int]:
	var offsets: Array[float] = [-165.0, -55.0, 55.0, 165.0]
	var selected: Array[int] = []
	for step: int in offsets.size():
		var lane: int = (_lane_cursor + step) % offsets.size()
		if lane == _disabled_lane:
			continue
		selected.append(lane)
		if selected.size() >= count:
			break
	_lane_cursor = (_lane_cursor + 1) % offsets.size()
	if _disabled_lane_uses > 0:
		_disabled_lane_uses -= 1
		if _disabled_lane_uses <= 0:
			_disabled_lane = -1
	return selected

func _runway_paths(origin: Vector2, direction: Vector2, selected: Array[int]) -> Array:
	var paths: Array = []
	var offsets: Array[float] = [-165.0, -55.0, 55.0, 165.0]
	for lane: int in selected:
		var start: Vector2 = origin + direction.orthogonal() * offsets[lane] - direction * 390.0
		paths.append([start, start + direction * 780.0])
	return paths

func _replay_paths(fallback: Vector2, authored_count: int) -> Array:
	var count: int = maxi(1, authored_count - _broken_bells.size())
	var history: Array[Vector2] = _trail_history.duplicate()
	if history.size() < 3:
		history = [fallback + Vector2(-160,0), fallback, fallback + Vector2(160,0)]
	var base: Array[Vector2] = [history[history.size()-3], history[history.size()-2], history.back()]
	var direction: Vector2 = base[0].direction_to(base[2])
	if direction.length_squared() <= EPSILON:
		direction = Vector2.RIGHT
	var paths: Array = []
	for index: int in count:
		var offset: float = (float(index) - float(count - 1) * 0.5) * 54.0
		var path: Array[Vector2] = []
		for point: Vector2 in base:
			path.append(point + direction.orthogonal() * offset)
		paths.append(path)
	return paths

func _next_lane(count: int) -> int:
	var lane: int = _lane_cursor % count
	for offset: int in count:
		var candidate: int = (lane + offset) % count
		if candidate != _disabled_lane:
			lane = candidate
			break
	_lane_cursor = (lane + 1) % count
	if _disabled_lane_uses > 0:
		_disabled_lane_uses -= 1
		if _disabled_lane_uses <= 0:
			_disabled_lane = -1
	return lane

func _next_available(count: int, unavailable: Array[int]) -> int:
	for offset: int in count:
		var candidate: int = (_lane_cursor + offset) % count
		if candidate not in unavailable:
			_lane_cursor = (candidate + 1) % count
			return candidate
	return 0

func _remove_last_live_path() -> void:
	var paths: Array = command.get("paths", [])
	if paths.size() <= 1:
		return
	paths.pop_back()
	command.paths = paths
	command.count = paths.size()

func _sample_victim(victim: Node2D, delta: float) -> void:
	if boss_id != "BO04":
		return
	_sample_time -= delta
	if _sample_time > 0.0:
		return
	_sample_time = 0.14
	_trail_history.append(victim.position)
	while _trail_history.size() > 8:
		_trail_history.pop_front()

func _update_weakpoint(actor: Node2D, delta: float) -> void:
	if actor.has_meta("enemy_charge_wall_stop"):
		actor.remove_meta("enemy_charge_wall_stop")
		_pending_weakpoint = ""
		_pending_weakpoint_time = 0.0
		_pending_weakpoint_duration = 0.0
	if not _pending_weakpoint.is_empty():
		_pending_weakpoint_time = maxf(0.0, _pending_weakpoint_time - delta)
		if _pending_weakpoint_time <= 0.0:
			var pending_id: String = _pending_weakpoint
			var pending_duration: float = _pending_weakpoint_duration
			_pending_weakpoint = ""
			_pending_weakpoint_duration = 0.0
			_open_weakpoint(actor, pending_id, pending_duration)
	if weakpoint_time <= 0.0:
		return
	weakpoint_time = maxf(0.0, weakpoint_time - delta)
	if weakpoint_time <= 0.0:
		_close_weakpoint(actor)

func _open_weakpoint(actor: Node2D, id: String, duration: float) -> void:
	_pending_weakpoint = ""
	_pending_weakpoint_time = 0.0
	_pending_weakpoint_duration = 0.0
	weakpoint = id
	weakpoint_time = duration
	if actor.has_method("boss_weakpoint_changed"):
		actor.call("boss_weakpoint_changed", true, id, duration)

func _close_weakpoint(actor: Node2D) -> void:
	_pending_weakpoint = ""
	_pending_weakpoint_time = 0.0
	_pending_weakpoint_duration = 0.0
	if weakpoint.is_empty() and weakpoint_time <= 0.0:
		return
	var previous: String = weakpoint
	weakpoint = ""
	weakpoint_time = 0.0
	if actor.has_method("boss_weakpoint_changed"):
		actor.call("boss_weakpoint_changed", false, previous, 0.0)

func _health_ratio(actor: Node2D) -> float:
	var health_value: Variant = actor.get("health")
	if health_value == null:
		return 1.0
	var maximum: float = maxf(EPSILON, float(health_value.get("maximum")))
	return clampf(float(health_value.get("current")) / maximum, 0.0, 1.0)

func _phase_for_ratio(ratio: float) -> int:
	var thresholds: Array = definition.get("phase_thresholds", [0.7, 0.35])
	if thresholds.size() >= 2 and ratio <= float(thresholds[1]):
		return 3
	if not thresholds.is_empty() and ratio <= float(thresholds[0]):
		return 2
	return 1

func _parse_counter(counter_id: String, payload: Dictionary) -> Dictionary:
	var kind: String = str(payload.get("counter_id", payload.get("kind", counter_id)))
	var lane: int = int(payload.get("lane", -1))
	var parts: PackedStringArray = counter_id.split(":")
	if parts.size() >= 3:
		kind = parts[1]
		if parts[2].is_valid_int():
			lane = int(parts[2])
	return {"kind":kind, "lane":lane}

func _set_actor_state(actor: Node2D, next_state: StringName) -> void:
	actor.set("state", next_state)
	actor.set("state_time", maxf(0.0, state_time))
	actor.set("velocity", Vector2.ZERO)

func _alive(actor: Node2D) -> bool:
	return is_instance_valid(actor) and (not actor.has_method("is_alive") or bool(actor.call("is_alive")))
