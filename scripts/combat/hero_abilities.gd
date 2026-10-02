class_name HeroAbilities
extends RefCounted
## Each successful cast owns a finite timeline. Cancellation drops only future
## events; cost, cooldown, fired projectiles and deployed objects remain committed.

const Numbers = preload("res://config/numerical_rules.gd")
const FeedbackScript = preload("res://scripts/combat/hero_feedback.gd")

var owner_player: Node2D
var feedback: Node2D
var active: Dictionary = {}
var last_failure: String = ""
var last_failure_details: Dictionary = {}
var cast_serial: int = 0

func configure(player: Node2D) -> void:
	owner_player = player
	feedback = owner_player.get_node_or_null("HeroFeedback")
	if not is_instance_valid(feedback):
		feedback = FeedbackScript.new()
		feedback.configure(owner_player)
		owner_player.add_child(feedback)
	cancel()

func busy() -> bool:
	return not active.is_empty()

func recovery_chain_wait() -> float:
	if active.is_empty():
		return 0.0
	# A follow-up may trim only recovery. All shots, waves and authored travel
	# belong to the committed action and must finish before its next action.
	var data: Dictionary = active.spec
	var release_end: float = float(data.windup)
	var events: Array[Dictionary] = active.events
	if not events.is_empty():
		release_end = maxf(release_end, float(events.back().time))
	if float(data.get("travel", 0.0)) > 0.0:
		release_end = maxf(release_end, float(data.windup) + float(data.get("travel_time", 0.0)))
	var contact_recovery: float = 0.07 if str(data.slot) in ["secondary", "ultimate"] else 0.06
	if str(data.slot) == "f" or (str(data.hero) == "CH03" and str(data.slot) == "secondary"):
		contact_recovery = 0.045
	var chain_at: float = minf(float(data.duration), release_end + contact_recovery)
	return maxf(0.0, chain_at - float(active.elapsed))

func recovery_chain_ready() -> bool:
	if active.is_empty():
		return true
	return int(active.next_event) >= active.events.size() and recovery_chain_wait() <= 0.00001

func cancel() -> void:
	active.clear()
	if is_instance_valid(feedback):
		feedback.cancel_cast()

func movement_scale() -> float:
	if active.is_empty():
		return 1.0
	var data: Dictionary = active.spec
	var clock: float = float(active.elapsed)
	if float(data.get("travel", 0.0)) > 0.0 and clock >= float(data.windup) and clock < float(data.windup) + float(data.get("travel_time", 0.0)):
		return 0.0
	return float(data.get("movement", 1.0))

func hero_key() -> String:
	var identifier: String = owner_player.hero_id() if is_instance_valid(owner_player) else "CH01"
	return {"breaker":"CH01", "ranger":"CH02", "resonator":"CH03"}.get(identifier, identifier)

static func preview_spec(hero_id: String, level: int, stats: Dictionary, slot: String) -> Dictionary:
	var helper := HeroAbilities.new()
	return helper.spec(slot, hero_id, level, stats)

## Preview and live actors share the three source-specific H definitions. AD
## remains a separate aggregated stat; basic AP must never enter skill H twice.
static func preview_powers(hero: String, stats: Dictionary) -> Dictionary:
	var version: int = int(stats.get("ruleset_version", Numbers.LEGACY))
	var fallback: float = 27.0 if hero == "CH01" else 24.0 if hero == "CH02" else 18.0
	var attack: Variant = Numbers.amount(float(stats.get("attack", Numbers.scale(fallback, version))), version)
	var ability: Variant = Numbers.amount(float(stats.get("ability_power", 0.0)), version)
	var ratios: Dictionary = Numbers.value("mage_power_ratios")
	return {
		"basic_H":Numbers.amount(float(attack) + (float(ratios.basic_ap) * float(ability) if hero == "CH03" and version == Numbers.V2 else 0.0), version),
		"skill_H":Numbers.amount(float(attack) + (float(ratios.skill_ap) * float(ability) if hero == "CH03" else 0.0), version),
		"relic_H":Numbers.amount(float(stats.get("ability_power", Numbers.scale(28.0, version))), version) if hero == "CH03" else attack,
	}

