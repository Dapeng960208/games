class_name B06BossState
extends RefCounted
## Isolated BO06 mechanics. The future adapter must supply verified hit regions
## and claw/pillar contacts and consult damage_admitted at BOTH cast and hit time.
## No actor, geometry, player cooldown, loot, or production-save mutation.
const Tide = preload("res://scripts/world/b06_tide_state.gd")
const EXPOSE_US := 5000000
const EXPOSE_CD_US := 12000000
const OUTPUT_US := 2500000
var _tide: RefCounted
var _pillars: Dictionary = {}
var _maximum_hp := 0
var _hp := 0
var _phase := 1
var _exposed_until := 0
var _pillar_ready_at := 0
var _output_until := 0

func configure(maximum_hp: int, patch_ids: Array, gates: Dictionary, pillars: Dictionary) -> bool:
	if _tide != null or maximum_hp < 1 or maximum_hp > 1000000000 or pillars.is_empty() or pillars.size() > 32: return false
	for id: Variant in pillars:
		if not Tide._id(id) or not pillars[id] is String or pillars[id] not in patch_ids: return false
	var candidate := Tide.new()
	if not candidate.configure("BO06", patch_ids, gates): return false
	_tide = candidate
	_pillars = pillars.duplicate(true)
	_maximum_hp = maximum_hp
	_hp = maximum_hp
	return true

## Bind the room's already configured clock. The adapter calls advance here,
## never both here and on the shared tide in one frame.
func configure_shared(maximum_hp: int, tide: RefCounted, pillars: Dictionary) -> bool:
	if _tide != null or maximum_hp < 1 or maximum_hp > 1000000000 or tide == null or not tide.has_method("snapshot"): return false
	var value: Dictionary = tide.snapshot()
	if value.get("room_id") != "BO06" or pillars.is_empty() or pillars.size() > 32: return false
	for id: Variant in pillars:
		if not Tide._id(id) or not pillars[id] is String or pillars[id] not in value.patch_ids: return false
	_tide = tide
	_pillars = pillars.duplicate(true)
	_maximum_hp = maximum_hp
	_hp = maximum_hp
	return true
func tide_state() -> RefCounted: return _tide

func phase() -> int:
	return _phase if _tide != null else 0

func clock_state() -> Dictionary:
	return _tide.clock_state() if _tide != null else {}

## HP is authoritative resolved health, not a damage request. Healing cannot
## regress phases; death cannot be revived inside the same encounter instance.
func set_health(health: int) -> bool:
	if _tide == null or _hp == 0 or health < 0 or health > _maximum_hp: return false
	_hp = health
	var next := 3 if health * 10 <= _maximum_hp * 4 else 2 if health * 10 <= _maximum_hp * 7 else 1
	_phase = maxi(_phase, next)
	_tide.set_boss_phase(_phase)
	if _hp == 0:
		var channel: Dictionary = _tide.snapshot().channel
		if not channel.is_empty(): _tide.cancel_drain(channel.actor_id)
	return true

func begin_drain(gate_id: String, actor_id: String) -> bool:
	return _tide != null and _hp > 0 and _tide.begin_drain(gate_id, actor_id)

func cancel_drain(actor_id: String) -> bool:
	return _tide != null and _tide.cancel_drain(actor_id)

func advance(delta: float) -> Dictionary:
	if _tide == null or _hp == 0: return {"ok":false,"events":[]}
	var result: Dictionary = _tide.advance(delta)
	if not result.ok: return result
	for event: Dictionary in result.events:
		if event.event == "boss_output_window":
			_output_until = int(event.at_us) + OUTPUT_US
	var now := _now()
	if _output_until <= now: _output_until = 0
	if _exposed_until <= now: _exposed_until = 0
	if _pillar_ready_at <= now: _pillar_ready_at = 0
	return result

func _now() -> int:
	return int(_tide.snapshot().now_us)

