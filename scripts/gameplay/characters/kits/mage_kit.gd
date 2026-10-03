class_name MageKit
extends RefCounted
## One companion and one spell-release ledger. All damage uses the room's
## existing original/derived pipelines; the companion never attacks on its own.

const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Companion = preload("res://scripts/gameplay/characters/star_companion.gd")
const CHORUS_LIFETIME := 8.0
const ECHO_LIFETIME := 6.0
const CHORUS_MULTIPLIER := 1.25
const ROOT_LIMIT := 128
const TIMER_EPSILON := 0.000000001

var owner_player: Node2D
var companion: Node2D
var starlight: int = 0
var decay_remaining: float = 0.0
var echo_remaining: float = 0.0
var _echo_power: float = 0.0
var _echo_stats: Dictionary = {}
var _echo_armed_serial: int = 0
var _last_release_serial: int = 0
var _last_release_modifier: Dictionary = {}
var _echo_roots: Dictionary = {}

static func skill_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	specs.assign(Numbers.value("class_skill_specs", {}).get("CH03", []))
	for index: int in range(specs.size()):
		var data: Dictionary = specs[index]
		data["name_en"] = ["Starbell Bolt", "Starlit Leap", "Star Ring Guard", "Wish Garden", "Starfall Fan", "Stardust Shield", "Comet Line", "Star Vortex", "Starlight Chain", "Twin-Star Resonance", "Star Spirit Patrol", "Starlight Step"][index]
		data["hero"] = "CH03"
		data["hero_id"] = "CH03"
		data["damage_type"] = "magic"
		data["effect_kind"] = data.kind
		data["category"] = {"攻击":"attack", "防御":"defense", "控场":"support", "辅助":"support", "机动":"mobility"}.get(str(data.category), "attack")
		data["origin_slot"] = str(data.origin_slot) if not str(data.origin_slot).is_empty() else "skill"
		data["slot"] = data.origin_slot
		data["unlock"] = 1
		data["base_cooldown"] = float(data.cooldown)
		data["total_coefficient"] = 4.6 if index == 3 else 0.8 if index == 9 else float(data.coefficient)
		data["acquisition_group"] = "" if index < 4 else "SG%02d" % (index - 3)
		if index == 0:
			data["branches"] = {"A":"双弹均分总伤害", "B":"追踪首次合法目标"}
			data["branch_rank"] = 4
		elif index == 3:
			data["branches"] = {"A":"范围提高15%", "B":"随身移动、范围缩小15%"}
			data["branch_rank"] = 5
	return specs

static func apply_mastery_branch(data: Dictionary, rank: int, branch: String) -> void:
	var id: String = str(data.get("skill_id", ""))
	if rank >= 2:
		match id:
			"CH03_SK01": data["speed"] = 850.0
			"CH03_SK02": data["radius"] = float(data.radius) * 1.1
			"CH03_SK03": data["cooldown"] = 6.0
			"CH03_SK04": data["radius"] = 210.0
	if id == "CH03_SK01" and rank >= 4:
		if branch == "A":
			data["shots"] = 2
			data["fan_degrees"] = 12.0
		elif branch == "B":
			data["homing"] = true
	if id == "CH03_SK04" and rank >= 5:
		if branch == "A":
			data["radius"] = float(data.radius) * 1.15
		elif branch == "B":
			data["radius"] = float(data.radius) * 0.85
			data["follow_player"] = true

func configure(player: Node2D) -> void:
	owner_player = player
	reset()
	if not is_instance_valid(owner_player):
		return
	companion = owner_player.get_node_or_null("StarCompanion") as Node2D
	if not is_instance_valid(companion):
		companion = Companion.new()
		companion.name = "StarCompanion"
		owner_player.add_child(companion)
	companion.configure(owner_player)

func reset() -> void:
	starlight = 0
	decay_remaining = 0.0
	echo_remaining = 0.0
	_echo_power = 0.0
	_echo_stats.clear()
	_echo_armed_serial = 0
	_last_release_serial = 0
	_last_release_modifier.clear()
	_echo_roots.clear()

func on_room_changed() -> void:
	reset()

func on_death() -> void:
	reset()

func tick(delta: float) -> void:
	if not _available() or not is_finite(delta) or delta <= 0.0:
		return
	decay_remaining = maxf(0.0, decay_remaining - delta)
	echo_remaining = maxf(0.0, echo_remaining - delta)
	if decay_remaining <= TIMER_EPSILON:
		decay_remaining = 0.0
		starlight = 0
	if echo_remaining <= TIMER_EPSILON:
		echo_remaining = 0.0
		_echo_armed_serial = 0
		_echo_power = 0.0
		_echo_stats.clear()

