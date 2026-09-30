class_name SalvagerPlayer
extends CharacterBody2D

signal skill_input_feedback(slot: String, reason: String, details: Dictionary)

const SKILL_BUFFER_SECONDS: float = 0.24
const COMBO_MAX_AGE: float = 0.90
const COMBO_QUEUE_LIMIT: int = 3

const Abilities = preload("res://scripts/combat/hero_abilities.gd")
const Visual = preload("res://scripts/combat/hero_visual.gd")
const Status = preload("res://scripts/combat/combat_status.gd")
const Loadout = preload("res://scripts/combat/combat_loadout.gd")
var room: Node2D
var abilities: RefCounted
var status: CombatStatus = Status.new()
var loadout: RefCounted
var aim_direction := Vector2.RIGHT
var dash_remaining: float = 0.0
var dash_cooldown: float = 0.0
var dash_elapsed: float = 0.0
var dash_direction := Vector2.RIGHT
var shot_cooldown: float = 0.0
var invulnerable: float = 0.0
var hurt_flash: float = 0.0
var muzzle_flash: float = 0.0
var knockback := Vector2.ZERO
var stride: float = 0.0
var cooldowns: Dictionary = {"q":0.0,"secondary":0.0,"f":0.0,"ultimate":0.0}
var resource_delay: float = 0.0
var combat_time: float = 5.0
var rage_hurt_cooldown: float = 0.0
var passive_count: int = 0
var passive_cooldown: float = 0.0
var walk_distance: float = 0.0
var attack_remaining: float = 0.0
var attack_resolved: bool = false
var visual_state: String = "idle"
var visual_remaining: float = 0.0
var visual_duration: float = 0.0
var visual_hitstop: float = 0.0
var last_cast_error: String = ""
var attack_buffer: float = 0.0
## Compatibility view of the first pending skill for the HUD. The bounded FIFO
## owns only value snapshots; no actor, resource or UI reference can survive it.
var buffered_skill: Dictionary = {}
var combo_queue: Array[Dictionary] = []
var _basic_chain_remaining: float = 0.0
var _attack_release_required: bool = false
var _attack_direction := Vector2.RIGHT
var _attack_critical: bool = false
var _pending_skill_slot: String = ""
var _enemy_status_origins: Dictionary = {}
var _enemy_slow_remaining: float = 0.0
var _enemy_slow_multiplier: float = 1.0
## Room-local identity state; target references never enter a save or equipment state.
var break_stacks: int = 0
var class_marks: Dictionary = {}

func _ready() -> void:
	abilities = Abilities.new()
	abilities.configure(self)
	loadout = Loadout.new()
	loadout.configure(self)
	var service: bool = room.get("expedition_context") != null and str(room.expedition_context.get("role","")) in ["entrance","supply"]
	loadout.event("room_enter", {"room_id":room.layout_id,"combat_room":not service})

func hero_id() -> String:
	return Game.run.hero_id if Game.run != null else "CH01"

func hero_level() -> int:
	return Game.run.level if Game.run != null else 1

func stat(key: String, fallback: float) -> float:
	if Game.run == null:
		return fallback
	var value: float = float(Game.run.stats.get(key, fallback))
	var modifiers: Dictionary = loadout.modifiers() if loadout != null else {}
	if key == "move_speed":
		var existing: float = float(Game.run.stats.get("move_speed_bonus", 0.0))
		var prop_bonus: float = _room_prop_modifier(&"move_multiplier", 1.0) - 1.0
		value = value / (1.0 + existing) * (1.0 + minf(0.45, existing + float(modifiers.get("move_speed_bonus", 0.0)) + prop_bonus))
		var slow_multiplier: float = _enemy_slow_multiplier if _enemy_slow_remaining > 0.0 else 1.0
		if status.has("chill"):
			slow_multiplier = minf(slow_multiplier, 0.75)
		value *= 1.0 - (1.0 - slow_multiplier) * (1.0 - clampf(float(modifiers.get("slow_resistance", 0.0)), 0.0, 1.0))
		return value
	if key == "damage_bonus":
		var supply_bonus: float = float(Game.run.stats.get("temporary_buffs",{}).get("amplify",{}).get("damage_bonus",0.0))
		return minf(0.60, value + supply_bonus + _room_prop_modifier(&"damage_bonus", 0.0))
	if key == "resource_regen":
		return value * _room_prop_modifier(&"resource_regen_multiplier", 1.0)
	if key == "attack_interval":
		var existing: float = float(Game.run.stats.get("attack_speed_bonus", 0.0))
		return value * (1.0 + existing) / (1.0 + minf(0.6, existing + float(modifiers.get("attack_speed_bonus", 0.0))))
	return value

