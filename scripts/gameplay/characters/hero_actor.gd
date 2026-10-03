class_name HeroActor
extends CharacterBody2D

signal skill_input_feedback(slot: String, reason: String, details: Dictionary)

const SKILL_BUFFER_SECONDS: float = 0.24
const COOLDOWN_BUFFER_SECONDS: float = 0.16
const COMBO_QUEUE_LIMIT: int = 3
const HELD_MOVE_INTERVAL: float = 0.16
const HELD_MOVE_TARGET_DISTANCE: float = 48.0

const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Abilities = preload("res://scripts/gameplay/characters/hero_abilities.gd")
const Visual = preload("res://scripts/presentation/characters/hero_visual.gd")
const Status = preload("res://scripts/domain/combat/combat_status.gd")
const Loadout = preload("res://scripts/domain/combat/combat_loadout.gd")
const ClickNavigation = preload("res://scripts/gameplay/world/click_navigation.gd")
const Passives = preload("res://scripts/gameplay/characters/hero_passives.gd")
const HitChain = preload("res://scripts/domain/combat/hit_chain.gd")
const INPUT_SLOTS := ["q", "secondary", "f", "ultimate"]
const Bindings = preload("res://scripts/infrastructure/input/control_bindings.gd")
var room: Node2D
var abilities: RefCounted
var role_kit: RefCounted
var skill_loadout: Array[String] = []
var status: CombatStatus = Status.new()
var loadout: RefCounted
var click_navigation: RefCounted = ClickNavigation.new()
var passives: RefCounted = Passives.new()
var hit_chain: RefCounted = HitChain.new()
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
var _b06_knockback_distance_scale := 1.0
var stride: float = 0.0
var cooldowns: Dictionary = {}
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
var _attack_power: float = 0.0
var _attack_stats: Dictionary = {}
var _attack_class_state: Dictionary = {}
var _attack_interval: float = 0.5
var _primary_serial: int = 0
var _attack_event_id: String = ""
var _dash_distance: float = 0.0
var _dash_blocked: bool = false
var _equipment_class_roots: Dictionary = {}
var _class_clock: float = 0.0
var _automatic_attack_target: WeakRef
var _move_release_required: bool = false
var _held_move_delay: float = 0.0
var _held_move_target := Vector2(INF, INF)
var _pending_skill_slot: String = ""
var _enemy_status_origins: Dictionary = {}
# Runtime attribution is fingerprinted to the winning status snapshot. Old save
# formats remain unchanged; resumed effects with unknown sources stay unknown.
var _enemy_status_contexts: Dictionary = {}
var _enemy_slow_remaining: float = 0.0
var _enemy_slow_multiplier: float = 1.0
var _enemy_root_remaining: float = 0.0
var _enemy_root_protection_remaining: float = 0.0
var _hostile_hazards: Dictionary = {}
## Room-local identity state; target references never enter a save or equipment state.
var break_stacks: int = 0
var class_marks: Dictionary = {}

func _ready() -> void:
	add_to_group("player")
	if Game.run != null: preload("res://scripts/presentation/characters/hero_visual.gd").prewarm(Game.run.hero_id)
	_sync_status_ruleset()
	_initialize_skill_loadout()
	role_kit = Abilities.kit_script(hero_id()).new()
	role_kit.configure(self)
	abilities = Abilities.new()
	abilities.configure(self)
	clamp_cast_serial()
	loadout = Loadout.new()
	loadout.configure(self)
	click_navigation.configure(room)
	passives.configure(self)
	hit_chain.configure(self)
	var service: bool = room.get("expedition_context") != null and str(room.expedition_context.get("role","")) in ["entrance","supply"]
	loadout.event("room_enter", {"room_id":room.layout_id,"combat_room":not service})

func _ruleset_version() -> int:
	return Game.run.ruleset_version() if Game.run != null else Numbers.LEGACY

func _sync_status_ruleset() -> void:
	status.ruleset_version = _ruleset_version()

func hero_id() -> String:
	return Game.run.hero_id if Game.run != null else "CH01"

func hero_level() -> int:
	return Game.run.level if Game.run != null else 1

func _initialize_skill_loadout() -> void:
	skill_loadout.clear()
	var selected: Array = Game.get_loadout(hero_id()) if Game.has_method("get_loadout") else []
	if selected.size() != 4:
		selected = [hero_id() + "_SK01", hero_id() + "_SK02", hero_id() + "_SK03", hero_id() + "_SK04"]
	for index: int in 4:
		var skill_id: String = str(selected[index])
		if not skill_id.begins_with(hero_id() + "_SK") or skill_id in skill_loadout:
			skill_loadout = [hero_id() + "_SK01", hero_id() + "_SK02", hero_id() + "_SK03", hero_id() + "_SK04"]
			break
		skill_loadout.append(skill_id)
	for index: int in 12: cooldowns[hero_id() + "_SK%02d" % (index + 1)] = 0.0

func skill_id_for_slot(slot: String) -> String:
	var index: int = INPUT_SLOTS.find(slot)
	if index < 0: return slot if slot.begins_with(hero_id() + "_SK") else ""
	return skill_loadout[index] if skill_loadout.size() == 4 else canonical_skill_id(slot)

func canonical_skill_id(slot: String) -> String:
	var index: int = INPUT_SLOTS.find(slot)
	return hero_id() + "_SK%02d" % (index + 1) if index >= 0 else slot

func skill_cooldown(slot: String) -> float:
	return float(cooldowns.get(skill_id_for_slot(slot), 0.0))

func skill_progress(skill_id: String) -> Dictionary:
	if Game.has_method("get_skill_progress"): return Game.get_skill_progress(hero_id(), skill_id)
	return {"xp":0, "level":1, "branch":"", "learned":skill_id in [hero_id() + "_SK01", hero_id() + "_SK02", hero_id() + "_SK03", hero_id() + "_SK04"]}

func skill_is_learned(skill_id: String) -> bool:
	var progress: Dictionary = skill_progress(skill_id)
	return bool(progress.get("learned", progress.get("unlocked", not progress.is_empty())))

func clamp_cast_serial() -> void:
	if abilities == null or Game.run == null: return
	var state: Dictionary = Game.profile.get("skill_state", {}).get(hero_id(), {})
	if str(state.get("cast_run_id", "")) == str(Game.run.id):
		abilities.cast_serial = maxi(int(abilities.cast_serial), int(state.get("cast_cursor", 0)))

func class_state_snapshot() -> Dictionary:
	return role_kit.hud_state().duplicate(true) if role_kit != null else {}

func class_state_view() -> Dictionary:
	return class_state_snapshot()

func export_role_state() -> Dictionary:
	return role_kit.export_state().duplicate(true) if role_kit != null else {}

func restore_role_state(values: Dictionary) -> void:
	if role_kit != null: role_kit.restore_state(values)
	clamp_cast_serial()

func on_role_room_changed() -> void:
	if role_kit == null: return
	if role_kit.has_method("on_room_changed"): role_kit.on_room_changed()
	elif role_kit.has_method("on_room_change"): role_kit.on_room_change()

func in_real_combat() -> bool:
	if not is_instance_valid(room) or Game.run == null or Game.run.hp <= 0.0: return false
	var context: Variant = room.get("expedition_context")
	if context is Dictionary and str(context.get("role", "")) in ["entrance", "supply"]: return false
	var targets: Array = room.targets_in_radius(position, 2000.0) if room.has_method("targets_in_radius") else []
	for target: Node2D in targets:
		if is_instance_valid(target) and not target.is_queued_for_deletion() and target.has_method("is_alive") and target.is_alive() and str(target.get("actor_kind")) != "objective": return true
	return false

