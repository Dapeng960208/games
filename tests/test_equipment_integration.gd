extends Node
## Real-node equipment acceptance: attacks, damage, dodges and skills enter through
## the production player/room. No test calls EquipmentEffects.handle directly.

const RoomScene = preload("res://scenes/room.tscn")
const Registry = preload("res://scripts/data/content_registry.gd")
var room: MineRoom
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fixture(ids: Array[String], hero: String = "CH01", level: int = 8) -> void:
	if is_instance_valid(room):
		room.free()
	var loadout: Dictionary = {}
	var owned: Dictionary = {}
	for id: String in ids:
		var item: Dictionary = Registry.equipment(id)
		loadout[str(item.slot)] = id
		owned[id] = {"level":0}
	Game.run.hero_id = hero
	Game.run.level = level
	Game.run.loadout_snapshot = loadout.duplicate(true)
	Game.run.equipment_snapshot = owned.duplicate(true)
	Game.run.stats = StatResolver.resolve(hero, level, loadout, owned)
	Game.run.stats["crit_chance"] = 0.0
	# Natural regeneration is irrelevant to equipment refund assertions.
	Game.run.stats["resource_regen"] = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = true
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430,350)
	room.player.aim_direction = Vector2.RIGHT

func dummy(at: Vector2 = Vector2(500,350), hp: float = 10000.0) -> MineEnemy:
	var enemy: MineEnemy = room.spawn_enemy(at)
	enemy.armor = 0.0
	enemy.health.reset(hp)
	enemy.state = &"chase"
	return enemy

func tick_player(delta: float) -> void:
	room.player._physics_process(delta)

func tick_projectiles(duration: float = 0.25) -> void:
	var elapsed: float = 0.0
	while elapsed < duration:
		var step: float = minf(0.02, duration - elapsed)
		for projectile: Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():
				projectile._physics_process(step)
		elapsed += step

func basic(target: MineEnemy, other: MineEnemy = null) -> float:
	tick_player(0.51)
	room.player.position = Vector2(430,350)
	room.player.aim_direction = Vector2.RIGHT
	target.position = Vector2(500,350)
	if is_instance_valid(other):
		other.position = Vector2(505,365)
	var before: float = target.health.current
	check(room.player.fire(Vector2.RIGHT), "real primary attack accepted after its cooldown")
	tick_player(0.12)
	tick_projectiles()
	return before - target.health.current

