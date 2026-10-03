extends RefCounted
## B05 value-only room mechanism. No room registration, actors, rewards or saves.
## Callers validate legal damage, plant identity and real hit events. Apply the
## returned shield VALUE by replacement (never addition) to the actor shield.
## Destroyed wells stay destroyed. Their network is locked for 12 seconds;
## other surviving wells on that network can resume after the lock expires.
const RADIUS := 220.0
const REFRESH_SECONDS := 12.0
const CHANNEL_SECONDS := 0.6
var _wells: Dictionary = {}
var _gates: Dictionary = {}
var _cooldowns: Dictionary = {}
var _locks: Dictionary = {}
var _channel: Dictionary = {}

## wells: {id: {x, y, frontline_hp, network_id}}; gates: {id: {well_ids, bridge_id}}.
## Configure only a fresh room object; restoration uses the same authored config.
func configure(wells: Dictionary, gates: Dictionary = {}) -> bool:
	if not _wells.is_empty() or wells.is_empty(): return false
	var prepared: Dictionary = {}
	for id in wells:
		if not _id(id) or not wells[id] is Dictionary: return false
		var spec: Dictionary = wells[id]
		if not _number(spec.get("x")) or not _number(spec.get("y")): return false
		if not _number(spec.get("frontline_hp")) or float(spec.frontline_hp) <= 0.0: return false
		if not _id(spec.get("network_id")): return false
		var maximum: float = maxf(1.0, roundf(float(spec.frontline_hp) * 0.6))
		prepared[id] = {"x":float(spec.x), "y":float(spec.y), "network_id":spec.network_id, "maximum":maximum, "hp":maximum, "closed":false}
	var prepared_gates: Dictionary = {}
	for id in gates:
		if not _id(id) or not gates[id] is Dictionary: return false
		var spec: Dictionary = gates[id]
		if not _id(spec.get("bridge_id")) or not spec.get("well_ids") is Array or spec.well_ids.is_empty(): return false
		for well_id in spec.well_ids:
			if not _id(well_id) or not prepared.has(well_id): return false
		prepared_gates[id] = {"well_ids":spec.well_ids.duplicate(), "bridge_id":spec.bridge_id, "open":false}
	_wells = prepared
	_gates = prepared_gates
	return true

func well_reaches(well_id: String, position: Vector2) -> bool:
	if not _wells.has(well_id) or not position.is_finite(): return false
	var well: Dictionary = _wells[well_id]
	return float(well.hp) > 0.0 and not well.closed and float(_locks.get(well.network_id, 0.0)) <= 0.0 and position.distance_squared_to(Vector2(well.x, well.y)) <= RADIUS * RADIUS

## Empty means no refresh. CD belongs to stable actor_id across ALL wells.
func connect_actor(well_id: String, actor_id: String, position: Vector2, maximum_hp: float, existing_shield: float) -> Dictionary:
	if actor_id.is_empty() or not is_finite(maximum_hp) or maximum_hp <= 0.0 or not is_finite(existing_shield) or existing_shield < 0.0: return {}
	if not well_reaches(well_id, position) or float(_cooldowns.get(actor_id, 0.0)) > 0.0: return {}
	_cooldowns[actor_id] = REFRESH_SECONDS
	return {"actor_id":actor_id, "shield":maxf(existing_shield, maximum_hp * 0.12)}

## Amount must already have passed the caller's legal-damage checks.
func damage_well(well_id: String, amount: float) -> bool:
	if not _wells.has(well_id) or not is_finite(amount) or amount <= 0.0: return false
	var well: Dictionary = _wells[well_id]
	if well.closed or float(well.hp) <= 0.0: return false
	well.hp = maxf(0.0, float(well.hp) - amount)
	if float(well.hp) == 0.0: _locks[well.network_id] = REFRESH_SECONDS
	return true

func begin_gate(gate_id: String, actor_id: String) -> bool:
	if not _gates.has(gate_id) or actor_id.is_empty() or not _channel.is_empty() or _gates[gate_id].open: return false
	_channel = {"gate_id":gate_id, "actor_id":actor_id, "remaining":CHANNEL_SECONDS}
	return true

