class_name B06EquipmentEffects
extends RefCounted
## Pure B06 extension. Geometry, source-shield receipts and actually emitted
## projectiles come from the loadout adapter; this file never accesses nodes.
## All durable state lives in EquipmentEffects' existing scalar state maps.

const Numerical = preload("res://config/numerical_rules.gd")
const PERIOD_KEY := "B06-SU_4:period"
const PERIOD := 12.0

static func modifiers(e: Variant, ctx: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(e.stats): return
	var displacement: float = float(out.get("received_displacement_reduction", 0.0))
	if e._has_set("B06-SW", 2) and bool(ctx.get("e_shield_active", false)):
		displacement += 0.25
	if e._has_set("B06-SU", 2): displacement += 0.20
	out["received_displacement_reduction"] = clampf(displacement, 0.0, 0.50)
	var terrain: float = float(out.get("terrain_slow_reduction", 0.0))
	if e._has("B06-U01"): terrain += 0.20
	out["terrain_slow_reduction"] = clampf(terrain, 0.0, 0.50)
	if e._has("B06-U02") and e._window("B06-U02:healing"):
		out["received_healing_bonus"] = float(out.get("received_healing_bonus", 0.0)) + 0.08
	if e._has_set("B06-SM", 2) and bool(ctx.get("immediate_w_burst", false)):
		out["immediate_w_radius_scale"] = float(out.get("immediate_w_radius_scale", 1.0)) * 1.10

static func advance(e: Variant, delta: float, ctx: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(e.stats) or delta <= 0.0 or not is_finite(delta): return
	if bool(ctx.get("combat_active", false)):
		e.windows["B06-combat"] = e.clock + 10.0
	elif e.windows.has("B06-combat") and not e._window("B06-combat"):
		e.clear_b06_temporary()
	if not e._has_set("B06-SU", 4): return
	# This one cooldown entry is REMAINING COMBAT TIME, not a clock deadline.
	# Existing cooldown migration preserves it through swaps and checkpoints.
	# Time outside combat, death and unequipped intervals cannot earn a shield.
	if not e.cooldowns.has(PERIOD_KEY): e.cooldowns[PERIOD_KEY] = PERIOD
	if not bool(ctx.get("combat_active", false)) or float(ctx.get("hp", 0.0)) <= 0.0: return
	var remaining: float = clampf(float(e.cooldowns[PERIOD_KEY]), 0.0, PERIOD) - delta
	if remaining > 0.000001:
		e.cooldowns[PERIOD_KEY] = remaining
		return
	# Retain cadence, but never mint a backlog of shields after one large tick.
	e.cooldowns[PERIOD_KEY] = PERIOD + fposmod(remaining, PERIOD)
	if float(e.cooldowns[PERIOD_KEY]) > PERIOD: e.cooldowns[PERIOD_KEY] -= PERIOD
	out.triggered.append("B06-SU_4")
	e._shield(out, ctx, 0.06, "B06-SU_4")

static func event(e: Variant, event_name: String, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(e.stats): return
	var slot: String = str(ctx.get("skill_slot", ctx.get("slot", "")))
	match event_name:
		"before_hit":
			if e._eligible(ctx): _before_hit(e, ctx, root, out, slot)
		"after_hit":
			if e._eligible(ctx) and bool(ctx.get("confirmed", false)):
				# V2 previews use copied state. Commit only a real health/shield loss.
				_before_hit(e, ctx, root, e._empty(), slot)
				_after_hit(e, ctx, root, out, slot)
		"skill_cast": _skill_cast(e, ctx, root, out, slot)
		"damaged":
			var absorbed: float = float(ctx.get("shield_absorbed", 0.0))
			if absorbed <= 0.0 or not is_finite(absorbed): return
			if e._has_set("B06-SW", 6) and e._ready("B06-SW_6"):
				e.windows["B06-SW_6:counter"] = e.clock + 6.0
			if e._has("B06-U02") and e._activate("B06-U02", 12.0, root, out, false):
				e.windows["B06-U02:healing"] = e.clock + 4.0
		"gunner_q_completed":
			var distance: float = float(ctx.get("actual_distance", 0.0))
			if e._has_set("B06-SG", 4) and _original_event(ctx) and is_finite(distance) and distance > 0.0:
				e.windows["B06-SG_4:shift"] = e.clock + 4.0
		"gunner_r_shot": _r_shot(e, ctx, root, out)
		"mage_w_burst_completed": _mage_burst(e, ctx, root, out)
		"b06_ring_due":
			if not e._has_set("B06-SM", 6) or not bool(root.get("b06_ring_reserved", false)) or bool(root.get("b06_ring_released", false)): return
			root["b06_ring_released"] = true
			_packet(e, ctx, root, out, "B06-SM_6:ring", 0.45, ctx.get("b06_ring_targets", []), 4, "magic", float(root.get("b06_ring_damage", 0.0)), true)
		"shield_source_ended":
			var source: String = str(ctx.get("source", "")).trim_prefix("equipment:").trim_prefix("set_")
			if e._has_set("B06-SU", 6) and source == "B06-SU_4" and str(ctx.get("cause", "")) in ["expired", "absorbed"] and e._ready("B06-SU_6"):
				e.windows["B06-SU_6:ended"] = e.clock + 6.0
		"combat_mechanism_completed":
			if e._has("B06-U03") and bool(ctx.get("completed", false)) and bool(ctx.get("combat_active", false)) and e._activate("B06-U03", 15.0, root, out):
				e._shield(out, ctx, 0.04, "B06-U03")
				out.shields.back().duration = 3.0

static func _before_hit(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	if slot != "secondary": return
	var target: String = str(ctx.get("target_id", ""))
	if e._has_set("B06-SG", 2) and not target.is_empty() and (str(root.first_target).is_empty() or str(root.first_target) == target):
		out.damage_bonus += 0.08
	if e._has_set("B06-SM", 4) and bool(ctx.get("immediate_w_burst", false)):
		if not root.flags.has("B06-SM_4:burst"):
			root.flags["B06-SM_4:burst"] = e._window("B06-SM_4:burst")
			e.windows.erase("B06-SM_4:burst")
		if bool(root.flags["B06-SM_4:burst"]): out.damage_bonus += 0.12

static func _after_hit(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	var target: String = str(ctx.get("target_id", ""))
	if target.is_empty(): return
	if slot in ["q", "secondary"] and e._has_set("B06-SW", 6) and e._window("B06-SW_6:counter") and not bool(root.get("b06_wave_used", false)):
		root["b06_wave_used"] = true
		e.windows.erase("B06-SW_6:counter")
		if e._activate("B06-SW_6", 8.0, root, out):
			_packet(e, ctx, root, out, "B06-SW_6", 0.40, ctx.get("b06_wave_targets", []), 3, "physical", -1.0, true)
	if slot == "secondary":
		if e._has_set("B06-SW", 4) and e._window("B06-SW_4:e") and not bool(root.get("b06_sw4_used", false)):
			root["b06_sw4_used"] = true
			e.windows.erase("B06-SW_4:e")
			var paid: float = float(ctx.get("paid_cost", 0.0))
			if is_finite(paid) and paid > 0.0 and str(ctx.get("resource_type", e.resource_type)) == "rage" and e._activate("B06-SW_4", 8.0, root, out, false):
				var missing: float = maxf(0.0, float(ctx.get("resource_max", e.stats.get("resource_max", 0.0))) - float(ctx.get("resource", 0.0)) - float(out.resource_restore))
				out.resource_restore += minf(float(Numerical.integer(paid * 0.15)), missing)
		if e._has_set("B06-SG", 4) and e._window("B06-SG_4:shift") and bool(ctx.get("hunter_marked", false)) and not bool(root.get("b06_sg4_used", false)):
			root["b06_sg4_used"] = true
			e.windows.erase("B06-SG_4:shift")
			if e._activate("B06-SG_4", 7.0, root, out, false):
				var remaining: float = maxf(0.0, float(ctx.get("remaining_cooldowns", {}).get("F", 0.0)))
				for pending: Dictionary in out.cooldown_refunds:
					if str(pending.get("slot", "")) == "F": remaining = maxf(0.0, remaining - float(pending.get("seconds", 0.0)))
				if remaining > 0.0: out.cooldown_refunds.append({"slot":"F", "seconds":minf(1.0, remaining), "source":"equipment", "effect_id":"B06-SG_4"})
		if e._has_set("B06-SG", 6):
			if not root.has("b06_w_targets"): root["b06_w_targets"] = []
			if root.b06_w_targets.size() < 2 and target not in root.b06_w_targets: root.b06_w_targets.append(target)
			if root.b06_w_targets.size() >= 2 and not bool(root.get("b06_tide_mark_created", false)):
				root["b06_tide_mark_created"] = true
				out["b06_tide_mark"] = {"target_id":str(root.b06_w_targets[0]), "duration":6.0}
	if slot == "f" and e._has_set("B06-SM", 4) and not bool(root.get("b06_sm4_armed", false)):
		root["b06_sm4_armed"] = true
		if e._activate("B06-SM_4", 8.0, root, out, false): e.windows["B06-SM_4:burst"] = e.clock + 6.0
	if e._has_set("B06-SU", 6) and e._window("B06-SU_6:ended") and not _shared_power_type(e, ctx).is_empty() and not bool(root.get("b06_su6_used", false)):
		root["b06_su6_used"] = true
		e.windows.erase("B06-SU_6:ended")
		if e._activate("B06-SU_6", 12.0, root, out):
			e._buff("B06-SU_6", "move_speed_bonus", 0.08, 3.0)
			_packet(e, ctx, root, out, "B06-SU_6", 0.25, [target], 1, _shared_power_type(e, ctx), -1.0, true)

static func _skill_cast(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	if not _original_event(ctx) or not bool(ctx.get("cast_success", false)): return
	if slot == "f" and e._has_set("B06-SW", 4) and not bool(root.get("b06_e_counted", false)):
		root["b06_e_counted"] = true
		e.windows["B06-SW_4:e"] = e.clock + 4.0
	if slot == "q" and e._has_set("B06-SM", 6) and e._paid_spell_cast(ctx) and bool(ctx.get("combat_active", false)) and not bool(root.get("b06_q_paid_counted", false)):
		root["b06_q_paid_counted"] = true
		e.counts["B06-SM_6:q"] = mini(3, int(e.counts.get("B06-SM_6:q", 0)) + 1)

static func _r_shot(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not e._has_set("B06-SG", 6) or not _original_event(ctx): return
	var ordinal: int = int(ctx.get("r_shot_ordinal", 0))
	if ordinal < 1 or ordinal > 3: return
	if not root.has("b06_r_target"):
		# Only a real first shot can bind/consume a mark. A skipped or cancelled
		# first round cannot be fabricated by receiving a later ordinal.
		var target: String = str(ctx.get("target_id", ""))
		if ordinal != 1 or target.is_empty() or not bool(ctx.get("b06_tide_marked", false)): return
		if not e._activate("B06-SG_6", 12.0, root, out): return
		root["b06_r_target"] = target
		root["b06_r_ordinals"] = []
		root["b06_r_power"] = _power(e, ctx, "physical")
		_prime_budget(e, ctx, root, float(root.b06_r_power))
	if ordinal in root.b06_r_ordinals: return
	root.b06_r_ordinals.append(ordinal)
	var packet_out: Dictionary = {"bonus_hits":[]}
	_packet(e, ctx, root, packet_out, "B06-SG_6", 0.12, [str(root.b06_r_target)], 1, "physical", float(Numerical.integer(float(root.b06_r_power) * 0.12)), true)
	if packet_out.bonus_hits.is_empty(): return
	var packet: Dictionary = packet_out.bonus_hits[0]
	packet["target_id"] = str(root.b06_r_target)
	packet["damage"] = int(packet.damage_by_target[packet.target_id])
	packet["r_shot_ordinal"] = ordinal
	out["b06_r_bonus"] = packet

static func _mage_burst(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not e._has_set("B06-SM", 6) or not _original_event(ctx) or int(e.counts.get("B06-SM_6:q", 0)) < 3 or bool(root.get("b06_ring_reserved", false)): return
	if not e._activate("B06-SM_6", 10.0, root, out): return
	e.counts["B06-SM_6:q"] = 0
	var power: float = _power(e, ctx, "magic")
	_prime_budget(e, ctx, root, power)
	root["b06_ring_reserved"] = true
	root["b06_ring_damage"] = Numerical.integer(power * 0.45)
	out["b06_ring"] = {"delay":0.8, "radius":110.0, "damage":int(root.b06_ring_damage), "root_event_id":str(ctx.get("root_event_id", ctx.get("attack_id", ctx.get("event_id", "")))), "burst_position":ctx.get("burst_position", Vector2.ZERO), "source":"equipment", "damage_source":"equipment", "damage_type":"magic", "proc_depth":1, "equipment_eligible":false, "critical":false}

static func _original_event(ctx: Dictionary) -> bool:
	return int(ctx.get("proc_depth", 0)) == 0 and bool(ctx.get("equipment_eligible", true)) and str(ctx.get("damage_source", "skill")) in ["primary", "basic", "skill"]

static func _shared_power_type(e: Variant, ctx: Dictionary) -> String:
	var explicit: String = str(ctx.get("b06_shared_power_type", e.stats.get("b06_shared_power_type", "")))
	if explicit in ["physical", "magic"]: return explicit
	# Shared instances retain their original AD/AP orientation across classes.
	# Mixed orientation has no defined tie-break, so preserve the token rather
	# than silently choosing a class or consuming an unresolved effect.
	return ""

static func _power(e: Variant, ctx: Dictionary, power_type: String) -> float:
	var power_stats: Dictionary = ctx.get("attacker_stats", e.stats)
	var value: float = float(power_stats.get("ability_power" if power_type == "magic" else "attack", 0.0))
	return maxf(0.0, value) if is_finite(value) else 0.0

static func _prime_budget(_e: Variant, ctx: Dictionary, root: Dictionary, power: float) -> void:
	if not root.has("raw_packet"):
		root["raw_packet"] = Numerical.integer(float(ctx.get("X", ctx.get("H", 0.0))))
		root["damage_spent"] = int(floor(float(root.raw_packet) * float(root.coefficient)))
	root["b06_budget_basis"] = maxf(float(root.get("b06_budget_basis", 0.0)), maxf(float(root.raw_packet), power))

## All B06 damage shares the existing original cast's four-package / 1.2X
## budget (fixed-P effects use max(original X, fixed P), as B05 does).
## A delayed ring / actual R shot cannot invent a new independent budget.
static func _packet(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, id: String, coefficient: float, targets: Array, limit: int, power_type: String, frozen_damage: float = -1.0, reserved: bool = false) -> void:
	var power: float = _power(e, ctx, power_type)
	var amount: int = Numerical.integer(power * coefficient) if frozen_damage < 0.0 else Numerical.integer(frozen_damage)
	if amount <= 0 or targets.is_empty(): return
	if frozen_damage < 0.0: _prime_budget(e, ctx, root, power)
	elif not root.has("b06_budget_basis"): return
	var ids: Array[String] = []
	for value: Variant in targets:
		var target: String = str(value)
		if target.is_empty() or target in ids: continue
		ids.append(target)
		if ids.size() >= limit: break
	if ids.is_empty(): return
	var remaining: int = maxi(0, int(Numerical.derived_budget(float(root.b06_budget_basis), Numerical.V2)) - int(root.get("damage_spent", 0)))
	var amounts: Dictionary = {}
	var spent: int = 0
	for target: String in ids:
		var damage: int = mini(amount, remaining)
		if damage <= 0: break
		amounts[target] = damage
		remaining -= damage
		spent += damage
	if spent <= 0: return
	if not reserved and not e._activate(id, 0.0, root, out): return
	root["damage_spent"] = int(root.get("damage_spent", 0)) + spent
	root.coefficient = float(root.damage_spent) / maxf(1.0, float(root.raw_packet))
	ids.assign(amounts.keys())
	out.bonus_hits.append({"target_ids":ids, "damage":amount, "damage_by_target":amounts, "coefficient":coefficient, "source":"equipment", "damage_source":"equipment", "damage_type":power_type, "proc_depth":1, "equipment_eligible":false, "original_basic":false, "critical":false, "states":[], "effect_id":id})
