extends RefCounted
## Isolated B06 value state. No Game, scene nodes, saving, damage or route unlock.
## Time is integer microseconds. Advance uses active simulation time, never wall time.
const Content = preload("res://scripts/levels/b06/world/content.gd")
const SECOND := 1000000
const LOW := 8 * SECOND
const WARNING := 2 * SECOND
const HIGH := 6 * SECOND
const TUTORIAL_LOW := 12 * SECOND
const CHANNEL := 600000
const DRAIN := 8 * SECOND
const DRAIN_CD := 16 * SECOND
const SHELL_CD := 12 * SECOND
const PUSH_PROTECTION := 2 * SECOND
const MAX_STEP_SECONDS := 60.0
const MAX_TIME_US := 9007199000000000
var _room_id := ""
var _patches: Array = []
var _gates: Dictionary = {}
var _now := 0
var _start := 0
var _boss_phase := 0
var _drained_until: Dictionary = {}
var _gate_ready_at: Dictionary = {}
var _channel: Dictionary = {}
var _shells: Dictionary = {}
var _push_ready_at: Dictionary = {}
var _rounding_remainder := 0.0

## Geometry is a later authored dependency: patches are stable IDs, gates map to
## one patch each. Empty maps are valid (e.g. teaching room). No positions invented.
func configure(room_id: String, patch_ids: Array, gates: Dictionary) -> bool:
	if not _room_id.is_empty() or Content.room(room_id).is_empty() or patch_ids.size() > 32 or gates.size() > 16: return false
	var seen := {}
	for id: Variant in patch_ids:
		if not _id(id) or seen.has(id): return false
		seen[id] = true
	for id: Variant in gates:
		if not _id(id) or not gates[id] is String or not seen.has(gates[id]): return false
	_room_id = room_id
	_patches = patch_ids.duplicate()
	_gates = gates.duplicate(true)
	_boss_phase = 1 if room_id == "BO06" else 0
	_start = -1 if room_id == "BO06" else 0
	return true

func _first_low() -> int:
	return TUTORIAL_LOW if _room_id == "L31" else LOW

func _clock(at: int) -> Dictionary:
	if _start < 0: return {"phase":"inactive", "cycle":-1, "remaining_us":0}
	var elapsed := at - _start
	var first_cycle := _first_low() + WARNING + HIGH
	var cycle := 0
	var low := _first_low()
	if elapsed >= first_cycle:
		elapsed -= first_cycle
		@warning_ignore("integer_division")
		cycle = 1 + elapsed / (LOW + WARNING + HIGH)
		elapsed %= LOW + WARNING + HIGH
		low = LOW
	if elapsed < low: return {"phase":"low", "cycle":cycle, "remaining_us":low - elapsed}
	if elapsed < low + WARNING: return {"phase":"warning", "cycle":cycle, "remaining_us":low + WARNING - elapsed}
	return {"phase":"high", "cycle":cycle, "remaining_us":low + WARNING + HIGH - elapsed}

func clock_state() -> Dictionary:
	var result := _clock(_now)
	result["remaining_seconds"] = float(result.remaining_us) / SECOND
	return result

## Monotonic boss phases. Starting P2 begins a full low→warning→high sequence;
## P3 changes no tide clock, no gate uses and no player ability cooldowns.
func set_boss_phase(phase: int) -> bool:
	if _room_id != "BO06" or phase < _boss_phase or phase < 1 or phase > 3: return false
	if phase >= 2 and _start < 0: _start = _now
	_boss_phase = phase
	return true

func begin_drain(gate_id: String, actor_id: String) -> bool:
	if not _gates.has(gate_id) or not _id(actor_id) or not _channel.is_empty() or int(_gate_ready_at.get(gate_id, 0)) > _now: return false
	_channel = {"gate_id":gate_id, "actor_id":actor_id, "complete_at_us":_now + CHANNEL}
	return true

## Adapter must cancel on interruption, leaving range, death or changing rooms.
## A cancelled interaction never drains, grants equipment effects or starts CD.
func cancel_drain(actor_id: String) -> bool:
	if _channel.is_empty() or _channel.actor_id != actor_id: return false
	_channel.clear()
	return true

