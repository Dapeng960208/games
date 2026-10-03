extends SceneTree
## Production Core API: resistance resolution, health mutation and settlement.
const Controller = preload("res://scripts/app/game.gd")
var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CORE DAMAGE FAIL: " + label)

func _game(name: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + name + ".json"
	root.add_child(game)
	_check(game.new_profile() and game.start_run(), "isolated production run starts")
	return game

func _reset(game: Node, armor: float = 100.0, magic_resist: float = 25.0, reduction: float = 0.0) -> void:
	game.run.max_hp = 1000.0
	game.run.hp = 800.0
	game.run.shield = 0.0
	game.run.stats.armor = armor
	game.run.stats.magic_resist = magic_resist
	game.run.stats.damage_reduction = reduction
	game.run.stats.equipment_damage_reduction = reduction

func _run() -> void:
	directory = "user://core_damage_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var game := _game("damage")
	_reset(game)
	_check(is_equal_approx(game.damage_player(100.0), 50.0) and is_equal_approx(game.run.hp, 750.0), "legacy incoming hits default to physical and armor resolves once")
	_reset(game)
	_check(is_equal_approx(game.damage_player(100.0, {"damage_type":"magic"}), 80.0), "magic uses magic resistance rather than armor")
	_reset(game, 1000.0, 1000.0, 0.35)
	_check(is_equal_approx(game.damage_player(100.0, {"damage_type":"true","damage_reduction":0.3}), 100.0), "true damage bypasses both defenses and generic damage reduction")
	_reset(game, 100.0, 100.0, 0.2)
	_check(is_equal_approx(game.damage_player(100.0), 40.0), "equipment aliases count once after physical defense")
	_reset(game, 100.0, 100.0, 0.2)
	var context: Dictionary = {"damage_type":"magic","damage_reduction":0.25,"attacker_stats":{"magic_penetration":50.0}}
	var original_context := context.duplicate(true)
	var original_stats: Dictionary = game.run.stats.duplicate(true)
	_check(is_equal_approx(game.damage_player(100.0, context), 100.0 / 1.5 * 0.55), "status and equipment reduction combine once after resistance penetration")
	_check(context == original_context and game.run.stats == original_stats, "damage does not mutate caller context or stored stats")
	_reset(game, 0.0, 0.0, 0.35)
	_check(is_equal_approx(game.damage_player(100.0, {"damage_reduction":0.6}), 35.0), "generic reduction observes resolver cap independently of armor")
	_reset(game, 100.0, 25.0)
	_check(is_equal_approx(game.damage_player(100.0, {"attacker_stats":{"armor_penetration":50.0}}), 100.0 / 1.5), "physical attacker penetration reduces matching resistance")
	_reset(game, 100.0, 25.0)
	_check(is_equal_approx(game.damage_player(100.0, {"armor_penetration":100.0,"attacker_stats":{"armor_penetration":10.0}}), 100.0), "explicit attack penetration overrides attacker snapshot")
	_reset(game, 50.0, 25.0)
	_check(is_equal_approx(game.damage_player(100.0, {"armor_penetration":500.0}), 100.0), "excess penetration cannot amplify damage past zero resistance")
	_reset(game, 100.0, 25.0)
	_check(is_equal_approx(game.damage_player(100.0, {"damage_type":"magic","armor_penetration":1000.0}), 80.0), "physical penetration cannot bypass magic resistance")
	_reset(game, 100.0, 25.0)
	_check(is_equal_approx(game.damage_player(100.0, {"critical":true,"already_critical":false,"attacker_stats":{"crit_multiplier":2.0}}), 100.0), "unmultiplied critical packet is amplified exactly once")
	_reset(game, 100.0, 25.0)
	_check(is_equal_approx(game.damage_player(100.0, {"critical":true,"attacker_stats":{"crit_multiplier":2.0}}), 50.0), "already-scaled critical packet does not multiply again")
	_reset(game)
	game.run.shield = 30.0
	_check(is_equal_approx(game.damage_player(100.0), 20.0) and game.run.shield == 0.0 and game.run.hp == 780.0, "shield absorbs resolved damage before health loss")
	_reset(game)
	game.run.shield = 130.0
	_check(game.damage_player(100.0, {"damage_type":"true"}) == 0.0 and game.run.shield == 30.0 and game.run.hp == 800.0, "true damage still consumes shield before health")
	for type: String in ["physical", "magic", "true"]:
		_reset(game)
		game.run.shield = 40.0
		_check(game.damage_player(100.0, {"damage_type":type,"invulnerable":true}) == 0.0 and game.run.hp == 800.0 and game.run.shield == 40.0, "invulnerability preserves shield and health against " + type)
	_reset(game)
	for invalid: float in [NAN, INF, -1.0, 0.0]:
		_check(game.damage_player(invalid) == 0.0 and game.run.hp == 800.0, "invalid damage does not mutate health")
	_test_healing(game)
	var signals := {"finished":0}
	game.run_finished.connect(func(_result: Dictionary) -> void: signals.finished += 1)
	game.run.hp = 20.0
	game.damage_player(100.0, {"damage_type":"true"})
	_check(game.run == null and game.last_result.outcome == "death" and signals.finished == 1, "fatal resolved damage settles once")
	_check(game.damage_player(100.0) == 0.0 and game.heal_player(100.0) == 0.0 and signals.finished == 1, "damage and healing cannot resurrect or re-settle a finished run")
	game.free()
	_test_pending_death()
	print("CORE DAMAGE TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _test_healing(game: Node) -> void:
	_reset(game)
	_check(game.heal_player(100.0) == 100.0 and game.run.hp == 900.0, "normal combat healing reports actual health gained")
	_check(game.heal_player(100.0, 0.6) == 60.0 and game.run.hp == 960.0, "grievous healing multiplier applies once")
	_check(game.heal_player(100.0) == 40.0 and game.run.hp == 1000.0, "healing caps at max health and returns capped gain")
	_check(game.heal_player(100.0, 0.6) == 0.0 and game.run.hp == 1000.0, "full-health healing does not overheal")
	game.run.hp = 500.0
	_check(game.heal_player(100.0, 0.0) == 0.0 and game.run.hp == 500.0, "zero healing multiplier blocks recovery")
	for multiplier: float in [-0.1, 1.1, NAN, INF]:
		_check(game.heal_player(100.0, multiplier) == 0.0 and game.run.hp == 500.0, "invalid multiplier rejects without changing HP")
	for invalid: float in [NAN, INF, -1.0, 0.0]:
		_check(game.heal_player(invalid) == 0.0 and game.run.hp == 500.0, "invalid heal rejects without changing HP")
	game.run.hp = 0.0
	_check(game.heal_player(100.0) == 0.0 and game.run.hp == 0.0, "healing cannot revive a dead actor")
	game.run.hp = 500.0

func _test_pending_death() -> void:
	var game := _game("pending")
	var blocked := directory + "/not-a-directory"
	var file := FileAccess.open(AssetCatalog.resolve(blocked), FileAccess.WRITE)
	file.store_string("block fixture writes")
	file.close()
	game._store.path = blocked + "/profile.json"
	game.damage_player(100000.0, {"damage_type":"true"})
	_check(game.run != null and game.run.hp == 0.0 and not game._pending_outcome.is_empty(), "failed death save preserves pending settlement")
	_check(game.heal_player(100.0) == 0.0 and game.damage_player(100.0) == 0.0 and game.run.hp == 0.0, "pending settlement blocks all health mutation")
	game._store.path = game.profile_path
	_check(game.finish_run("death").outcome == "death" and game.run == null, "pending death can still settle after storage recovers")
	game.free()