static func packet_amount(coefficient: float, power: float, stats: Dictionary) -> Variant:
	return Numbers.amount(coefficient * power, int(stats.get("ruleset_version", Numbers.LEGACY)))

func spec(slot: String, preview_hero: String = "", preview_level: int = -1, preview_stats: Dictionary = {}) -> Dictionary:
	var preview: bool = not preview_hero.is_empty()
	var hero: String = preview_hero if preview else hero_key()
	var level: int = preview_level if preview else owner_player.hero_level() if is_instance_valid(owner_player) else 1
	var effective_stats: Dictionary = preview_stats if preview else Game.run.stats if Game.run != null else {}
	var data: Dictionary = {}
	if hero == "CH01":
		match slot:
			"q": data = {"name":"破阵冲锋", "cost":15.0 if level >= 10 else 20.0, "cooldown":6.0, "windup":0.10, "duration":0.42, "travel":160.0, "travel_time":0.18, "coefficient":1.5, "radius":75.0, "knockback":45.0, "movement":0.65}
			"secondary": data = {"name":"裂地重斩", "cost":30.0, "cooldown":4.0, "windup":0.18, "duration":0.46 if level >= 12 else 0.54, "coefficient":2.2, "radius":115.0, "arc":120.0, "knockback":65.0, "movement":0.65}
			"f": data = {"name":"铁壁战吼", "cost":25.0, "cooldown":11.0, "windup":0.12, "duration":0.38, "coefficient":0.6, "radius":100.0, "knockback":70.0, "guard":0.18 if level >= 14 else 0.12, "damage_reduction":0.25, "guard_duration":1.5, "movement":0.8}
			"ultimate": data = {"name":"天崩斧落", "cost":70.0, "cooldown":42.0, "windup":0.45, "duration":1.02, "coefficient":4.6 if level >= 16 else 4.0, "radius":180.0, "range":130.0, "knockback":90.0, "movement":0.35}
	elif hero == "CH02":
		match slot:
			"q": data = {"name":"游击撤射", "cost":20.0 if level >= 10 else 25.0, "cooldown":7.0, "windup":0.06, "duration":0.42, "travel":150.0, "travel_time":0.16, "coefficient":0.35, "range":450.0, "speed":950.0, "movement":0.8}
			"secondary": data = {"name":"磁轨贯穿", "cost":30.0, "cooldown":3.5, "windup":0.45, "duration":0.66, "coefficient":2.0, "range":780.0, "speed":1300.0, "pierce":1, "pierce_multiplier":1.0 if level >= 12 else 0.65, "movement":0.65}
			"f": data = {"name":"震爆榴弹", "cost":30.0, "cooldown":12.0, "windup":0.15, "duration":0.35, "coefficient":1.1, "range":260.0, "radius":130.0 if level >= 14 else 110.0, "fuse":0.65, "knockback":30.0, "movement":1.0}
			"ultimate": data = {"name":"火力倾泻", "cost":60.0, "cooldown":40.0, "windup":0.25, "duration":1.17, "coefficient":1.2, "range":760.0, "speed":1150.0, "shots":4, "movement":0.7 if level >= 16 else 0.45}
	else:
		match slot:
			"q": data = {"name":"奥术晶爆", "cost":18.0, "cooldown":5.0, "windup":0.18, "duration":0.36, "coefficient":1.25, "range":550.0, "speed":850.0 if level >= 10 else 650.0, "explosion_radius":65.0, "movement":0.85}
			"secondary": data = {"name":"星界法晶", "cost":30.0, "cooldown":3.5, "windup":0.20, "duration":0.44, "coefficient":0.15, "range":220.0, "radius":160.0, "health":50.0 if level >= 12 else 35.0, "movement":0.85}
			"f": data = {"name":"冰霜新星", "cost":25.0, "cooldown":9.0 if level >= 14 else 11.0, "windup":0.14, "duration":0.40, "coefficient":0.8, "radius":140.0, "movement":0.85}
			"ultimate": data = {"name":"星陨领域", "cost":60.0, "cooldown":48.0, "windup":0.40, "duration":0.80, "coefficient":0.6, "tick_coefficient":0.8, "range":280.0, "radius":210.0 if level >= 16 else 180.0, "lifetime":5.0, "movement":0.65}
	if data.is_empty():
		return data
	# V2 specialization is independent from archived legacy adventures. Runtime,
	# HUD and inspection all sample this exact override before branch/cooldown math.
	if Numbers.is_v2(effective_stats):
		var profiles: Dictionary = Numbers.value("hero_class_profiles", {})
		var profile: Dictionary = profiles.get(hero, {})
		var changes: Dictionary = profile.get("skills", {}).get(slot, {}).duplicate(true)
		var upgraded: Dictionary = changes.get("level_upgrade", {})
		changes.erase("level_upgrade")
		if not upgraded.is_empty() and level >= int(upgraded.get("level", 99)):
			var upgraded_values: Dictionary = upgraded.duplicate(true)
			upgraded_values.erase("level")
			changes.merge(upgraded_values, true)
		data.merge(changes, true)
	var skill_definition: Dictionary = ContentRegistry.hero(hero).get("skills", {}).get(slot, {})
	data["unlock"] = int(skill_definition.get("unlock", 99))
	data["slot"] = slot
	data["input"] = {"q":"Q", "secondary":"W", "f":"E", "ultimate":"R"}.get(slot, "")
	data["hero"] = hero
	data["damage_type"] = "magic" if hero == "CH03" else "physical"
	data["branch"] = _branch(slot, level, effective_stats)
	_apply_branch(data)
	if Numbers.is_v2(effective_stats) and hero == "CH03" and slot == "q" and str(data.branch) == "B":
		data.cooldown = 3.0
	if Numbers.is_v2(effective_stats):
		data.cost = Numbers.scale(float(data.cost), Numbers.V2)
		if data.has("health"):
			data.health = Numbers.scale(float(data.health), Numbers.V2)
	data["base_cooldown"] = float(data.cooldown)
	var cooldown_cap: float = float(Numbers.value("caps").cooldown_reduction) if Numbers.is_v2(effective_stats) else 0.30
	data.cooldown = float(data.cooldown) * (1.0 - clampf(float(effective_stats.get("cooldown_reduction", 0.0)), 0.0, cooldown_cap))
	# Live cost is sampled before commitment consumes Momentum. The same spec
	# feeds casting and the HUD; catalog previews retain the ordinary Rage cost.
	if not preview and hero == "CH01" and slot == "secondary" and is_instance_valid(owner_player):
		data["momentum_free"] = int(owner_player.break_stacks) >= 3
		if bool(data.momentum_free):
			data.cost = Numbers.amount(0.0, int(effective_stats.get("ruleset_version", Numbers.LEGACY)))
	return data

