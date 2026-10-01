extends SceneTree
## S01 opt-in actor/resource boundaries. No profile creation, saving or migration.
## godot --headless --path . --script res://tests/test_numerical_resources.gd -- --test-profile=user://test_numerical_resources/profile.json
const Rules = preload("res://config/numerical_rules.gd")
const State = preload("res://scripts/core/run_state.gd")
var Player: GDScript
var Deployment: GDScript
var checks: int = 0
var failures: int = 0
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("NUMERICAL RESOURCES FAIL: " + label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.000001, label + " actual=" + str(actual))

func fresh(version: int, hero: String = "CH03") -> void:
	game.run = State.new()
	game.run.hero_id = hero
	game.run.stats = {"ruleset_version":version, "max_hp":1001, "resource_max":1000, "resource_regen":50.0, "armor":0.0, "magic_resist":0.0}
	game.run.max_hp = 1001.0
	game.run.hp = 800.0
	game.run.resource = 500.0
	game.run.shield = 0.0

func test_legacy() -> void:
	var old := State.new()
	check(old.ruleset_version() == Rules.LEGACY and typeof(old.hp) == TYPE_FLOAT, "unversioned state retains legacy floats")
	fresh(Rules.LEGACY)
	game.run.hp = 800.25
	game.run.resource = 500.25
	game.run.shield = 0.25
	check(game.run.hp == 800.25 and game.run.resource == 500.25 and game.run.shield == 0.25, "legacy assignments preserve fractions")
	near(game.heal_player(4.4, 0.6), 2.64, "legacy healing unchanged")
	near(game.restore_resource(0.25), 0.25, "legacy resource restoration unchanged")
	check(game.try_spend_resource(0.25), "legacy fractional spend succeeds")
	near(game.resource_cost(0.25), 0.25, "legacy direct costs have no new floor")
	near(game.add_shield(0.25), 0.25, "legacy shield gains remain fractional")
	near(game.damage_player(1.25, {"damage_type":"true"}), 0.75, "legacy split shield/HP loss stays fractional")
	var player: Node2D = Player.new()
	game.run.resource = 0.0
	player._tick_resources(0.01)
	near(game.run.resource, 0.5, "legacy per-frame regeneration remains fractional")
	game.run.hero_id = "CH01"
	player.on_primary_hit(null)
	near(game.run.resource, 8.5, "legacy basic rage restore remains eight")
	player.combat_time = 0.0
	player._tick_resources(0.1)
	near(game.run.resource, 7.9, "legacy rage decay remains six per second")
	player.free()

func test_integer_boundaries() -> void:
	fresh(Rules.V2)
	game.run.hp = 800.5
	game.run.resource = 500.49
	game.run.shield = 3.5
	check(game.run.hp == 801 and game.run.resource == 500 and game.run.shield == 4, "V2 assignments use nonnegative half-up rounding")
	for key: String in ["hp", "max_hp", "resource", "shield"]:
		check(typeof(game.run.get(key)) == TYPE_INT, "V2 stored " + key + " is integer")
	var restored: Variant = game.heal_player(4.4, 0.6)
	check(typeof(restored) == TYPE_INT and restored == 3 and game.run.hp == 804, "healing rounds complete grievous expression once")
	game.run.hp = 1000
	check(game.heal_player(99) == 1 and game.run.hp == 1001, "integer healing caps to missing HP")
	check(game.heal_player(NAN) == 0 and game.heal_player(10, INF) == 0, "invalid healing cannot mutate state")
	check(game.resource_cost(0) == 0 and typeof(game.resource_cost(0)) == TYPE_INT, "zero cost remains integer zero")
	check(game.resource_cost(0.01) == 10 and game.resource_cost(15.5) == 16, "positive cost floor scales to ten")
	game.run.resource = 9
	check(not game.try_spend_resource(0.1) and game.run.resource == 9, "floor cost is checked before spending")
	game.run.resource = 10
	check(game.try_spend_resource(0.1) and game.run.resource == 0, "positive floor is actually spent")
	check(game.try_spend_resource(0) and game.run.resource == 0, "free cast spends zero")
	check(not game.try_spend_resource(-1) and not game.try_spend_resource(INF), "invalid spend rejected")
	check(game.restore_resource(0.49) == 0 and game.run.resource == 0, "discrete sub-half resource restore rounds down")
	check(game.restore_resource(0.5) == 1 and typeof(game.restore_resource(1.5)) == TYPE_INT, "resource restore returns integer gains")
	game.run.resource = 999
	check(game.restore_resource(999) == 1 and game.run.resource == 1000, "resource gain caps without overflow")
	game.run.shield = 0
	check(game.add_shield(800.5) == 501 and game.run.shield == 501, "odd maximum HP yields one rounded integer shield cap")
	game.run.hp = 1001
	game.run.shield = 4
	var loss: Variant = game.damage_player(10.5, {"damage_type":"true"})
	check(typeof(loss) == TYPE_INT and loss == 7 and game.run.hp == 994 and game.run.shield == 0, "true damage uses integer shield and HP boundaries")
	check(game.damage_player(100, {"damage_type":"true", "invulnerable":true}) == 0 and game.run.hp == 994, "immunity still blocks true damage")
	game.run.stats.armor = 1000
	check(game.damage_player(100, {"damage_type":"physical"}) == 50, "controller forwards frozen V2 version to defense resolver")
	var player: Node2D = Player.new()
	player._sync_status_ruleset()
	check(player.status.ruleset_version == Rules.V2, "actor status follows run version")
	game.run.hero_id = "CH01"
	game.run.resource = 0
	player.on_primary_hit(null)
	check(game.run.resource == 80, "V2 primary rage restore scales once")
	check(player.resource_cost(0.1) == 10 and typeof(player.resource_cost(0)) == TYPE_INT, "player preview and spend share integer floor")
	player.free()
	game.run.expedition = {"relic_levels":{}, "temporary_buffs":{}}
	game._refresh_expedition_stats()
	check(game.run.ruleset_version() == Rules.V2 and game.run.max_hp == 1500, "in-memory stat refresh retains frozen V2 rules")
	check(typeof(game.run.max_hp) == TYPE_INT and typeof(game.run.resource) == TYPE_INT, "stat refresh retains integer state")

