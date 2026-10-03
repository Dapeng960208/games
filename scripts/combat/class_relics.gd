class_name ClassRelics
extends RefCounted
## Saved relic IDs stay stable while their combat expression follows the hero.
## Call only AFTER the original hit. Reservation/budget ownership stays in Room.

const Numbers = preload("res://config/numerical_rules.gd")
const ALIASES: Dictionary = {"split":"RL01", "ember":"RL02", "arc":"RL03"}
const ART: Dictionary = {"RL01":"res://assets/ui/relic_split.png", "RL02":"res://assets/generated/ui/state_burn_v1.png", "RL03":"res://assets/ui/relic_arc.png"}
const HISTORY_META: StringName = &"class_relic_root_history"
const RaceTraits = preload("res://scripts/combat/race_relics.gd")
const ENGLISH_NAMES := {"CH01:RL01":"Earthsplit Wedge","CH01:RL02":"Armor Fang","CH01:RL03":"Counterweight Anvil","CH02:RL01":"Split Magazine","CH02:RL02":"Barbed Cartridge","CH02:RL03":"Hunt Crosshair","CH03:RL01":"Resonant Prism","CH03:RL02":"Ember Core","CH03:RL03":"Returning Coil"}

static func art_path(relic_id: String) -> String:
	return str(ART.get(str(ALIASES.get(relic_id,relic_id)),""))

static func display(hero: String, relic_id: String, rank: int = 1, biome: String = "", ruleset_version: int = Numbers.LEGACY) -> Dictionary:
	var id: String = str(ALIASES.get(relic_id, relic_id))
	var level: int = clampi(rank, 1, 2)
	var enhanced: bool = level == 2
	var mana_refund: String = str(Numbers.scale(4.5 if enhanced else 3.0, ruleset_version)) if ruleset_version == Numbers.V2 else "4.5" if enhanced else "3"
	var name: String = "未知遗物"
	var description: String = ""
	match hero + ":" + id:
		"CH01:RL01":
			name = "裂地楔"
			description = "普攻近身裂地，对前方最多3个额外敌人造成%d%%攻击力物理伤害。" % (60 if enhanced else 40)
		"CH01:RL02":
			name = "破甲齿"
			description = "普攻降低目标15%%护甲，持续%d秒，并每秒造成%d%%攻击力物理伤害。" % [5 if enhanced else 4, 12 if enhanced else 8]
		"CH01:RL03":
			name = "回震砧"
			description = "每第3发普攻有效命中时，获得%d%%最大生命护盾（4秒）及1层破势。" % (18 if enhanced else 12)
		"CH02:RL01":
			name = "分流弹匣"
			description = "普攻命中后向前分出2颗扇弹，每颗造成%d%%攻击力物理伤害。" % (60 if enhanced else 40)
		"CH02:RL02":
			name = "倒钩弹芯"
			description = "普攻使目标流血3秒，每秒造成%d%%攻击力物理伤害。" % (15 if enhanced else 10)
		"CH02:RL03":
			name = "追猎准星"
			description = "每第3发普攻有效命中时，标记目标4秒并追加%s%%攻击力物理伤害；W或R引爆标记。" % ("52.5" if enhanced else "35")
		"CH03:RL01":
			name = "共鸣棱镜"
			description = "普攻命中后产生法术回响，对附近最多2个额外敌人造成%d%%法强魔法伤害。" % (60 if enhanced else 40)
		"CH03:RL02":
			name = "余烬晶核"
			description = "普攻使目标灼烧3秒，每秒造成%d%%法强魔法伤害。" % (18 if enhanced else 12)
		"CH03:RL03":
			name = "归流线圈"
			description = "每第3发普攻有效命中时，回%s法力、附近节点充%d层，并追加%s%%法强魔法伤害。" % [mana_refund, 2 if enhanced else 1, "52.5" if enhanced else "35"]
	if Words.locale == "en":
		name = str(ENGLISH_NAMES.get(hero+":"+id,"Unknown relic"))
		description = _english_description(hero,id,enhanced,ruleset_version)
	return RaceTraits.decorate({"name":name + (" II" if enhanced else ""), "description":description, "art":str(ART.get(id, "")), "id":id, "rank":level},hero,id,biome)

