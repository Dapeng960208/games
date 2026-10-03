extends Node
## Isolated scene-based acceptance: real player, room, projectiles and deployments.
## Time advances explicitly so every boundary and cancellation can be asserted.

const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const StatusScript = preload("res://scripts/domain/combat/combat_status.gd")
var room: RoomController
var abilities: HeroAbilities
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func fixture(hero: String, level: int = 8) -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hero_id = hero
	Game.run.level = level
	Game.run.stats = StatResolver.resolve(hero, level, {}, {})
	Game.run.stats["crit_chance"] = 0.0
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
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430,350)
	room.player.aim_direction = Vector2.RIGHT
	abilities = room.player.abilities as HeroAbilities

func dummy(at: Vector2) -> EnemyActor:
	var result: EnemyActor = room.spawn_enemy(at)
	result.health.reset(10000.0)
	result.state = &"chase"
	return result

func deployments(kind: String) -> Array[HeroDeployment]:
	var result: Array[HeroDeployment] = []
	for candidate: Node in get_tree().get_nodes_in_group("hero_deployments"):
		if candidate is HeroDeployment and candidate.room == room and candidate.kind == kind and candidate.is_alive():
			result.append(candidate)
	return result

func tick_projectiles(duration: float) -> void:
	var time: float = 0.0
	while time < duration:
		var step: float = minf(0.02, duration - time)
		for projectile: Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():
				projectile._physics_process(step)
		time += step

