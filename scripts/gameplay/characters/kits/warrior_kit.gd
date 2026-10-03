class_name WarriorKit
extends RefCounted
## Rage uses the run's single resource bar. A hit earns rage once per original
## attack/cast; released damage keeps the multiplier captured by the kernel.

const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const BERSERK_DURATION := 8.0
const REARM_DURATION := 3.0
const LEDGER_LIMIT := 128
const HERO_ID := "CH01"

var owner_player: Node2D
var berserk_remaining := 0.0
var berserk_rearm_remaining := 0.0
var incoming_rage_icd := 0.0
var _primary_roots: Array[String] = []
var _skill_roots: Array[String] = []
var _release_roots: Array[String] = []
var _counter: Dictionary = {}

func configure(player: Node2D) -> void:
	owner_player = player

static func skill_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.assign(Numbers.value("class_skill_specs", {}).get("CH01", []))
	for index in range(specs.size()):
		var data: Dictionary = specs[index]
		data["skill_id"] = "CH01_SK%02d" % (index + 1)
		data["hero"] = HERO_ID
		data["hero_id"] = HERO_ID
		data["damage_type"] = "physical"
		data["unlock"] = 1
		data["origin_slot"] = str(data.get("origin_slot", "skill"))
		data["slot"] = data.origin_slot
		data["base_cooldown"] = float(data.cooldown)
		data["total_coefficient"] = float(data.get("total_coefficient", data.coefficient))
		data["acquisition_group"] = "" if index < 4 else "SG%02d" % (index - 3)
		data["description"] = _skill_description(index + 1)
		data["name_en"] = ["Breach Charge","Earth Cleaver","Iron Warcry","Skyfall Axe","Twin Axe Sweep","Stone Guard","Faultline Strike","Rift Pull","Returning Axe","Reprisal Stance","Whirling Axe","Aftershock Stomp"][index]
		data["description_en"] = ["Charge forward and strike at the destination. Confirmed original hits build Rage.","Deliver a heavy strike in a forward cone.","Repel nearby enemies and gain a shield with brief damage reduction.","Crash your axe at a valid target point. Capture Berserk damage when the cast starts.","Sweep twice around you for 1.6H total damage.","Gain a shield worth 12% of maximum health for three seconds.","Strike a forward strip with a ground fissure for 1.8H.","Damage and pull enemies in a forward cone; existing boss resistance applies.","Throw and recall an axe for 0.7H on each pass.","Gain a one-second shield; your first confirmed damage taken triggers a 1.2H counterstrike.","Move freely while performing four sweeps for 3.2H total damage.","Stomp around you for 2.0H damage and slow enemies."][index]
	return specs

static func _skill_description(index: int) -> String:
	return [
		"向前冲锋，在终点挥斧击退敌人。持续近身进攻积怒，满怒自动进入狂暴。",
		"向前方扇形范围重斩；伤害、冷却和分支始终跟随技能身份。",
		"震退周围敌人，获得四秒护盾与短暂减伤。护盾在实际释放时获得。",
		"向指定落点重斧砸击，造成大范围伤害。狂暴中的强化在起手时冻结。",
		"连续两次周身旋斩，整次共造成1.6H伤害。",
		"获得最大生命12%的三秒护盾。",
		"释放前向地裂，打击前方直线内敌人。",
		"牵引前方扇形敌人并造成伤害；首领保留原有位移抗性。",
		"投出战斧并沿原方向收回，去程与回程各造成0.7H伤害。",
		"获得一秒护盾，首次承受有效伤害时向周围反击1.2H。",
		"移动中发动四次周身旋斩，整次共造成3.2H伤害。",
		"踏碎周围地面，造成范围伤害并减速敌人。"
	][index - 1]

func apply_skill_variant(data: Dictionary, rank: int, branch: String) -> void:
	if rank >= 2:
		data.merge(data.get("mastery_upgrade", {}), true)
	var identifier: String = str(data.get("skill_id", ""))
	data["branch"] = branch if rank >= int(data.get("branch_rank", 99)) and branch in ["A", "B"] else ""
	if identifier in ["CH01_SK01", "CH01_SK02", "CH01_SK03", "CH01_SK04"]:
		data["total_coefficient"] = float(data.coefficient)
	if identifier == "CH01_SK01" and str(data.branch) == "A":
		data["aftershock_coefficient"] = 0.4
		data["aftershock_radius"] = 70.0
		data["total_coefficient"] = float(data.coefficient) + 0.4
	elif identifier == "CH01_SK04" and str(data.branch) == "A":
		data["radius"] = float(data.radius) * 1.2

