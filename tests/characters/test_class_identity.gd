extends SceneTree
## Run with --headless --script res://tests/characters/test_class_identity.gd --
## --test-profile=user://test_class_identity/profile.json
## Real rooms, damage pipeline and deployed nodes; no production profile or import.

var game: Node
var room: Node2D
var room_scene: PackedScene
var resolver: Script
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CLASS IDENTITY FAIL: " + description)

func fixture(hero: String, level: int = 8) -> void:
	if is_instance_valid(room):
		room.free()
	game.run.hero_id = hero
	game.run.level = level
	game.run.stats = resolver.resolve(hero, level, {}, {})
	game.run.stats["crit_chance"] = 0.0
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430, 350)
	room.player.aim_direction = Vector2.RIGHT

func dummy(at: Vector2) -> Node2D:
	var enemy: Node2D = room.spawn_enemy(at)
	enemy.health.reset(10000.0)
	enemy.state = &"chase"
	return enemy

func finish_cast() -> void:
	room.player.abilities.tick(2.0)

func cast(slot: String, at: Vector2) -> bool:
	game.run.resource = 100.0
	room.player.cooldowns[slot] = 0.0
	room.player.attack_remaining = 0.0
	return room.player.cast_skill(slot, at)

func add_node(at: Vector2) -> Node2D:
	check(cast("secondary", at), "node can be placed on legal ground")
	finish_cast()
	var nodes: Array[Node2D] = []
	for child: Node in room.get_children():
		if child.has_method("charge_node") and child.kind == "node" and child.is_alive():
			nodes.append(child)
	var result: Node2D = nodes.back()
	result.advance(0.35)
	return result

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_class_identity"):
		push_error("Refusing non-test profile; use test_class_identity in profile path")
		quit(2)
		return
	room_scene = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn"))
	resolver = load(AssetCatalog.resolve("res://scripts/domain/combat/stat_resolver.gd"))
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated run starts")
	if game.run == null:
		quit(1)
		return
	_test_breaker()
	_test_ranger()
	_test_resonator()
	_test_spell_snapshots()
	_test_received_damage_and_healing()
	_test_unlocks_and_room_local_state()
	_test_lethal_shock_demo_boundary()
	if is_instance_valid(room):
		if is_instance_valid(room.combat_audio):
			await room.combat_audio.wait_for_cleanup()
		room.free()
	print("CLASS IDENTITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_breaker() -> void:
	fixture("CH01")
	var target: Node2D = dummy(Vector2(490, 350))
	dummy(Vector2(490, 365))
	check(room.player.fire(Vector2.RIGHT), "breaker basic attack starts")
	room.player._tick_attack(0.50)
	check(room.player.break_stacks == 1, "one multi-target swing grants exactly one Momentum")
	room.player.on_primary_hit(target)
	room.player.on_primary_hit(target)
	room.player.on_primary_hit(target)
	check(room.player.break_stacks == 3, "Momentum caps at three")
	check(cast("secondary", target.position), "empowered sweep starts")
	var data: Dictionary = room.player.abilities.active.spec
	check(room.player.break_stacks == 0 and is_equal_approx(float(data.coefficient), 3.55), "sweep commits all three stacks for 3.55H")
	check(float(data.radius) == 140.0 and float(data.arc) == 160.0, "full Momentum widens the heavy hammer sweep")
	room.player.cancel_actions()
	check(room.player.break_stacks == 0, "cancelled sweep cannot refund committed Momentum")
	check(cast("f", room.player.position), "brace starts")
	finish_cast()
	check(room.player.break_stacks == 1 and game.run.shield > 0.0, "brace grants one Momentum and retains shield")
	dummy(Vector2(620, 350))
	dummy(Vector2(625, 360))
	check(cast("q", Vector2(650, 350)), "rush starts")
	finish_cast()
	check(room.player.break_stacks == 2, "multi-target rush grants one Momentum")
	check(room.player.class_status().max == 3, "breaker exposes a three-stack HUD status")

func _test_ranger() -> void:
	fixture("CH02")
	var target: Node2D = dummy(Vector2(500, 350))
	var power: float = room.player.attack_power()
	var context: Dictionary = {"H":power, "power":power, "equipment_eligible":true, "original_basic":false, "root_event_id":"identity:test", "attack_id":"identity:test"}
	room.resolve_direct_hit(target, 1.0, &"f", "", 0.0, Vector2.RIGHT, context)
	check(room.player.class_marks.has(target.get_instance_id()), "confirmed original F contact marks its target for a precision follow-up")
	var marked: float = room.player.class_modify_hit_amount(target, power * 2.0, &"secondary", context)
	check(is_equal_approx(marked, power * 3.25), "marked secondary adds exactly 1.25H")
	check(is_equal_approx(room.player.class_modify_hit_amount(target, power * 2.0, &"secondary", context), power * 2.0), "one mark cannot be consumed twice")
	room.player.class_mark_target(target)
	check(is_equal_approx(room.player.class_modify_hit_amount(target, power, &"primary", context), power) and room.player.class_marks.size() == 1, "basic hits cannot consume marks")
	room.player._tick_class_state(4.01)
	check(room.player.class_marks.is_empty(), "marks expire after four seconds")
	room.resolve_direct_hit(target, power, &"f", "", 0.0, Vector2.RIGHT, context)
	check(room.player.class_marks.has(target.get_instance_id()), "production original-hit hook marks an F victim")
	var before: float = target.health.current
	room.resolve_direct_hit(target, power, &"ultimate", "", 0.0, Vector2.RIGHT, context)
	var burst: float = before - target.health.current
	check(room.player.class_marks.is_empty(), "production R hit consumes the mark")
	before = target.health.current
	room.resolve_direct_hit(target, power, &"ultimate", "", 0.0, Vector2.RIGHT, context)
	check(burst > (before - target.health.current) * 1.8, "mark burst is part of the original damage packet")

func _test_resonator() -> void:
	fixture("CH03")
	check(is_equal_approx(float(room.player.abilities.spec("secondary").cooldown), 3.5), "nodes have a 3.5 second baseline cooldown")
	var first: Node2D = add_node(Vector2(490, 350))
	var second: Node2D = add_node(Vector2(550, 350))
	check(first.lifetime == 14.0 and room.player.resonance_nodes().size() == 2, "two nodes have fourteen-second lifetimes")
	var bolt: Node2D = room.spawn_ability_projectile(first.position, Vector2.RIGHT, 1.0, {"source":"q", "status":"shock", "speed":650.0, "range":550.0, "root_event_id":"identity:q1"})
	first.advance(0.01)
	first.advance(0.01)
	second.advance(0.01)
	check(first.resonance_charge == 1 and second.resonance_charge == 1, "a real Q bolt charges each nearby node once")
	bolt.options.root_event_id = "identity:q2"
	first.advance(0.01)
	check(first.resonance_charge == 2, "a new Q cast can add another charge")
	check(cast("ultimate", Vector2(530, 350)), "resonance field starts")
	finish_cast()
	check(first.resonance_charge == 3 and second.resonance_charge == 3, "R fully charges both nodes in its field")
	check(room.player.charge_resonance(first.position, 200.0, 1) == 0, "environmental charge cannot overfill nodes")
	check(first.resonance_readout().charge + second.resonance_readout().charge == 6, "individual crystal readouts report six total stored charges")
	check(room.player.class_status().max == 3, "mage class HUD reports the separate three-beat passive rhythm")
	var target: Node2D = dummy(Vector2(540, 350))
	var before: float = target.health.current
	check(cast("f", room.player.position), "manual detonation starts")
	finish_cast()
	check(not first.is_alive() and not second.is_alive(), "F consumes both deployed nodes")
	check(room.player.resonance_nodes().is_empty(), "detonated nodes immediately leave the active set")
	check(target.health.current < before - room.player.attack_power() * 4.0, "overlapping charged node blasts damage the enemy")
	check(not first.detonate(), "a consumed node cannot detonate twice")
	var pending: Node2D = room.add_deployment("node", Vector2(490, 350), {"power":18.0, "owner_player":room.player})
	check(not pending.charge_node(1) and not pending.detonate(), "unfolding nodes cannot charge or detonate")

func _test_unlocks_and_room_local_state() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		fixture(hero, 1)
		check(not cast("secondary", room.player.position) and room.player.last_cast_error == "locked", "%s retains the level-two secondary gate" % hero)
		check(room.player.break_stacks == 0 and room.player.class_marks.is_empty(), "%s starts with fresh room-local state" % hero)
		check(room.player.abilities.spec("q").unlock == 1 and room.player.abilities.spec("secondary").unlock == 2 and room.player.abilities.spec("f").unlock == 3 and room.player.abilities.spec("ultimate").unlock == 4, "%s unlocks the complete skill loop by level four" % hero)

func _test_spell_snapshots() -> void:
	fixture("CH03")
	var attack: float = room.player.attack_power()
	game.run.stats.ability_power = 40.0
	var spell: float = attack + 28.0
	check(is_equal_approx(room.player.skill_power(), spell) and is_equal_approx(room.player.attack_power(), attack), "forty AP adds twenty-eight spell power without changing basic power")
	check(cast("q", Vector2(600, 350)), "spell-powered Q starts")
	game.run.stats.ability_power = 0.0
	check(is_equal_approx(float(room.player.abilities.active.power), spell), "Q snapshots spell power at cast commitment")
	finish_cast()
	var bolt: Node2D = room.projectiles.get_children().back()
	check(is_equal_approx(bolt.damage, spell * 1.25) and bolt.options.damage_type == "magic", "Q uses the captured magic coefficient")
	check(is_equal_approx(float(bolt.options.echo_damage), spell * .35) and float(bolt.options.attacker_stats.ability_power) == 40.0, "Q echo and attacker attributes use the same original snapshot")
	game.run.stats.ability_power = 40.0
	var node: Node2D = add_node(Vector2(500, 350))
	game.run.stats.ability_power = 0.0
	check(is_equal_approx(node.damage, spell * .15) and is_equal_approx(float(node.options.power), spell), "node cannon and detonation retain deployment spell power")
	dummy(Vector2(540, 350))
	node._fire_node()
	bolt = room.projectiles.get_children().back()
	check(bolt.source == &"node" and bolt.options.damage_type == "magic" and not bolt.options.original and not bolt.options.equipment_eligible, "node cannon stays derived magic and cannot enter an original equipment chain")
	check(cast("f", room.player.position), "spell-powered F starts")
	check(is_equal_approx(float(room.player.abilities.active.power), attack), "F takes its own current power, separate from previously deployed nodes")
	finish_cast()
	game.run.stats.ability_power = 40.0
	check(cast("ultimate", Vector2(530, 350)), "spell-powered R starts")
	check(is_equal_approx(float(room.player.abilities.active.power), spell), "R direct strike captures current spell power")
	finish_cast()
	var field: Node2D
	for child: Node in room.get_children():
		if child.has_method("charge_node") and child.kind == "field":
			field = child
	check(is_instance_valid(field) and is_equal_approx(field.damage, spell * .8) and field.options.damage_type == "magic", "R sustained field retains its magic snapshot")
	for hero: String in ["CH01", "CH02"]:
		fixture(hero)
		game.run.stats.ability_power = 100.0
		check(is_equal_approx(room.player.skill_power(), room.player.attack_power()) and room.player.abilities.spec("q").damage_type == "physical", "%s remains physical and does not inherit mage scaling" % hero)

func _test_received_damage_and_healing() -> void:
	fixture("CH01")
	game.run.stats.armor = 100.0
	game.run.stats.magic_resist = 25.0
	game.run.stats.equipment_damage_reduction = 0.0
	game.run.hp = 100.0
	room.player.receive_damage(60.0, Vector2.ZERO, {"damage_type":"physical", "attacker_stats":{"armor_penetration":50.0}})
	check(is_equal_approx(game.run.hp, 60.0), "incoming armor penetration yields forty damage against fifty effective armor")
	room.player.invulnerable = 0.0
	game.run.hp = 100.0
	room.player.receive_damage(50.0, Vector2.ZERO, {"damage_type":"magic"})
	check(is_equal_approx(game.run.hp, 60.0), "incoming magic uses twenty-five MR instead of one hundred armor")
	room.player.invulnerable = 0.0
	game.run.hp = 100.0
	room.player.receive_enemy_status({"id":"damage_reduction", "power":0.5, "duration":5.0})
	room.player.receive_damage(40.0, Vector2.ZERO, {"damage_type":"physical"})
	check(is_equal_approx(game.run.hp, 90.0), "status reduction joins resistance exactly once")
	room.player.invulnerable = 0.0
	game.run.hp = 100.0
	room.player.receive_damage(20.0, Vector2.ZERO, {"damage_type":"true"})
	check(is_equal_approx(game.run.hp, 80.0), "true damage ignores resistance and ordinary reduction")
	check(room.player.receive_enemy_status({"id":"invulnerable", "power":1.0, "duration":2.0}), "player accepts the explicit invulnerability state")
	var before: float = game.run.hp
	check(not room.player.receive_damage(20.0, Vector2.ZERO, {"damage_type":"true"}) and not room.player.receive_damage(20.0, Vector2.ZERO, {"dot":true, "damage_type":"magic"}), "status invulnerability blocks true hits and DOT alike")
	check(game.run.hp == before, "blocked invulnerable packets never reach health")
	room.player.status.states.clear()
	game.run.hp = 50.0
	check(room.player.receive_enemy_status({"id":"grievous", "duration":2.0}), "player accepts grievous wounds")
	check(is_equal_approx(room.player.heal(20.0), 12.0) and is_equal_approx(game.run.hp, 62.0), "grievous wounds applies the forty-percent healing penalty exactly once")
	room.player.status.tick(2.0)
	check(is_equal_approx(room.player.heal(20.0), 20.0), "healing returns to normal when grievous wounds expires")
	check(room.player.heal(INF) == 0.0, "nonfinite healing is rejected")
	room.player.status.states.clear()
	room.input_blocked = true
	game.run.stats.armor = 100.0
	game.run.stats.magic_resist = 100.0
	game.run.hp = 100.0
	room.player.receive_enemy_status({"id":"bleed", "power":100.0})
	room.player._physics_process(1.0)
	check(is_equal_approx(game.run.hp, 95.0), "ten raw bleed DOT becomes five physical damage")
	room.player.status.states.clear()
	game.run.hp = 100.0
	room.player.receive_damage(8.0, Vector2.ZERO, {"dot":true, "damage_type":"physical"})
	check(is_equal_approx(game.run.hp, 96.0), "without corrosion one hundred armor reduces eight physical DOT to four")
	game.run.hp = 100.0
	room.player.receive_enemy_status({"id":"corrosion", "power":100.0})
	room.player._physics_process(1.0)
	check(is_equal_approx(100.0-game.run.hp, 800.0/185.0), "corrosion reduces one hundred armor to eighty-five before its eight raw physical DOT")

func _test_lethal_shock_demo_boundary() -> void:
	# Disposable test state only: the demo must restore this exact profile and a
	# lethal first packet must never send the pending shock to another run.
	game.run = null
	var saved_profile: Dictionary = game.profile.duplicate(true)
	check(game.start_demo("CH01", 0), "isolated demo starts for lethal-packet regression")
	fixture("CH01")
	game.run.hp = 1.0
	room.player.receive_enemy_status({"id":"shock", "power":1000.0})
	check(room.player.receive_damage(100.0, Vector2.ZERO, {"damage_type":"physical"}), "lethal physical body is accepted while shock is pending")
	check(game.run == null and game.profile == saved_profile, "first-packet death restores demo profile without applying pending magic damage")
	check(not room.player.receive_damage(100.0, Vector2.ZERO), "late damage after demo restoration safely stops")
