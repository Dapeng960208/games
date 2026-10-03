extends SceneTree
## Rule acceptance through real player/projectile/room/deployment/HUD APIs.
## Stationary M01 targets and manual ticks isolate the rules. The shot helper
## resets only the weapon cadence, never the passive ICD. This is not a natural
## combat/balance playthrough, graphics review, or an audio listening assessment.
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const PLAYER_AT := Vector2(430, 350)
const TARGET_AT := Vector2(550, 350)
var game: Node
var room: Node2D
var room_scene: PackedScene
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RESONANCE LOOP FAIL: " + label)

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_resonance_loop"):
		push_error("Refusing resonance tests without isolated test_resonance_loop profile")
		quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		Input.action_release(action)
	check(game.new_profile() and game.start_run(), "isolated real run starts")
	if game.run == null:
		quit(1)
		return
	room_scene = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn"))
	_test_four_confirmed_hits_and_icd()
	_test_full_and_two_node_selection()
	_test_rejected_candidates()
	_test_no_node_and_confirmed_gate()
	_test_derived_damage()
	_test_hud_capacity()
	_test_badge_conditions()
	_test_f_damage_and_radius()
	_test_reduced_fx()
	check(await room.combat_audio.wait_for_cleanup(), "audio objects cleaned before shutdown")
	room.free()
	print("RESONANCE LOOP: %d checks, %d failures (fixed targets/manual ticks; weapon cadence accelerated, passive ICD intact; no balance/visual/listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _fixture(reduced_fx: bool = false) -> void:
	if is_instance_valid(room):
		room.combat_audio.stop_all()
		room.free()
	game.run.hero_id = "CH03"
	game.run.level = 8
	game.run.stats = Resolver.resolve("CH03", 8, {}, {})
	game.run.stats["crit_chance"] = 0.0
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 20.0
	game.run.shield = 0.0
	game.run.relics.clear()
	game.profile.settings.merge({"muted":false, "sfx_muted":false, "master_volume":1.0, "sfx_volume":1.0, "reduced_fx":reduced_fx}, true)
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	room.obstructions.clear()
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	room.player.position = PLAYER_AT
	room.player.aim_direction = Vector2.RIGHT
	# Manual player ticks below measure ICD alone, without automatic mana regen.
	room.player.resource_delay = 1000.0

func _dummy(at: Vector2 = TARGET_AT) -> Node2D:
	var target: Node2D = room.spawn_enemy(at, "M01")
	target.health.reset(10000.0)
	target.state = &"chase"
	return target

func _node(at: Vector2, unfolded: bool = true) -> Node2D:
	# The real deployment factory is used, with a fixed power snapshot and legal
	# room coordinates so selection/radius tests do not depend on placement UI.
	var node: Node2D = room.add_deployment("node", at, {"damage":6.0, "power":40.0, "radius":160.0, "lifetime":14.0, "owner_player":room.player, "damage_type":"magic", "attacker_stats":game.run.stats.duplicate(true)})
	if unfolded: node.advance(node.setup_time)
	return node

func _step_projectiles(duration: float = 0.4) -> void:
	for _step: int in ceili(duration / 0.01):
		for projectile: Node2D in room.projectiles.get_children():
			if not projectile.consumed and not projectile.is_queued_for_deletion():
				projectile._physics_process(0.01)
	for projectile: Node2D in room.projectiles.get_children():
		if projectile.is_queued_for_deletion(): projectile.free()

func _fire(target: Node2D) -> bool:
	var before: float = target.health.current + target.status.shield()
	# Intentional fixture acceleration: passive_cooldown is never overwritten.
	room.player.shot_cooldown = 0.0
	var direction: Vector2 = (target.position - room.player.position).normalized()
	room.player.aim_direction = direction
	check(room.player.fire(direction), "real basic projectile is accepted")
	_step_projectiles()
	return target.health.current + target.status.shield() < before

func _four_hits(target: Node2D) -> void:
	for index: int in 4:
		check(_fire(target), "actual basic damage confirmed at beat %d" % (index + 1))

func _tick_player(delta: float) -> void:
	room.input_blocked = true
	room.player._physics_process(delta)
	room.input_blocked = false

func _test_four_confirmed_hits_and_icd() -> void:
	_fixture()
	var target: Node2D = _dummy()
	var near: Node2D = _node(TARGET_AT + Vector2(30, 30))
	var far: Node2D = _node(TARGET_AT + Vector2(90, 30))
	for beat: int in 3:
		check(_fire(target), "first three basics cause real damage")
		check(room.player.passive_count == beat + 1 and near.resonance_charge == 0 and far.resonance_charge == 0, "only confirmed beat count advances before fourth hit")
	check(is_equal_approx(game.run.resource, 20.0), "first three beats do not refund mana")
	check(_fire(target), "fourth projectile causes damage")
	check(near.resonance_charge == 1 and far.resonance_charge == 0, "fourth confirmed hit charges only the nearest of two nodes")
	check(room.player.passive_count == 0 and is_equal_approx(room.player.passive_cooldown, 2.0), "successful four-beat loop commits the two-second ICD")
	check(is_equal_approx(game.run.resource, 26.0), "fourth hit restores six mana")
	check(near.charge_flash > 0.0 and near.pulse == 0.0, "fourth hit uses intake flash without cannon fire pulse")
	_four_hits(target)
	check(near.resonance_charge == 1 and far.resonance_charge == 0 and room.player.passive_count == 0, "confirmed hits during ICD cannot charge or queue passive beats")
	check(is_equal_approx(game.run.resource, 26.0), "ICD blocks repeated mana refunds")
	_tick_player(1.99)
	check(_fire(target) and near.resonance_charge == 1 and room.player.passive_count == 0, "a hit just before two seconds is still gated")
	_tick_player(0.02)
	_four_hits(target)
	check(near.resonance_charge == 2 and far.resonance_charge == 0, "four new confirmed hits after actual ICD tick charge one node")
	check(is_equal_approx(game.run.resource, 32.0), "only the next completed loop refunds again")

func _test_full_and_two_node_selection() -> void:
	_fixture()
	var target: Node2D = _dummy()
	var full: Node2D = _node(TARGET_AT + Vector2(25, 30))
	var available: Node2D = _node(TARGET_AT + Vector2(95, 30))
	check(full.charge_node(3), "nearest node reaches its real capacity")
	_four_hits(target)
	check(full.resonance_charge == 3 and available.resonance_charge == 1, "full nearest node is skipped in favor of the next eligible node")
	_fixture()
	target = _dummy()
	var boundary: Node2D = _node(TARGET_AT + Vector2(160, 0))
	_four_hits(target)
	check(boundary.resonance_charge == 1, "exact target-to-node reach of 160 is included")
	check(room.player.position.distance_to(boundary.position) > 260.0, "charge reach is centered on hit target rather than player F range")

func _test_rejected_candidates() -> void:
	for scenario: String in ["unfolding", "dead", "foreign_owner", "wall", "range"]:
		_fixture()
		var target: Node2D = _dummy()
		var node: Node2D = _node(TARGET_AT + Vector2(100, 0), scenario != "unfolding")
		match scenario:
			"dead":
				check(node.receive_damage(node.health + 1.0), "test node is destroyed through its actual damage API")
			"foreign_owner":
				var foreign: Node2D = Node2D.new()
				room.add_child(foreign)
				node.owner_player = foreign
			"wall":
				room.obstructions.assign([Rect2(595, 320, 20, 60)])
				check(room.has_line_of_sight(PLAYER_AT, TARGET_AT) and not room.has_line_of_sight(TARGET_AT, node.position), "wall blocks target-to-node path without blocking original basic")
			"range": node.position = TARGET_AT + Vector2(160.1, 0)
		_four_hits(target)
		check(node.resonance_charge == 0, "fourth hit cannot charge candidate: " + scenario)
		check(is_equal_approx(game.run.resource, 26.0) and room.player.passive_cooldown > 0.0, "rejected candidate preserves ordinary fourth-hit mana and ICD: " + scenario)

func _test_no_node_and_confirmed_gate() -> void:
	_fixture()
	var target: Node2D = _dummy()
	_four_hits(target)
	check(room.player.resonance_nodes().is_empty() and is_equal_approx(game.run.resource, 26.0), "field without deployed nodes still grants four-beat mana refund")
	_fixture()
	target = _dummy()
	var node: Node2D = _node(TARGET_AT + Vector2(30, 30))
	target.status.apply("invulnerable", 0.0, 5.0)
	for _beat: int in 4: check(not _fire(target), "immune target rejects actual projectile damage")
	check(room.player.passive_count == 0 and room.player.passive_cooldown == 0.0 and node.resonance_charge == 0, "projectile contact without HP/shield loss never advances four beats")
	check(is_equal_approx(game.run.resource, 20.0), "immune contact cannot manufacture mana refund")

func _test_derived_damage() -> void:
	_fixture()
	var target: Node2D = _dummy()
	var node: Node2D = _node(Vector2(480, 380))
	for _beat: int in 3: check(_fire(target), "three real basics prime the passive without synthetic counter injection")
	var before: float = target.health.current
	check(is_instance_valid(room.spawn_projectile(PLAYER_AT, Vector2.RIGHT, 20.0, &"child")), "real child projectile created")
	_step_projectiles()
	check(target.health.current < before and str(target.last_damage_context.damage_source) == "child", "child projectile deals derived damage")
	check(room.player.passive_count == 3 and node.resonance_charge == 0, "child damage cannot complete the fourth beat")
	before = target.health.current
	node.advance(1.2)
	_step_projectiles()
	check(target.health.current < before and str(target.last_damage_context.damage_source) == "node", "node's scheduled real bolt hits target")
	check(room.player.passive_count == 3 and node.resonance_charge == 0, "node bolt cannot complete its own charging loop")
	var field: Node2D = room.add_deployment("field", TARGET_AT, {"damage":20.0, "power":20.0, "radius":100.0, "lifetime":5.0, "owner_player":room.player, "damage_type":"magic", "attacker_stats":game.run.stats.duplicate(true)})
	before = target.health.current
	field.advance(1.0)
	check(target.health.current < before and str(target.last_damage_context.damage_source) == "field", "real field tick deals derived damage")
	check(room.player.passive_count == 3 and node.resonance_charge == 0 and is_equal_approx(game.run.resource, 20.0), "field damage neither charges nor refunds mana")
	check(not bool(target.last_damage_context.original_basic) and not bool(target.last_damage_context.equipment_eligible), "derived field retains non-basic non-equipment attribution")
	check(_fire(target) and node.resonance_charge == 1 and is_equal_approx(game.run.resource, 26.0), "only the subsequent real fourth basic closes the primed loop")

func _test_hud_capacity() -> void:
	_fixture()
	var hud: Control = load(AssetCatalog.resolve("res://scenes/presentation/hud.tscn")).instantiate()
	hud.room = room
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(hud)
	hud._update_identity_and_circuit()
	check(room.player.class_status().max == 3 and hud.class_bar.max_value == 3.0, "empty field retains minimum class meter capacity three")
	var first: Node2D = _node(Vector2(480, 350))
	check(first.charge_node(3), "first node fills through charging API")
	hud._update_identity_and_circuit()
	check(hud.class_label.text.replace(" ","").contains("3/3") and hud.class_bar.value == 3.0 and hud.class_bar.max_value == 3.0, "actual HUD renders one full node as 3 / 3")
	var second: Node2D = _node(Vector2(520, 390))
	hud._update_identity_and_circuit()
	check(hud.class_label.text.replace(" ","").contains("3/6") and hud.class_bar.max_value == 6.0, "second active node expands actual HUD capacity to six")
	check(second.charge_node(3), "second node fills independently")
	hud._update_identity_and_circuit()
	check(hud.class_label.text.replace(" ","").contains("6/6") and hud.class_bar.value == 6.0, "two full nodes render 6 / 6")
	second.receive_damage(second.health + 1.0)
	hud._update_identity_and_circuit()
	check(hud.class_label.text.replace(" ","").contains("3/3") and hud.class_bar.max_value == 3.0, "destroying a node contracts HUD capacity immediately")
	hud.free()

func _test_badge_conditions() -> void:
	_fixture()
	game.run.resource = 100.0
	var node: Node2D = _node(PLAYER_AT + Vector2(260, 0))
	var state: Dictionary = node.resonance_readout()
	check(state.connected and state.available and not state.full and state.radius == 100.0, "uncharged node at exact F range is connected and usable")
	node.position.x += 0.1
	state = node.resonance_readout()
	check(not state.connected and not state.available, "F badge rejects node beyond 260")
	node.position.x -= 0.1
	room.obstructions.assign([Rect2(570, 320, 20, 60)])
	check(not node.resonance_readout().available and not node.resonance_readout().connected, "F badge obeys real player-to-node wall occlusion")
	room.obstructions.clear()
	room.player.cooldowns.f = 0.01
	check(not node.resonance_readout().available, "positive F cooldown dims availability")
	room.player.cooldowns.f = 0.0
	var cost: float = room.player.skill_definition("f").cost
	game.run.resource = cost - 0.01
	check(not node.resonance_readout().available, "resource below actual effective F cost dims availability")
	game.run.resource = cost
	check(node.resonance_readout().available, "resource exactly equal to F cost is usable")
	game.run.level = 2
	check(not node.resonance_readout().available, "F badge stays unavailable before unlock")
	game.run.level = 3
	check(node.resonance_readout().available, "F badge becomes available at level three")
	room.player.dash_remaining = 0.01
	check(not node.resonance_readout().available, "dash blocks F badge readiness")
	room.player.dash_remaining = 0.0
	game.run.resource = 100.0
	check(room.player.cast_skill("q", TARGET_AT), "real Q begins competing cast")
	check(not node.resonance_readout().available, "active skill blocks F badge readiness")
	room.player.abilities.cancel()
	check(node.charge_node(1) and node.resonance_readout().radius == 120.0 and not node.resonance_readout().full, "one stored charge previews a 120 radius")
	check(node.charge_node(2) and node.resonance_readout().radius == 160.0 and node.resonance_readout().full, "full charge previews a 160 radius")
	node.receive_damage(node.health + 1.0)
	check(not node.resonance_readout().connected and not node.resonance_readout().available, "destroyed node loses F badge eligibility immediately")

func _f_sample(charge: int, reduced_fx: bool = false) -> Dictionary:
	_fixture(reduced_fx)
	game.run.resource = 100.0
	var node: Node2D = _node(Vector2(620, 350))
	if charge > 0: check(node.charge_node(charge), "F sample stores requested charge %d" % charge)
	# Neither victim is inside player's own 140-radius F pulse. The near victim
	# is in every node blast; the rim victim is between 0-charge and 1-charge reach.
	var near: Node2D = _dummy(Vector2(700, 350))
	var rim: Node2D = _dummy(Vector2(620, 460))
	var before: float = near.health.current
	var rim_before: float = rim.health.current
	var spec: Dictionary = room.player.skill_definition("f")
	check(room.player.cast_skill("f", room.player.position), "actual F is accepted for charge %d" % charge)
	check(is_equal_approx(game.run.resource, 100.0 - float(spec.cost)) and room.player.cooldowns.f > 0.0, "F commits actual resource and cooldown")
	room.player.abilities.tick(float(spec.windup) - 0.001)
	check(node.is_alive() and near.health.current == before, "F does not detonate before authored release")
	room.player.abilities.tick(0.002)
	var dealt: float = before - near.health.current
	var rim_dealt: float = rim_before - rim.health.current
	check(not node.is_alive() and dealt > 0.0, "F release consumes node and deals actual blast damage")
	check(str(near.last_damage_context.get("damage_source", "")) == "node_detonation" and not bool(near.last_damage_context.get("original_basic", true)), "measured damage comes from derived node explosion, not player's F pulse")
	check(not bool(near.last_damage_context.get("equipment_eligible", true)) and room.player.passive_count == 0, "F blast cannot count as a basic or equipment proc")
	check(not node.detonate() and is_equal_approx(before - near.health.current, dealt), "spent node cannot detonate a second time")
	room.player.abilities.tick(float(spec.duration))
	check(not room.player.abilities.busy(), "F finishes actual recovery")
	return {"damage":dealt, "rim_damage":rim_dealt, "resource":game.run.resource}

func _test_f_damage_and_radius() -> void:
	var empty: Dictionary = _f_sample(0)
	var one: Dictionary = _f_sample(1)
	var full: Dictionary = _f_sample(3)
	check(float(empty.damage) > 0.0 and float(one.damage) > float(empty.damage) and float(full.damage) > float(one.damage), "actual F node damage increases for zero, one, and three charges")
	check(is_equal_approx(float(one.damage) / float(empty.damage), 1.65) and is_equal_approx(float(full.damage) / float(empty.damage), 2.95), "fixed-defense F damage follows authored 1 / 1.65 / 2.95 charge multipliers")
	check(empty.rim_damage == 0.0 and one.rim_damage > 0.0 and full.rim_damage > 0.0, "real F blast reach grows with stored charge")

func _test_reduced_fx() -> void:
	for reduced: bool in [false, true]:
		_fixture(reduced)
		var target: Node2D = _dummy()
		var nearest: Node2D = _node(TARGET_AT + Vector2(30, 30))
		var other: Node2D = _node(TARGET_AT + Vector2(90, 30))
		_four_hits(target)
		check(nearest.resonance_charge == 1 and other.resonance_charge == 0 and is_equal_approx(game.run.resource, 26.0), "reduced_fx=%s keeps four-hit selection and mana rules" % str(reduced))
	var normal: Dictionary = _f_sample(3, false)
	var reduced_sample: Dictionary = _f_sample(3, true)
	check(is_equal_approx(normal.damage, reduced_sample.damage) and is_equal_approx(normal.rim_damage, reduced_sample.rim_damage) and normal.resource == reduced_sample.resource, "reduced FX leaves actual F damage/range/resource unchanged")