func notify_skill_release(cast: Dictionary) -> Dictionary:
	cast["combat"] = in_real_combat()
	return role_kit.on_skill_release(cast) if role_kit != null else {}

func record_skill_release(cast: Dictionary) -> void:
	if Game.has_method("record_skill_release"): Game.record_skill_release(str(cast.skill_id), int(cast.serial), float(cast.spec.base_cooldown), bool(cast.combat))
	if loadout != null:
		loadout.event("skill_released", {"event_id":"skill:" + str(cast.serial) + ":release", "root_event_id":"skill:" + str(cast.serial), "cast_id":int(cast.serial), "skill_id":str(cast.skill_id), "input_slot":str(cast.input_slot), "skill_slot":str(cast.spec.origin_slot), "target_position":cast.target, "burst_position":cast.target, "class_state":cast.class_state, "attacker_stats":cast.attacker_stats, "combat_active":bool(cast.combat), "X":float(cast.power), "H":float(cast.power), "paid_cost":float(cast.paid_cost), "damage_source":"skill", "proc_depth":0, "equipment_eligible":true})

func primary_power_snapshot() -> float:
	return _attack_power

func primary_stats_snapshot() -> Dictionary:
	return _attack_stats.duplicate(true)

func primary_class_snapshot() -> Dictionary:
	return _attack_class_state.duplicate(true)

func request_reload() -> bool:
	if hero_id() != "CH02" or role_kit == null or not room.controls_enabled() or Game.run == null or Game.run.hp <= 0.0: return false
	var result: Variant = role_kit.request_reload() if role_kit.has_method("request_reload") else false
	var accepted: bool = bool(result.get("ok", false)) if result is Dictionary else bool(result)
	var reason: String = str(result.get("reason", "accepted" if accepted else "reload_full")) if result is Dictionary else str(role_kit.get("last_reload_reason"))
	_emit_skill_feedback("reload", position, reason, {"key":Bindings.label_for("reload", Game.profile.get("settings", {}).get("controls", {}), Words.locale)})
	return accepted

func apply_equipment_class_command(command: Dictionary) -> bool:
	if role_kit == null or Game.run == null or Game.run.hp <= 0.0: return false
	var root: String = str(command.get("root_event_id", ""))
	var amount: float = float(command.get("amount", 0.0))
	var kind: String = str(command.get("kind", ""))
	if root.is_empty() or not is_finite(amount) or amount <= 0.0: return false
	var key := kind + ":" + str(command.get("source", "")) + ":" + root
	if _equipment_class_roots.has(key): return false
	_equipment_class_roots[key] = _class_clock
	while _equipment_class_roots.size() > 128: _equipment_class_roots.erase(_equipment_class_roots.keys()[0])
	match kind:
		"rage_gain", "rage_restore":
			if hero_id() != "CH01": return false
			restore_class_resource(amount)
			if role_kit.has_method("on_valid_combat_event"): role_kit.on_valid_combat_event()
		"ammo_restore":
			if hero_id() != "CH02" or not role_kit.has_method("restore_ammo"): return false
			role_kit.restore_ammo(int(amount))
		"starlight_gain", "starlight_restore":
			if hero_id() != "CH03" or not role_kit.has_method("restore_starlight"): return false
			role_kit.restore_starlight(int(amount))
		_: return false
	return true

func combat_hud_view() -> Dictionary:
	if Game.run == null: return {}
	var slots: Array[Dictionary] = []
	for slot: String in INPUT_SLOTS:
		var data: Dictionary = skill_definition(slot)
		var skill_id: String = str(data.get("skill_id", skill_id_for_slot(slot)))
		var casting: bool = abilities != null and abilities.busy() and str(abilities.active.skill_id) == skill_id
		var learned: bool = skill_is_learned(skill_id)
		var remaining: float = skill_cooldown(slot)
		var busy_now: bool = dash_remaining > 0.0 or _basic_chain_remaining > 0.0 or (attack_remaining > 0.0 and not attack_resolved) or (abilities != null and abilities.busy() and not abilities.recovery_chain_ready())
		slots.append({"slot":slot, "input_slot":slot, "skill_id":skill_id, "name":str(data.get("name", "")), "name_en":str(data.get("name_en", data.get("name", ""))), "description":str(data.get("description", "")), "description_en":str(data.get("description_en", data.get("description", ""))), "icon":str(data.get("icon_id", data.get("icon", ""))), "icon_id":str(data.get("icon_id", data.get("icon", ""))), "cost":float(data.get("cost", 0.0)), "cooldown":float(data.get("cooldown", 0.0)), "remaining":remaining, "key":Bindings.label_for("skill_" + slot, Game.profile.get("settings", {}).get("controls", {}), Words.locale), "casting":casting, "cast_progress":clampf(float(abilities.active.elapsed) / maxf(0.001, float(abilities.active.spec.duration)), 0.0, 1.0) if casting else 0.0, "queued":queued_action_position(slot) > 0, "queue_position":queued_action_position(slot), "unlocked":learned, "locked":not learned, "lock_reason":"尚未学会该技能" if not learned else "", "busy":busy_now, "ready":learned and remaining <= 0.0 and float(Game.run.resource) >= float(data.get("cost", 0.0)) and not busy_now, "branch":str(data.get("branch", "")), "rank":int(data.get("rank", 1))})
	return {"hero_id":hero_id(), "hp":float(Game.run.hp), "max_hp":float(Game.run.max_hp), "shield":float(Game.run.shield), "resource":float(Game.run.resource), "resource_max":float(Game.run.stats.get("resource_max", 0.0)), "slots":slots, "role_state":class_state_snapshot()}

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
		var tide: Variant = room.get("b06_mechanics") if is_instance_valid(room) else null
		if is_instance_valid(tide): value *= tide.movement_multiplier(self, false, float(modifiers.get("terrain_slow_reduction", 0.0)))
		return value * (float(role_kit.movement_multiplier()) if role_kit != null and role_kit.has_method("movement_multiplier") else 1.0)
	if key == "damage_bonus":
		var supply_bonus: float = float(Game.run.stats.get("temporary_buffs",{}).get("amplify",{}).get("damage_bonus",0.0))
		var cap: float = float(Numbers.value("caps").damage_bonus) if _ruleset_version() == Numbers.V2 else 0.60
		return minf(cap, value + supply_bonus + _room_prop_modifier(&"damage_bonus", 0.0))
	if key == "resource_regen":
		return value * _room_prop_modifier(&"resource_regen_multiplier", 1.0)
	if key == "attack_interval":
		var existing: float = float(Game.run.stats.get("attack_speed_bonus", 0.0))
		var cap: float = float(Numbers.value("caps").attack_speed) if _ruleset_version() == Numbers.V2 else 0.60
		return value * (1.0 + existing) / (1.0 + minf(cap, existing + float(modifiers.get("attack_speed_bonus", 0.0)))) / (float(role_kit.attack_speed_multiplier()) if role_kit != null and role_kit.has_method("attack_speed_multiplier") else 1.0)
	if _ruleset_version() == Numbers.V2 and key in ["burn_damage", "corrosion_damage_bonus"]:
		return clampf(value, 0.0, float(Numbers.value("caps")[key]))
	return value

func _room_prop_modifier(method: StringName, fallback: float) -> float:
	if not is_instance_valid(room):
		return fallback
	var props: Variant = room.get("enemy_props")
	if not is_instance_valid(props) or not props.has_method(method):
		return fallback
	var value: float = float(props.call(method))
	return value if is_finite(value) and value >= 0.0 else fallback