func tick(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	incoming_rage_icd = maxf(0.0, incoming_rage_icd - delta)
	if berserk_remaining > 0.0:
		var after_end: float = maxf(0.0, delta - berserk_remaining)
		berserk_remaining = maxf(0.0, berserk_remaining - delta)
		if berserk_remaining <= 0.0:
			berserk_rearm_remaining = maxf(0.0, REARM_DURATION - after_end)
			_feedback("berserk_end")
	else:
		berserk_rearm_remaining = maxf(0.0, berserk_rearm_remaining - delta)
	if not _counter.is_empty():
		_counter["remaining"] = maxf(0.0, float(_counter.remaining) - delta)
		if float(_counter.remaining) <= 0.0:
			_counter.clear()

func on_original_hit(_target: Node2D, packet: Dictionary, result: Dictionary) -> void:
	if not _available() or int(packet.get("proc_depth", 0)) != 0 or not bool(packet.get("equipment_eligible", true)):
		return
	var hp_damage: float = float(result.get("hp_damage", 0.0))
	var shield_damage: float = float(result.get("shield_damage", 0.0))
	if not bool(result.get("confirmed", false)) or not is_finite(hp_damage) or not is_finite(shield_damage) or hp_damage < 0.0 or shield_damage < 0.0 or hp_damage + shield_damage <= 0.0:
		return
	var root: String = str(packet.get("root_event_id", packet.get("attack_id", "")))
	if root.is_empty():
		return
	var basic: bool = bool(packet.get("original_basic", false))
	var identifier: String = str(packet.get("skill_id", ""))
	if not basic and not identifier.begins_with("CH01_SK"):
		return
	owner_player.set("combat_time", 5.0)
	if basic:
		if _remember(_primary_roots, root):
			_gain_rage(10.0)
	elif _remember(_skill_roots, root):
		_gain_rage(8.0 + (10.0 if identifier == "CH01_SK01" and str(packet.get("branch", "")) == "B" else 0.0))
	_try_berserk()

func on_hurt(amount: float, _context: Dictionary = {}) -> void:
	if not _available() or not is_finite(amount) or amount <= 0.0:
		return
	owner_player.set("combat_time", 5.0)
	if incoming_rage_icd <= 0.0:
		_gain_rage(5.0)
		incoming_rage_icd = 1.0
	_try_berserk()
	if not _counter.is_empty():
		var captured: Dictionary = _counter.duplicate(true)
		_counter.clear()
		var counter_cast: Dictionary = {"skill_id":"CH01_SK10", "cast_id":int(captured.get("cast_id", 0)), "serial":int(captured.get("cast_id", 0)), "spec":{"slot":"skill", "origin_slot":"skill", "skill_id":"CH01_SK10", "damage_type":"physical", "radius":130.0}, "power":float(captured.power), "attacker_stats":captured.get("attacker_stats", {}), "paid_cost":float(captured.get("paid_cost", 0.0)), "direction":owner_player.aim_direction}
		_strike(counter_cast, owner_player.position, 130.0, 1.2, 1)
		_feedback("counter")

func on_skill_release(cast: Dictionary) -> Dictionary:
	var key: String = str(cast.get("skill_id", "")) + ":" + str(cast.get("cast_id", cast.get("serial", 0)))
	if not _remember(_release_roots, key):
		return {}
	return {"damage_multiplier":1.0, "shield_multiplier":1.0}

func primary_damage_multiplier() -> float:
	return 1.2 if berserk_remaining > 0.0 else 1.0

func damage_multiplier(skill_id: String) -> float:
	if berserk_remaining <= 0.0:
		return 1.0
	if skill_id == "CH01_SK04" and is_instance_valid(owner_player) and owner_player.has_method("skill_progress"):
		var progress: Dictionary = owner_player.skill_progress(skill_id)
		if str(progress.get("branch", "")) == "B" and int(progress.get("rank", progress.get("level", 1))) >= 5:
			return 1.4
	return 1.2

func attack_speed_multiplier() -> float:
	return 1.25 if berserk_remaining > 0.0 else 1.0

func movement_multiplier() -> float:
	return 1.1 if berserk_remaining > 0.0 else 1.0

func can_primary() -> bool:
	return true

func on_primary_created() -> void:
	pass

func on_dash_finished(_success: bool) -> void:
	pass

func timeline(data: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var start: float = float(data.get("windup", 0.0))
	if str(data.get("skill_id", "")) == "CH01_SK01":
		start += float(data.get("travel_time", 0.0)) if float(data.get("travel", 0.0)) > 0.0 else 0.0
	var offsets: Array = data.get("event_offsets", [0.0])
	for index in range(offsets.size()):
		events.append({"time":start + float(offsets[index]), "index":index})
	return events

func resolve_skill(cast: Dictionary, index: int) -> bool:
	if not _available() or not is_instance_valid(owner_player.room):
		return false
	var data: Dictionary = cast.get("spec", {})
	var identifier: String = str(cast.get("skill_id", data.get("skill_id", "")))
	var at: Vector2 = owner_player.position
	var direction: Vector2 = cast.get("direction", owner_player.aim_direction)
	match identifier:
		"CH01_SK01":
			_strike(cast, at, float(data.radius), float(data.coefficient), index, "", float(data.get("knockback", 0.0)))
			if float(data.get("aftershock_coefficient", 0.0)) > 0.0:
				_strike(cast, at, float(data.aftershock_radius), float(data.aftershock_coefficient), index + 1)
		"CH01_SK02":
			_strike(cast, at, float(data.radius), float(data.coefficient), index, "", float(data.get("knockback", 0.0)), float(data.arc))
		"CH01_SK03":
			_strike(cast, at, float(data.radius), float(data.coefficient), index, "", float(data.get("knockback", 0.0)))
			_guard(cast, data)
			owner_player.status.apply("brace_guard", float(data.damage_reduction), float(data.reduction_duration))
		"CH01_SK04":
			at = cast.get("target", at)
			_strike(cast, at, float(data.radius), float(data.coefficient), index, "", float(data.get("knockback", 0.0)))
		"CH01_SK05", "CH01_SK11":
			_strike(cast, at, float(data.radius), float(data.coefficient), index)
		"CH01_SK06":
			_guard(cast, data)
		"CH01_SK07":
			# Filter the direct hit candidates to a finite forward strip, then use
			# the central hit entry for normal resistance and equipment behavior.
			var hit_context: Dictionary = _hit_context(cast, index)
			for enemy: Node2D in owner_player.room.targets_in_radius(at, float(data.radius)):
				var offset: Vector2 = enemy.position - at
				if offset.dot(direction) < 0.0 or absf(offset.cross(direction)) > float(data.line_width) * 0.5:
					continue
				owner_player.room.resolve_direct_hit(enemy, _amount(cast, float(data.coefficient)), StringName(str(data.slot)), "", float(data.get("knockback", 0.0)), direction, hit_context)
			owner_player.room.add_ring(at + direction * float(data.radius) * 0.5, Color("db6248"), 42.0, 0.25)
		"CH01_SK08":
			var hits: Array = _strike(cast, at, float(data.radius), float(data.coefficient), index, "", 0.0, float(data.arc))
			for enemy: Node2D in hits:
				if is_instance_valid(enemy) and enemy.has_method("apply_knockback"):
					enemy.apply_knockback(enemy.position.direction_to(at), minf(float(data.pull), maxf(0.0, at.distance_to(enemy.position) - 30.0)))
		"CH01_SK09":
			var origin: Vector2 = cast.get("origin", at)
			var projectile_at: Vector2 = owner_player.room.move_actor(origin, direction * 19.0, 4.0)
			if index > 0:
				projectile_at = owner_player.room.move_actor(origin, direction * float(data.range), 4.0)
				direction = -direction
			var options: Dictionary = _hit_context(cast, index)
			options.merge({"source":"skill", "original":true, "speed":float(data.speed), "range":float(data.range), "pierce":int(data.pierce), "pierce_multiplier":1.0, "color":Color("db6248"), "heavy":true}, true)
			owner_player.room.spawn_ability_projectile(projectile_at, direction, _amount(cast, float(data.coefficient)), options)
		"CH01_SK10":
			_guard(cast, data)
			_counter = {"remaining":float(data.guard_duration), "power":float(cast.get("power", 0.0)), "cast_id":int(cast.get("cast_id", cast.get("serial", 0))), "attacker_stats":_value_dictionary(cast.get("attacker_stats", {})), "paid_cost":float(cast.get("paid_cost", 0.0))}
		"CH01_SK12":
			_strike(cast, at, float(data.radius), float(data.coefficient), index, str(data.get("applied_status", "chill")))
		_:
			return false
	return true

func _strike(cast: Dictionary, at: Vector2, radius: float, coefficient: float, index: int, applied_status: String = "", push: float = 0.0, arc: float = 360.0) -> Array:
	var data: Dictionary = cast.get("spec", {})
	var direction: Vector2 = cast.get("direction", owner_player.aim_direction)
	var hits: Array = owner_player.room.strike_area(at, radius, _amount(cast, coefficient), StringName(str(data.get("slot", "skill"))), applied_status, push, direction, arc, true, _hit_context(cast, index), true)
	if arc >= 360.0:
		owner_player.room.add_ring(at, Color("db6248"), radius, 0.25)
	return hits

func _amount(cast: Dictionary, coefficient: float) -> float:
	var stats: Dictionary = cast.get("attacker_stats", {})
	return float(Numbers.amount(coefficient * float(cast.get("power", 0.0)), int(stats.get("ruleset_version", Numbers.LEGACY))))

func _guard(cast: Dictionary, data: Dictionary) -> void:
	var multiplier: float = float(cast.get("guard_multiplier", 1.0))
	var frozen_stats: Dictionary = cast.get("attacker_stats", {})
	var max_hp: float = float(frozen_stats.get("max_hp", 0.0))
	owner_player.grant_guard(max_hp * float(data.guard) * multiplier, float(data.guard_duration), "hero_f" if str(data.skill_id) == "CH01_SK03" else "hero_skill:" + str(data.skill_id))

func _hit_context(cast: Dictionary, index: int) -> Dictionary:
	var data: Dictionary = cast.get("spec", {})
	var identifier: String = str(cast.get("skill_id", data.get("skill_id", "")))
	var serial: int = int(cast.get("cast_id", cast.get("serial", 0)))
	var result: Dictionary = cast.get("hit_context", {}).duplicate(true)
	var root: String = str(result.get("root_event_id", "skill:" + str(serial)))
	result.merge({"root_event_id":root, "attack_id":root + ":" + str(index), "cast_id":serial, "skill_id":identifier, "input_slot":str(cast.get("input_slot", "")), "skill_slot":str(data.get("origin_slot", "skill")), "branch":str(cast.get("branch", data.get("branch", ""))), "power":float(cast.get("power", 0.0)), "H":float(cast.get("base_power", cast.get("power", 0.0))), "attacker_stats":cast.get("attacker_stats", {}), "original_basic":false, "equipment_eligible":true, "damage_source":"skill", "damage_type":"physical", "proc_depth":0, "paid_cost":float(cast.get("paid_cost", 0.0))}, true)
	return result

func _gain_rage(unscaled_amount: float) -> void:
	owner_player.restore_class_resource(float(Numbers.scale(unscaled_amount, Game.run.ruleset_version())))

func on_valid_combat_event() -> void:
	# Equipment rage grants settle in the same confirmed combat event.
	_try_berserk()

func _try_berserk() -> void:
	if berserk_remaining > 0.0 or berserk_rearm_remaining > 0.0 or not _available():
		return
	var cap: float = float(Game.run.stats.get("resource_max", Numbers.scale(100.0, Game.run.ruleset_version())))
	if cap > 0.0 and Game.run.resource >= cap:
		berserk_remaining = BERSERK_DURATION
		_feedback("berserk_start")

func _feedback(kind: String) -> void:
	if not is_instance_valid(owner_player):
		return
	var feedback: Node = owner_player.get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback) and feedback.has_method("class_event"):
		feedback.class_event(kind, owner_player.position, owner_player.aim_direction)
	owner_player.queue_redraw()

func _available() -> bool:
	return is_instance_valid(owner_player) and Game.run != null and Game.run.hp > 0.0

func _remember(ledger: Array[String], key: String) -> bool:
	if key.is_empty() or key in ledger:
		return false
	ledger.append(key)
	if ledger.size() > LEDGER_LIMIT:
		ledger.pop_front()
	return true

func export_state() -> Dictionary:
	return {"version":2, "berserk_remaining":berserk_remaining, "berserk_rearm_remaining":berserk_rearm_remaining, "incoming_rage_icd":incoming_rage_icd, "primary_roots":_primary_roots.duplicate(), "skill_roots":_skill_roots.duplicate(), "release_roots":_release_roots.duplicate(), "counter":_value_dictionary(_counter)}

func restore_state(data: Dictionary) -> void:
	berserk_remaining = _finite_time(data.get("berserk_remaining", 0.0), BERSERK_DURATION)
	berserk_rearm_remaining = 0.0 if berserk_remaining > 0.0 else _finite_time(data.get("berserk_rearm_remaining", 0.0), REARM_DURATION)
	incoming_rage_icd = _finite_time(data.get("incoming_rage_icd", 0.0), 1.0)
	_primary_roots = _restore_ledger(data.get("primary_roots", []))
	_skill_roots = _restore_ledger(data.get("skill_roots", []))
	_release_roots = _restore_ledger(data.get("release_roots", []))
	_counter.clear()
	var captured: Variant = data.get("counter", {})
	if captured is Dictionary and _finite_time(captured.get("remaining", 0.0), 1.0) > 0.0 and (captured.get("power", null) is float or captured.get("power", null) is int):
		var power: float = float(captured.get("power", 0.0))
		if is_finite(power) and power >= 0.0:
			_counter = _value_dictionary(captured)
			_counter["remaining"] = _finite_time(captured.get("remaining", 0.0), 1.0)
			_counter["power"] = power

func hud_state() -> Dictionary:
	var active: bool = berserk_remaining > 0.0
	var phase: String = "berserk" if active else "rearm" if berserk_rearm_remaining > 0.0 else "normal"
	var cap: float = float(Game.run.stats.get("resource_max", 0.0)) if Game.run != null else 0.0
	var rage: float = float(Game.run.resource) if Game.run != null else 0.0
	return {"kind":"fury", "name":"怒气狂战", "rage":rage, "current":rage, "rage_max":cap, "max":cap, "phase":phase, "remaining":berserk_remaining if active else berserk_rearm_remaining, "duration":BERSERK_DURATION if active else REARM_DURATION if phase == "rearm" else 0.0, "berserk_active":active, "berserk_remaining":berserk_remaining, "rearm_remaining":berserk_rearm_remaining, "incoming_rage_icd":incoming_rage_icd, "ready":not active and berserk_rearm_remaining <= 0.0, "damage_multiplier":primary_damage_multiplier(), "attack_speed_multiplier":attack_speed_multiplier(), "movement_multiplier":movement_multiplier(), "description":"有效普攻+10怒，技能首次有效命中+8怒，受击+5怒（1秒冷却）。满怒触发8秒狂暴。", "hint":"狂暴：伤害+20% / 普攻攻速+25% / 移速+10%" if active else "狂暴再触发锁定" if phase == "rearm" else "持续进攻积怒；脱战5秒后每秒衰减10怒"}

static func _finite_time(value: Variant, ceiling: float) -> float:
	if not (value is float or value is int):
		return 0.0
	var number: float = float(value)
	return clampf(number, 0.0, ceiling) if is_finite(number) else 0.0

static func _restore_ledger(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry: Variant in value:
			if entry is String and not entry.is_empty() and entry.length() <= 192 and entry not in result:
				result.append(entry)
				if result.size() >= LEDGER_LIMIT:
					break
	return result

static func _value_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in value:
		if not key is String:
			continue
		var item: Variant = value[key]
		if item is bool or item is String or item is int or item is float and is_finite(item):
			result[key] = item
		elif item is Dictionary:
			result[key] = _value_dictionary(item)
	return result

static func validate_state(data: Dictionary) -> bool:
	if data.is_empty():
		return true
	if not _valid_number(data.get("version", null), 2.0, 2.0):
		return false
	for entry: Array in [["berserk_remaining",8.0], ["berserk_rearm_remaining",3.0], ["incoming_rage_icd",1.0]]:
		if not _valid_number(data.get(entry[0], null), 0.0, float(entry[1])):
			return false
	if float(data.berserk_remaining) > 0.0 and float(data.berserk_rearm_remaining) > 0.0:
		return false
	for field: String in ["primary_roots", "skill_roots", "release_roots"]:
		var ledger: Variant = data.get(field, null)
		if not ledger is Array or ledger.size() > LEDGER_LIMIT:
			return false
		var seen: Array[String] = []
		for key: Variant in ledger:
			if not key is String or key.is_empty() or key.length() > 192 or key in seen:
				return false
			seen.append(key)
	var captured: Variant = data.get("counter", null)
	if not captured is Dictionary:
		return false
	if not captured.is_empty():
		if not _valid_number(captured.get("remaining", null), 0.0, 1.0) or not _valid_number(captured.get("power", null), 0.0, 1000000000000.0) or not _valid_number(captured.get("paid_cost", null), 0.0, 1000000000000.0):
			return false
		var serial: Variant = captured.get("cast_id", null)
		if not (serial is int or serial is float) or not is_finite(float(serial)) or float(serial) < 0.0 or float(serial) > 9007199254740991.0 or floor(float(serial)) != float(serial):
			return false
		if not captured.get("attacker_stats", null) is Dictionary or not _json_values(captured.attacker_stats):
			return false
	return _json_values(data)

static func _valid_number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _json_values(value: Variant) -> bool:
	if value is bool or value is String or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item: Variant in value:
			if not _json_values(item):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_values(value[key]):
				return false
		return true
	return false