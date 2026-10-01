class_name MineEnemy
extends CharacterBody2D
const Numerical = preload("res://config/numerical_rules.gd")

const HealthScript = preload("res://scripts/combat/health.gd")
const StatusScript = preload("res://scripts/combat/combat_status.gd")
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const TextureSampler = preload("res://scripts/ui/texture_sampler.gd")
const BrainScript = preload("res://scripts/combat/enemy_brain.gd")
const BodyVisualScript = preload("res://scripts/combat/enemy_visual.gd")
const EnemyPalette = preload("res://scripts/combat/enemy_palette.gd")
const ImageBounds = preload("res://scripts/combat/hero_visual.gd")
const MAX_PUSH_PULSES: int = 16
static var _body_regions: Dictionary = {}
var room: Node2D
var health: CombatHealth
var state: StringName = &"emerging"
var state_time: float = Balance.ENEMY_SPAWN_GRACE
var aim_direction := Vector2.LEFT
var knockback := Vector2.ZERO
## Distance-authored skill pushes are integrated independently of the legacy
## basic-hit velocity. Each pulse spends its distance once over a short ease-out;
## later hits never restart an earlier pulse's lifetime.
var _pushes: Array[Dictionary] = []
var hurt_flash: float = 0.0
var burn_remaining: float = 0.0
var burn_tick: float = 0.0
var lifetime: float = 0.0
var body_texture: Texture2D
var empty_body_texture: Texture2D
var body_region := Rect2()
var body_bounds := Rect2(-43,-48,86,86)
var status_textures: Dictionary = {}
var status: CombatStatus = StatusScript.new()
var rank: String = "normal"
var armor: float = 0.0
var magic_resist: float = 0.0
var reaction_cooldown: float = 0.0
var reaction_remaining: float = 0.0
var navigation_timer: float = 0.0
var navigation_vector := Vector2.ZERO
var last_damage_context: Dictionary = {}
## Receipt for the most recent packet, captured before death/phase callbacks.
## Auxiliary support shields belong to the receiving actor even when HP and
## CombatStatus shields are untouched. take_damage keeps its historical bool API.
var last_damage_result: Dictionary = {}
var last_damage_direction := Vector2.ZERO
var profile: Dictionary = {}
var brain: RefCounted
var enemy_id: String = ""
var enemy_level: int = 1
var navigation_radius: float = Balance.ENEMY_RADIUS
var move_speed: float = Balance.ENEMY_SPEED
var attack_range: float = Balance.ENEMY_RANGE
var contact_damage: float = Balance.ENEMY_DAMAGE
var actor_kind: String = "enemy"
var static_actor: bool = false
var reward_enabled: bool = true
var reward_spawn_id: String = ""
var zone_index: int = -1
var threat_cost: float = 1.0
var owner_enemy: WeakRef
var training_ai_disabled: bool = false
var aggro_target: WeakRef
var aggro_hold: float = 0.0
var body_visual: Node2D
## Temporary arena openings affect resolved defense, never the armor base. This
## lets natural armor changes (such as a destroyed support pod) survive expiry.
var _biome_counters: Dictionary = {}

func configure(next_profile: Dictionary, options: Dictionary = {}) -> void:
	_biome_counters.clear()
	aggro_target = null
	aggro_hold = 0.0
	profile = next_profile.duplicate(true)
	status.ruleset_version = int(profile.get("ruleset_version", Numerical.LEGACY))
	enemy_id = str(profile.get("enemy_id", ""))
	enemy_level = int(profile.get("enemy_level", 1))
	navigation_radius = float(profile.get("navigation_radius", Balance.ENEMY_RADIUS))
	move_speed = float(profile.get("move_speed", Balance.ENEMY_SPEED))
	attack_range = float(profile.get("attack_range", Balance.ENEMY_RANGE))
	contact_damage = float(profile.get("damage", Balance.ENEMY_DAMAGE))
	# Profiles already resolve level, role and elite growth; do not add it twice.
	armor = maxf(0.0, float(profile.get("armor", 0.0)))
	magic_resist = maxf(0.0, float(profile.get("magic_resist", 0.0)))
	rank = str(profile.get("rank", "normal"))
	zone_index = int(options.get("zone_index", profile.get("zone_index", -1)))
	threat_cost = float(profile.get("effective_threat_cost", 1.0))
	reward_enabled = bool(options.get("reward_enabled", true))
	reward_spawn_id = str(options.get("reward_spawn_id", ""))
	static_actor = bool(options.get("static_actor", false))
	actor_kind = str(options.get("actor_kind", "enemy"))
	if is_instance_valid(options.get("owner", null)):
		owner_enemy = weakref(options.owner)
	if static_actor:
		set_meta("enemy_skill_anchor", true)

