extends RefCounted
## CH02 owns ammunition and reload timing. Skill energy is paid by HeroAbilities.
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const CAPACITY: int = 8
const RELOAD_SECONDS: float = 1.0
const PRECISION_START: float = 0.45
const PRECISION_END: float = 0.65
const ENHANCED_DAMAGE: float = 1.20

var owner_player: Node2D
var ammo: int = CAPACITY
var enhanced_shots: int = 0
var reloading: bool = false
var reload_elapsed: float = 0.0
var precision_attempted: bool = false
var reload_serial: int = 0
var last_reload_result: String = ""
var last_reload_reason: String = ""
var _primary_enhanced_pending: bool = false
var _released_serial: int = -1
var _finished_serial: int = -1
var _chain_roots: Dictionary = {}

static func skill_specs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(Numbers.value("class_skill_specs", {}).get("CH02", []))
	var names_en: Array[String] = ["Skirmisher Retreat", "Rail Piercer", "Shock Grenade", "Bullet Barrage", "Fan Volley", "Smoke Step", "Explosive Round", "Binding Mine", "Ricochet Chain", "Tactical Reload", "Suppressive Fire", "Rail Sentry"]
	var descriptions: Array[String] = [
		"后撤并连续射出三发技能弹，完成后补充两发普通弹；技能弹不消耗弹匣。",
		"蓄力发射贯穿弹，穿过首个目标后命中第二目标；熟练度Lv.2取消后续目标伤害衰减。",
		"向合法落点投掷榴弹，0.5秒后范围爆炸并击退，投出后取消动作不影响已投出的榴弹。",
		"连续射出四发技能弹，射击方向可缓慢调整；技能弹不消耗普通弹匣。",
		"同时发射三发扇形技能弹，每发造成0.5H伤害。",
		"向施法方向移动120，并在实际释放时获得一秒30%减伤。",
		"发射爆裂弹，在命中位置产生范围爆炸，整次爆炸为1.6H。",
		"布置一枚八秒缚足雷，敌人靠近时爆炸并短暂定身；最多存在两枚，首领承受较弱的移动控制。",
		"首发弹命中后，在视线范围内跳射最多两个不同目标，每目标0.6H。",
		"第一次实际释放时装满八发弹匣，并将接下来三发原始普攻强化20%；起手取消不补弹。",
		"连续射出六发技能弹，总伤害3.0H，射击期间可移动。",
		"布置一台磁轨哨机，三秒内每半秒寻找合法目标射击一次，共六次、总预算2.4H；最多一台。",
	]
	for index in range(result.size()):
		result[index]["skill_id"] = "CH02_SK%02d" % (index + 1)
		result[index]["hero"] = "CH02"
		result[index]["hero_id"] = "CH02"
		result[index]["name_en"] = names_en[index]
		result[index]["description"] = descriptions[index]
		result[index]["damage_type"] = "physical"
		if index in [0, 3]:
			var labels: Dictionary = {"A":"轻步游击", "B":"弹匣回补"} if index == 0 else {"A":"密集弹幕", "B":"装填终势"}
			var branch_descriptions: Dictionary = result[index].branch_descriptions
			result[index]["branches"] = {"A":{"name":str(labels.A), "description":str(branch_descriptions.A)}, "B":{"name":str(labels.B), "description":str(branch_descriptions.B)}}
		if not result[index].has("origin_slot"):
			result[index]["origin_slot"] = "skill"
	return result

func configure(player: Node2D) -> void:
	owner_player = player
	ammo = CAPACITY
	enhanced_shots = 0
	_cancel_reload()
	last_reload_result = ""
	last_reload_reason = ""
	_primary_enhanced_pending = false
	_released_serial = -1
	_finished_serial = -1
	_chain_roots.clear()

