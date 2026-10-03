extends SceneTree
## Focused acceptance of the three automatic passives through real hit/cast paths.
var room_scene: PackedScene
var resolver: Script
var game: Node
var room: Node2D
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HERO PASSIVES: " + description)

func fixture(hero: String) -> void:
	if is_instance_valid(room):
		room.free()
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = resolver.resolve(hero, 8, {}, {})
	game.run.stats["crit_chance"] = 0.0
	game.run.loadout_snapshot.clear()
	game.run.relics.clear()
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.stop_all()

func dummy(offset: Vector2 = Vector2(70, 0)) -> Node2D:
	var target: Node2D = room.spawn_enemy(room.player.position + offset, "M01", 1)
	target.health.reset(10000.0)
	target.armor = 0.0
	target.magic_resist = 0.0
	target.reward_enabled = false
	target.training_ai_disabled = true
	return target

func hit(target: Node2D, serial: int, source: StringName = &"primary", amount: float = 10.0) -> bool:
	var context: Dictionary = {"root_event_id":"test:" + str(serial), "attack_id":"test:" + str(serial), "power":20.0, "original_basic":source == &"primary", "equipment_eligible":true, "proc_depth":0}
	return room.resolve_direct_hit(target, amount, source, "", 0.0, Vector2.RIGHT, context)

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_hero_passives"):
		push_error("Use isolated test_hero_passives profile")
		quit(2)
		return
	check(game.new_profile() and game.start_run(), "isolated run starts")
	room_scene = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn"))
	resolver = load(AssetCatalog.resolve("res://scripts/domain/combat/stat_resolver.gd"))
	_test_guard()
	_test_weakpoint()
	_test_resonance()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("HERO PASSIVES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_guard() -> void:
	fixture("CH01")
	var a: Node2D = dummy()
	var b: Node2D = dummy(Vector2(70, 30))
	a.status.grant_guard(1000.0, 10.0, "test", a.health.maximum)
	check(hit(a, 1) and room.player.class_status().current == 1, "shield-only original hit builds support")
	hit(b, 1)
	check(room.player.class_status().current == 1, "same multi-target swing counts once")
	room.resolve_derived_hit(a, 10.0, &"equipment", Vector2.RIGHT, {})
	check(room.player.class_status().current == 1, "equipment derived hit cannot build support")
	check(not hit(a, 2, &"primary", 0.0) and room.player.class_status().current == 1, "zero damage does not count")
	hit(a, 3)
	hit(a, 4)
	check(is_equal_approx(game.run.shield, game.run.max_hp * 0.08), "third confirmed attack grants actual eight-percent shield")
	check(is_equal_approx(room.player.class_status().icd, 6.0), "support starts six-second cooldown")
	hit(a, 5)
	check(room.player.class_status().current == 0, "support does not bank hits during cooldown")
	room.player.passives.tick(6.0)
	hit(a, 6)
	check(room.player.class_status().current == 1, "support can begin another cycle after cooldown")

func _test_weakpoint() -> void:
	fixture("CH02")
	var a: Node2D = dummy()
	var b: Node2D = dummy(Vector2(70, 30))
	hit(a, 1)
	hit(a, 2)
	check(bool(room.player.class_status().ready), "two same-target hits expose weak point")
	a.apply_status("invulnerable", 1.0, 2.0)
	check(not hit(a, 3) and bool(room.player.class_status().ready), "immune hit does not spend weak point")
	a.status.states.erase("invulnerable")
	var before: float = a.health.current
	var combo_multiplier: float = 1.0 + float(room.player.hit_chain.snapshot().bonus)
	hit(a, 4)
	check(is_equal_approx(before - a.health.current, 23.0 * combo_multiplier), "third basic receives actual 0.65H original damage bonus and current chain multiplier")
	check(room.player.class_status().current == 0 and is_equal_approx(room.player.class_status().icd, 2.0), "confirmed bonus consumes weak point and starts cooldown")
	room.player.passives.tick(2.0)
	hit(a, 5)
	hit(b, 6)
	check(room.player.class_status().current == 1 and not bool(room.player.class_status().ready), "changing target restarts consecutive progress")
	hit(b, 7)
	before = b.health.current
	combo_multiplier = 1.0 + float(room.player.hit_chain.snapshot().bonus)
	hit(b, 8, &"q")
	check(is_equal_approx(before - b.health.current, 23.0 * combo_multiplier), "direct Q consumes and receives weak-point bonus and current chain multiplier")
	room.player.passives.tick(2.0)
	hit(a, 9)
	hit(a, 10)
	room.player.passives.tick(5.0)
	check(room.player.class_status().current == 0, "unspent weak point expires")

func _test_resonance() -> void:
	fixture("CH03")
	var a: Node2D = dummy()
	var node: Node2D = room.add_deployment("node", room.player.position + Vector2(90, 30), {"damage":1.0, "power":20.0, "radius":160.0, "health":35.0, "lifetime":14.0, "owner_player":room.player})
	node.advance(0.35)
	hit(a, 1)
	hit(a, 2)
	check(room.player.class_status().current == 1, "repeating basics does not build alternating resonance")
	check(room.player.abilities.try_cast("q", a.position), "successful Q commits the skill half of alternation")
	room.player.abilities.tick(1.0)
	check(room.player.class_status().current == 2, "a committed skill adds one alternating stack")
	hit(a, 3)
	check(bool(room.player.class_status().ready), "basic-skill-basic fills resonance")
	game.run.resource = 0.0
	check(not room.player.abilities.try_cast("secondary", room.player.position + Vector2(80, 0)) and bool(room.player.class_status().ready) and game.run.resource == 0.0, "failed cast neither spends readiness nor restores Mana")
	game.run.resource = 60.0
	check(room.player.abilities.try_cast("secondary", room.player.position + Vector2(80, 0)), "ready resonance follows a successful W commitment")
	check(is_equal_approx(game.run.resource, 38.0) and node.resonance_charge == 1, "W pays 30 Mana, restores exactly eight and charges one existing node")
	room.player.abilities.tick(2.0)
	check(is_equal_approx(game.run.resource, 38.0), "skill release/deployment cannot refund again")
	room.resolve_derived_hit(a, 10.0, &"field", Vector2.RIGHT, {})
	check(room.player.class_status().current == 0, "field damage cannot build resonance")
	room.player.passives.tick(2.0)
	hit(a, 4)
	check(room.player.class_status().current == 1, "alternation resumes after internal cooldown")
	room.player.passives.tick(8.0)
	check(room.player.class_status().current == 0, "idle resonance expires after eight seconds")
	hit(a, 5)
	game.run.hp = 0.0
	check(room.player.class_status().current == 0, "death clears passive state")