func _run() -> void:
	if not Game.profile_path.contains("test_heroes"):
		push_error("Refusing non-test profile; pass -- --test-profile=user://test_heroes/profile.json")
		get_tree().quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_r"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated hero run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_twelve_skills()
	_test_basics_passives_and_dashes()
	_test_gates_and_costs()
	_test_cancellation()
	_test_ground_and_sweeps()
	_test_deployment_boundaries()
	_test_status_and_guard_rules()
	_test_original_and_derived_sources()
	_test_strengths_and_branches()
	if is_instance_valid(room):
		room.free()
	print("HERO ACCEPTANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_basics_passives_and_dashes() -> void:
	fixture("CH01",1)
	Game.run.resource = 0.0
	var target: EnemyActor = dummy(Vector2(490,350))
	var second: EnemyActor = dummy(Vector2(490,365))
	check(room.player.fire(Vector2.RIGHT), "level-one breaker can swing at zero rage")
	room.player._tick_attack(0.119)
	check(target.health.current == 10000.0, "basic hammer has its real twelve-hundredths windup")
	room.player._tick_attack(0.001)
	check(target.health.current < 10000.0 and second.health.current < 10000.0, "hammer is a real multi-target frontal swing")
	check(Game.run.resource == 8.0 and room.player.class_status().current == 1, "one multi-target swing grants rage and counts passive once")
	for index in range(2):
		room.player.shot_cooldown = 0.0
		room.player.fire(Vector2.RIGHT)
		room.player._tick_attack(0.50)
	check(is_equal_approx(Game.run.shield,12.0) and Game.run.resource == 24.0, "third real swing activates eight-percent guard")
	check(room.projectiles.get_child_count() == 0, "breaker basic attack never masquerades as a projectile")
	fixture("CH02",1)
	Input.action_press("move_right")
	room.player._physics_process(1.0)
	Input.action_release("move_right")
	check(room.player.class_status().current == 0, "walking alone cannot arm the ranger's confirmed-hit passive")
	Game.run.resource = 0.0
	target = dummy(room.player.position + Vector2(75,0))
	check(room.player.fire(Vector2.RIGHT), "ranger can shoot at zero energy")
	tick_projectiles(0.2)
	check(Game.run.resource == 0.0 and room.player.class_status().current == 1, "first real bullet builds same-target focus without a legacy walking-charge refund")
	room.player.shot_cooldown = 0.0
	check(room.player.fire(Vector2.RIGHT), "second ranger basic fires at zero energy")
	tick_projectiles(0.2)
	check(room.player.class_status().ready, "two real bullets on the same target expose its weak point")
	var before_weakpoint: float = target.health.current
	var weakpoint_chain: float = 1.0 + float(room.player.hit_chain.snapshot().bonus)
	room.player.shot_cooldown = 0.0
	check(room.player.fire(Vector2.RIGHT), "ranger weak-point follow-up fires")
	tick_projectiles(0.2)
	check(is_equal_approx(before_weakpoint-target.health.current,room.player.attack_power()*1.65*weakpoint_chain) and room.player.class_status().current == 0, "third real bullet gains and consumes the 65-percent weak-point bonus with current chain damage")
	fixture("CH03",1)
	Game.run.resource = 0.0
	target = dummy(Vector2(500,350))
	second = dummy(Vector2(560,350))
	for index in range(4):
		room.player.shot_cooldown = 0.0
		check(room.player.fire(Vector2.RIGHT), "resonator basic shot is available with no mana")
		tick_projectiles(0.2)
	check(Game.run.resource == 0.0 and room.player.class_status().current == 1, "four repeated mage basics build one alternation stack without refunding mana")
	check(second.health.current == 10000.0, "repeated mage basics cannot fabricate the retired fourth-hit chain damage")
	fixture("CH03",8)
	target = dummy(Vector2(500,350))
	check(room.player.fire(Vector2.RIGHT), "mage alternating cycle starts with a real basic")
	tick_projectiles(0.2)
	check(abilities.try_cast("q", target.position), "mage follows its basic with a real skill commitment")
	abilities.tick(1.0)
	tick_projectiles(0.2)
	room.player.shot_cooldown = 0.0
	check(room.player.fire(Vector2.RIGHT), "mage alternating cycle returns to a basic")
	tick_projectiles(0.2)
	check(room.player.class_status().ready, "basic-skill-basic fills real mage resonance")
	Game.run.resource = 60.0
	check(abilities.try_cast("secondary", Vector2(510,390)), "ready mage resonance follows a successful crystal cast")
	check(Game.run.resource == 38.0 and room.player.class_status().current == 0, "successful crystal commitment pays 30 mana and refunds eight exactly once")
	abilities.tick(1.0)
	check(Game.run.resource == 38.0, "crystal release cannot repeat the resonance refund")
	for hero: String in ["CH01", "CH02", "CH03"]:
		fixture(hero,1)
		Game.run.resource = 0.0
		var origin: Vector2 = room.player.position
		check(room.player.start_dash(Vector2.RIGHT), hero + " zero-resource dodge starts")
		check(not room.player.start_dash(Vector2.RIGHT), hero + " dodge has one charge")
		if hero == "CH01":
			check(room.player.dash_protected(), "steel step protection starts immediately")
			room.player._tick_dash(0.10)
			check(not room.player.dash_protected(), "steel step protection ends before movement ends")
		elif hero == "CH02":
			check(not room.player.dash_protected(), "ranger slide starts without premature invulnerability")
			room.player._tick_dash(0.04)
			check(room.player.dash_protected(), "ranger protection starts at 0.04 seconds")
			room.player._tick_dash(0.12)
			check(not room.player.dash_protected(), "ranger protection ends at 0.16 seconds")
		else:
			room.player._tick_dash(0.079)
			check(room.player.position == origin and not room.player.dash_protected(), "refractive step waits before teleport and protection")
			room.player._tick_dash(0.001)
			check(room.player.dash_protected() and room.player.position.x > origin.x, "refractive step commits at 0.08 seconds")
		room.player._tick_dash(1.0)
		var distance: float = 110.0 if hero == "CH01" else 160.0 if hero == "CH02" else 130.0
		check(is_equal_approx(room.player.position.distance_to(origin),distance), hero + " dodge travels the planned distance")
		check(not room.player.dash_protected() and Game.run.resource == 0.0, hero + " dodge expires without charging resource")

func _test_twelve_skills() -> void:
	for hero: String in ["CH01", "CH02", "CH03"]:
		for slot: String in ["q", "secondary", "f", "ultimate"]:
			fixture(hero)
			var at := Vector2(480,350)
			if hero == "CH01" and slot == "q":
				at = Vector2(590,350)
			var target: EnemyActor = dummy(at)
			var data: Dictionary = abilities.spec(slot)
			var label: String = hero + " " + slot
			check(abilities.try_cast(slot, at), label + " starts when unlocked and funded")
			check(is_equal_approx(Game.run.resource, 100.0 - float(data.cost)), label + " spends once at start")
			check(float(room.player.cooldowns.get(slot, 0.0)) > 0.0, label + " cooldown commits before hit")
			abilities.tick(float(data.windup) - 0.001)
			check(is_equal_approx(target.health.current, 10000.0), label + " cannot hurt before windup")
			check(room.projectiles.get_child_count() == 0, label + " cannot fire before windup")
			abilities.tick(float(data.duration))
			check(not abilities.busy(), label + " eventually leaves recovery")
			if hero == "CH02" and slot == "q":
				check(room.player.position.x < 285.0, "ranger Q retreats without a move key")
				check(room.projectiles.get_child_count() == 3, "ranger Q fires exactly three shots")
			if hero == "CH02" and slot == "ultimate":
				check(room.projectiles.get_child_count() == 4, "ranger R fires exactly four shots")
			if hero == "CH01" and slot == "q":
				check(is_equal_approx(room.player.position.x, 590.0), "breaker Q advances 160 pixels")
			if hero == "CH01" and slot == "f":
				check(Game.run.shield > 0.0 and Game.run.shield <= Game.run.max_hp * 0.5, "breaker F grants bounded guard")
			if hero == "CH02" and slot == "f":
				var grenades: Array[HeroDeployment] = deployments("grenade")
				check(grenades.size() == 1, "ranger F deploys a timed physical grenade")
				if not grenades.is_empty():
					grenades[0].advance(0.65)
			if hero == "CH03" and slot == "secondary":
				var nodes: Array[HeroDeployment] = deployments("node")
				check(nodes.size() == 1, "resonator secondary creates one attackable node")
				if not nodes.is_empty():
					nodes[0].advance(1.55)
			if hero == "CH03" and slot == "ultimate":
				check(deployments("field").size() == 1, "resonator R leaves a persistent field")
			tick_projectiles(1.4)
			check(target.health.current < 10000.0, label + " produces its real damaging mechanism")

func _test_gates_and_costs() -> void:
	var expected_unlocks := {"q":1, "secondary":2, "f":3, "ultimate":4}
	for hero: String in ["CH01", "CH02", "CH03"]:
		for milestone: int in [1,2,3,4,8]:
			fixture(hero, milestone)
			for slot: String in ["q", "secondary", "f", "ultimate"]:
				var data: Dictionary = abilities.spec(slot)
				var before: float = Game.run.resource
				check(int(data.unlock) == int(expected_unlocks[slot]), "%s %s uses the early unlock level" % [hero,slot])
				var unlocked: bool = milestone >= int(expected_unlocks[slot])
				check(abilities.try_cast(slot, Vector2(480,350)) == unlocked, "%s level %d %s gate" % [hero,milestone,slot])
				if not unlocked:
					check(abilities.last_failure == "locked", "pre-unlock cast reports the level gate")
					check(Game.run.resource == before and float(room.player.cooldowns.get(slot,0.0)) == 0.0, "locked cast cannot debit resource or cooldown")
				abilities.cancel()
				room.player.cooldowns.clear()
				Game.run.resource = 100.0
	fixture("CH02")
	Game.run.resource = 24.0
	check(not abilities.try_cast("q", Vector2(480,350)) and abilities.last_failure == "resource", "insufficient energy rejects Q")
	check(Game.run.resource == 24.0 and room.player.cooldowns.get("q",0.0) == 0.0, "insufficient cast has no partial debit")
	Game.run.resource = 100.0
	check(abilities.try_cast("q", Vector2(480,350)), "funded cast starts")
	var committed: float = Game.run.resource
	check(not abilities.try_cast("q", Vector2(480,350)) and Game.run.resource == committed, "same-frame second cast cannot double debit")
	abilities.cancel()
	check(not abilities.try_cast("q", Vector2(480,350)) and abilities.last_failure == "cooldown", "cancelling does not remove cooldown")

func _test_cancellation() -> void:
	fixture("CH02")
	check(abilities.try_cast("ultimate", Vector2(600,350)), "ranger R cancellation fixture starts")
	abilities.tick(0.25)
	check(room.projectiles.get_child_count() == 1, "first R shot occurs exactly at windup boundary")
	abilities.cancel()
	abilities.tick(10.0)
	check(room.projectiles.get_child_count() == 1, "cancelled R never emits its other three shots")
	check(Game.run.resource == 40.0 and float(room.player.cooldowns.ultimate) == 40.0, "cancelled R keeps its full committed cost")
	fixture("CH01")
	var target: EnemyActor = dummy(Vector2(500,350))
	check(abilities.try_cast("ultimate", target.position), "breaker cancellation fixture starts")
	abilities.tick(0.44)
	abilities.cancel()
	abilities.tick(2.0)
	check(target.health.current == 10000.0 and Game.run.resource == 30.0, "cancel before hammer impact avoids damage without refund")
	fixture("CH02")
	check(abilities.try_cast("q", Vector2(500,350)), "ranger volley cancellation fixture starts")
	abilities.tick(0.22)
	abilities.cancel()
	abilities.tick(1.0)
	check(room.projectiles.get_child_count() == 1, "Q cancel stops pending second and third shots")

func _test_ground_and_sweeps() -> void:
	fixture("CH03")
	check(not abilities.try_cast("secondary", Vector2(900,350)) and Game.run.resource == 100.0, "out-of-range node is not charged")
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(460,270,30,150)])
	check(not abilities.try_cast("secondary", Vector2(505,350)), "node cannot be placed behind an occluding wall")
	check(not abilities.try_cast("ultimate", Vector2(475,350)), "field cannot be placed inside solid ground")
	check(Game.run.resource == 100.0, "invalid deployment keeps all mana")
	fixture("CH01")
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(470,270,30,150)])
	var target: EnemyActor = dummy(Vector2(515,350))
	check(abilities.try_cast("q", target.position), "Q with some legal path can begin")
	abilities.tick(1.0)
	check(room.player.position.x < 470.0 - Balance.PLAYER_RADIUS + 0.01, "Q movement sweeps into a wall and stops")
	check(target.health.current == 10000.0, "Q impact cannot damage an enemy through the wall")
	fixture("CH01")
	var behind: EnemyActor = dummy(Vector2(380,350))
	var front: EnemyActor = dummy(Vector2(510,350))
	check(abilities.try_cast("secondary", front.position), "arc strike starts")
	abilities.tick(1.0)
	check(front.health.current < 10000.0 and behind.health.current == 10000.0, "sweep damages front arc but excludes rear")
	var once: float = front.health.current
	abilities.tick(5.0)
	check(front.health.current == once, "spent melee event cannot hit again on a later tick")