## Call immediately on a real damaging hit, before advancing the room clock.
func interrupt_actor(actor_id: String) -> bool:
	if _channel.is_empty() or _channel.actor_id != actor_id: return false
	_channel.clear()
	return true

func advance(delta: float) -> bool:
	if not is_finite(delta) or delta < 0.0: return false
	for timers: Dictionary in [_cooldowns, _locks]:
		for id in timers.keys():
			timers[id] = maxf(0.0, float(timers[id]) - delta)
			if float(timers[id]) == 0.0: timers.erase(id)
	if not _channel.is_empty():
		_channel.remaining = maxf(0.0, float(_channel.remaining) - delta)
		if float(_channel.remaining) == 0.0:
			var gate: Dictionary = _gates[_channel.gate_id]
			gate.open = true
			for well_id in gate.well_ids: _wells[well_id].closed = true
			_channel.clear()
	return true

func bridge_is_open(bridge_id: String) -> bool:
	for gate: Dictionary in _gates.values():
		if gate.bridge_id == bridge_id and gate.open: return true
	return false

func snapshot() -> Dictionary:
	return {"version":1, "wells":_wells.duplicate(true), "gates":_gates.duplicate(true), "cooldowns":_cooldowns.duplicate(true), "locks":_locks.duplicate(true), "channel":_channel.duplicate(true)}

## Transactional, value-only and JSON-round-trip safe. Never defaults damaged
## state back to fresh state. Restoring is explicit checkpoint rollback only.
func restore(data: Dictionary) -> bool:
	if not _number(data.get("version")) or float(data.version) != 1.0: return false
	for field in ["wells", "gates", "cooldowns", "locks", "channel"]:
		if not data.get(field) is Dictionary: return false
	if data.wells.size() != _wells.size() or data.gates.size() != _gates.size(): return false
	for id in _wells:
		if not data.wells.get(id) is Dictionary: return false
		var well: Dictionary = data.wells[id]
		for field in ["x", "y", "maximum"]:
			if not _number(well.get(field)): return false
			# JSON decimal serialization can lose sub-nanopixel digits from
			# Vector2 float32 positions. Coordinates are validated, never copied.
			var tolerance := 0.0 if field == "maximum" else 0.000001
			if absf(float(well[field])-float(_wells[id][field])) > tolerance: return false
		if well.get("network_id") != _wells[id].network_id or not well.get("closed") is bool: return false
		if not _bounded(well.get("hp"), float(well.maximum)): return false
	for id in _gates:
		if not data.gates.get(id) is Dictionary: return false
		var gate: Dictionary = data.gates[id]
		if gate.get("well_ids") != _gates[id].well_ids or gate.get("bridge_id") != _gates[id].bridge_id or not gate.get("open") is bool: return false
		if gate.open:
			for well_id in gate.well_ids:
				if not data.wells[well_id].closed: return false
	for timers: Dictionary in [data.cooldowns, data.locks]:
		for id in timers:
			if not _id(id) or not _bounded(timers[id], REFRESH_SECONDS): return false
	for network_id in data.locks:
		var known := false
		for well: Dictionary in _wells.values():
			if well.network_id == network_id: known = true
		if not known: return false
	var channel: Dictionary = data.channel
	if not channel.is_empty():
		if not _id(channel.get("gate_id")) or not _gates.has(channel.gate_id) or not _id(channel.get("actor_id")): return false
		if data.gates[channel.gate_id].open or not _bounded(channel.get("remaining"), CHANNEL_SECONDS) or float(channel.remaining) == 0.0: return false
	# Copy only the approved schema: no unknown object/reference-bearing fields.
	for id in _wells:
		_wells[id].hp = float(data.wells[id].hp)
		_wells[id].closed = data.wells[id].closed
	for id in _gates: _gates[id].open = data.gates[id].open
	_cooldowns = data.cooldowns.duplicate(true)
	_locks = data.locks.duplicate(true)
	_channel = {} if channel.is_empty() else {"gate_id":channel.gate_id, "actor_id":channel.actor_id, "remaining":float(channel.remaining)}
	return true

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty()

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _bounded(value: Variant, maximum: float) -> bool:
	return _number(value) and float(value) >= 0.0 and float(value) <= maximum
