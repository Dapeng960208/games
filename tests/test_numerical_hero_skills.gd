extends SceneTree
## S02 source H, all 264 frozen skill previews/releases, class resources.
## Only isolated in-memory runs; never creates or writes a profile.
## godot --headless --path . --script res://tests/test_numerical_hero_skills.gd -- --test-profile=user://test_numerical_hero_skills/profile.json
const Rules = preload("res://config/numerical_rules.gd")
const State = preload("res://scripts/core/run_state.gd")
var Player: GDScript
var Abilities: GDScript
var Relics: GDScript
var Deployment: GDScript
var game: Node
var checks: int = 0
var failures: int = 0
var actor: Node2D
var room: PacketRoom

class PacketRoom extends Node2D:
	var player: Node2D
	var combat_audio: Node
	var expedition_context: Dictionary = {}
	var layout_id: String = "numerical_hero_skills"
	var packets: Array[Dictionary] = []
	var telemetry: Dictionary = {"arc_hits":0, "split_spawned":0}
	func move_actor(at: Vector2, movement: Vector2, _radius: float) -> Vector2: return at + movement
	func valid_ground(_at: Vector2, _radius: float) -> bool: return true
	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool: return true
	func add_ring(_at: Vector2, _color: Color, _radius: float, _duration: float) -> void: pass
	func add_arc_visual(_at: Vector2, _direction: Vector2, _radius: float, _angle: float, _color: Color, _duration: float) -> void: pass
	func add_arc_between(_from: Vector2, _to: Vector2) -> void: pass
	func strike_area(_at: Vector2, _radius: float, amount: Variant, source: StringName, _status: String = "", _push: float = 0.0, _direction: Vector2 = Vector2.ZERO, _arc: float = 360.0, _original: bool = true, context: Dictionary = {}, _confirmed_only: bool = false) -> Array:
		packets.append({"kind":"strike", "source":source, "amount":amount, "context":context.duplicate(true)})
		return []
	func spawn_ability_projectile(_at: Vector2, _direction: Vector2, amount: Variant, options: Dictionary) -> void:
		packets.append({"kind":"projectile", "amount":amount, "context":options.duplicate(true)})
	func add_deployment(kind: String, _at: Vector2, options: Dictionary) -> void:
		packets.append({"kind":kind, "amount":options.damage, "context":options.duplicate(true)})
	func targets_in_radius(_at: Vector2, _radius: float) -> Array[Node2D]: return []

class TargetStub extends Node2D:
	var packets: Array[Dictionary] = []
	func is_alive() -> bool: return true
	func take_damage(amount: Variant, source: StringName, _direction: Vector2, context: Dictionary) -> void:
		packets.append({"amount":amount, "source":source, "context":context})

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("NUMERICAL HERO SKILLS FAIL: " + label)

func same(actual: Variant, expected: Variant) -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		return absf(float(actual) - float(expected)) < 0.000001
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not same(actual[key], expected[key]): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index: int in expected.size():
			if not same(actual[index], expected[index]): return false
		return true
	return actual == expected

func stats_for(hero: String, level: int, version: int = Rules.V2) -> Dictionary:
	var bases: Dictionary = {"CH01":[270, 0, 1500], "CH02":[240, 0, 1100], "CH03":[180, 280, 1050]}
	var stats: Dictionary = {"ruleset_version":version, "resource_max":1000, "resource_regen":180 if hero == "CH02" else 50, "branches":{}}
	stats.attack = Rules.integer(float(bases[hero][0]) * (1.0 + 0.04 * (level - 1)))
	stats.ability_power = Rules.integer(float(bases[hero][1]) * (1.0 + 0.05 * (level - 1)))
	stats.max_hp = Rules.integer(float(bases[hero][2]) * (1.0 + 0.05 * (level - 1)))
	return stats

func fresh(hero: String, level: int = 1, version: int = Rules.V2) -> void:
	if is_instance_valid(actor): actor.free()
	if is_instance_valid(room): room.free()
	game.run = State.new()
	game.run.hero_id = hero
	game.run.level = level
	game.run.stats = stats_for(hero, level, version)
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 1000
	room = PacketRoom.new()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	actor = Player.new()
	actor.room = room
	room.player = actor
	actor._sync_status_ruleset()
	actor.passives.configure(actor)
	actor.abilities = Abilities.new()
	actor.abilities.owner_player = actor

