class_name CombatSnapshot
extends RefCounted
## JSON-only safe-boundary snapshots. Capture never ticks or changes live state.
## Room-local room_prop:* guards expire on departure; hero/equipment guards keep
## their independent amounts and expiry times. No positions, scene IDs, pending
## attacks, projectiles or target-bound equipment counters cross the boundary.
## Restore runs after actor initialization and before caller-owned entry rewards.
## It never emits room_enter or applies one-shot equipment commands.
## restore_room_entry additionally merges one new-room equipment entry event;
## same-room checkpoints and fresh_entry never repeat that event.

const VERSION := 1
const LIMIT := 1000000000.0
const Status = preload("res://scripts/combat/combat_status.gd")
const Rules = preload("res://scripts/combat/equipment_effects.gd")
const PLAYER_TIMERS := ["dash_cooldown", "shot_cooldown", "invulnerable", "resource_delay", "combat_time", "rage_hurt_cooldown", "passive_cooldown"]
const SKILLS := ["q", "secondary", "f", "ultimate"]
# Keep the JSON validator aligned with the runtime reducer. Adding a supported
# status does not alter the version-one shape or invalidate older snapshots.
const STATES := Status.VALID_STATES
const EFFECT_MAPS := ["cooldowns", "buffs", "windows", "rooms", "counts"]
const EFFECT_HISTORIES := ["heal_history", "resource_history", "refund_history"]
const EFFECT_NUMBERS := ["clock", "undamaged_time", "eq12_spent_at", "movement_time", "dash_time", "delayed_shield_at"]
const MODIFIERS := ["damage_bonus", "crit_bonus", "attack_speed_bonus", "move_speed_bonus", "damage_reduction_bonus", "knockback_scale", "received_knockback_scale", "slow_resistance", "chill_duration_bonus", "cost_reduction"]

static func capture(room: Node) -> Dictionary:
	var game: Node = _game()
	var actor: Node2D = _actor(room)
	if actor == null or game == null or game.run == null:
		return {}
	var status: RefCounted = actor.get("status")
	var loadout: RefCounted = actor.get("loadout")
	var effects: RefCounted = loadout.get("effects")
	var player: Dictionary = {"cooldowns":actor.get("cooldowns").duplicate(true), "passive_count":int(actor.get("passive_count")), "walk_distance":float(actor.get("walk_distance")), "aim_direction":_vector(actor.get("aim_direction")), "cast_serial":int(actor.get("abilities").get("cast_serial"))}
	for key: String in PLAYER_TIMERS:
		player[key] = float(actor.get(key))
	var guards: Dictionary = status.get("guards").duplicate(true)
	# Account for shield damage applied directly to RunState without mutating the
	# source status. All source pools consume the same effective damage.
	var external_damage: float = maxf(0.0, float(status.call("shield")) - game.run.shield)
	Status.activate_prepared_guards(guards, external_damage)
	for source: String in guards.keys():
		guards[source].amount = maxf(0.0, float(guards[source].amount) - external_damage)
		if source.begins_with("room_prop:") or float(guards[source].remaining) <= 0.0 or float(guards[source].amount) <= 0.0:
			guards.erase(source)
	var origins: Dictionary = {}
	for id: String in actor.get("_enemy_status_origins"):
		if status.get("states").has(id):
			origins[id] = _vector(actor.get("_enemy_status_origins")[id])
	var status_data: Dictionary = {"clock":float(status.get("clock")), "shock_cooldown":float(status.get("shock_cooldown")), "states":status.get("states").duplicate(true), "guards":guards, "origins":origins, "slow_remaining":float(actor.get("_enemy_slow_remaining")), "slow_multiplier":float(actor.get("_enemy_slow_multiplier"))}
	var equipment: Dictionary = {}
	for key: String in EFFECT_MAPS + EFFECT_HISTORIES:
		equipment[key] = effects.get(key).duplicate(true)
	for key: String in equipment.cooldowns.keys():
		if key.begins_with("EQ03:"):
			equipment.cooldowns.erase(key) # Per-enemy burn ICD, not a global ICD.
	for key: String in EFFECT_NUMBERS:
		equipment[key] = float(effects.get(key))
	equipment["room_id"] = str(effects.get("room_id"))
	equipment["room_low_shield_used"] = bool(effects.get("room_low_shield_used"))
	equipment["room_first_kill_used"] = bool(effects.get("room_first_kill_used"))
	equipment["adapter"] = {"clock":float(loadout.get("_clock")), "movement_time":float(loadout.get("_movement_time")), "event_serial":int(loadout.get("_event_serial")), "modifiers":loadout.get("_modifiers").duplicate(true)}
	var source_writes: Dictionary = loadout.call("self_status_sources", status_data.states)
	var source_known: bool = bool(loadout.get("_self_status_sources_known"))
	if not source_known:
		source_known = true
		for id: String in ["damage_reduction", "invulnerable"]:
			if status_data.states.has(id) and not source_writes.has(id):
				source_known = false
	if source_known:
		equipment.adapter["self_status_sources"] = source_writes
	var result: Dictionary = {"snapshot_version":VERSION, "mode":"safe_boundary", "hero_id":game.run.hero_id, "hp":game.run.hp, "resource":game.run.resource, "player":player, "status":status_data, "equipment":equipment}
	# Runtime dictionary dot writes can create StringName keys. Normalize that
	# engine-only key representation in the detached copy, not in live reducers;
	# all value types and the strict JSON/schema validator remain unchanged.
	result = _json_keys(result)
	return result if validate(result, game.run.hero_id, game.run.stats) else {}