func attack_power() -> Variant:
	# This is AD, not basic H: skill/relic sources must not inherit basic AP.
	var fallback: float = 27.0 if hero_id() == "CH01" else 24.0 if hero_id() == "CH02" else 18.0
	return Numbers.amount(stat("attack", float(Numbers.scale(fallback, _ruleset_version()))), _ruleset_version())

func _power_snapshot() -> Dictionary:
	var result: Dictionary={"ruleset_version":_ruleset_version(), "attack":attack_power(), "ability_power":stat("ability_power", 0.0)}
	if Game.run!=null and int(Game.run.stats.get("mage_balance_candidate",0))==1:
		result["mage_balance_candidate"]=1
		result["mage_spell_power_multiplier"]=Game.run.stats.mage_spell_power_multiplier
	if Game.run!=null and int(Game.run.stats.get("warrior_balance_candidate",0))==1:
		result["warrior_balance_candidate"]=1
		result["warrior_skill_power_multiplier"]=Game.run.stats.warrior_skill_power_multiplier
	return result

func basic_power() -> Variant:
	return Abilities.preview_powers(hero_id(), _power_snapshot()).basic_H

func relic_power() -> Variant:
	return Numbers.amount(stat("ability_power", float(Numbers.scale(28.0, _ruleset_version()))), _ruleset_version()) if hero_id() == "CH03" else attack_power()

func basic_attack_variant() -> int:
	var feedback: Node = get_node_or_null("HeroFeedback")
	return int(feedback.basic_events) % 3 if is_instance_valid(feedback) else 0

func skill_power() -> Variant:
	return Abilities.preview_powers(hero_id(), _power_snapshot()).skill_H

func heal(amount: float, source: String = "self") -> Variant:
	_sync_status_ruleset()
	var restored: Variant = Game.heal_player(amount * (1.0 + float(loadout.modifiers().get("received_healing_bonus", 0.0)) if loadout != null else 1.0), status.healing_multiplier())
	if restored > 0.0 and is_instance_valid(room) and room.has_method("add_damage_text"):
		room.add_damage_text(position + Vector2(0,-72), restored, &"heal", {"feedback_kind":"heal"})
	if restored > 0.0 and source == "external" and loadout != null:
		loadout.event("external_heal", {"actual_healing":restored})
	return restored

func _physics_process(delta: float) -> void:
	if Game.run == null or Game.run.hp <= 0.0 or get_tree().paused:
		clear_buffered_skill()
		clear_movement_target()
		return
	_sync_status_ruleset()
	_tick_class_state(delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	rage_hurt_cooldown = maxf(0.0, rage_hurt_cooldown - delta)
	attack_buffer = maxf(0.0, attack_buffer - delta)
	_basic_chain_remaining = maxf(0.0, _basic_chain_remaining - delta)
	_tick_b05_control(delta)
	var slow_was_active := _enemy_slow_remaining > 0.0
	_enemy_slow_remaining = maxf(0.0, _enemy_slow_remaining - delta)
	if _enemy_slow_remaining <= 0.0:
		_enemy_slow_multiplier = 1.0
		if slow_was_active and loadout != null:
			loadout.event("ordinary_slow_ended", {"actually_slowed":true})
	for key: String in cooldowns:
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - delta)
	# Synchronize external shield damage before expiries recompute the maximum pool.
	status.absorb(maxf(0.0, status.shield() - Game.run.shield))
	var was_chilled: bool = status.has("chill")
	var b06_guards_before: Dictionary = status.guards.duplicate(true)
	var status_damage: Array[Dictionary] = status.tick(delta)
	_b06_guard_ends(b06_guards_before, "expired")
	Game.run.shield = status.shield()
	for tick: Dictionary in status_damage:
		var source_origin: Vector2 = _enemy_status_origins.get(str(tick.kind), position)
		var tick_context: Dictionary = _status_source_context(str(tick.kind), tick)
		tick_context.merge({"dot":true,"status":str(tick.kind),"damage_type":str(tick.get("damage_type", "magic" if str(tick.kind) == "burn" else "physical"))}, true)
		receive_damage(float(tick.damage), source_origin, tick_context)
		if Game.run == null or Game.run.hp <= 0.0:
			return
	for identifier: String in _enemy_status_origins.keys():
		if not status.has(identifier):
			_enemy_status_origins.erase(identifier)
			_enemy_status_contexts.erase(identifier)
	if was_chilled != status.has("chill") and loadout != null:
		loadout.event("state_changed", {"enemy_status":"chill"})
	_tick_resources(delta)
	var motion := Vector2.ZERO
	var pointer_enabled: bool = room.pointer_controls_enabled()
	if not attack_input_held():
		_attack_release_required = false
	if not pointer_enabled:
		attack_buffer = 0.0
		_attack_release_required = attack_input_held()
		_drop_pointer_combo_inputs()
		clear_movement_target()
	if not room.controls_enabled():
		clear_buffered_skill()
		clear_movement_target()
	_update_held_movement(delta, pointer_enabled)
	if room.controls_enabled():
		motion = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if motion.length_squared() > 0.0:
			clear_movement_target()
		elif pointer_enabled:
			motion = click_navigation.motion(position, stat("move_speed", 220.0) * abilities.movement_scale() * delta, Balance.PLAYER_RADIUS, delta)
		var aim := get_global_mouse_position() - global_position
		if aim.length_squared() > 16.0:
			aim_direction = aim.normalized()
		if Input.is_action_just_pressed("dash"):
			start_dash(motion.normalized() if motion.length_squared() > 0.0 else aim_direction)
		if hero_id() == "CH02" and InputMap.has_action("reload") and Input.is_action_just_pressed("reload") and pointer_enabled:
			request_reload()
		for slot: String in INPUT_SLOTS:
			if not pointer_enabled:
				continue
			if InputMap.has_action("skill_" + slot) and Input.is_action_just_pressed("skill_" + slot):
				request_skill(slot, get_global_mouse_position())
		if pointer_enabled and not _attack_release_required and Input.is_action_just_pressed("attack"):
			request_attack(aim_direction, _pointed_attack_target(get_global_mouse_position()))
		elif combo_queue.is_empty() and pointer_enabled and not _attack_release_required and attack_input_held():
			var target: Node2D = _pointed_attack_target(get_global_mouse_position())
			var direction: Vector2 = position.direction_to(target.position) if is_instance_valid(target) else aim_direction
			if not fire(direction):
				attack_buffer = 0.10
		elif pointer_enabled:
			_tick_auto_attack()
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
	if dash_remaining > 0.0:
		_tick_dash(delta)
	else:
		if _enemy_root_remaining > 0.0: motion = Vector2.ZERO
		velocity = motion * stat("move_speed", 220.0) * abilities.movement_scale() + knockback * _b06_knockback_distance_scale
		if is_instance_valid(room.b09_mechanics): velocity = room.b09_mechanics.movement_velocity(self,motion,velocity,delta)
		position = room.move_actor(position, velocity * delta, Balance.PLAYER_RADIUS)
	var was_knocked := knockback.length_squared() > 0.0
	knockback = knockback.move_toward(Vector2.ZERO, Balance.PLAYER_KNOCKBACK_DECAY * delta)
	if was_knocked and knockback.is_zero_approx() and loadout != null:
		loadout.event("ordinary_forced_movement_ended", {"actual_enemy_forced_movement":true})
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