func test_catalog() -> void:
	var text: String = FileAccess.get_file_as_string("res://docs/balance/TARGET_HERO_SKILL_BUFF_TABLES.md")
	var body: String = text.split("<!-- TARGET_SKILL_ROWS_START -->")[1].split("<!-- TARGET_SKILL_ROWS_END -->")[0]
	var count: int = 0
	var seen: Dictionary = {}
	for line: String in body.split("\n"):
		if not line.begins_with("| CH0"): continue
		var columns: PackedStringArray = line.trim_prefix("|").trim_suffix("|").split("|")
		var hero: String = columns[0].strip_edges()
		var level: int = int(columns[1])
		var slot: String = columns[2].strip_edges()
		var branch: String = columns[3].strip_edges()
		if branch == "默认": branch = ""
		var expected_spec: Dictionary = JSON.parse_string(columns[6].strip_edges().xml_unescape())
		var expected: Dictionary = JSON.parse_string(columns[7].strip_edges().xml_unescape())
		var expected_timeline: Array = JSON.parse_string(columns[8].strip_edges().xml_unescape())
		var label: String = "%s/%d/%s/%s" % [hero, level, slot, branch]
		check(not seen.has(label), label + " unique fixture")
		seen[label] = true
		fresh(hero, level)
		game.run.stats.branches = {slot:branch}
		var spec: Dictionary = Abilities.preview_spec(hero, level, game.run.stats, slot)
		check(same(spec, expected_spec), label + " complete preview preserves coefficients, time, range, unlock and branch")
		check(typeof(spec.cost) == TYPE_INT and (not spec.has("health") or typeof(spec.health) == TYPE_INT), label + " only combat costs/health become integers")
		var powers: Dictionary = Abilities.preview_powers(hero, game.run.stats)
		check(powers.basic_H == expected.basic_H and powers.skill_H == expected.skill_H and powers.relic_H == expected.relic_H, label + " three preview H match frozen target")
		check(actor.basic_power() == expected.basic_H and actor.skill_power() == expected.skill_H and actor.relic_power() == expected.relic_H, label + " actor H matches preview")
		check(typeof(actor.basic_power()) == TYPE_INT and typeof(actor.skill_power()) == TYPE_INT and typeof(actor.relic_power()) == TYPE_INT, label + " H stored as integer values")
		var old_stats: Dictionary = game.run.stats.duplicate(true)
		old_stats.erase("ruleset_version")
		var old_spec: Dictionary = Abilities.preview_spec(hero, level, old_stats, slot)
		var old_expected: Dictionary = expected_spec.duplicate(true)
		old_expected.cost = float(old_expected.cost) / 10.0
		if old_expected.has("health"): old_expected.health = float(old_expected.health) / 10.0
		check(same(old_spec, old_expected), label + " unversioned complete preview remains legacy")
		var timeline: Array = actor.abilities._timeline(spec)
		check(same(timeline, expected_timeline), label + " release timeline unchanged")
		actor.abilities.active = {"spec":spec, "power":actor.skill_power(), "attacker_stats":game.run.stats.duplicate(true), "serial":1, "target":Vector2(100, 0), "direction":Vector2.RIGHT, "events":timeline}
		for event: Dictionary in timeline: actor.abilities._resolve(int(event.index))
		check(room.packets.size() == timeline.size() + (1 if hero == "CH03" and slot == "ultimate" else 0), label + " actual finite release count")
		for packet: Dictionary in room.packets:
			var expected_amount: int = int(expected.field_tick_damage) if packet.kind == "field" else int(expected.damage_each)
			check(typeof(packet.amount) == TYPE_INT and packet.amount == expected_amount, label + " actual emitted integer packet " + str(packet.kind))
			check(typeof(packet.context.power) == TYPE_INT and packet.context.power == expected.skill_H, label + " committed skill H snapshot")
			if packet.kind == "node":
				check(packet.context.health == expected.node_health and packet.context.health_scale_version == 10, label + " native node health is marked against rescaling")
				var node: Node2D = Deployment.new()
				node.configure(room, "node", packet.context)
				check(node.health == expected.node_health, label + " deployment health not scaled twice")
				node.free()
			if hero == "CH03" and slot == "q": check(packet.context.echo_damage == expected.node_echo_damage and typeof(packet.context.echo_damage) == TYPE_INT, label + " Q echo integer packet")
		count += 1
	check(count == 264 and seen.size() == 264, "all 264 authored skill combinations verified")