static func _english_description(hero: String, id: String, enhanced: bool, ruleset_version: int = Numbers.LEGACY) -> String:
	var mana_refund: String = str(Numbers.scale(4.5 if enhanced else 3.0, ruleset_version)) if ruleset_version == Numbers.V2 else "4.5" if enhanced else "3"
	match hero+":"+id:
		"CH01:RL01": return "Basic hits cleave up to 3 extra enemies in front for %d%% attack physical damage." % (60 if enhanced else 40)
		"CH01:RL02": return "Basic hits reduce target armor by 15%% for %ds and deal %d%% attack physical damage each second." % [5 if enhanced else 4,12 if enhanced else 8]
		"CH01:RL03": return "Every third fired basic attack grants a %d%% max-HP guard for 4s and one Momentum stack on a confirmed hit." % (18 if enhanced else 12)
		"CH02:RL01": return "Basic hits launch 2 forward split bullets, each dealing %d%% attack physical damage." % (60 if enhanced else 40)
		"CH02:RL02": return "Basic hits cause 3s of bleed, dealing %d%% attack physical damage each second." % (15 if enhanced else 10)
		"CH02:RL03": return "Every third fired basic attack marks for 4s and adds %s%% attack physical damage on a confirmed hit; W or R consumes the mark." % ("52.5" if enhanced else "35")
		"CH03:RL01": return "Basic hits echo to up to 2 extra nearby enemies for %d%% ability-power magic damage." % (60 if enhanced else 40)
		"CH03:RL02": return "Basic hits cause 3s of burn, dealing %d%% ability-power magic damage each second." % (18 if enhanced else 12)
		"CH03:RL03": return "Every third fired basic attack restores %s mana, charges nearby nodes by %d, and adds %s%% ability-power magic damage on a confirmed hit." % [mana_refund,2 if enhanced else 1,"52.5" if enhanced else "35"]
	return ""

static func native_status(hero: String) -> String:
	return "corrosion" if hero == "CH01" else "bleed" if hero == "CH02" else "burn"

static func native_status_power(_hero: String, power: float, rank: int = 1, ruleset_version: int = Numbers.LEGACY) -> Variant:
	return Numbers.amount(maxf(0.0, power) * (1.5 if rank >= 2 else 1.0), ruleset_version)

static func native_status_duration(hero: String, rank: int = 1, room: Node = null) -> float:
	var base := (5.0 if rank >= 2 else 4.0) if hero == "CH01" else 3.0
	return RaceTraits.native_duration(room,base)

static func on_original_hit(room: Node, context: Dictionary) -> void:
	RaceTraits.confirmed_original_hit(room,context)

static func reset_room(room: Node) -> void:
	RaceTraits.reset_room(room)
	if is_instance_valid(room) and room.has_meta(HISTORY_META):
		room.remove_meta(HISTORY_META)

static func apply_reserved(room: Node2D, reserved: Dictionary, context: Dictionary, at: Vector2, target: Node2D, direction: Vector2) -> bool:
	if not is_instance_valid(room) or not is_instance_valid(room.player) or reserved.is_empty():
		return false
	# A derived damage packet can never re-enter the relic adapter.
	if int(context.get("proc_depth", 0)) > 0 or not bool(context.get("original_basic", true)) or not bool(context.get("equipment_eligible", true)):
		return false
	var root_id: String = str(context.get("root_event_id", ""))
	if root_id.is_empty():
		return false
	var hero: String = room.player.hero_id()
	if hero not in ["CH01", "CH02", "CH03"]:
		return false
	var fired: bool = false
	var aim: Vector2 = direction.normalized() if not direction.is_zero_approx() else room.player.aim_direction
	for channel: String in ["split", "arc"]:
		if not reserved.has(channel) or float(reserved[channel]) <= 0.0 or not _claim(room, root_id, channel):
			continue
		var coefficient: float = float(reserved[channel])
		if channel == "split":
			_emit_split(room, hero, coefficient, context, at, target, aim)
		else:
			_emit_arc(room, hero, coefficient, context, at, target, aim)
		fired = true
	return fired

static func _claim(room: Node, root_id: String, channel: String) -> bool:
	var history: Dictionary = room.get_meta(HISTORY_META, {})
	var channels: Dictionary = history.get(root_id, {})
	if channels.has(channel):
		return false
	channels[channel] = true
	history[root_id] = channels
	while history.size() > 256:
		history.erase(history.keys()[0])
	room.set_meta(HISTORY_META, history)
	return true

static func _power(player: Node2D, hero: String) -> Variant:
	if player.has_method("relic_power"):
		return player.relic_power()
	return player.stat("ability_power", 28.0) if hero == "CH03" else player.attack_power()

static func _amount(room: Node, amount: float) -> Variant:
	var game: Node = room.get_node("/root/Game")
	return Numbers.amount(amount, game.run.ruleset_version() if game.run != null else Numbers.LEGACY)