func attack_input_held() -> bool:
	if not InputMap.has_action("attack"): return false
	# Releasing one alias must not reopen the gate while another stays held.
	for event: InputEvent in InputMap.action_get_events("attack"):
		if event is InputEventMouseButton and Input.is_mouse_button_pressed(event.button_index): return true
		if event is InputEventKey:
			if event.physical_keycode != 0 and Input.is_physical_key_pressed(event.physical_keycode): return true
			if event.keycode != 0 and Input.is_key_pressed(event.keycode): return true
	return Input.is_action_pressed("attack")

func _update_held_movement(delta: float, pointer_enabled: bool) -> void:
	_held_move_delay = maxf(0.0, _held_move_delay - delta)
	var held: bool = InputMap.has_action("click_move") and Input.is_action_pressed("click_move")
	if not held:
		_move_release_required = false
		_held_move_target = Vector2(INF, INF)
		return
	if not pointer_enabled or not room.controls_enabled():
		_move_release_required = true
		clear_movement_target()
		return
	if _move_release_required or dash_remaining > 0.0 or (abilities.busy() and float(abilities.active.spec.get("travel", 0.0)) > 0.0):
		return
	if not Input.get_vector("move_left", "move_right", "move_up", "move_down").is_zero_approx():
		return
	var target: Vector2 = get_global_mouse_position()
	var fresh: bool = Input.is_action_just_pressed("click_move")
	var target_changed: bool = not _held_move_target.is_finite() or _held_move_target.distance_squared_to(target) >= HELD_MOVE_TARGET_DISTANCE * HELD_MOVE_TARGET_DISTANCE
	if fresh or (_held_move_delay <= 0.0 and target_changed):
		request_move(target, fresh)
		# Even invalid held destinations are remembered until the pointer moves,
		# so a stationary cursor outside the map cannot retry every physics tick.
		_held_move_target = target
		_held_move_delay = HELD_MOVE_INTERVAL

func _pointed_attack_target(at: Vector2) -> Node2D:
	var best: Node2D = null
	var nearest: float = INF
	for target: Node2D in room.targets_in_radius(position, auto_attack_range()):
		if target.is_queued_for_deletion() or str(target.get("actor_kind")) == "objective": continue
		var height: float = clampf(float(target.get("navigation_radius")) * 3.8, 66.0, 88.0)
		var body := Rect2(target.position + Vector2(-30,-height), Vector2(60,height + 18))
		if not body.has_point(at): continue
		var distance: float = at.distance_squared_to(target.position + Vector2(0,-height * 0.4))
		if distance < nearest:
			nearest = distance
			best = target
	return best

func request_move(target: Vector2, show_feedback: bool = true) -> bool:
	if not is_instance_valid(room) or not room.controls_enabled() or not room.pointer_controls_enabled() or Game.run == null or Game.run.hp <= 0.0 or dash_remaining > 0.0:
		clear_movement_target()
		return false
	var accepted: bool = click_navigation.request(position, target, Balance.PLAYER_RADIUS)
	if accepted and show_feedback:
		room.add_ring(target, Color("65bcae"), 18.0, 0.32)
	return accepted

func clear_movement_target() -> void:
	click_navigation.cancel()
	_held_move_target = Vector2(INF, INF)
	_held_move_delay = 0.0
	velocity = Vector2.ZERO

func auto_attack_range() -> float:
	return 100.0 if hero_id() == "CH01" else clampf(stat("range", 650.0 if hero_id() == "CH02" else 480.0) - 20.0, 100.0, 780.0)

func auto_attack_target() -> Node2D:
	if not is_instance_valid(room): return null
	for target: Node2D in room.targets_in_radius(position, auto_attack_range()):
		if not target.is_queued_for_deletion() and str(target.get("actor_kind")) != "objective":
			return target
	return null

func _tick_auto_attack() -> bool:
	if not bool(Game.profile.get("settings", {}).get("auto_attack", false)) or not room.controls_enabled() or not room.pointer_controls_enabled() or not combo_queue.is_empty() or shot_cooldown > 0.0 or dash_remaining > 0.0 or _attack_release_required:
		return false
	var target: Node2D = auto_attack_target()
	if not is_instance_valid(target): return false
	var direction: Vector2 = position.direction_to(target.position)
	if direction.is_zero_approx() or not fire(direction, target): return false
	aim_direction = direction
	return true

func fire(direction: Vector2, automatic_target: Node2D = null) -> bool:
	if Game.run == null or Game.run.hp <= 0.0 or shot_cooldown > 0.0 or dash_remaining > 0.0 or not direction.is_finite() or direction.is_zero_approx() or abilities == null or (role_kit != null and not role_kit.can_primary()):
		return false
	if abilities.busy():
		if not abilities.recovery_chain_ready():
			return false
		abilities.finish_recovery()
	_attack_direction = direction.normalized()
	_automatic_attack_target = weakref(automatic_target) if is_instance_valid(automatic_target) else null
	_attack_critical = false # Resolved once against the primary target's pre-hit snapshot.
	_attack_interval = stat("attack_interval", 0.5)
	shot_cooldown = _attack_interval
	_attack_power = float(basic_power()) * (float(role_kit.primary_damage_multiplier()) if role_kit != null else 1.0)
	_attack_stats = Game.run.stats.duplicate(true)
	_attack_class_state = class_state_snapshot()
	_primary_serial += 1
	_attack_event_id = "basic:" + str(get_instance_id()) + ":" + str(_primary_serial)
	if hero_id() == "CH01":
		attack_remaining = shot_cooldown
		attack_resolved = false
		room.record_attack()
		visual_event("attack_windup", 0.12, _attack_direction)
	else:
		if not room.fire_from_player(_attack_direction, _attack_critical):
			shot_cooldown = 0.0
			return false
		if role_kit != null: role_kit.on_primary_created()
		muzzle_flash = 0.07
		visual_event("attack_strike", 0.12, _attack_direction)
	_play_combat_audio(&"attack", [hero_id()])
	return true

func _tick_attack(delta: float) -> void:
	if attack_remaining <= 0.0:
		return
	var old: float = attack_remaining
	attack_remaining = maxf(0.0, attack_remaining - delta)
	var hit_threshold: float = maxf(0.0, _attack_interval - 0.12)
	if not attack_resolved and old >= hit_threshold and attack_remaining <= hit_threshold:
		attack_resolved = true
		_basic_chain_remaining = 0.045
		if _automatic_attack_target != null:
			var target: Variant = _automatic_attack_target.get_ref()
			if not is_instance_valid(target) or not target.is_alive() or target.is_queued_for_deletion() or position.distance_to(target.position) > 105.0 or not room.has_line_of_sight(position, target.position):
				_automatic_attack_target = null
				return
		# The start pose, release arc and real cone share the committed direction.
		# Even auto attacks may whiff when a target moves around the windup;
		# tracking validates the recipient, it never turns a committed swing.
		var victims: Array = room.strike_area(position, 105.0, _attack_power * (1.5 if _attack_critical else 1.0), &"primary", "", 12.0, _attack_direction, 100.0, true, {"root_event_id":_attack_event_id, "attack_id":_attack_event_id, "power":_attack_power, "attacker_stats":_attack_stats, "class_state":_attack_class_state, "original_basic":true, "equipment_eligible":true, "proc_depth":0}, true)
		visual_event("attack_strike", 0.08, _attack_direction)
		if not victims.is_empty():
			if _ruleset_version() != Numbers.V2: on_primary_hit(victims[0])
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
		_automatic_attack_target = null
		# Commit a fresh click after an action with authored travel. A stale path
		# must never pull a completed dash/jump back toward its starting corner.
		if float(abilities.active.spec.get("travel", 0.0)) > 0.0:
			clear_movement_target()
		# Read the committed spec: consuming full Momentum changes the next live
		# preview back to 30 Rage and must not spend a paid-skill discount here.
		# Payment and the new skill cooldown are already committed. A stable cast
		# root counts once, independently of later hits, projectiles or deployments.
		var cast_event := "cast_commit:" + str(abilities.active.serial)
		loadout.event("skill_cast", {"event_id":cast_event, "root_event_id":cast_event,
			"slot":str(abilities.active.spec.origin_slot), "b09_hit_root_id":"skill:" + str(abilities.active.serial), "skill_id":str(abilities.active.skill_id), "input_slot":slot, "skill_slot":str(abilities.active.spec.origin_slot), "base_cost":float(abilities.active.spec.cost), "paid_cost":float(abilities.active.paid_cost),
			"cast_success":true, "damage_source":"skill", "proc_depth":0, "equipment_eligible":true, "original_basic":false})
		if room.has_method("record_player_sound"):
			room.record_player_sound()
		_play_combat_audio(&"prepare", [hero_id(), str(abilities.active.spec.get("audio_slot", abilities.active.spec.origin_slot))])
	_pending_skill_slot = ""
	_emit_skill_feedback(slot, target, "accepted" if success else last_cast_error, abilities.last_failure_details)
	return success