func _test_deployment_boundaries() -> void:
	fixture("CH03")
	var target: EnemyActor = dummy(Vector2(530,350))
	check(abilities.try_cast("secondary", Vector2(480,350)), "node timing fixture starts")
	abilities.tick(1.0)
	var nodes: Array[HeroDeployment] = deployments("node")
	if nodes.size() != 1:
		check(false, "node timing fixture exists")
		return
	nodes[0].advance(1.549)
	check(room.projectiles.get_child_count() == 0, "node grants neither an immediate nor early attack")
	nodes[0].advance(0.001)
	check(room.projectiles.get_child_count() == 1, "node first attack follows 0.35 setup plus 1.2 interval")
	var node_hp: float = nodes[0].health
	check(nodes[0].receive_damage(node_hp + 1.0) and not nodes[0].is_alive(), "enemy damage can destroy a node")
	fixture("CH02")
	target = dummy(Vector2(485,350))
	check(abilities.try_cast("f", Vector2(480,350)), "grenade timing fixture starts")
	abilities.tick(1.0)
	var grenades: Array[HeroDeployment] = deployments("grenade")
	if grenades.size() != 1:
		check(false, "grenade timing fixture exists")
		return
	grenades[0].advance(0.649)
	check(target.health.current == 10000.0, "grenade is harmless before its fuse completes")
	grenades[0].advance(0.001)
	check(target.health.current < 10000.0 and not grenades[0].is_alive(), "grenade explodes once at the fuse boundary")
	var hit_health: float = target.health.current
	grenades[0].advance(5.0)
	check(target.health.current == hit_health, "spent grenade cannot explode a second time")
	fixture("CH03")
	target = dummy(Vector2(485,350))
	check(abilities.try_cast("ultimate", Vector2(480,350)), "field timing fixture starts")
	abilities.tick(1.0)
	var fields: Array[HeroDeployment] = deployments("field")
	if fields.size() != 1:
		check(false, "field timing fixture exists")
		return
	var after_impact: float = target.health.current
	fields[0].advance(0.999)
	check(target.health.current == after_impact, "field has no fractional or immediate extra tick")
	fields[0].advance(0.001)
	var first_tick: float = after_impact - target.health.current
	check(first_tick > 0.0, "field ticks at exactly one second")
	fields[0].advance(4.0)
	check(is_equal_approx(after_impact - target.health.current, first_tick * 5.0), "field performs all five ticks including expiry boundary")
	check(not fields[0].is_alive(), "field retires after its final fifth tick")