func _room_prop_modifier(method: StringName, fallback: float) -> float:
	if not is_instance_valid(room):
		return fallback
	var props: Variant = room.get("enemy_props")
	if not is_instance_valid(props) or not props.has_method(method):
		return fallback
	var value: float = float(props.call(method))
	return value if is_finite(value) and value >= 0.0 else fallback

func attack_power() -> float:
	return stat("attack", 27.0 if hero_id() == "CH01" else 24.0 if hero_id() == "CH02" else 18.0)

func skill_power() -> float:
	return attack_power() + (maxf(0.0, stat("ability_power", 0.0)) * 0.7 if hero_id() == "CH03" else 0.0)

func heal(amount: float) -> float:
	return Game.heal_player(amount, status.healing_multiplier())

func _physics_process(delta: float) -> void:
	if Game.run == null or Game.run.hp <= 0.0 or get_tree().paused:
		clear_buffered_skill()
		return
	_tick_class_state(delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	passive_cooldown = maxf(0.0, passive_cooldown - delta)
	rage_hurt_cooldown = maxf(0.0, rage_hurt_cooldown - delta)
	attack_buffer = maxf(0.0, attack_buffer - delta)
	_basic_chain_remaining = maxf(0.0, _basic_chain_remaining - delta)
	_enemy_slow_remaining = maxf(0.0, _enemy_slow_remaining - delta)
	if _enemy_slow_remaining <= 0.0:
		_enemy_slow_multiplier = 1.0
	for key: String in cooldowns:
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
	# Synchronize external shield damage before expiries recompute the maximum pool.
	status.absorb(maxf(0.0, status.shield() - Game.run.shield))
	var was_chilled: bool = status.has("chill")
	var status_damage: Array[Dictionary] = status.tick(delta)
	Game.run.shield = status.shield()
	for tick: Dictionary in status_damage:
		var source_origin: Vector2 = _enemy_status_origins.get(str(tick.kind), position)
		receive_damage(float(tick.damage), source_origin, {"dot":true,"status":str(tick.kind),"damage_type":str(tick.get("damage_type", "magic" if str(tick.kind) == "burn" else "physical"))})
		if Game.run == null or Game.run.hp <= 0.0:
			return
	for identifier: String in _enemy_status_origins.keys():
		if not status.has(identifier):
			_enemy_status_origins.erase(identifier)
	if was_chilled != status.has("chill") and loadout != null:
		loadout.event("state_changed", {"enemy_status":"chill"})
	var regen_step: float = maxf(0.0, delta - resource_delay)
	var rage_decay_step: float = maxf(0.0, delta - combat_time)
	resource_delay = maxf(0.0, resource_delay - delta)
	combat_time = maxf(0.0, combat_time - delta)
	if hero_id() == "CH01":
		if combat_time <= 0.0:
			Game.run.resource = maxf(0.0, Game.run.resource - 6.0 * rage_decay_step)
	elif regen_step > 0.0:
		Game.restore_resource(stat("resource_regen", 18.0 if hero_id() == "CH02" else 5.0) * regen_step)
	var motion := Vector2.ZERO
	var pointer_enabled: bool = room.pointer_controls_enabled()
	if not Input.is_action_pressed("attack"):
		_attack_release_required = false
	if not pointer_enabled:
		attack_buffer = 0.0
		_attack_release_required = Input.is_action_pressed("attack")
		_drop_pointer_combo_inputs()
	if not room.controls_enabled():
		clear_buffered_skill()
	if room.controls_enabled():
		motion = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var aim := get_global_mouse_position() - global_position
		if aim.length_squared() > 16.0:
			aim_direction = aim.normalized()
		if Input.is_action_just_pressed("dash"):
			start_dash(motion.normalized() if motion.length_squared() > 0.0 else aim_direction)
		for slot: String in cooldowns:
			if slot == "secondary" and not pointer_enabled:
				continue
			if InputMap.has_action("skill_" + slot) and Input.is_action_just_pressed("skill_" + slot):
				request_skill(slot, get_global_mouse_position())
		if pointer_enabled and not _attack_release_required and Input.is_action_just_pressed("attack"):
			request_attack(aim_direction)
		elif combo_queue.is_empty() and pointer_enabled and not _attack_release_required and Input.is_action_pressed("attack"):
			if not fire(aim_direction):
				attack_buffer = 0.10
	elif room.input_blocked or room.release_gate:
		attack_buffer = 0.0
	abilities.tick(delta)
	_tick_attack(delta)
	_consume_buffered_skill()
	# Let a release on this exact physics boundary consume its follow-up
	# before evaluating expiry; the full advertised input window stays usable.
	_tick_skill_buffer(delta)
	if Game.run == null:
		return
	var from := position
	var displaced: bool = dash_remaining > 0.0 or knockback.length_squared() > 1.0
	if dash_remaining > 0.0:
		_tick_dash(delta)
	else:
		velocity = motion * stat("move_speed", 220.0) * abilities.movement_scale() + knockback
		position = room.move_actor(position, velocity * delta, Balance.PLAYER_RADIUS)
	knockback = knockback.move_toward(Vector2.ZERO, Balance.PLAYER_KNOCKBACK_DECAY * delta)
	if hero_id() == "CH02" and not displaced and motion.length_squared() > 0.0 and passive_cooldown <= 0.0:
		walk_distance = minf(240.0, walk_distance + position.distance_to(from))
		passive_count = int(walk_distance / 60.0)
	stride += position.distance_to(from) * 0.12
	loadout.tick(delta)
	if combo_queue.is_empty() and attack_buffer > 0.0 and pointer_enabled and not _attack_release_required and room.controls_enabled():
		if fire(aim_direction):
			attack_buffer = 0.0
	if visual_hitstop > 0.0:
		visual_hitstop = maxf(0.0, visual_hitstop - delta)
	else:
		visual_remaining = maxf(0.0, visual_remaining - delta)
		if visual_remaining <= 0.0:
			visual_state = "idle"
	queue_redraw()

func fire(direction: Vector2) -> bool:
	if Game.run == null or Game.run.hp <= 0.0 or shot_cooldown > 0.0 or dash_remaining > 0.0 or not direction.is_finite() or direction.is_zero_approx() or abilities == null:
		return false
	if abilities.busy():
		if not abilities.recovery_chain_ready():
			return false
		abilities.cancel()
	_attack_direction = direction.normalized()
	_attack_critical = false # Resolved once against the primary target's pre-hit snapshot.
	shot_cooldown = stat("attack_interval", 0.5)
	if hero_id() == "CH01":
		attack_remaining = shot_cooldown
		attack_resolved = false
		room.record_attack()
		visual_event("attack_windup", 0.12)
	else:
		if not room.fire_from_player(_attack_direction, _attack_critical):
			shot_cooldown = 0.0
			return false
		muzzle_flash = 0.07
		visual_event("attack_strike", 0.12)
	_play_combat_audio(&"attack", [hero_id()])
	return true

func _tick_attack(delta: float) -> void:
	if attack_remaining <= 0.0:
		return
	var old: float = attack_remaining
	attack_remaining = maxf(0.0, attack_remaining - delta)
	var hit_threshold: float = maxf(0.0, stat("attack_interval", 0.5) - 0.12)
	if not attack_resolved and old >= hit_threshold and attack_remaining <= hit_threshold:
		attack_resolved = true
		_basic_chain_remaining = 0.045
		_attack_direction = aim_direction
		var victims: Array = room.strike_area(position, 105.0, attack_power() * (1.5 if _attack_critical else 1.0), &"primary", "", 12.0, _attack_direction, 100.0, true, {}, true)
		room.add_arc_visual(position, _attack_direction, 105.0, 100.0, Color("e9b16e"), 0.16)
		visual_event("attack_strike", 0.08)
		if not victims.is_empty():
			on_primary_hit(victims[0])
			room.resolve_melee_relics(victims[0], _attack_direction)

func cast_skill(slot: String, target: Vector2) -> bool:
	# Public API remains immediate: a false return never hides a later cast.
	if abilities == null or Game.run == null or Game.run.hp <= 0.0:
		return _reject_skill(slot, target, "unavailable")
	if dash_remaining > 0.0:
		return _reject_skill(slot, target, "dashing")
	if attack_remaining > 0.0 and not attack_resolved:
		return _reject_skill(slot, target, "busy", {"cause":"attack_windup"})
	_pending_skill_slot = slot
	var success: bool = abilities.try_cast(slot, target, false, true)
	last_cast_error = abilities.last_failure
	if success:
		# The basic strike already happened. Only its recovery can be cancelled;
		# shot_cooldown still governs the next held-button attack.
		attack_remaining = 0.0
		_basic_chain_remaining = 0.0
		# Read the committed spec: consuming full Momentum changes the next live
		# preview back to 30 Rage and must not spend a paid-skill discount here.
		loadout.event("skill_cast", {"slot":slot,"base_cost":float(abilities.active.spec.cost),"cast_success":true})
		if room.has_method("record_player_sound"):
			room.record_player_sound()
		_play_combat_audio(&"prepare", [hero_id(), slot])
	_pending_skill_slot = ""
	_emit_skill_feedback(slot, target, "accepted" if success else last_cast_error, abilities.last_failure_details)
	return success

func request_skill(slot: String, target: Vector2) -> bool:
	if not is_instance_valid(room) or not room.controls_enabled() or (slot == "secondary" and not room.pointer_controls_enabled()):
		return _reject_skill(slot, target, "unavailable", {"cause":"input_blocked"})
	if abilities == null or Game.run == null or Game.run.hp <= 0.0:
		return _reject_skill(slot, target, "unavailable")
	if dash_remaining > 0.0:
		return _reject_skill(slot, target, "dashing")
	_pending_skill_slot = slot
	var valid: bool = abilities.can_cast(slot, target, true)
	_pending_skill_slot = ""
	if not valid:
		last_cast_error = abilities.last_failure
		_emit_skill_feedback(slot, target, last_cast_error, abilities.last_failure_details)
		return false
	for pending: Dictionary in combo_queue:
		if str(pending.slot) == slot:
			return _reject_skill(slot, target, "busy", {"cause":"already_queued"})
	var wait: float = _combo_wait_seconds(slot)
	if combo_queue.is_empty() and wait <= 0.00001:
		return cast_skill(slot, target)
	return _append_combo_input({"slot":slot, "target":target}, wait)

func request_attack(direction: Vector2) -> bool:
	if not is_instance_valid(room) or not room.controls_enabled() or not room.pointer_controls_enabled() or _attack_release_required:
		return _reject_skill("attack", position, "unavailable", {"cause":"input_blocked"})
	if Game.run == null or Game.run.hp <= 0.0 or abilities == null:
		return _reject_skill("attack", position, "unavailable")
	if not direction.is_finite() or direction.is_zero_approx():
		return _reject_skill("attack", position, "invalid_direction")
	if dash_remaining > 0.0:
		# A fresh press rejected during a dodge cannot turn into a held-button
		# attack after that dodge. Only a real release can open this input again.
		_attack_release_required = true
		return _reject_skill("attack", position, "dashing")
	var wait: float = _combo_wait_seconds("attack")
	if combo_queue.is_empty() and wait <= 0.00001:
		if not fire(direction):
			return _reject_skill("attack", position, "busy")
		_emit_skill_feedback("attack", position, "accepted")
		return true
	return _append_combo_input({"slot":"attack", "direction":direction.normalized(), "target":position}, wait)

func _combo_wait_seconds(slot: String) -> float:
	var wait: float = _basic_chain_remaining
	if attack_remaining > 0.0 and not attack_resolved:
		var hit_threshold: float = maxf(0.0, stat("attack_interval", 0.5) - 0.12)
		wait = maxf(wait, maxf(0.0, attack_remaining - hit_threshold) + 0.045)
	if abilities != null and abilities.busy():
		wait = maxf(wait, abilities.recovery_chain_wait())
	if slot == "attack":
		wait = maxf(wait, shot_cooldown)
	return wait

func _append_combo_input(request: Dictionary, wait: float) -> bool:
	var slot: String = str(request.slot)
	var target: Vector2 = request.target
	if combo_queue.size() >= COMBO_QUEUE_LIMIT:
		return _reject_skill(slot, target, "busy", {"cause":"queue_full"})
	if combo_queue.is_empty() and wait > SKILL_BUFFER_SECONDS + 0.00001:
		return _reject_skill(slot, target, "busy", {"cause":"early_chain", "chain_in":wait})
	request["age"] = 0.0
	request["remaining"] = SKILL_BUFFER_SECONDS if combo_queue.is_empty() else -1.0
	combo_queue.append(request)
	attack_buffer = 0.0
	_sync_buffered_skill()
	last_cast_error = ""
	_emit_skill_feedback(slot, target, "queued", {"remaining":SKILL_BUFFER_SECONDS, "queue_position":combo_queue.size()})
	return true

func clear_buffered_skill() -> void:
	combo_queue.clear()
	buffered_skill.clear()
	attack_buffer = 0.0
	if InputMap.has_action("attack") and Input.is_action_pressed("attack"):
		_attack_release_required = true

func _sync_buffered_skill() -> void:
	buffered_skill.clear()
	for request: Dictionary in combo_queue:
		if str(request.slot) != "attack":
			buffered_skill = request.duplicate(true)
			return

func queued_action_position(slot: String) -> int:
	for index in combo_queue.size():
		if str(combo_queue[index].slot) == slot:
			return index + 1
	return 0

func _prime_combo_head() -> void:
	if not combo_queue.is_empty() and float(combo_queue[0].remaining) < 0.0:
		# A second or third press waits for its preceding queued action, rather
		# than expiring while that action still owns its legitimate windup.
		combo_queue[0].remaining = SKILL_BUFFER_SECONDS + _combo_wait_seconds(str(combo_queue[0].slot))
	_sync_buffered_skill()

func _drop_pointer_combo_inputs() -> void:
	for index in range(combo_queue.size() - 1, -1, -1):
		if str(combo_queue[index].slot) in ["attack", "secondary"]:
			combo_queue.remove_at(index)
	_prime_combo_head()

func _tick_skill_buffer(delta: float) -> void:
	if combo_queue.is_empty():
		return
	var step: float = maxf(0.0, delta)
	for index in range(combo_queue.size() - 1, -1, -1):
		combo_queue[index].age = float(combo_queue[index].age) + step
		if index == 0:
			combo_queue[index].remaining = maxf(0.0, float(combo_queue[index].remaining) - step)
		if float(combo_queue[index].age) >= COMBO_MAX_AGE or (index == 0 and float(combo_queue[index].remaining) <= 0.0):
			var expired: Dictionary = combo_queue[index].duplicate(true)
			combo_queue.remove_at(index)
			_reject_skill(str(expired.slot), expired.target, "busy", {"cause":"buffer_expired", "remaining":0.0})
	_prime_combo_head()

func _consume_buffered_skill() -> void:
	if combo_queue.is_empty():
		return
	var slot: String = str(combo_queue[0].slot)
	if _combo_wait_seconds(slot) > 0.00001 or (abilities.busy() and not abilities.recovery_chain_ready()):
		return
	var request: Dictionary = combo_queue.pop_front()
	_sync_buffered_skill()
	# Take the request out before signals or loadout hooks run; one press can
	# never cast twice even if an observer responds synchronously.
	if not room.controls_enabled() or (slot in ["attack", "secondary"] and not room.pointer_controls_enabled()):
		_prime_combo_head()
		return
	if slot == "attack":
		if fire(request.direction):
			_emit_skill_feedback(slot, request.target, "accepted")
		else:
			_reject_skill(slot, request.target, "busy")
	else:
		cast_skill(slot, request.target)
	_prime_combo_head()

func _reject_skill(slot: String, target: Vector2, reason: String, extra: Dictionary = {}) -> bool:
	last_cast_error = reason
	if abilities != null:
		abilities.last_failure = reason
		abilities.last_failure_details = extra.duplicate(true)
	_emit_skill_feedback(slot, target, reason, extra)
	return false

func _emit_skill_feedback(slot: String, target: Vector2, reason: String, extra: Dictionary = {}) -> void:
	var definition: Dictionary = skill_definition(slot) if abilities != null else {}
	var details: Dictionary = {"slot":slot, "target":target, "cost":float(definition.get("cost", 0.0)),
		"resource":float(Game.run.resource) if Game.run != null else 0.0,
		"remaining":float(cooldowns.get(slot, 0.0)), "unlock":int(definition.get("unlock", 99)),
		"level":hero_level(), "range":float(definition.get("range", 0.0))}
	details.merge(extra.duplicate(true), true)
	skill_input_feedback.emit(slot, reason, details)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		clear_buffered_skill()
		attack_buffer = 0.0
		# Also cover an attack first pressed while physics is paused, after this
		# notification has already run. Resume must observe a released button.
		_attack_release_required = true

func _exit_tree() -> void:
	clear_buffered_skill()

func _play_combat_audio(event: StringName, arguments: Array = []) -> void:
	if not is_instance_valid(room):
		return
	var audio: Variant = room.get("combat_audio")
	if is_instance_valid(audio) and audio.has_method(event):
		audio.callv(event, arguments)

func resource_cost(amount: float) -> float:
	return loadout.resource_cost(amount, _pending_skill_slot) if loadout != null else amount

func skill_definition(slot: String) -> Dictionary:
	var definition: Dictionary = abilities.spec(slot).duplicate(true)
	if not definition.is_empty():
		definition["cost"] = loadout.resource_cost(float(definition.cost), slot) if loadout != null else float(definition.cost)
	return definition

func cancel_actions() -> void:
	abilities.cancel()
	clear_buffered_skill()
	attack_remaining = 0.0
	attack_resolved = true
	_basic_chain_remaining = 0.0
	attack_buffer = 0.0

func start_dash(direction: Vector2) -> bool:
	if is_instance_valid(room) and room.has_method("objective_blocks_dash") and room.objective_blocks_dash():
		return false
	if dash_cooldown > 0.0 or direction.is_zero_approx() or Game.run == null:
		return false
	if room.move_actor(position, direction.normalized() * 8.0, Balance.PLAYER_RADIUS).distance_to(position) < 1.0:
		return false
	cancel_actions()
	dash_direction = direction.normalized()
	dash_elapsed = 0.0
	dash_remaining = 0.22 if hero_id() == "CH02" else 0.18
	dash_cooldown = 2.2 if hero_id() == "CH01" else 2.0 if hero_id() == "CH02" else 2.6
	room.telemetry["dashes"] += 1
	visual_event("dash", dash_remaining)
	room.add_ring(position, Color("67c7d5"), 28.0, 0.2)
	loadout.event("dash")
	return true

func _tick_dash(delta: float) -> void:
	var step: float = minf(delta, dash_remaining)
	var previous: float = dash_elapsed
	dash_elapsed += step
	dash_remaining = maxf(0.0, dash_remaining - delta)
	if hero_id() == "CH03":
		velocity = Vector2.ZERO
		if previous < 0.08 and dash_elapsed >= 0.08:
			position = room.move_actor(position, dash_direction * 130.0, Balance.PLAYER_RADIUS)
	else:
		velocity = dash_direction * (110.0 / 0.18 if hero_id() == "CH01" else 160.0 / 0.22)
		position = room.move_actor(position, velocity * step, Balance.PLAYER_RADIUS)
	if dash_remaining <= 0.0:
		loadout.event("dash_end")

func dash_protected() -> bool:
	if dash_remaining <= 0.0:
		return false
	match hero_id():
		"CH01": return dash_elapsed < 0.10
		"CH02": return dash_elapsed >= 0.04 and dash_elapsed < 0.16
		_: return dash_elapsed >= 0.08 and dash_elapsed < 0.18

func receive_enemy_status(effect: Dictionary) -> bool:
	if Game.run == null or Game.run.hp <= 0.0:
		return false
	var identifier: String = str(effect.get("id", effect.get("status", "")))
	if identifier not in ["burn", "shock", "chill", "corrosion", "slow", "bleed", "grievous", "damage_reduction", "invulnerable"]:
		return false
	var duration: float = float(effect.get("duration", 4.0 if identifier == "corrosion" else 3.0))
	if not is_finite(duration) or duration <= 0.0:
		return false
	if identifier == "slow":
		var multiplier: float = float(effect.get("magnitude", 0.8))
		if not is_finite(multiplier) or multiplier < 0.0 or multiplier > 1.0:
			return false
		# Ordinary slows share their strongest multiplier and refresh their timer.
		# They remain separate from chill and cannot activate chill-only affixes.
		_enemy_slow_multiplier = minf(_enemy_slow_multiplier, multiplier) if _enemy_slow_remaining > 0.0 else multiplier
		_enemy_slow_remaining = maxf(_enemy_slow_remaining, duration)
		queue_redraw()
		return true
	var power: float = float(effect.get("power", 0.0))
	if not is_finite(power) or power < 0.0:
		return false
	var prior: Dictionary = status.states.get(identifier, {})
	var retain_origin: bool = is_equal_approx(float(prior.get("applied_at", -1.0)),status.clock) and float(prior.get("power", 0.0)) > power
	status.apply(identifier,power,duration)
	if not retain_origin:
		var supplied_origin: Variant = effect.get("origin", position)
		_enemy_status_origins[identifier] = supplied_origin if supplied_origin is Vector2 else position
	# A state refresh recomputes equipment resistances, but is not a player attack,
	# skill cast or successful offensive status-application event.
	if loadout != null:
		loadout.event("state_changed", {"enemy_status":identifier})
	queue_redraw()
	return true

func receive_damage(amount: float, origin: Vector2, context: Dictionary = {}) -> bool:
	var is_dot: bool = bool(context.get("dot", false))
	if Game.run == null or Game.run.hp <= 0.0 or not is_finite(amount) or amount <= 0.0:
		return false
	var damage_context: Dictionary = context.duplicate()
	var status_modifiers: Dictionary = status.damage_modifiers()
	damage_context["damage_reduction"] = maxf(float(damage_context.get("damage_reduction", 0.0)), float(status_modifiers.get("damage_reduction", 0.0)))
	damage_context["invulnerable"] = bool(damage_context.get("invulnerable", false)) or bool(status_modifiers.get("invulnerable", false))
	if bool(damage_context.invulnerable):
		return false
	if not is_dot and (invulnerable > 0.0 or dash_protected()):
		return false
	var incoming: float = amount
	if status.has("corrosion"): damage_context["armor_multiplier"] = 0.85
	var shock_damage: float = 0.0
	if not is_dot:
		invulnerable = Balance.HURT_INVULNERABILITY
		knockback = (position - origin).normalized() * Balance.PLAYER_KNOCKBACK
		if status.has("corrosion"):
			incoming *= 1.08
		shock_damage = status.consume_shock()
	hurt_flash = 0.08 if is_dot else 0.16
	room.telemetry["player_hits"] += 1
	room.add_ring(position, Color("e46b69"), 24.0 if is_dot else 38.0, 0.20 if is_dot else 0.28)
	var previous_shield: float = Game.run.shield
	var previous_hp: float = Game.run.hp
	var modifiers: Dictionary = loadout.modifiers()
	var damaged_run: RunState = Game.run
	damage_context["damage_reduction"] = minf(0.65, float(damage_context.damage_reduction) + maxf(0.0, float(modifiers.get("damage_reduction_bonus", 0.0))))
	Game.damage_player(incoming, damage_context)
	# Shock is a magic packet within this same received-hit event. A lethal
	# first packet may close the run (or restore a demo's backup), so identity
	# must still match before the second packet can reach Core.
	if shock_damage > 0.0 and Game.run == damaged_run and damaged_run.hp > 0.0:
		var shock_context: Dictionary = damage_context.duplicate()
		shock_context["damage_type"] = "magic"
		Game.damage_player(shock_damage, shock_context)
	if not is_dot and (damaged_run.hp < previous_hp or damaged_run.shield < previous_shield):
		_play_combat_audio(&"hurt")
	if Game.run != damaged_run or damaged_run.hp <= 0.0:
		cancel_actions()
		return true
	status.absorb(previous_shield - Game.run.shield)
	Game.run.shield = status.shield()
	if not is_dot:
		knockback *= float(modifiers.get("received_knockback_scale", 1.0))
	loadout.event("damaged", {"hp_damage":previous_hp - Game.run.hp,"shield_absorbed":previous_shield - Game.run.shield,"shield_broken":previous_shield > 0.0 and Game.run.shield <= 0.0,"enemy_damage":true,"dot":is_dot})
	combat_time = 5.0
	if hero_id() == "CH01" and Game.run.hp < previous_hp and rage_hurt_cooldown <= 0.0:
		Game.restore_resource(5.0)
		rage_hurt_cooldown = 1.0
	return true

func grant_guard(amount: float, duration: float, source: String) -> void:
	if Game.run == null:
		return
	status.absorb(maxf(0.0, status.shield() - Game.run.shield))
	var increased: bool = status.grant_guard(amount, duration, source, Game.run.max_hp, source.begins_with("set_") or source.begins_with("equipment:"))
	Game.run.shield = status.shield()
	if increased:
		room.add_ring(position, Color("abd6c3"), 34.0, 0.3)
		if loadout != null:
			loadout.event("shield_gain", {"source":source,"increased":true})

func on_primary_hit(target: Node2D) -> void:
	if Game.run == null:
		return
	combat_time = 5.0
	if hero_id() == "CH01":
		gain_break_stacks(1)
		Game.restore_resource(8.0)
		if passive_cooldown <= 0.0:
			passive_count += 1
			if passive_count >= 3:
				passive_count = 0
				passive_cooldown = 6.0
				grant_guard(Game.run.max_hp * 0.08, 3.0, "three_rivets")
	elif hero_id() == "CH02":
		if walk_distance >= 240.0 and passive_cooldown <= 0.0:
			class_mark_target(target)
			Game.restore_resource(10.0)
			cooldowns.q = maxf(0.0, float(cooldowns.q) - 0.5)
			walk_distance = 0.0
			passive_count = 0
			passive_cooldown = 2.0
	elif passive_cooldown <= 0.0:
		passive_count += 1
		if passive_count >= 4:
			passive_count = 0
			passive_cooldown = 2.0
			Game.restore_resource(6.0)
			charge_nearest_resonance(target.position, 160.0)
			for other in room.targets_in_radius(target.position, 140.0):
				if other != target:
					other.take_damage(attack_power() * 0.3, &"passive", Vector2.ZERO, {"damage_type":"magic", "attacker_stats":Game.run.stats.duplicate(), "original_basic":false, "equipment_eligible":false})
					room.add_arc_between(target.position, other.position)
					break

func gain_break_stacks(amount: int = 1) -> void:
	if hero_id() != "CH01":
		return
	break_stacks = clampi(break_stacks + maxi(amount, 0), 0, 3)
	queue_redraw()

func consume_break_stacks() -> int:
	var result: int = break_stacks
	break_stacks = 0
	return result

func _tick_class_state(delta: float) -> void:
	for key: int in class_marks.keys():
		var entry: Dictionary = class_marks[key]
		var target: Variant = entry.target.get_ref()
		entry.remaining = float(entry.remaining) - maxf(delta, 0.0)
		if not is_instance_valid(target) or not target.is_alive() or float(entry.remaining) <= 0.0:
			class_marks.erase(key)

func class_mark_target(target: Node2D) -> void:
	if hero_id() != "CH02" or not is_instance_valid(target) or not target.is_alive():
		return
	class_marks[target.get_instance_id()] = {"target":weakref(target), "remaining":4.0}
	if class_marks.size() > 32:
		class_marks.erase(class_marks.keys()[0])
	var feedback: Node = get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.class_event("mark", target.position, aim_direction)

## Called once by the shared original-hit pipeline, before equipment multipliers.
## Bonus remains part of that hit and cannot start a second proc chain.
func class_modify_hit_amount(target: Node2D, amount: float, source: StringName, context: Dictionary) -> float:
	if hero_id() != "CH02" or source not in [&"secondary", &"ultimate"] or not bool(context.get("equipment_eligible", true)):
		return amount
	if not is_instance_valid(target) or not class_marks.has(target.get_instance_id()):
		return amount
	var key: int = target.get_instance_id()
	var ready: bool = float(class_marks[key].remaining) > 0.0
	class_marks.erase(key)
	if not ready:
		return amount
	var feedback: Node = get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.class_event("mark_burst", target.position, aim_direction)
	return amount + float(context.get("H", attack_power())) * 1.25

## Called only after a direct hit actually removes health or shield.
func class_record_hit(target: Node2D, source: StringName, context: Dictionary) -> void:
	if hero_id() == "CH02" and source == &"f" and bool(context.get("equipment_eligible", true)):
		class_mark_target(target)

func resonance_nodes() -> Array[Node2D]:
	var result: Array[Node2D] = []
	if not is_instance_valid(room):
		return result
	for child: Node in room.get_children():
		if child.has_method("charge_node") and child.kind == "node" and child.is_active():
			result.append(child)
	return result

## Also used by the room's environmental circuit; no resource or equipment proc.
func charge_resonance(origin: Vector2, reach: float, amount: int = 1) -> int:
	if hero_id() != "CH03":
		return 0
	var charged: int = 0
	for node: Node2D in resonance_nodes():
		if node.position.distance_to(origin) <= reach and room.has_line_of_sight(origin, node.position):
			if node.charge_node(amount):
				charged += 1
	return charged

## Four-beat basic hits feed one nearby capacitor. Prefer an unfilled node;
## excess energy is never banked or allowed through walls/into a second proc.
func charge_nearest_resonance(origin: Vector2, reach: float) -> bool:
	if hero_id() != "CH03" or not origin.is_finite() or not is_finite(reach) or reach < 0.0:
		return false
	var nearest: Node2D = null
	var nearest_distance: float = INF
	for node: Node2D in resonance_nodes():
		var distance: float = node.position.distance_squared_to(origin)
		if node.owner_player != self or int(node.resonance_charge) >= 3 or distance > reach * reach or not room.has_line_of_sight(origin, node.position):
			continue
		if nearest == null or distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and node.get_instance_id() < nearest.get_instance_id()):
			nearest = node
			nearest_distance = distance
	return nearest.charge_node(1) if is_instance_valid(nearest) else false

