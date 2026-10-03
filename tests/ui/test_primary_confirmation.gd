extends Node
## Real room/player/projectile damage paths, deterministic explicit advances.
## Fixture-only health/shields isolate confirmation semantics; no gameplay tuning.
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
var room: RoomController
var node: Node2D
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PRIMARY CONFIRMATION: " + message)

func fixture(hero: String) -> void:
	if is_instance_valid(room): room.free()
	Game.run.hero_id = hero
	Game.run.level = 8
	Game.run.stats = Resolver.resolve(hero, 8, {}, {})
	Game.run.stats["crit_chance"] = 0.0
	Game.run.stats["true_damage_bonus"] = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 20.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true
	for actor in room.enemies.get_children(): actor.free()
	for projectile in room.projectiles.get_children(): projectile.free()
	room.player.position = Vector2(1100, 750)
	room.player.aim_direction = Vector2.RIGHT
	room.combat_audio.audible = false
	room.combat_audio.stop_all()
	room.combat_audio.set_process(false)
	node = null
	if hero == "CH02":
		room.player.walk_distance = 240.0
		room.player.cooldowns.q = 3.0
	elif hero == "CH03":
		# Prime the fourth-hit boundary to expose both free mana and false charge.
		room.player.passive_count = 3
		node = room.add_deployment("node", room.player.position + Vector2(80, 30), {"damage":1.0, "power":20.0, "radius":160.0, "health":35.0, "lifetime":14.0, "owner_player":room.player})
		node.advance(0.35)

func target_at(offset: Vector2 = Vector2(60, 0)) -> EnemyActor:
	var target: EnemyActor = room.spawn_enemy(room.player.position + offset, "M01", 1)
	target.health.reset(10000.0)
	target.reward_enabled = false
	target.training_ai_disabled = true
	return target

func class_state() -> Dictionary:
	return {"resource":Game.run.resource, "count":room.player.passive_count,
		"break":room.player.break_stacks, "walk":room.player.walk_distance,
		"marks":room.player.class_marks.size(), "q":room.player.cooldowns.q,
		"charge":node.resonance_charge if is_instance_valid(node) else -1}

func primary() -> void:
	room.player.shot_cooldown = 0.0
	check(room.player.fire(Vector2.RIGHT), room.player.hero_id() + " starts real basic attack")
	if room.player.hero_id() == "CH01":
		room.player._tick_attack(0.13)
	else:
		# Exercise projectile collision and resolve_weapon_hit, not on_primary_hit.
		for projectile in room.projectiles.get_children():
			if projectile.source == &"primary" and not projectile.consumed:
				projectile._physics_process(0.20)

func check_class_proc(hero: String, before: Dictionary, label: String) -> void:
	if hero == "CH01":
		check(room.player.break_stacks == 1 and room.player.passive_count == 1 and is_equal_approx(Game.run.resource, float(before.resource) + 8.0), label + " grants exactly one hammer passive")
	elif hero == "CH02":
		check(room.player.walk_distance == 0.0 and is_equal_approx(room.player.cooldowns.q, 2.5) and is_equal_approx(Game.run.resource, float(before.resource) + 10.0), label + " spends ranger readiness once, even on a kill")
	else:
		check(room.player.passive_count == 0 and room.player.passive_cooldown == 2.0 and is_equal_approx(Game.run.resource, float(before.resource) + 6.0), label + " completes exactly one fourth hit")
		check(node.resonance_charge == 1, label + " charges one node from the confirmed fourth hit")