## Pure safe-boundary replacement. Preserve absolute survival values and spent
## rewards; only the new caps and the ownership of active benefits may change.
static func for_loadout(snapshot: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary, new_stats: Dictionary, hero_id: String, old_stats: Dictionary = {}) -> Dictionary:
	var prior_stats: Dictionary = old_stats if not old_stats.is_empty() else {"max_hp":LIMIT, "resource_max":LIMIT}
	if not validate(snapshot, hero_id, prior_stats) or not _number(new_stats.get("max_hp")) or float(new_stats.max_hp) <= 0.0 or not _number(new_stats.get("resource_max")):
		return {}
	if not loadout_source_error(snapshot, old_loadout, new_loadout, old_stats, new_stats).is_empty():
		return {}
	var result: Dictionary = snapshot.duplicate(true)
	result.hp = minf(float(result.hp), float(new_stats.max_hp))
	result.resource = minf(float(result.resource), float(new_stats.resource_max))
	result.equipment = Rules.for_loadout(result.equipment, old_loadout, new_loadout, old_stats, new_stats)
	var previous: Dictionary = Rules.loadout_binding(old_loadout, old_stats)
	var next: Dictionary = Rules.loadout_binding(new_loadout, new_stats)
	var guards: Dictionary = result.status.guards
	for source: String in guards.keys():
		var equipment_source: bool = source.begins_with("equipment:") or source.begins_with("set_")
		if equipment_source and (not Rules.source_active(source, previous) or not Rules.source_active(source, next)):
			guards.erase(source)
			continue
		var ratio: float = 0.35 if equipment_source else 0.15 if Status.is_prepared_supply_guard(source) else 0.5
		guards[source].amount = minf(float(guards[source].amount), float(new_stats.max_hp) * ratio)
	var writes: Dictionary = result.equipment.adapter.get("self_status_sources", {})
	for id: String in writes.keys():
		var origin: Dictionary = writes[id]
		var state: Dictionary = result.status.states.get(id, {})
		var owns_state: bool = not state.is_empty() and float(state.applied_at) == float(origin.applied_at) and float(state.power) == float(origin.power) and float(state.H) == float(origin.H)
		if not Rules.source_active(str(origin.source), previous) or not Rules.source_active(str(origin.source), next):
			if owns_state:
				result.status.states.erase(id)
				result.status.origins.erase(id)
			writes.erase(id)
		elif not owns_state:
			writes.erase(id)
	# Evaluate passive modifiers on detached rules. No advance(), event(), heal,
	# shield, mana restore or room entry can occur while constructing this copy.
	var reducer: RefCounted = Rules.new()
	reducer.call("rebind", new_loadout, new_stats, str(new_stats.get("resource_type", "")))
	for key: String in ["clock", "buffs", "windows"]:
		reducer.set(key, result.equipment[key])
	var shield: float = 0.0
	for guard: Dictionary in guards.values():
		if float(guard.remaining) > 0.0:
			shield = maxf(shield, float(guard.amount))
	var hero: Dictionary = Rules.Registry.hero(hero_id)
	var context: Dictionary = {"hp":result.hp, "max_hp":new_stats.max_hp, "resource":result.resource, "resource_max":new_stats.resource_max, "resource_type":new_stats.get("resource_type", ""), "shield":shield, "current_speed":0.0, "base_speed":float(hero.get("move_speed", 220.0)), "nearby_burning":false, "self_chilled":result.status.states.has("chill") and float(result.status.states.get("chill", {}).get("remaining", 0.0)) > 0.0}
	var modifiers: Dictionary = reducer.call("passive_modifiers", context)
	for key: String in MODIFIERS:
		result.equipment.adapter.modifiers[key] = float(modifiers[key])
	return result if validate(result, hero_id, new_stats) else {}

