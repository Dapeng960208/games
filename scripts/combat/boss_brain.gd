class_name BossBrain
extends RefCounted
## Seeded three-phase boss tactics. Distance, cooldowns and finite summon
## availability select among each boss's abilities; recovery navigates its
## preferred range. Frozen command dictionaries are both warnings and hits.
## Arena objects call apply_arena_counter(); the host actor owns phase cleanup,
## finite reinforcement requests and the completion signal.

const EPSILON := 0.00001
const Abilities = preload("res://scripts/combat/boss_ability_catalog.gd")
const SEQUENCES := {
	"BO01": {1:["hammer_fan", "ladle_drag", "solar_cross"], 2:["hammer_fan", "slag_lane", "ladle_drag", "solar_cross"], 3:["hammer_fan", "ladle_drag", "back_heat", "solar_cross"]},
	"BO02": {1:["root_fork", "spore_pod", "brood_eggs", "root_link", "acid_scatter"], 2:["root_fork", "root_link", "spore_pod", "brood_eggs", "acid_scatter"], 3:["root_link", "spore_pod", "brood_eggs", "crown_open", "acid_scatter"]},
	"BO03": {1:["glide", "capacitor_burst", "grave_recall", "stitch_cage"], 2:["runway_pair", "capacitor_burst", "glide", "grave_recall", "stitch_cage"], 3:["runway_pair", "sweep_land", "capacitor_burst", "grave_recall", "stitch_cage"]},
	"BO04": {1:["resonance_ring", "sound_blade", "war_drum_rage", "crag_leap"], 2:["replay_path", "resonance_ring", "sound_blade", "war_drum_rage", "crag_leap"], 3:["alternating_ring", "replay_path", "heart_crack", "sound_blade", "war_drum_rage", "crag_leap"]},
}