func test_cast_costs_and_gates() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		for slot: String in ["q", "secondary", "f", "ultimate"]:
			fresh(hero, 20)
			var data: Dictionary = actor.abilities.spec(slot)
			var before: int = game.run.resource
			check(actor.abilities.try_cast(slot, Vector2(100, 0)), hero + "/" + slot + " real commitment succeeds")
			check(before - game.run.resource == data.cost, hero + "/" + slot + " spends exact scaled cost")
			check(actor.resource_delay == (0.5 if hero == "CH02" else 0.8), hero + " recovery delay unchanged")
			fresh(hero, 1)
			if slot != "q": check(not actor.abilities.try_cast(slot, Vector2(100, 0)) and actor.abilities.last_failure == "locked", hero + "/" + slot + " original unlock gate")
	for stacks: int in range(4):
		fresh("CH01", 20)
		actor.break_stacks = stacks
		game.run.resource = 0 if stacks == 3 else 1000
		check(actor.skill_definition("secondary").cost == (0 if stacks == 3 else 300), "Momentum live/HUD cost " + str(stacks))
		check(Abilities.preview_spec("CH01", 20, game.run.stats, "secondary").cost == 300, "catalog ignores live Momentum")
		check(actor.abilities.try_cast("secondary", Vector2(100, 0)), "Momentum commitment " + str(stacks))
		check(actor.break_stacks == 0, "Momentum consumed once")
		actor.abilities.tick(0.3)
		check(room.packets[0].amount == Rules.integer((2.2 + 0.45 * stacks) * 475), "Momentum coefficient integer release " + str(stacks))
		actor.abilities.cancel()
		check(game.run.resource == (0 if stacks == 3 else 700), "cancel never refunds cost or stacks")
	fresh("CH03", 17)
	game.run.stats.branches = {"q":"A", "ultimate":"B"}
	check(actor.abilities.spec("q").branch == "" and actor.abilities.spec("ultimate").branch == "", "permanent branches remain locked")
	game.run.level = 18
	check(actor.abilities.spec("q").branch == "A" and actor.abilities.spec("ultimate").branch == "", "Q branch unlocks at eighteen only")

func test_caps() -> void:
	for version: int in [Rules.LEGACY, Rules.V2]:
		fresh("CH03", 20, version)
		game.run.stats.cooldown_reduction = 0.99
		game.run.stats.attack_interval = 0.2
		game.run.stats.attack_speed_bonus = 0.8
		game.run.stats.damage_bonus = 0.9
		game.run.stats.burn_damage = 1.25
		game.run.stats.corrosion_damage_bonus = 1.25
		check(is_equal_approx(actor.abilities.spec("q").cooldown, 3.0 if version == Rules.V2 else 3.5), "cooldown cap follows frozen version")
		check(is_equal_approx(actor.stat("attack_interval", 0.0), 0.2 if version == Rules.V2 else 0.225), "attack speed cap follows frozen version")
		check(actor.stat("damage_bonus", 0.0) == (0.9 if version == Rules.V2 else 0.6), "direct bonus cap follows frozen version")
		check(actor.stat("burn_damage", 0.0) == (1.0 if version == Rules.V2 else 1.25), "burn bucket cap is V2 only")
		check(actor.stat("corrosion_damage_bonus", 0.0) == (1.0 if version == Rules.V2 else 1.25), "corrosion bucket cap is V2 only")