## Legacy v1 saves did not record who granted these two positive statuses.
## Reject only an ambiguous removal instead of inventing an owner or retaining
## an unequipped benefit. Once it expires a new capture becomes unambiguous.
static func loadout_source_error(snapshot: Dictionary, old_loadout: Dictionary, new_loadout: Dictionary, old_stats: Dictionary = {}, new_stats: Dictionary = {}) -> String:
	var equipment: Variant = snapshot.get("equipment", {})
	var status_data: Variant = snapshot.get("status", {})
	if not equipment is Dictionary or not status_data is Dictionary:
		return ""
	var adapter: Variant = equipment.get("adapter", {})
	var states: Variant = status_data.get("states", {})
	if not adapter is Dictionary or not states is Dictionary:
		return ""
	if adapter.has("self_status_sources"):
		return ""
	var previous: Dictionary = Rules.loadout_binding(old_loadout, old_stats)
	var next: Dictionary = Rules.loadout_binding(new_loadout, new_stats)
	for id: String in ["damage_reduction", "invulnerable"]:
		var source: String = "EQ20" if id == "damage_reduction" else "EQ21"
		var state: Variant = states.get(id, {})
		if state is Dictionary and Rules.source_active(source, previous) and not Rules.source_active(source, next) and float(state.get("remaining", 0.0)) > 0.0:
			return "旧存档无法确定当前临时增益的来源。本次请保持当前装备；新装备会保留为战利品，成功撤离后可在营地穿戴。"
	return ""

static func restore(room: Node, snapshot: Dictionary) -> bool:
	var game: Node = _game()
	var actor: Node2D = _actor(room)
	if actor == null or game == null or game.run == null or not validate(snapshot, game.run.hero_id, game.run.stats, true):
		return false
	# Initial actor setup owns fresh-entry values and entry effects.
	if snapshot.mode == "fresh_entry":
		return true
	# Nothing above this point mutates state. Everything below uses validated,
	# detached copies, so rejection cannot leave a partially restored actor.
	var player: Dictionary = snapshot.player
	var status_data: Dictionary = snapshot.status
	var equipment: Dictionary = snapshot.equipment
	var status: RefCounted = actor.get("status")
	var loadout: RefCounted = actor.get("loadout")
	var effects: RefCounted = loadout.get("effects")
	var binding: Dictionary = Rules.loadout_binding(game.run.loadout_snapshot, game.run.stats)
	var rebound: bool = effects.get("equipped") != binding.equipped or effects.get("set_counts") != binding.set_counts or effects.get("stats") != game.run.stats
	if rebound:
		loadout.call("rebind", game.run.loadout_snapshot, game.run.stats)
	actor.call("cancel_actions")
	actor.set("dash_remaining", 0.0)
	actor.set("dash_elapsed", 0.0)
	actor.set("knockback", Vector2.ZERO)
	actor.set("velocity", Vector2.ZERO)
	actor.set("hurt_flash", 0.0)
	actor.set("muzzle_flash", 0.0)
	actor.set("visual_state", "idle")
	actor.set("visual_remaining", 0.0)
	actor.set("visual_duration", 0.0)
	actor.set("visual_hitstop", 0.0)
	actor.set("_pending_skill_slot", "")
	actor.set("_attack_critical", false)
	actor.set("last_cast_error", "")
	for key: String in PLAYER_TIMERS:
		actor.set(key, float(player[key]))
	actor.set("cooldowns", player.cooldowns.duplicate(true))
	actor.set("passive_count", int(player.passive_count))
	actor.set("walk_distance", float(player.walk_distance))
	actor.set("aim_direction", Vector2(float(player.aim_direction[0]), float(player.aim_direction[1])))
	actor.get("abilities").set("cast_serial", int(player.cast_serial))
	status.set("clock", float(status_data.clock))
	status.set("shock_cooldown", float(status_data.shock_cooldown))
	status.set("states", status_data.states.duplicate(true))
	status.set("guards", status_data.guards.duplicate(true))
	var origins: Dictionary = {}
	for id: String in status_data.origins:
		origins[id] = Vector2(float(status_data.origins[id][0]), float(status_data.origins[id][1]))
	actor.set("_enemy_status_origins", origins)
	actor.set("_enemy_slow_remaining", float(status_data.slow_remaining))
	actor.set("_enemy_slow_multiplier", float(status_data.slow_multiplier))
	for key: String in EFFECT_MAPS:
		effects.set(key, equipment[key].duplicate(true))
	for key: String in EFFECT_HISTORIES:
		var history: Array[Dictionary] = []
		for entry: Dictionary in equipment[key]:
			history.append(entry.duplicate(true))
		effects.set(key, history)
	for key: String in EFFECT_NUMBERS:
		effects.set(key, float(equipment[key]))
	for key: String in ["room_id", "room_low_shield_used", "room_first_kill_used"]:
		effects.set(key, equipment[key])
	for key: String in ["roots", "deaths", "same_target", "first_full_targets", "shock_targets"]:
		effects.set(key, {})
	loadout.set("_clock", float(equipment.adapter.clock))
	loadout.set("_movement_time", float(equipment.adapter.movement_time))
	loadout.set("_event_serial", int(equipment.adapter.event_serial))
	loadout.set("_modifiers", equipment.adapter.modifiers.duplicate(true))
	loadout.set("_self_status_sources", equipment.adapter.get("self_status_sources", {}).duplicate(true))
	loadout.set("_self_status_sources_known", equipment.adapter.has("self_status_sources"))
	loadout.set("_last_position", actor.get("position"))
	loadout.set("_current_speed", 0.0)
	loadout.set("_applying_depth", 0)
	game.run.hp = minf(float(snapshot.hp), game.run.max_hp)
	game.run.resource = minf(float(snapshot.resource), float(game.run.stats.resource_max))
	game.run.shield = float(status.call("shield"))
	if rebound:
		loadout.call("refresh_modifiers")
	actor.queue_redraw()
	return true