func request_skill(slot: String, target: Vector2) -> bool:
	if not is_instance_valid(room) or not room.controls_enabled() or not room.pointer_controls_enabled():
		return _reject_skill(slot, target, "unavailable", {"cause":"input_blocked"})
	if abilities == null or Game.run == null or Game.run.hp <= 0.0:
		return _reject_skill(slot, target, "unavailable")
	if dash_remaining > 0.0:
		return _reject_skill(slot, target, "dashing")
	_pending_skill_slot = slot
	var cooldown_wait: float = skill_cooldown(slot)
	var prequeue: bool = _ruleset_version() == Numbers.V2 and cooldown_wait > 0.0 and cooldown_wait <= COOLDOWN_BUFFER_SECONDS
	var valid: bool = abilities.can_cast(slot, target, true, prequeue)
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
	return _append_combo_input({"slot":slot, "skill_id":skill_id_for_slot(slot), "target":target}, wait)

func request_attack(direction: Vector2, selected_target: Node2D = null) -> bool:
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
	if role_kit != null and not role_kit.can_primary():
		var class_view: Dictionary = class_state_snapshot()
		return _reject_skill("attack", position, "reloading" if bool(class_view.get("reloading", false)) else "ammo_empty")
	if is_instance_valid(selected_target):
		direction = position.direction_to(selected_target.position)
	var wait: float = _combo_wait_seconds("attack")
	if combo_queue.is_empty() and wait <= 0.00001:
		if not fire(direction):
			return _reject_skill("attack", position, "busy")
		_emit_skill_feedback("attack", position, "accepted")
		return true
	return _append_combo_input({"slot":"attack", "direction":direction.normalized(), "target":position,
		"target_id":selected_target.get_instance_id() if is_instance_valid(selected_target) else 0}, wait)

func _combo_wait_seconds(slot: String) -> float:
	return maxf(_action_chain_wait_seconds(), shot_cooldown if slot == "attack" else skill_cooldown(slot))

func _action_chain_wait_seconds() -> float:
	var wait: float = _basic_chain_remaining
	if attack_remaining > 0.0 and not attack_resolved:
		var hit_threshold: float = maxf(0.0, _attack_interval - 0.12)
		wait = maxf(wait, maxf(0.0, attack_remaining - hit_threshold) + 0.045)
	if abilities != null and abilities.busy():
		wait = maxf(wait, abilities.recovery_chain_wait())
	return wait

func _append_combo_input(request: Dictionary, wait: float) -> bool:
	var slot: String = str(request.slot)
	var target: Vector2 = request.target
	if combo_queue.size() >= COMBO_QUEUE_LIMIT:
		return _reject_skill(slot, target, "busy", {"cause":"queue_full"})
	if combo_queue.is_empty() and wait > SKILL_BUFFER_SECONDS + 0.00001:
		return _reject_skill(slot, target, "busy", {"cause":"early_chain", "chain_in":wait})
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
	if attack_input_held():
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
		# Only the predecessor's finite action extends this one-time budget;
		# a cooldown added after admission cannot buy the pending input more time.
		combo_queue[0].remaining = SKILL_BUFFER_SECONDS + _action_chain_wait_seconds()
	_sync_buffered_skill()

func _drop_pointer_combo_inputs() -> void:
	clear_buffered_skill()

func _tick_skill_buffer(delta: float) -> void:
	if combo_queue.is_empty():
		return
	# Only the head owns a deadline. Later admitted inputs get one finite
	# predecessor budget when promoted; their window never refreshes per frame.
	combo_queue[0].remaining = maxf(0.0, float(combo_queue[0].remaining) - maxf(0.0, delta))
	if float(combo_queue[0].remaining) <= 0.0:
		var expired: Dictionary = combo_queue.pop_front()
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
	if not room.controls_enabled() or not room.pointer_controls_enabled():
		_prime_combo_head()
		return
	if slot == "attack":
		var target_id: int = int(request.get("target_id", 0))
		var target: Variant = instance_from_id(target_id) if target_id > 0 else null
		if not is_instance_valid(target) or not target is Node2D or not target.is_alive() or target.is_queued_for_deletion() or position.distance_to(target.position) > auto_attack_range() or not room.has_line_of_sight(position, target.position):
			target = null
		var direction: Vector2 = position.direction_to(target.position) if is_instance_valid(target) else request.direction
		if fire(direction):
			_emit_skill_feedback(slot, request.target, "accepted")
		else:
			_reject_skill(slot, request.target, "busy")
	else:
		if str(request.get("skill_id", skill_id_for_slot(slot))) != skill_id_for_slot(slot):
			_reject_skill(slot, request.target, "invalid_skill")
			_prime_combo_head()
			return
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
		"remaining":skill_cooldown(slot), "unlock":int(definition.get("unlock", 99)),
		"level":hero_level(), "range":float(definition.get("range", 0.0))}
	details["skill_id"] = str(definition.get("skill_id", ""))
	details["input_slot"] = slot
	details["key"] = Bindings.label_for("reload" if slot == "reload" else "skill_" + slot if slot in INPUT_SLOTS else slot, Game.profile.get("settings", {}).get("controls", {}), Words.locale)
	details["lock_reason"] = "尚未学会该技能" if reason == "locked" else ""
	details.merge(extra.duplicate(true), true)
	skill_input_feedback.emit(slot, reason, details)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		clear_buffered_skill()
		clear_movement_target()
		attack_buffer = 0.0
		# Also cover an attack first pressed while physics is paused, after this
		# notification has already run. Resume must observe a released button.
		_attack_release_required = true
		_move_release_required = true

func _exit_tree() -> void:
	clear_buffered_skill()
	clear_movement_target()
	passives.reset()

func _play_combat_audio(event: StringName, arguments: Array = []) -> void:
	if not is_instance_valid(room):
		return
	var audio: Variant = room.get("combat_audio")
	if is_instance_valid(audio) and audio.has_method(event):
		audio.callv(event, arguments)