func cast_enemy_skill(skill: Dictionary) -> void:
	if room.enemy_skills != null and is_alive():
		room.enemy_skills.emit_skill(self, skill)

func _exit_tree() -> void:
	if is_instance_valid(room) and is_instance_valid(room.enemy_skills):
		room.enemy_skills.cancel_owner(self)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body_texture = TextureSampler.sampled("res://assets/characters/rust_mite.png")
	if not enemy_id.is_empty():
		var generated_path: String = "res://assets/generated/enemies/" + enemy_id + "_v1.png"
		if FileAccess.file_exists(generated_path) or ResourceLoader.exists(generated_path):
			body_texture = TextureSampler.sampled(generated_path)
			if not _body_regions.has(generated_path):
				_body_regions[generated_path] = ImageBounds._visible_region(body_texture.get_image())
			body_region = _body_regions[generated_path]
			var height: float = clampf(navigation_radius*3.8,66.0,88.0)
			var width: float = body_region.size.x / maxf(1.0,body_region.size.y) * height
			body_bounds = Rect2(-width*.5,18.0-height,width,height)
		if enemy_id == "M35":
			empty_body_texture = TextureSampler.sampled("res://assets/generated/enemies/M35_empty_v1.png")
	if static_actor:
		body_texture = null
	for id: String in ["burn", "shock", "chill", "corrosion"]:
		status_textures[id] = TextureSampler.sampled("res://assets/generated/ui/state_" + id + "_v1.png")
	health = HealthScript.new()
	add_child(health)
	health.reset(float(profile.get("max_hp", Balance.ENEMY_HP)), int(profile.get("ruleset_version", Numerical.LEGACY)))
	health.depleted.connect(_die)
	if not profile.is_empty() and not static_actor:
		brain = BrainScript.new()
		brain.configure(profile)
	if not static_actor:
		body_visual = BodyVisualScript.new()
		body_visual.show_behind_parent = true
		add_child(body_visual)
		body_visual.configure(self)

func impact_material() -> String:
	if enemy_id in ["M04", "M10", "M11", "M12", "M13", "M14", "M15", "M16", "M17", "M18", "M28", "M29", "M32", "M33", "M35"]:
		return "organic"
	if enemy_id in ["M30", "M31", "M34", "M36"] or enemy_id.is_empty():
		return "stone"
	return "metal"

func receive_confirmed_impact(direction: Vector2, strength: float, heavy: bool, reaction_style: String = "CH01") -> void:
	if is_instance_valid(body_visual):
		body_visual.receive_impact(direction, strength, heavy, reaction_style)

func impact_anchor(direction: Vector2) -> Dictionary:
	return body_visual.contact_anchor(direction) if is_instance_valid(body_visual) else {}

func is_alive() -> bool:
	return health != null and not health.dead

func visible_status_ids() -> Array[String]:
	var active: Array[String] = []
	for id: String in StatusScript.VALID_STATES:
		if status.has(id):
			active.append(id)
	return active