static func restore_room_entry(room: Node, snapshot: Dictionary) -> bool:
	if not is_instance_valid(room) or not room.get("layout_id") is String or str(room.get("layout_id")).is_empty():
		return false
	if not restore(room, snapshot):
		return false
	if snapshot.mode == "fresh_entry" or str(snapshot.equipment.room_id) == str(room.get("layout_id")):
		return true
	var actor: Node2D = _actor(room)
	var loadout: RefCounted = actor.get("loadout")
	var effects: RefCounted = loadout.get("effects")
	var windows: Dictionary = effects.get("windows").duplicate(true)
	var delayed_shield_at: float = float(effects.get("delayed_shield_at"))
	var undamaged_time: float = float(effects.get("undamaged_time"))
	var context: Variant = room.get("expedition_context")
	var combat_room: bool = not context is Dictionary or str(context.get("role", "")) not in ["entrance", "supply"]
	# Entry owns per-room flags, EQ27's new source pool and EQ42's fresh buff.
	# Existing generic windows, delayed procs and no-damage progress belong to
	# the expedition and survive the legacy reducer's room initialization.
	loadout.call("event", "room_enter", {"room_id":str(room.get("layout_id")), "unvisited":true, "combat_room":combat_room})
	effects.set("windows", windows)
	effects.set("delayed_shield_at", delayed_shield_at)
	effects.set("undamaged_time", undamaged_time)
	# Recompute only passive modifiers. advance(0) could release a due one-shot
	# command, so it must not be used as a cache refresh at a save boundary.
	var modifiers: Dictionary = effects.call("_empty")
	effects.call("_modifiers", loadout.call("_context"), modifiers)
	loadout.call("_update_modifiers", effects.call("_cap_modifiers", modifiers))
	return true

