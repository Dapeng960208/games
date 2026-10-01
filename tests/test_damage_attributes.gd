extends Node
const Damage = preload("res://scripts/combat/damage_resolver.gd")
const Stats = preload("res://scripts/combat/stat_resolver.gd")
const Status = preload("res://scripts/combat/combat_status.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Effects = preload("res://scripts/combat/equipment_effects.gd")
const Profiles = preload("res://scripts/combat/enemy_profiles.gd")
const RoomScene = preload("res://scenes/room.tscn")
var checks := 0
var failures := 0
var room: MineRoom

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DAMAGE ATTRIBUTES FAIL: " + description)

func near(value: float, expected: float, description: String) -> void:
	check(absf(value - expected) < 0.001, description + " actual=" + str(value) + " expected=" + str(expected))

func test_math() -> void:
	var defense := {"armor":100.0,"magic_resist":25.0,"damage_reduction":0.2}
	near(Damage.resolve(100, "physical", {}, defense).damage, 40, "physical uses armor then universal reduction")
	near(Damage.resolve(100, "magic", {}, defense).damage, 64, "magic uses MR instead of armor")
	near(Damage.resolve(100, "physical", {"armor_penetration":50}, defense).damage, 100.0 / 1.5 * 0.8, "flat armor penetration")
	near(Damage.resolve(100, "magic", {"magic_penetration":25}, defense).damage, 80, "flat magic penetration")
	near(Damage.resolve(100, "physical", {"armor_penetration":500}, defense).damage, 80, "penetration never makes resistance negative")
	near(Damage.resolve(100, "true", {}, defense).damage, 100, "true damage ignores both mitigation layers")
	near(Damage.resolve(100, "true", {}, defense, {"invulnerable":true}).damage, 0, "immunity blocks true damage")
	near(Damage.resolve(100, "physical", {}, {"damage_reduction":2}).damage, 35, "reduction has explicit 65 percent cap")
	near(Damage.resolve(100, "magic", {"crit_multiplier":2.0}, {}, {"critical":true,"already_critical":false}).damage, 200, "explicit unmultiplied critical")
	near(Damage.resolve(100, "magic", {"crit_multiplier":2.0}, {}, {"critical":true}).damage, 100, "room critical cannot multiply twice")
	near(Damage.resolve(NAN).damage, 0, "nonfinite damage is rejected")
	near(Damage.resolve(-4).damage, 0, "negative damage cannot heal")
	near(Damage.healing(100, true), 60, "grievous reduces healing by forty percent")
	near(Damage.healing(INF, true), 0, "nonfinite healing is rejected")
	check(defense.armor == 100 and defense.magic_resist == 25, "resolver leaves caller state unchanged")

func test_status() -> void:
	var status := Status.new()
	status.apply("damage_reduction", 0.9, 2)
	near(status.damage_modifiers().damage_reduction, .65, "status reduction cap")
	status.apply("invulnerable", 0, .6)
	check(status.damage_modifiers().invulnerable, "invulnerability status is active")
	status.grant_guard(20, 3, "test", 100)
	var immune: float = Damage.resolve(30, "true", {}, status.damage_modifiers()).damage
	near(status.absorb(immune), 0, "immune packet causes no health damage")
	near(status.shield(), 20, "immune packet does not consume shield")
	status.tick(.61)
	near(status.absorb(Damage.resolve(30, "true", {}, status.damage_modifiers()).damage), 10, "true damage consumes shield after immunity expires")
	status.apply("grievous", 100, 2)
	near(status.healing_multiplier(), .6, "status healing multiplier")
	status.tick(2.0)
	near(status.healing_multiplier(), 1, "expired grievous restores healing")
	var dot := Status.new()
	for id in ["burn", "corrosion", "bleed"]:
		dot.apply(id, 100, 3)
	var ticks: Array[Dictionary] = dot.tick(1.0)
	check(ticks.size() == 3, "three distinct DoT families tick once per second")
	for tick in ticks:
		near(tick.damage, {"burn":12.0,"corrosion":8.0,"bleed":10.0}[tick.kind], "DoT coefficient " + str(tick.kind))
		check(tick.damage_type == ("magic" if tick.kind == "burn" else "physical"), "DoT damage type " + str(tick.kind))
	check(dot.tick(-1).is_empty(), "negative time cannot generate ticks")

func test_stats() -> void:
	check(Registry.validate().is_empty(), "expanded multi-stat catalog validates")
	var owned := {"EQ04":{"level":0},"EQ14":{"level":0},"EQ24":{"level":0},"EQ54":{"level":0},"EQ05":{"level":0},"EQ09":{"level":0},"EQ08":{"level":0}}
	var magic_items := {"weapon":"EQ04","head":"EQ14","chest":"EQ24","charm":"EQ54"}
	var mage: Dictionary = Stats.resolve("CH03", 8, magic_items, owned)
	var base: Dictionary = Stats.resolve("CH03", 8, {}, {})
	check(mage.ability_power > base.ability_power and mage.magic_resist > base.magic_resist, "caster loadout raises AP and MR")
	near(mage.resource_max - base.resource_max, 75, "mana equipment increases mana capacity")
	near(mage.max_mana, mage.resource_max, "mana display reflects actual capacity")
	near(mage.starting_resource, mage.resource_max, "caster begins with equipment-sized full mana")
	var rage: Dictionary = Stats.resolve("CH01", 8, magic_items, owned)
	near(rage.resource_max, 100, "mana equipment never grants rage capacity")
	near(rage.max_mana, 0, "rage hero has no hidden mana bar")
	var crit: Dictionary = Stats.resolve("CH02", 8, {"weapon":"EQ09"}, owned)
	near(crit.crit_multiplier, 1.7, "equipment improves critical multiplier")
	var true_stats: Dictionary = Stats.resolve("CH01", 8, {"weapon":"EQ08"}, owned)
	near(true_stats.true_damage_bonus, 2, "true damage equipment is a flat value")
	near(Stats.clamp_equipment_contributions({"ability_power":1000,"crit_chance":2,"crit_multiplier":4}).ability_power, 90, "AP cap")

func make_fx(loadout: Dictionary) -> RefCounted:
	var fx := Effects.new()
	fx.configure(loadout, {"attack":30,"max_hp":100,"resource_max":100}, "rage")
	return fx

func hit_context(index: int) -> Dictionary:
	return {"attack_id":"hit%d" % index,"root_event_id":"hit%d" % index,"target_id":"victim","target_states":[],"H":30.0,"X":30.0,"equipment_eligible":true,"original_basic":true,"proc_depth":0,"damage_source":"primary","hp":100.0,"max_hp":100.0}

func test_affixes() -> void:
	var bleed := make_fx({"weapon":"EQ01"})
	var response: Dictionary = {}
	for i in range(3):
		var context := hit_context(i)
		bleed.handle("before_hit", context)
		response = bleed.handle("after_hit", context)
	check(response.statuses.size() == 1 and response.statuses[0].status == "bleed", "third locator hit applies bleed")
	check(bleed.handle("after_hit", hit_context(2)).statuses.is_empty(), "same event cannot apply bleed twice")
	var grievous := make_fx({"weapon":"EQ06"})
	for i in range(3):
		response = grievous.handle("after_hit", hit_context(i))
	check(response.statuses.size() == 2, "corrosion injector emits corrosion and grievous together")
	check(response.statuses[1].status == "grievous", "second injector status is grievous")
	var escort := make_fx({"head":"EQ20"})
	response = escort.handle("dash", {"event_id":"dash1"})
	check(response.self_statuses.size() == 1 and response.self_statuses[0].status == "damage_reduction", "escort grants a real timed status")
	check(escort.handle("dash", {"event_id":"dash2"}).self_statuses.is_empty(), "escort cannot bypass ICD")
	var patchwork := make_fx({"chest":"EQ21"})
	patchwork.handle("room_enter", {"event_id":"entry","room_id":"test"})
	response = patchwork.handle("damaged", {"event_id":"damage1","enemy_damage":true,"hp_damage":10,"hp":25,"max_hp":100})
	check(response.self_statuses.size() == 1 and response.self_statuses[0].status == "invulnerable", "surviving low health triggers brief immunity")
	check(patchwork.handle("damaged", {"event_id":"damage2","enemy_damage":true,"hp_damage":10,"hp":20,"max_hp":100}).self_statuses.is_empty(), "patchwork is once per room")

func test_live_enemy() -> void:
	for action in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_f","ultimate","secondary"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(Game.new_profile() and Game.start_run(), "isolated profile starts")
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	get_tree().root.add_child(room)
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	room.release_gate = false
	for old in room.enemies.get_children(): old.free()
	var enemy: MineEnemy = room.spawn_enemy(Vector2(650,350))
	enemy.health.reset(1000)
	enemy.armor = 100
	enemy.magic_resist = 25
	enemy.status.apply("damage_reduction", .2, 5)
	var before := enemy.health.current
	check(enemy.take_damage(100, &"skill", Vector2.ZERO, {"damage_type":"magic"}), "real enemy accepts magic hit")
	near(before - enemy.health.current, 64, "live enemy uses magic resistance")
	before = enemy.health.current
	enemy.take_damage(100, &"skill", Vector2.ZERO, {"damage_type":"physical","attacker_stats":{"armor_penetration":50}})
	near(before - enemy.health.current, 100.0 / 1.5 * .8, "live enemy consumes attacker penetration")
	enemy.status.grant_guard(30, 5, "test", 1000)
	before = enemy.health.current
	enemy.take_damage(100, &"true", Vector2.ZERO, {"damage_type":"true"})
	near(before - enemy.health.current, 70, "live true damage bypasses reductions but hits shield")
	enemy.status.apply("invulnerable", 1, .5)
	before = enemy.health.current
	check(not enemy.take_damage(100, &"true", Vector2.ZERO, {"damage_type":"true"}), "live enemy invulnerability rejects true damage")
	near(enemy.health.current, before, "invulnerability does not mutate health")
	enemy.status.tick(.6)
	enemy.status.apply("grievous", 1, 3)
	near(enemy.heal(100), 60, "live enemy healing respects grievous")
	enemy.status.apply("corrosion", 10, 4)
	before = enemy.health.current
	enemy.take_damage(100, &"primary", Vector2.ZERO, {"damage_type":"physical"})
	near(before - enemy.health.current, 100.0 / 1.85 * .8, "corrosion removes fifteen percent armor")
	var high: MineEnemy = room.spawn_enemy(Vector2(760,350), "M08", 15)
	var high_profile: Dictionary = Profiles.resolve("M08", 15)
	var low_profile: Dictionary = Profiles.resolve("M08", 1)
	near(high.armor, high_profile.armor, "enemy applies profile armor exactly once")
	near(high.magic_resist, high_profile.magic_resist, "enemy applies profile magic resistance exactly once")
	check(high.magic_resist > float(low_profile.magic_resist) and high.armor > float(low_profile.armor), "enemy tank levels grow both resistances")
	# Use real loadout commands, not a mocked status receiver.
	room.player.loadout._apply_commands({"self_statuses":[{"status":"damage_reduction","power":.12,"duration":2.0}]}, {})
	check(room.player.status.has("damage_reduction"), "loadout status reaches actual player")
	Game.run.hp = Game.run.max_hp - 30
	room.player.status.apply("grievous", 1, 2)
	before = Game.run.hp
	room.player.loadout._apply_commands({"heal_ratio":.1}, {})
	near(Game.run.hp - before, Game.run.max_hp * .06, "equipment healing passes through player grievous multiplier once")
	check(await room.combat_audio.wait_for_cleanup(), "audio playback releases before teardown")
	room.free()
	room = null
	Game.finish_run("abandoned")

func _run() -> void:
	if not Game.profile_path.contains("test_damage_attributes"):
		push_error("Refusing non-test profile")
		get_tree().quit(2)
		return
	test_math()
	test_status()
	test_stats()
	test_affixes()
	await test_live_enemy()
	print("Damage attributes: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
