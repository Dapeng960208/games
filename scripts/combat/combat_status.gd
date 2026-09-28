class_name CombatStatus
extends RefCounted
## Snapshot status rules. A direct strike checks pre-hit states, then applies its own.
var states: Dictionary = {}
var shock_cooldown: float = 0.0
var clock: float = 0.0
var guards: Dictionary = {}

func apply(id: String, power: float, duration: float = -1.0, raw_power: float = -1.0) -> void:
	if id not in ["burn", "shock", "chill", "corrosion"]:
		return
	var life: float = duration if duration > 0.0 else (4.0 if id == "corrosion" else 3.0)
	var old: Dictionary = states.get(id, {})
	var snapshot: float = maxf(0.0, power)
	var raw_snapshot: float = power if raw_power < 0.0 else raw_power
	if is_equal_approx(float(old.get("applied_at", -1.0)), clock):
		if float(old.get("power", 0.0)) > snapshot:
			raw_snapshot = float(old.get("H", raw_snapshot))
		snapshot = maxf(snapshot, float(old.get("power", 0.0)))
	states[id] = {"remaining":life,"tick":float(old.get("tick", 0.0)),"power":snapshot,"H":raw_snapshot,"applied_at":clock}

func has(id: String) -> bool:
	return states.has(id) and float(states[id].remaining) > 0.0

func consume_shock() -> float:
	if not has("shock") or shock_cooldown > 0.0:
		return 0.0
	var damage: float = float(states.shock.power) * 0.25
	states.erase("shock")
	shock_cooldown = 1.0
	return damage

func tick(delta: float) -> Array[Dictionary]:
	clock += delta
	shock_cooldown = maxf(0.0, shock_cooldown - delta)
	var result: Array[Dictionary] = []
	for id: String in states.keys():
		var state: Dictionary = states[id]
		var step: float = minf(delta, float(state.remaining))
		state.remaining = maxf(0.0, float(state.remaining) - delta)
		if id in ["burn", "corrosion"]:
			state.tick = float(state.tick) + step
			while float(state.tick) + 0.00001 >= 1.0:
				state.tick = maxf(0.0, float(state.tick) - 1.0)
				result.append({"kind":id,"damage":float(state.power) * (0.12 if id == "burn" else 0.08),"H":float(state.H)})
		if float(state.remaining) <= 0.0:
			states.erase(id)
	tick_guard(delta)
	return result

func grant_guard(amount: float, duration: float, source: String, maximum: float, equipment: bool = false) -> bool:
	var before: float = shield()
	var old: Dictionary = guards.get(source, {})
	guards[source] = {"remaining":duration,"amount":minf(maxf(float(old.get("amount", 0.0)), amount), maximum * (0.35 if equipment else 0.5))}
	return shield() > before

func tick_guard(delta: float) -> void:
	for source: String in guards.keys():
		guards[source].remaining = float(guards[source].remaining) - delta
		if float(guards[source].remaining) <= 0.0 or float(guards[source].amount) <= 0.0:
			guards.erase(source)

func shield() -> float:
	var value: float = 0.0
	for source: String in guards:
		value = maxf(value, float(guards[source].amount))
	return value

func absorb(amount: float) -> float:
	var consumed: float = minf(shield(), maxf(0.0, amount))
	for source: String in guards:
		guards[source].amount = maxf(0.0, float(guards[source].amount) - consumed)
	return amount - consumed