func _test_status_and_guard_rules() -> void:
	var status: CombatStatus = StatusScript.new()
	status.apply("burn", 100.0)
	check(status.tick(0.75).is_empty(), "burn does not tick early")
	status.apply("burn", 50.0)
	var ticks: Array[Dictionary] = status.tick(0.25)
	check(ticks.size() == 1 and is_equal_approx(float(ticks[0].damage), 6.0), "burn refresh preserves cadence and uses refreshed power")
	status.apply("burn", 70.0)
	status.apply("burn", 10.0)
	ticks = status.tick(1.0)
	check(ticks.size() == 1 and is_equal_approx(float(ticks[0].damage), 8.4), "same-frame status application retains the larger snapshot")
	ticks = status.tick(2.0)
	check(ticks.size() == 2 and not status.has("burn"), "refreshed burn may exceed three lifetime ticks and expires exactly")
	status.apply("shock", 100.0)
	check(is_equal_approx(status.consume_shock(), 25.0), "shock consumes its stored source power")
	status.apply("shock", 100.0)
	check(status.consume_shock() == 0.0 and status.has("shock"), "shock ICD neither fires nor consumes a reapplied state")
	status.tick(1.0)
	check(is_equal_approx(status.consume_shock(),25.0), "shock ICD releases at one second")
	status.grant_guard(900.0,4.0,"hero",100.0)
	status.grant_guard(900.0,4.0,"equipment",100.0,true)
	check(is_equal_approx(status.shield(),50.0), "guard sources are capped before storage and combine by maximum")
	check(is_equal_approx(status.absorb(40.0),0.0) and is_equal_approx(status.shield(),10.0), "absorbed hit drains every source, avoiding hidden weak shield resurrection")
	check(not status.grant_guard(5.0,4.0,"hero",100.0), "weak refresh emits no new effective-guard event")
	status.tick(4.0)
	check(status.shield() == 0.0, "guard duration expires independently of health")