func _physics_process(delta: float) -> void:
	if not is_alive() or Game.run == null or Game.run.hp <= 0.0 or get_tree().paused:
		return
	if owner_enemy != null:
		var owner_actor: Node2D = owner_enemy.get_ref()
		if not is_instance_valid(owner_actor) or not owner_actor.is_alive():
			queue_free()
			return
	lifetime += delta
	hurt_flash = maxf(0.0, hurt_flash - delta)
	tick_statuses(delta)
	if not is_alive():
		return
	if static_actor:
		queue_redraw()
		return
	aggro_hold = maxf(0.0, aggro_hold - delta)
	var victim: Node2D = _select_aggro_target()
	if not is_instance_valid(victim):
		velocity = Vector2.ZERO
		return
	var offset: Vector2 = victim.position - position
	var distance := offset.length()
	reaction_cooldown = maxf(0.0, reaction_cooldown - delta)
	reaction_remaining = maxf(0.0, reaction_remaining - delta)
	navigation_timer -= delta
	velocity = Vector2.ZERO
	if training_ai_disabled:
		_finish_motion(delta)
		return
	if brain != null:
		brain.tick(self, delta, victim)
		if state == &"chase":
			velocity += _separation()
		if status.has("chill"):
			velocity *= 0.9 if rank == "boss" else 0.8
		_finish_motion(delta)
		return
	state_time -= delta
	match state:
		&"emerging":
			if state_time <= 0.0:
				state = &"chase"
		&"chase":
			if distance > 0.1:
				aim_direction = offset / distance
			if distance <= Balance.ENEMY_RANGE + Balance.PLAYER_RADIUS and room.has_line_of_sight(position, victim.position):
				state = &"windup"
				state_time = Balance.ENEMY_WINDUP
			else:
				if navigation_timer <= 0.0:
					navigation_vector = room.navigation_direction(position, victim.position, navigation_radius)
					navigation_timer = 0.18
				velocity = navigation_vector * Balance.ENEMY_SPEED + _separation()
				if status.has("chill"):
					velocity *= 0.9 if rank == "boss" else 0.8
		&"windup":
			if state_time <= 0.0:
				state = &"recovery"
				state_time = Balance.ENEMY_RECOVERY
				room.add_slash(position, aim_direction)
				if distance <= Balance.ENEMY_RANGE + Balance.PLAYER_RADIUS and offset.normalized().dot(aim_direction) > 0.35 and room.has_line_of_sight(position, victim.position):
					victim.receive_damage(Balance.ENEMY_DAMAGE, position)
		&"recovery":
			if state_time <= 0.0:
				state = &"chase"
	_finish_motion(delta)

func _valid_aggro_target(target: Node2D) -> bool:
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	if target == room.player:
		return Game.run != null and Game.run.hp > 0.0
	return target is HeroDeployment and target.room == room and target.kind == "node" and target.is_alive()

func _select_aggro_target() -> Node2D:
	var current: Node2D = aggro_target.get_ref() as Node2D if aggro_target != null else null
	if not _valid_aggro_target(current):
		current = room.player if _valid_aggro_target(room.player) else null
	# Keep a live target through the committed attack. Geometry stops tracking
	# at lock; a destroyed node immediately falls back to the living player.
	if _valid_aggro_target(current) and (aggro_hold > 0.0 or state not in [&"chase", &"emerging", &"idle"]):
		aggro_target = weakref(current)
		return current
	for candidate: Variant in room.enemy_skill_targets():
		if not candidate is Node2D or not _valid_aggro_target(candidate) or not room.has_line_of_sight(position, candidate.position):
			continue
		if current == null or not room.has_line_of_sight(position, current.position) or position.distance_to(candidate.position) + 24.0 < position.distance_to(current.position):
			current = candidate
	aggro_target = weakref(current) if current != null else null
	return current

func _finish_motion(delta: float) -> void:
	if room.enemy_skills != null:
		velocity *= room.enemy_skills.movement_multiplier(self)
	velocity += knockback
	if reaction_remaining > 0.0:
		velocity = knockback
	knockback = knockback.move_toward(Vector2.ZERO, Balance.ENEMY_KNOCKBACK_DECAY * delta)
	position = room.move_actor(position, velocity * delta, navigation_radius)
	_advance_pushes(delta)
	if is_instance_valid(body_visual):
		body_visual.advance(delta)
	queue_redraw()

func _separation() -> Vector2:
	var force := Vector2.ZERO
	for other in room.enemies.get_children():
		if other == self or not other.is_alive() or other.static_actor:
			continue
		var offset: Vector2 = position - other.position
		var distance := offset.length()
		var spacing: float = maxf(Balance.ENEMY_SEPARATION_DISTANCE, navigation_radius + other.navigation_radius + 4.0)
		if distance > 0.01 and distance < spacing:
			force += offset / distance * (spacing - distance) * Balance.ENEMY_SEPARATION_STRENGTH
	return force.limit_length(move_speed * Balance.ENEMY_SEPARATION_SPEED_RATIO)