func _branch(slot: String, level: int, stats: Dictionary) -> String:
	if slot != "q" and slot != "ultimate":
		return ""
	var gate: int = 18 if slot == "q" else 20
	if level < gate:
		return ""
	var branches: Dictionary = stats.get("branches", {})
	var chosen: String = str(branches.get(slot, branches.get(str(gate), ""))).to_upper()
	return chosen if chosen == "A" or chosen == "B" else ""

func _apply_branch(data: Dictionary) -> void:
	var branch: String = data.branch
	if branch.is_empty():
		return
	if data.hero == "CH01":
		if data.slot == "q":
			if branch == "A":
				data.merge({"travel":240.0, "coefficient":1.2}, true)
			else:
				data.merge({"travel":0.0, "coefficient":1.7, "radius":135.0, "guard":0.08}, true)
		elif branch == "A":
			data.merge({"coefficient":5.4, "radius":140.0, "windup":0.65, "duration":1.22}, true)
		else:
			data.merge({"coefficient":1.9, "radius":220.0, "duration":1.02, "waves":2}, true)
	elif data.hero == "CH02":
		if data.slot == "q":
			if branch == "A":
				data.merge({"travel":230.0, "coefficient":0.25}, true)
			else:
				data.merge({"travel":0.0, "travel_time":0.0, "coefficient":0.55, "duration":0.40}, true)
		elif branch == "A":
			data.merge({"movement":0.0, "coefficient":1.5, "pierce":1, "pierce_multiplier":0.7}, true)
		else:
			data.merge({"movement":1.0, "shots":3}, true)
	elif data.slot == "q":
		if branch == "A":
			data.merge({"explosion_radius":0.0, "coefficient":1.0, "pierce":1, "pierce_multiplier":1.0, "echo_along_path":true}, true)
		else:
			data.merge({"range":350.0, "explosion_radius":100.0, "coefficient":1.35, "cooldown":6.0}, true)
	elif branch == "A":
		data.merge({"lifetime":7.0, "tick_coefficient":0.65}, true)
	else:
		data.merge({"lifetime":4.0, "tick_coefficient":0.65, "radius":140.0, "follow_player":true}, true)