static func validate(value: Variant, hero_id: String, stats: Dictionary, fresh_allowed: bool = false) -> bool:
	if not value is Dictionary or not _json(value) or JSON.stringify(value).length() > 180000:
		return false
	if value.get("snapshot_version") != VERSION or value.get("hero_id") != hero_id or hero_id not in ["CH01", "CH02", "CH03"]:
		return false
	# JSON's decimal roundtrip can place an exactly-full fractional bar a few
	# ulps above its recomputed cap. Accept that precision error, never extra HP.
	if not _number(value.get("hp"), float(stats.get("max_hp", 0.0)) + 0.00001) or float(value.hp) <= 0.0 or not _number(value.get("resource"), float(stats.get("resource_max", 0.0)) + 0.00001):
		return false
	if value.get("mode") == "fresh_entry":
		return fresh_allowed and _keys(value, ["snapshot_version", "mode", "hero_id", "hp", "resource"]) and is_equal_approx(float(value.hp), float(stats.get("max_hp", 0.0))) and is_equal_approx(float(value.resource), float(stats.get("starting_resource", 0.0)))
	if value.get("mode") != "safe_boundary" or not _keys(value, ["snapshot_version", "mode", "hero_id", "hp", "resource", "player", "status", "equipment"]):
		return false
	return _player_valid(value.player) and _status_valid(value.status, float(stats.get("max_hp", 0.0))) and _equipment_valid(value.equipment)

static func _player_valid(value: Variant) -> bool:
	if not value is Dictionary or not _keys(value, PLAYER_TIMERS + ["cooldowns", "passive_count", "walk_distance", "aim_direction", "cast_serial"]):
		return false
	if not value.cooldowns is Dictionary or not _keys(value.cooldowns, SKILLS):
		return false
	for key: String in SKILLS:
		if not _number(value.cooldowns[key], 300.0): return false
	for key: String in PLAYER_TIMERS:
		if not _number(value[key], 300.0): return false
	return _number(value.passive_count, 1000000.0, true) and _number(value.walk_distance, 1000000.0) and _number(value.cast_serial, LIMIT, true) and _vector_valid(value.aim_direction, 1.0)

static func _status_valid(value: Variant, maximum_hp: float) -> bool:
	if not value is Dictionary or not _keys(value, ["clock", "shock_cooldown", "states", "guards", "origins", "slow_remaining", "slow_multiplier"]): return false
	if not _number(value.clock) or not _number(value.shock_cooldown, 300.0) or not _number(value.slow_remaining, 300.0) or not _number(value.slow_multiplier, 1.0): return false
	if not value.states is Dictionary or not value.guards is Dictionary or not value.origins is Dictionary or value.guards.size() > 64: return false
	for id: String in value.states:
		var state: Variant = value.states[id]
		if id not in STATES or not state is Dictionary or not _keys(state, ["remaining", "tick", "power", "H", "applied_at"]): return false
		if not _number(state.remaining, 300.0) or not _number(state.tick, 1.0) or not _number(state.power, 1000000.0) or not _number(state.H, 1000000.0) or not _number(state.applied_at, float(value.clock) + 0.00001): return false
	for source: String in value.guards:
		var guard: Variant = value.guards[source]
		if source.is_empty() or source.begins_with("room_prop:") or not guard is Dictionary or not _keys(guard, ["amount", "remaining"]): return false
		var cap: float = maximum_hp * (0.35 if source.begins_with("set_") or source.begins_with("equipment:") else 0.5)
		if not _number(guard.amount, cap + 0.00001) or not _number(guard.remaining, 300.0): return false
		if source.begins_with(Status.SUPPLY_READY_PREFIX):
			if not Status.is_prepared_supply_guard(source) or not is_equal_approx(float(guard.remaining), Status.SUPPLY_GUARD_SECONDS) or float(guard.amount) > maximum_hp * 0.15 + 0.00001: return false
	for id: String in value.origins:
		if not value.states.has(id) or not _vector_valid(value.origins[id], 1000000.0): return false
	return true