func confirmation_cases() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		for mode: String in ["health", "shield_only", "shield_break", "lethal", "immune", "zero"]:
			fixture(hero)
			var target := target_at()
			if mode == "shield_only": target.status.grant_guard(1000.0, 10.0, "test", target.health.maximum)
			if mode == "shield_break": target.status.grant_guard(1.0, 10.0, "test", target.health.maximum)
			if mode == "lethal": target.health.reset(1.0)
			if mode == "immune": target.apply_status("invulnerable", 1.0, 10.0)
			if mode == "zero": Game.run.stats.attack = 0.0
			var before := class_state()
			var hp: float = target.health.current
			var shield: float = target.status.shield()
			primary()
			var label: String = hero + " " + mode
			if mode in ["immune", "zero"]:
				check(target.health.current == hp and target.status.shield() == shield, label + " consumes no HP/shield")
				check(class_state() == before, label + " grants no class passive, mana, readiness or node energy")
			else:
				check_class_proc(hero, before, label)
				if mode == "shield_only": check(target.health.current == hp and target.status.shield() < shield, label + " is a pure absorbed shield hit")
				elif mode == "shield_break": check(target.status.shield() == 0.0 and target.health.current < hp, label + " breaks the shield")
				elif mode == "lethal": check(not target.is_alive(), label + " is a genuine killing blow")
				else: check(target.health.current < hp, label + " deals direct health damage")

func hammer_multi_target() -> void:
	fixture("CH01")
	var immune := target_at(Vector2(35, 0))
	immune.apply_status("invulnerable", 1.0, 10.0)
	var first := target_at(Vector2(60, -15))
	var second := target_at(Vector2(70, 16))
	var before := class_state()
	primary()
	check(immune.health.current == immune.health.maximum and first.health.current < first.health.maximum and second.health.current < second.health.maximum, "one hammer swing skips immunity and damages both valid recipients")
	check_class_proc("CH01", before, "one swing / two confirmed recipients")

func derived_and_shock_cases() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		fixture(hero)
		var target := target_at()
		var before := class_state()
		var child := room.spawn_projectile(room.player.position, Vector2.RIGHT, 8.0, &"child")
		child._physics_process(0.20)
		room.resolve_derived_hit(target, 8.0, &"node", Vector2.RIGHT)
		target.apply_status("burn", 10.0, 3.0)
		target.tick_statuses(1.0)
		check(target.health.current < target.health.maximum and class_state() == before, hero + " child/node/DOT damage cannot trigger an original-basic passive")
		# A zero original packet can still consume an old Shock. That secondary
		# damage must not retroactively qualify the original basic for a passive.
		target.apply_status("shock", 40.0, 3.0)
		Game.run.stats.attack = 0.0
		var hp: float = target.health.current
		primary()
		check(target.health.current < hp and class_state() == before, hero + " shock follow-up does not turn a zero basic into a confirmed basic")

func area_return_contract() -> void:
	fixture("CH01")
	var target := target_at()
	target.apply_status("invulnerable", 1.0, 10.0)
	var geometric: Array = room.strike_area(room.player.position, 105.0, 10.0, &"q")
	var confirmed: Array = room.strike_area(room.player.position, 105.0, 10.0, &"primary", "", 0.0, Vector2.RIGHT, 100.0, true, {}, true)
	check(geometric.size() == 1 and confirmed.is_empty(), "existing area callers keep geometric results; confirmed-only basic excludes immunity")
	target.status.states.clear()
	target.status.grant_guard(1000.0, 10.0, "test", target.health.maximum)
	confirmed = room.strike_area(room.player.position, 105.0, 10.0, &"primary", "", 0.0, Vector2.RIGHT, 100.0, true, {}, true)
	check(confirmed.size() == 1 and confirmed[0] == target, "confirmed-only area includes a pure shield recipient")

func _run() -> void:
	if not Game.profile_path.contains("test_primary_confirmation"):
		push_error("Requires isolated test_primary_confirmation profile")
		get_tree().quit(2)
		return
	check(Game.new_profile() and Game.start_run(), "isolated test profile starts")
	Game.profile.settings["muted"] = true
	confirmation_cases()
	hammer_multi_target()
	derived_and_shock_cases()
	area_return_contract()
	if is_instance_valid(room):
		await room.combat_audio.wait_for_cleanup()
		room.free()
	print("PRIMARY CONFIRMATION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