func tick(delta: float) -> void:
	if not is_finite(delta) or delta < 0.0:
		return
	if not _available():
		if reloading:
			on_death()
		return
	if not reloading:
		if ammo != 0:
			return
		# An empty magazine remains empty across rooms, then starts a fresh reload.
		_start_reload()
	reload_elapsed = minf(RELOAD_SECONDS, reload_elapsed + delta)
	if reload_elapsed >= RELOAD_SECONDS:
		_finish_reload(reload_serial, false)

func request_reload() -> bool:
	if not _available():
		last_reload_reason = "unavailable"
		return false
	if not reloading:
		if ammo >= CAPACITY:
			last_reload_reason = "reload_full"
			return false
		_start_reload()
		last_reload_reason = "accepted"
		return true
	if precision_attempted:
		last_reload_reason = "reload_attempt_used"
		return false
	precision_attempted = true
	var progress: float = reload_elapsed / RELOAD_SECONDS
	if _in_precision_window(progress):
		last_reload_reason = "reload_precision"
		return _finish_reload(reload_serial, true)
	last_reload_result = "missed"
	last_reload_reason = "reload_missed"
	_feedback("reload_missed")
	return true

func _start_reload() -> void:
	reload_serial += 1
	reloading = true
	reload_elapsed = 0.0
	precision_attempted = false
	last_reload_result = "reloading"
	_feedback("reload_start")

func _finish_reload(serial: int, precise: bool) -> bool:
	if not reloading or serial != reload_serial:
		return false
	ammo = CAPACITY
	if precise:
		enhanced_shots = 3
	_cancel_reload()
	last_reload_result = "precision" if precise else "normal"
	_feedback("reload_success" if precise else "reload_complete")
	return true

func _feedback(kind: String) -> void:
	if not is_instance_valid(owner_player):
		return
	var feedback: Node = owner_player.get_node_or_null("HeroFeedback")
	if is_instance_valid(feedback) and feedback.has_method("class_event"):
		feedback.class_event(kind, owner_player.position, owner_player.aim_direction)
	if is_instance_valid(owner_player.room):
		var audio: Variant = owner_player.room.get("combat_audio")
		if is_instance_valid(audio) and audio.has_method("reload"):
			audio.reload(kind)
	owner_player.queue_redraw()

func _cancel_reload() -> void:
	reload_serial += 1
	reloading = false
	reload_elapsed = 0.0
	precision_attempted = false

func can_primary() -> bool:
	return ammo > 0 and not reloading

func primary_damage_multiplier() -> float:
	# The attack samples its enhancement before windup; failed creation spends none.
	_primary_enhanced_pending = enhanced_shots > 0
	return ENHANCED_DAMAGE if _primary_enhanced_pending else 1.0

func on_primary_created() -> void:
	if ammo <= 0:
		return
	ammo -= 1
	if _primary_enhanced_pending and enhanced_shots > 0:
		enhanced_shots -= 1
	_primary_enhanced_pending = false
	if ammo == 0:
		_start_reload()

func damage_multiplier(_skill_id: String) -> float:
	return 1.0

func attack_speed_multiplier() -> float:
	return 1.0

func movement_multiplier() -> float:
	return 1.0

func on_original_hit(target: Node2D, packet: Dictionary, result: Dictionary) -> void:
	if not _available() or not is_instance_valid(target) or not bool(result.get("confirmed", false)):
		return
	if _skill_id(packet) != "CH02_SK09" or int(packet.get("proc_depth", 0)) != 0 or bool(packet.get("original_basic", false)):
		return
	var chain: Dictionary = packet.get("gunner_chain", {})
	var root: String = str(packet.get("root_event_id", ""))
	if chain.is_empty() or root.is_empty() or _chain_roots.has(root):
		return
	_chain_roots[root] = true
	while _chain_roots.size() > 128:
		_chain_roots.erase(_chain_roots.keys()[0])
	var room: Node2D = owner_player.room
	var origin: Vector2 = target.position
	var excluded: Array[int] = [target.get_instance_id()]
	var context: Dictionary = packet.duplicate(true)
	context.erase("gunner_chain")
	for index in range(mini(2, int(chain.get("remaining", 2)))):
		var next: Node2D = _nearest_target(room, origin, float(chain.get("range", 200.0)), excluded)
		if not is_instance_valid(next):
			break
		excluded.append(next.get_instance_id())
		context["attack_id"] = root + ":chain:" + str(index + 1)
		var direction: Vector2 = origin.direction_to(next.position)
		room.add_arc_between(origin, next.position)
		room.resolve_direct_hit(next, float(chain.get("amount", 0.0)), StringName(packet.get("source", "skill")), "", 0.0, direction, context)
		origin = next.position

