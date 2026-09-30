class_name CombatStatus
extends RefCounted
## Snapshot status rules. A direct strike checks pre-hit states, then applies its own.
var states: Dictionary = {}
var shock_cooldown: float = 0.0
var clock: float = 0.0
var guards: Dictionary = {}
const SUPPLY_READY_PREFIX := "supply:ready:"
const SUPPLY_ACTIVE_PREFIX := "supply:active:"
const SUPPLY_GUARD_SECONDS := 4.0
const VALID_STATES: Array[String] = ["burn", "shock", "chill", "corrosion", "bleed", "grievous", "damage_reduction", "invulnerable"]

func apply(id: String, power: float, duration: float = -1.0, raw_power: float = -1.0) -> void:
	if id not in VALID_STATES or not is_finite(power) or not is_finite(duration):
		return
	var life: float = duration if duration > 0.0 else (4.0 if id == "corrosion" else 3.0)
	var old: Dictionary = states.get(id, {})
	var snapshot: float = maxf(0.0, power)
	if id == "damage_reduction":
		snapshot = clampf(snapshot, 0.0, 0.65)
	elif id in ["invulnerable", "grievous"]:
		snapshot = 1.0
	var raw_snapshot: float = power if raw_power < 0.0 else raw_power
	if is_equal_approx(float(old.get("applied_at", -1.0)), clock):
		if float(old.get("power", 0.0)) > snapshot:
			raw_snapshot = float(old.get("H", raw_snapshot))
		snapshot = maxf(snapshot, float(old.get("power", 0.0)))
	states[id] = {"remaining":life,"tick":float(old.get("tick", 0.0)),"power":snapshot,"H":raw_snapshot,"applied_at":clock}

func has(id: String) -> bool:
	return states.has(id) and float(states[id].remaining) > 0.0

func damage_modifiers() -> Dictionary:
	return {"damage_reduction":float(states.get("damage_reduction", {}).get("power", 0.0)) if has("damage_reduction") else 0.0,"invulnerable":has("invulnerable")}

func healing_multiplier() -> float:
	return 0.6 if has("grievous") else 1.0

func consume_shock() -> float:
	if not has("shock") or shock_cooldown > 0.0:
		return 0.0
	var damage: float = float(states.shock.power) * 0.25
	states.erase("shock")
	shock_cooldown = 1.0
	return damage

func tick(delta: float) -> Array[Dictionary]:
	if not is_finite(delta) or delta < 0.0:
		return []
	if delta == 0.0:
		# Depleted shields can be reconciled by HUD/snapshot callers without
		# advancing time or releasing any pending damage-over-time packets.
		tick_guard(0.0)
		return []
	clock += delta
	shock_cooldown = maxf(0.0, shock_cooldown - delta)
	var result: Array[Dictionary] = []
	for id: String in states.keys():
		var state: Dictionary = states[id]
		var step: float = minf(delta, float(state.remaining))
		state.remaining = maxf(0.0, float(state.remaining) - delta)
		if id in ["burn", "corrosion", "bleed"]:
			state.tick = float(state.tick) + step
			while float(state.tick) + 0.00001 >= 1.0:
				state.tick = maxf(0.0, float(state.tick) - 1.0)
				var coefficient: float = {"burn":0.12,"corrosion":0.08,"bleed":0.10}[id]
				result.append({"kind":id,"damage":float(state.power) * coefficient,"damage_type":"magic" if id == "burn" else "physical","H":float(state.H)})
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
		# A purchased reserve protects the next room's first actual contact.
		# Looking around or walking to that encounter does not spend its timer.
		if not is_prepared_supply_guard(source):
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
	activate_prepared_guards(guards, consumed)
	for source: String in guards:
		guards[source].amount = maxf(0.0, float(guards[source].amount) - consumed)
	return amount - consumed

static func is_prepared_supply_guard(source: String) -> bool:
	if not source.begins_with(SUPPLY_READY_PREFIX): return false
	var index: String = source.trim_prefix(SUPPLY_READY_PREFIX)
	return index.is_valid_int() and int(index) >= 0 and str(int(index)) == index

static func activate_prepared_guards(pools: Dictionary, absorbed: float) -> void:
	if not is_finite(absorbed) or absorbed <= 0.0: return
	for source: String in pools.keys():
		if not is_prepared_supply_guard(source): continue
		var guard: Dictionary = pools[source]
		pools.erase(source)
		pools[SUPPLY_ACTIVE_PREFIX + source.trim_prefix(SUPPLY_READY_PREFIX)] = guard