func _run() -> void:
	if not Game.profile_path.contains("test_equipment_integration"):
		push_error("Refusing non-test profile; use --test-profile with test_equipment_integration")
		get_tree().quit(2)
		return
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated equipment integration run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_starter_attack_and_movement()
	_test_starter_defenses()
	_test_burn_set_and_derived_kills()
	_test_burn_snapshot_is_not_dot_multiplier()
	_test_shield_dash_set()
	_test_shared_roots_and_source_gates()
	_test_refund_and_cost_commit()
	_test_relic_equipment_budget()
	_test_live_guard_source_exhaustion()
	_test_native_chill_duration()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "audio mixer releases playback from all equipment fixtures")
		room.free()
	print("EQUIPMENT INTEGRATION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_starter_attack_and_movement() -> void:
	fixture(["EQ01","EQ11","EQ21","EQ31","EQ41","EQ51"])
	var target: MineEnemy = dummy()
	var power: float = room.player.attack_power()
	var first: float = basic(target)
	var second: float = basic(target)
	var third: float = basic(target)
	# Equipment bonuses share their additive bucket; the confirmed-hit chain
	# multiplies the resulting direct packet by +0.5% per preceding attack.
	check(is_equal_approx(first,power * 1.03) and is_equal_approx(second,power * 1.03 * 1.005), "starter gloves add three percent while the second hit gains its separate combo bonus")
	check(is_equal_approx(third,power * 1.11 * 1.01), "starter core adds eight percent only on the third same-target hit before the combo multiplier")
	check(room.player.hit_chain.count == 3, "three real starter attacks build exactly three confirmed combo stacks")
	check(is_equal_approx(basic(target),power * 1.03 * 1.015), "third-hit equipment counter resets while the live combo continues")
	Game.run.hp = Game.run.max_hp * 0.5
	check(is_equal_approx(basic(target),power * 1.02), "losing full health removes glove damage immediately and retains the combo bonus")
	var different: MineEnemy = dummy(Vector2(510,350))
	target.position = Vector2(950,500)
	basic(different)
	different.position = Vector2(950,500)
	check(is_equal_approx(basic(target),power * 1.03), "changing targets resets equipment consecutive-hit tracking without clearing the combo")
	check(room.player.hit_chain.count == 7, "target switches preserve one combo stack per confirmed attack")
	var healthy_move: float = _walk_sample()
	Game.run.hp = Game.run.max_hp * 0.25
	var low_move: float = _walk_sample()
	check(low_move > healthy_move * 1.04, "low-health goggles increase actual walking distance")
	Game.run.hp = Game.run.max_hp
	check(is_equal_approx(_walk_sample(),healthy_move), "goggle movement bonus disappears immediately after recovery")

func _walk_sample() -> float:
	room.player.position = Vector2(430,350)
	room.player.knockback = Vector2.ZERO
	# Manual fixture HP changes enter normal stat refresh before sampled movement.
	tick_player(0.001)
	room.input_blocked = false
	room.release_gate = false
	Input.action_press("move_down")
	tick_player(0.1)
	Input.action_release("move_down")
	room.input_blocked = true
	return room.player.position.distance_to(Vector2(430,350))

func _test_starter_defenses() -> void:
	fixture(["EQ21"])
	Game.run.hp = Game.run.max_hp * 0.31
	check(room.player.receive_damage(Game.run.max_hp * 0.04,Vector2(400,350)), "enemy damage crosses low-health threshold")
	check(Game.run.hp < Game.run.max_hp * 0.30 and is_equal_approx(Game.run.shield,Game.run.max_hp * 0.05), "patch coat gives five-percent guard on actual threshold crossing")
	tick_player(4.1)
	check(Game.run.shield == 0.0, "patch guard expires normally")
	room.player.invulnerable = 0.0
	room.player.receive_damage(1.0,Vector2(400,350))
	check(Game.run.shield == 0.0, "patch coat cannot grant a second shield in the same battle room")
	fixture(["EQ51"])
	Game.run.hp = Game.run.max_hp * 0.5
	var before: float = Game.run.hp
	room.player.receive_damage(10.0,Vector2(400,350))
	var healthy_loss: float = before - Game.run.hp
	Game.run.hp = Game.run.max_hp * 0.25
	tick_player(0.001)
	room.player.invulnerable = 0.0
	before = Game.run.hp
	room.player.receive_damage(10.0,Vector2(400,350))
	check(Game.run.hp > before - healthy_loss, "low-health compass reduces real health damage")
	fixture([])
	room.player.receive_damage(1.0,Vector2(400,350))
	var base_push: float = room.player.knockback.length()
	fixture(["EQ41"])
	room.player.receive_damage(1.0,Vector2(400,350))
	check(is_equal_approx(room.player.knockback.length(),base_push * 0.9), "starter boots reduce actual incoming knockback by ten percent")

func _test_burn_set_and_derived_kills() -> void:
	fixture(["EQ03","EQ13","EQ23","EQ33"])
	var target: MineEnemy = dummy()
	var power: float = room.player.attack_power()
	check(is_equal_approx(basic(target),power), "first flame strike cannot benefit retroactively from its new burn or set buff")
	check(target.status.has("burn"), "flame core applies shared burn after the real hit")
	check(is_equal_approx(basic(target),power * 1.18 * 1.005), "next burning strike receives additive S01 two-piece and four-piece bonuses before combo scaling")
	tick_player(3.1)
	target.apply_status("burn",power)
	check(is_equal_approx(basic(target),power * 1.08 * 1.01), "three-second four-piece buff expires while burning condition and four-second combo remain")
	tick_player(4.01)
	check(room.player.hit_chain.count == 0, "normal player time expires the confirmed-hit combo")
	check(is_equal_approx(basic(target),power * 1.08), "after combo expiry only the active S01 burning condition increases the next strike")
	fixture(["EQ03","EQ13","EQ23","EQ33","EQ43","EQ53"])
	target = dummy()
	basic(target)
	check(is_equal_approx(Game.run.shield,Game.run.max_hp * 0.02), "flame pendant grants real guard only after successful burn application")
	fixture(["EQ03","EQ13","EQ23","EQ33","EQ43","EQ53"])
	target = dummy(Vector2(500,350),1.0)
	target.apply_status("burn",room.player.attack_power())
	var neighbors: Array[MineEnemy] = []
	for at: Vector2 in [Vector2(650,350),Vector2(670,350),Vector2(690,350),Vector2(710,350)]:
		var neighbor: MineEnemy = dummy(at,1.0)
		neighbor.apply_status("burn",room.player.attack_power())
		neighbors.append(neighbor)
	basic(target)
	var deaths: int = 0
	for neighbor: MineEnemy in neighbors:
		if not neighbor.is_alive():
			deaths += 1
	check(deaths == 3 and neighbors[3].is_alive(), "burning kill emits at most three embers and derived kills do not cascade")

func _test_shield_dash_set() -> void:
	fixture(["EQ08","EQ18","EQ28","EQ38","EQ48","EQ58"])
	var target: MineEnemy = dummy()
	var power: float = room.player.attack_power()
	room.player.grant_guard(Game.run.max_hp * 0.10,4.0,"test_guard")
	check(room.player.start_dash(Vector2.RIGHT), "shielded S06 real dodge starts")
	tick_player(0.18)
	var boosted: float = basic(target)
	check(is_equal_approx(boosted,power * 1.12 + 4.0), "S06 shielded dash adds twelve percent physical damage and four flat true damage")
	check(is_equal_approx(basic(target),power * 1.005 + 4.0), "S06 dash window is consumed while combo scales physical damage and flat true damage stays four")
	check(room.player.hit_chain.count == 2, "equipment true-damage follow-ups do not add combo stacks")
	fixture(["EQ08","EQ18","EQ28","EQ38","EQ48","EQ58"])
	target = dummy()
	room.player.grant_guard(1.0,4.0,"test_guard")
	room.player.receive_damage(5.0,Vector2(400,350))
	check(Game.run.shield == 0.0, "actual enemy damage breaks the test shield")
	var other: MineEnemy = dummy(Vector2(650,350))
	var prior: float = other.health.current
	basic(target)
	check(is_equal_approx(prior-other.health.current,room.player.attack_power() * 0.4), "S06 shield-break follow-up creates a real secondary wave")
	prior = other.health.current
	basic(target)
	check(other.health.current == prior, "shield-break wave is consumed and cannot repeat on next attack")
	fixture(["EQ48"])
	check(room.player.start_dash(Vector2.RIGHT), "rock boot dash starts")
	tick_player(0.18)
	check(is_equal_approx(Game.run.shield,Game.run.max_hp * 0.02), "rock boots grant shield at real dash end")
	room.player.status.absorb(Game.run.shield)
	Game.run.shield = 0.0
	room.player.dash_cooldown = 0.0
	room.player.start_dash(Vector2.RIGHT)
	tick_player(0.18)
	check(Game.run.shield == 0.0, "rock-boot six-second ICD blocks a second rapid dodge reward")

func _test_shared_roots_and_source_gates() -> void:
	fixture(["EQ04"])
	var target: MineEnemy = dummy()
	var other: MineEnemy = dummy(Vector2(505,365))
	basic(target,other)
	check(not target.status.has("shock") and not other.status.has("shock"), "one two-target hammer sweep is only one equipment count")
	basic(target,other)
	check(not target.status.has("shock") and not other.status.has("shock"), "second multi-target sweep still cannot satisfy three-attack trigger")
	basic(target,other)
	check(target.status.has("shock") and not other.status.has("shock"), "third sweep applies shock once to the shared root's primary target")
	check(room.player.hit_chain.count == 3, "multi-target equipment sweeps count once per original attack in the combo")
	fixture(["EQ04"],"CH03")
	target = dummy()
	basic(target)
	for index in range(8):
		var child: SparkProjectile = room.spawn_projectile(Vector2(470,350),Vector2.RIGHT,1.0,&"child")
		child.hit(target)
	target.apply_status("burn",1.0)
	target.tick_statuses(3.0)
	check(not target.status.has("shock"), "relic child hits and DOT ticks cannot advance weapon procs")
	check(room.player.hit_chain.count == 1, "relic children and DOT ticks cannot advance the confirmed original-hit combo")
	basic(target)
	check(not target.status.has("shock"), "derived sources did not increment the original-attack counter")
	basic(target)
	check(target.status.has("shock"), "third actual primary still triggers after intervening derived damage")

func _test_refund_and_cost_commit() -> void:
	fixture(["EQ32"],"CH03")
	var target: MineEnemy = dummy()
	Game.run.resource = 0.0
	for index in range(4):
		basic(target)
	check(Game.run.resource == 0.0 and int(room.player.class_status().current) == 1, "four repeated basics build one resonance stack and grant no mana or early EQ32 refund")
	Game.run.resource = 100.0
	check(room.player.cast_skill("q",target.position), "resource-counter fixture casts actual pulse")
	tick_player(0.4)
	tick_projectiles(0.3)
	check(is_equal_approx(Game.run.resource,82.0), "active skill cannot masquerade as fifth original basic for EQ32")
	check(int(room.player.class_status().current) == 2 and not bool(room.player.class_status().ready), "successful pulse advances only the skill half of alternating resonance")
	basic(target)
	check(is_equal_approx(Game.run.resource,85.0), "fifth actual basic restores exactly three mage mana")
	check(bool(room.player.class_status().ready), "fifth basic fills alternating resonance without paying its next-skill refund early")
	fixture(["EQ56"],"CH03")
	target = dummy()
	target.apply_status("corrosion",room.player.attack_power())
	basic(target)
	Game.run.level = 1
	check(not room.player.cast_skill("secondary",target.position), "level-two node remains locked and does not consume prepared cost discount")
	Game.run.level = 8
	room.player.cooldowns.q = 1.0
	check(not room.player.cast_skill("q",target.position), "cooling skill does not consume prepared discount")
	room.player.cooldowns.q = 0.0
	check(not room.player.cast_skill("secondary",Vector2(900,350)), "illegal node location does not consume prepared discount")
	Game.run.resource = 1.0
	check(not room.player.cast_skill("q",target.position), "unfunded skill does not consume prepared discount")
	Game.run.resource = 100.0
	check(room.player.cast_skill("q",target.position), "prepared discount reaches the first successful real skill")
	check(is_equal_approx(Game.run.resource,83.44), "successful pulse applies precisely eight-percent cost reduction")
	room.player.cancel_actions()
	room.player.cooldowns.q = 0.0
	var remaining: float = Game.run.resource
	check(room.player.cast_skill("q",target.position), "second pulse can be tested after isolated cooldown reset")
	check(is_equal_approx(remaining-Game.run.resource,18.0), "paid successful cast consumes discount even if its animation is cancelled")

func _test_relic_equipment_budget() -> void:
	fixture(["EQ03","EQ53"],"CH03")
	Game.run.relics.assign(["split","ember","arc"])
	Game.run.shots = 2
	var target: MineEnemy = dummy()
	# CH03 now echoes spells within 135 pixels instead of spawning gun bullets.
	var first_echo: MineEnemy = dummy(Vector2(570,350))
	var second_echo: MineEnemy = dummy(Vector2(620,350))
	first_echo.magic_resist = 0.0
	second_echo.magic_resist = 0.0
	basic(target)
	var root_id: String = "basic:" + str(room.attack_serial)
	var rules: RefCounted = room.player.loadout.effects
	var usage: Dictionary = rules.root_usage(root_id)
	check(int(usage.packets) == 4 and float(usage.coefficient) <= 1.2, "three native relics and equipment share a four-package root budget")
	check(room.telemetry.split_spawned == 0 and room.telemetry.arc_hits == 1 and target.status.has("burn"), "mage relic packages produce spell echoes and burn without gun bullets")
	var echo_damage: float = room.player.stat("ability_power",28.0) * 0.4
	check(is_equal_approx(first_echo.health.maximum-first_echo.health.current,echo_damage) and is_equal_approx(second_echo.health.maximum-second_echo.health.current,echo_damage), "both nearby enemies receive the published forty-percent AP echo damage")
	for echoed: MineEnemy in [first_echo,second_echo]:
		check(echoed.last_damage_context.get("damage_type") == "magic" and not echoed.last_damage_context.get("equipment_eligible",true) and int(echoed.last_damage_context.get("proc_depth",0)) == 1 and echoed.last_damage_context.get("root_event_id") == root_id, "mage echo retains magical non-recursive damage within its original shared root")
	check(Game.run.shield == 0.0, "weapon priority uses the last package before the later charm shield")
	var core_key: String = "EQ03:" + str(target.get_instance_id())
	check(rules.cooldowns.has(core_key) and not rules.cooldowns.has("EQ53"), "funded weapon starts its cooldown while budget-denied charm does not")
	var packet_count: int = int(usage.packets)
	tick_projectiles(0.5)
	usage = rules.root_usage(root_id)
	check(int(usage.packets) == packet_count, "derived spell echoes cannot reopen or enlarge the original root budget")
	# Expire the burn and keep only one native relic, while the denied charm's
	# seven-second ICD would still be active if rejection incorrectly paid it.
	Game.run.relics.assign(["ember"])
	tick_player(3.1)
	target.tick_statuses(3.1)
	check(not target.status.has("burn"), "relic burn expires before the charm retry fixture")
	basic(target)
	check(target.status.has("burn") and is_equal_approx(Game.run.shield,Game.run.max_hp * 0.02), "budget-denied charm remains eligible on a later funded burn attack")

func _test_live_guard_source_exhaustion() -> void:
	fixture([])
	var maximum: float = Game.run.max_hp
	room.player.grant_guard(maximum * 4.0,4.0,"strong_source")
	room.player.grant_guard(maximum * 0.3,4.0,"weak_source")
	check(is_equal_approx(Game.run.shield,maximum * 0.5), "live player stores capped strong guard and combines sources by maximum")
	var raw: float = (Game.run.shield + 1.0) * (1.0 + float(Game.run.stats.armor) / 100.0)
	var prior_hp: float = Game.run.hp
	check(room.player.receive_damage(raw,Vector2(400,350)), "real enemy hit exhausts the visible guard pool")
	check(Game.run.shield == 0.0 and is_equal_approx(prior_hp-Game.run.hp,1.0), "guard absorbs mitigated damage before one residual health damage")
	check(room.player.status.shield() == 0.0, "damage drains weak and strong source records together")
	tick_player(0.25)
	check(Game.run.shield == 0.0 and room.player.status.shield() == 0.0, "next physics update cannot revive the weaker stored guard")

func _test_native_chill_duration() -> void:
	fixture(["EQ05","EQ15"],"CH03")
	var target: MineEnemy = dummy()
	check(room.player.cast_skill("f",target.position), "S03 two-piece native frost ring casts")
	tick_player(0.4)
	check(target.status.has("chill") and is_equal_approx(float(target.status.states.get("chill",{}).get("remaining",0.0)),3.6), "S03 two-piece extends actual native F chill from three to 3.6 seconds")
	fixture(["EQ05","EQ15"],"CH03")
	Game.run.stats["status_duration"] = 0.35
	target = dummy()
	check(room.player.cast_skill("f",target.position), "high-duration native frost ring casts")
	tick_player(0.4)
	check(is_equal_approx(float(target.status.states.get("chill",{}).get("remaining",0.0)),4.2), "native chill adds equipment and set duration then respects the shared forty-percent cap")

func _test_burn_snapshot_is_not_dot_multiplier() -> void:
	fixture(["EQ03", "EQ13", "EQ23", "EQ33", "EQ43", "EQ53"])
	var power: float = room.player.attack_power()
	Game.run.stats["burn_damage"] = 0.6
	var target: MineEnemy = dummy(Vector2(500,350), 1.0)
	var neighbor: MineEnemy = dummy(Vector2(560,350), 1000.0)
	target.apply_status("burn", power)
	Game.run.stats["attack"] = power * 2.0
	target.tick_statuses(1.0)
	check(not target.is_alive(), "enhanced burn tick causes a real lethal status event")
	check(is_equal_approx(1000.0 - neighbor.health.current, power * 0.35), "burn-kill embers use original H snapshot, not DOT multiplier or later hero power")