func on_skill_release(cast: Dictionary) -> Dictionary:
	if not _available():
		return {"damage_multiplier":1.0}
	var serial: int = _cast_serial(cast)
	if serial <= _released_serial:
		return {"damage_multiplier":1.0}
	_released_serial = serial
	if _skill_id(cast) == "CH02_SK10":
		_tactical_reload()
	return {"damage_multiplier":1.0}

func on_dash_finished(success: bool) -> void:
	if success and _available():
		_refill(2)

func on_skill_finished(cast: Dictionary) -> void:
	var serial: int = _cast_serial(cast)
	if serial <= _finished_serial:
		return
	_finished_serial = serial
	if not _available():
		return
	var identifier: String = _skill_id(cast)
	var branch: String = str(cast.get("branch", cast.get("spec", {}).get("branch", "")))
	if identifier == "CH02_SK01":
		_refill(4 if branch == "B" else 2)
	elif identifier == "CH02_SK04" and branch == "B":
		_tactical_reload()

func _refill(count: int) -> void:
	_cancel_reload()
	ammo = mini(CAPACITY, ammo + maxi(0, count))
	last_reload_result = "refill"

func restore_ammo(amount: int) -> void:
	# Equipment replenishes ordinary rounds without cancelling or perfecting reload.
	ammo = mini(CAPACITY, ammo + maxi(0, amount))

func _tactical_reload() -> void:
	_cancel_reload()
	ammo = CAPACITY
	enhanced_shots = 3
	last_reload_result = "tactical"

func on_room_changed() -> void:
	_cancel_reload()
	_primary_enhanced_pending = false
	last_reload_result = ""
	last_reload_reason = ""
	_released_serial = -1
	_finished_serial = -1
	_chain_roots.clear()

func on_death() -> void:
	on_room_changed()

func export_state() -> Dictionary:
	return {"version":2, "ammo":ammo, "capacity":CAPACITY, "enhanced_shots":enhanced_shots, "reloading":reloading, "reload_elapsed":reload_elapsed, "precision_attempted":precision_attempted, "reload_serial":reload_serial, "last_reload_result":last_reload_result, "released_serial":_released_serial, "finished_serial":_finished_serial}

func restore_state(data: Dictionary) -> bool:
	# Missing class state is the old-save migration: a single full ordinary magazine.
	if data.is_empty():
		configure(owner_player)
		return true
	if not validate_state(data):
		return false
	ammo = int(data.ammo)
	enhanced_shots = int(data.enhanced_shots)
	reloading = bool(data.reloading)
	reload_elapsed = float(data.reload_elapsed)
	precision_attempted = bool(data.precision_attempted)
	reload_serial = int(data.reload_serial)
	last_reload_result = str(data.last_reload_result)
	_released_serial = int(data.released_serial)
	_finished_serial = int(data.finished_serial)
	_primary_enhanced_pending = false
	_chain_roots.clear()
	return true