func take_damage(amount: float, kind: StringName, from_direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
	last_damage_result = {"confirmed":false,"hp_damage":0,"status_shield_damage":0,"auxiliary_shield_damage":0,"shield_damage":0,"shield_broken":false}
	if not is_alive() or Game.run == null:
		return false
	status.ruleset_version = int(profile.get("ruleset_version", Numerical.LEGACY))
	var damage_type := Damage.normalized_type(str(context.get("damage_type", str(kind))))
	var numerical: bool = status.ruleset_version == Numerical.V2
	if status.has("invulnerable") or (numerical and (not is_finite(amount) or amount <= 0.0 or bool(context.get("invulnerable", false)))):
		return false
	var auxiliary_absorbed: Variant = Numerical.amount(0.0, status.ruleset_version)
	# Enemy barrier/stance multipliers are reduction, so true damage bypasses
	# them. Immunity is checked above; shields are still consumed below.
	if room.enemy_skills != null and damage_type != "true":
		var before_support: float = amount
		amount = room.enemy_skills.filter_incoming_damage(self, amount, kind, from_direction)
		auxiliary_absorbed = Numerical.amount(maxf(0.0, before_support - amount), status.ruleset_version)
	if amount <= 0.0:
		if numerical and auxiliary_absorbed > 0:
			last_damage_result.merge({"confirmed":true,"auxiliary_shield_damage":auxiliary_absorbed,"shield_damage":auxiliary_absorbed}, true)
			last_damage_context = context.duplicate()
		return bool(last_damage_result.confirmed) if numerical else false
	last_damage_context = context.duplicate()
	if last_damage_context.is_empty():
		last_damage_context = {"damage_source":str(kind),"equipment_eligible":false,"original_basic":false,"proc_depth":1}
	if (kind == &"primary" or kind == &"child") and not static_actor and rank != "boss" and from_direction.is_finite():
		knockback += from_direction * Balance.ENEMY_KNOCKBACK
	var defense: Dictionary = status.damage_modifiers()
	defense.merge({"armor":effective_armor() * (0.85 if status.has("corrosion") else 1.0),"magic_resist":magic_resist}, true)
	var settlement := context.duplicate()
	settlement["ruleset_version"] = status.ruleset_version
	var weakpoint := 1.35 if biome_weakpoint_open() else 1.0
	if status.ruleset_version == Numerical.V2: settlement["post_defense_multiplier"] = weakpoint
	var resolved: Dictionary = Damage.resolve(amount, damage_type, context.get("attacker_stats", {}), defense, settlement)
	var final_amount: float = float(resolved.damage) * (1.0 if status.ruleset_version == Numerical.V2 else weakpoint)
	var health_before: float = health.current
	var shield_before: float = status.shield()
	final_amount = status.absorb(final_amount)
	if final_amount > 0.0 or status.shield() < shield_before:
		hurt_flash = 0.1
	if brain != null:
		var hit_context: Dictionary = context.duplicate()
		hit_context.merge({"damage":final_amount,"kind":str(kind),"direction":from_direction},true)
		brain.on_damaged(self, hit_context)
	if final_amount > 0.0:
		last_damage_direction = from_direction.normalized() if from_direction.is_finite() else Vector2.ZERO
	# Capture the packet before health.damage can emit a death/phase signal. A
	# subsequent resurrection or spawned actor must not inflate this number.
	var consumed_hp: float = minf(maxf(0.0, final_amount), maxf(0.0, health_before))
	var consumed_shield: float = maxf(0.0, shield_before - status.shield())
	last_damage_result = {"confirmed":consumed_hp + consumed_shield + float(auxiliary_absorbed) > 0.0,
		"hp_damage":Numerical.amount(consumed_hp, status.ruleset_version),"status_shield_damage":Numerical.amount(consumed_shield, status.ruleset_version),
		"auxiliary_shield_damage":auxiliary_absorbed,"shield_damage":Numerical.amount(consumed_shield + float(auxiliary_absorbed), status.ruleset_version),
		"shield_broken":shield_before > 0.0 and status.shield() <= 0.0}
	if (consumed_hp > 0.0 or consumed_shield > 0.0) and kind == &"primary" and not static_actor and _valid_aggro_target(room.player):
		# Direct hero attacks draw attention; status ticks do not reset this hold.
		aggro_target = weakref(room.player)
		aggro_hold = 2.0
	var number_at: Vector2 = position - Vector2(0, 65 if body_texture != null else 26)
	if consumed_hp > 0.0:
		room.add_damage_text(number_at, consumed_hp, kind, context)
	if consumed_shield > 0.0:
		var shield_context: Dictionary = context.duplicate()
		shield_context["feedback_kind"] = "shield"
		room.add_damage_text(number_at, consumed_shield, kind, shield_context)
	var damaged: bool = health.damage(final_amount)
	return bool(last_damage_result.confirmed) if numerical else damaged

func apply_biome_counter(kind: String, duration: float = 6.0) -> bool:
	if actor_kind != "enemy" or static_actor or rank == "boss" or not is_alive() or is_queued_for_deletion() or (is_inside_tree() and get_tree().paused):
		return false
	if kind not in ["solar_conduit", "brood_egg", "war_drum"] or not is_finite(duration) or duration <= 0.0:
		return false
	if kind == "solar_conduit":
		status.guards.clear()
		if is_instance_valid(room) and is_instance_valid(room.enemy_skills) and room.enemy_skills.has_method("clear_target_guards"):
			room.enemy_skills.clear_target_guards(self)
	_biome_counters[kind] = clampf(duration, 0.01, 30.0)
	queue_redraw()
	return true

func biome_weakpoint_open() -> bool:
	return not _biome_counters.is_empty() and is_alive()

func effective_armor() -> float:
	return 0.0 if float(_biome_counters.get("war_drum", 0.0)) > 0.0 else armor

func biome_counter_status() -> Dictionary:
	return {"weakpoint":biome_weakpoint_open(), "damage_multiplier":1.35 if biome_weakpoint_open() else 1.0, "effective_armor":effective_armor(), "remaining":_biome_counters.duplicate()}

func heal(amount: float) -> float:
	if not is_alive():
		return 0.0
	var restored := minf(health.maximum - health.current, Damage.healing(amount, status.has("grievous"), int(profile.get("ruleset_version", Numerical.LEGACY))))
	health.current += restored
	queue_redraw()
	return restored

func apply_burn() -> void:
	apply_status("burn", room.player.attack_power())

func tick_burn(delta: float) -> void:
	tick_statuses(delta)

func apply_status(id: String, power: float, duration: float = -1.0) -> bool:
	if not is_alive():
		return false
	if id not in StatusScript.VALID_STATES and id != "guard":
		return false
	status.ruleset_version = int(profile.get("ruleset_version", Numerical.LEGACY))
	var accepted: bool = false
	if id == "guard":
		accepted = bool(status.grant_guard_result(power, 4.0 if duration <= 0.0 else duration, "enemy", health.maximum).accepted_refresh)
	elif id in ["damage_reduction", "invulnerable"]:
		accepted = status.apply(id, power, duration)
	else:
		var duration_bonus: float = room.player.stat("status_duration", 0.0)
		if id == "chill":
			duration_bonus += float(room.player.loadout.modifiers().get("chill_duration_bonus", 0.0))
		var life: float = duration if duration > 0.0 else (4.0 if id == "corrosion" else 3.0) * (1.0 + minf(0.4, duration_bonus))
		accepted = status.apply(id, power * (1.0 + room.player.stat("burn_damage", 0.0)) if id == "burn" else power, life, power)
	burn_remaining = float(status.states.get("burn", {}).get("remaining", 0.0))
	burn_tick = float(status.states.get("burn", {}).get("tick", 0.0))
	queue_redraw()
	return accepted if status.ruleset_version == Numerical.V2 else true

func tick_statuses(delta: float) -> void:
	if is_finite(delta) and delta > 0.0 and (not is_inside_tree() or not get_tree().paused):
		for kind: String in _biome_counters.keys():
			_biome_counters[kind] = maxf(0.0, float(_biome_counters[kind]) - delta)
			if float(_biome_counters[kind]) <= 0.0:
				_biome_counters.erase(kind)
	for tick: Dictionary in status.tick(delta):
		if not is_alive():
			break
		if tick.kind == "burn":
			room.telemetry["burn_ticks"] += 1
		var event_id: String = "dot:" + str(get_instance_id()) + ":" + str(status.clock)
		take_damage(float(tick.damage), StringName(tick.kind), Vector2.ZERO, {"attack_id":event_id,"root_event_id":event_id,"damage_source":tick.kind,"damage_type":tick.damage_type,"attacker_stats":Game.run.stats,"proc_depth":1,"equipment_eligible":false,"original_basic":false,"target_states":[tick.kind],"H":float(tick.H),"X":float(tick.damage)})
	burn_remaining = float(status.states.get("burn", {}).get("remaining", 0.0))
	burn_tick = float(status.states.get("burn", {}).get("tick", 0.0))

func apply_knockback(direction: Vector2, distance: float) -> void:
	if static_actor or not is_alive() or not direction.is_finite() or not is_finite(distance) or distance <= 0.0 or direction.is_zero_approx():
		return
	if rank == "boss":
		room.add_ring(position, Color("beb09a"), 24.0, 0.2)
		return
	var length: float = distance * (0.5 if rank == "elite" else 1.0)
	var travel: Vector2 = direction.normalized() * length
	var reachable: Vector2 = room.move_actor(position, travel, navigation_radius) - position
	# A wall-blocked request must not interrupt a perfectly stationary enemy.
	if reachable.length_squared() <= 0.0001:
		return
	var projected: Vector2 = room.move_actor(position, pending_displacement() + travel, navigation_radius)
	_compact_pushes()
	_pushes.append({"travel":travel,"elapsed":0.0,"duration":clampf(0.10 + length * 0.0005, 0.10, 0.16)})
	# Commit the interrupt now, before the next brain tick can release damage
	# from the old locked standing point. This does not move the body early.
	if brain != null:
		brain.on_displacement_committed(self, projected)
	if room.enemy_skills != null:
		room.enemy_skills.cancel_displaced_motion(self)
	if rank == "normal" and reaction_cooldown <= 0.0:
		reaction_cooldown = 1.0
		reaction_remaining = 0.12

func has_pending_displacement() -> bool:
	return not _pushes.is_empty()

func pending_displacement() -> Vector2:
	var remaining := Vector2.ZERO
	for push: Dictionary in _pushes:
		var left: float = 1.0 - clampf(float(push.elapsed) / float(push.duration), 0.0, 1.0)
		remaining += Vector2(push.travel) * left * left
	return remaining

func _compact_pushes() -> void:
	if _pushes.size() < MAX_PUSH_PULSES:
		return
	# Rare bursts share a bounded 16-pulse queue. Prefer equal deadlines so
	# same-frame impacts merge without extending an older batch's lifetime.
	# If all differ, the closest pair retains its latest existing deadline;
	# no pulse acquires the newly arriving hit's duration.
	var first_index: int = 0
	var second_index: int = 1
	var closest_deadline: float = INF
	for left: int in range(_pushes.size() - 1):
		var left_time: float = float(_pushes[left].duration) - float(_pushes[left].elapsed)
		for right: int in range(left + 1, _pushes.size()):
			var right_time: float = float(_pushes[right].duration) - float(_pushes[right].elapsed)
			var difference: float = absf(left_time - right_time)
			if difference < closest_deadline:
				closest_deadline = difference
				first_index = left
				second_index = right
	var first: Dictionary = _pushes[first_index]
	var second: Dictionary = _pushes[second_index]
	_pushes.remove_at(second_index)
	_pushes.remove_at(first_index)
	var remainder := Vector2.ZERO
	var deadline: float = 0.0
	for push: Dictionary in [first, second]:
		var left: float = maxf(0.0, float(push.duration) - float(push.elapsed))
		remainder += Vector2(push.travel) * pow(left / float(push.duration), 2.0)
		deadline = maxf(deadline, left)
	if deadline > 0.0 and not remainder.is_zero_approx():
		_pushes.push_front({"travel":remainder,"elapsed":0.0,"duration":deadline})

func _advance_pushes(delta: float) -> void:
	if delta <= 0.0 or _pushes.is_empty():
		return
	var displacement := Vector2.ZERO
	for push: Dictionary in _pushes.duplicate():
		var before: float = clampf(float(push.elapsed) / float(push.duration), 0.0, 1.0)
		push.elapsed = minf(float(push.duration), float(push.elapsed) + delta)
		var after: float = float(push.elapsed) / float(push.duration)
		# Integral of linearly decaying velocity; independent of frame rate.
		displacement += Vector2(push.travel) * ((1.0 - before) * (1.0 - before) - (1.0 - after) * (1.0 - after))
		if after >= 1.0:
			_pushes.erase(push)
	position = room.move_actor(position, displacement, navigation_radius)

func _die() -> void:
	_biome_counters.clear()
	room.enemy_died(self)
	queue_free()

func _draw() -> void:
	if health == null:
		return
	if static_actor:
		_draw_skill_anchor()
		return
	var reduced: bool = Game.profile.get("settings", {}).get("reduced_fx", false)
	var show_skill_paths: bool = bool(Game.profile.get("settings", {}).get("enemy_skill_paths", true))
	if state == &"emerging":
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 24, Color(0.9, 0.42, 0.41, 0.65), 2.0, true)
		draw_line(Vector2(-5,-30), Vector2(5,-30), Color("e46b69"), 2.0)
	if state == &"windup" and show_skill_paths:
		var progress := 1.0 - state_time / Balance.ENEMY_WINDUP
		var fan := PackedVector2Array([Vector2.ZERO])
		for i in range(13):
			fan.append(aim_direction.rotated(-1.15 + float(i) / 12.0 * 2.3) * (Balance.ENEMY_RANGE + 8.0))
		draw_colored_polygon(fan, Color(0.89, 0.28, 0.24, 0.13 + progress * 0.15))
		draw_polyline(fan, Color(0.95, 0.44, 0.40, 0.85), 1.5, true)
		draw_arc(Vector2.ZERO, 42 if body_texture != null else 25, -PI / 2, -PI / 2 + TAU * progress, 24, Color("f1b466"), 3, true)
	draw_set_transform(Vector2(0,10), 0.0, Vector2(1,0.5))
	draw_circle(Vector2.ZERO, 22.0, Color(0.20, 0.17, 0.25, 0.25))
	draw_set_transform(Vector2.ZERO)
	if body_texture != null:
		if show_skill_paths and state in [&"windup", &"telegraph", &"locked"]:
			draw_arc(Vector2.ZERO,navigation_radius,0,TAU,24,Color(0.89,0.28,0.27,0.52),1.0,true)
		var tint := Color(1,1,1,.35 if bool(get_meta("enemy_shadow_stealth",false)) else 1.0)
		if hurt_flash > 0.0 and not reduced:
			var lift: float = .12*clampf(hurt_flash/.1,0.0,1.0)
			tint.r += lift
			tint.g += lift
			tint.b += lift
		var image_texture: Texture2D = body_texture
		if enemy_id == "M35" and empty_body_texture != null and (not is_instance_valid(room.enemy_props) or not room.enemy_props.carried_by(self)):
			image_texture = empty_body_texture
		if is_instance_valid(body_visual):
			pass # Body child renders behind this actor's bars, states and tells.
		elif body_region.has_area():
			draw_texture_rect_region(image_texture,body_bounds,body_region,tint)
		else:
			draw_texture_rect(image_texture,body_bounds,false,tint)
	elif not is_instance_valid(body_visual):
		_draw_fallback_body()
	if bool(get_meta("solid_owner_ring",false)) or str(profile.get("behavior_id","")) == "solid_ring_decoy":
		draw_circle(Vector2(0,18),12.0,Color(.6,.77,.85,.65))
	if state == &"windup" and brain == null:
		var marker_y := -70.0 if body_texture != null else -35.0
		draw_line(Vector2(0,marker_y), Vector2(0,marker_y+8), Color("fff0cf"), 3)
		draw_circle(Vector2(0,marker_y+13), 1.8, Color("fff0cf"))
	if burn_remaining > 0.0:
		for i in range(3):
			var base := Vector2(-10 + i * 10, -34 if body_texture != null else -17)
			var flicker := 3.0 * sin(lifetime * 14 + i)
			draw_colored_polygon(PackedVector2Array([base + Vector2(-4,0),base+Vector2(1,-14-flicker),base+Vector2(5,0)]),Color("e6aa4a"))
	var visible_statuses: Array[String] = visible_status_ids()
	var status_x: float = -float(visible_statuses.size()) * 10.0
	for id: String in visible_statuses:
		var icon: Texture2D = status_textures.get(id)
		var color: Color = {"burn":Color("e6aa4a"),"shock":Color("eed897"),"chill":Color("98d8e2"),"corrosion":Color("a7c783"),"bleed":Color("e36f79"),"grievous":Color("c670b2"),"damage_reduction":Color("91bbd0"),"invulnerable":Color("fff4bd")}[id]
		draw_rect(Rect2(status_x,-76,18,18),Color("fff0cf"))
		draw_rect(Rect2(status_x,-76,18,18),Color("80617e"),false,1.0)
		if icon != null:
			var icon_size: Vector2 = icon.get_size()
			var extent: Vector2 = icon_size * minf(18.0/icon_size.x,18.0/icon_size.y)
			draw_texture_rect(icon,Rect2(Vector2(status_x,-76)+(Vector2(18,18)-extent)*.5,extent),false)
		else:
			draw_circle(Vector2(status_x+9,-67),4.0,color)
		status_x += 20.0
	if status.shield() > 0.0:
		draw_arc(Vector2.ZERO, 28.0, 0, TAU, 24, Color("addbca"), 2.0, true)
	var biome_skill: Dictionary = profile.get("biome_skill", {})
	if str(biome_skill.get("id", "")) == "blood_rage" and health.current <= health.maximum * float(biome_skill.get("health_threshold", 0.5)):
		draw_arc(Vector2.ZERO, navigation_radius + 8.0, 0, TAU, 24, Color("e77755"), 2.0, true)
	if health.current < health.maximum or (not enemy_id.is_empty() and position.distance_to(room.player.position)<520):
		var bar_y: float = body_bounds.position.y-8.0 if body_texture != null else -40.0
		draw_rect(Rect2(-19,bar_y-1,38,6),Color("4d3854"))
		draw_rect(Rect2(-18,bar_y,36,4),Color("f1d9b4"))
		draw_rect(Rect2(-18,bar_y,36 * health.current / health.maximum,4),Color("d65b65"))
	if not enemy_id.is_empty():
		var nearby: bool = position.distance_to(room.player.position)<300
		var english: bool = Words.locale == "en"
		var caption: String = "Lv.%d" % enemy_level
		if rank == "elite":
			caption += " Elite" if english else " 精英"
		if nearby or hurt_flash > 0:
			caption += " " + str(profile.get("name_en" if english else "name",enemy_id))
		if get_local_mouse_position().length() < 48.0 and actor_kind == "enemy":
			var role: String = str(profile.get("archetype","skirmisher"))
			caption += " · " + (role.capitalize() if english else str({"tank":"坦克","caster":"法系","assassin":"刺客","support":"支援","skirmisher":"散兵"}.get(role,"野怪")))
			caption += " / M" if english and profile.get("damage_type","physical")=="magic" else " / P" if english else " / 魔法" if profile.get("damage_type","physical")=="magic" else " / 物理"
			caption += " · " + str(profile.get("biome_skill_name_en" if english else "biome_skill_name", ""))
		var text_width: float = room.fx_font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		draw_rect(Rect2(-text_width*.5-4,25,text_width+8,16),Color(1.0,.945,.82,.93))
		draw_rect(Rect2(-text_width*.5-4,25,text_width+8,16),Color(.46,.34,.45,.72),false,1.0)
		draw_string(room.fx_font,Vector2(-text_width*.5,37),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("49364f"))