func _test_strengths_and_branches() -> void:
	fixture("CH01", 20)
	check(abilities.spec("q").cost == 15.0 and abilities.spec("secondary").duration == 0.46, "breaker levels 10/12 improve cost and recovery")
	check(abilities.spec("f").guard == 0.18 and abilities.spec("ultimate").coefficient == 4.6, "breaker levels 14/16 improve shield and ultimate")
	Game.run.stats["branches"] = {"q":"A", "ultimate":"A"}
	check(abilities.spec("q").travel == 240.0 and abilities.spec("ultimate").windup == 0.65, "breaker A branches trade damage/charge time for reach/power")
	Game.run.stats["branches"] = {"q":"B", "ultimate":"B"}
	check(abilities.spec("q").travel == 0.0 and abilities.spec("ultimate").waves == 2, "breaker B branches become anchored shock and two waves")
	fixture("CH02",20)
	check(abilities.spec("q").cost == 20.0 and abilities.spec("secondary").pierce_multiplier == 1.0, "ranger levels 10/12 improve energy and second hit")
	check(abilities.spec("f").radius == 130.0 and abilities.spec("ultimate").movement == 0.7, "ranger levels 14/16 improve grenade and moving ultimate")
	Game.run.stats["branches"] = {"q":"B", "ultimate":"B"}
	check(abilities.spec("q").coefficient == 0.55 and abilities.spec("ultimate").shots == 3, "ranger B branches are stationary Q and mobile three-shot R")
	fixture("CH03",20)
	check(abilities.spec("q").speed == 850.0 and abilities.spec("secondary").health == 50.0, "resonator levels 10/12 improve pulse and node")
	check(abilities.spec("f").cooldown == 9.0 and abilities.spec("ultimate").radius == 210.0, "resonator levels 14/16 improve cold ring and dome")
	Game.run.stats["branches"] = {"q":"A", "ultimate":"A"}
	check(abilities.spec("q").explosion_radius == 0.0 and abilities.spec("q").pierce == 1, "phase Q replaces explosion with two-target piercing")
	check(abilities.spec("ultimate").lifetime == 7.0, "stationary pressure dome has seven ticks")
	Game.run.stats["branches"] = {"q":"B", "ultimate":"B"}
	check(abilities.spec("q").range == 350.0 and abilities.spec("ultimate").follow_player, "mobile resonator branches reduce reach and follow player")
	check(abilities.try_cast("ultimate",Vector2(5000,5000)), "self-centered mobile dome ignores an unused out-of-range cursor")
	abilities.cancel()
	Game.run.resource = 100.0
	Game.run.level = 17
	check(abilities.spec("q").branch == "" and abilities.spec("ultimate").branch == "", "future saved branch selections never bypass level gates")
	Game.run.stats["cooldown_reduction"] = 9.0
	check(is_equal_approx(float(abilities.spec("f").cooldown),6.3), "equipment cooldown reduction caps at thirty percent")
	check(abilities.try_cast("f", Vector2(480,350)) and is_equal_approx(float(room.player.cooldowns.f),6.3), "cast commits the same reduced cooldown exposed by its specification")