func _tick_resources(delta: float) -> void:
	if Game.run == null or not is_finite(delta) or delta <= 0.0:
		return
	var regen_step: float = maxf(0.0, delta - resource_delay)
	var rage_decay_step: float = maxf(0.0, delta - combat_time)
	resource_delay = maxf(0.0, resource_delay - delta)
	combat_time = maxf(0.0, combat_time - delta)
	if hero_id() == "CH01":
		if combat_time <= 0.0:
			var decay: float = float(Numbers.scale(10.0, _ruleset_version())) * rage_decay_step
			if _ruleset_version() == Numbers.V2:
				var accumulated: Dictionary = Numbers.accumulate(decay, Game.run.resource_decay_remainder)
				decay = float(accumulated.whole)
				Game.run.resource_decay_remainder = float(accumulated.remainder)
			Game.run.resource = maxf(0.0, Game.run.resource - decay)
			if Game.run.resource <= 0.0:
				Game.run.resource_decay_remainder = 0.0
	elif regen_step > 0.0:
		var fallback: float = float(Numbers.scale(18.0 if hero_id() == "CH02" else 5.0, _ruleset_version()))
		# Round the complete effective per-second rate, then integrate time.
		# Per-frame rounding would make the same rate depend on rendering FPS.
		var rate: float = stat("resource_regen", fallback)
		if _ruleset_version() == Numbers.V2:
			rate = float(Numbers.integer(rate * resource_gain_multiplier()))
		var regenerated: float = rate * regen_step
		if _ruleset_version() == Numbers.V2:
			var accumulated: Dictionary = Numbers.accumulate(regenerated, Game.run.resource_regen_remainder)
			regenerated = float(accumulated.whole)
			Game.run.resource_regen_remainder = float(accumulated.remainder)
		Game.restore_resource(regenerated)
		# Time at a full bar is not banked for the next cast.
		if Game.run.resource >= float(Game.run.stats.get("resource_max", 0.0)):
			Game.run.resource_regen_remainder = 0.0

func resource_gain_multiplier() -> float:
	if _ruleset_version() != Numbers.V2:
		return 1.0
	var modifiers: Dictionary = loadout.modifiers() if loadout != null else {}
	return 1.0 + clampf(stat("resource_gain_bonus", 0.0) + float(modifiers.get("resource_gain_bonus", 0.0)), 0.0, float(Numbers.value("caps").resource_gain_bonus))

## The amount is already in this run's units. Supply/beacon percentage fills
## intentionally call Game.restore_resource directly and bypass this bonus.
func restore_class_resource(amount: float) -> Variant:
	return Game.restore_resource(amount * resource_gain_multiplier())

func resource_cost(amount: float) -> Variant:
	return Game.resource_cost(loadout.resource_cost(amount, _pending_skill_slot) if loadout != null else amount)

func skill_definition(slot: String) -> Dictionary:
	var definition: Dictionary = abilities.spec(slot).duplicate(true)
	if not definition.is_empty():
		definition["cost"] = Game.resource_cost(loadout.resource_cost(float(definition.cost), slot) if loadout != null else float(definition.cost))
	return definition

func cancel_actions() -> void:
	abilities.cancel()
	clear_buffered_skill()
	clear_movement_target()
	_automatic_attack_target = null
	attack_remaining = 0.0
	attack_resolved = true
	_basic_chain_remaining = 0.0
	attack_buffer = 0.0

func start_dash(direction: Vector2) -> bool:
	if is_instance_valid(room) and room.has_method("objective_blocks_dash") and room.objective_blocks_dash():
		return false
	if _enemy_root_remaining > 0.0 or dash_cooldown > 0.0 or direction.is_zero_approx() or Game.run == null:
		return false
	if room.move_actor(position, direction.normalized() * 8.0, Balance.PLAYER_RADIUS).distance_to(position) < 1.0:
		return false
	cancel_actions()
	dash_direction = direction.normalized()
	dash_elapsed = 0.0
	_dash_distance = 0.0
	_dash_blocked = false
	dash_remaining = 0.22 if hero_id() == "CH02" else 0.18
	dash_cooldown = 2.2 if hero_id() == "CH01" else 2.0 if hero_id() == "CH02" else 2.6
	room.telemetry["dashes"] += 1
	visual_event("dash", dash_remaining)
	room.add_ring(position, Color("67c7d5"), 28.0, 0.2)
	loadout.event("dash")
	return true

func _tick_dash(delta: float) -> void:
	var before: Vector2 = position
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
	var travelled: float = before.distance_to(position)
	_dash_distance += travelled
	if not velocity.is_zero_approx() and travelled + 0.5 < velocity.length() * step: _dash_blocked = true
	if hero_id() == "CH03" and previous < 0.08 and dash_elapsed >= 0.08 and travelled < 1.0: _dash_blocked = true
	if dash_remaining <= 0.0:
		loadout.event("dash_end")
		if role_kit != null: role_kit.on_dash_finished(not _dash_blocked and _dash_distance > 1.0 and Game.run != null and Game.run.hp > 0.0)

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
	if identifier not in ["burn", "shock", "chill", "corrosion", "slow", "root", "bleed", "grievous", "damage_reduction", "invulnerable"]:
		return false
	var duration: float = float(effect.get("duration", 4.0 if identifier == "corrosion" else 3.0))
	if not is_finite(duration) or duration <= 0.0:
		return false
	if identifier in ["slow", "root"] and loadout != null and loadout.effects != null:
		duration = loadout.effects.b09_slow_duration(duration) if identifier=="slow" else loadout.effects.b05_control_duration(duration)
	if identifier == "root":
		if _enemy_root_remaining > 0.0 or _enemy_root_protection_remaining > 0.0: return false
		_enemy_root_remaining = minf(duration, 300.0)
		dash_remaining = 0.0
		clear_movement_target()
		queue_redraw()
		return true
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
	_sync_status_ruleset()
	var accepted: bool = status.apply(identifier,power,duration)
	if accepted:
		var supplied_origin: Variant = effect.get("origin", position)
		_enemy_status_origins[identifier] = supplied_origin if supplied_origin is Vector2 else position
		var winner: Dictionary = status.states[identifier]
		_enemy_status_contexts[identifier] = {"applied_at":float(winner.applied_at),"power":float(winner.power),"H":float(winner.H),"source_id":str(effect.get("source_id", "")).left(96),"source_name":str(effect.get("source_name", "")).left(96),"attack_id":str(effect.get("attack_id", "")).left(96)}
	# A state refresh recomputes equipment resistances, but is not a player attack,
	# skill cast or successful offensive status-application event.
	if loadout != null:
		loadout.event("state_changed", {"enemy_status":identifier})
	queue_redraw()
	return true

func _status_source_context(identifier: String, snapshot: Dictionary) -> Dictionary:
	var source: Dictionary = _enemy_status_contexts.get(identifier, {})
	if source.is_empty(): return {}
	for key: String in ["applied_at", "power", "H"]:
		if not is_equal_approx(float(source[key]), float(snapshot.get(key, -1.0))): return {}
	return {"source_id":str(source.source_id),"source_name":str(source.source_name),"attack_id":str(source.attack_id)}

func _damage_key_states() -> Array[String]:
	var result: Array[String] = []
	for id: String in status.states:
		if status.has(id): result.append(id)
	if _enemy_slow_remaining > 0.0: result.append("slow")
	if _enemy_root_remaining > 0.0: result.append("root")
	if dash_remaining > 0.0: result.append("dash")
	return result

