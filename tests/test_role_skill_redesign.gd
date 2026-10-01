extends Node
## Behavioral role acceptance uses the real room, actors and committed casts.
## Explicit clocks isolate release, fuse and expiry; no player's save is touched.

const RoomScene = preload("res://scenes/room.tscn")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
var room: MineRoom
var abilities: HeroAbilities
var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROLE SKILL FAIL: " + label)

func fixture(hero: String, level: int = 8) -> void:
	if is_instance_valid(room):
		room.free()
	Game.run.hero_id = hero
	Game.run.level = level
	Game.run.stats = StatResolver.resolve(hero, level, {}, {})
	Game.run.stats.merge({"crit_chance":0.0, "armor":0.0, "magic_resist":0.0, "equipment_damage_reduction":0.0, "damage_reduction":0.0}, true)
	Game.run.loadout_snapshot = {}
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = 100.0
	Game.run.shield = 0.0
	Game.run.relics.clear()
	Game.profile.settings["muted"] = true
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children():
		enemy.free()
	room.player.position = Vector2(430, 350)
	room.player.aim_direction = Vector2.RIGHT
	abilities = room.player.abilities as HeroAbilities

func dummy(at: Vector2) -> MineEnemy:
	var target: MineEnemy = room.spawn_enemy(at)
	target.health.reset(10000.0)
	target.status.states.clear()
	target.status.guards.clear()
	target.armor = 0.0
	target.magic_resist = 0.0
	target.rank = "normal"
	target.state = &"chase"
	return target

func deployment(kind: String) -> HeroDeployment:
	for child: Node in room.get_children():
		if child is HeroDeployment and child.kind == kind and child.is_alive():
			return child as HeroDeployment
	return null

func incoming(amount: float) -> float:
	var before: float = Game.run.hp + Game.run.shield
	room.player.invulnerable = 0.0
	check(room.player.receive_damage(amount, room.player.position + Vector2.LEFT * 80.0, {"damage_type":"physical"}), "real enemy contact is accepted")
	return before - Game.run.hp - Game.run.shield

func tick_projectiles(duration: float) -> void:
	var time: float = 0.0
	while time < duration:
		var step: float = minf(0.02, duration - time)
		for projectile: Node in room.projectiles.get_children():
			if not projectile.is_queued_for_deletion():
				projectile._physics_process(step)
		time += step

