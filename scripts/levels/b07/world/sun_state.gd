extends RefCounted
## Pure mirror/altar state. No player, RNG, files or clocks outside this instance.
const CHANNEL_SECONDS := 0.6
const SUPPRESSION_SECONDS := 8.0
const EXPOSURE_SECONDS := 4.0
const COUNTER_COOLDOWN := 12.0
var room_id := ""
var mirrors: Dictionary = {}
var gate_open := false
var phase := 1
var altar_hp := 0.0
var altar_max_hp := 0.0
var suppression := 0.0
var exposure := 0.0
var counter_cooldown := 0.0
var _required := 1
var _altar := ""
var _definitions: Dictionary = {}
var _channel_id := ""
var _channel_elapsed := 0.0

func configure(id: String, definitions: Array, altar_id: String, required: int, boss_hp: float = 0.0) -> bool:
	if not room_id.is_empty() or definitions.is_empty() or required < 1 or required > definitions.size() or not is_finite(boss_hp) or boss_hp < 0: return false
	var parsed := {}
	for mirror: Dictionary in definitions:
		if str(mirror.get("id","")).is_empty() or parsed.has(mirror.id) or mirror.get("states",[]).size() != 3: return false
		for direction: Dictionary in mirror.states:
			if not direction.get("targets") is Array or direction.get("path",[]).size() < 2: return false
		parsed[mirror.id] = mirror.duplicate(true)
	_definitions = parsed
	room_id = id
	_altar = altar_id
	_required = required
	altar_max_hp = ceilf(boss_hp*.08)
	altar_hp = altar_max_hp
	for key: String in parsed: mirrors[key] = int(parsed[key].get("initial_state",0))%3
	_evaluate()
	return true

func current_direction(id: String, next: bool = false) -> Dictionary:
	if not mirrors.has(id): return {}
	return _definitions[id].states[(int(mirrors[id])+(1 if next else 0))%3].duplicate(true)

func begin_rotation(id: String) -> bool:
	if not mirrors.has(id) or not _channel_id.is_empty(): return false
	_channel_id = id
	_channel_elapsed = 0.0
	return true

func cancel_rotation() -> void:
	_channel_id = ""
	_channel_elapsed = 0.0

func channel() -> Dictionary:
	return {"id":_channel_id,"elapsed":_channel_elapsed,"duration":CHANNEL_SECONDS}

func tick(delta: float, channel_valid: bool = true, paused: bool = false) -> bool:
	if paused or not is_finite(delta) or delta <= 0: return false
	suppression = maxf(0,suppression-delta)
	exposure = maxf(0,exposure-delta)
	counter_cooldown = maxf(0,counter_cooldown-delta)
	var changed := false
	if not _channel_id.is_empty():
		if not channel_valid: cancel_rotation()
		else:
			_channel_elapsed += delta
			if _channel_elapsed + .000001 >= CHANNEL_SECONDS:
				mirrors[_channel_id] = (int(mirrors[_channel_id])+1)%3
				cancel_rotation()
				changed = true
	_evaluate()
	return changed

func aligned_count() -> int:
	var result := 0
	for key: String in mirrors:
		if _altar in current_direction(key).get("targets",[]): result += 1
	return result

func _evaluate() -> void:
	if aligned_count() >= _required:
		gate_open = true # Opened roads never close when a support rotates away.
		if phase >= 2 and altar_hp > 0 and counter_cooldown <= 0:
			suppression = SUPPRESSION_SECONDS
			exposure = EXPOSURE_SECONDS
			counter_cooldown = COUNTER_COOLDOWN

func set_phase(value: int) -> void:
	if value in [1,2,3]: phase = value; _evaluate()

func open_manual_gate(combat_cleared: bool) -> bool:
	if not combat_cleared: return false
	gate_open = true
	return true

func damage_altar(confirmed_damage: float) -> bool:
	if phase < 2 or altar_hp <= 0 or not is_finite(confirmed_damage) or confirmed_damage <= 0: return false
	altar_hp = maxf(0,altar_hp-confirmed_damage)
	if altar_hp <= 0 and counter_cooldown <= 0:
		exposure = EXPOSURE_SECONDS
		counter_cooldown = COUNTER_COOLDOWN
	return true

func boss_multiplier() -> float:
	if phase < 2: return 1.0
	if exposure > 0: return 1.15
	return .7 if altar_hp > 0 and suppression <= 0 else 1.0

func checkpoint() -> Dictionary:
	# Interrupted channels intentionally never cross the safe-boundary format.
	return {"version":1,"room_id":room_id,"mirrors":mirrors.duplicate(),"gate_open":gate_open,"phase":phase,"altar_hp":altar_hp,"suppression":suppression,"exposure":exposure,"counter_cooldown":counter_cooldown}

func restore(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 9 or not value.has_all(["version","room_id","mirrors","gate_open","phase","altar_hp","suppression","exposure","counter_cooldown"]): return false
	if value.version != 1 or value.room_id != room_id or not value.mirrors is Dictionary or value.mirrors.size() != mirrors.size() or not value.gate_open is bool: return false
	if not _integer_in(value.phase,1,3): return false
	for key: String in mirrors:
		if not _integer_in(value.mirrors.get(key),0,2): return false
	for key: String in ["altar_hp","suppression","exposure","counter_cooldown"]:
		var number: Variant = value[key]
		var upper: float = {"altar_hp":altar_max_hp,"suppression":SUPPRESSION_SECONDS,"exposure":EXPOSURE_SECONDS,"counter_cooldown":COUNTER_COOLDOWN}[key]
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > upper: return false
	var count := 0
	for key: String in mirrors:
		if _altar in _definitions[key].states[int(value.mirrors[key])].targets: count += 1
	if count >= _required and not value.gate_open: return false
	mirrors = value.mirrors.duplicate()
	gate_open = value.gate_open
	phase = int(value.phase)
	altar_hp = float(value.altar_hp)
	suppression = float(value.suppression)
	exposure = float(value.exposure)
	counter_cooldown = float(value.counter_cooldown)
	cancel_rotation()
	return true

func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum
