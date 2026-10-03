extends Node
## Focused deterministic gear contracts plus real projectile/health integration.
## Uses an isolated managed profile; controlled actor fixtures are not balance play.
const Effects = preload("res://scripts/domain/combat/equipment_effects.gd")
const Catalog = preload("res://scripts/levels/b10/equipment/equipment_catalog.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Transactions = preload("res://scripts/domain/equipment/instance_transactions.gd")
const Forging = preload("res://scripts/domain/equipment/instance_forging.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Numbers = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const AcquisitionPanel = preload("res://scripts/presentation/equipment/instance_acquisition_panel.gd")
const Workshop = preload("res://scripts/presentation/equipment/workshop_panel.gd")
const RoomScene = preload("res://scenes/gameplay/world/room.tscn")
const HEROES := ["CH01", "CH02", "CH03"]
var checks := 0
var failures: Array[String] = []
var serial := 0
var room: RoomController

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func near(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual, expected), label + " actual=" + str(actual) + " expected=" + str(expected))

func ctx(skill: String = "CH01_SK01", extra: Dictionary = {}) -> Dictionary:
	serial += 1
	var id := "b10-gear:" + str(serial)
	var value := {"event_id":id, "attack_id":id, "root_event_id":id, "skill_id":skill,
		"hero_id":skill.left(4), "input_slot":"ultimate", "skill_slot":"ultimate", "slot":"ultimate",
		"target_id":"one", "target_alive":true, "target_states":[], "confirmed":true,
		"hp":500, "max_hp":1000, "shield":0, "resource":0, "resource_max":2000,
		"resource_type":"mana" if skill.begins_with("CH03") else "energy" if skill.begins_with("CH02") else "rage",
		"H":100, "X":300, "attacker_stats":{"attack":100, "ability_power":200},
		"equipment_eligible":true, "original_basic":false, "original":true, "derived":false,
		"damage_source":"skill", "proc_depth":0, "paid_cost":300, "cast_success":true,
		"combat_active":true, "remaining_cooldowns":{"dash":3.0}}
	value.merge(extra, true)
	return value

func fx(hero: String, set_id: String, pieces: int = 6) -> RefCounted:
	var effect := Effects.new()
	effect.stats = {"ruleset_version":2, "hero_id":hero, "attack":100, "ability_power":200, "max_hp":1000}
	effect.resource_type = "mana" if hero == "CH03" else "energy" if hero == "CH02" else "rage"
	if not set_id.is_empty(): effect.set_counts[set_id] = pieces
	return effect

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	if not Game.profile_path.contains("test_b10_equipment_effects"):
		printerr("B10 gear checks require their managed isolated profile")
		get_tree().quit(2)
		return
	check(Game.new_profile(), "fresh isolated gear profile")
	_generation()
	_stable_identities()
	_mage_extended()
	_shared_extended()
	_gunner_packets()
	_unique_effects()
	_finale_fixed_stats()
	await _live_projectiles()
	if is_instance_valid(room):
		check(await room.combat_audio.wait_for_cleanup(), "live combat audio cleanup")
		room.free()
	Game.run = null
	print("B10 EQUIPMENT EFFECTS: %d checks, %d failures: %s" % [checks, failures.size(), failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _generation() -> void:
	check(Catalog.validate().is_empty(), "35 natural templates plus separate fixed reward validate")
	check(ContentRegistry.validate(2).is_empty(), "shared content registry validates")
	check(Acquisition.current_version_error().is_empty(), "prior archives plus separate B10 generator remain compatible")
	check(Catalog.equipment_ids().size() == 36, "B10 catalog has 35 natural and one unique reward")
	for hero: String in HEROES:
		var pool := Acquisition.natural_pool("B10", hero, 5)
		var count := 0
		for ids: Array in pool.values():
			count += ids.size()
			check(not ids.has(Catalog.FINALE_RING_ID), hero + " random pool excludes finale ring")
		check(pool.size() == 8 and count == 19, hero + " class-qualified eight slots / nineteen natural items")
		var catalog_pool := Catalog.natural_pool(hero)
		for slot: String in ContentRegistry.V2_SLOTS:
			var expected: Array = catalog_pool.get(slot, []).duplicate()
			var actual: Array = pool.get(slot, []).duplicate()
			expected.sort()
			actual.sort()
			check(actual == expected, hero + " catalog and generator agree on " + slot + " membership")
		for room_id: String in Acquisition.B10.ROOM_LEVELS:
			var boss := room_id == "BO10"
			var result := Acquisition.roll_event({"event_id":"b10:" + hero + ":" + room_id, "seed":731,
				"source":"boss" if boss else "room", "race_id":"B10", "difficulty":4,
				"challenge_level":Acquisition.B10.ROOM_LEVELS[room_id], "hero_id":hero,
				"power_type":ContentRegistry.ClassPolicy.power_type(hero), "room_id":room_id, "force_gold":boss})
			check(bool(result.get("ok", false)) and Acquisition.event_result_valid(result), hero + " frozen legal event " + room_id)
			for item: Dictionary in result.get("items", []):
				check(Instances.validate(item).is_empty() and item.item_level <= 50 and item.template_id != Catalog.FINALE_RING_ID, "generated chapter item remains legal and excludes special reward")
	for id: String in Catalog.equipment_ids():
		if id == Catalog.FINALE_RING_ID: continue
		var definition := Catalog.equipment(id)
		check(definition.unlock_boss == "BO09", id + " requires previous court boss")
		for hero: String in definition.allowed_heroes:
			var item := Acquisition.roll_item({"instance_id":"fixture:" + id + ":" + hero, "source_event_id":"fixture:b10",
				"template_id":id, "rarity":"gold", "power_type":ContentRegistry.ClassPolicy.power_type(hero),
				"hero_id":hero, "item_level":50, "source":"drop", "location":"inventory"}, 732)
			check(not item.is_empty() and Instances.validate(item).is_empty(), id + " legal complete instance for " + hero)

func _stable_identities() -> void:
	for input: String in ["q", "secondary", "f", "ultimate"]:
		for entry: Array in [["CH01", "B10-SW", "CH01_SK01"], ["CH02", "B10-SG", "CH02_SK02"], ["CH03", "B10-SM", "CH03_SK01"]]:
			var effect := fx(entry[0], entry[1], 2)
			near(effect.handle("before_hit", ctx(entry[2], {"input_slot":input, "skill_slot":input, "slot":input})).damage_bonus, .08, entry[1] + " skill identity survives binding " + input)
			near(effect.handle("before_hit", ctx(entry[0] + "_SK05", {"input_slot":input, "skill_slot":"q", "slot":"q"})).damage_bonus, 0, entry[1] + " SK05 cannot impersonate first skill through input labels")
		var binding := {"input_slot":input, "skill_slot":input, "slot":input}
		var warrior := fx("CH01", "B10-SW")
		warrior.handle("after_hit", ctx("CH01_SK01", binding))
		warrior.handle("after_hit", ctx("CH01_SK02", binding))
		check(int(warrior.counts.get("B10-SW_4:stacks", 0)) == 1, "SW4 stable first-to-second sequence at " + input)
		warrior.handle("skill_cast", ctx("CH01_SK03", binding))
		var out: Dictionary = warrior.handle("after_hit", ctx("CH01_SK02", binding))
		near(out.shield_ratio, .03, "SW6 third identity commits second-hit shield at " + input)
		check(int(warrior.counts.get("B10-SW_4:stacks", 0)) == 0, "SW6 consumes oath once")
		var gunner := fx("CH02", "B10-SG")
		var movement := binding.duplicate()
		movement["actual_distance"] = 120
		gunner.handle("gunner_q_completed", ctx("CH02_SK01", movement))
		gunner.handle("after_hit", ctx("CH02_SK03", binding))
		gunner.handle("after_hit", ctx("CH02_SK02", binding))
		var shot := binding.duplicate()
		shot["r_shot_ordinal"] = 1
		check(gunner.handle("gunner_r_shot", ctx("CH02_SK04", shot)).has("b10_r_bonus"), "SG6 stable 1/3/2/4 chain at " + input)
		var mage := fx("CH03", "B10-SM")
		for id: String in ["CH03_SK01", "CH03_SK02", "CH03_SK03"]: mage.handle("skill_cast", ctx(id, binding))
		check(mage.handle("after_hit", ctx("CH03_SK12", binding)).bonus_hits.is_empty() and mage._window("B10-SM_6:burst"), "SM6 extended skill cannot impersonate first/fourth identity")
		check(mage.handle("after_hit", ctx("CH03_SK04", binding)).bonus_hits.size() == 1, "SM6 stable fourth identity consumes burst at " + input)

func _mage_extended() -> void:
	for extended in range(5, 13):
		var effect := fx("CH03", "B10-SM")
		var first := ctx("CH03_SK%02d" % extended)
		effect.handle("skill_cast", first)
		effect.handle("skill_cast", first)
		effect.handle("skill_cast", ctx("CH03_SK01"))
		check(not effect.cooldowns.has("B10-SM_4"), "SM4 duplicates do not supply third identity")
		near(effect.handle("skill_cast", ctx("CH03_SK04")).resource_restore, Numbers.scale(80, 2), "SM4 includes extended identity " + str(extended))
		var burst: Dictionary = effect.handle("after_hit", ctx("CH03_SK01", {"nearby_targets":[{"id":"two", "distance":20}, {"id":"three", "distance":30}, {"id":"four", "distance":40}]}))
		check(burst.bonus_hits.size() == 1 and burst.bonus_hits[0].target_ids.size() <= 3, "SM6 first original segment owns bounded burst")
		check(effect.handle("after_hit", ctx("CH03_SK01")).bonus_hits.is_empty(), "SM6 subsequent cast cannot replay consumed burst")
	for invalid: Dictionary in [{"derived":true}, {"original":false}, {"proc_depth":1}, {"cast_success":false}, {"paid_cost":0}, {"combat_active":false}]:
		var effect := fx("CH03", "B10-SM")
		for index in [5, 6, 7]: effect.handle("skill_cast", ctx("CH03_SK%02d" % index, invalid))
		check(not effect.cooldowns.has("B10-SM_4") and not effect._window("B10-SM_6:burst"), "SM4 rejected/derived/unpaid context cannot count: " + str(invalid))

func _shared_extended() -> void:
	for hero: String in HEROES:
		for index in range(5, 13):
			var effect := fx(hero, "B10-SU")
			effect.handle("damaged", ctx(hero + "_SK01", {"enemy_damage":true, "shield_broken":true, "shield_absorbed":20}))
			near(effect.skill_cost(100, ctx(hero + "_SK%02d" % index)), 92, "SU4 extended cost preview " + hero + str(index))
			effect.handle("skill_cast", ctx(hero + "_SK%02d" % index, {"paid_cost":0}))
			check(effect._window("B10-SU_4:discount"), "SU4 unpaid cast preserves discount")
			effect.handle("skill_cast", ctx(hero + "_SK%02d" % index))
			check(not effect._window("B10-SU_4:discount"), "SU4 real extended paid cast consumes discount")
			effect.advance(.1, ctx(hero + "_SK01", {"actual_movement_distance":160}))
			effect.handle("after_hit", ctx(hero + "_SK01"))
			near(effect.passive_modifiers(ctx()).b10_direct_damage_reduction, .08, "SU6 real movement/hit/extended submission completes " + hero + str(index))
			near(effect.passive_modifiers(ctx()).move_speed_bonus, .08, "SU6 bounded movement reward")
	for invalid: Dictionary in [{"derived":true}, {"original":false}, {"cast_success":false}]:
		var effect := fx("CH01", "B10-SU")
		effect.handle("damaged", ctx("CH01_SK01", {"enemy_damage":true, "shield_broken":true, "shield_absorbed":20}))
		effect.advance(.1, ctx("CH01_SK01", {"actual_movement_distance":160}))
		effect.handle("after_hit", ctx("CH01_SK01"))
		effect.handle("skill_cast", ctx("CH01_SK12", invalid))
		check(not effect._window("B10-SU_6:balance"), "SU6 rejected submission cannot complete balance")
		check(effect._window("B10-SU_4:discount"), "SU4 rejected or derived cast cannot consume discount")

func arm_gunner(effect: RefCounted) -> void:
	effect.handle("gunner_q_completed", ctx("CH02_SK01", {"actual_distance":120}))
	effect.handle("after_hit", ctx("CH02_SK03"))
	effect.handle("after_hit", ctx("CH02_SK02"))

func _gunner_packets() -> void:
	var effect := fx("CH02", "B10-SG")
	effect.handle("gunner_q_completed", ctx("CH02_SK01", {"actual_distance":0}))
	effect.handle("after_hit", ctx("CH02_SK03"))
	effect.handle("after_hit", ctx("CH02_SK02"))
	check(not effect.handle("gunner_r_shot", ctx("CH02_SK04", {"r_shot_ordinal":1})).has("b10_r_bonus"), "SG6 blocked movement cannot arm emitted bonus")
	effect = fx("CH02", "B10-SG")
	arm_gunner(effect)
	var first := ctx("CH02_SK04", {"r_shot_ordinal":1})
	var total := 0
	for ordinal in range(1, 5):
		var shot := ctx("CH02_SK04", {"root_event_id":first.root_event_id, "r_shot_ordinal":ordinal, "target_id":"other"})
		var out: Dictionary = effect.handle("gunner_r_shot", shot)
		check(out.has("b10_r_bonus") == (ordinal <= 3), "SG6 exact emitted ordinal " + str(ordinal))
		check(out.bonus_hits.is_empty(), "SG6 emitting never applies health damage immediately")
		if out.has("b10_r_bonus"):
			check(out.b10_r_bonus.target_id == "one", "SG6 target binding cannot retarget mid-barrage")
			near(out.b10_r_bonus.damage, 18, "SG6 each actual round uses .18 frozen AD")
			total += int(out.b10_r_bonus.damage)
		check(not effect.handle("gunner_r_shot", shot).has("b10_r_bonus"), "SG6 duplicate emission cannot repeat ordinal")
	check(total <= int(Numbers.derived_budget(300, 2)), "SG6 three packages stay in shared derived damage budget")
	effect = fx("CH02", "B10-SG")
	arm_gunner(effect)
	check(not effect.handle("gunner_r_shot", ctx("CH02_SK04", {"r_shot_ordinal":2})).has("b10_r_bonus"), "SG6 later ordinal cannot invent cancelled first round")
	for invalid: Dictionary in [{"derived":true}, {"original":false}, {"proc_depth":1}, {"equipment_eligible":false}, {"skill_id":"CH02_SK11"}]:
		effect = fx("CH02", "B10-SG")
		arm_gunner(effect)
		var rejected := invalid.duplicate()
		rejected["r_shot_ordinal"] = 1
		check(not effect.handle("gunner_r_shot", ctx("CH02_SK04", rejected)).has("b10_r_bonus") and not effect.cooldowns.has("B10-SG_6"), "SG6 rejects derived or unrelated emitted receipt " + str(invalid))
	effect = fx("CH02", "B10-SG")
	arm_gunner(effect)
	first = ctx("CH02_SK04", {"r_shot_ordinal":1})
	check(effect.reserve_native(first.root_event_id, "native", 1.1), "shared native reservation accepted")
	total = 0
	for ordinal in range(1, 4):
		var out: Dictionary = effect.handle("gunner_r_shot", ctx("CH02_SK04", {"root_event_id":first.root_event_id, "r_shot_ordinal":ordinal}))
		if out.has("b10_r_bonus"): total += int(out.b10_r_bonus.damage)
	check(total <= 30 and effect.root_usage(first.root_event_id).damage_spent <= int(Numbers.derived_budget(300, 2)), "SG6 respects already spent native budget")

func _unique_effects() -> void:
	var effect := fx("CH01", "")
	effect.equipped["B10-U01"] = true
	effect.handle("ordinary_slow_ended", ctx("CH01_SK01", {"actually_slowed":true}))
	var refunds: Array = effect.handle("dash", ctx()).cooldown_refunds
	check(refunds.size() == 1, "U01 produces one actual dash refund")
	if refunds.size() == 1: near(refunds[0].seconds, .5, "U01 actual ordinary slow end returns half-second dash budget")
	effect = fx("CH01", "")
	effect.equipped["B10-U02"] = true
	near(effect.handle("hostile_shield_broken", ctx("CH01_SK01", {"player_attributed":true})).shield_ratio, .03, "U02 attributable break grants bounded shield")
	effect = fx("CH01", "")
	effect.equipped["B10-U03"] = true
	effect.handle("ordinary_forced_movement_ended", ctx("CH01_SK01", {"actual_enemy_forced_movement":true}))
	near(effect.passive_modifiers(ctx()).b10_direct_damage_reduction, .06, "U03 ordinary displacement recovery adds bounded direct reduction")

func _finale_fixed_stats() -> void:
	check(not AcquisitionPanel.creation_ids(false).has(Catalog.FINALE_RING_ID), "actual shop/craft creation list excludes reward-only template")
	var shop := Workshop.new()
	shop.mode = "shop"
	check(not shop._filtered_equipment().has(Catalog.FINALE_RING_ID), "actual workshop shop list excludes reward-only template")
	shop.free()
	check(Instances.make_finale_ring("", "CH01").is_empty() and Instances.make_finale_ring("fixture:finale", "CH99").is_empty(), "fixed reward constructor rejects invalid provenance")
	for hero: String in HEROES:
		var ring := Instances.make_finale_ring("fixture:" + hero + ":finale_ring", hero)
		check(not ring.is_empty() and Instances.validate(ring).is_empty(), hero + " fixed finale constructor creates legal instance")
		if ring.is_empty(): continue
		check(ring.instance_id == "instance:finale:ring" and ring.rarity == "gold" and ring.item_level == 50 and ring.lock_state, "fixed unique identity, quality, level and initial lock")
		check(ring.source_kind == "finale_reward" and ring.source_metadata == {"generator_version":5, "reward_id":"B10-D4-FINALE"} and ring.allowed_heroes == HEROES, "fixed reward retains universal eligibility provenance")
		check(ring == Instances.make_finale_ring(ring.source_event_id, hero), "fixed constructor repeats identical record without a random roll")
		var values := Instances.stats(ring)
		check(values == Catalog.FINALE_STATS and values.size() == ContentRegistry.STAT_KEYS.size(), "fixed reward has precisely all nineteen authored attributes")
		for key: String in ContentRegistry.STAT_KEYS: check(float(values.get(key, 0)) > 0, hero + " fixed positive stat " + key)
		var loadout := {"ring":ring.instance_id}
		var owned := {ring.instance_id:ring}
		for wearer: String in HEROES:
			check(Instances.can_equip(ring, wearer, 50), "ring can transfer across class " + wearer)
			var stats := Resolver.resolve(wearer, 50, loadout, owned, 2)
			check(not stats.is_empty(), wearer + " real resolver accepts universal ring")
			if stats.is_empty(): continue
			for key: String in ContentRegistry.STAT_KEYS: near(float(stats.equipment_contribution.get(key, 0)), float(values[key]), wearer + " real contribution " + key)
			var baseline := Resolver.resolve(wearer, 50, {}, {}, 2)
			for key: String in ["attack", "ability_power", "max_hp", "armor", "magic_resist", "armor_penetration", "magic_penetration", "true_damage_bonus", "crit_multiplier", "crit_chance", "cooldown_reduction", "damage_bonus", "damage_reduction", "burn_damage", "corrosion_damage_bonus", "status_duration"]:
				near(float(stats[key]) - float(baseline[key]), float(values[key]), wearer + " actual resolved addition " + key)
			near(stats.attack_speed_bonus - baseline.attack_speed_bonus, values.attack_speed, wearer + " actual attack speed addition")
			near(stats.move_speed_bonus - baseline.move_speed_bonus, values.move_speed, wearer + " actual movement speed addition")
			# Mana is retained as a contribution for every class; only CH03 uses it.
			near(stats.resource_max - baseline.resource_max, values.max_mana if wearer == "CH03" else 0, wearer + " native resource remains class appropriate")
			check(stats.crit_chance <= .75 and stats.cooldown_reduction <= .4 and stats.damage_reduction <= .35, wearer + " resolved percentages respect caps")
		var altered := ring.duplicate(true)
		altered.main_rolls.attack = 99
		check(not Instances.validate(altered).is_empty(), "fixed stats cannot be rerolled through record edits")
		var profile: Dictionary = Game.profile.duplicate(true)
		profile.selected_hero = hero
		profile.hero_xp[hero] = int(Game.Progression.thresholds().back())
		profile.equipment[ring.instance_id] = ring
		var request := {"hero_id":hero, "template_id":Catalog.FINALE_RING_ID, "rarity":"white", "power_type":ring.power_type, "item_level":50}
		check(Transactions.quote_purchase(profile, request).get("error") == "REWARD_ONLY_TEMPLATE", "reward cannot be purchased")
		request.rarity = "gold"
		check(Transactions.quote_craft(profile, request).get("error") == "REWARD_ONLY_TEMPLATE", "reward cannot be crafted")
		check(Acquisition.roll_item({"instance_id":"fake", "source_event_id":"fake", "template_id":Catalog.FINALE_RING_ID, "rarity":"gold", "power_type":ring.power_type, "item_level":50, "hero_id":hero, "source":"drop"}, 1).is_empty(), "reward cannot be explicit randomly generated drop")
		for kind: String in ["sell", "dismantle", "enhance", "enhancement_reroll", "reforge", "resolve_reforge", "refine"]:
			var operation := {"hero_id":hero, "instance_id":ring.instance_id}
			if kind == "enhancement_reroll": operation["rank"] = 1
			if kind in ["reforge", "refine"]: operation["affix_index"] = 0
			if kind == "reforge": operation["affix_type"] = "attack"
			if kind == "resolve_reforge": operation.merge({"pending_operation_id":"fixture:pending", "choice":"keep"})
			check(Forging.quote(profile, kind, operation).get("error") == "FIXED_FINALE_REWARD", "reward rejects workshop operation " + kind)
		var ordinary := Acquisition.roll_item({"instance_id":"fixture:ordinary:" + hero, "source_event_id":"fixture:ordinary",
			"template_id":"B10-SU-ring", "rarity":"white", "power_type":ring.power_type, "item_level":50,
			"hero_id":hero, "source":"drop", "location":"inventory"}, 1)
		check(not ordinary.is_empty() and Instances.validate(ordinary).is_empty(), "legal ordinary ring for inheritance guard")
		if not ordinary.is_empty():
			profile.equipment[ordinary.instance_id] = ordinary
			for source: String in [ring.instance_id, ordinary.instance_id]:
				var target: String = ordinary.instance_id if source == ring.instance_id else ring.instance_id
				check(Forging.quote(profile, "inherit", {"hero_id":hero, "source_instance_id":source, "target_instance_id":target}).get("error") == "FIXED_FINALE_REWARD", "reward cannot be source or target of inheritance")
		profile.equipment[ring.instance_id] = ring.duplicate(true)
		profile.equipment[ring.instance_id].lock_state = false
		for kind: String in ["sell", "dismantle"]:
			check(Forging.quote(profile, kind, {"hero_id":hero, "instance_id":ring.instance_id}).get("error") == "FIXED_FINALE_REWARD", "unique reward guard persists when UI lock is removed: " + kind)

func _live_fixture() -> bool:
	if Game.run == null and not Game.start_run(): return false
	var owned := {}
	var loadout := {}
	for slot: String in ContentRegistry.V2_SLOTS:
		var id := "B10-SG-" + ("accessory" if slot == "charm" else slot)
		var item := Acquisition.roll_item({"instance_id":"b10-live:" + slot, "source_event_id":"b10-live:fixture", "template_id":id,
			"rarity":"white", "power_type":"physical", "hero_id":"CH02", "item_level":50, "source":"drop", "location":"inventory"}, 100)
		if item.is_empty(): return false
		owned[item.instance_id] = item
		loadout[slot] = item.instance_id
	Game.run.hero_id = "CH02"
	Game.run.level = 50
	Game.run.frozen_versions = Numbers.frozen_versions(2)
	Game.run.stats = Resolver.resolve("CH02", 50, loadout, owned, 2)
	Game.run.stats.crit_chance = 0.0
	Game.run.loadout_snapshot = loadout
	Game.run.equipment_snapshot = owned
	Game.run.skill_loadout_snapshot = ["CH02_SK04", "CH02_SK03", "CH02_SK02", "CH02_SK01"]
	Game.run.skill_branches_snapshot = {"CH02_SK01":"", "CH02_SK04":""}
	Game.run.relics.clear()
	Game.run.max_hp = Game.run.stats.max_hp
	Game.run.hp = Game.run.max_hp
	Game.run.resource = Game.run.stats.resource_max
	Game.run.shield = 0
	room = RoomScene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = false
	room.release_gate = false
	room.combat_audio.audible = false
	for actor: Node in room.enemies.get_children(): actor.free()
	room.player.position = Vector2(600, 450)
	room.player.aim_direction = Vector2.RIGHT
	return true

func _target(offset: Vector2) -> EnemyActor:
	var enemy := room.spawn_enemy(room.player.position + offset, "M01") as EnemyActor
	enemy.health.reset(1000000)
	enemy.armor = 0
	enemy.magic_resist = 0
	enemy.reward_enabled = false
	enemy.training_ai_disabled = true
	enemy.rank = "boss"
	return enemy

func _emit(seconds: float) -> void:
	var remaining := seconds
	while remaining > .000001:
		var delta := minf(.01, remaining)
		room.player.abilities.tick(delta)
		room.player.loadout.tick(delta)
		remaining -= delta

func _live_arm(target: EnemyActor) -> void:
	room.player.loadout.event("gunner_q_completed", ctx("CH02_SK01", {"actual_distance":120}))
	for index in [3, 2]:
		var context := ctx("CH02_SK%02d" % index, {"target":target, "target_id":str(target.get_instance_id()), "attacker_stats":Game.run.stats, "input_slot":"secondary" if index == 3 else "f"})
		check(room.resolve_direct_hit(target, 100, &"skill", "", 0, Vector2.RIGHT, context), "controlled confirmed real adapter hit SK" + str(index))

func _live_projectiles() -> void:
	if not _live_fixture(): check(false, "legal live SG fixture"); return
	var first := _target(Vector2(100, 0))
	var other := _target(Vector2(200, 0))
	await get_tree().physics_frame
	_live_arm(first)
	check(room.player.skill_id_for_slot("q") == "CH02_SK04", "live actor reverse input binding owns stable barrage identity")
	check(room.player.cast_skill("q", first.position), "real reverse-bound barrage accepted: " + room.player.last_cast_error)
	_emit(2.5)
	var shots: Array[Node] = []
	for projectile: Node in room.projectiles.get_children():
		if str(projectile.options.get("skill_id", "")) == "CH02_SK04": shots.append(projectile)
	check(shots.size() >= 4, "production gunner kit actually emits at least four barrage rounds")
	if shots.size() < 4: return
	var bonuses := 0
	var bonus_damage := 0
	for index in shots.size():
		var bonus: Dictionary = shots[index].options.get("b06_r_bonus", {})
		if bonus.is_empty(): continue
		bonuses += 1
		bonus_damage += int(bonus.damage)
		check(index < 3 and bonus.r_shot_ordinal == index + 1 and bonus.target_id == str(first.get_instance_id()), "real emitted ordinal and bound target")
		near(bonus.damage, Numbers.integer(float(Game.run.stats.attack) * .18), "real projectile carries .18 frozen AD supplement")
	check(bonuses == 3, "exactly three emitted live barrage bonus packets")
	var root_id: String = str(shots[0].options.get("root_event_id", ""))
	var usage: Dictionary = room.player.loadout.effects.root_usage(root_id)
	var basis: float = maxf(float(shots[0].options.get("H", 0.0)), float(Game.run.stats.attack))
	check(not root_id.is_empty() and int(usage.packets) <= 4 and float(usage.coefficient) <= 1.200001 and bonus_damage <= int(Numbers.derived_budget(basis, 2)), "real emitted supplements obey the shared packet and derived damage budgets")
	var first_packets: Array[float] = []
	var other_packets: Array[float] = []
	first.health.damaged.connect(func(amount: float): first_packets.append(amount))
	other.health.damaged.connect(func(amount: float): other_packets.append(amount))
	shots[0].hit(first)
	check(first_packets.size() == 2, "confirmed bound hit applies direct plus equipment health packet")
	if first_packets.size() == 2: near(first_packets[1], shots[0].options.b06_r_bonus.damage, "live extra health loss matches reserved supplement")
	var after := first.health.current
	shots[0].hit(first)
	near(first.health.current, after, "repeat callback cannot damage twice")
	shots[1].hit(other)
	check(other_packets.size() == 1, "redirected round has no supplement on other target")
	shots[2].hit(first)
	check(first_packets.size() == 4, "third actual bound round applies its one supplement")
	shots[3].hit(first)
	check(first_packets.size() == 5, "fourth actual round applies only direct packet")
	check(await room.combat_audio.wait_for_cleanup(), "emitted barrage fixture audio cleanup")
	room.free()
	room = null
	if not _live_fixture(): check(false, "fresh real cancellation fixture"); return
	first = _target(Vector2(100, 0))
	await get_tree().physics_frame
	_live_arm(first)
	var hp: float = first.health.current
	check(room.player.cast_skill("q", first.position), "fresh real barrage accepts before cancellation")
	room.player.abilities.cancel()
	_emit(2.5)
	check(room.projectiles.get_child_count() == 0, "cancelled barrage cannot invent un-emitted projectiles")
	near(first.health.current, hp, "cancelled un-emitted rounds cause no health damage")
	check(not room.player.loadout.effects.cooldowns.has("B10-SG_6"), "cancel before emission spends no SG6 internal cooldown")
	check(room.player.loadout.effects._window("B10-SG_6:ready:" + str(first.get_instance_id())), "cancel before emission preserves existing bound target")
	room.player.cooldowns["CH02_SK04"] = 0.0
	Game.run.resource = Game.run.stats.resource_max
	check(room.player.cast_skill("q", first.position), "real barrage after cancelled fixture accepts")
	_emit(2.5)
	var immune_shot: Node = null
	for projectile: Node in room.projectiles.get_children():
		if not projectile.options.get("b06_r_bonus", {}).is_empty(): immune_shot = projectile; break
	check(is_instance_valid(immune_shot), "immune-contact fixture owns an actually emitted bonus round")
	if is_instance_valid(immune_shot):
		check(first.apply_status("invulnerable", 1.0, 5.0), "real target enters invulnerability")
		hp = first.health.current
		immune_shot.hit(first)
		near(first.health.current, hp, "unconfirmed immune contact cannot apply direct or reserved equipment damage")