func _run() -> void:
	if not Game.profile_path.contains("test_role_skill_redesign"):
		push_error("Refusing non-test role profile; use --test-profile containing test_role_skill_redesign")
		get_tree().quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated role run starts")
	if Game.run == null:
		get_tree().quit(1)
		return
	_test_warrior_guard()
	_test_warrior_stronger_guard()
	_test_warrior_guard_snapshot()
	_test_gunner_grenade_and_combo()
	_test_gunner_center_contact()
	_test_gunner_empty_and_cancelled()
	_test_gunner_ground_and_radius()
	_test_mage_field_control()
	_test_mage_field_cancellation()
	if is_instance_valid(room):
		room.free()
	print("ROLE SKILL REDESIGN: %d checks, %d failures (real guard, grenade and field behavior)" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_warrior_guard() -> void:
	fixture("CH01")
	var target: MineEnemy = dummy(Vector2(485, 350))
	var power: float = room.player.skill_power()
	check(abilities.try_cast("f", target.position), "warrior guard commits")
	check(Game.run.resource == 75.0 and room.player.cooldowns.f == 11.0, "warrior guard retains one 25-rage / 11-second commitment")
	abilities.tick(0.119)
	check(Game.run.shield == 0.0 and not room.player.status.has("brace_guard") and target.health.current == 10000.0, "warrior windup grants no premature defense or damage")
	abilities.tick(0.001)
	check(is_equal_approx(10000.0 - target.health.current, power * 0.6), "warrior war cry retains its close physical strike")
	check(is_equal_approx(target.pending_displacement().length(), 70.0), "warrior war cry pushes a nearby ordinary enemy away")
	check(is_equal_approx(Game.run.shield, Game.run.max_hp * 0.12), "warrior release grants its ordinary guard")
	check(is_equal_approx(incoming(40.0), 30.0), "released warrior guard prevents one quarter of actual incoming damage before shield absorption")
	abilities.cancel()
	room.player.status.tick(1.499)
	check(is_equal_approx(incoming(40.0), 30.0), "cancelling recovery preserves already-earned defense until its final millisecond")
	room.player.status.tick(0.001)
	check(is_equal_approx(incoming(40.0), 40.0), "warrior damage prevention expires exactly after 1.5 seconds")
	fixture("CH01")
	check(abilities.try_cast("f", Vector2(480, 350)), "cancelled warrior guard commits its cost")
	abilities.tick(0.119)
	check(room.player.start_dash(Vector2.UP), "real defensive dash cancels warrior preparation")
	abilities.tick(2.0)
	check(Game.run.shield == 0.0 and not room.player.status.has("brace_guard"), "cancelled guard cannot award a free shield or damage prevention")
	check(Game.run.resource == 75.0 and room.player.cooldowns.f == 11.0, "cancelled guard keeps committed rage and cooldown")

func _test_warrior_stronger_guard() -> void:
	fixture("CH01")
	room.player.receive_enemy_status({"id":"damage_reduction", "power":0.50, "duration":0.4})
	room.player.status.tick(0.1)
	check(abilities.try_cast("f", Vector2(480, 350)), "warrior can cast under an existing stronger defense")
	abilities.tick(0.12)
	check(is_equal_approx(incoming(40.0), 20.0), "war cry preserves an existing stronger damage-prevention effect")
	room.player.status.tick(0.301)
	check(is_equal_approx(incoming(40.0), 30.0), "stronger defense expires independently while the warrior's remaining 25-percent guard still protects")
	room.player.status.tick(1.2)
	check(is_equal_approx(incoming(40.0), 40.0), "warrior guard also expires at its own boundary without extending stronger defense")
	fixture("CH01")
	room.player.receive_enemy_status({"id":"damage_reduction", "power":0.20, "duration":4.0})
	room.player.status.tick(0.1)
	check(abilities.try_cast("f", Vector2(480,350)), "warrior guard can overlap a weaker long-lived defense")
	abilities.tick(0.12)
	check(is_equal_approx(incoming(40.0), 30.0), "overlapping warrior guard uses the stronger 25-percent reduction without adding the two reductions")
	room.player.status.tick(1.5)
	check(is_equal_approx(incoming(40.0), 32.0), "weaker defense retains its original strength after warrior guard expires")
	room.player.status.tick(2.401)
	check(is_equal_approx(incoming(40.0), 40.0), "weaker defense retains its original expiry instead of being renewed by war cry")

func _test_warrior_guard_snapshot() -> void:
	fixture("CH01")
	check(abilities.try_cast("f", Vector2(480,350)), "warrior snapshot fixture earns a real guard")
	abilities.tick(0.12)
	room.player.status.tick(0.4)
	var saved: Dictionary = Snapshot.capture(room)
	check(not saved.is_empty(), "active warrior guard is accepted by the safe-boundary snapshot schema")
	if saved.is_empty():
		return
	var replay: Dictionary = JSON.parse_string(JSON.stringify(saved))
	fixture("CH01")
	check(Snapshot.restore(room, replay), "JSON-only snapshot restores warrior guard into another initialized real room")
	check(Game.run.resource == 75.0 and room.player.cooldowns.f == 11.0, "guard restore preserves committed rage and cooldown")
	check(is_equal_approx(incoming(40.0), 30.0), "restored guard still reduces actual incoming damage by one quarter")
	room.player.status.tick(1.1)
	check(is_equal_approx(incoming(40.0), 40.0), "restored guard preserves its remaining 1.1 seconds instead of restarting its duration")

func _test_gunner_grenade_and_combo() -> void:
	fixture("CH02")
	var landing := Vector2(480, 350)
	var target: MineEnemy = dummy(Vector2(500, 350))
	target.armor = 100.0
	var power: float = room.player.skill_power()
	check(abilities.try_cast("f", landing), "gunner throws at valid ground")
	check(Game.run.resource == 70.0 and room.player.cooldowns.f == 12.0, "grenade retains one 30-energy / 12-second commitment")
	abilities.tick(0.149)
	check(deployment("grenade") == null and target.health.current == 10000.0, "grenade does not exist or hit before release")
	abilities.tick(0.001)
	var grenade: HeroDeployment = deployment("grenade")
	check(is_instance_valid(grenade) and deployment("trap") == null, "release places one grenade at the selected landing zone")
	if not is_instance_valid(grenade):
		return
	check(grenade.position == landing, "grenade lands at the validated cursor position")
	grenade.advance(0.649)
	check(target.health.current == 10000.0 and room.player.class_marks.is_empty(), "fuse delay cannot deal damage or mark the target early")
	check(room.player.start_dash(Vector2.UP), "gunner can cancel recovery with a real dash after throwing")
	grenade.advance(0.001)
	check(is_equal_approx(10000.0 - target.health.current, power * 1.1 * 0.5), "grenade blast deals 1.1 attack power as armor-mitigated physical damage")
	check(not target.status.has("chill") and is_equal_approx(target.pending_displacement().length(), 30.0), "gunner grenade pushes 30 pixels without borrowing mage chill")
	check(room.player.class_marks.has(target.get_instance_id()), "confirmed original grenade blast marks its target for follow-up fire")
	check(not grenade.is_alive(), "grenade retires immediately after its single blast")
	var before_followup: float = target.health.current
	room.player._tick_dash(1.0)
	room.player.aim_direction = (target.position - room.player.position).normalized()
	check(abilities.try_cast("secondary", target.position), "gunner follows the grenade with a rail shot")
	abilities.tick(0.66)
	tick_projectiles(0.3)
	check(is_equal_approx(before_followup - target.health.current, power * 3.25 * 0.5), "rail shot consumes the grenade mark for its real 1.25 attack-power bonus")
	check(not room.player.class_marks.has(target.get_instance_id()), "rail shot consumes the mark once")
	var after: float = target.health.current
	grenade.advance(10.0)
	check(target.health.current == after, "retired grenade cannot damage or re-mark its victim later")

func _test_gunner_center_contact() -> void:
	fixture("CH02")
	var landing := Vector2(490,410)
	var thrown_direction: Vector2 = (landing - room.player.position).normalized()
	var target: MineEnemy = dummy(landing)
	check(abilities.try_cast("f", landing), "gunner throws diagonally at an enemy exactly on the landing center")
	abilities.tick(0.15)
	var grenade: HeroDeployment = deployment("grenade")
	check(is_instance_valid(grenade), "center-contact grenade releases normally")
	if not is_instance_valid(grenade):
		return
	grenade.advance(0.65)
	check(target.health.current < 10000.0 and target.pending_displacement().distance_to(thrown_direction * 30.0) < 0.001, "exact-center grenade contact deals damage and pushes 30 pixels along the actual throw direction")

func _test_gunner_empty_and_cancelled() -> void:
	fixture("CH02")
	var landing := Vector2(480, 350)
	check(abilities.try_cast("f", landing), "empty-zone grenade commits")
	abilities.tick(0.15)
	var grenade: HeroDeployment = deployment("grenade")
	check(is_instance_valid(grenade), "empty-zone grenade exists after release")
	if is_instance_valid(grenade):
		grenade.advance(0.65)
		check(not grenade.is_alive() and Game.run.resource == 70.0, "empty zone still spends and retires its grenade at the timed blast")
		var late_target: MineEnemy = dummy(landing + Vector2(20, 0))
		grenade.advance(5.0)
		check(late_target.health.current == 10000.0 and room.player.class_marks.is_empty(), "empty blast leaves no mine for a later arrival")
	fixture("CH02")
	check(abilities.try_cast("f", landing), "pre-release grenade cancellation commits")
	abilities.tick(0.149)
	check(room.player.start_dash(Vector2.UP), "real gunner dash interrupts the throw")
	abilities.tick(3.0)
	check(deployment("grenade") == null and Game.run.resource == 70.0 and room.player.cooldowns.f == 12.0, "cancelled throw creates no delayed grenade and refunds neither cost nor cooldown")

func _test_gunner_ground_and_radius() -> void:
	fixture("CH02")
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(470, 270, 30, 150)])
	for landing: Vector2 in [Vector2(720,350), Vector2(485,350), Vector2(520,350), Vector2(INF,350)]:
		check(not abilities.try_cast("f", landing), "grenade rejects out-of-range, solid, occluded or nonfinite landing")
		check(Game.run.resource == 100.0 and room.player.cooldowns.f == 0.0, "invalid grenade landing leaves energy and cooldown intact")
	fixture("CH02")
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(525, 270, 20, 150)])
	var hidden: MineEnemy = dummy(Vector2(560, 350))
	check(abilities.try_cast("f", Vector2(480,350)), "grenade can land on the visible side of a wall")
	abilities.tick(0.15)
	var grenade: HeroDeployment = deployment("grenade")
	if is_instance_valid(grenade):
		grenade.advance(0.65)
	check(hidden.health.current == 10000.0 and not room.player.class_marks.has(hidden.get_instance_id()), "grenade blast respects wall occlusion for both damage and its mark")
	for level: int in [8,14]:
		fixture("CH02", level)
		var edge: MineEnemy = dummy(Vector2(600, 350))
		check(abilities.try_cast("f", Vector2(480,350)), "grenade radius fixture casts at level " + str(level))
		abilities.tick(0.15)
		grenade = deployment("grenade")
		if is_instance_valid(grenade):
			grenade.advance(0.65)
		check((edge.health.current < 10000.0) == (level == 14), "level-14 grenade reaches a target 120 pixels away while the base grenade cannot")