## Bounded step prevents unbounded event allocations. Larger offline intervals
## must not be replayed: rooms pause while suspended. Invalid input is atomic.
func advance(delta: float) -> Dictionary:
	if _room_id.is_empty() or not is_finite(delta) or delta < 0.0 or delta > MAX_STEP_SECONDS: return {"ok":false, "events":[]}
	var fractional := delta * SECOND + _rounding_remainder
	var step := int(floor(fractional))
	if step > MAX_TIME_US - _now:
		return {"ok":false, "events":[]}
	_rounding_remainder = fractional - step
	var target := _now + step
	var events: Array = []
	while _now < target:
		var current := _clock(_now)
		var transition_at := _now + int(current.remaining_us) if _start >= 0 else target + 1
		var channel_at := int(_channel.complete_at_us) if not _channel.is_empty() else target + 1
		_now = mini(target, mini(transition_at, channel_at))
		# Drain completion first at a coincident transition: the patch is already
		# dry when the high-entry event is consumed by a future actor adapter.
		if not _channel.is_empty() and _now == channel_at:
			var gate_id: String = _channel.gate_id
			var patch_id: String = _gates[gate_id]
			_drained_until[patch_id] = _now + DRAIN
			_gate_ready_at[gate_id] = _now + DRAIN_CD
			events.append({"event":"drain_completed", "gate_id":gate_id, "patch_id":patch_id, "actor_id":_channel.actor_id, "at_us":_now})
			_channel.clear()
		if _start >= 0 and _now == transition_at:
			var next := _clock(_now)
			events.append({"event":"tide_" + str(next.phase), "cycle":next.cycle, "at_us":_now, "direction_visible":next.phase == "warning"})
			if current.phase == "high" and _room_id == "BO06":
				events.append({"event":"boss_output_window", "seconds":2.5, "at_us":_now})
	_prune_expired()
	return {"ok":true, "events":events}

func _prune_expired() -> void:
	for timers: Dictionary in [_drained_until, _gate_ready_at, _push_ready_at]:
		for id: String in timers.keys():
			if int(timers[id]) <= _now: timers.erase(id)
	# Retain an entry through this high phase even after its ICD; re-entering
	# a drained patch cannot mint another shield in the same high cycle.
	var cycle: int = int(_clock(_now).cycle)
	for id: String in _shells.keys():
		if int(_shells[id].ready_at_us) <= _now and int(_shells[id].cycle) < cycle: _shells.erase(id)

func is_wet(patch_id: String) -> bool:
	return patch_id in _patches and _clock(_now).phase == "high" and int(_drained_until.get(patch_id, 0)) <= _now

func player_movement_multiplier(patch_id: String, slow_reduction: float = 0.0) -> float:
	if not is_finite(slow_reduction) or slow_reduction < 0: return 1.0
	return 1.0 - 0.15 * (1.0 - minf(0.5, slow_reduction)) if is_wet(patch_id) else 1.0

func sea_movement_multiplier(patch_id: String) -> float:
	return 1.12 if is_wet(patch_id) else 1.0

## Call only for a genuine B06 ordinary actor entering the current high water.
## Returned amount replaces that actor's same-source tide shell, never adds.
## The six-second shell lifetime belongs to the caller's status layer.
func enter_high_water(actor_id: String, enemy_id: String, patch_id: String, maximum_hp: int, existing_tide_shell: int = 0) -> Dictionary:
	if not _id(actor_id) or Content.enemy(enemy_id).is_empty() or not is_wet(patch_id) or maximum_hp <= 0 or existing_tide_shell < 0: return {}
	var cycle: int = int(_clock(_now).cycle)
	var previous: Dictionary = _shells.get(actor_id, {})
	if not previous.is_empty() and (int(previous.ready_at_us) > _now or int(previous.cycle) == cycle): return {}
	if not _shells.has(actor_id) and _shells.size() >= 128: return {}
	_shells[actor_id] = {"cycle":cycle, "ready_at_us":_now + SHELL_CD}
	return {"actor_id":actor_id, "shield":maxi(existing_tide_shell, int(floor(maximum_hp * 0.1 + 0.5))), "seconds":6.0, "replace_not_add":true}

## Value-only push admission. Future room adapter must clip accepted displacement
## to the actual navigation/collision shape before moving a body.
func admit_push(actor_id: String, distance: float, reduction: float = 0.0) -> Dictionary:
	if _room_id.is_empty() or not _id(actor_id) or not is_finite(distance) or distance <= 0 or not is_finite(reduction) or reduction < 0: return {}
	if int(_push_ready_at.get(actor_id, 0)) > _now: return {"distance":0.0, "protected":true}
	if not _push_ready_at.has(actor_id) and _push_ready_at.size() >= 128: return {}
	_push_ready_at[actor_id] = _now + PUSH_PROTECTION
	return {"distance":distance * (1.0 - minf(0.5, reduction)), "protected":false}

## The caller passes an already body-radius-inset navigable polygon. Clip at the
## FIRST crossed edge, even if the target re-enters a concave polygon further on.
static func clip_push(origin: Vector2, displacement: Vector2, safe_polygon: PackedVector2Array) -> Vector2:
	if not origin.is_finite() or not displacement.is_finite() or safe_polygon.size() < 3 or safe_polygon.size() > 256: return origin
	for point: Vector2 in safe_polygon:
		if not point.is_finite(): return origin
	if not Geometry2D.is_point_in_polygon(origin, safe_polygon) or displacement.is_zero_approx(): return origin
	var crossings: Array[float] = [0.0, 1.0]
	for index in range(safe_polygon.size()):
		var start := safe_polygon[index]
		var edge := safe_polygon[(index + 1) % safe_polygon.size()] - start
		var cross := displacement.cross(edge)
		if absf(cross) < 0.000001: continue
		var offset := start - origin
		var t := offset.cross(edge) / cross
		var u := offset.cross(displacement) / cross
		if t > 0.0 and t < 1.0 and u >= 0.0 and u <= 1.0: crossings.append(t)
	crossings.sort()
	# Test interiors of the intervals between exact crossings. A tiny probe
	# beside an edge is vulnerable to Geometry2D's own boundary tolerance.
	for index in range(crossings.size() - 1):
		var left: float = crossings[index]
		var right: float = crossings[index + 1]
		if right - left < 0.0000001: continue
		var midpoint := origin + displacement * ((left + right) * 0.5)
		if not Geometry2D.is_point_in_polygon(midpoint, safe_polygon):
			var margin := 0.01 / maxf(displacement.length(), 0.01)
			var clipped := origin + displacement * maxf(0.0, left - margin)
			return clipped if Geometry2D.is_point_in_polygon(clipped, safe_polygon) else origin
	var target := origin + displacement
	return target if Geometry2D.is_point_in_polygon(target, safe_polygon) else origin

