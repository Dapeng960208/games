class_name B10EquipmentEffects
extends RefCounted
## Final-court rules use confirmed original casts/hits and the shared cast budget.
## Temporary counters fit the existing scalar checkpoint maps; ICDs survive swaps.
const Numerical = preload("res://scripts/infrastructure/content/runtime_rules.gd")

static func modifiers(e: Variant, _ctx: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(e.stats): return
	out["b10_ranged_damage_reduction"] = 0.06 if e._has_set("B10-SU", 2) else 0.0
	out["b10_direct_damage_reduction"] = (0.08 if e._window("B10-SU_6:balance") else 0.0) + (0.06 if e._window("B10-U03:recovery") else 0.0)
	if e._window("B10-SU_6:balance"): out.move_speed_bonus += 0.08
	if e._window("B10-SU_4:discount"): out.cost_reduction += 0.08

static func advance(e: Variant, delta: float, ctx: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(e.stats) or delta <= 0.0 or not is_finite(delta): return
	if bool(ctx.get("combat_active", false)):
		e.windows["B10-combat"] = e.clock + 10.0
	elif e.windows.has("B10-combat") and not e._window("B10-combat"):
		e.clear_b10_temporary()
	if not e._has_set("B10-SU", 6) or not bool(ctx.get("combat_active", false)): return
	var distance: float = float(ctx.get("actual_movement_distance", 0.0))
	if distance <= 0.0 or not is_finite(distance) or bool(ctx.get("teleported", false)): return
	if not e._window("B10-SU_6:movement"):
		e.counts["B10-SU_6:distance"] = 0
		e.windows["B10-SU_6:movement"] = e.clock + 10.0
	e.counts["B10-SU_6:distance"] = mini(160000, int(e.counts.get("B10-SU_6:distance", 0)) + maxi(0, Numerical.integer(distance * 1000.0)))
	_balance(e, ctx, e._root("b10_move:" + str(e.clock)), out)

static func event(e: Variant, name: String, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not Numerical.is_v2(e.stats): return
	var slot: String = e.skill_origin(ctx)
	match name:
		"before_hit":
			if e._eligible(ctx): _before_hit(e, ctx, root, out, slot)
		"after_hit":
			if e._eligible(ctx) and bool(ctx.get("confirmed", false)):
				_before_hit(e, ctx, root, e._empty(), slot)
				_after_hit(e, ctx, root, out, slot)
		"skill_cast": _cast(e, ctx, root, out, slot)
		"gunner_q_completed":
			var distance: float = float(ctx.get("actual_distance", 0.0))
			if slot == "q" and e.resource_type == "energy" and e._has_set("B10-SG", 6) and _original(ctx) and is_finite(distance) and distance > 0.0 and not bool(ctx.get("teleported", false)):
				e.windows["B10-SG_6:q"] = e.clock + 8.0
		"gunner_r_shot": _r_shot(e, ctx, root, out)
		"damaged":
			if e._has_set("B10-SU", 4) and bool(ctx.get("enemy_damage", false)) and bool(ctx.get("shield_broken", false)) and float(ctx.get("shield_absorbed", 0.0)) > 0.0 and e._activate("B10-SU_4", 12.0, root, out, false):
				e.windows["B10-SU_4:discount"] = e.clock + 6.0
		"ordinary_slow_ended":
			if e._has("B10-U01") and bool(ctx.get("actually_slowed", false)) and not bool(ctx.get("boss_marker", false)) and e._ready("B10-U01"):
				e.windows["B10-U01:dash"] = e.clock + 300.0
		"dash":
			if e._has("B10-U01") and e._window("B10-U01:dash"):
				e._refund(out, ctx, root, "B10-U01", 12.0, "dash", 0.5)
				if not out.cooldown_refunds.is_empty(): e.windows.erase("B10-U01:dash")
		"hostile_shield_broken", "hostile_destructible_destroyed":
			if e._has("B10-U02") and bool(ctx.get("player_attributed", false)) and e._activate("B10-U02", 12.0, root, out): e._shield(out, ctx, 0.03, "B10-U02")
		"ordinary_forced_movement_ended":
			if e._has("B10-U03") and bool(ctx.get("actual_enemy_forced_movement", false)) and not bool(ctx.get("boss_marker", false)) and not bool(ctx.get("teleported", false)) and e._activate("B10-U03", 15.0, root, out, false):
				e.windows["B10-U03:recovery"] = e.clock + 4.0

static func _before_hit(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	if slot == "q" and (e._has_set("B10-SW", 2) or e._has_set("B10-SM", 2)): out.damage_bonus += 0.08
	var target: String = str(ctx.get("target_id", ""))
	if slot == "secondary":
		if e._has_set("B10-SG", 2) and not target.is_empty() and (str(root.first_target).is_empty() or str(root.first_target) == target): out.damage_bonus += 0.08
		if e._has_set("B10-SW", 6):
			if not root.flags.has("B10-SW_6:stacks"):
				root.flags["B10-SW_6:stacks"] = int(e.counts.get("B10-SW_6:pending", 0)) if e._window("B10-SW_6:w") else 0
				if int(root.flags["B10-SW_6:stacks"]) > 0:
					e.windows.erase("B10-SW_6:w")
					e.counts.erase("B10-SW_6:pending")
			out.damage_bonus += int(root.flags["B10-SW_6:stacks"]) * 0.08

static func _after_hit(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	var target: String = str(ctx.get("target_id", ""))
	if target.is_empty(): return
	if e._has_set("B10-SW", 4):
		if slot == "q": e.windows["B10-SW_4:q:" + target] = e.clock + 4.0
		elif slot == "secondary" and not bool(root.get("b10_oath_counted", false)) and e._window("B10-SW_4:q:" + target):
			root["b10_oath_counted"] = true
			e.windows.erase("B10-SW_4:q:" + target)
			var stacks: int = int(e.counts.get("B10-SW_4:stacks", 0)) if e._window("B10-SW_4:oath") else 0
			e.counts["B10-SW_4:stacks"] = mini(2, stacks + 1)
			e.windows["B10-SW_4:oath"] = e.clock + 8.0
	if slot == "secondary" and e._has_set("B10-SW", 6) and int(root.flags.get("B10-SW_6:stacks", 0)) > 0 and not bool(root.get("b10_oath_shield", false)):
		root["b10_oath_shield"] = true
		e._shield(out, ctx, int(root.flags["B10-SW_6:stacks"]) * 0.03, "B10-SW_6")
	if e._has_set("B10-SG", 4):
		if slot == "f" and e._ready("B10-SG_4") and (str(root.first_target).is_empty() or str(root.first_target) == target):
			e.windows["B10-SG_4:mark:" + target] = e.clock + 6.0
		elif slot == "secondary" and e._window("B10-SG_4:mark:" + target) and e._activate("B10-SG_4", 8.0, root, out):
			e.windows.erase("B10-SG_4:mark:" + target)
			_packet(e, ctx, root, out, "B10-SG_4", 0.30, [target], 1, "physical", true)
	if e._has_set("B10-SG", 6):
		if slot == "f" and e._window("B10-SG_6:q"): e.windows["B10-SG_6:e:" + target] = e.clock + 8.0
		elif slot == "secondary" and e._window("B10-SG_6:q") and e._window("B10-SG_6:e:" + target) and e._ready("B10-SG_6"):
			# Only one pending target. Its identity stays in a scalar window key.
			for key: String in e.windows.keys():
				if key.begins_with("B10-SG_6:ready:"): e.windows.erase(key)
			e.windows["B10-SG_6:ready:" + target] = e.clock + 6.0
			e.windows.erase("B10-SG_6:q")
			e.windows.erase("B10-SG_6:e:" + target)
	if e._has_set("B10-SM", 6) and slot in ["q", "ultimate"] and e._window("B10-SM_6:burst") and not bool(root.get("b10_star_burst", false)):
		# The first actual segment consumes once; later R ticks cannot repeat it.
		root["b10_star_burst"] = true
		e.windows.erase("B10-SM_6:burst")
		var targets: Array = [target]
		for candidate: Dictionary in ctx.get("nearby_targets", []):
			if bool(candidate.get("alive", true)) and float(candidate.get("distance", 10000.0)) <= 110.0: targets.append(str(candidate.get("id", "")))
		_packet(e, ctx, root, out, "B10-SM_6:burst", 0.60, targets, 3, "magic")
	if e._has_set("B10-SU", 6):
		e.windows["B10-SU_6:hit"] = e.clock + 10.0
		_balance(e, ctx, root, out)

static func _cast(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, slot: String) -> void:
	var skill: String = str(ctx.get("skill_id", ""))
	if skill.is_empty(): skill = e.canonical_skill_id(ctx, slot)
	if not _original(ctx) or not bool(ctx.get("cast_success", false)) or e._skill_index({"skill_id":skill}) == 0 or bool(root.get("b10_cast_counted", false)): return
	root["b10_cast_counted"] = true
	var paid: float = float(ctx.get("paid_cost", 0.0))
	if e._has_set("B10-SU", 4) and is_finite(paid) and paid > 0.0: e.windows.erase("B10-SU_4:discount")
	if e._has_set("B10-SW", 6) and slot == "f" and e._window("B10-SW_4:oath") and int(e.counts.get("B10-SW_4:stacks", 0)) > 0 and e._activate("B10-SW_6", 12.0, root, out, false):
		e.counts["B10-SW_6:pending"] = mini(2, int(e.counts["B10-SW_4:stacks"]))
		e.windows["B10-SW_6:w"] = e.clock + 6.0
		e.counts.erase("B10-SW_4:stacks")
		e.windows.erase("B10-SW_4:oath")
	if e._has_set("B10-SM", 4) and e.resource_type == "mana" and is_finite(paid) and paid > 0.0 and bool(ctx.get("combat_active", false)):
		e.windows["B10-SM_4:spell:" + skill] = e.clock + 8.0
		e.counts["B10-SM_4:cost:" + skill] = Numerical.integer(paid)
		var spells: Array[String] = []
		var spent := 0
		for index in range(1, 13):
			var id: String = "CH03_SK%02d" % index
			if e._window("B10-SM_4:spell:" + id):
				spells.append(id)
				spent += int(e.counts.get("B10-SM_4:cost:" + id, 0))
		var refund: int = Numerical.scale(80.0, Numerical.V2)
		if spells.size() >= 3 and spent > refund:
			for id: String in spells:
				e.windows.erase("B10-SM_4:spell:" + id)
				e.counts.erase("B10-SM_4:cost:" + id)
			if e._activate("B10-SM_4", 10.0, root, out, false): out.resource_restore += mini(refund, maxi(0, Numerical.integer(float(ctx.get("resource_max", 0.0)) - float(ctx.get("resource", 0.0)))))
			if e._has_set("B10-SM", 6) and e._activate("B10-SM_6", 12.0, root, out, false): e.windows["B10-SM_6:burst"] = e.clock + 6.0
	if e._has_set("B10-SU", 6) and bool(ctx.get("combat_active", false)):
		e.windows["B10-SU_6:cast"] = e.clock + 10.0
		_balance(e, ctx, root, out)

static func _balance(e: Variant, _ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	if not e._has_set("B10-SU", 6) or not e._window("B10-SU_6:movement") or int(e.counts.get("B10-SU_6:distance", 0)) < 160000 or not e._window("B10-SU_6:hit") or not e._window("B10-SU_6:cast"): return
	if not e._activate("B10-SU_6", 12.0, root, out, false): return
	e.windows["B10-SU_6:balance"] = e.clock + 4.0
	for key: String in ["B10-SU_6:movement", "B10-SU_6:hit", "B10-SU_6:cast"]: e.windows.erase(key)
	e.counts.erase("B10-SU_6:distance")

static func _r_shot(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary) -> void:
	var ordinal := int(ctx.get("r_shot_ordinal", 0))
	if e.skill_origin(ctx) != "ultimate" or e.resource_type != "energy" or not e._has_set("B10-SG", 6) or not _original(ctx) or ordinal < 1 or ordinal > 3: return
	if not root.has("b10_r_target"):
		if ordinal != 1: return
		var target := ""
		for key: String in e.windows:
			if key.begins_with("B10-SG_6:ready:") and e._window(key):
				target = key.trim_prefix("B10-SG_6:ready:")
				break
		if target.is_empty() or not e._activate("B10-SG_6", 12.0, root, out): return
		e.windows.erase("B10-SG_6:ready:" + target)
		root["b10_r_target"] = target
		root["b10_r_ordinals"] = []
	if ordinal in root.b10_r_ordinals: return
	root.b10_r_ordinals.append(ordinal)
	var packet_out: Dictionary = {"bonus_hits":[]}
	_packet(e, ctx, root, packet_out, "B10-SG_6", 0.18, [str(root.b10_r_target)], 1, "physical", true)
	if packet_out.bonus_hits.is_empty(): return
	var packet: Dictionary = packet_out.bonus_hits[0]
	packet["target_id"] = str(root.b10_r_target)
	packet["damage"] = int(packet.damage_by_target[packet.target_id])
	packet["r_shot_ordinal"] = ordinal
	out["b10_r_bonus"] = packet

static func _original(ctx: Dictionary) -> bool:
	return int(ctx.get("proc_depth", 0)) == 0 and bool(ctx.get("equipment_eligible", false)) and bool(ctx.get("original", true)) and not bool(ctx.get("derived", false)) and str(ctx.get("damage_source", ctx.get("source", "skill"))) in ["primary", "basic", "skill"]

static func _packet(e: Variant, ctx: Dictionary, root: Dictionary, out: Dictionary, id: String, coefficient: float, targets: Array, limit: int, power_type: String, reserved: bool = false) -> void:
	var power_stats: Dictionary = ctx.get("attacker_stats", e.stats)
	var power: float = float(power_stats.get("ability_power" if power_type == "magic" else "attack", 0.0))
	if not is_finite(power) or power <= 0.0: return
	if not root.has("raw_packet"):
		root["raw_packet"] = Numerical.integer(float(ctx.get("X", ctx.get("H", 0.0))))
		root["damage_spent"] = int(floor(float(root.raw_packet) * float(root.coefficient)))
	var basis: float = maxf(float(root.get("b10_budget_basis", 0.0)), maxf(float(root.raw_packet), power))
	root["b10_budget_basis"] = basis
	var remaining := maxi(0, int(Numerical.derived_budget(basis, Numerical.V2)) - int(root.get("damage_spent", 0)))
	var damage: int = Numerical.integer(power * coefficient)
	var amounts := {}
	for value: Variant in targets:
		var target := str(value)
		if target.is_empty() or amounts.has(target): continue
		var amount := mini(damage, remaining)
		if amount <= 0: break
		amounts[target] = amount
		remaining -= amount
		if amounts.size() >= limit: break
	if amounts.is_empty() or (not reserved and not e._activate(id, 0.0, root, out)): return
	for amount: int in amounts.values(): root["damage_spent"] = int(root.get("damage_spent", 0)) + amount
	root.coefficient = float(root.damage_spent) / maxf(1.0, float(root.raw_packet))
	out.bonus_hits.append({"target_ids":amounts.keys(), "damage":damage, "damage_by_target":amounts, "coefficient":coefficient, "source":"equipment", "damage_source":"equipment", "damage_type":power_type, "proc_depth":1, "equipment_eligible":false, "original_basic":false, "critical":false, "states":[], "effect_id":id})