func test_resources_and_relics() -> void:
	fresh("CH01")
	game.run.resource = 0
	game.run.stats.resource_gain_bonus = 0.75
	actor.on_primary_hit(null)
	check(game.run.resource == 104, "rage basic eighty with capped thirty-percent gain")
	actor.combat_time = 0
	actor._tick_resources(0.5)
	check(game.run.resource == 74, "rage sixty/second decay does not take positive bonus")
	for hero: String in ["CH02", "CH03"]:
		fresh(hero)
		game.run.resource = 0
		game.run.stats.resource_gain_bonus = 0.3
		actor.resource_delay = 0.5 if hero == "CH02" else 0.8
		actor._tick_resources(actor.resource_delay)
		check(game.run.resource == 0, hero + " no gain during full recovery delay")
		for index: int in 60: actor._tick_resources(1.0 / 60.0)
		check(game.run.resource == (234 if hero == "CH02" else 65), hero + " effective integer rate is frame-independent")
	fresh("CH03")
	game.run.stats.resource_regen = 50.25
	game.run.resource = 0
	for index: int in 60: actor._tick_resources(1.0 / 60.0)
	check(game.run.resource == 50 and game.run.resource_regen_remainder < 0.000001, "round per-second effective rate before accumulating fractional time")
	game.run.stats.resource_gain_bonus = 0.3
	game.run.resource = 0
	actor.passives._record_rhythm("basic")
	actor.passives._record_rhythm("skill")
	actor.passives._record_rhythm("basic")
	actor.passives.skill_committed("q", 42)
	check(game.run.resource == 104, "mage passive restores eighty with gain bonus")
	actor.passives.skill_committed("q", 42)
	check(game.run.resource == 104, "duplicate committed root cannot refund twice")
	var target := TargetStub.new()
	for rank: int in [1, 2]:
		fresh("CH03")
		game.run.resource = 0
		game.run.stats.resource_gain_bonus = 0.3
		Relics._emit_arc(room, "CH03", 0.35 * (1.5 if rank == 2 else 1.0), {}, Vector2.ZERO, target, Vector2.RIGHT)
		check(game.run.resource == (59 if rank == 2 else 39), "relic mana scaled once and whole-expression rounded " + str(rank))
		check(target.packets.back().amount == (147 if rank == 2 else 98) and typeof(target.packets.back().amount) == TYPE_INT, "mage relic uses AP, never basic/skill H " + str(rank))
		check(Relics.display("CH03", "RL03", rank, "", Rules.V2).description.contains("45" if rank == 2 else "30"), "relic V2 display uses scaled base refund")
	fresh("CH02", 18)
	actor.passives._count = 2
	actor.passives._focus = weakref(target)
	actor.passives._focus_remaining = 5.0
	actor.class_mark_target(target)
	var context: Dictionary = {"H":403, "equipment_eligible":true, "root_event_id":"calibration", "proc_depth":0}
	check(actor.class_modify_hit_amount(target, 100, &"secondary", context) == 866, "calibration and mark additions each round independently")
	target.free()
	fresh("CH03", 1, Rules.LEGACY)
	game.run.stats.attack = 18.25
	game.run.stats.ability_power = 28.5
	game.run.resource = 0
	game.run.stats.resource_gain_bonus = 0.3
	check(actor.attack_power() == 18.25 and actor.basic_power() == 18.25 and is_equal_approx(actor.skill_power(), 38.2) and actor.relic_power() == 28.5, "legacy H retains fractional AD and skill formula")
	check(actor.restore_class_resource(4.5) == 4.5, "legacy gain ignores new bucket")
	check(Relics.native_status_power("CH03", 28.5, 2) == 42.75 and Relics.native_status_power("CH03", 281, 2, Rules.V2) == 422, "native status version boundary remains opt-in")
	fresh("CH03", 60)
	check(actor.attack_power() == 605 and actor.basic_power() == 992 and actor.skill_power() == 1379 and actor.relic_power() == 1106, "future sixty-level H interface without enabling content")

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_numerical_hero_skills"):
		push_error("Refusing non-test profile for numerical hero skills")
		quit(2)
		return
	Player = load("res://scripts/combat/player.gd")
	Abilities = load("res://scripts/combat/hero_abilities.gd")
	Relics = load("res://scripts/combat/class_relics.gd")
	Deployment = load("res://scripts/combat/hero_deployment.gd")
	test_catalog()
	test_cast_costs_and_gates()
	test_resources_and_relics()
	test_caps()
	if is_instance_valid(actor): actor.free()
	if is_instance_valid(room): room.free()
	game.run = null
	print("NUMERICAL HERO SKILLS: ", checks - failures, "/", checks, " passed")
	quit(0 if failures == 0 else 1)