## Called only for a confirmed locked claw hitting this authored fixed pillar.
## Dry low tide alone is insufficient: its patch needs an active completed drain.
## Pillars are reusable. A shared cooldown prevents alternating pillars bypassing it.
func confirm_claw_pillar_contact(pillar_id: String) -> bool:
	if not damage_admitted() or not _pillars.has(pillar_id): return false
	var state: Dictionary = _tide.snapshot()
	var now := int(state.now_us)
	if _pillar_ready_at > now or int(state.drained_until.get(_pillars[pillar_id], 0)) <= now: return false
	_exposed_until = now + EXPOSE_US
	_pillar_ready_at = now + EXPOSE_CD_US
	return true

func damage_admitted() -> bool:
	return _tide != null and _hp > 0 and _output_until <= _now()

func exposure_remaining() -> float:
	return maxf(0.0, float(_exposed_until - _now()) / Tide.SECOND) if _tide != null else 0.0

## The authored side/abdomen weak point gains 15%; front shell stays at 35% DR.
## Unknown hit regions reject instead of silently becoming a damage multiplier.
func incoming_multiplier(hit_region: String) -> float:
	if _tide == null or _hp == 0: return 0.0
	if hit_region == "front_shell": return 0.65
	if hit_region == "side_abdomen": return 1.15 if exposure_remaining() > 0.0 else 1.0
	if hit_region == "other": return 1.0
	return -1.0

func snapshot() -> Dictionary:
	if _tide == null: return {}
	return {"version":1,"maximum_hp":_maximum_hp,"hp":_hp,"phase":_phase,
		"pillars":_pillars.duplicate(true),"exposed_until_us":_exposed_until,
		"pillar_ready_at_us":_pillar_ready_at,"output_until_us":_output_until,"tide":_tide.snapshot()}

## Atomic and JSON-safe. Requires an already configured, matching encounter.
func restore(value: Variant) -> bool:
	if _tide == null or not value is Dictionary or not Tide._keys(value,["version","maximum_hp","hp","phase","pillars","exposed_until_us","pillar_ready_at_us","output_until_us","tide"]): return false
	if not Tide._integer(value.version,1,1) or value.maximum_hp != _maximum_hp or value.pillars != _pillars: return false
	if not Tide._integer(value.hp,0,_maximum_hp) or not Tide._integer(value.phase,1,3): return false
	var minimum_phase := 3 if int(value.hp) * 10 <= _maximum_hp * 4 else 2 if int(value.hp) * 10 <= _maximum_hp * 7 else 1
	if int(value.phase) < minimum_phase: return false
	var current: Dictionary = _tide.snapshot()
	var candidate := Tide.new()
	if not candidate.configure("BO06",current.patch_ids,current.gates) or not candidate.restore(value.tide): return false
	var tide: Dictionary = candidate.snapshot()
	if int(tide.boss_phase) != int(value.phase): return false
	var now := int(tide.now_us)
	for key: String in ["exposed_until_us","pillar_ready_at_us","output_until_us"]:
		var duration: int = EXPOSE_US if key == "exposed_until_us" else EXPOSE_CD_US if key == "pillar_ready_at_us" else OUTPUT_US
		if not Tide._integer(value[key],0,now + duration): return false
		if int(value[key]) != 0 and int(value[key]) <= now: return false
	if int(value.exposed_until_us) > 0 and int(value.pillar_ready_at_us) - int(value.exposed_until_us) != EXPOSE_CD_US - EXPOSE_US: return false
	# Output window is derived from the single tide clock, never a free timer.
	var expected_output := 0
	if int(tide.tide_start_us) >= 0:
		var elapsed := now - int(tide.tide_start_us)
		var cycle := Tide.LOW + Tide.WARNING + Tide.HIGH
		if elapsed >= cycle and elapsed % cycle < OUTPUT_US: expected_output = now + OUTPUT_US - elapsed % cycle
	if int(value.output_until_us) != expected_output: return false
	if int(value.hp) == 0 and not tide.channel.is_empty(): return false
	_tide = candidate
	_hp = int(value.hp)
	_phase = int(value.phase)
	_exposed_until = int(value.exposed_until_us)
	_pillar_ready_at = int(value.pillar_ready_at_us)
	_output_until = int(value.output_until_us)
	return true