static func validate_state(data: Dictionary) -> bool:
	if data.size() != 11:
		return false
	if not _valid_integer(data.get("version"), 2, 2) or not _valid_integer(data.get("capacity"), CAPACITY, CAPACITY):
		return false
	if not _valid_integer(data.get("ammo"), 0, CAPACITY) or not _valid_integer(data.get("enhanced_shots"), 0, 3):
		return false
	if not (data.get("reloading") is bool) or not (data.get("precision_attempted") is bool):
		return false
	var clock: Variant = data.get("reload_elapsed")
	if not (clock is float or clock is int) or not is_finite(float(clock)) or float(clock) < 0.0 or float(clock) >= RELOAD_SECONDS:
		return false
	if not _valid_integer(data.get("reload_serial"), 0, 2147483647):
		return false
	if not _valid_integer(data.get("released_serial"), -1, 2147483647) or not _valid_integer(data.get("finished_serial"), -1, 2147483647):
		return false
	if not bool(data.reloading) and (float(clock) != 0.0 or bool(data.precision_attempted)):
		return false
	var result: Variant = data.get("last_reload_result")
	if not (result is String) or str(result) not in ["", "reloading", "missed", "precision", "normal", "refill", "tactical"]:
		return false
	return true

func hud_state() -> Dictionary:
	var progress: float = reload_elapsed / RELOAD_SECONDS if reloading else 0.0
	var in_window: bool = reloading and not precision_attempted and _in_precision_window(progress)
	var phase: String = "reloading" if reloading else "enhanced" if enhanced_shots > 0 else "ready"
	return {"kind":"reload", "hero_id":"CH02", "name":"机动装填", "phase":phase, "ammo":ammo, "capacity":CAPACITY, "reloading":reloading, "reload_progress":progress, "reload_remaining":RELOAD_SECONDS - reload_elapsed if reloading else 0.0, "reload_duration":RELOAD_SECONDS, "precision_window_start":PRECISION_START, "precision_window_end":PRECISION_END, "precision_window_active":in_window, "in_window":in_window, "precision_attempted":precision_attempted, "enhanced_shots":enhanced_shots, "enhanced_remaining":enhanced_shots, "empowered_rounds":enhanced_shots, "enhanced_damage_multiplier":ENHANCED_DAMAGE, "last_reload_result":last_reload_result, "reload_action":"reload", "reload_key":_reload_key()}

func _reload_key() -> String:
	var settings: Dictionary = Game.profile.get("settings", {})
	return ControlBindings.label_for("reload", settings.get("controls", {}), Words.locale)

func _available() -> bool:
	return is_instance_valid(owner_player) and Game.run != null and Game.run.hp > 0.0

static func _in_precision_window(progress: float) -> bool:
	return progress >= PRECISION_START - 0.00000001 and progress <= PRECISION_END + 0.00000001

static func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and int(value) >= minimum and int(value) <= maximum

static func _cast_serial(cast: Dictionary) -> int:
	return int(cast.get("serial", cast.get("cast_id", -1)))

static func _skill_id(cast: Dictionary) -> String:
	return str(cast.get("skill_id", cast.get("spec", {}).get("skill_id", "")))