func receive_damage(amount: float, origin: Vector2, context: Dictionary = {}) -> bool:
	var is_dot: bool = bool(context.get("dot", false))
	if Game.run == null or Game.run.hp <= 0.0 or not is_finite(amount) or amount <= 0.0:
		return false
	_sync_status_ruleset()
	var damage_context: Dictionary = context.duplicate()
	damage_context["key_states"] = _damage_key_states()
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
	var shock_source: Dictionary = _status_source_context("shock", status.states.get("shock", {}))
	var numerical: bool = _ruleset_version() == Numbers.V2
	if not is_dot:
		if not numerical:
			invulnerable = Balance.HURT_INVULNERABILITY
			knockback = (position - origin).normalized() * Balance.PLAYER_KNOCKBACK
		if status.has("corrosion"):
			incoming *= 1.08
		if not numerical: shock_damage = status.consume_shock()
	if not numerical:
		hurt_flash = 0.08 if is_dot else 0.16
		room.telemetry["player_hits"] += 1
		room.add_ring(position, Color("e46b69"), 24.0 if is_dot else 38.0, 0.20 if is_dot else 0.28)
	var previous_shield: float = Game.run.shield
	var e_guard: Dictionary = status.guards.get("hero_f", {})
	var e_shield_active := float(e_guard.get("remaining", 0.0)) > 0.0 and float(e_guard.get("amount", 0.0)) >= previous_shield and previous_shield > 0.0
	var previous_hp: float = Game.run.hp
	loadout.refresh_modifiers()
	var modifiers: Dictionary = loadout.modifiers()
	if not is_dot: _b06_knockback_distance_scale = 1.0 - clampf(float(modifiers.get("received_displacement_reduction", 0.0)), 0.0, 0.5)
	if not is_dot and not bool(context.get("fixed_mechanism_cost", false)):
		damage_context["damage_reduction"] = float(damage_context.damage_reduction) + maxf(0.0, float(modifiers.get("b10_direct_damage_reduction", 0.0)))
		if bool(context.get("ranged_direct_damage", false)):
			damage_context["damage_reduction"] += maxf(0.0, float(modifiers.get("b10_ranged_damage_reduction", 0.0)))
	var damaged_run: RunSession = Game.run
	damage_context["damage_reduction"] = minf(0.65, float(damage_context.damage_reduction) + maxf(0.0, float(modifiers.get("damage_reduction_bonus", 0.0))))
	if not is_dot and not bool(damage_context.get("b09_environment",false)) and not bool(damage_context.get("self_damage",false)):
		damage_context["damage_reduction"] = minf(0.65,float(damage_context.damage_reduction)+float(modifiers.get("b09_direct_reduction",0.0)))
	Game.damage_player(incoming, damage_context)
	if numerical:
		if damaged_run.hp >= previous_hp and damaged_run.shield >= previous_shield:
			return false
		if not is_dot:
			shock_damage = status.consume_shock()
			invulnerable = Balance.HURT_INVULNERABILITY
			knockback = (position - origin).normalized() * Balance.PLAYER_KNOCKBACK
		hurt_flash = 0.08 if is_dot else 0.16
		room.telemetry["player_hits"] += 1
		room.add_ring(position, Color("e46b69"), 24.0 if is_dot else 38.0, 0.20 if is_dot else 0.28)
	var consumed_total: float = maxf(0.0, previous_hp - damaged_run.hp) + maxf(0.0, previous_shield - damaged_run.shield)
	if consumed_total > 0.0 and is_instance_valid(room):
		var tide: Variant = room.get("b06_mechanics")
		if is_instance_valid(tide): tide.notify_actor_hit("player",consumed_total)
		var mechanisms: Variant = room.get("b05_mechanics")
		if mechanisms is Object and mechanisms.has_method("notify_actor_hit"):
			mechanisms.call("notify_actor_hit", "player", consumed_total)
	_show_received_numbers(damaged_run, previous_hp, previous_shield, damage_context)
	# Shock is a magic packet within this same received-hit event. A lethal
	# first packet may close the run (or restore a demo's backup), so identity
	# must still match before the second packet can reach Core.
	if shock_damage > 0.0 and Game.run == damaged_run and damaged_run.hp > 0.0:
		var shock_context: Dictionary = damage_context.duplicate()
		shock_context["damage_type"] = "magic"
		shock_context["damage_kind"] = "electric"
		shock_context["damage_event"] = "shock"
		shock_context["status"] = "shock"
		# The triggering hit and the charged status may have different casters.
		for key: String in ["source_id", "source_name", "attack_id"]:
			shock_context[key] = str(shock_source.get(key, ""))
		var before_shock_hp: float = damaged_run.hp
		var before_shock_shield: float = damaged_run.shield
		Game.damage_player(shock_damage, shock_context)
		_show_received_numbers(damaged_run, before_shock_hp, before_shock_shield, shock_context)
	if not is_dot and (damaged_run.hp < previous_hp or damaged_run.shield < previous_shield):
		_play_combat_audio(&"hurt")
	var b06_guards_before: Dictionary = status.guards.duplicate(true)
	status.absorb(maxf(0.0, status.shield() - damaged_run.shield))
	_b06_guard_ends(b06_guards_before, "absorbed")
	if Game.run != damaged_run or damaged_run.hp <= 0.0:
		cancel_actions()
		passives.reset()
		if role_kit != null and role_kit.has_method("on_death"): role_kit.on_death()
		return true
	Game.run.shield = status.shield()
	if not is_dot:
		knockback *= float(modifiers.get("received_knockback_scale", 1.0))
	loadout.event("damaged", {"hp_damage":previous_hp - Game.run.hp,"shield_absorbed":previous_shield - Game.run.shield,"shield_broken":previous_shield > 0.0 and Game.run.shield <= 0.0,"enemy_damage":not bool(damage_context.get("self_damage",false)),"self_damage":bool(damage_context.get("self_damage",false)),"dot":is_dot,"e_shield_absorbed":maxf(0.0, previous_shield - Game.run.shield) if e_shield_active else 0.0})
	combat_time = 5.0
	if consumed_total > 0.0 and role_kit != null and role_kit.has_method("on_hurt"):
		role_kit.on_hurt(consumed_total, damage_context)
	return true

func _show_received_numbers(damaged_run: RunSession, before_hp: float, before_shield: float, context: Dictionary) -> void:
	if not is_instance_valid(room) or not room.has_method("add_damage_text"): return
	var hp_loss: float = maxf(0.0, before_hp - damaged_run.hp)
	var shield_loss: float = maxf(0.0, before_shield - damaged_run.shield)
	var number_context: Dictionary = context.duplicate()
	number_context["feedback_kind"] = "received"
	if hp_loss > 0.0:
		room.add_damage_text(position + Vector2(0,-72), hp_loss, &"received", number_context)
	if shield_loss > 0.0:
		number_context["feedback_kind"] = "shield"
		room.add_damage_text(position + Vector2(0,-90), shield_loss, &"received", number_context)

func shield_summary() -> Dictionary:
	_sync_status_ruleset()
	if Game.run != null:
		status.absorb(maxf(0.0, status.shield() - Game.run.shield))
	return status.shield_summary()

