class_name CombatLoadout
extends RefCounted
## Bridges pure equipment rules to live actors. Damage emitted here is a derived
## equipment source; it never re-enters the original-attack equipment pipeline.

const Rules = preload("res://scripts/combat/equipment_effects.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const MODIFIER_KEYS: Array[String] = ["damage_bonus", "crit_bonus", "attack_speed_bonus", "move_speed_bonus", "damage_reduction_bonus", "knockback_scale", "received_knockback_scale", "slow_resistance", "chill_duration_bonus", "cost_reduction"]

var owner_player: Node2D
var effects: RefCounted
var _last_position := Vector2.ZERO
var _movement_time: float = 0.0
var _clock: float = 0.0
var _current_speed: float = 0.0
var _modifiers: Dictionary = {}
var _applying_depth: int = 0
var _event_serial: int = 0
var _self_status_sources: Dictionary = {}
var _self_status_sources_known: bool = true


func configure(player: Node2D) -> void:
	owner_player = player
	effects = Rules.new()
	_last_position = player.position
	_clock = 0.0
	_event_serial = 0
	_movement_time = 0.0
	_modifiers.clear()
	_self_status_sources.clear()
	_self_status_sources_known = true
	if Game.run == null:
		return
	# V2 stats retain instance IDs; the pure reducer reads the separately
	# resolved template map for fixed traits, without accessing owned records.
	var loadout: Dictionary = Game.run.stats.get("loadout", Game.run.loadout_snapshot).duplicate(true)
	effects.call("configure", loadout, Game.run.stats, str(Game.run.stats.get("resource_type", "")))
	_update_modifiers(effects.call("advance", 0.0, _context()))


## Safe replacement changes rule identities only. Snapshot.restore supplies
## migrated timers and source pools; this emits neither entry nor one-shots.
func rebind(loadout: Dictionary, resolved_stats: Dictionary) -> void:
	if effects == null:
		effects = Rules.new()
	effects.call("rebind", loadout, resolved_stats, str(resolved_stats.get("resource_type", "")))


func refresh_modifiers() -> void:
	if effects != null:
		_update_modifiers(effects.call("passive_modifiers", _context()))


## Status clocks advance independently of the equipment clock. Keep a write
## fingerprint rather than guessing ownership from remaining duration/power.
func self_status_sources(states: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in _self_status_sources:
		var origin: Dictionary = _self_status_sources[id]
		var state: Dictionary = states.get(id, {})
		if not state.is_empty() and float(state.get("remaining", 0.0)) > 0.0 and float(state.get("applied_at", -1.0)) == float(origin.applied_at) and float(state.get("power", -1.0)) == float(origin.power) and float(state.get("H", -1.0)) == float(origin.H):
			result[id] = origin.duplicate(true)
	return result


func tick(delta: float) -> void:
	if effects == null or Game.run == null or not is_instance_valid(owner_player) or delta <= 0.0:
		return
	if owner_player.get_tree().paused:
		return
	_clock += delta
	var travelled: float = owner_player.position.distance_to(_last_position)
	_last_position = owner_player.position
	_current_speed = travelled / delta
	var ordinary_move: bool = travelled > 0.01 and float(owner_player.get("dash_remaining")) <= 0.0
	var knockback: Vector2 = owner_player.get("knockback")
	ordinary_move = ordinary_move and knockback.length_squared() < 1.0
	var abilities: Variant = owner_player.get("abilities")
	if abilities != null and bool(abilities.call("busy")):
		ordinary_move = false
	_movement_time = _movement_time + delta if ordinary_move else 0.0
	var context: Dictionary = _context({"moving": ordinary_move})
	var result: Dictionary = effects.call("advance", delta, context)
	_update_modifiers(result)
	_apply_commands(result, context)


func event(name: String, extra: Dictionary = {}) -> Dictionary:
	if effects == null or Game.run == null or not is_instance_valid(owner_player):
		return {}
	var context: Dictionary = _context(extra)
	if not context.has("attack_id") and not context.has("event_id") and name not in ["before_hit", "after_hit", "status_applied", "kill"]:
		_event_serial += 1
		context["event_id"] = "loadout:%d:%d" % [owner_player.get_instance_id(), _event_serial]
	var result: Dictionary = effects.call("handle", name, context)
	# before_hit returns modifiers only; the caller owns the root damage transaction.
	if name != "before_hit":
		_update_modifiers(result)
		_apply_commands(result, context)
	return result


func modifiers() -> Dictionary:
	return _modifiers.duplicate()


func resource_cost(amount: float, slot: String = "") -> float:
	if not is_finite(amount) or amount < 0.0:
		return INF
	if effects == null or Game.run == null:
		return amount
	var cost: float = float(effects.call("skill_cost", amount, _context({"base_cost": amount, "slot": slot})))
	return maxf(0.0, cost) if is_finite(cost) else amount


func _update_modifiers(result: Dictionary) -> void:
	_modifiers.clear()
	for key: String in MODIFIER_KEYS:
		_modifiers[key] = float(result.get(key, 1.0 if key.ends_with("_scale") else 0.0))


func _apply_commands(result: Dictionary, context: Dictionary) -> void:
	if Game.run == null or _applying_depth >= 4:
		return
	_applying_depth += 1
	for command: Dictionary in result.get("self_statuses", []):
		var id: String = str(command.get("status", ""))
		var applied: bool = owner_player.status.apply(id, float(command.get("power", 0.0)), float(command.get("duration", 0.0)))
		var state: Dictionary = owner_player.status.states.get(id, {})
		# A stronger same-clock write can win the status reducer; do not claim it.
		if applied and not state.is_empty():
			_self_status_sources[id] = {"source":str(command.get("source", "")), "applied_at":float(state.applied_at), "power":float(state.power), "H":float(state.H)}
	var shields: Array = result.get("shields", [])
	if not shields.is_empty():
		for command: Dictionary in shields:
			_grant_shield(float(command.get("ratio", 0.0)), float(command.get("duration", 4.0)), str(command.get("source", "loadout")))
	elif float(result.get("shield_ratio", 0.0)) > 0.0:
		_grant_shield(float(result.shield_ratio), float(result.get("shield_duration", 4.0)), str(result.get("shield_source", "loadout")))
	if Game.run != null:
		var healing: float = float(result.get("heal_amount", maxf(0.0, float(result.get("heal_ratio", 0.0))) * Game.run.max_hp))
		if healing > 0.0 and Game.run.hp > 0.0:
			owner_player.heal(healing)
		Game.restore_resource(maxf(0.0, float(result.get("resource_restore", 0.0))))
	_apply_refunds(result.get("cooldown_refunds", []))
	_apply_extensions(result.get("status_extensions", []), context)
	var accepted: Dictionary = {}
	var accepted_effects: Array[String] = []
	for command: Dictionary in result.get("statuses", []):
		var target: Node2D = _target(command.get("target_id"), context.get("target"))
		var status_id: String = str(command.get("status", ""))
		if _apply_status(target, status_id, float(command.get("power", context.get("H", 0.0))), float(command.get("duration", 3.0))):
			var effect_id: String = str(command.get("effect_id", ""))
			if not effect_id.is_empty() and effect_id not in accepted_effects: accepted_effects.append(effect_id)
			var id: int = target.get_instance_id()
			if not accepted.has(id):
				accepted[id] = {"target": target, "states": []}
			if not accepted[id].states.has(status_id):
				accepted[id].states.append(status_id)
	# Rejected provisional status packets become available to later slot stages;
	# accepted bundles commit exactly one ICD before any status follow-ups.
	result.triggered.append_array(effects.settle_status_requests(context, result.get("statuses", []), accepted_effects))
	# Only confirmed status writes may activate "successfully applied" affixes.
	for id: int in accepted:
		var followup: Dictionary = context.duplicate()
		followup["target"] = accepted[id].target
		followup["target_id"] = id
		followup["applied_states"] = accepted[id].states
		var status_result: Dictionary = effects.call("handle", "status_applied", followup)
		_update_modifiers(status_result)
		_apply_commands(status_result, followup)
	for command: Dictionary in result.get("bonus_hits", []):
		_apply_bonus_hit(command, context)
	# Weapon and foot status requests pause the reducer's slot order. Resume even
	# when every request failed or the target is immune; only the confirmations
	# above are conditional on actual application. Reuse the original root and
	# pre-hit snapshot, so later slots share the same proc budget and cannot loop.
	if bool(result.get("resume_after_statuses", false)) and Game.run != null:
		var continuation: Dictionary = effects.call("handle", "statuses_resolved", context)
		_update_modifiers(continuation)
		_apply_commands(continuation, context)
	_applying_depth -= 1


func _grant_shield(ratio: float, duration: float, source: String) -> void:
	if Game.run == null or ratio <= 0.0 or duration <= 0.0:
		return
	var key: String = source if source.begins_with("equipment:") else "equipment:" + source
	var previous: float = Game.run.shield
	owner_player.call("grant_guard", Game.run.max_hp * clampf(ratio, 0.0, 0.35), duration, key)
	if Game.run != null and not is_equal_approx(previous, Game.run.shield):
		Game.changed.emit()


func _apply_refunds(commands: Array) -> void:
	if not is_instance_valid(owner_player):
		return
	var cooldowns: Dictionary = owner_player.get("cooldowns")
	for command: Dictionary in commands:
		var seconds: float = maxf(0.0, float(command.get("seconds", 0.0)))
		var slot: String = str(command.get("slot", ""))
		slot = str({"Q": "q", "right": "secondary", "F": "f", "R": "ultimate"}.get(slot, slot))
		if slot == "dash":
			owner_player.set("dash_cooldown", maxf(0.0, float(owner_player.get("dash_cooldown")) - seconds))
		elif cooldowns.has(slot):
			cooldowns[slot] = maxf(0.0, float(cooldowns[slot]) - seconds)


func _apply_status(target: Node2D, status_id: String, power: float, duration: float) -> bool:
	if not _alive(target) or status_id not in Rules.ENEMY_STATES or not target.has_method("apply_status"):
		return false
	return bool(target.call("apply_status", status_id, maxf(0.0, power), duration))


func _apply_extensions(commands: Array, context: Dictionary) -> void:
	for command: Dictionary in commands:
		var target: Node2D = _target(command.get("target_id"), context.get("target"))
		if not _alive(target):
			continue
		var state: Variant = target.get("status")
		if state == null:
			continue
		var status_id: String = str(command.get("status", ""))
		var states: Dictionary = state.get("states")
		if not states.has(status_id):
			continue
		var entry: Dictionary = states[status_id]
		var remaining: float = float(entry.get("remaining", 0.0))
		if remaining <= 0.0:
			continue
		var base: float = 4.0 if status_id == "corrosion" else 3.0
		var cap: float = float(command.get("max_duration", base * 1.4))
		entry["remaining"] = minf(maxf(remaining, cap), remaining + maxf(0.0, float(command.get("seconds", 0.0))))
		# No apply_status call: extension must retain tick cadence and the H snapshot.


func _apply_bonus_hit(command: Dictionary, context: Dictionary) -> void:
	if not is_instance_valid(owner_player) or Game.run == null:
		return
	var amount: float = maxf(0.0, float(command.get("damage", 0.0)))
	if amount <= 0.0:
		return
	var seen: Dictionary = {}
	for identifier: Variant in command.get("target_ids", []):
		var target: Node2D = _target(identifier)
		if not _alive(target) or seen.has(target.get_instance_id()):
			continue
		seen[target.get_instance_id()] = true
		# Deliberately bypass room.resolve_direct_hit and all primary-hit callbacks.
		var packet: Dictionary = {"damage_source":"equipment","damage_type":str(command.get("damage_type", "magic" if Game.run.hero_id == "CH03" else "physical")),"attacker_stats":Game.run.stats,"proc_depth":1,"equipment_eligible":false,"original_basic":false}
		var accepted_hit: bool = bool(target.call("take_damage", float(command.get("damage_by_target", {}).get(str(identifier), amount)), &"equipment", Vector2.ZERO, packet))
		if accepted_hit and _alive(target):
			for status_data: Variant in command.get("states", []):
				var status_id: String = str(status_data.get("status", "")) if status_data is Dictionary else str(status_data)
				var duration: float = float(status_data.get("duration", 3.0)) if status_data is Dictionary else 3.0
				_apply_status(target, status_id, float(command.get("power", context.get("H", 0.0))), duration)
		if seen.size() >= 3:
			break


func _context(extra: Dictionary = {}) -> Dictionary:
	var context: Dictionary = {}
	if Game.run == null or not is_instance_valid(owner_player):
		return context
	var stats: Dictionary = Game.run.stats
	var room: Node = owner_player.get("room")
	var velocity: Vector2 = owner_player.get("velocity")
	var hero: Dictionary = Registry.hero(Game.run.hero_id)
	var power: float = float(owner_player.call("attack_power"))
	var cooldowns: Dictionary = owner_player.get("cooldowns")
	context = {
		"hero_id": Game.run.hero_id,
		"level": Game.run.level,
		"hp": Game.run.hp,
		"max_hp": Game.run.max_hp,
		"hp_ratio": Game.run.hp / maxf(1.0, Game.run.max_hp),
		"resource": Game.run.resource,
		"resource_max": float(stats.get("resource_max", 100.0)),
		"resource_type": str(stats.get("resource_type", "")),
		"shield": Game.run.shield,
		"equipment_shield": _equipment_shield(),
		"power": power,
		"H": power,
		"X": power,
		"position": owner_player.position,
		"moving": velocity.length_squared() > 1.0 and _movement_time > 0.0,
		"moving_time": _movement_time,
		"current_speed": _current_speed,
		"base_speed": float(hero.get("move_speed", stats.get("move_speed", 220.0))),
		"now": _clock,
		"room_id": room.get_instance_id() if is_instance_valid(room) else 0,
		"stats": stats,
		"remaining_cooldowns": {"Q": float(cooldowns.get("q", 0.0)), "right": float(cooldowns.get("secondary", 0.0)), "F": float(cooldowns.get("f", 0.0)), "R": float(cooldowns.get("ultimate", 0.0)), "dash": float(owner_player.get("dash_cooldown"))},
		"self_chilled": _statuses(owner_player).has("chill"),
	}
	context.merge(extra, true)
	if not context.has("damage_source") and extra.has("kind"):
		context["damage_source"] = str(extra.kind)
	if not context.has("original_basic"):
		context["original_basic"] = str(context.get("damage_source", "")) == "primary"
	if not context.has("equipment_eligible"):
		context["equipment_eligible"] = bool(context.original_basic)
	if not context.has("proc_depth"):
		context["proc_depth"] = 0 if bool(context.equipment_eligible) else 1
	var target: Variant = extra.get("target")
	var origin: Vector2 = owner_player.position
	if target is Node2D and is_instance_valid(target):
		origin = target.position
		context["target_id"] = target.get_instance_id()
		context["target_position"] = target.position
		context["distance"] = owner_player.position.distance_to(target.position)
		context["target_alive"] = _alive(target)
		var health: Variant = target.get("health")
		if health != null:
			context["target_hp"] = float(health.get("current"))
			context["target_max_hp"] = float(health.get("maximum"))
			if not extra.has("target_full_hp"):
				context["target_full_hp"] = is_equal_approx(float(health.get("current")), float(health.get("maximum")))
		if not extra.has("target_states"):
			context["target_states"] = _statuses(target).keys()
	if context.get("target_states") is Dictionary:
		context["target_states"] = context.target_states.keys()
	var nearby: Array[Dictionary] = []
	for candidate: Node2D in _nearby(origin, target if target is Node2D else null, 0):
		nearby.append({"id": candidate.get_instance_id(), "distance": origin.distance_to(candidate.position), "alive": _alive(candidate), "states": _statuses(candidate)})
	context["nearby_targets"] = nearby
	context["nearby_burning"] = false
	for candidate: Node2D in _nearby(owner_player.position, null, 0):
		if _statuses(candidate).has("burn"):
			context["nearby_burning"] = true
			break
	return context


func _equipment_shield() -> float:
	if Game.run == null:
		return 0.0
	var status: Variant = owner_player.get("status")
	if status == null:
		return 0.0
	var guards: Dictionary = status.get("guards")
	var amount: float = 0.0
	for key: String in guards:
		if not key.begins_with("equipment:") and not key.begins_with("set_"):
			continue
		var guard: Dictionary = guards[key]
		if float(guard.get("remaining", 0.0)) > 0.0:
			amount = maxf(amount, float(guard.get("amount", 0.0)))
	return minf(amount, Game.run.shield)


func _statuses(target: Node) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(target):
		return result
	var status: Variant = target.get("status")
	if status == null:
		return result
	var states: Variant = status.get("states")
	if not states is Dictionary:
		return result
	for key: String in states:
		var entry: Variant = states[key]
		if entry is Dictionary and float(entry.get("remaining", 0.0)) > 0.0:
			result[key] = entry.duplicate(true)
	return result


func _alive(target: Variant) -> bool:
	return target is Node and is_instance_valid(target) and target.has_method("is_alive") and bool(target.call("is_alive"))


func _target(identifier: Variant, fallback: Variant = null) -> Node2D:
	if identifier is Node2D and is_instance_valid(identifier):
		return identifier
	if identifier is String and str(identifier).is_valid_int():
		identifier = int(identifier)
	if identifier is int and int(identifier) > 0:
		var candidate: Object = instance_from_id(int(identifier))
		if candidate is Node2D and is_instance_valid(candidate):
			return candidate
	return fallback if fallback is Node2D and is_instance_valid(fallback) else null


func _nearby(origin: Vector2, excluded: Node2D = null, maximum: int = 3) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if not is_instance_valid(owner_player):
		return result
	var room: Node = owner_player.get("room")
	if not is_instance_valid(room) or not room.has_method("targets_in_radius"):
		return result
	var candidates: Array = room.call("targets_in_radius", origin, 240.0)
	for candidate: Variant in candidates:
		if not candidate is Node2D or not _alive(candidate) or candidate == excluded:
			continue
		if room.has_method("has_line_of_sight") and not bool(room.call("has_line_of_sight", origin, candidate.position)):
			continue
		result.append(candidate)
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var first: float = a.position.distance_squared_to(origin)
		var second: float = b.position.distance_squared_to(origin)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(first, second) else first < second)
	if maximum > 0 and result.size() > maximum:
		result.resize(maximum)
	return result