func timeline(data: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var start: float = float(data.get("windup", 0.0))
	var kind: String = str(data.get("kind", ""))
	if kind == "retreat_burst":
		start += float(data.get("travel_time", 0.16))
		for index in range(3):
			events.append({"time":start + 0.06 * index, "index":index})
	elif kind in ["barrage", "suppression_barrage"]:
		var count: int = clampi(int(data.get("shots", 4)), 1, 6)
		for index in range(count):
			events.append({"time":start + 0.72 * index / float(maxi(1, count - 1)), "index":index})
	else:
		events.append({"time":start, "index":0})
	return events

func can_release(cast: Dictionary, _index: int) -> bool:
	if not _available() or not is_instance_valid(owner_player.room):
		return false
	var room: Node2D = owner_player.room
	var data: Dictionary = cast.get("spec", {})
	var kind: String = str(data.get("kind", ""))
	if kind in ["retreat_burst", "piercing_projectile", "barrage", "suppression_barrage", "explosive_projectile", "chain_projectile", "fan_projectiles"]:
		var required: int = 3 if kind == "fan_projectiles" else 1
		var projectiles: Variant = room.get("projectiles")
		return is_instance_valid(projectiles) and projectiles.get_child_count() + required <= Balance.MAX_PROJECTILES
	if kind in ["grenade", "root_mine", "sentry"]:
		var target: Vector2 = Vector2(cast.get("target", owner_player.position))
		return target.is_finite() and room.valid_ground(target, 14.0) and room.has_line_of_sight(owner_player.position, target)
	return kind in ["smoke_step", "tactical_reload"]

func resolve_skill(cast: Dictionary, index: int) -> bool:
	if not _available() or not is_instance_valid(owner_player.room):
		return false
	var data: Dictionary = cast.get("spec", {})
	var kind: String = str(data.get("kind", ""))
	var room: Node2D = owner_player.room
	var direction: Vector2 = Vector2(cast.get("direction", Vector2.RIGHT)).normalized()
	var power: float = float(cast.get("power", 0.0))
	var stats: Dictionary = cast.get("attacker_stats", {})
	var context: Dictionary = cast.get("hit_context", {}).duplicate(true)
	var source: String = str(data.get("origin_slot", "skill"))
	var at: Vector2 = owner_player.position
	if direction.is_zero_approx() or not direction.is_finite() or not is_finite(power):
		return false
	context["source"] = source
	context["attack_id"] = str(context.get("root_event_id", "skill:" + str(_cast_serial(cast)))) + ":" + str(index)
	var amount: float = float(Numbers.amount(float(data.get("coefficient", 0.0)) * power, int(stats.get("ruleset_version", Numbers.LEGACY))))
	match kind:
		"retreat_burst", "piercing_projectile", "barrage", "suppression_barrage", "explosive_projectile", "chain_projectile":
			var options: Dictionary = _projectile_options(data, context, source)
			if kind == "chain_projectile":
				options["gunner_chain"] = {"amount":amount, "remaining":2, "range":float(data.get("chain_range", 200.0))}
			var projectile: Node2D = room.spawn_ability_projectile(_projectile_origin(room, at, direction), direction, amount, options)
			if kind == "barrage" and is_instance_valid(projectile):
				cast["b06_fired_rounds"] = int(cast.get("b06_fired_rounds", 0)) + 1
				if owner_player.loadout != null:
					var shot: Dictionary = context.duplicate(true)
					shot["r_shot_ordinal"] = int(cast.b06_fired_rounds)
					shot["event_id"] = str(context.attack_id) + ":fired"
					var bonus: Dictionary = owner_player.loadout.b06_r_shot(shot)
					if not bonus.is_empty():
						projectile.options["b06_r_bonus"] = bonus
			return is_instance_valid(projectile)
		"fan_projectiles":
			var created: bool = false
			for fan_index in range(3):
				var shot_direction: Vector2 = direction.rotated(deg_to_rad(float(data.get("spread", 18.0))) * (fan_index - 1))
				var shot_context: Dictionary = context.duplicate(true)
				shot_context["attack_id"] = str(context.attack_id) + ":fan:" + str(fan_index)
				var projectile: Node2D = room.spawn_ability_projectile(_projectile_origin(room, at, shot_direction), shot_direction, amount, _projectile_options(data, shot_context, source))
				created = is_instance_valid(projectile) or created
			return created
		"smoke_step":
			return owner_player.status.apply("damage_reduction", float(data.get("damage_reduction", 0.30)), float(data.get("guard_duration", 1.0)))
		"tactical_reload":
			# The first-release hook owns the refill, so this event cannot grant twice.
			return true
		"grenade", "root_mine", "sentry":
			var target: Vector2 = Vector2(cast.get("target", at))
			if not target.is_finite() or not room.valid_ground(target, 14.0) or not room.has_line_of_sight(at, target):
				return false
			var device := GunnerDevice.new()
			device.position = target
			device.configure(room, owner_player, self, kind, data, context, amount)
			_limit_devices(room, kind, int(data.get("maximum", 1 if kind == "sentry" else 2)))
			room.add_child(device)
			return true
	return false

static func _projectile_options(data: Dictionary, context: Dictionary, source: String) -> Dictionary:
	var options: Dictionary = context.duplicate(true)
	options.merge({"source":source, "original":true, "speed":float(data.get("speed", 1000.0)), "range":float(data.get("range", 620.0)), "pierce":int(data.get("pierce", 0)), "pierce_multiplier":float(data.get("pierce_multiplier", 1.0)), "explosion_radius":float(data.get("explosion_radius", 0.0)), "color":Color("dfd19c"), "heavy":str(data.get("kind", "")) == "piercing_projectile", "visual_hero":"CH02"}, true)
	return options

static func _projectile_origin(room: Node2D, at: Vector2, direction: Vector2) -> Vector2:
	return room.move_actor(at, direction * 19.0, 4.0)

static func _nearest_target(room: Node2D, at: Vector2, radius: float, excluded: Array[int] = []) -> Node2D:
	var nearest: Node2D = null
	var distance: float = INF
	for target: Node2D in room.targets_in_radius(at, radius):
		if not is_instance_valid(target) or not target.is_alive() or target.get_instance_id() in excluded or not room.has_line_of_sight(at, target.position):
			continue
		var next_distance: float = at.distance_squared_to(target.position)
		if next_distance < distance or (is_equal_approx(next_distance, distance) and (not is_instance_valid(nearest) or target.get_instance_id() < nearest.get_instance_id())):
			nearest = target
			distance = next_distance
	return nearest

static func _limit_devices(room: Node2D, kind: String, maximum: int) -> void:
	var existing: Array[Node2D] = []
	for deployment: Node2D in room.get_tree().get_nodes_in_group("hero_deployments"):
		if deployment.get("room") == room and str(deployment.get("kind")) == "gunner_" + kind and deployment.is_alive():
			existing.append(deployment)
	while existing.size() >= maxi(1, maximum):
		existing.pop_front().retire()

class GunnerDevice extends Node2D:
	var room: Node2D
	var owner_player: Node2D
	var kit: RefCounted
	var kind: String
	var data: Dictionary = {}
	var context: Dictionary = {}
	var damage: float = 0.0
	var elapsed: float = 0.0
	var lifetime: float = 0.0
	var alive: bool = true
	var shots_emitted: int = 0
	var fire_direction := Vector2.RIGHT
	var flash_remaining: float = 0.0

	func configure(host: Node2D, player: Node2D, controller: RefCounted, device_kind: String, specification: Dictionary, packet: Dictionary, amount: float) -> void:
		room = host
		owner_player = player
		kit = controller
		kind = "gunner_" + device_kind
		data = specification.duplicate(true)
		context = packet.duplicate(true)
		damage = amount
		lifetime = float(data.get("fuse", 0.5)) if device_kind == "grenade" else float(data.get("lifetime", 3.0))
		add_to_group("hero_deployments")
		z_index = 1

	func is_alive() -> bool:
		return alive and not is_queued_for_deletion()

	func is_active() -> bool:
		return is_alive()

	func retire(_destroyed: bool = false) -> void:
		if not alive:
			return
		alive = false
		queue_free()

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(room) or not is_instance_valid(owner_player) or Game.run == null or Game.run.hp <= 0.0:
			retire()
			return
		advance(delta)

	func advance(delta: float) -> void:
		if not is_alive() or not is_finite(delta) or delta < 0.0:
			return
		var previous: float = elapsed
		elapsed += delta
		flash_remaining = maxf(0.0, flash_remaining - delta)
		if kind == "gunner_grenade" and elapsed + 0.00001 >= lifetime:
			_blast(false)
			return
		if kind == "gunner_root_mine" and elapsed >= 0.2 and previous < lifetime:
			if is_instance_valid(kit._nearest_target(room, position, float(data.get("radius", 95.0)))):
				_blast(true)
				return
		if kind == "gunner_sentry":
			while shots_emitted < 6 and (shots_emitted + 1) * 0.5 <= minf(elapsed, lifetime) + 0.00001:
				shots_emitted += 1
				_fire_sentry()
		if elapsed >= lifetime:
			retire()
		else:
			queue_redraw()

	func _blast(root: bool) -> void:
		# Retire before resolving: callbacks and large deltas cannot repeat the blast.
		alive = false
		var radius: float = float(data.get("radius", 95.0))
		var direction: Vector2 = Vector2(context.get("b05_direction", Vector2.RIGHT))
		var hits: Array = room.strike_area(position, radius, damage, StringName(context.get("source", "skill")), "", float(data.get("knockback", 0.0)), direction, 360.0, true, context, true)
		if root:
			for target: Node2D in hits:
				if is_instance_valid(target) and target.is_alive() and target.has_method("apply_ordinary_slow"):
					# Existing bosses resist movement control; ordinary foes are briefly rooted.
					target.apply_ordinary_slow(0.75 if str(target.get("rank")) == "boss" else 0.0, float(data.get("root_duration", 0.65)))
		room.add_ring(position, Color("efcb76"), radius, 0.3)
		queue_free()

	func _fire_sentry() -> void:
		var target: Node2D = kit._nearest_target(room, position, float(data.get("attack_range", 620.0)))
		if not is_instance_valid(target):
			return
		fire_direction = position.direction_to(target.position)
		var shot: Dictionary = context.duplicate(true)
		shot["attack_id"] = str(context.get("root_event_id", "")) + ":sentry:" + str(shots_emitted)
		shot.merge({"source":"skill", "original":true, "speed":float(data.get("speed", 1150.0)), "range":float(data.get("attack_range", 620.0)), "color":Color("efd39d"), "visual_hero":"CH02", "deployment_origin":true}, true)
		var muzzle: Vector2 = room.move_actor(position, fire_direction * 14.0, 4.0)
		if is_instance_valid(room.spawn_ability_projectile(muzzle, fire_direction, damage, shot)):
			flash_remaining = 0.12
			room.add_ring(position, Color("e6c578"), 16.0, 0.12)

	func _draw() -> void:
		var brass := Color("d6b660")
		var ink := Color("454936")
		var olive := Color("879161")
		if kind == "gunner_sentry":
			for index in range(3):
				var axis: Vector2 = Vector2.RIGHT.rotated(index * TAU / 3.0)
				draw_line(Vector2(0, -6), axis * 19.0, ink, 5.0, true)
				draw_line(Vector2(0, -6), axis * 19.0, brass, 2.0, true)
			draw_circle(Vector2(0, -9), 10.0, ink)
			draw_circle(Vector2(0, -9), 7.5, olive)
			draw_line(Vector2(0, -9), Vector2(0, -9) + fire_direction * 25.0, ink, 8.0, true)
			draw_line(Vector2(0, -9), Vector2(0, -9) + fire_direction * 25.0, brass, 3.5, true)
			if flash_remaining > 0.0:
				draw_circle(Vector2(0, -9) + fire_direction * 28.0, 5.0, Color("fff1b5"))
		else:
			var radius: float = float(data.get("radius", 95.0))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(brass, 0.5), 1.5, true)
			draw_circle(Vector2(0, -5), 13.0, ink)
			draw_circle(Vector2(0, -5), 10.0, olive)
			draw_arc(Vector2(0, -5), 10.0, 0.0, TAU, 24, brass, 2.0, true)
			for index in range(4):
				var axis: Vector2 = Vector2.RIGHT.rotated(index * PI * 0.5)
				draw_line(Vector2(0, -5) + axis * 4.0, Vector2(0, -5) + axis * 16.0, brass, 2.0, true)
			draw_circle(Vector2(0, -5), 3.0, Color("fff1b5"))