func grant_guard(amount: float, duration: float, source: String) -> void:
	if Game.run == null:
		return
	_sync_status_ruleset()
	status.absorb(maxf(0.0, status.shield() - Game.run.shield))
	var previous_shield: float = Game.run.shield
	if source == "hero_f" and hero_id() == "CH01" and loadout != null and loadout.effects != null:
		amount = loadout.effects.b05_e_shield(amount)
	var equipment: bool = source.begins_with("set_") or source.begins_with("equipment:")
	var result: Dictionary = status.grant_guard_result(amount, duration, source, Game.run.max_hp, equipment)
	Game.run.shield = status.shield()
	if _ruleset_version() == Numbers.V2 and bool(result.accepted_refresh) and (source == "hero_f" or source.begins_with("hero_skill:CH01_SK")) and loadout != null:
		loadout.event("class_shield_gain", {"source":source,"accepted_refresh":true,"increased":bool(result.increased),"equipment":equipment})
	if bool(result.increased):
		room.add_ring(position, Color("abd6c3"), 34.0, 0.3)
		if room.has_method("add_damage_text") and Game.run.shield > previous_shield:
			room.add_damage_text(position + Vector2(0,-90), Game.run.shield - previous_shield, &"guard", {"feedback_kind":"guard"})
		if loadout != null:
			loadout.event("shield_gain", {"source":source,"increased":true})

func on_primary_hit(target: Node2D) -> void:
	if Game.run == null:
		return
	combat_time = 5.0
	# Rage is awarded by the confirmed packet callback, once per original root.

func gain_break_stacks(amount: int = 1) -> void:
	# Retained as a neutral adapter for old environmental callers.
	break_stacks = 0

func consume_break_stacks() -> int:
	break_stacks = 0
	return 0

func _tick_class_state(delta: float) -> void:
	_class_clock += maxf(0.0, delta)
	if role_kit != null: role_kit.tick(delta)
	hit_chain.tick(delta)
	# Keep the existing visual/snapshot fields as a compatibility view. The
	# actual passive owns its counters and weak target references in one place.
	var passive_state: Dictionary = passives.snapshot()
	passive_count = int(passive_state.get("current", 0))
	passive_cooldown = float(passive_state.get("icd", 0.0))
	walk_distance = 0.0
	for key: String in _equipment_class_roots.keys():
		if _class_clock - float(_equipment_class_roots[key]) > 12.0: _equipment_class_roots.erase(key)

func class_mark_target(target: Node2D) -> void:
	pass

## Called once by the shared original-hit pipeline, before equipment multipliers.
## Bonus remains part of that hit and cannot start a second proc chain.
func class_modify_hit_amount(target: Node2D, amount: float, source: StringName, context: Dictionary) -> float:
	return amount

## Called only after a direct hit actually removes health or shield.
func class_record_hit(target: Node2D, source: StringName, context: Dictionary) -> void:
	if not bool(context.get("confirmed", false)) or float(context.get("hp_damage", 0.0)) + float(context.get("shield_damage", 0.0)) <= 0.0: return
	if int(context.get("proc_depth", 0)) != 0 or not bool(context.get("equipment_eligible", false)): return
	passives.record_hit(target, source, context)
	var chain_before: int = hit_chain.count
	if hit_chain.record_hit(source, context):
		var feedback: Node = get_node_or_null("HeroFeedback")
		if is_instance_valid(feedback) and feedback.has_method("chain_hit"):
			var chain_state: Dictionary = hit_chain.snapshot()
			chain_state["advanced"] = int(chain_state.count) > chain_before
			feedback.chain_hit(chain_state)

func resonance_nodes() -> Array[Node2D]:
	return []

## Also used by the room's environmental circuit; no resource or equipment proc.
func charge_resonance(origin: Vector2, reach: float, amount: int = 1) -> int:
	return 0

## Four-beat basic hits feed one nearby capacitor. Prefer an unfilled node;
## excess energy is never banked or allowed through walls/into a second proc.
func charge_nearest_resonance(origin: Vector2, reach: float) -> bool:
	return false

func class_status() -> Dictionary:
	return passives.snapshot()

func original_hit(target: Node2D, amount: float, kind: StringName, applied_status: String = "", push: float = 0.0) -> void:
	room.resolve_direct_hit(target, amount, kind, applied_status, push, (target.position - position).normalized())

func visual_event(kind: String, duration: float, committed_direction: Vector2 = Vector2.ZERO) -> void:
	visual_state = kind
	visual_remaining = duration
	visual_duration = duration
	var feedback: Node = get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback):
		feedback.observe_basic(kind, duration, committed_direction)
	queue_redraw()

func hit_feedback(duration: float) -> void:
	if not Game.profile.get("settings", {}).get("reduced_fx", false):
		visual_hitstop = maxf(visual_hitstop, duration)

func _draw() -> void:
	Visual.draw_hero(self)


func has_hunter_mark(target: Node2D) -> bool:
	return false

## Only a real persistent hostile zone may call this, using one stable room ID.
## Damage means confirmed HP/shield loss, never a warning or overlap attempt.
func notify_hostile_hazard(hazard_id: String, inside: bool, damaged: bool = false) -> void:
	if loadout == null or hazard_id.is_empty(): return
	var id := hazard_id.left(160)
	# Repeated overlap samples are not new events. Keep reducer roots bounded
	# by entries/exits and real hits rather than by physics frames.
	if bool(_hostile_hazards.get(id, false)) == inside and not damaged: return
	if inside: _hostile_hazards[id] = true
	else: _hostile_hazards.erase(id)
	loadout.event("hostile_hazard", {"hazard_id":id, "inside":inside, "zone_damaged":damaged})

## The mechanism owner calls this only after a player-attributed destruction.
func notify_hostile_destructible_destroyed(mechanism_id: String) -> void:
	if loadout == null or mechanism_id.is_empty(): return
	loadout.event("hostile_destructible_destroyed", {"event_id":"mechanism:" + mechanism_id.left(160), "player_attributed":true})


func _tick_b05_control(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta): return
	_enemy_root_protection_remaining = maxf(0.0, _enemy_root_protection_remaining - delta)
	var remaining := _enemy_root_remaining
	_enemy_root_remaining = maxf(0.0, remaining - delta)
	if remaining > 0.0 and _enemy_root_remaining <= 0.0:
		_enemy_root_protection_remaining = maxf(0.0, 2.0 - maxf(0.0, delta - remaining))
		if loadout != null: loadout.event("root_ended", {"actually_rooted":true})


## Source-local ending receipts remain true even under a larger shared pool.
func _b06_guard_ends(previous: Dictionary, cause: String) -> void:
	if loadout == null: return
	var source := "equipment:B06-SU_4"
	var before: Dictionary = previous.get(source, {})
	var after: Dictionary = status.guards.get(source, {})
	if float(before.get("amount", 0.0)) > 0.0 and float(before.get("remaining", 0.0)) > 0.0 and (float(after.get("amount", 0.0)) <= 0.0 or float(after.get("remaining", 0.0)) <= 0.0):
		loadout.event("shield_source_ended", {"source":"B06-SU_4", "cause":cause})

## Only ordinary negative statuses are eligible. Phase marks and roots remain.
func clear_ordinary_negative() -> bool:
	var selected := ""
	var longest := -1.0
	for id: String in ["burn","bleed","corrosion"]:
		var remaining := float(status.states.get(id,{}).get("remaining",0.0))
		if remaining>0.0 and remaining>longest:
			selected=id
			longest=remaining
	if not selected.is_empty():
		status.states.erase(selected)
		_enemy_status_origins.erase(selected)
		_enemy_status_contexts.erase(selected)
	elif _enemy_slow_remaining>0.0:
		_enemy_slow_remaining=0.0
		_enemy_slow_multiplier=1.0
	else: return false
	if loadout!=null: loadout.event("ordinary_negative_cleared",{"actually_cleared":true,"ordinary_status":selected if not selected.is_empty() else "slow"})
	queue_redraw()
	return true