# Internal action keys remain stable for saved telemetry and arena fixtures;
# this identity is the displayed/executable new theme, not a second boss set.
const THEMED_ACTIONS := {
	"BO01":{"hammer_fan":"gear_arm_sweep", "ladle_drag":"lightning_trace", "slag_lane":"solar_lightning_lane", "back_heat":"exposed_solar_core", "solar_cross":"solar_cross"},
	"BO02":{"root_fork":"acid_fork", "spore_pod":"acid_pool", "root_link":"wing_cone", "crown_open":"amber_carapace_open", "brood_eggs":"brood_eggs", "acid_scatter":"acid_scatter"},
	"BO03":{"glide":"stitch_pull", "capacitor_burst":"barrel_throw", "runway_pair":"stitch_lanes", "sweep_land":"mayor_body_slam", "grave_recall":"grave_recall", "stitch_cage":"stitch_cage"},
	"BO04":{"resonance_ring":"ground_slam", "sound_blade":"warchief_charge", "replay_path":"rock_fissures", "alternating_ring":"outer_ground_slam", "heart_crack":"exhausted_ground_slam", "war_drum_rage":"war_drum_rage", "crag_leap":"crag_leap"},
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
var rage_time: float = 0.0
var brood_batches: int = 0
var grave_recalls: int = 0
var grave_sealed: bool = false
var drums_broken: bool = false
var _last_actor: WeakRef
var movement_intent: StringName = &"idle"
var movement_target: Vector2 = Vector2.ZERO
var _orbit_sign: float = 1.0
var _actions_used: Dictionary = {}
var _action_ready_at: Dictionary = {}
var _last_action: String = ""
var _recovery_elapsed: float = 0.0

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
	rage_time = 0.0
	brood_batches = 0
	grave_recalls = 0
	grave_sealed = false
	drums_broken = false
	_last_actor = null
	_rng.seed = (seed_value if seed_value != 0 else boss_id.hash() ^ 0xB055)
	movement_intent = &"idle"
	movement_target = Vector2.ZERO
	_orbit_sign = -1.0 if _rng.randf() < 0.5 else 1.0
	_actions_used.clear()
	_action_ready_at.clear()
	_last_action = ""
	_recovery_elapsed = 0.0

func tick(actor: Node2D, delta: float, victim: Node2D) -> void:
	if stopped or delta <= 0.0 or not is_instance_valid(actor) or not _alive(victim):
		return
	elapsed += delta
	_last_actor = weakref(actor)
	rage_time = maxf(0.0, rage_time - delta)
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
		_recovery_elapsed += delta
		_set_actor_state(actor, &"recovery")
		if state_time > 0.0 and _recovery_elapsed >= 0.28:
			_move_tactically(actor, victim)
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

func outgoing_damage_multiplier() -> float:
	return 1.25 if rage_time > 0.0 and not drums_broken else 1.0

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
	# New arena hosts attach semantic names; legacy layout IDs keep their lane
	# semantics and one-use accounting intact.
	var theme: String = str(payload.get("thematic_counter", kind))
	var aliases: Dictionary = {"solar_conduit":"cooling_valve", "shieldbreak":"cooling_valve", "brood_egg":"root_knot", "eggs":"root_knot", "grave_seal":"fuse_box", "graves":"fuse_box", "war_drum":"edge_bell", "barricade":"edge_bell"}
	kind = str(aliases.get(kind, kind))
	if lane < 0 and aliases.has(theme):
		lane = 0
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
			_counter_weakpoint("solar_core", 2.8)
			return true
		"BO02":
			if kind != "root_knot" or lane < 0 or lane > 3 or lane in _broken_roots:
				return false
			_broken_roots.append(lane)
			if current_action == "root_fork" and state in [&"telegraph",&"locked"]:
				_remove_last_live_path()
			_counter_weakpoint("broken_brood", 2.6)
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
			grave_sealed = true
			if current_action == "grave_recall" and state in [&"telegraph", &"locked"]:
				command.clear()
				state = &"recovery"
				state_time = 1.0
				state_duration = state_time
			_counter_weakpoint("unstitched_mayor", 2.5)
			return true
		"BO04":
			if kind != "edge_bell" or lane < 0 or lane > 3 or lane in _broken_bells:
				return false
			_broken_bells.append(lane)
			if current_action == "replay_path" and state in [&"telegraph",&"locked"]:
				_remove_last_live_path()
			drums_broken = true
			rage_time = 0.0
			_cancel_drum_windup()
			_counter_weakpoint("broken_war_drum", 2.5)
			return true
	return false

func counter_snapshot() -> Dictionary:
	return {
		"disabled_lane": _disabled_lane,
		"disabled_lane_uses": _disabled_lane_uses,
		"broken_roots": _broken_roots.duplicate(),
		"used_fuses": _used_fuses.duplicate(),
		"broken_bells": _broken_bells.duplicate(),
		"brood_batches":brood_batches, "grave_recalls":grave_recalls,
		"grave_sealed":grave_sealed, "drums_broken":drums_broken,
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
		"thematic_action":str(THEMED_ACTIONS.get(boss_id, {}).get(current_action, current_action)),
		"rage_remaining":rage_time,
		"tactics":tactical_snapshot(),
	}

func tactical_snapshot() -> Dictionary:
	return {"intent":str(movement_intent), "target":movement_target, "last_action":_last_action, "actions_used":_actions_used.duplicate(true)}

func stop(actor: Node2D = null) -> void:
	stopped = true
	command.clear()
	rage_time = 0.0
	if is_instance_valid(actor):
		_close_weakpoint(actor)

func _enter_phase(actor: Node2D) -> void:
	command.clear()
	action_index = 0
	current_action = ""
	_recovery_elapsed = 0.0
	_close_weakpoint(actor)
	state = &"phase_shift"
	state_time = 0.9
	state_duration = state_time
	if actor.has_method("boss_phase_started"):
		actor.call("boss_phase_started", phase, _health_ratio(actor))

func _begin_action(actor: Node2D, victim: Node2D, forced_action: String = "") -> void:
	# The explicit action argument lets arena fixtures exercise one real ability;
	# ordinary gameplay selects by distance, availability and recent casts.
	var sequence: Array = available_actions()
	if sequence.is_empty():
		state = &"recovery"
		state_time = 1.0
		return
	if not forced_action.is_empty() and Abilities.tier(boss_id,forced_action) > int(definition.get("difficulty",0)):
		command.clear()
		state = &"recovery"
		state_time = .45
		_set_actor_state(actor,&"recovery")
		return
	current_action = forced_action if not forced_action.is_empty() else _select_action(actor, victim, sequence)
	if current_action.is_empty():
		command.clear()
		state = &"recovery"
		state_time = 0.45
		state_duration = state_time
		_recovery_elapsed = 0.28
		_set_actor_state(actor, &"recovery")
		_move_tactically(actor, victim)
		return
	action_index += 1
	command = _build_action(actor, victim, current_action)
	if command.is_empty():
		state = &"recovery"
		state_time = 0.35
		state_duration = state_time
		_recovery_elapsed = 0.0
		return
	if bool(command.get("tracks_target", true)):
		_retarget(actor, victim)
	state = &"telegraph"
	state_time = maxf(0.55, float(command.get("tell", 0.8)))
	state_duration = state_time
	_set_actor_state(actor, &"telegraph")

func _select_action(actor: Node2D, victim: Node2D, sequence: Array) -> String:
	if not _can_navigate(actor):
		# Lightweight catalog/geometry hosts intentionally have no room movement.
		return str(sequence[action_index % sequence.size()])
	var distance: float = actor.position.distance_to(victim.position)
	var victim_radius: float = _victim_radius(actor, victim)
	var best_action: String = ""
	var best_score: float = -INF
	for action_value: String in sequence:
		if not _action_available(actor, action_value) or float(_action_ready_at.get(action_value, 0.0)) > elapsed:
			continue
		var preview: Dictionary = _preview_action(actor, victim, action_value)
		if preview.is_empty():
			continue
		var interval: Vector2 = _action_distance(action_value)
		var kind: String = str(preview.get("kind", ""))
		var shape: String = str(preview.get("shape", ""))
		if shape == "ring":
			# Match the executable annulus, including the next alternating ring.
			# A stationary player in its permanent inner safe zone is not a
			# useful attack target; ordinary navigation can first make room.
			interval = Vector2(float(preview.get("inner_radius", 0.0)), float(preview.get("radius", 0.0)))
			var ring_distance: float = victim.position.distance_to(Vector2(preview.get("target", actor.position)))
			if ring_distance < maxf(0.0, interval.x - victim_radius) or ring_distance > interval.y + victim_radius:
				continue
		elif kind == "charge":
			# Closing strikes are useful at short distance too. Their swept
			# body or landing blast extends beyond the travel endpoint.
			interval = Vector2(0.0, clampf(float(preview.get("travel_distance", preview.get("range", interval.y))), 0.0, 600.0) + float(preview.get("radius", 0.0)))
		elif kind in ["melee", "pull"]:
			interval = Vector2(0.0, float(preview.get("range", interval.y)))
		if kind not in ["summon", "haste"] and distance > interval.y + victim_radius:
			continue
		var range_gap: float = maxf(0.0, maxf(interval.x - distance, distance - interval.y))
		var usage: int = int(_actions_used.get(action_value, 0))
		var score: float = 2.3 / (1.0 + float(usage)) - range_gap / 95.0
		if action_value == _last_action: score -= 3.5
		if action_value == "grave_recall": score += 0.7
		if action_value == "war_drum_rage" and rage_time > 0.0: score -= 4.0
		score += _rng.randf_range(-0.12, 0.12)
		if score > best_score:
			best_score = score
			best_action = action_value
	if not best_action.is_empty(): return best_action
	# When every usable ability is cooling down, keep repositioning until an
	# actual cooldown finishes instead of silently releasing an early attack.
	return ""

func _preview_action(actor: Node2D, victim: Node2D, action: String) -> Dictionary:
	# Reuse the same initial tracking pass as a real cast. Raw legacy builds
	# still have victim-centered base fields until _retarget fixes them.
	var lane_cursor_before: int = _lane_cursor
	var disabled_lane_before: int = _disabled_lane
	var disabled_uses_before: int = _disabled_lane_uses
	var ring_toggle_before: bool = _ring_toggle
	var command_before: Dictionary = command
	var action_before: String = current_action
	current_action = action
	command = _build_action(actor, victim, action)
	if not command.is_empty() and bool(command.get("tracks_target", true)):
		_retarget(actor, victim)
	var result: Dictionary = command
	command = command_before
	current_action = action_before
	# Inspection must not spend lane/counter uses or toggle the next ring.
	_lane_cursor = lane_cursor_before
	_disabled_lane = disabled_lane_before
	_disabled_lane_uses = disabled_uses_before
	_ring_toggle = ring_toggle_before
	return result

func _victim_radius(actor: Node2D, victim: Node2D) -> float:
	var host: Node = _property(actor, "room", null) as Node
	var fallback: float = Balance.PLAYER_RADIUS if _property(host, "player", null) == victim else 12.0
	return maxf(0.0, float(_property(victim, "collision_radius", _property(victim, "navigation_radius", fallback))))

func _action_available(actor: Node2D, action: String) -> bool:
	if Abilities.tier(boss_id,action) > int(definition.get("difficulty",0)): return false
	if action == "brood_eggs":
		return brood_batches < int(definition.get("brood_batch_limit", 3)) and _owned_add_count(actor) < 2
	if action == "grave_recall":
		return not grave_sealed and grave_recalls < int(definition.get("grave_recall_limit", 2)) and _owned_add_count(actor) < 2 and (not actor.has_method("can_recall_grave") or bool(actor.can_recall_grave()))
	if action == "war_drum_rage": return not drums_broken
	return true

func _action_distance(action: String) -> Vector2:
	match action:
		"axe_fan": return Vector2(0,285)
		"wing_storm": return Vector2(0,440)
		"gear_dash", "royal_dive": return Vector2(180,480)
		"eclipse_ring": return Vector2(155,410)
		"seismic_crown": return Vector2(250,550)
		"prism_fan", "funeral_hook": return Vector2(0,700)
		"needle_fan": return Vector2(0,650)
		"fault_lines": return Vector2(0,720)
		"boulder_volley": return Vector2(0,760)
		"hammer_fan": return Vector2(0.0, 255.0)
		"root_link": return Vector2(0.0, 350.0)
		"back_heat": return Vector2(105.0, 285.0)
		"crown_open": return Vector2(110.0, 260.0)
		"resonance_ring": return Vector2(135.0, 310.0)
		"alternating_ring": return Vector2(135.0, 520.0)
		"heart_crack": return Vector2(145.0, 315.0)
		"crag_leap": return Vector2(200.0, 500.0)
		"sound_blade", "sweep_land": return Vector2(180.0, 600.0)
		"glide": return Vector2(100.0, 500.0)
		"capacitor_burst": return Vector2(100.0, 800.0)
		"runway_pair": return Vector2(100.0, 420.0)
	return Vector2(150.0, float(definition.get("attack_range", 760.0)))

func _move_tactically(actor: Node2D, victim: Node2D) -> void:
	# Active motion belongs to EnemySkillRuntime. Ordinary navigation must not
	# displace its frozen start or steal a player's earned weakpoint opening.
	if not _can_navigate(actor) or weakpoint_open() or not _pending_weakpoint.is_empty() or bool(actor.get_meta("enemy_skill_motion", false)):
		return
	var host: Node2D = _property(actor, "room", null) as Node2D
	var tactics: Dictionary = definition.get("tactics", {})
	var minimum: float = float(tactics.get("min_range", 220.0))
	var maximum: float = float(tactics.get("max_range", 350.0))
	var retreat: float = float(tactics.get("retreat_range", 140.0))
	var distance: float = actor.position.distance_to(victim.position)
	var direction: Vector2 = actor.position.direction_to(victim.position)
	if direction.length_squared() <= EPSILON: direction = Vector2.RIGHT
	var lateral: Vector2 = direction.orthogonal() * _orbit_sign
	var orbit: float = float(tactics.get("orbit_weight", 0.5))
	var desired: Vector2
	var speed_multiplier: float = 1.0
	if distance > maximum or not bool(host.call("has_line_of_sight", actor.position, victim.position)):
		movement_intent = &"chase"
		desired = direction + lateral * orbit * 0.28
		speed_multiplier = float(tactics.get("chase_multiplier", 1.1))
	elif distance < retreat:
		movement_intent = &"retreat"
		desired = -direction + lateral * orbit * 0.45
	elif distance < minimum:
		movement_intent = &"space"
		desired = -direction * 0.5 + lateral * orbit
	else:
		movement_intent = &"orbit"
		desired = lateral + direction * clampf((distance - (minimum + maximum) * 0.5) / 180.0, -0.3, 0.3)
	desired = desired.normalized()
	var radius: float = float(_property(actor, "navigation_radius", 54.0))
	movement_target = host.call("move_actor", actor.position, desired * 160.0, radius)
	if actor.position.distance_to(movement_target) < 18.0:
		_orbit_sign = -_orbit_sign
		desired = direction.orthogonal() * _orbit_sign
		movement_target = host.call("move_actor", actor.position, desired * 160.0, radius)
	var navigation: Vector2 = host.call("navigation_direction", actor.position, movement_target, radius)
	actor.set("velocity", navigation.limit_length(1.0) * float(_property(actor, "move_speed", 70.0)) * speed_multiplier)
	if navigation.length_squared() > EPSILON:
		# The brain keeps its recovery clock, while the shared body visual uses
		# the existing locomotion phase instead of sliding a stationary pose.
		actor.set("state", &"reposition")
	if _has_property(actor, "aim_direction"): actor.set("aim_direction", direction)

func _can_navigate(actor: Node2D) -> bool:
	var host: Node = _property(actor, "room", null) as Node
	return is_instance_valid(host) and host.has_method("navigation_direction") and host.has_method("move_actor") and host.has_method("has_line_of_sight") and _has_property(actor, "move_speed")

func _owned_add_count(actor: Node2D) -> int:
	var host: Node = _property(actor, "room", null) as Node
	var container: Node = _property(host, "enemies", null) as Node
	if not is_instance_valid(container): return 0
	var count: int = 0
	for child: Node in container.get_children():
		if child == actor or not child is Node2D or not _alive(child): continue
		var owner: Variant = _property(child, "owner_enemy", null)
		if owner is WeakRef and owner.get_ref() == actor: count += 1
	return count

func _has_property(object: Object, property_name: String) -> bool:
	if not is_instance_valid(object): return false
	for descriptor: Dictionary in object.get_property_list():
		if str(descriptor.name) == property_name: return true
	return false

func _property(object: Object, property_name: String, fallback: Variant) -> Variant:
	return object.get(property_name) if _has_property(object, property_name) else fallback

func _execute(actor: Node2D) -> void:
	var released: Dictionary = command.duplicate(true)
	_last_action = current_action
	_actions_used[current_action] = int(_actions_used.get(current_action, 0)) + 1
	_action_ready_at[current_action] = elapsed + float(released.get("cooldown", 5.0))
	if current_action == "brood_eggs":
		brood_batches += 1
	if current_action == "grave_recall":
		grave_recalls += 1
	if current_action == "war_drum_rage" and not drums_broken:
		rage_time = 5.0
	released["damage_multiplier"] = float(released.get("damage_multiplier", 1.0)) * outgoing_damage_multiplier()
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
	_recovery_elapsed = 0.0
	command.clear()
	_set_actor_state(actor, &"recovery")

func _build_action(actor: Node2D, victim: Node2D, action: String) -> Dictionary:
	if Abilities.tier(boss_id,action) > 0:
		if Abilities.tier(boss_id,action) > int(definition.get("difficulty",0)): return {}
		return Abilities.build(boss_id,action,actor.position,victim.position)
	var origin: Vector2 = actor.position
	var target: Vector2 = victim.position
	var direction: Vector2 = origin.direction_to(target)
	if direction.length_squared() <= EPSILON:
		direction = Vector2.RIGHT
	var base := {"action_id":action, "thematic_action":str(THEMED_ACTIONS.get(boss_id, {}).get(action, action)), "behavior_id":"boss_"+boss_id.to_lower(), "boss_id":boss_id,"fx_color":Abilities.COLORS[boss_id],"origin":origin, "target":target, "direction":direction, "tracks_target":true}
	match action:
		"hammer_fan":
			base.merge({"kind":"melee", "shape":"cone", "range":255.0, "angle":1.85, "damage_multiplier":1.15, "tell":0.78, "lock":0.34, "recovery":1.0})
		"ladle_drag":
			base.merge({"kind":"ground_area", "shape":"line", "range":680.0, "width":58.0, "duration":1.0, "tick_interval":0.65, "max_active_hazards":2, "damage_multiplier":0.75, "damage_type":"magic", "status":{"id":"shock", "duration":2.4}, "tell":0.95, "lock":0.4, "recovery":1.15})
		"solar_cross":
			base.merge({"kind":"ground_area", "shape":"line", "paths":_solar_cross_paths(origin, target, actor), "count":2, "width":54.0, "duration":1.45, "tick_interval":0.65, "max_active_hazards":2, "damage_multiplier":0.5, "damage_type":"magic", "status":{"id":"shock", "duration":2.0}, "tell":1.1, "lock":0.5, "recovery":1.7, "cooldown":7.0})
		"slag_lane":
			var lane: int = _next_lane(3)
			var lane_direction: Vector2 = Vector2.RIGHT.rotated(lane * TAU / 3.0)
			base.merge({"kind":"ground_area", "shape":"line", "range":740.0, "width":82.0, "duration":1.1, "tick_interval":0.7, "max_active_hazards":2, "damage_multiplier":0.7, "damage_type":"magic", "status":{"id":"shock", "duration":2.6}, "direction":lane_direction, "target":origin+lane_direction*740.0, "lane_index":lane, "tracks_target":false, "tell":1.0, "lock":0.4, "recovery":1.1})
		"back_heat":
			var safe: Vector2 = -direction
			base.merge({"kind":"ground_area", "shape":"ring", "target":origin, "radius":285.0, "inner_radius":105.0, "ring_gap_degrees":92.0, "direction":safe, "duration":0.0, "damage_multiplier":1.0, "weakpoint_id":"furnace_back", "weakpoint_duration":2.1, "tracks_target":true, "tell":1.0, "lock":0.42, "recovery":2.1})
		"root_fork":
			var fork_count: int = maxi(1, 3 - mini(2, _broken_roots.size()))
			var paths: Array = _fork_paths(origin, target, fork_count)
			base.merge({"kind":"projectile", "shape":"line", "paths":paths, "count":paths.size(), "width":24.0, "speed":390.0, "projectile_radius":10.0, "damage_multiplier":0.62, "status":{"id":"corrosion", "duration":2.8}, "tracks_target":true, "tell":0.9, "lock":0.38, "recovery":1.0})
		"spore_pod":
			base.merge({"kind":"ground_area", "shape":"circle", "targets":[target], "radius":105.0, "duration":3.3, "tick_interval":0.65, "max_active_hazards":2, "lob":true, "damage_multiplier":0.42, "status":{"id":"corrosion", "duration":3.0}, "tell":0.88, "lock":0.4, "recovery":1.15})
		"acid_scatter":
			base.merge({"kind":"ground_area", "shape":"circle", "targets":_acid_targets(origin, target), "radius":82.0, "duration":2.5, "tick_interval":0.7, "max_active_hazards":2, "lob":true, "damage_multiplier":0.58, "status":{"id":"corrosion", "duration":2.6}, "tell":1.1, "lock":0.5, "recovery":1.6, "cooldown":6.0})
		"root_link":
			base.merge({"kind":"melee", "shape":"cone", "range":350.0, "angle":1.6, "damage_multiplier":0.9, "status":{"id":"slow", "duration":0.9, "magnitude":0.78}, "tell":1.0, "lock":0.4, "recovery":1.25})
		"brood_eggs":
			if brood_batches >= int(definition.get("brood_batch_limit", 3)):
				return {}
			base.merge({"kind":"summon", "shape":"circle", "target":origin+direction*180.0, "targets":[origin+direction*170.0+direction.orthogonal()*72.0, origin+direction*170.0-direction.orthogonal()*72.0], "radius":46.0, "count":2, "max_alive":2, "summon_enemy_id":"M14", "hatch_delay":2.2, "pod_health":40.0, "pod_break_armor_loss":2.0, "damage_multiplier":0.0, "tracks_target":false, "tell":1.0, "lock":0.35, "recovery":2.6})
		"crown_open":
			base.merge({"kind":"ground_area", "shape":"ring", "target":origin, "radius":260.0, "inner_radius":110.0, "ring_gap_degrees":78.0, "damage_multiplier":0.9, "duration":0.0, "weakpoint_id":"open_crown", "weakpoint_duration":2.35, "tell":0.95, "lock":0.42, "recovery":2.35})
		"glide":
			base.merge({"kind":"pull", "shape":"line", "range":500.0, "width":62.0, "pull_distance":85.0, "damage_multiplier":0.6, "tell":1.0, "lock":0.42, "recovery":1.2})
		"capacitor_burst":
			base.merge({"kind":"projectile", "shape":"line", "range":800.0, "count":1, "width":38.0, "speed":420.0, "projectile_radius":19.0, "damage_multiplier":0.95, "tell":1.0, "lock":0.4, "recovery":1.2})
		"stitch_cage":
			base.merge({"kind":"projectile", "shape":"line", "paths":_stitch_cage_paths(origin, target), "count":3, "width":20.0, "speed":350.0, "projectile_radius":8.0, "damage_multiplier":0.45, "status":{"id":"slow", "duration":1.0, "magnitude":0.78}, "tell":1.15, "lock":0.5, "recovery":1.5, "cooldown":6.5})
		"grave_recall":
			if grave_sealed or grave_recalls >= int(definition.get("grave_recall_limit", 2)):
				return {}
			if actor.has_method("can_recall_grave") and not bool(actor.can_recall_grave()):
				return {}
			var grave_at: Vector2 = actor.grave_recall_target() if actor.has_method("grave_recall_target") else origin+direction.orthogonal()*180.0
			base.merge({"kind":"summon", "shape":"circle", "target":grave_at, "radius":65.0, "count":1, "summon_enemy_id":"M27", "damage_multiplier":0.0, "tracks_target":false, "tell":1.25, "lock":0.4, "recovery":1.35})
		"runway_pair":
			var runway_lanes: Array[int] = _select_runway_lanes(2)
			var runway_paths: Array = _runway_paths(origin, direction, runway_lanes)
			base.merge({"kind":"projectile", "shape":"line", "paths":runway_paths, "lane_indices":runway_lanes, "count":runway_paths.size(), "width":30.0, "speed":420.0, "projectile_radius":12.0, "damage_multiplier":0.66, "status":{"id":"slow", "duration":1.0, "magnitude":0.82}, "tracks_target":true, "tell":1.05, "lock":0.42, "recovery":1.25})
		"sweep_land":
			base.merge({"kind":"charge", "shape":"line", "path_mode":"leap", "arc_height":0.0, "range":620.0, "travel_distance":620.0, "width":144.0, "radius":72.0, "speed":600.0, "damage_along_path":true, "landing_shape":"circle", "landing_only":false, "damage_multiplier":0.92, "tell":1.0, "lock":0.45, "recovery":3.3, "weakpoint_id":"landed_core", "weakpoint_delay":1.05, "weakpoint_duration":2.2})
		"resonance_ring":
			base.merge(_ring_command(origin, direction, false))
		"sound_blade":
			base.merge({"kind":"charge", "shape":"line", "range":600.0, "travel_distance":600.0, "charge_past_target":true, "width":124.0, "radius":62.0, "speed":430.0, "damage_multiplier":1.05, "tell":1.1, "lock":0.45, "recovery":1.6})
		"crag_leap":
			base.merge({"kind":"charge", "shape":"line", "path_mode":"leap", "arc_height":0.0, "range":500.0, "travel_distance":500.0, "width":34.0, "radius":110.0, "speed":520.0, "landing_only":true, "landing_shape":"circle", "damage_along_path":false, "damage_multiplier":1.22, "weakpoint_id":"landed_warchief", "weakpoint_delay":0.97, "weakpoint_duration":1.45, "tell":1.15, "lock":0.55, "recovery":2.6, "cooldown":7.0})
		"war_drum_rage":
			if drums_broken:
				return {}
			base.merge({"kind":"haste", "shape":"circle", "target":origin, "radius":280.0, "max_targets":3, "duration":5.0, "multiplier":1.18, "damage_multiplier":0.0, "tracks_target":false, "tell":1.2, "lock":0.4, "recovery":1.2})
		"replay_path":
			var replay_paths: Array = _replay_paths(victim.position, 2 if phase == 2 else 4, actor)
			base.merge({"kind":"projectile", "shape":"line", "paths":replay_paths, "count":replay_paths.size(), "width":28.0, "speed":470.0, "projectile_radius":11.0, "damage_multiplier":0.62, "tracks_target":true, "tell":1.05, "lock":0.45, "recovery":1.25})
		"alternating_ring":
			_ring_toggle = not _ring_toggle
			base.merge(_ring_command(origin, direction, _ring_toggle))
		"heart_crack":
			base.merge({"kind":"ground_area", "shape":"ring", "target":origin, "radius":315.0, "inner_radius":145.0, "ring_gap_degrees":105.0, "damage_multiplier":0.88, "duration":0.0, "weakpoint_id":"cracked_heart", "weakpoint_duration":2.8, "tell":1.05, "lock":0.45, "recovery":2.8})
		_:
			return {}
	return base

func _ring_command(origin: Vector2, direction: Vector2, outer: bool) -> Dictionary:
	var radius: float = 520.0 if outer else 310.0
	var inner: float = 350.0 if outer else 135.0
	return {"kind":"ground_area", "shape":"ring", "target":origin, "radius":radius, "inner_radius":inner, "ring_gap_degrees":82.0, "direction":direction, "duration":0.0, "damage_multiplier":0.88, "tell":0.95, "lock":0.42, "recovery":1.1}

func _retarget(actor: Node2D, victim: Node2D) -> void:
	if command.is_empty():
		return
	if Abilities.tier(boss_id,current_action) > 0:
		command = Abilities.build(boss_id,current_action,actor.position,victim.position)
		return
	command.origin = actor.position
	var direction: Vector2 = actor.position.direction_to(victim.position)
	if direction.length_squared() > EPSILON:
		if current_action == "back_heat":
			command.direction = -direction
		elif str(command.get("shape", "")) == "ring":
			# Aim the dangerous arc at the target. A side gap stays visibly safe,
			# while standing still in front no longer avoids every ring attack.
			command.direction = direction.rotated(PI * 0.5 * _orbit_sign)
		else:
			command.direction = direction
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
		"solar_cross":
			command.paths = _solar_cross_paths(actor.position, victim.position, actor)
		"acid_scatter":
			command.targets = _acid_targets(actor.position, victim.position)
		"stitch_cage":
			command.paths = _stitch_cage_paths(actor.position, victim.position)
		"replay_path":
			command.paths = _replay_paths(victim.position, 2 if phase == 2 else 4, actor)
			command.count = command.paths.size()
	if shape == "line" and command.get("paths", []).is_empty():
		var reach: float = float(command.get("range", actor.position.distance_to(victim.position)))
		if str(command.get("kind", "")) == "charge" and not bool(command.get("charge_past_target", false)):
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
		var distance: float = float(result.get("travel_distance", result.get("range", 0.0)))
		if not bool(result.get("charge_past_target", false)):
			distance = minf(distance, result.origin.distance_to(Vector2(result.target)))
		result.travel_distance = distance
		result.target = result.origin + result.direction * distance
		if str(result.get("action_id", "")) == "crag_leap":
			result.weakpoint_delay = maxf(0.1, distance / float(result.get("speed", 520.0)))
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

func available_actions(for_phase: int = -1) -> Array:
	var actions: Array = SEQUENCES.get(boss_id,{}).get(phase if for_phase < 0 else for_phase,[]).duplicate()
	actions.append_array(Abilities.unlocked(boss_id,int(definition.get("difficulty",0))))
	return actions

func skill_pool() -> Array:
	var actions: Array = []
	for phase_id: int in [1,2,3]:
		for action: String in available_actions(phase_id):
			if not actions.has(action): actions.append(action)
	return actions

func _solar_cross_paths(origin: Vector2, target: Vector2, actor: Node2D = null) -> Array:
	var direction: Vector2 = origin.direction_to(target)
	if direction.length_squared() <= EPSILON: direction = Vector2.RIGHT
	return [[_bounded_endpoint(actor, target, -direction, 360.0), _bounded_endpoint(actor, target, direction, 360.0)], [_bounded_endpoint(actor, target, -direction.orthogonal(), 245.0), _bounded_endpoint(actor, target, direction.orthogonal(), 245.0)]]

func _bounded_endpoint(actor: Node2D, center: Vector2, direction: Vector2, reach: float) -> Vector2:
	var host: Node = _property(actor, "room", null) as Node
	var layout: Dictionary = _property(host, "layout", {})
	var arena_value: Variant = layout.get("arena", null)
	if arena_value is Rect2:
		var arena: Rect2 = arena_value.grow(-2.0)
		for axis: int in 2:
			if direction[axis] > EPSILON: reach = minf(reach, (arena.end[axis] - center[axis]) / direction[axis])
			elif direction[axis] < -EPSILON: reach = minf(reach, (arena.position[axis] - center[axis]) / direction[axis])
	return center + direction * maxf(0.0, reach)

func _acid_targets(origin: Vector2, target: Vector2) -> Array:
	var direction: Vector2 = origin.direction_to(target)
	if direction.length_squared() <= EPSILON: direction = Vector2.RIGHT
	return [target, target + direction.orthogonal() * 150.0, target - direction.orthogonal() * 150.0]

func _stitch_cage_paths(origin: Vector2, target: Vector2) -> Array:
	var direction: Vector2 = origin.direction_to(target)
	if direction.length_squared() <= EPSILON: direction = Vector2.RIGHT
	var midpoint: Vector2 = origin.lerp(target, 0.5)
	var paths: Array = []
	for bend: float in [-155.0, 0.0, 155.0]:
		# Runtime executes one bend per projectile. End each warned thread at
		# that convergence point instead of drawing an unexecuted fourth leg.
		paths.append([origin, midpoint + direction.orthogonal() * bend, target])
	return paths

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

func _replay_paths(fallback: Vector2, authored_count: int, actor: Node2D = null) -> Array:
	var count: int = maxi(1, authored_count - _broken_bells.size())
	var history: Array[Vector2] = _trail_history.duplicate()
	if history.size() < 3:
		history = [fallback, fallback, fallback]
	var base: Array[Vector2] = [history[history.size()-3], history[history.size()-2], history.back()]
	var direction: Vector2 = base[0].direction_to(base[2])
	var travelled: float = base[0].distance_to(base[1]) + base[1].distance_to(base[2])
	if travelled < 32.0:
		# Repeated stationary samples still warn a finite fissure. Its first
		# path passes through the warned point instead of producing two empty
		# zero-length shots on either side of a motionless player.
		direction = actor.position.direction_to(fallback) if is_instance_valid(actor) else Vector2.RIGHT
		if direction.length_squared() <= EPSILON: direction = Vector2.RIGHT
		base = [_bounded_endpoint(actor, fallback, -direction, 160.0), fallback, _bounded_endpoint(actor, fallback, direction, 160.0)]
	if direction.length_squared() <= EPSILON:
		direction = Vector2.RIGHT
	var paths: Array = []
	for index: int in count:
		# Keep the center path first: removing the last path for a broken drum
		# reduces coverage while preserving one real, readable threat.
		var offset: float = 0.0 if index == 0 else ceilf(float(index) * 0.5) * 54.0 * (1.0 if index % 2 == 1 else -1.0) * _orbit_sign
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
	if actor.has_meta("enemy_pod_broken"):
		actor.remove_meta("enemy_pod_broken")
		if boss_id == "BO02":
			_open_weakpoint(actor, "broken_brood", 2.6)
	if actor.has_meta("enemy_charge_wall_stop"):
		actor.remove_meta("enemy_charge_wall_stop")
		_pending_weakpoint = ""
		_pending_weakpoint_time = 0.0
		_pending_weakpoint_duration = 0.0
		if boss_id == "BO04":
			# Collision has already stopped the committed runtime motion. A real
			# wall impact buys a full stunned recovery, never another attack.
			command.clear()
			state = &"recovery"
			state_time = 1.8
			state_duration = state_time
			_open_weakpoint(actor, "wall_stunned_warchief", 1.8)
			_set_actor_state(actor, &"recovery")
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
	if is_instance_valid(actor) and actor.has_method("boss_weakpoint_changed"):
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
	if is_instance_valid(actor) and actor.has_method("boss_weakpoint_changed"):
		actor.call("boss_weakpoint_changed", false, previous, 0.0)

func _counter_weakpoint(id: String, duration: float) -> void:
	var actor: Node2D = _last_actor.get_ref() as Node2D if _last_actor != null else null
	_open_weakpoint(actor, id, duration)

func apply_biome_counter(kind: String, duration: float = 2.6) -> bool:
	if stopped or kind not in ["solar_conduit", "brood_egg", "grave_seal", "war_drum"]:
		return false
	var expected: String = {"BO01":"solar_conduit", "BO02":"brood_egg", "BO03":"grave_seal", "BO04":"war_drum"}.get(boss_id, "")
	if kind != expected:
		return false
	if kind == "grave_seal":
		grave_sealed = true
		if current_action == "grave_recall" and state in [&"telegraph", &"locked"]:
			command.clear()
			state = &"recovery"
			state_time = 1.0
			state_duration = state_time
	if kind == "war_drum":
		drums_broken = true
		rage_time = 0.0
		_cancel_drum_windup()
	_counter_weakpoint(kind, clampf(duration, 0.5, 6.0))
	return true

func _cancel_drum_windup() -> void:
	if current_action != "war_drum_rage" or state not in [&"telegraph", &"locked"]: return
	command.clear()
	state = &"recovery"
	state_time = 1.0
	state_duration = state_time

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
	movement_intent = &"idle"
	movement_target = actor.position

func _alive(actor: Node2D) -> bool:
	return is_instance_valid(actor) and (not actor.has_method("is_alive") or bool(actor.call("is_alive")))