func simulate_resource(hero: String, delta: float, steps: int, delay: float, rate: float) -> Dictionary:
	fresh(Rules.V2, hero)
	game.run.resource = 500 if hero == "CH01" else 0
	game.run.stats.resource_regen = rate
	var player: Node2D = Player.new()
	player.resource_delay = delay
	player.combat_time = delay
	for index in steps:
		player._tick_resources(delta)
	var result := {"resource":game.run.resource, "remainder":game.run.resource_decay_remainder if hero == "CH01" else game.run.resource_regen_remainder}
	player.free()
	return result

func test_accumulation() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		var coarse: Dictionary = simulate_resource(hero, 0.2, 20, 0.13, 50.25)
		var fine: Dictionary = simulate_resource(hero, 1.0 / 60.0, 240, 0.13, 50.25)
		check(typeof(fine.resource) == TYPE_INT and fine.resource == coarse.resource, hero + " frame sizes preserve total spendable resource")
		near(float(fine.remainder), float(coarse.remainder), hero + " frame sizes preserve sub-point remainder")
	fresh(Rules.V2)
	game.run.resource = 0
	var first: Node2D = Player.new()
	first._tick_resources(0.01)
	check(game.run.resource == 0 and is_equal_approx(game.run.resource_regen_remainder, 0.5), "sub-point frame is accumulated, not rounded")
	first.free()
	var next: Node2D = Player.new()
	next._tick_resources(0.01)
	check(game.run.resource == 1 and is_zero_approx(game.run.resource_regen_remainder), "replacement actor retains run-owned remainder")
	game.run.resource = 1000
	next._tick_resources(0.015)
	check(game.run.resource_regen_remainder == 0.0, "full resource does not bank recovery")
	game.run.resource = 900
	next._tick_resources(0.01)
	check(game.run.resource == 900, "spending from full does not cash a banked fraction")
	game.run.hero_id = "CH01"
	game.run.resource = 0
	next.combat_time = 0
	next._tick_resources(0.005)
	check(game.run.resource_decay_remainder == 0.0, "empty rage does not bank decay")
	next.free()

func test_deployment() -> void:
	fresh(Rules.LEGACY)
	var legacy: Node2D = Deployment.new()
	legacy.configure(null, "node", {"health":35.25})
	check(typeof(legacy.health) == TYPE_FLOAT and legacy.health == 35.25, "legacy crystal health stays exact")
	check(legacy.receive_damage(0.25) and legacy.health == 35.0, "legacy crystal damage stays fractional")
	legacy.free()
	fresh(Rules.V2)
	var node: Node2D = Deployment.new()
	node.configure(null, "node", {})
	check(typeof(node.health) == TYPE_INT and node.health == 350 and node.max_health == 350, "V2 default crystal health scales once")
	check(not node.receive_damage(0.49) and node.health == 350, "sub-half crystal packet has no false hit")
	check(node.receive_damage(1.5) and node.health == 348, "V2 crystal loss is integer")
	check(not node.receive_damage(INF) and not node.receive_damage(NAN) and node.health == 348, "invalid crystal packets rejected")
	node.free()
	var upgraded: Node2D = Deployment.new()
	upgraded.configure(null, "node", {"health":50.0})
	check(upgraded.health == 500, "upgraded authored crystal durability scales")
	upgraded.free()
	var native: Node2D = Deployment.new()
	native.configure(null, "node", {"health":500, "health_scale_version":10})
	check(native.health == 500, "V2-native S02 health is not scaled twice")
	native.free()

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_numerical_resources"):
		push_error("Refusing non-test profile for numerical resources")
		quit(2)
		return
	Player = load("res://scripts/combat/player.gd")
	Deployment = load("res://scripts/combat/hero_deployment.gd")
	test_legacy()
	test_integer_boundaries()
	test_accumulation()
	test_deployment()
	game.run = null
	print("NUMERICAL RESOURCES: ", checks - failures, "/", checks, " passed")
	quit(0 if failures == 0 else 1)
