extends SceneTree
var game: Node
var room: Node2D
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HIT CHAIN: " + message)

func fixture(hero: String) -> void:
	if is_instance_valid(room): room.free()
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = load(AssetCatalog.resolve("res://scripts/domain/combat/stat_resolver.gd")).resolve(hero, 8, {}, {})
	game.run.stats.crit_chance = 0.0
	game.run.loadout_snapshot.clear()
	game.run.relics.clear()
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.stop_all()

func dummy(offset: Vector2 = Vector2(70, 0)) -> Node2D:
	var target: Node2D = room.spawn_enemy(room.player.position + offset, "M01", 1)
	target.health.reset(100000.0)
	target.armor = 0.0
	target.magic_resist = 0.0
	target.reward_enabled = false
	target.training_ai_disabled = true
	return target

func packet(id: String, root_id: String = "") -> Dictionary:
	return {"attack_id":id, "root_event_id":id if root_id.is_empty() else root_id, "original_basic":false, "equipment_eligible":true, "proc_depth":0, "power":20.0}

func hit(target: Node2D, id: String, root_id: String = "") -> bool:
	return room.resolve_direct_hit(target, 20.0, &"q", "", 0.0, Vector2.RIGHT, packet(id, root_id))

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_hit_chain"):
		quit(2)
		return
	check(game.new_profile() and game.start_run(), "isolated run starts")
	for hero: String in ["CH01", "CH02", "CH03"]:
		fixture(hero)
		var target := dummy()
		for n in range(1, 101):
			var before: float = target.health.current
			check(hit(target, "ramp:" + str(n)), hero + " confirmed hit")
			check(absf(before - target.health.current - 20.0 * (1.0 + (n - 1) * .005)) < .02, hero + " actual progressive damage at x" + str(n))
			var state: Dictionary = room.player.hit_chain.snapshot()
			check(int(state.count) == n and is_equal_approx(float(state.bonus), n * .005), hero + " authoritative count and bonus")
		check(int(room.player.hit_chain.snapshot().tier) == 5, hero + " x100 tier")
		for n in range(101, 401): hit(target, "ramp:" + str(n))
		check(room.player.hit_chain.count == 100 and room.player.hit_chain.packets.size() == 256, hero + " capped count and bounded history")
		room.player.hit_chain.tick(3.0)
		paused = true
		room.player.hit_chain.tick(20.0)
		check(is_equal_approx(room.player.hit_chain.remaining, 1.0), "pause freezes chain")
		paused = false
		room.player.hit_chain.tick(1.0)
		check(room.player.hit_chain.count == 0 and float(room.player.hit_chain.snapshot().bonus) == 0.0, "expiry removes actual buff")
		var before: float = target.health.current
		hit(target, "after_expiry")
		check(absf(before - target.health.current - 20.0) < .02, "first new hit has no previous buff")
	_test_original_boundaries()
	_test_native_attacks()
	_test_native_skills()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("HIT CHAIN: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_original_boundaries() -> void:
	fixture("CH01")
	var a := dummy()
	var b := dummy(Vector2(70, 30))
	hit(a, "first")
	var before_a: float = a.health.current
	var before_b: float = b.health.current
	room.strike_area(room.player.position, 105.0, 20.0, &"q", "", 0.0, Vector2.RIGHT, 100.0, true, packet("aoe"))
	check(room.player.hit_chain.count == 2, "multi-target area counts once")
	check(absf(before_a - a.health.current - 20.1) < .02 and absf(before_b - b.health.current - 20.1) < .02, "same area has identical pre-contact buff for every victim")
	room.player.hit_chain.tick(2.0)
	hit(b, "aoe")
	check(room.player.hit_chain.count == 2 and is_equal_approx(room.player.hit_chain.remaining, 2.0), "duplicate packet cannot count or refresh timer")
	hit(a, "burst:0", "burst")
	hit(a, "burst:1", "burst")
	check(room.player.hit_chain.count == 4, "separate released rounds sharing a cast root count separately")
	a.apply_status("invulnerable", 1.0, 1.0)
	check(not hit(a, "immune") and room.player.hit_chain.count == 4, "immune hits cannot build combo")
	a.status.states.erase("invulnerable")
	room.resolve_direct_hit(a, 0.0, &"q", "", 0.0, Vector2.RIGHT, packet("zero"))
	check(room.player.hit_chain.count == 4, "zero damage does not count")
	for source: StringName in [&"burn", &"shock", &"equipment", &"node", &"field", &"child", &"node_detonation"]:
		room.resolve_derived_hit(a, 10.0, source, Vector2.RIGHT, packet("derived:" + str(source)))
		check(room.player.hit_chain.count == 4, "derived " + str(source) + " cannot count")
	a.status.grant_guard(100.0, 10.0, "test", a.health.maximum)
	hit(a, "shield")
	check(room.player.hit_chain.count == 5, "shield-only contact counts")
	game.run.stats.true_damage_bonus = 7.0
	hit(b, "true_followup")
	check(room.player.hit_chain.count == 6, "equipment true damage cannot add another count")
	var snapshot: Dictionary = room.expedition_runtime_snapshot()
	check(not JSON.stringify(snapshot).contains("hit_chain"), "transient chain never enters persisted checkpoint")
	game.run.hp = 0.0
	check(int(room.player.hit_chain.snapshot().count) == 0, "death clears chain even before another tick")
	fixture("CH01")
	check(room.player.hit_chain.count == 0, "new room begins without carried combo")

func _test_native_attacks() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		fixture(hero)
		var a := dummy()
		var b := dummy(Vector2(95, 0))
		check(room.player.fire(Vector2.RIGHT), hero + " public basic release accepted")
		if hero == "CH01": room.player._tick_attack(.13)
		else:
			var bolt: Node2D = room.projectiles.get_child(0)
			bolt.pierce_remaining = 1
			bolt._physics_process(.2)
		check(a.health.current < a.health.maximum and b.health.current < b.health.maximum, hero + " real area/pierce reaches both targets")
		check(room.player.hit_chain.count == 1, hero + " native basic counts once")

func _test_native_skills() -> void:
	for slot: String in ["q","ultimate"]:
		fixture("CH02")
		var a := dummy()
		check(room.player.cast_skill(slot,a.position), "public gunner " + slot + " commits")
		room.player.abilities.tick(1.3)
		var expected: int = 3 if slot == "q" else 4
		check(room.projectiles.get_child_count() == expected, "native gunner emits independent rounds")
		for bolt: Node in room.projectiles.get_children(): bolt._physics_process(.5)
		check(room.player.hit_chain.count == expected, "native gunner " + slot + " counts each confirmed independent round")
	fixture("CH03")
	var a := dummy()
	var b := dummy(Vector2(95,0))
	check(room.player.cast_skill("q",a.position), "public mage Q commits")
	room.player.abilities.tick(1.0)
	for bolt: Node in room.projectiles.get_children(): bolt._physics_process(.3)
	check(a.health.current < a.health.maximum and b.health.current < b.health.maximum and room.player.hit_chain.count == 1, "native mage Q explosion damages both targets but counts once")
	check(room.player.cast_skill("ultimate",a.position), "public mage R commits")
	room.player.abilities.tick(1.0)
	check(room.player.hit_chain.count == 2, "native domain original placement adds one")
	var field: Node2D
	for child: Node in room.get_children():
		if child.has_method("advance") and child.get("kind") == "field": field = child
	check(is_instance_valid(field), "actual native domain deployment exists")
	var before: float = a.health.current
	if is_instance_valid(field): field.advance(3.0)
	check(a.health.current < before and room.player.hit_chain.count == 2, "native domain deals periodic damage without farming combo")