func can_cast(slot: String, target: Vector2, ignore_busy: bool = false, preview_cooldown: bool = false) -> bool:
	# Same checks as commitment, but no resource/cooldown/stack/audio mutation.
	return try_cast(slot, target, true, false, ignore_busy, preview_cooldown)

func try_cast(slot: String, target: Vector2, validate_only: bool = false, allow_recovery_chain: bool = false, ignore_busy: bool = false, preview_cooldown: bool = false) -> bool:
	last_failure = ""
	last_failure_details = {}
	if not is_instance_valid(owner_player) or Game.run == null or Game.run.hp <= 0.0:
		return _fail("unavailable")
	if busy() and not (validate_only and ignore_busy) and not (allow_recovery_chain and recovery_chain_ready()):
		return _fail("busy")
	var data: Dictionary = spec(slot)
	if data.is_empty() or owner_player.hero_level() < int(data.unlock):
		return _fail("locked")
	if float(owner_player.cooldowns.get(slot, 0.0)) > 0.00001 and not (validate_only and preview_cooldown):
		return _fail("cooldown")
	var origin: Vector2 = owner_player.position
	var direction: Vector2 = owner_player.aim_direction.normalized()
	if not direction.is_finite() or direction.is_zero_approx():
		return _fail("invalid_direction")
	var hero: String = data.hero
	var travel_direction: Vector2 = direction
	if hero == "CH02" and slot == "q":
		var move: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		travel_direction = move.normalized() if not move.is_zero_approx() else -direction
	if hero == "CH01" and slot == "q" and float(data.travel) > 0.0:
		var step: Vector2 = owner_player.room.move_actor(origin, travel_direction * 4.0, Balance.PLAYER_RADIUS)
		if step.distance_squared_to(origin) < 0.1:
			return _fail("invalid_ground", {"cause":"blocked_ground"})
	var ground_cast: bool = (hero == "CH02" and slot == "f") or (hero == "CH03" and slot in ["secondary", "ultimate"])
	if hero == "CH03" and slot == "ultimate" and bool(data.get("follow_player", false)):
		# The mobile branch is self-centered, so an unused cursor over a wall
		# must not block it or consume a different targeting rule than its effect.
		target = origin
	if ground_cast:
		if not target.is_finite():
			return _fail("invalid_ground", {"cause":"blocked_ground"})
		if origin.distance_to(target) > float(data.range) + 0.01:
			return _fail("invalid_ground", {"cause":"out_of_range", "range":float(data.range), "distance":origin.distance_to(target)})
		if not owner_player.room.valid_ground(target, 14.0) or not owner_player.room.has_line_of_sight(origin, target):
			return _fail("invalid_ground", {"cause":"blocked_ground"})
	if hero == "CH01" and slot == "ultimate":
		if not target.is_finite():
			return _fail("invalid_ground", {"cause":"blocked_ground"})
		var offset: Vector2 = target - origin
		if offset.length() > float(data.range):
			offset = offset.normalized() * float(data.range)
		target = owner_player.room.move_actor(origin, offset, 4.0)
		if not owner_player.room.valid_ground(target, 4.0):
			return _fail("invalid_ground", {"cause":"blocked_ground"})
	var ground_facing: bool = ground_cast or (hero == "CH01" and slot == "ultimate")
	if ground_facing and origin.distance_squared_to(target) > 0.001:
		# A queued landing is a committed point. Its body/weapon faces that point,
		# even if the mouse has moved elsewhere before the queued cast starts.
		direction = origin.direction_to(target)
	var cost: float = float(data.cost)
	if owner_player.has_method("resource_cost"):
		cost = owner_player.resource_cost(cost)
	if not is_finite(cost) or cost < 0.0 or Game.run.resource < cost:
		return _fail("resource", {"cost":cost, "resource":float(Game.run.resource)})
	if validate_only:
		return true
	if not Game.try_spend_resource(cost):
		return _fail("resource")
	# Validation and payment succeeded. Retire only the old completed recovery;
	# released projectiles, deployments and feedback still own their lifetimes.
	if busy():
		cancel()
	if hero == "CH01" and slot in ["secondary", "ultimate"]:
		# Momentum commits with the cast. A defensive dash cannot refund it.
		var stacks: int = owner_player.consume_break_stacks()
		data["break_stacks"] = stacks
		if Numbers.is_v2(Game.run.stats):
			data["full_break_w"] = slot == "secondary" and stacks == 3
			data["shielded_cast"] = Game.run.shield > 0.0
		data.coefficient = float(data.coefficient) + stacks * (0.45 if slot == "secondary" else 0.60)
		if stacks == 3:
			data.radius = float(data.radius) + (25.0 if slot == "secondary" else 30.0)
			data.knockback = float(data.knockback) + 25.0
			if slot == "secondary":
				data.arc = 160.0
	owner_player.cooldowns[slot] = float(data.cooldown)
	owner_player.resource_delay = float(Game.run.stats.get("resource_regen_delay", 0.5 if hero == "CH02" else 0.8))
	cast_serial += 1
	if owner_player.get("passives") != null:
		owner_player.passives.skill_committed(slot, cast_serial)
	active = {"spec":data, "elapsed":0.0, "origin":origin, "target":target, "direction":direction, "initial_direction":direction, "travel_direction":travel_direction, "ground_facing":ground_facing,"power":owner_player.skill_power(), "attacker_stats":Game.run.stats.duplicate(), "events":_timeline(data), "next_event":0, "serial":cast_serial}
	owner_player.visual_event("cast_" + slot, float(data.duration))
	if is_instance_valid(feedback):
		feedback.cast_started(data, active.direction, active.target, cast_serial)
	return true