func _test_original_and_derived_sources() -> void:
	fixture("CH03")
	var target: EnemyActor = dummy(Vector2(500,350))
	var node_power: float = 1.0
	var first: HeroDeployment = room.add_deployment("node", Vector2(490,350), {"damage":1.0,"power":node_power,"owner_player":room.player})
	var second: HeroDeployment = room.add_deployment("node", Vector2(510,350), {"damage":1.0,"power":node_power,"owner_player":room.player})
	first.advance(0.35)
	second.advance(0.35)
	check(abilities.try_cast("q", target.position), "pulse with overlapping echo nodes starts")
	abilities.tick(1.0)
	tick_projectiles(0.4)
	check(target.status.has("shock"), "pulse's own newly applied shock survives its derived node echoes")
	var power: float = room.player.skill_power()
	check(is_equal_approx(10000.0-target.health.current,power * 1.6), "overlapping nodes contribute only one 0.35H echo to the 1.25H pulse")
	var prior: float = target.health.current
	var frost_chain: float = 1.0 + float(room.player.hit_chain.snapshot().bonus)
	check(first.resonance_charge == 0 and second.resonance_charge == 0, "nodes do not gain charge without advancing across a live Q bolt")
	check(abilities.try_cast("f", target.position), "original frost ring follows shock")
	abilities.tick(1.0)
	check(not target.status.has("shock") and target.status.has("chill"), "next original skill consumes old shock before applying chill")
	check(is_equal_approx(prior-target.health.current,power * .8 * frost_chain + power * .25 + node_power * 2.0), "frost ring buffs direct body damage while shock and two uncharged node blasts retain their own damage")
	check(not first.is_alive() and not second.is_alive(), "F consumes each node once after its derived blast")
	fixture("CH03")
	target = dummy(Vector2(480,350))
	check(abilities.try_cast("ultimate",target.position), "derived field source fixture starts")
	abilities.tick(1.0)
	var fields: Array[HeroDeployment] = deployments("field")
	if not fields.is_empty():
		fields[0].advance(1.0)
	check(target.status.has("shock"), "field's recurring damage cannot consume impact shock")