func class_status() -> Dictionary:
	match hero_id():
		"CH01":
			return {"name":"破势", "current":break_stacks, "max":3, "hint":"普攻 / Q积势 · 右键 / R消耗强化", "color":Color("eabb78")}
		"CH02":
			return {"name":"游猎蓄势", "current":walk_distance, "max":240, "hint":"走满后普攻标记 · 已标记%d · 右键 / R引爆" % class_marks.size(), "color":Color("f5ebc9")}
		_:
			var nodes: Array[Node2D] = resonance_nodes()
			var charge: int = 0
			for node: Node2D in nodes:
				charge += int(node.resonance_charge)
			return {"name":"节点共振", "current":charge, "max":maxi(3, nodes.size() * 3), "hint":"节点%d/2 · 普攻四拍 / Q蓄能 · F引爆 · R充满" % nodes.size(), "color":Color("78d9d1")}

func original_hit(target: Node2D, amount: float, kind: StringName, applied_status: String = "", push: float = 0.0) -> void:
	room.resolve_direct_hit(target, amount, kind, applied_status, push, (target.position - position).normalized())

func visual_event(kind: String, duration: float) -> void:
	visual_state = kind
	visual_remaining = duration
	visual_duration = duration
	var feedback: Node = get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.observe_basic(kind, duration)
	queue_redraw()

func hit_feedback(duration: float) -> void:
	if not Game.profile.get("settings", {}).get("reduced_fx", false):
		visual_hitstop = maxf(visual_hitstop, duration)

func _draw() -> void:
	Visual.draw_hero(self)
