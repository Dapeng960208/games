extends SceneTree
## Production Room, actors, damage pipeline and deployments; isolated profile.

const Relics = preload("res://scripts/combat/class_relics.gd")
var game: Node
var room: Node2D
var resolver: Script
var room_scene: PackedScene
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CLASS RELICS FAIL: " + label)

func fixture(hero: String, rank: int = 1) -> void:
	if is_instance_valid(room):
		room.free()
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = resolver.resolve(hero, 8, {}, {})
	game.run.stats["crit_chance"] = 0.0
	game.run.stats["relic_levels"] = {"RL01":rank,"RL02":rank,"RL03":rank}
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 50.0
	game.run.shield = 0.0
	game.run.relics.clear()
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for actor: Node in room.enemies.get_children():
		actor.free()
	room.player.position = Vector2(430,350)
	room.player.aim_direction = Vector2.RIGHT

func target(at: Vector2) -> Node2D:
	var actor: Node2D = room.spawn_enemy(at)
	actor.health.reset(10000.0)
	actor.armor = 0.0
	actor.magic_resist = 0.0
	actor.state = &"chase"
	return actor

func context(identifier: String) -> Dictionary:
	return {"root_event_id":identifier,"attack_id":identifier,"original_basic":true,"equipment_eligible":true,"proc_depth":0}

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_class_relics"):
		push_error("Refusing non-test profile; use test_class_relics in profile path")
		quit(2)
		return
	resolver = load("res://scripts/combat/stat_resolver.gd")
	room_scene = load("res://scenes/room.tscn")
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated run starts")
	if game.run == null:
		quit(1)
		return
	_test_catalog()
	_test_breaker()
	_test_ranger()
	_test_resonator()
	_test_native_statuses()
	_test_native_production_hits()
	_test_budget_and_production_dispatch()
	if is_instance_valid(room):
		room.free()
	print("CLASS RELICS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_catalog() -> void:
	var names: Dictionary = {}
	for hero: String in ["CH01","CH02","CH03"]:
		for id: String in ["RL01","RL02","RL03"]:
			var first: Dictionary = Relics.display(hero,id)
			var second: Dictionary = Relics.display(hero,id,2)
			check(not names.has(first.name), "nine hero relic names stay distinct")
			names[first.name] = true
			check(not first.description.is_empty() and ResourceLoader.exists(first.art), "relic has real description and art")
			check(first.description != second.description and second.name.ends_with(" II"), "rank II publishes its real benefit")
	check(Relics.display("CH01","split").id == "RL01", "legacy save aliases remain valid")

func _test_breaker() -> void:
	fixture("CH01")
	var main: Node2D = target(Vector2(480,350))
	var cleave: Node2D = target(Vector2(530,370))
	var behind: Node2D = target(Vector2(360,350))
	var distant: Node2D = target(Vector2(660,350))
	var power: float = room.player.attack_power()
	check(Relics.apply_reserved(room,{"split":0.4},context("breaker:1"),main.position,main,Vector2.RIGHT), "breaker cleave applies")
	check(room.projectiles.get_child_count() == 0, "melee relic never creates bullets")
	check(is_equal_approx(10000.0-cleave.health.current,power*0.4), "cleave deals real physical damage")
	check(main.health.current == 10000.0 and behind.health.current == 10000.0 and distant.health.current == 10000.0, "cleave respects original exclusion, cone and melee distance")
	var before: float = cleave.health.current
	check(not Relics.apply_reserved(room,{"split":0.4},context("breaker:1"),main.position,main,Vector2.RIGHT) and cleave.health.current == before, "one attack root cannot dispatch cleave twice")
	Relics.apply_reserved(room,{"arc":0.35},context("breaker:2"),main.position,main,Vector2.RIGHT)
	check(is_equal_approx(game.run.shield,game.run.max_hp*0.12) and room.player.break_stacks == 1, "breaker counterweight grants meaningful shield and Momentum")
	Relics.apply_reserved(room,{"arc":0.525},context("breaker:3"),main.position,main,Vector2.RIGHT)
	check(is_equal_approx(game.run.shield,game.run.max_hp*0.18) and room.player.break_stacks == 2, "rank II increases actual shield")
	var guard_before: float = game.run.shield
	var derived: Dictionary = context("breaker:derived")
	derived.equipment_eligible = false
	derived.proc_depth = 1
	check(not Relics.apply_reserved(room,{"arc":0.35},derived,main.position,main,Vector2.RIGHT) and game.run.shield == guard_before, "derived damage cannot re-trigger relics")
	check(cleave.last_damage_context.damage_type == "physical" and not cleave.last_damage_context.equipment_eligible and cleave.last_damage_context.proc_depth == 1, "cleave retains typed non-recursive damage context")

func _test_ranger() -> void:
	fixture("CH02")
	var main: Node2D = target(Vector2(480,350))
	var secondary: Node2D = target(Vector2(540,380))
	Relics.apply_reserved(room,{"split":0.4},context("ranger:1"),main.position,main,Vector2.RIGHT)
	check(room.projectiles.get_child_count() == 2, "ranger alone emits two split bullets")
	var child: Node2D = room.projectiles.get_child(0)
	check(child.trigger_budget == 0 and child.ignored_enemy == main.get_instance_id(), "split bullet excludes initial victim and cannot reserve another proc")
	child.hit(secondary)
	check(is_equal_approx(10000.0-secondary.health.current,room.player.attack_power()*0.4), "split bullet hits through production projectile pipeline")
	check(secondary.last_damage_context.damage_type == "physical" and not secondary.last_damage_context.equipment_eligible, "bullet hit preserves relic damage context")
	var before: float = main.health.current
	Relics.apply_reserved(room,{"arc":0.35},context("ranger:2"),main.position,main,Vector2.RIGHT)
	check(room.player.class_marks.has(main.get_instance_id()), "ranger relic applies actual consumable class mark")
	check(is_equal_approx(before-main.health.current,room.player.attack_power()*0.35), "ranger mark adds real physical damage")
	var original: Dictionary = context("ranger:cash")
	original["H"] = room.player.attack_power()
	check(room.player.class_modify_hit_amount(main,10.0,&"secondary",original) > 10.0 and room.player.class_marks.is_empty(), "marked enemy supports class right-button cash-out")
	before = main.health.current
	Relics.apply_reserved(room,{"arc":0.525},context("ranger:3"),main.position,main,Vector2.RIGHT)
	check(is_equal_approx(before-main.health.current,room.player.attack_power()*0.525), "ranger rank II damage rises 50 percent")

func _test_resonator() -> void:
	fixture("CH03")
	var main: Node2D = target(Vector2(490,350))
	var echo: Node2D = target(Vector2(530,365))
	var node: Node2D = room.add_deployment("node",Vector2(470,380),{"owner_player":room.player,"lifetime":14.0})
	node.advance(0.35)
	var power: float = room.player.stat("ability_power",28.0)
	Relics.apply_reserved(room,{"split":0.4},context("mage:1"),main.position,main,Vector2.RIGHT)
	check(room.projectiles.get_child_count() == 0 and is_equal_approx(10000.0-echo.health.current,power*0.4), "mage echoes magic without gun bullets")
	check(echo.last_damage_context.damage_type == "magic" and not echo.last_damage_context.equipment_eligible, "mage echo uses magic defense and no equipment recursion")
	var before: float = main.health.current
	Relics.apply_reserved(room,{"arc":0.35},context("mage:2"),main.position,main,Vector2.RIGHT)
	check(is_equal_approx(game.run.resource,53.0) and node.resonance_charge == 1, "mage relic restores actual mana and charges real node")
	check(is_equal_approx(before-main.health.current,power*0.35), "mage echo scales with ability power")
	Relics.apply_reserved(room,{"arc":0.525},context("mage:3"),main.position,main,Vector2.RIGHT)
	check(is_equal_approx(game.run.resource,57.5) and node.resonance_charge == 3, "rank II adds mana and two node charges")

func _test_native_statuses() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		fixture(hero)
		var enemy: Node2D = target(Vector2(490,350))
		var id: String = Relics.native_status(hero)
		var power: float = room.player.stat("ability_power",28.0) if hero == "CH03" else room.player.attack_power()
		check(enemy.apply_status(id,Relics.native_status_power(hero,power),Relics.native_status_duration(hero)), "class-specific native state applies to actual enemy")
		check(enemy.status.has(id), "actual native state is retained")
		enemy.tick_statuses(1.0)
		var first_damage: float = 10000.0-enemy.health.current
		check(first_damage > 0.0 and enemy.last_damage_context.damage_type == ("magic" if hero == "CH03" else "physical"), "native DOT has class-appropriate damage type")
		enemy.status.states.clear()
		enemy.health.reset(10000.0)
		enemy.apply_status(id,Relics.native_status_power(hero,power,2),Relics.native_status_duration(hero,2))
		enemy.tick_statuses(1.0)
		check(is_equal_approx(10000.0-enemy.health.current,first_damage*1.5), "rank II native DOT actually increases 50 percent")

func _test_budget_and_production_dispatch() -> void:
	fixture("CH01")
	game.run.relics.assign(["split","ember","arc"])
	var original: Dictionary = context("budget:1")
	var reserved: Dictionary = room._prepare_relics(original,4,true)
	check(reserved.size() == 3 and room.player.loadout.effects.root_usage("budget:1").packets <= 4, "three class relics reserve the shared root budget")
	room._prepare_relics(original,4,true)
	check(room.player.loadout.effects.root_usage("budget:1").packets == 3, "idempotent reservation does not consume additional budget")
	var main: Node2D = target(Vector2(480,350))
	var nearby: Node2D = target(Vector2(520,370))
	room._emit_reserved_relics(reserved,original,main.position,main,Vector2.RIGHT)
	check(room.projectiles.get_child_count() == 0 and nearby.health.current < 10000.0 and game.run.shield > 0.0, "production room dispatches class relics instead of universal bullets")
	var health_before: float = nearby.health.current
	var stacks_before: int = room.player.break_stacks
	room._emit_reserved_relics(reserved,original,main.position,main,Vector2.RIGHT)
	check(nearby.health.current == health_before and room.player.break_stacks == stacks_before and room.projectiles.get_child_count() == 0, "production room cannot fall back to bullets on repeated root")
	for index in range(4):
		room.player.loadout.effects.reserve_native("budget:full","existing:%d" % index)
	check(room._prepare_relics(context("budget:full"),4,true).is_empty(), "exhausted shared four-packet budget suppresses all relics")

func _test_native_production_hits() -> void:
	for hero: String in ["CH01","CH02","CH03"]:
		fixture(hero,2)
		game.run.relics.assign(["ember"])
		var enemy: Node2D = target(Vector2(490,350))
		if hero == "CH01":
			room.strike_area(room.player.position,105.0,1.0,&"primary","",0.0,Vector2.RIGHT,100.0,true,context("production:"+hero))
		else:
			var projectile: Node2D = room.spawn_projectile(room.player.position,Vector2.RIGHT,1.0,&"primary")
			projectile.hit(enemy)
		var id: String = Relics.native_status(hero)
		check(enemy.status.has(id), "production original hit selects the correct hero relic state")
		var power: float = room.player.stat("ability_power",28.0) if hero == "CH03" else room.player.attack_power()
		check(is_equal_approx(float(enemy.status.states.get(id,{}).get("power",0.0)),power*1.5), "production rank II status uses the published AD/AP scaling")
		check(is_equal_approx(float(enemy.status.states.get(id,{}).get("remaining",0.0)),Relics.native_status_duration(hero,2)), "production state lifetime matches relic text")
