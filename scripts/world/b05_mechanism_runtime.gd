extends Node2D
## Opt-in adapter, NOT a registered chapter. Invisible test targets are not
## MineEnemy and must not be inserted into room.enemies. Production attacks use
## apply_confirmed_well_damage AFTER settlement, not ObjectiveTarget's pre-hit hook.
## Release blockers: approved art, MineEnemy target binding, bridge geometry,
## and an explicit authored shield_duration (the design specifies no lifetime).
const Network = preload("res://scripts/world/b05_root_network.gd")
signal bridge_changed(bridge_id: String, opened: bool)
var _network = Network.new()
var _room_id := ""
var _shield_duration := 0.0
var _interaction_radius := 0.0
var _gate_positions: Dictionary = {}
var _targets: Dictionary = {}
var _plants: Dictionary = {}
# Retain stable identity while an actor lives, even across unregister/register.
var _plant_bindings: Dictionary = {}
var _interactor: WeakRef
var _alive_check: Callable
var _line_of_sight: Callable
var _active_actor_id := ""

class TestWellTarget extends Node2D:
	## Deliberately invisible and reward-free. This is a contract fixture only.
	var adapter: Node2D
	var well_id := ""
	var actor_kind := "objective"
	var reward_enabled := false
	var last_damage_result: Dictionary = {}
	func is_alive() -> bool:
		return is_instance_valid(adapter) and adapter.well_can_take_damage(well_id)
	func take_damage(amount: float, _kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
		last_damage_result = {"confirmed":false, "hp_damage":0.0, "shield_damage":0.0}
		# Only a caller's already legal hit may exercise the fixture interface.
		if not is_alive() or not direction.is_finite() or not bool(context.get("legal_hit", false)) or bool(context.get("invulnerable", false)): return false
		last_damage_result = adapter.apply_confirmed_well_damage(well_id, {"confirmed":true, "hp_damage":amount})
		return bool(last_damage_result.get("confirmed", false))

## Positions use this node's local world-pixel space, with the production room's
## transform. interaction_radius must come from Balance.INTERACTION_RADIUS (68).
## shield_duration is mandatory experimental input, not a frozen B05 default.
func configure(room_id: String, wells: Dictionary, gates: Dictionary, shield_duration: float, interaction_radius: float) -> bool:
	if not _room_id.is_empty() or room_id.is_empty() or not is_finite(shield_duration) or shield_duration <= 0.0 or not is_finite(interaction_radius) or interaction_radius <= 0.0: return false
	var positions: Dictionary = {}
	for id in gates:
		if not gates[id] is Dictionary: return false
		if not _finite_number(gates[id].get("x")) or not _finite_number(gates[id].get("y")): return false
		positions[id] = Vector2(float(gates[id].x), float(gates[id].y))
	if not _network.configure(wells, gates): return false
	_room_id = room_id
	_shield_duration = shield_duration
	_interaction_radius = interaction_radius
	_gate_positions = positions
	for id in wells:
		var target := TestWellTarget.new()
		target.adapter = self
		target.well_id = id
		target.position = Vector2(wells[id].x, wells[id].y)
		add_child(target)
		_targets[id] = target
	return true

func well_target(well_id: String) -> Node2D:
	return _targets.get(well_id)

func well_can_take_damage(well_id: String) -> bool:
	var well: Dictionary = _network.snapshot().wells.get(well_id, {})
	return not well.is_empty() and float(well.hp) > 0.0 and not well.closed

## Receipt amount is post-defense, actual HP damage, never a raw pre-hit packet.
## Return a capped receipt; do not award enemy kill XP or equipment for a well.
func apply_confirmed_well_damage(well_id: String, receipt: Dictionary) -> Dictionary:
	var rejected := {"confirmed":false, "hp_damage":0.0, "shield_damage":0.0}
	if not receipt.get("confirmed", false) is bool or not receipt.get("confirmed", false) or not _finite_number(receipt.get("hp_damage")): return rejected
	var amount: float = float(receipt.hp_damage)
	if amount <= 0.0 or not well_can_take_damage(well_id): return rejected
	var before: float = float(_network.snapshot().wells[well_id].hp)
	if not _network.damage_well(well_id, amount): return rejected
	return {"confirmed":true, "hp_damage":minf(before, amount), "shield_damage":0.0, "destroyed":not well_can_take_damage(well_id)}

## actor_id must be the encounter's persistent spawn ID, never instance_id.
## Actor uses production enemy health.maximum and status.grant_guard_result.
func register_plant(actor_id: String, actor: Node2D) -> bool:
	if actor_id.is_empty() or not _plant_is_legal(actor): return false
	# Reflection/contract validation is registration-only, never a frame task.
	for old_instance_id in _plant_bindings.keys():
		if not is_instance_valid(_plant_bindings[old_instance_id].actor.get_ref()): _plant_bindings.erase(old_instance_id)
	var instance_id: int = actor.get_instance_id()
	if _plant_bindings.has(instance_id) and _plant_bindings[instance_id].actor_id != actor_id: return false
	for id in _plants:
		var bound = _plants[id].actor.get_ref()
		if is_instance_valid(bound) and (id == actor_id or bound == actor): return false
	_plants[actor_id] = {"actor":weakref(actor), "health":weakref(_property(actor, "health")), "status":weakref(_property(actor, "status")), "enemy_id":_property(actor, "enemy_id")}
	_plant_bindings[instance_id] = {"actor":weakref(actor), "actor_id":actor_id}
	return true

func unregister_plant(actor_id: String) -> void:
	_plants.erase(actor_id) # Root cooldown deliberately survives re-registration.

## Called by the room's F action, with explicit player-life and LOS queries.
## Player life currently belongs to Game.run, so never guess it from a node.
func interact(gate_id: String, actor: Node2D, actor_id: String, alive_check: Callable, line_of_sight: Callable) -> bool:
	if not _gate_positions.has(gate_id) or not is_instance_valid(actor) or actor_id.is_empty() or not alive_check.is_valid() or not line_of_sight.is_valid(): return false
	if is_inside_tree() and get_tree().paused: return false
	if not bool(alive_check.call()) or not _within_gate(gate_id, actor, line_of_sight): return false
	if not _network.begin_gate(gate_id, actor_id): return false
	_interactor = weakref(actor)
	_alive_check = alive_check
	_line_of_sight = line_of_sight
	_active_actor_id = actor_id
	return true

## Supply actual HP + shield consumed by a hostile hit. Rejected/zero hits do
## not interrupt; callers also call cancel_interaction when UI blocks controls.
func notify_actor_hit(actor_id: String, consumed_damage: float) -> bool:
	if not is_finite(consumed_damage) or consumed_damage <= 0.0 or actor_id != _active_actor_id: return false
	cancel_interaction()
	return true

func cancel_interaction() -> void:
	if not _active_actor_id.is_empty(): _network.interrupt_actor(_active_actor_id)
	_active_actor_id = ""
	_interactor = null
	_alive_check = Callable()
	_line_of_sight = Callable()

## No automatic _process: room owns ordering. Deliver damage/cancellation before
## tick; call once per unpaused room frame. Paused ticks never advance cooldowns.
func tick(delta: float, paused: bool = false) -> bool:
	if not is_finite(delta) or delta < 0.0 or _room_id.is_empty(): return false
	if paused or (is_inside_tree() and get_tree().paused):
		cancel_interaction()
		return true
	var before: Dictionary = _network.snapshot()
	if not before.channel.is_empty():
		var actor = _interactor.get_ref() if _interactor != null else null
		if not is_instance_valid(actor) or not _alive_check.is_valid() or not bool(_alive_check.call()) or not _within_gate(str(before.channel.gate_id), actor, _line_of_sight): cancel_interaction()
	_network.advance(delta)
	var state: Dictionary = _network.snapshot()
	for id in state.gates:
		if state.gates[id].open and not before.gates[id].open:
			bridge_changed.emit(str(state.gates[id].bridge_id), true)
	if state.channel.is_empty(): cancel_interaction()
	for actor_id in _plants.keys():
		var binding: Dictionary = _plants[actor_id]
		var actor = binding.actor.get_ref()
		var health = binding.health.get_ref()
		var status = binding.status.get_ref()
		# Registered objects have a verified schema. Keep reads direct and cheap;
		# replaced components must register again, never silently use stale refs.
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not is_instance_valid(health) or not is_instance_valid(status):
			_plants.erase(actor_id)
			continue
		if actor.actor_kind != "enemy" or actor.enemy_id != binding.enemy_id or actor.health != health or actor.status != status or not actor.is_alive():
			_plants.erase(actor_id)
			continue
		var hp: float = float(health.maximum)
		if not is_finite(hp) or hp <= 0.0:
			_plants.erase(actor_id)
			continue
		if float(state.cooldowns.get(actor_id, 0.0)) > 0.0: continue
		var shield: float = float(status.shield())
		if not is_finite(shield) or shield < 0.0:
			_plants.erase(actor_id)
			continue
		var at: Vector2 = to_local(actor.global_position)
		for well_id in state.wells:
			if not well_can_refresh(str(well_id)) or not _network.well_reaches(well_id, at): continue
			# Only an eligible, in-range refresh needs rollback state. Actors on
			# cooldown and out-of-range wells allocate no per-actor snapshots.
			var previous: Dictionary = _network.snapshot()
			var grant: Dictionary = _network.connect_actor(well_id, actor_id, at, hp, shield)
			if grant.is_empty(): break
			# CombatStatus itself takes the highest pool. Do not copy another
			# stronger shield into this source and extend its lifetime.
			var result: Dictionary = status.grant_guard_result(hp * 0.12, _shield_duration, "b05_root_network", hp)
			if not bool(result.get("accepted_refresh", false)): _network.restore(previous)
			break
	return true

func bridge_is_open(bridge_id: String) -> bool:
	return _network.bridge_is_open(bridge_id)

func checkpoint() -> Dictionary:
	var positions: Dictionary = {}
	for id in _gate_positions: positions[id] = {"x":_gate_positions[id].x, "y":_gate_positions[id].y}
	return {"version":1, "room_id":_room_id, "shield_duration":_shield_duration, "interaction_radius":_interaction_radius, "gate_positions":positions, "network":_network.snapshot()}

## Restoring checkpoints does not restore an old held F input. It cancels only
## the channel, preserving wells, bridges and all root cooldown/lock values.
## Combat actor health/status checkpoints remain the room's responsibility.
func restore_checkpoint(data: Dictionary) -> bool:
	if not _finite_number(data.get("version")) or float(data.version) != 1.0 or _room_id.is_empty() or data.get("room_id") != _room_id: return false
	for field in ["shield_duration", "interaction_radius"]:
		if not _finite_number(data.get(field)) or float(data[field]) != float(checkpoint()[field]): return false
	if not data.get("gate_positions") is Dictionary or not data.get("network") is Dictionary: return false
	var expected_positions: Dictionary = checkpoint().gate_positions
	if data.gate_positions.size() != expected_positions.size(): return false
	for id in expected_positions:
		if not data.gate_positions.get(id) is Dictionary: return false
		for axis in ["x","y"]:
			if not _finite_number(data.gate_positions[id].get(axis)) or absf(float(data.gate_positions[id][axis])-float(expected_positions[id][axis])) > 0.000001: return false
	var before: Dictionary = _network.snapshot()
	if not _network.restore(data.network): return false
	var channel: Dictionary = _network.snapshot().channel
	if not channel.is_empty(): _network.interrupt_actor(str(channel.actor_id))
	cancel_interaction()
	var after: Dictionary = _network.snapshot()
	for id in after.gates:
		if after.gates[id].open != before.gates[id].open: bridge_changed.emit(str(after.gates[id].bridge_id), bool(after.gates[id].open))
	return true

func _within_gate(gate_id: String, actor: Node2D, sight: Callable) -> bool:
	if not sight.is_valid() or not actor.global_position.is_finite(): return false
	var target: Vector2 = to_global(_gate_positions[gate_id])
	return actor.global_position.distance_to(target) <= _interaction_radius and bool(sight.call(actor.global_position, target))

func _plant_is_legal(actor: Variant) -> bool:
	if not is_instance_valid(actor) or not actor is Node2D or actor.is_queued_for_deletion() or not actor.has_method("is_alive") or not actor.is_alive(): return false
	if _property(actor, "actor_kind") != "enemy": return false
	var enemy_id = _property(actor, "enemy_id")
	if not enemy_id is String or enemy_id.length() != 7 or not enemy_id.begins_with("B05-M"): return false
	var ordinal: String = enemy_id.substr(5)
	if not ordinal.is_valid_int() or int(ordinal) < 1 or int(ordinal) > 18: return false
	var health = _property(actor, "health")
	var status = _property(actor, "status")
	return is_instance_valid(health) and _finite_number(_property(health, "maximum")) and float(health.maximum) > 0.0 and is_instance_valid(status) and status.has_method("shield") and status.has_method("grant_guard_result")

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED: cancel_interaction()

func _exit_tree() -> void:
	cancel_interaction()

static func _property(object: Object, key: String) -> Variant:
	for item in object.get_property_list():
		if item.name == key: return object.get(key)
	return null

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

## Production hosts can deactivate phase wells or switch to a speed-only mode.
func well_can_refresh(_well_id: String) -> bool:
	return true