static func _equipment_valid(value: Variant) -> bool:
	if not value is Dictionary or not _keys(value, EFFECT_MAPS + EFFECT_HISTORIES + EFFECT_NUMBERS + ["room_id", "room_low_shield_used", "room_first_kill_used", "adapter"]): return false
	for key: String in EFFECT_MAPS:
		if not value[key] is Dictionary: return false
	for key: String in ["clock", "undamaged_time", "eq12_spent_at", "movement_time"]:
		if not _number(value[key]): return false
	if not _signed_number(value.dash_time, -100.0, float(value.clock)) or not _signed_number(value.delayed_shield_at, -1.0, float(value.clock) + 300.0): return false
	if float(value.eq12_spent_at) > float(value.clock) + 0.00001 or not value.room_id is String or not value.room_low_shield_used is bool or not value.room_first_kill_used is bool: return false
	for key: String in value.cooldowns:
		if key.is_empty() or key.begins_with("EQ03:") or not _number(value.cooldowns[key], float(value.clock) + 3600.0): return false
	for key: String in value.windows:
		if key.is_empty() or not _number(value.windows[key], float(value.clock) + 300.0): return false
	for key: String in value.counts:
		if key.is_empty() or not _number(value.counts[key], 1000000.0, true): return false
	for key: String in value.rooms:
		if key.is_empty() or value.rooms[key] != true: return false
	for key: String in value.buffs:
		var buff: Variant = value.buffs[key]
		if key.is_empty() or not buff is Dictionary or not _keys(buff, ["stat", "amount", "until"]) or buff.stat not in MODIFIERS: return false
		if not _number(buff.amount, 1.0) or not _number(buff.until, float(value.clock) + 300.0): return false
	for key: String in EFFECT_HISTORIES:
		if not value[key] is Array: return false
		var previous: float = -1.0
		for entry: Variant in value[key]:
			if not entry is Dictionary or not _keys(entry, ["time", "amount"]) or not _number(entry.time, float(value.clock) + 0.00001) or not _number(entry.amount, 1000000.0) or float(entry.time) < previous: return false
			previous = float(entry.time)
	var adapter: Variant = value.adapter
	if not adapter is Dictionary: return false
	var adapter_keys: Array = ["clock", "movement_time", "event_serial", "modifiers"]
	if adapter.has("self_status_sources"):
		adapter_keys.append("self_status_sources")
		if not adapter.self_status_sources is Dictionary or adapter.self_status_sources.size() > 2: return false
		for id: String in adapter.self_status_sources:
			var origin: Variant = adapter.self_status_sources[id]
			if id not in ["damage_reduction", "invulnerable"] or not origin is Dictionary or not _keys(origin, ["source", "applied_at", "power", "H"]): return false
			if origin.source != ("EQ20" if id == "damage_reduction" else "EQ21") or not _number(origin.applied_at) or not _number(origin.power, 1.0) or not _number(origin.H, 1000000.0): return false
	if not _keys(adapter, adapter_keys): return false
	if not _number(adapter.clock) or not _number(adapter.movement_time) or not _number(adapter.event_serial, LIMIT, true) or not adapter.modifiers is Dictionary or not _keys(adapter.modifiers, MODIFIERS): return false
	for key: String in MODIFIERS:
		if not _number(adapter.modifiers[key], 1.0): return false
	return true

static func _game() -> Node:
	# Runtime lookup keeps the pure validator usable before autoload compilation,
	# including core save validation and Godot's standalone --script test runner.
	var tree: MainLoop = Engine.get_main_loop()
	return tree.root.get_node_or_null("Game") if tree is SceneTree else null

static func _actor(room: Node) -> Node2D:
	if not is_instance_valid(room): return null
	var actor: Variant = room.get("player")
	if not actor is Node2D or not is_instance_valid(actor) or not actor.has_method("cancel_actions"): return null
	var status: Variant = actor.get("status")
	var loadout: Variant = actor.get("loadout")
	if not status is RefCounted or not loadout is RefCounted or not loadout.get("effects") is RefCounted or not actor.get("abilities") is RefCounted: return null
	return actor

static func _number(value: Variant, maximum: float = LIMIT, integral: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= maximum and (not integral or float(value) == floorf(float(value)))

static func _signed_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _keys(value: Dictionary, expected: Array) -> bool:
	return value.size() == expected.size() and value.has_all(expected)

static func _vector(value: Vector2) -> Array:
	return [value.x, value.y]

static func _vector_valid(value: Variant, extent: float) -> bool:
	return value is Array and value.size() == 2 and _signed_number(value[0], -extent, extent) and _signed_number(value[1], -extent, extent)

static func _json(value: Variant, depth: int = 0) -> bool:
	if depth > 12: return false
	if value == null or value is bool: return true
	if value is int or value is float: return is_finite(float(value)) and absf(float(value)) <= LIMIT
	if value is String: return value.length() <= 256
	if value is Array:
		if value.size() > 512: return false
		for child: Variant in value:
			if not _json(child, depth + 1): return false
		return true
	if value is Dictionary:
		if value.size() > 512: return false
		for key: Variant in value:
			if not key is String or key.length() > 160 or not _json(value[key], depth + 1): return false
		return true
	return false

static func _json_keys(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[str(key) if key is StringName else key] = _json_keys(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry: Variant in value:
			result.append(_json_keys(entry))
		return result
	return value
