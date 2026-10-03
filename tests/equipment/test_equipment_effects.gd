extends SceneTree
## Runs real raw events against the reducer: no scene, RNG, or mutated Game.
const Effects = preload("res://scripts/domain/combat/equipment_effects.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
var checks: int = 0
var failures: int = 0
var serial: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EQUIPMENT FAIL: " + label)

func _near(value: float, expected: float, label: String) -> void:
	_check(absf(value - expected) < 0.00001, label + " (actual=" + str(value) + ", expected=" + str(expected) + ")")

func _ctx(extra: Dictionary = {}) -> Dictionary:
	serial += 1
	var context: Dictionary = {"attack_id":"attack_" + str(serial), "target_id":"enemy_1", "hp":50.0, "max_hp":100.0,
		"shield":0.0, "resource":0.0, "resource_max":100.0, "resource_type":"mana", "H":20.0, "X":100.0,
		"equipment_eligible":true, "original_basic":true, "proc_depth":0, "damage_source":"primary",
		"target_states":[], "critical":false, "remaining_cooldowns":{"Q":2.0,"right":4.0,"F":4.0,"R":1.0,"dash":1.0},
		"nearby_targets":[{"id":"enemy_1","distance":0.0},{"id":"enemy_2","distance":30.0},{"id":"enemy_3","distance":60.0},{"id":"enemy_4","distance":90.0},{"id":"far","distance":300.0}]}
	context.merge(extra, true)
	return context

func _fx(ids: Array, type: String = "mana", base: Dictionary = {}) -> RefCounted:
	var loadout: Dictionary = {}
	for id in ids:
		loadout[Registry.equipment(id).slot] = id
	var stats: Dictionary = {"max_hp":100.0, "resource_max":100.0, "attack":20.0}
	stats.merge(base, true)
	var value: RefCounted = Effects.new()
	value.configure(loadout, stats, type)
	return value

func _set_fx(id: String, pieces: int) -> RefCounted:
	var ids: Array = []
	for eq in Registry.equipment_ids():
		if Registry.equipment(eq).get("set_id", "") == id and ids.size() < pieces: ids.append(eq)
	return _fx(ids)

func _strike(fx: RefCounted, extra: Dictionary = {}) -> Dictionary:
	var context: Dictionary = _ctx(extra)
	var before: Dictionary = fx.handle("before_hit", context)
	var after: Dictionary = fx.handle("after_hit", context)
	after = _resolve(fx, after, context)
	return {"before":before, "after":after, "context":context}

func _resolve(fx: RefCounted, result: Dictionary, context: Dictionary, accepted: bool = true) -> Dictionary:
	var current: Dictionary = result
	var combined: Dictionary = result.duplicate(true)
	for step in range(3):
		if not bool(current.get("resume_after_statuses", false)): break
		var success: Array = []
		for command in current.statuses:
			if accepted: success.append(command.status)
		if not success.is_empty():
			var confirmation: Dictionary = context.duplicate(true)
			confirmation.applied_states = success
			fx.handle("status_applied", confirmation)
		current = fx.handle("statuses_resolved", context)
		for key in current:
			if current[key] is Array: combined[key].append_array(current[key])
			elif key == "shield_ratio": combined[key] = maxf(float(combined[key]), float(current[key]))
			elif key in ["resource_restore", "heal_ratio"]: combined[key] = float(combined[key]) + float(current[key])
			else: combined[key] = current[key]
	return combined

func _dash(fx: RefCounted, extra: Dictionary = {}) -> Dictionary:
	return fx.handle("dash", _ctx(extra))

func _break(fx: RefCounted) -> Dictionary:
	return fx.handle("damaged", _ctx({"enemy_damage":true,"shield_broken":true,"shield_absorbed":10.0,"hp_damage":0.0}))

func _status(fx: RefCounted, state: String, extra: Dictionary = {}) -> Dictionary:
	var context: Dictionary = _ctx({"applied_states":[state]})
	context.merge(extra, true)
	fx.handle("status_applied", context)
	fx.handle("before_hit", context)
	return _resolve(fx, fx.handle("after_hit", context), context)

func _passive(fx: RefCounted, extra: Dictionary = {}) -> Dictionary:
	return fx.advance(0.0, _ctx(extra))

func _run() -> void:
	_check(Effects.implemented_ids().size() == 96, "manifest contains 96 implemented affixes")
	_check(Effects.implemented_set_ids().size() == 14, "manifest contains 14 implemented sets")
	_all_affixes()
	_all_sets()
	_identity_and_timing()
	_resources_and_budgets()
	_ordered_confirmations()
	print("EQUIPMENT EFFECT TESTS: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

func _all_affixes() -> void:
	var fx: RefCounted
	var result: Dictionary
	for id in Effects.implemented_ids():
		fx = _fx([id])
		match id:
			"EQ01":
				_strike(fx); _strike(fx)
				_near(_strike(fx).before.damage_bonus, 0.08, id + " third same target bonus")
			"EQ02":
				_dash(fx)
				_near(_strike(fx).before.damage_bonus, 0.10, id + " dash first attack bonus")
			"EQ03": _check(_strike(fx).after.statuses[0].status == "burn", id + " applies burn after hit")
			"EQ04", "EQ05", "EQ06":
				_strike(fx); _strike(fx)
				_check(_strike(fx).after.statuses[0].status == {"EQ04":"shock","EQ05":"chill","EQ06":"corrosion"}[id], id + " third attack state")
			"EQ07":
				_strike(fx); _strike(fx); _strike(fx)
				_near(_strike(fx).after.shield_ratio, 0.03, id + " fourth attack shield")
			"EQ08":
				_dash(fx)
				_near(_strike(fx).before.knockback_scale, 1.25, id + " dash knockback")
			"EQ09": _near(_strike(fx, {"target_full_hp":true}).before.crit_bonus, 0.08, id + " full target precrit")
			"EQ10":
				_dash(fx)
				_check(_strike(fx).after.statuses[0].status == "shock", id + " dash shock")
			"EQ11": _near(_passive(fx, {"hp":29.0}).move_speed_bonus, 0.05, id + " low HP speed")
			"EQ12":
				fx.advance(4.0, _ctx())
				_near(_strike(fx).before.damage_bonus, 0.08, id + " undamaged next strike")
			"EQ13":
				result = fx.handle("kill", _ctx({"target_states":["burn"]}))
				_near(result.cooldown_refunds[0].seconds, 0.15, id + " burn kill refund")
			"EQ14": _near(_strike(fx, {"target_states":["shock"]}).after.shield_ratio, 0.02, id + " shock shield")
			"EQ15": _near(_strike(fx, {"target_states":["chill"]}).before.crit_bonus, 0.04, id + " chill precrit")
			"EQ16": _near(fx.handle("kill", _ctx({"target_states":["corrosion"],"distance":100.0})).heal_ratio, 0.01, id + " nearby corrosion death heal")
			"EQ17": _near(_passive(fx, {"shield":10.0}).received_knockback_scale, 0.80, id + " shield knockback resistance")
			"EQ18":
				_break(fx)
				_near(_strike(fx).before.knockback_scale, 1.30, id + " broken shield next knockback")
			"EQ19": _near(_strike(fx, {"critical":true,"target_states":["corrosion","chill"]}).after.status_extensions[0].seconds, 0.30, id + " critical chill extension")
			"EQ20":
				result = _dash(fx)
				_near(result.self_statuses[0].power, 0.12, id + " dash timed damage reduction")
			"EQ21": _near(fx.handle("damaged", _ctx({"enemy_damage":true,"hp_damage":1.0,"hp":29.0})).shield_ratio, 0.05, id + " room rescue shield")
			"EQ22": _near(fx.advance(5.0, _ctx()).cooldown_refunds[0].seconds, 0.20, id + " undamaged dash refund")
			"EQ23": _near(_passive(fx, {"nearby_burning":true}).damage_reduction_bonus, 0.04, id + " nearby burn resistance")
			"EQ24": _near(_status(fx, "shock").damage_reduction_bonus, 0.05, id + " applied shock resistance")
			"EQ25": _near(_strike(fx, {"target_states":["chill"]}).after.received_knockback_scale, 0.80, id + " chill hit knockback resistance")
			"EQ26": _near(_status(fx, "corrosion").shield_ratio, 0.02, id + " corrosion success shield")
			"EQ27": _near(fx.handle("room_enter", _ctx({"room_id":"test"})).shield_ratio, 0.04, id + " entry shield")
			"EQ28": _near(_passive(fx, {"current_speed":100.0,"base_speed":200.0}).received_knockback_scale, 0.75, id + " slowed knockback resistance")
			"EQ29": _near(_strike(fx, {"critical":true,"target_states":["chill"]}).after.shield_ratio, 0.02, id + " critical chilled shield")
			"EQ30": _near(fx.handle("dash_end", _ctx()).damage_reduction_bonus, 0.06, id + " dash end resistance")
			"EQ31": _near(_passive(fx, {"hp":100.0}).damage_bonus, 0.03, id + " full HP damage")
			"EQ32":
				for index in range(4): _strike(fx)
				_near(_strike(fx).after.resource_restore, 3.0, id + " fifth basic mana")
			"EQ33": _near(_strike(fx, {"target_states":["burn"]}).after.status_extensions[0].seconds, 0.30, id + " burn extension")
			"EQ34": _near(_strike(fx, {"target_states":["shock"]}).before.damage_bonus, 0.04, id + " conditional shock damage")
			"EQ35":
				_strike(fx, {"target_states":["chill"]}); _strike(fx, {"target_states":["chill"]})
				_near(_strike(fx, {"target_states":["chill"]}).after.bonus_hits[0].damage, 15.0, id + " third chill raw X damage")
			"EQ36": _near(_strike(fx, {"target_states":["corrosion"]}).after.status_extensions[0].seconds, 0.30, id + " corrosion extension")
			"EQ37": _near(_passive(fx, {"shield":10.0}).attack_speed_bonus, 0.04, id + " shield attack speed")
			"EQ38":
				_dash(fx)
				_near(_strike(fx, {"target_states":["chill"]}).after.bonus_hits[0].damage, 20.0, id + " dash raw X damage")
			"EQ39": _near(_strike(fx, {"critical":true,"target_states":["corrosion"]}).after.attack_speed_bonus, 0.04, id + " corrosion critical attack speed")
			"EQ40":
				_dash(fx)
				result = _strike(fx)
				_near(fx.handle("kill", result.context).cooldown_refunds[0].seconds, 0.20, id + " first dash attack kill refund")
			"EQ41": _near(_passive(fx).received_knockback_scale, 0.90, id + " passive knockback resistance")
			"EQ42": _near(fx.handle("room_enter", _ctx({"room_id":"new"})).move_speed_bonus, 0.08, id + " new room haste")
			"EQ43": _near(fx.handle("kill", _ctx({"target_states":["burn"]})).move_speed_bonus, 0.06, id + " primary burn kill haste")
			"EQ44": _near(_status(fx, "shock").cooldown_refunds[0].seconds, 0.10, id + " shock application dash refund")
			"EQ45": _near(_passive(fx, {"self_chilled":true}).slow_resistance, 0.20, id + " chill slow resistance")
			"EQ46": _near(_status(fx, "corrosion").move_speed_bonus, 0.05, id + " corrosion haste")
			"EQ47": _near(_passive(fx, {"shield":10.0}).slow_resistance, 0.15, id + " shield slow resistance")
			"EQ48": _near(fx.handle("dash_end", _ctx()).shield_ratio, 0.02, id + " dash end shield")
			"EQ49":
				fx.advance(2.0, _ctx({"moving":true}))
				_near(_strike(fx, {"target_states":["chill"]}).before.crit_bonus, 0.05, id + " moving precrit")
			"EQ50":
				_dash(fx)
				_check(_strike(fx, {"target_states":["shock"]}).after.statuses[0].status == "chill", id + " dash shocked target chill")
			"EQ51": _near(_passive(fx, {"hp":29.0}).damage_reduction_bonus, 0.03, id + " low HP resistance")
			"EQ52": _near(fx.handle("kill", _ctx()).heal_ratio, 0.01, id + " first room kill heal")
			"EQ53": _near(_status(fx, "burn").shield_ratio, 0.02, id + " burn application shield")
			"EQ54": _near(_strike(fx, {"target_states":["shock"]}).before.crit_bonus, 0.03, id + " shock precrit")
			"EQ55": _near(_strike(fx, {"critical":true,"target_states":["chill"]}).after.heal_ratio, 0.01, id + " chilled critical heal")
			"EQ56":
				_strike(fx, {"target_states":["corrosion"]})
				_near(fx.skill_cost(20.0), 18.4, id + " next paid skill discount")
			"EQ57": _near(_break(fx).move_speed_bonus, 0.06, id + " enemy breaks shield haste")
			"EQ58": _near(_strike(fx, {"target_states":["chill"]}).after.shield_ratio, 0.02, id + " chilled hit shield")
			"EQ59":
				_strike(fx); _strike(fx)
				_near(_strike(fx).before.crit_bonus, 0.0, id + " third noncrit cannot buff itself")
				_near(_strike(fx, {"target_states":["corrosion"]}).before.crit_bonus, 0.10, id + " fourth attack precrit")
			"EQ60":
				_dash(fx)
				_near(_strike(fx, {"target_states":["burn"]}).after.attack_speed_bonus, 0.05, id + " dash status attack speed")

func _all_sets() -> void:
	var fx: RefCounted = _set_fx("S01", 2)
	_near(_strike(fx, {"target_states":["burn"]}).before.damage_bonus, 0.08, "S01 two pieces old burn only")
	fx = _set_fx("S01", 4)
	_near(_status(fx, "burn").damage_bonus, 0.10, "S01 four pieces successful burn buff")
	fx = _set_fx("S01", 6)
	_near(fx.handle("kill", _ctx({"target_states":["burn"]})).bonus_hits[0].damage, 35.0, "S01 six pieces three embers")
	fx = _set_fx("S02", 2)
	_near(_strike(fx, {"target_states":["shock"]}).after.cooldown_refunds[0].seconds, 0.15, "S02 two dash refund")
	fx = _set_fx("S02", 4)
	_near(_strike(fx, {"target_states":["shock"]}).after.bonus_hits[0].damage, 25.0, "S02 four arc raw X")
	fx = _set_fx("S02", 6)
	_strike(fx, {"target_states":["shock"],"target_id":"enemy_1"})
	_strike(fx, {"target_states":["shock"],"target_id":"enemy_2"})
	_near(_strike(fx, {"target_states":["shock"],"target_id":"enemy_3"}).after.attack_speed_bonus, 0.10, "S02 six unique-target speed")
	fx = _set_fx("S03", 2)
	_near(_passive(fx).chill_duration_bonus, 0.20, "S03 two chill duration")
	fx = _set_fx("S03", 4)
	_near(_strike(fx, {"target_states":["chill"]}).after.shield_ratio, 0.04, "S03 four shield")
	fx = _set_fx("S03", 6)
	var result: Dictionary = _strike(fx, {"target_states":["chill"]}).after
	_check(result.bonus_hits[0].states[0].status == "chill" and result.bonus_hits[0].target_ids.size() == 3, "S03 six frost ring three targets chill")
	fx = _set_fx("S04", 2)
	_near(_strike(fx, {"target_states":["corrosion"]}).before.damage_bonus, 0.08, "S04 two corrosion damage")
	fx = _set_fx("S04", 4)
	_near(_status(fx, "corrosion").heal_ratio, 0.01, "S04 four successful corrosion heal")
	fx = _set_fx("S04", 6)
	_near(_strike(fx, {"target_states":["corrosion"]}).after.bonus_hits[0].damage, 35.0, "S04 six acid burst")
	fx = _set_fx("S05", 2)
	_near(_passive(fx, {"shield":10.0}).damage_bonus, 0.06, "S05 two shielded damage")
	fx = _set_fx("S05", 4)
	_near(_break(fx).attack_speed_bonus, 0.10, "S05 four actual absorption speed")
	fx = _set_fx("S05", 6)
	_break(fx)
	_near(fx.advance(0.99, _ctx()).shield_ratio, 0.0, "S05 six waits full second")
	_near(fx.advance(0.01, _ctx()).shield_ratio, 0.10, "S05 six delayed shield")
	fx = _set_fx("S06", 2)
	_near(_strike(fx, {"shield":10.0}).before.knockback_scale, 1.20, "S06 two shielded knockback")
	fx = _set_fx("S06", 4)
	_dash(fx, {"shield":10.0})
	_near(_strike(fx, {"shield":10.0}).before.damage_bonus, 0.12, "S06 four dash first hit damage")
	fx = _set_fx("S06", 6)
	_break(fx)
	_near(_strike(fx).after.bonus_hits[0].damage, 40.0, "S06 six broken shield shockwave")
	fx = _set_fx("S07", 2)
	_near(_strike(fx, {"target_states":["chill"]}).before.crit_bonus, 0.06, "S07 two conditional precrit")
	fx = _set_fx("S07", 4)
	result = _strike(fx, {"target_states":["corrosion"],"critical":true}).after
	_check(result.cooldown_refunds.size() == 1 and result.cooldown_refunds[0].slot == "right", "S07 four refund longest single skill")
	fx = _set_fx("S07", 6)
	_strike(fx, {"target_states":["corrosion"],"critical":true})
	_strike(fx, {"target_states":["corrosion"],"critical":true})
	_near(_strike(fx, {"target_states":["corrosion"],"critical":true}).after.bonus_hits[0].damage, 40.0, "S07 six third critical raw X calibration")
	fx = _set_fx("S08", 2)
	_dash(fx)
	_near(_strike(fx, {"target_states":["shock"]}).after.cooldown_refunds[0].seconds, 0.20, "S08 two first dash attack refund")
	fx = _set_fx("S08", 4)
	_dash(fx)
	_near(_status(fx, "shock").move_speed_bonus, 0.12, "S08 four dash status haste")
	fx = _set_fx("S08", 6)
	result = _dash(fx, {"shield":10.0,"H":20.0,"X":999.0})
	_near(result.bonus_hits[0].damage, 7.0, "S08 six dash snapshot H instead of previous skill X")
	for set_id in Effects.implemented_set_ids():
		fx = _set_fx(set_id, 1)
		_check(int(fx.set_counts[set_id]) == 1 and not fx._has_set(set_id, 2), set_id + " one piece never activates threshold")

func _identity_and_timing() -> void:
	var fx: RefCounted = _fx(["EQ04"])
	var context: Dictionary = _ctx()
	fx.handle("before_hit", context)
	fx.handle("after_hit", context)
	fx.handle("after_hit", context)
	var same_root: Dictionary = context.duplicate(true)
	same_root.target_id = "enemy_2"
	fx.handle("before_hit", same_root)
	fx.handle("after_hit", same_root)
	_check(_strike(fx).after.statuses.is_empty(), "multiple targets and duplicate after_hit count only once")
	_check(_strike(fx).after.statuses.size() == 1, "third independent attack triggers after multiswing")
	fx = _fx(["EQ03"])
	_check(_strike(fx).after.statuses.size() == 1, "EQ03 first application")
	_check(_strike(fx).after.statuses.is_empty(), "ICD blocks same target at frozen clock")
	fx.advance(3.99, _ctx())
	_check(_strike(fx).after.statuses.is_empty(), "ICD does not expire early")
	fx.advance(0.01, _ctx())
	_check(_strike(fx).after.statuses.size() == 1, "ICD expires only advanced time")
	fx = _fx(["EQ03", "EQ13", "EQ23", "EQ33"])
	context = _ctx()
	_near(fx.handle("before_hit", context).damage_bonus, 0.0, "new burn cannot amplify original strike")
	var after: Dictionary = fx.handle("after_hit", context)
	_check(after.statuses.size() == 1, "burn application is requested after original damage")
	_near(_passive(fx).damage_bonus, 0.0, "request is not successful status application")
	context.applied_states = ["burn"]
	fx.handle("status_applied", context)
	_near(fx.handle("statuses_resolved", context).damage_bonus, 0.10, "confirmed application activates timed set bonus")
	fx = _fx(["EQ50"])
	_dash(fx)
	_strike(fx)
	_check(_strike(fx, {"target_states":["shock"]}).after.statuses.is_empty(), "wrong-state first hit consumes dash opportunity")
	fx = _fx(["EQ02"])
	_dash(fx)
	fx.advance(3.0, _ctx())
	_near(_strike(fx).before.damage_bonus, 0.0, "default next strike window expires at three seconds")
	fx = _fx(["EQ01"])
	_strike(fx); _strike(fx)
	_strike(fx, {"target_id":"other"})
	_near(_strike(fx).before.damage_bonus, 0.0, "same target combo resets when switching target")
	_strike(fx)
	fx.advance(3.01, _ctx())
	_near(_strike(fx).before.damage_bonus, 0.0, "same target combo resets after three seconds")
	fx = _fx(["EQ21", "EQ52"])
	fx.handle("room_enter", _ctx({"room_id":"r1"}))
	_near(fx.handle("damaged", _ctx({"hp":29.0,"hp_damage":1.0,"enemy_damage":true})).shield_ratio, 0.05, "first low HP room shield")
	_near(fx.handle("damaged", _ctx({"hp":29.0,"hp_damage":1.0,"enemy_damage":true})).shield_ratio, 0.0, "low HP room shield cannot repeat")
	fx.handle("room_enter", _ctx({"room_id":"r1"}))
	_near(fx.handle("damaged", _ctx({"hp":29.0,"hp_damage":1.0,"enemy_damage":true})).shield_ratio, 0.0, "duplicate room event does not rearm")
	fx.handle("room_enter", _ctx({"room_id":"r2"}))
	_near(fx.handle("damaged", _ctx({"hp":29.0,"hp_damage":1.0,"enemy_damage":true})).shield_ratio, 0.05, "new room rearms rescue shield")
	fx = _set_fx("S05", 6)
	_near(fx.handle("damaged", _ctx({"shield_broken":true,"enemy_damage":false})).attack_speed_bonus, 0.0, "expiry or cleanup is not enemy shield break")
	_break(fx)
	fx.handle("room_enter", _ctx({"room_id":"other"}))
	_near(fx.advance(1.0, _ctx()).shield_ratio, 0.0, "delayed shield cannot leak to a new room")

func _resources_and_budgets() -> void:
	var fx: RefCounted
	for type in ["rage", "energy", "mana"]:
		fx = _fx(["EQ32"], type)
		for index in range(4): _strike(fx, {"resource_type":type})
		_near(_strike(fx, {"resource_type":type}).after.resource_restore, {"rage":1.0,"energy":2.0,"mana":3.0}[type], type + " exact resource adaptation")
	fx = _fx(["EQ32"])
	for index in range(8): _strike(fx, {"original_basic":false,"damage_source":"skill"})
	for index in range(4): _strike(fx)
	_near(_strike(fx, {"resource":99.0}).after.resource_restore, 1.0, "skills excluded from basic count and restoration capped by missing")
	fx = _fx(["EQ32"])
	for index in range(4): _strike(fx, {"resource_max":10.0})
	_near(_strike(fx, {"resource_max":10.0}).after.resource_restore, 2.0, "shared resource five-second cap 20 percent")
	fx.advance(3.0, _ctx())
	for index in range(4): _strike(fx, {"resource_max":10.0})
	_near(_strike(fx, {"resource_max":10.0}).after.resource_restore, 0.0, "resource window cap survives individual ICD expiry")
	fx = _fx(["EQ56"])
	_strike(fx, {"target_states":["corrosion"]})
	_near(fx.skill_cost(0.0), 0.0, "discount keeps free attacks free")
	_near(fx.skill_cost(0.5), 1.0, "paid cost never drops below one")
	_near(fx.skill_cost(20.0, {"resource_type":"rage"}), 20.0, "discount cannot cross resource types")
	fx.handle("skill_cast", _ctx({"base_cost":20.0,"cast_success":false}))
	_near(fx.skill_cost(20.0), 18.4, "failed cast keeps discount")
	fx.handle("skill_cast", _ctx({"base_cost":20.0,"cast_success":true}))
	_near(fx.skill_cost(20.0), 20.0, "successful paid cast consumes discount")
	fx = _set_fx("S01", 6)
	var derived: Dictionary = _ctx({"damage_source":"equipment","proc_depth":1,"target_states":["burn"],"critical":true})
	_check(fx.handle("after_hit", derived).statuses.is_empty(), "equipment-derived hit cannot trigger weapon status")
	_check(fx.handle("kill", derived).bonus_hits.is_empty(), "equipment-derived burning kill cannot chain embers")
	var tick: Dictionary = _ctx({"damage_source":"burn","proc_depth":1,"target_states":["burn"],"target_id":"burned","H":20.0,"X":999.0})
	_near(fx.handle("kill", tick).bonus_hits[0].damage, 7.0, "burn kill exception uses H snapshot")
	_check(fx.handle("kill", _ctx({"target_id":"burned","target_states":["burn"]})).bonus_hits.is_empty(), "death identity deduplicated across root IDs")
	fx = _set_fx("S03", 6)
	var saturated: Dictionary = _strike(fx, {"target_states":["chill"],"root_packets_used":4}).after
	_check(saturated.bonus_hits.is_empty() and saturated.shields.is_empty(), "root original packets reserve shared budget")
	_check(not fx.cooldowns.has("S03_6"), "budget denied proc does not start ICD")
	var allowed: Dictionary = _strike(fx, {"target_states":["chill"],"root_coefficient_used":1.05}).after
	_near(allowed.bonus_hits[0].damage, 5.0, "remaining coefficient shared across all three targets")
	_check(allowed.bonus_hits[0].equipment_eligible == false and allowed.bonus_hits[0].critical == false, "bonus packets cannot crit or recurse")
	fx = _fx(["EQ13", "EQ44", "EQ40"])
	_dash(fx)
	var strike: Dictionary = {"context":_ctx({"target_states":["burn"],"applied_states":["shock"]})}
	fx.handle("status_applied", strike.context)
	fx.handle("before_hit", strike.context)
	fx.handle("after_hit", strike.context)
	var kill: Dictionary = fx.handle("kill", strike.context)
	var total: float = 0.10
	for refund in kill.cooldown_refunds: total += float(refund.seconds)
	_near(total, 0.45, "cooldown packets share accounting across application and kill")
	fx = _fx(["EQ11", "EQ31", "EQ51"], "mana", {"move_speed_bonus":0.44,"damage_bonus":0.59,"equipment_damage_reduction":0.34})
	_near(_passive(fx, {"hp":29.0}).move_speed_bonus, 0.01, "conditional speed respects remaining global cap")
	_near(_passive(fx, {"hp":100.0}).damage_bonus, 0.01, "conditional direct damage respects remaining cap")
	_near(_passive(fx, {"hp":29.0}).damage_reduction_bonus, 0.01, "conditional equipment DR respects equipment contribution cap")
	fx = _fx(["EQ03"])
	_check(fx.reserve_native("native-root", "skill-status"), "native status reserves one shared package")
	_check(fx.reserve_native("native-root", "skill-status"), "same native packet reservation is idempotent")
	_check(fx.reserve_native("native-root", "relic-split", 0.8), "two split targets reserve total 0.8 coefficient")
	_check(not fx.reserve_native("native-root", "oversized-arc", 0.5), "native relic cannot cross shared coefficient cap")
	_check(fx.reserve_native("native-root", "relic-ember"), "third native packet reserves")
	var native_hit: Dictionary = _strike(fx, {"root_event_id":"native-root"}).after
	_check(native_hit.statuses.size() == 1 and fx.root_usage("native-root").packets == 4, "native plus affix packages share four-slot root")
	_check(not fx.reserve_native("native-root", "late-extra"), "legacy after equipment cannot get independent budget")
	fx = _fx(["EQ03"])
	fx.reserve_native("frozen", "a"); fx.reserve_native("frozen", "b")
	fx.reserve_native("frozen", "c"); fx.reserve_native("frozen", "d")
	_check(_strike(fx, {"root_event_id":"frozen"}).after.statuses.is_empty(), "native priority denies equipment when full")
	_check(_strike(fx).after.statuses.size() == 1, "denied affix retains ready ICD on another root")
	fx = _fx(["EQ14", "EQ29", "EQ58"])
	var shield_result: Dictionary = _strike(fx, {"target_states":["shock","chill"],"critical":true}).after
	_check(shield_result.shields.size() == 3 and shield_result.shields[0].source != shield_result.shields[1].source, "independent shield sources retain distinct expiry identity")
	_near(shield_result.shield_ratio, 0.02, "multiple two-percent shields combine by maximum, not sum")
	fx = _set_fx("S05", 6)
	_break(fx)
	_near(fx.advance(1.0, _ctx({"hp":0.0})).shield_ratio, 0.0, "delayed shield never revives a dead hero")
	fx = _fx(["EQ12", "EQ22"])
	fx.advance(4.0, _ctx())
	_strike(fx)
	_check(fx.advance(1.0, _ctx()).cooldown_refunds.size() == 1, "consuming EQ12 does not reset EQ22 undamaged timer")
	fx = _fx(["EQ49"])
	fx.advance(2.0, _ctx({"moving":true}))
	fx.advance(0.10, _ctx({"moving":false}))
	_near(_strike(fx, {"target_states":["chill"]}).before.crit_bonus, 0.05, "movement charge survives stopping before the next attack")
	fx = _fx(["EQ38"])
	_dash(fx)
	_check(_strike(fx, {"target_states":["chill"],"target_alive":false}).after.bonus_hits.is_empty(), "single target follow-up never retargets a dead original victim")

func _ordered_confirmations() -> void:
	var fx: RefCounted = _fx(["EQ06", "EQ14", "EQ26", "EQ36", "EQ44", "EQ58"])
	_strike(fx); _strike(fx)
	var combined: Dictionary = _strike(fx, {"target_states":["shock","chill","corrosion"]}).after
	var shield_sources: Array = []
	for shield in combined.shields: shield_sources.append(shield.source)
	_check("EQ14" in shield_sources and "EQ26" in shield_sources and not "EQ58" in shield_sources, "weapon confirmation resumes head then chest ahead of charm packet")
	_check(not fx.cooldowns.has("EQ58"), "later charm denied by ordered budget never starts ICD")
	fx = _fx(["EQ26", "EQ44"])
	var context: Dictionary = _ctx({"applied_states":["shock","corrosion"],"root_packets_used":3})
	fx.handle("status_applied", context)
	fx.handle("before_hit", context)
	combined = fx.handle("after_hit", context)
	_check(combined.shields.size() == 1 and combined.cooldown_refunds.is_empty(), "mixed confirmed states respect chest before feet rather than state-name order")
	fx = _fx(["EQ03", "EQ14", "EQ53"])
	context = _ctx({"target_states":["shock"]})
	fx.handle("before_hit", context)
	combined = _resolve(fx, fx.handle("after_hit", context), context, false)
	_check(combined.shields.size() == 1 and combined.shields[0].source == "EQ14", "immune weapon status continues normal gear but cannot grant success-only charm")
	fx = _fx(["EQ20", "EQ30", "EQ40", "EQ50"])
	_dash(fx)
	_near(_strike(fx, {"target_states":["shock"]}).after.move_speed_bonus, 0.12, "feet status confirmation resumes charm and S08 four-piece in order")
	fx = _fx(["EQ02", "EQ18"])
	_break(fx); _dash(fx)
	context = _ctx()
	var first: Dictionary = fx.handle("before_hit", context)
	context.target_id = "enemy_2"
	var second: Dictionary = fx.handle("before_hit", context)
	_near(first.damage_bonus, 0.10, "dash first attack bonus starts on first target")
	_near(second.damage_bonus, 0.10, "same dash attack retains damage bonus on other targets")
	_near(second.knockback_scale, 1.30, "same shield-break attack retains knockback on other targets")
	fx = _fx(["EQ59"])
	_strike(fx); _strike(fx); _strike(fx)
	_strike(fx, {"target_states":[]})
	_near(_strike(fx, {"target_states":["corrosion"]}).before.crit_bonus, 0.0, "EQ59 wrong-state next attack consumes opportunity")
	fx = _fx(["EQ59"])
	_strike(fx); _strike(fx); _strike(fx)
	fx.advance(3.0, _ctx())
	_near(_strike(fx, {"target_states":["corrosion"]}).before.crit_bonus, 0.0, "EQ59 next attack opportunity expires after three seconds")
	fx = _fx(["EQ04"])
	for source in ["equipment", "child", "burn", "node"]:
		_check(_strike(fx, {"damage_source":source,"proc_depth":1}).after.statuses.is_empty(), source + " cannot advance primary counters")
	_strike(fx, {"valid_target":false})
	_strike(fx); _strike(fx)
	_check(_strike(fx).after.statuses.size() == 1, "only three valid original attacks count after invalid and derived events")
	fx = _fx(["EQ03"])
	_strike(fx)
	_check(_strike(fx, {"target_id":"another"}).after.statuses.size() == 1, "EQ03 ignition ICD is per target")
	fx = _set_fx("S02", 6)
	_strike(fx, {"target_states":["shock"]}); _strike(fx, {"target_states":["shock"]})
	_near(_strike(fx, {"target_states":["shock"]}).after.attack_speed_bonus, 0.0, "S02 six cannot count one shocked enemy three times")
	fx = _fx(["EQ32", "EQ50"])
	for index in range(4): _strike(fx)
	_dash(fx)
	var phased: Dictionary = _strike(fx, {"target_states":["shock"]}).after
	_near(phased.resource_restore, 3.0, "hand resource command survives later feet status continuation")
	_check(phased.statuses.size() == 1 and phased.statuses[0].status == "chill", "same fifth attack includes foot chill and hand resource exactly once")