func snapshot() -> Dictionary:
	if _room_id.is_empty(): return {}
	return {"version":1, "room_id":_room_id, "patch_ids":_patches.duplicate(), "gates":_gates.duplicate(true),
		"now_us":_now, "tide_start_us":_start, "boss_phase":_boss_phase, "rounding_remainder":_rounding_remainder,
		"drained_until":_drained_until.duplicate(true), "gate_ready_at":_gate_ready_at.duplicate(true),
		"channel":_channel.duplicate(true), "shells":_shells.duplicate(true), "push_ready_at":_push_ready_at.duplicate(true)}

## Restore into a configured object. No partial mutation on corrupt snapshots;
## exact room/patch/gate identity prevents restoring one room's drainage elsewhere.
func restore(value: Variant) -> bool:
	if _room_id.is_empty() or not value is Dictionary or not _keys(value, ["version","room_id","patch_ids","gates","now_us","tide_start_us","boss_phase","rounding_remainder","drained_until","gate_ready_at","channel","shells","push_ready_at"]): return false
	if not _integer(value.version,1,1) or value.room_id != _room_id or value.patch_ids != _patches or value.gates != _gates: return false
	if not _integer(value.now_us,0,MAX_TIME_US) or not _integer(value.tide_start_us,-1,int(value.now_us)) or not _number(value.rounding_remainder,0,0.9999999999999999): return false
	if not _integer(value.boss_phase,0,3): return false
	if _room_id == "BO06":
		if int(value.boss_phase) < 1 or (int(value.boss_phase) == 1) != (int(value.tide_start_us) == -1): return false
	elif int(value.boss_phase) != 0 or int(value.tide_start_us) != 0: return false
	var now: int = int(value.now_us)
	for field: String in ["drained_until","gate_ready_at","push_ready_at"]:
		if not value[field] is Dictionary or value[field].size() > 128: return false
		var limit: int = DRAIN if field == "drained_until" else DRAIN_CD if field == "gate_ready_at" else PUSH_PROTECTION
		for id: Variant in value[field]:
			if not _id(id) or not _integer(value[field][id],now + 1,now + limit): return false
			if field == "drained_until" and id not in _patches: return false
			if field == "gate_ready_at" and not _gates.has(id): return false
	if not value.channel is Dictionary: return false
	if not value.channel.is_empty():
		if not _keys(value.channel,["gate_id","actor_id","complete_at_us"]) or not _gates.has(value.channel.gate_id) or not _id(value.channel.actor_id) or value.gate_ready_at.has(value.channel.gate_id) or not _integer(value.channel.complete_at_us,now + 1,now + CHANNEL): return false
	if not value.shells is Dictionary or value.shells.size() > 128: return false
	var saved_cycle := -1
	if int(value.tide_start_us) >= 0:
		var elapsed := now - int(value.tide_start_us)
		var first_cycle := _first_low() + WARNING + HIGH
		@warning_ignore("integer_division")
		saved_cycle = 0 if elapsed < first_cycle else 1 + (elapsed - first_cycle) / (LOW + WARNING + HIGH)
	for id: Variant in value.shells:
		var shell: Variant = value.shells[id]
		if not _id(id) or not shell is Dictionary or not _keys(shell,["cycle","ready_at_us"]): return false
		if not _integer(shell.cycle,0,saved_cycle) or not _integer(shell.ready_at_us,maxi(0,now - HIGH),now + SHELL_CD): return false
		if int(shell.ready_at_us) <= now and int(shell.cycle) < saved_cycle: return false
	_now = now
	_start = int(value.tide_start_us)
	_boss_phase = int(value.boss_phase)
	_rounding_remainder = float(value.rounding_remainder)
	_drained_until = value.drained_until.duplicate(true)
	_gate_ready_at = value.gate_ready_at.duplicate(true)
	_channel = value.channel.duplicate(true)
	_shells = value.shells.duplicate(true)
	_push_ready_at = value.push_ready_at.duplicate(true)
	return true

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 160
static func _keys(value: Dictionary, fields: Array) -> bool:
	return value.size() == fields.size() and value.has_all(fields)
static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,minimum,maximum) and float(value) == floorf(float(value))