## The shared timeline calls this at its first actual effect, before freezing
## packet power. Windup cancellation never reaches this method.
func on_skill_release(cast: Dictionary) -> Dictionary:
	var result: Dictionary = {"damage_multiplier":1.0, "shield_multiplier":1.0, "guard_multiplier":1.0, "chorus":false}
	if not _available():
		return result
	var serial: int = int(cast.get("cast_id", cast.get("serial", 0)))
	if serial <= 0 or serial < _last_release_serial:
		return result
	if serial == _last_release_serial:
		return _last_release_modifier.duplicate(true)
	_last_release_serial = serial
	var id: String = str(cast.get("skill_id", cast.get("spec", {}).get("skill_id", "")))
	if bool(cast.get("combat", false)):
		if starlight >= 3:
			starlight = 0
			result.merge({"damage_multiplier":CHORUS_MULTIPLIER, "shield_multiplier":CHORUS_MULTIPLIER, "guard_multiplier":CHORUS_MULTIPLIER, "chorus":true}, true)
			owner_player.restore_class_resource(float(Numbers.scale(10.0, _ruleset_version())))
		else:
			starlight = mini(3, starlight + 1)
		decay_remaining = CHORUS_LIFETIME
		if id == "CH03_SK10":
			starlight = mini(3, starlight + 1)
			echo_remaining = ECHO_LIFETIME
			_echo_armed_serial = serial
			_echo_power = float(cast.get("power", cast.get("base_power", 0.0))) * float(result.damage_multiplier)
			_echo_stats = cast.get("attacker_stats", {}).duplicate(true)
	_last_release_modifier = result.duplicate(true)
	if is_instance_valid(companion):
		companion.spell_released(id, bool(result.chorus))
	return result

func primary_damage_multiplier() -> float:
	return 1.0

func damage_multiplier(_id: String) -> float:
	return 1.0

func attack_speed_multiplier() -> float:
	return 1.0

func movement_multiplier() -> float:
	return 1.0

func can_primary() -> bool:
	return _available()

func on_primary_created() -> void:
	if is_instance_valid(companion):
		companion.primary_created(owner_player.aim_direction)

func on_dash_finished(_success: bool) -> void:
	pass

func on_skill_finished(_cast: Dictionary) -> void:
	pass

func restore_starlight(amount: int) -> bool:
	if not _available() or amount <= 0:
		return false
	var previous: int = starlight
	starlight = mini(3, starlight + amount)
	if starlight > previous:
		decay_remaining = CHORUS_LIFETIME
	return starlight > previous

