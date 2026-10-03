extends RefCounted
## Room-local simulation. No player data, global clocks, RNG or reward writes.
const CHANNEL := 0.6
const WARNING := 1.0
const TAILWIND_WINDOW := 4.0
const TAILWIND_ICD := 10.0
var now := 0.0
var lanes: Dictionary = {}
var channel: Dictionary = {}
var pending: Dictionary = {}
var boons: Dictionary = {}
var displacement_until: Dictionary = {}
var suppressed_until := 0.0
var counter_ready := false
var counter_until := 0.0
var counter_icd_until := 0.0
var dive_owner := ""

func configure(ids: Array) -> bool:
	if not lanes.is_empty() or ids.is_empty() or ids.size() > 3: return false
	for id: Variant in ids:
		if not id is String or id.is_empty() or lanes.has(id):
			lanes.clear()
			return false
		lanes[id] = 0
	return true

func begin_turn(lane: String, actor: String) -> bool:
	if not lanes.has(lane) or actor.is_empty() or not channel.is_empty() or not pending.is_empty(): return false
	channel = {"lane":lane,"actor":actor,"remaining":CHANNEL}
	return true

func cancel_turn() -> void: channel.clear()

func advance(delta: float, paused: bool = false) -> Array:
	if paused or not is_finite(delta) or delta < 0 or delta > 60: return []
	var events: Array = []
	now += delta
	# Spend overshoot against the next state so frame rate cannot shorten/extend it.
	var rest := delta
	if not channel.is_empty():
		var spent := minf(rest,float(channel.remaining))
		channel.remaining -= spent
		rest -= spent
		if float(channel.remaining) <= 0.000001:
			pending = {"lane":channel.lane,"mode":(int(lanes[channel.lane])+1)%3,"remaining":WARNING}
			events.append({"kind":"turn_warning","lane":channel.lane,"mode":pending.mode})
			channel.clear()
	if not pending.is_empty():
		pending.remaining -= rest
		if float(pending.remaining) <= 0.000001:
			lanes[pending.lane] = int(pending.mode)
			if int(pending.mode) == 2 and now >= counter_icd_until:
				counter_ready = true
				counter_until = now + 12.0
			events.append({"kind":"turn_completed","lane":pending.lane,"mode":pending.mode})
			pending.clear()
	return events

func direction(lane: String, authored: Vector2) -> Vector2:
	if not lanes.has(lane): return Vector2.ZERO
	return [authored,-authored,authored.orthogonal()][int(lanes[lane])].normalized()

func movement(lane: String, authored: Vector2, motion: Vector2) -> float:
	if not lanes.has(lane) or motion.length_squared() < 0.0001: return 1.0
	var alignment := motion.normalized().dot(direction(lane,authored))
	return 1.2 if alignment > 0.25 else 0.9 if alignment < -0.25 else 1.0

func grant_tailwind(actor: String, lane: String, completed_warned_move: bool, distance: float) -> bool:
	if actor.is_empty() or not lanes.has(lane) or not completed_warned_move or not is_finite(distance) or distance < 30 or now < suppressed_until: return false
	var previous: Dictionary = boons.get(actor,{})
	if now < float(previous.get("icd_until",0)): return false
	boons[actor] = {"expires":now+TAILWIND_WINDOW,"icd_until":now+TAILWIND_ICD,"available":true}
	return true

func consume_tailwind(actor: String, unlocked_active: bool, harmful: bool) -> float:
	if not unlocked_active or not harmful or now < suppressed_until: return 1.0
	var boon: Dictionary = boons.get(actor,{})
	if not bool(boon.get("available",false)) or now >= float(boon.get("expires",0)): return 1.0
	boon.available = false
	return 1.12

func break_flag() -> void:
	suppressed_until = now + 8.0
	# Existing charges are invalidated, not banked until suppression ends.
	for boon: Dictionary in boons.values(): boon.available = false

func admit_dive(actor: String) -> bool:
	if actor.is_empty() or not dive_owner.is_empty(): return false
	dive_owner = actor
	return true

func release_dive(actor: String) -> void:
	if dive_owner == actor: dive_owner = ""

func admit_displacement(actor: String) -> bool:
	if actor.is_empty() or now < float(displacement_until.get(actor,0)): return false
	displacement_until[actor] = now + 2.0
	return true

func consume_boss_counter() -> bool:
	if not counter_ready or now >= counter_until or now < counter_icd_until: return false
	counter_ready = false
	counter_icd_until = now + 12.0
	return true
