class_name SalvagerPlayer
extends CharacterBody2D

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
var _attack_direction := Vector2.RIGHT
var _attack_critical: bool = false
var _pending_skill_slot: String = ""
var _enemy_status_origins: Dictionary = {}
var _enemy_slow_remaining: float = 0.0
var _enemy_slow_multiplier: float = 1.0

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

func _physics_process(delta: float) -> void:
	if Game.run == null or Game.run.hp <= 0.0 or get_tree().paused:
		return
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	passive_cooldown = maxf(0.0, passive_cooldown - delta)
	rage_hurt_cooldown = maxf(0.0, rage_hurt_cooldown - delta)
	attack_buffer = maxf(0.0, attack_buffer - delta)
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
		receive_damage(float(tick.damage), source_origin, {"dot":true,"status":str(tick.kind)})
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
	if not pointer_enabled:
		attack_buffer = 0.0
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
				cast_skill(slot, get_global_mouse_position())
		if pointer_enabled and Input.is_action_pressed("attack"):
			if not fire(aim_direction):
				attack_buffer = 0.10
	elif room.input_blocked or room.release_gate:
		attack_buffer = 0.0
	abilities.tick(delta)
	_tick_attack(delta)
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
	if attack_buffer > 0.0 and pointer_enabled and room.controls_enabled():
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
	if Game.run == null or shot_cooldown > 0.0 or dash_remaining > 0.0 or direction.is_zero_approx() or abilities.busy():
		return false
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
		_attack_direction = aim_direction
		var victims: Array = room.strike_area(position, 105.0, attack_power() * (1.5 if _attack_critical else 1.0), &"primary", "", 12.0, _attack_direction, 100.0, true)
		room.add_arc_visual(position, _attack_direction, 105.0, 100.0, Color("e9b16e"), 0.16)
		visual_event("attack_strike", 0.08)
		if not victims.is_empty():
			on_primary_hit(victims[0])
			room.resolve_melee_relics(victims[0], _attack_direction)
			hit_feedback(0.035)

func cast_skill(slot: String, target: Vector2) -> bool:
	if abilities == null or attack_remaining > 0.0 or dash_remaining > 0.0:
		return false
	_pending_skill_slot = slot
	var success: bool = abilities.try_cast(slot, target)
	last_cast_error = abilities.last_failure
	if success:
		loadout.event("skill_cast", {"slot":slot,"base_cost":float(abilities.spec(slot).cost),"cast_success":true})
		if room.has_method("record_player_sound"):
			room.record_player_sound()
		_play_combat_audio(&"cast", [hero_id(), slot])
	_pending_skill_slot = ""
	return success

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
	attack_remaining = 0.0
	attack_resolved = true
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
	if identifier not in ["burn", "shock", "chill", "corrosion", "slow"]:
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
	if not is_dot and (invulnerable > 0.0 or dash_protected()):
		return false
	var incoming: float = amount
	if not is_dot:
		invulnerable = Balance.HURT_INVULNERABILITY
		knockback = (position - origin).normalized() * Balance.PLAYER_KNOCKBACK
		if status.has("corrosion"):
			incoming *= 1.08
		incoming += status.consume_shock()
	hurt_flash = 0.08 if is_dot else 0.16
	room.telemetry["player_hits"] += 1
	room.add_ring(position, Color("e46b69"), 24.0 if is_dot else 38.0, 0.20 if is_dot else 0.28)
	var previous_shield: float = Game.run.shield
	var previous_hp: float = Game.run.hp
	var modifiers: Dictionary = loadout.modifiers()
	var original_dr: float = float(Game.run.stats.get("equipment_damage_reduction", 0.0))
	var damaged_run: RunState = Game.run
	Game.run.stats["equipment_damage_reduction"] = minf(0.35, original_dr + float(modifiers.get("damage_reduction_bonus", 0.0)))
	Game.damage_player(incoming)
	damaged_run.stats["equipment_damage_reduction"] = original_dr
	if not is_dot and (damaged_run.hp < previous_hp or damaged_run.shield < previous_shield):
		_play_combat_audio(&"hurt")
	if Game.run == null or Game.run.hp <= 0.0:
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
		Game.restore_resource(8.0)
		if passive_cooldown <= 0.0:
			passive_count += 1
			if passive_count >= 3:
				passive_count = 0
				passive_cooldown = 6.0
				grant_guard(Game.run.max_hp * 0.08, 3.0, "three_rivets")
	elif hero_id() == "CH02":
		if walk_distance >= 240.0 and passive_cooldown <= 0.0:
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
			for other in room.targets_in_radius(target.position, 140.0):
				if other != target:
					other.take_damage(attack_power() * 0.3, &"passive")
					room.add_arc_between(target.position, other.position)
					break

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