static func _context(room: Node2D, original: Dictionary, damage_type: String, channel: String) -> Dictionary:
	var context: Dictionary = original.duplicate(true)
	context["original_basic"] = false
	context["equipment_eligible"] = false
	context["proc_depth"] = 1
	context["damage_source"] = "relic"
	context["damage_type"] = damage_type
	context["relic_channel"] = channel
	context["native_statuses"] = []
	context["critical"] = false
	var game: Node = room.get_node("/root/Game")
	context["attacker_stats"] = game.run.stats.duplicate(true) if game.run != null else {}
	context["H"] = _power(room.player, room.player.hero_id())
	return context

static func _emit_split(room: Node2D, hero: String, coefficient: float, original: Dictionary, at: Vector2, target: Node2D, direction: Vector2) -> void:
	coefficient *= RaceTraits.split_multiplier(room,at)
	var context: Dictionary = _context(room, original, "magic" if hero == "CH03" else "physical", "split")
	var amount: Variant = _amount(room, float(_power(room.player, hero)) * coefficient)
	if hero == "CH02":
		for side: float in [-1.0, 1.0]:
			var child: Node2D = room.spawn_projectile(at, direction.rotated(side * Balance.SPLIT_ANGLE), amount, &"child", target.get_instance_id() if is_instance_valid(target) else 0)
			if is_instance_valid(child):
				child.trigger_budget = 0
				child.options = context.duplicate(true)
				child.distance_left = 420.0
				child.remaining = 0.65
				room.telemetry.split_spawned += 1
		return
	var origin: Vector2 = room.player.position if hero == "CH01" else at
	var radius: float = 200.0 if hero == "CH01" else 135.0
	var hit_count: int = 0
	for candidate: Node2D in room.targets_in_radius(origin, radius):
		if candidate == target:
			continue
		var offset: Vector2 = candidate.position - origin
		if hero == "CH01" and not offset.is_zero_approx() and direction.dot(offset.normalized()) < cos(deg_to_rad(55.0)):
			continue
		candidate.take_damage(amount, &"relic_fracture" if hero == "CH01" else &"relic_echo", offset.normalized(), context)
		if hero == "CH03":
			room.add_arc_between(at, candidate.position)
		hit_count += 1
		if hit_count >= (3 if hero == "CH01" else 2):
			break
	if hero == "CH01":
		room.add_arc_visual(origin, direction, 170.0, 110.0, Color("eabb78"), 0.24)
	else:
		room.add_ring(at, Color("79d8d1"), 82.0, 0.24)

static func _emit_arc(room: Node2D, hero: String, coefficient: float, original: Dictionary, at: Vector2, target: Node2D, direction: Vector2) -> void:
	var multiplier: float = coefficient / Balance.ARC_RATIO
	var game: Node = room.get_node("/root/Game")
	if game.run.ruleset_version() == Numbers.V2 and is_equal_approx(multiplier, 1.5):
		# The authored II rank is exactly 3/2. Recovering it by .525/.35
		# can fall just below 1.5 and turn a later .5 refund into a round-down.
		multiplier = 1.5
		coefficient = 0.525
	if hero == "CH01":
		# Derived shields must not emit a fresh equipment shield_gain event.
		room.player.status.absorb(maxf(0.0, room.player.status.shield() - game.run.shield))
		room.player.status.grant_guard(game.run.max_hp * 0.12 * multiplier * RaceTraits.guard_multiplier(room), 4.0, "relic:counterweight", game.run.max_hp)
		game.run.shield = room.player.status.shield()
		room.player.gain_break_stacks(1)
		room.add_ring(room.player.position, Color("eabb78"), 52.0, 0.32)
		return
	if hero == "CH03":
		room.player.restore_class_resource(float(Numbers.scale(3.0, game.run.ruleset_version())) * multiplier)
		room.player.charge_resonance(at, 300.0, 2 if multiplier > 1.1 else 1)
		room.add_ring(at, Color("79d8d1"), 44.0, 0.30)
	if not is_instance_valid(target) or not target.is_alive():
		return
	if hero == "CH02":
		room.player.class_mark_target(target)
		room.add_ring(at, Color("f1d298"), 24.0, 0.22)
	var context: Dictionary = _context(room, original, "magic" if hero == "CH03" else "physical", "arc")
	target.take_damage(_amount(room, float(_power(room.player, hero)) * coefficient), &"relic_echo" if hero == "CH03" else &"relic_mark", direction, context)
	room.telemetry.arc_hits += 1