func _fail(reason: String, details: Dictionary = {}) -> bool:
	last_failure = reason
	last_failure_details = details.duplicate(true)
	return false

func _timeline(data: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var windup: float = float(data.windup)
	if data.hero == "CH01" and data.slot == "q":
		events.append({"time":windup + float(data.travel_time) if float(data.travel) > 0.0 else windup, "index":0})
	elif data.hero == "CH02" and data.slot == "q":
		var start: float = windup + float(data.travel_time)
		var interval: float = 0.13 if data.branch == "B" else 0.06
		for index in range(3):
			events.append({"time":start + interval * index, "index":index})
	elif data.hero == "CH02" and data.slot == "ultimate":
		var count: int = int(data.shots)
		for index in range(count):
			events.append({"time":windup + 0.72 * index / float(count - 1), "index":index})
	elif int(data.get("waves", 1)) == 2:
		events.append({"time":windup, "index":0})
		events.append({"time":windup + 0.20, "index":1})
	else:
		events.append({"time":windup, "index":0})
	return events

func tick(delta: float) -> void:
	if not is_instance_valid(owner_player):
		return
	if is_instance_valid(feedback):
		feedback.advance(delta)
	if active.is_empty():
		return
	if Game.run == null or Game.run.hp <= 0.0:
		cancel()
		return
	var previous: float = float(active.elapsed)
	var finish: float = minf(previous + maxf(delta, 0.0), float(active.spec.duration))
	var events: Array[Dictionary] = active.events
	while int(active.next_event) < events.size():
		var event: Dictionary = events[int(active.next_event)]
		var event_time: float = float(event.time)
		if event_time > finish + 0.00001:
			break
		_advance(previous, event_time)
		active.elapsed = event_time
		active.next_event = int(active.next_event) + 1
		_resolve(int(event.index))
		previous = event_time
	_advance(previous, finish)
	active.elapsed = finish
	if finish >= float(active.spec.duration) - 0.00001:
		active.clear()

func _advance(from_time: float, to_time: float) -> void:
	var data: Dictionary = active.spec
	var elapsed: float = maxf(0.0, to_time - from_time)
	var aim: Vector2 = owner_player.aim_direction.normalized()
	if data.hero == "CH02" and data.slot == "ultimate" and not aim.is_zero_approx():
		var direction: Vector2 = active.direction
		active.direction = direction.rotated(clampf(direction.angle_to(aim), -PI * 0.5 * elapsed, PI * 0.5 * elapsed))
	elif from_time < float(data.windup) and not aim.is_zero_approx() and not bool(active.get("ground_facing",false)):
		if data.hero == "CH01" and data.slot == "secondary":
			var initial: Vector2 = active.initial_direction
			active.direction = initial.rotated(clampf(initial.angle_to(aim), -PI / 6.0, PI / 6.0))
		elif data.slot != "q" or data.hero != "CH01":
			active.direction = aim
	var distance: float = float(data.get("travel", 0.0))
	var duration: float = float(data.get("travel_time", 0.0))
	if distance > 0.0 and duration > 0.0:
		var start: float = float(data.windup)
		var portion: float = maxf(0.0, minf(to_time, start + duration) - maxf(from_time, start)) / duration
		if portion > 0.0:
			owner_player.position = owner_player.room.move_actor(owner_player.position, active.travel_direction * distance * portion, Balance.PLAYER_RADIUS)
			owner_player.visual_event("skill_slide", 0.10)

func _resolve(index: int) -> void:
	var data: Dictionary = active.spec
	var hero: String = data.hero
	var slot: String = data.slot
	var power: Variant = active.power
	var amount: Variant = packet_amount(float(data.coefficient), float(power), active.attacker_stats)
	var room: Node = owner_player.room
	var at: Vector2 = owner_player.position
	var direction: Vector2 = active.direction
	var hit_context: Dictionary = {"root_event_id":"skill:" + str(active.serial), "attack_id":"skill:" + str(active.serial) + ":" + str(index), "power":power, "original_basic":false, "equipment_eligible":true, "damage_type":str(data.damage_type), "attacker_stats":active.attacker_stats}
	if Numbers.is_v2(active.attacker_stats):
		hit_context["full_break_w"] = bool(data.get("full_break_w", false))
		hit_context["shielded_cast"] = bool(data.get("shielded_cast", false))
		hit_context["H_skill"] = power
	if hero == "CH01":
		if slot == "ultimate":
			at = active.target
		var knockback: float = float(data.get("knockback", 0.0)) if index == 0 else 0.0
		var hits: Array = room.strike_area(at, float(data.radius), amount, slot, "", knockback, direction, float(data.get("arc", 360.0)), true, hit_context, Numbers.is_v2(active.attacker_stats))
		if slot == "q" and not hits.is_empty():
			owner_player.gain_break_stacks(1)
		elif slot == "f":
			owner_player.gain_break_stacks(1)
		if float(data.get("guard", 0.0)) > 0.0:
			owner_player.grant_guard(Game.run.max_hp * float(data.guard), 4.0, "hero_" + slot)
		if slot == "f":
			# The guard is earned on release. Cancelling the windup cannot provide
			# free protection. Independent expiry preserves other defense sources.
			owner_player.status.apply("brace_guard", float(data.damage_reduction), float(data.guard_duration))
		# The horizontal sweep already has a directional weapon trail. A full
		# circle would falsely suggest it hits behind the committed attack sector.
		if slot != "secondary":
			room.add_ring(at, Color("da995b"), float(data.radius), 0.25)
	elif hero == "CH02":
		if slot == "f":
			# A thrown grenade owns its fuse after release, just as a fired round
			# owns its flight. It explodes once even when the landing zone is empty.
			room.add_deployment("grenade", active.target, {"damage":amount, "power":power, "radius":data.radius, "fuse":data.fuse, "knockback":data.knockback, "lifetime":float(data.fuse) + 0.1, "origin":at, "owner_player":owner_player, "damage_type":str(data.damage_type), "attacker_stats":active.attacker_stats, "root_event_id":hit_context.root_event_id, "attack_id":hit_context.attack_id, "heavy":true})
		else:
			if slot == "q" and index == 0:
				active.direction = owner_player.aim_direction.normalized()
				direction = active.direction
			var options: Dictionary = {"source":slot, "original":true, "speed":data.speed, "range":data.range, "pierce":data.get("pierce", 0), "pierce_multiplier":data.get("pierce_multiplier", 1.0), "power":power, "color":Color("dfd19c"), "heavy":slot == "secondary" or (slot == "ultimate" and index == int(data.shots) - 1)}
			options.merge(hit_context, true)
			room.spawn_ability_projectile(_projectile_origin(direction), direction, amount, options)
	elif slot == "q":
		var options: Dictionary = {"source":"q", "original":true, "status":"shock", "power":power, "speed":data.speed, "range":data.range, "pierce":data.get("pierce", 0), "pierce_multiplier":data.get("pierce_multiplier", 1.0), "explosion_radius":data.explosion_radius, "echo_reach":90.0, "echo_damage":packet_amount(0.35, float(power), active.attacker_stats), "echo_along_path":data.get("echo_along_path", false), "color":Color("6bc4ca")}
		options.merge(hit_context, true)
		room.spawn_ability_projectile(_projectile_origin(direction), direction, amount, options)
	elif slot == "secondary":
		# The spell is immediately useful without setting up a crystal circuit.
		# The lingering node is an optional auto-attacking bonus, not its payoff gate.
		if float(data.get("burst_coefficient", 0.0)) > 0.0:
			room.strike_area(active.target, float(data.burst_radius), packet_amount(float(data.burst_coefficient), float(power), active.attacker_stats), "secondary", "", 0.0, direction, 360.0, true, hit_context)
			room.add_ring(active.target, Color("9ba7ef"), float(data.burst_radius), 0.26)
			if is_instance_valid(feedback): feedback.class_event("node_burst", active.target, direction, float(data.burst_radius), 0)
		room.add_deployment("node", active.target, {"damage":amount, "power":power, "radius":data.radius, "health":data.health, "health_scale_version":10 if Numbers.is_v2(active.attacker_stats) else 1, "lifetime":14.0, "owner_player":owner_player, "damage_type":str(data.damage_type), "attacker_stats":active.attacker_stats})
	elif slot == "f":
		room.strike_area(at, float(data.radius), amount, "f", "chill", 0.0, Vector2.ZERO, 360.0, true, hit_context)
		for node: Node2D in owner_player.resonance_nodes():
			if node.position.distance_to(at) <= 260.0 and room.has_line_of_sight(at, node.position):
				node.detonate()
		room.add_ring(at, Color("a4d8da"), float(data.radius), 0.3)
	elif slot == "ultimate":
		if bool(data.get("follow_player", false)):
			at = owner_player.position
		else:
			at = active.target
		room.strike_area(at, float(data.radius), amount, "ultimate", "shock", 0.0, Vector2.ZERO, 360.0, true, hit_context)
		owner_player.charge_resonance(at, float(data.radius), 3)
		room.add_deployment("field", at, {"damage":packet_amount(float(data.tick_coefficient), float(power), active.attacker_stats), "power":power, "radius":data.radius, "lifetime":data.lifetime, "follow_player":data.get("follow_player", false), "owner_player":owner_player, "damage_type":str(data.damage_type), "attacker_stats":active.attacker_stats})
	owner_player.visual_event("release_" + slot, 0.12)
	# One sound per executed event, including branches and partial cancellation.
	# It belongs to the same release as this projectile/deployment/strike, never
	# to a prerecorded burst that can outlive cancelled future events.
	owner_player._play_combat_audio(&"cast", [hero, slot])
	if index == 0:
		owner_player._play_combat_audio(&"skill_music", [hero, slot])
	if is_instance_valid(feedback):
		var effect_center: Vector2 = active.target if (hero == "CH02" and slot == "f") or (hero == "CH03" and slot == "secondary") else at
		feedback.skill_released(data, direction, effect_center, index, active.events.size(), cast_serial)

func _projectile_origin(direction: Vector2) -> Vector2:
	# A long visible barrel must not put the collision origin through a thin wall.
	return owner_player.room.move_actor(owner_player.position, direction * 19.0, 4.0)