func timeline(data: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = [{"time":float(data.get("windup", 0.0)), "index":0}]
	if str(data.get("kind", "")) in ["vortex", "moving_pulses"]:
		for index: int in range(1, 5):
			events.append({"time":float(data.windup) + float(index) * 0.5, "index":index})
	return events

func can_release(cast: Dictionary, _index: int) -> bool:
	if not _available() or not is_instance_valid(owner_player.room):
		return false
	if str(cast.get("spec", {}).get("kind", "")) == "projectile":
		var projectiles: Variant = owner_player.room.get("projectiles")
		return is_instance_valid(projectiles) and projectiles.get_child_count() < Balance.MAX_PROJECTILES
	return true

func resolve_skill(cast: Dictionary, index: int) -> bool:
	if not _available() or not is_instance_valid(owner_player.room):
		return false
	var data: Dictionary = cast.get("spec", {})
	var kind: String = str(data.get("kind", ""))
	var room: Node2D = owner_player.room
	var direction: Vector2 = cast.get("direction", Vector2.RIGHT)
	if not direction.is_finite():
		return false
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var context: Dictionary = cast.get("hit_context", {}).duplicate(true)
	var power: float = float(cast.get("power", 0.0))
	if not is_finite(power) or power < 0.0:
		return false
	var amount: float = float(Numbers.amount(float(data.get("coefficient", 0.0)) * power, _ruleset_version()))
	var at: Vector2 = cast.get("target", owner_player.position)
	if not at.is_finite():
		return false
	context["spell_critical_eligible"] = true
	context["damage_type"] = "magic"
	match kind:
		"projectile":
			var shots: int = clampi(int(data.get("shots", 1)), 1, 3)
			var per_shot: float = amount / float(shots)
			if str(data.skill_id) == "CH03_SK07":
				per_shot /= 2.0
			var target: Node2D = null
			if bool(data.get("homing", false)):
				var targets: Array = room.targets_in_radius(owner_player.position, float(data.get("range", 550.0)))
				if not targets.is_empty():
					target = targets[0]
			for shot: int in range(shots):
				var offset: float = (float(shot) / float(shots - 1) - 0.5) * deg_to_rad(float(data.get("fan_degrees", 0.0))) if shots > 1 else 0.0
				var aim: Vector2 = (target.position - owner_player.position).normalized() if is_instance_valid(target) else direction.rotated(offset)
				var options: Dictionary = context.duplicate(true)
				options.merge({"source":"skill", "original":true, "speed":float(data.get("speed", 850.0)), "range":float(data.get("range", 550.0)), "pierce":int(data.get("pierce", 0)), "pierce_multiplier":float(data.get("pierce_multiplier", 1.0)), "explosion_radius":float(data.get("explosion_radius", 0.0)), "status":str(data.get("status", "")), "visual_hero":"CH03", "color":Color("eacb78")}, true)
				options["attack_id"] = str(context.get("attack_id", "")) + ":star:" + str(shot)
				if is_instance_valid(target):
					options["homing"] = true
					options["homing_target"] = weakref(target)
				room.spawn_ability_projectile(projectile_origin(aim), aim, per_shot, options)
		"burst":
			context["immediate_w_burst"] = true
			context["burst_position"] = at
			var radius: float = float(data.radius)
			if owner_player.loadout != null and owner_player.loadout.effects != null:
				var modifiers: Dictionary = owner_player.loadout.effects.passive_modifiers(context)
				radius *= float(modifiers.get("immediate_w_radius_scale", 1.0))
			room.strike_area(at, radius, amount, &"skill", "", 0.0, direction, 360.0, true, context, true)
			room.add_ring(at, Color("c6b4ef"), radius, 0.28)
		"guard_burst", "guard":
			var shield_multiplier: float = float(cast.get("guard_multiplier", cast.get("shield_multiplier", 1.0)))
			var max_hp: float = float(cast.get("attacker_stats", {}).get("max_hp", Game.run.max_hp))
			owner_player.grant_guard(max_hp * float(data.get("guard", 0.0)) * shield_multiplier, float(data.get("guard_duration", 3.0)), "skill:" + str(data.skill_id))
			if kind == "guard_burst":
				room.strike_area(owner_player.position, float(data.radius), amount, &"skill", str(data.get("status", "chill")), 0.0, direction, 360.0, true, context, true)
			room.add_ring(owner_player.position, Color("88d9cb"), float(data.get("radius", 65.0)), 0.3)
		"field":
			if bool(data.get("follow_player", false)):
				at = owner_player.position
			room.strike_area(at, float(data.radius), amount, &"skill", "shock", 0.0, direction, 360.0, true, context, true)
			var options: Dictionary = context.duplicate(true)
			options.merge({"damage":float(Numbers.amount(float(data.tick_coefficient) * power, _ruleset_version())), "power":power, "radius":float(data.radius), "lifetime":5.0, "follow_player":bool(data.get("follow_player", false)), "owner_player":owner_player, "damage_type":"magic", "spell_critical_eligible":true}, true)
			room.add_deployment("field", at, options)
			room.add_ring(at, Color("c9b4e8"), float(data.radius), 0.35)
		"vortex", "moving_pulses":
			if kind == "moving_pulses":
				at = owner_player.position
			if index == 0:
				room.add_ring(at, Color("cfb9ec"), float(data.radius), 0.35)
			else:
				room.strike_area(at, float(data.radius), amount / 4.0, &"skill", "", 0.0, direction, 360.0, true, context, true)
				if kind == "vortex":
					for target: Node2D in room.targets_in_radius(at, float(data.radius)):
						var pull: Vector2 = at - target.position
						if target.has_method("apply_knockback") and pull.length_squared() > 1.0:
							target.apply_knockback(pull.normalized(), minf(float(data.pull_distance), pull.length()))
				room.add_ring(at, Color("e0c87a") if kind == "moving_pulses" else Color("b6a2e4"), float(data.radius), 0.22)
		"chain":
			var visited: Array[int] = []
			var from: Vector2 = at
			for hop: int in range(3):
				var targets: Array = room.targets_in_radius(from, float(data.get("radius", 90.0)) if hop == 0 else float(data.get("chain_range", 200.0)))
				var next: Node2D = null
				for candidate: Node2D in targets:
					if candidate.get_instance_id() not in visited:
						next = candidate
						break
				if not is_instance_valid(next):
					break
				visited.append(next.get_instance_id())
				var delivered: Dictionary = context.duplicate(true)
				delivered["attack_id"] = str(context.get("attack_id", "")) + ":chain:" + str(hop)
				room.add_arc_between(owner_player.position if hop == 0 else from, next.position)
				room.resolve_direct_hit(next, amount / 3.0, &"skill", "", 0.0, (next.position - from).normalized(), delivered)
				from = next.position
		"resonance":
			# Arming is part of on_skill_release, so a cancelled windup gives none.
			room.add_ring(owner_player.position, Color("e4c86e"), 65.0, 0.3)
		"blink_burst":
			var origin: Vector2 = owner_player.position
			if float(owner_player.get("_enemy_root_remaining")) <= 0.0:
				owner_player.position = room.move_actor(origin, direction.normalized() * float(data.get("blink_distance", 140.0)), Balance.PLAYER_RADIUS)
			room.strike_area(origin, float(data.radius), amount, &"skill", "chill", 0.0, direction, 360.0, true, context, true)
			room.add_ring(origin, Color("8bd3cf"), float(data.radius), 0.25)
			var feedback: Node = owner_player.get_node_or_null("HeroFeedback")
			if is_instance_valid(feedback) and feedback.has_method("class_event"):
				feedback.class_event("blink_depart", origin, direction, float(data.radius))
		_:
			return false
	return true

func on_original_hit(target: Node2D, packet: Dictionary, result: Dictionary) -> void:
	if not _available() or echo_remaining <= 0.0 or not is_instance_valid(target) or not is_instance_valid(owner_player.room):
		return
	if int(packet.get("proc_depth", 0)) != 0 or bool(packet.get("original_basic", false)) or not bool(packet.get("equipment_eligible", false)):
		return
	var id: String = str(packet.get("skill_id", ""))
	if not id.begins_with("CH03_SK") or id == "CH03_SK10":
		return
	if float(result.get("hp_damage", 0.0)) + float(result.get("shield_damage", 0.0)) <= 0.0:
		return
	var root: String = str(packet.get("root_event_id", ""))
	var serial: int = int(packet.get("cast_id", packet.get("serial", root.trim_prefix("skill:") if root.begins_with("skill:") else 0)))
	if serial <= _echo_armed_serial or root.is_empty() or _echo_roots.has(root):
		return
	# Consume before damage; even a synchronous nested hit cannot re-enter.
	echo_remaining = 0.0
	_echo_armed_serial = 0
	_echo_roots[root] = true
	while _echo_roots.size() > ROOT_LIMIT:
		_echo_roots.erase(_echo_roots.keys()[0])
	var delivered: Dictionary = packet.duplicate(true)
	delivered.merge({"proc_depth":1, "equipment_eligible":false, "original_basic":false, "damage_source":"star_echo", "spell_critical_eligible":false, "attack_id":root + ":star_echo", "skill_id":"CH03_SK10", "attacker_stats":_echo_stats.duplicate(true), "H":_echo_power, "power":_echo_power}, true)
	owner_player.room.resolve_derived_hit(target, float(Numbers.amount(_echo_power * 0.8, _ruleset_version())), &"star_echo", (target.position - owner_player.position).normalized(), delivered)
	_echo_power = 0.0
	_echo_stats.clear()
	owner_player.room.add_ring(target.position, Color("e4cb83"), 32.0, 0.2)

func export_state() -> Dictionary:
	return {"starlight":starlight, "decay_remaining":decay_remaining, "echo_remaining":echo_remaining, "echo_armed_serial":_echo_armed_serial, "echo_power":_echo_power, "echo_stats":_echo_stats.duplicate(true), "last_release_serial":_last_release_serial, "last_release_modifier":_last_release_modifier.duplicate(true), "echo_roots":_echo_roots.duplicate(true)}

static func validate_state(data: Dictionary) -> bool:
	if not _json_values(data):
		return false
	for key: String in ["starlight", "decay_remaining", "echo_remaining", "echo_armed_serial", "last_release_serial", "echo_power"]:
		var value: Variant = data.get(key)
		if not value is int and not value is float:
			return false
		if not is_finite(float(value)) or float(value) < 0.0:
			return false
	if float(data.starlight) != floor(float(data.starlight)) or int(data.starlight) > 3 or float(data.decay_remaining) > CHORUS_LIFETIME or float(data.echo_remaining) > ECHO_LIFETIME:
		return false
	for key: String in ["echo_armed_serial", "last_release_serial"]:
		if float(data[key]) != floor(float(data[key])):
			return false
	var modifier: Variant = data.get("last_release_modifier", {})
	var roots: Variant = data.get("echo_roots", {})
	if not modifier is Dictionary or not roots is Dictionary or roots.size() > ROOT_LIMIT or not data.get("echo_stats", {}) is Dictionary:
		return false
	for key: Variant in roots:
		if not key is String or not roots[key] is bool:
			return false
	for key: Variant in modifier:
		if key not in ["damage_multiplier", "shield_multiplier", "guard_multiplier", "chorus"]:
			return false
		if key == "chorus":
			if not modifier[key] is bool:
				return false
		elif not _valid_multiplier(modifier[key]):
			return false
	return true

func restore_state(data: Dictionary) -> bool:
	if not validate_state(data):
		return false
	starlight = int(data.starlight)
	decay_remaining = float(data.decay_remaining)
	echo_remaining = float(data.echo_remaining)
	_echo_armed_serial = int(data.echo_armed_serial)
	_echo_power = float(data.echo_power)
	_echo_stats = data.get("echo_stats", {}).duplicate(true)
	_last_release_serial = int(data.last_release_serial)
	_last_release_modifier = data.get("last_release_modifier", {}).duplicate(true)
	_echo_roots = data.get("echo_roots", {}).duplicate(true)
	if decay_remaining <= TIMER_EPSILON:
		decay_remaining = 0.0
		starlight = 0
	if echo_remaining <= TIMER_EPSILON:
		echo_remaining = 0.0
		_echo_armed_serial = 0
		_echo_power = 0.0
		_echo_stats.clear()
	return true

func hud_state() -> Dictionary:
	var refund: float = float(Numbers.scale(10.0, _ruleset_version()))
	if is_instance_valid(owner_player):
		refund *= float(owner_player.resource_gain_multiplier())
	var ready: bool = starlight >= 3
	var refund_text: int = int(Numbers.amount(refund,_ruleset_version()))
	var description: String = "战斗中实际释放主动技能积一层星辉；满三层后的下一法术消耗星辉，伤害或护盾提高25%%，回复%d法力。8秒未继续施法，星辉消散。" % refund_text
	var description_en: String = "Actual active-skill releases in combat grant one Starlight stack. At three stacks, the next spell consumes them for +25%% damage or shield and restores %d Mana. Starlight fades after 8 seconds without another release." % refund_text
	var hint: String = "协奏就绪 · 下一法术强化25%% / 回%d法力" % refund_text if ready else "实际施法 %d/3 · 团团协同" % starlight
	var hint_en: String = "Chorus ready · next spell +25%% / restore %d Mana" % refund_text if ready else "Spell releases %d/3 · Tuantuan assists" % starlight
	return {"kind":"star_chorus", "name":"星辉协奏", "name_en":"Starlight Chorus", "description":description, "description_en":description_en, "current":starlight, "starlight":starlight, "stacks":starlight, "max":3, "ready":ready, "decay_remaining":decay_remaining, "decay_duration":CHORUS_LIFETIME, "remaining":decay_remaining, "rhythm_remaining":decay_remaining, "chorus_multiplier":CHORUS_MULTIPLIER, "damage_bonus":0.25, "resource_refund":refund, "mana_refund":refund, "pet_state":companion.hud_state() if is_instance_valid(companion) else "follow", "echo_remaining":echo_remaining, "cooldown":0.0, "icd":0.0, "color":Color("d7bfef"), "hint":hint, "hint_en":hint_en}

static func _valid_multiplier(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) in [1.0, CHORUS_MULTIPLIER]

static func _json_values(value: Variant, depth: int = 0) -> bool:
	if depth > 12:
		return false
	if value is Dictionary:
		if value.size() > ROOT_LIMIT:
			return false
		for key: Variant in value:
			if not key is String or not _json_values(value[key], depth + 1):
				return false
		return true
	if value is Array:
		if value.size() > ROOT_LIMIT:
			return false
		for item: Variant in value:
			if not _json_values(item, depth + 1):
				return false
		return true
	return value is String or value is bool or value is int or (value is float and is_finite(value)) or value == null

func projectile_origin(direction: Vector2) -> Vector2:
	return companion.projectile_origin(direction) if is_instance_valid(companion) else owner_player.position

func _ruleset_version() -> int:
	return Game.run.ruleset_version() if Game.run != null else Numbers.LEGACY

func _available() -> bool:
	if not is_instance_valid(owner_player) or Game.run == null or Game.run.hp <= 0.0:
		return false
	return not owner_player.is_inside_tree() or not owner_player.get_tree().paused