func _test_mage_field_control() -> void:
	fixture("CH03")
	var landing := Vector2(480, 350)
	var target: MineEnemy = dummy(Vector2(485,350))
	var shielded: MineEnemy = dummy(Vector2(505,350))
	var immune: MineEnemy = dummy(Vector2(515,350))
	var hidden: MineEnemy = dummy(Vector2(580,350))
	immune.apply_status("invulnerable", 1.0, 10.0)
	room.geometry_enabled = true
	room.obstructions.assign([Rect2(540,270,20,150)])
	var power: float = room.player.skill_power()
	check(abilities.try_cast("ultimate", landing), "mage commits a visible field")
	abilities.tick(0.40)
	var field: HeroDeployment = deployment("field")
	check(is_instance_valid(field), "mage release creates a persistent field")
	if not is_instance_valid(field):
		return
	check(target.status.has("shock") and not target.status.has("chill"), "initial impact applies shock before periodic frost control")
	var initial_hp: float = target.health.current
	shielded.status.grant_guard(100.0, 10.0, "fixture", shielded.health.maximum)
	var shielded_hp: float = shielded.health.current
	var initial_shield: float = shielded.status.shield()
	var passive_before: Dictionary = room.player.class_status()
	var resource_before: float = Game.run.resource
	# A direct original packet would add this visible equipment damage. The
	# already-created field must retain its snapshot and derived damage semantics.
	Game.run.stats["true_damage_bonus"] = 50.0
	Game.run.stats["attack"] = 500.0
	Game.run.stats["ability_power"] = 500.0
	field.advance(0.999)
	check(target.health.current == initial_hp and not target.status.has("chill"), "field cannot add an early fractional tick or premature slow")
	field.advance(0.001)
	check(is_equal_approx(initial_hp - target.health.current, power * 0.8), "first field tick deals its captured 0.8 skill power without original equipment bonus")
	check(target.status.has("chill") and target.status.has("shock"), "field tick chills its victim while preserving unconsumed original shock")
	check(shielded.health.current == shielded_hp and is_equal_approx(initial_shield - shielded.status.shield(), power * 0.8) and shielded.status.has("chill"), "real shield absorption also confirms field control")
	check(immune.health.current == 10000.0 and not immune.status.has("chill"), "immune target receives neither field damage nor field chill")
	check(hidden.health.current == 10000.0 and not hidden.status.has("chill"), "wall-occluded target receives neither field damage nor field chill")
	check(Game.run.resource == resource_before and room.player.class_status().current == passive_before.current and room.player.class_status().icd == passive_before.icd, "recurring field damage and chill cannot advance or refund the mage passive")
	target.status.tick(1.0)
	field.advance(1.0)
	check(is_equal_approx(float(target.status.states.chill.remaining), 3.0), "next confirmed field tick refreshes frost control to its normal duration")
	field.advance(3.0)
	check(is_equal_approx(initial_hp - target.health.current, power * 0.8 * 5.0) and not field.is_alive(), "field delivers exactly five authored ticks including expiry then retires")
	var finished_hp: float = target.health.current
	field.advance(10.0)
	check(target.health.current == finished_hp, "retired field produces no additional damage or control")

func _test_mage_field_cancellation() -> void:
	fixture("CH03")
	check(abilities.try_cast("ultimate", Vector2(480,350)), "cancelled mage field commits")
	abilities.tick(0.399)
	check(room.player.start_dash(Vector2.UP), "real mage dodge cancels field preparation")
	abilities.tick(3.0)
	check(deployment("field") == null and Game.run.resource == 40.0 and room.player.cooldowns.ultimate == 48.0, "cancel before impact creates no field and retains committed mana/cooldown")