func _draw_skill_anchor() -> void:
	var plate: bool = str(get_meta("enemy_skill_anchor_kind", "")) == "weld_cover" or actor_kind == "cover"
	var facing: Vector2 = get_meta("enemy_skill_anchor_direction",Vector2.RIGHT)
	draw_set_transform(Vector2.ZERO,facing.angle())
	if plate:
		draw_rect(Rect2(-8,-24,16,48),Color("657e89"))
		draw_rect(Rect2(-8,-24,16,48),Color("dcac65"),false,2)
		for y in [-15,0,15]:
			draw_line(Vector2(-5,y),Vector2(5,y),Color("e8e1c7"),2)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-10,0),Vector2(0,-13),Vector2(10,0),Vector2(0,13)]),Color("497784"))
		draw_circle(Vector2.ZERO,5,Color("a5e1dd"))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(-14,-33,28,5),Color("4d3854"))
	draw_rect(Rect2(-13,-32,26,3),Color("f1d9b4"))
	draw_rect(Rect2(-13,-32,26*health.current/maxf(1,health.maximum),3),Color("61bca9"))

func _draw_fallback_body() -> void:
	var colors: Dictionary = EnemyPalette.colors_for(enemy_id, profile)
	var walk := sin(lifetime * 9.0) * (3.0 if state == &"chase" else 0.0)
	for side in [-1.0, 1.0]:
		draw_polyline(PackedVector2Array([Vector2(side*8,0),Vector2(side*23,-8+walk),Vector2(side*29,6+walk)]), colors.trim, 4.0, true)
		draw_polyline(PackedVector2Array([Vector2(side*9,5),Vector2(side*21,13-walk),Vector2(side*23,21-walk)]), colors.shade, 4.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6),Vector2(13,12),Vector2(-12,12)]), colors.primary)
	draw_polyline(PackedVector2Array([Vector2(-16,-11),Vector2(-9,-21),Vector2(10,-19),Vector2(18,-6)]), colors.highlight, 2.0, true)
	draw_line(Vector2(-13,-4),Vector2(14,-4),colors.outline,6.0)
	draw_line(Vector2(-9,-4),Vector2(10,-4),colors.energy,3.0)
	draw_circle(Vector2(0,5),5.0,colors.trim)
	draw_circle(Vector2(0,5),2.0,colors.energy)
