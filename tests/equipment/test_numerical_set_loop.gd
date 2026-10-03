extends "res://tests/combat/test_numerical_confirmed_casts.gd"
## S07 real S06/EQ38/EQ58 lifecycles. Reuse only the non-stubbed room/receiver
## fixture; cast, primary windup, loadout adapter, health and status are production.
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Stats = preload("res://scripts/domain/combat/stat_resolver.gd")
const SIX: Array[String] = ["EQ08", "EQ18", "EQ28", "EQ38", "EQ48", "EQ58"]

class GateReceiver extends Receiver:
	var wave_icd_before_direct: Array[bool] = []
	func take_damage(amount: float, kind: StringName, direction := Vector2.ZERO, context: Dictionary = {}) -> bool:
		if kind == &"secondary":
			wave_icd_before_direct.append(room.player.loadout.effects.cooldowns.has("S06_6"))
		return super.take_damage(amount, kind, direction, context)

func equipped_fixture(templates: Array[String], hero: String = "CH01") -> void:
	fresh(hero, 20)
	var owned: Dictionary = {}
	var loadout: Dictionary = {}
	for template: String in templates:
		var definition: Dictionary = ContentRegistry.equipment(template, Rules.V2)
		var slot: Dictionary = Rules.value("slots")[definition.slot]
		var rolls: Dictionary = {}
		for key: String in slot.get("shared", slot.get("magic" if hero == "CH03" else "physical", {})):
			rolls[key] = 50
		var id := "set-loop:" + template
		var item: Dictionary = Instances.create({"instance_id":id, "template_id":template, "source_event_id":"test:" + id,
			"item_level":20, "rarity":"white", "power_type":"magic" if hero == "CH03" else "physical", "main_rolls":rolls,
			"affix_type_and_quantile":[], "enhancement_steps":[]})
		check(not item.is_empty(), template + " valid native instance")
		owned[id] = item
		loadout[definition.slot] = id
	game.run.stats = Stats.resolve(hero, 20, loadout, owned, Rules.V2)
	game.run.stats.crit_chance = 0.0
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 1000
	room.player.loadout.configure(room.player)
	check(room.player.loadout.effects.equipped.size() == templates.size(), "real instance binding retains each fixed trait")

func advance_clocks(delta: float) -> void:
	room.player.status.tick(delta)
	game.run.shield = room.player.status.shield()
	room.player.loadout.tick(delta)
	room.player._tick_class_state(delta)
	room.player.shot_cooldown = maxf(0.0, room.player.shot_cooldown - delta)
	for slot: String in room.player.cooldowns:
		room.player.cooldowns[slot] = maxf(0.0, float(room.player.cooldowns[slot]) - delta)
	room.player._tick_attack(delta)

func basic() -> void:
	check(room.player.fire(Vector2.RIGHT), "native basic commits")
	room.player._tick_attack(0.1199)
	check(not room.player.attack_resolved, "basic respects native windup")
	room.player._tick_attack(0.0001)
	check(room.player.attack_resolved, "basic resolves at native release")
	advance_clocks(room.player.stat("attack_interval", 0.5))

func cast(slot: String) -> Dictionary:
	check(room.player.abilities.try_cast(slot, room.player.position + Vector2(80, 0)), "native " + slot + " commits")
	var data: Dictionary = room.player.abilities.active.duplicate(true)
	if not data.is_empty(): tick_cast(float(data.spec.duration) + 0.01)
	return data

func hits(target: Receiver, source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for receipt: Dictionary in target.receipts:
		if receipt.source == source: result.append(receipt)
	return result

func test_active_set_loops() -> void:
	for from_e: bool in [true, false]:
		equipped_fixture(SIX)
		var label := "E then two basics" if from_e else "three basics"
		var flat_hp: int = int(game.run.stats.hero_base.max_hp) + int(game.run.stats.equipment_contribution.max_hp)
		check(game.run.max_hp is int and game.run.max_hp == Rules.integer(flat_hp * 1.10), label + " S06 two-piece HP enters one ratio bucket")
		var targets: Array[Receiver] = []
		for offset: Vector2 in [Vector2(65, 0), Vector2(75, 12), Vector2(85, -12), Vector2(95, 20)]:
			targets.append(dummy(room.player.position + offset))
		if from_e:
			cast("f")
			check(room.player.break_stacks == 1 and room.player.status.guards.has("hero_f"), "E earns break and its real class shield")
		for index: int in (2 if from_e else 3): basic()
		check(room.player.break_stacks == 3, label + " confirmed basics reach full break once per root across victims")
		check(game.run.shield > 0 and is_equal_approx(room.player.loadout.modifiers().damage_bonus, 0.20), label + " class shield opens real four-piece window")
		if not from_e:
			check(room.player.status.guards.has("hero_passive:three_rivets"), "three basics grant native three-rivet shield")
		for target: Receiver in targets: target.receipts.clear()
		var resource_before: int = game.run.resource
		var chain_before: int = room.player.hit_chain.count
		var committed: Dictionary = cast("secondary")
		check(not committed.is_empty() and committed.spec.full_break_w and committed.spec.shielded_cast, label + " W freezes earned full-break and shield conditions")
		check(room.player.break_stacks == 0 and game.run.resource == resource_before, label + " full-break W spends stacks and costs zero")
		var raw: int = Rules.integer(float(committed.spec.coefficient) * float(committed.power))
		var direct_damage: int = Rules.integer(raw * 1.20 * (1.0 + chain_before * 0.005))
		var wave_damage: int = Rules.integer(float(committed.power) * 0.60)
		var wave_count := 0
		for target: Receiver in targets:
			var direct: Array[Dictionary] = hits(target, "secondary")
			check(direct.size() == 1, label + " each real W contact occurs once")
			if not direct.is_empty(): receipt_check(direct[0], direct_damage, label + " W with earned buff")
			for receipt: Dictionary in hits(target, "equipment"):
				wave_count += 1
				receipt_check(receipt, wave_damage, label + " native S06 six-piece wave")
				check(not bool(receipt.context.get("critical", false)) and not bool(receipt.context.get("equipment_eligible", true)) and int(receipt.context.get("proc_depth", 0)) == 1, "wave remains derived without recursive effects")
		check(wave_count == 3 and hits(targets[3], "equipment").is_empty(), label + " wave reaches at most three in stable target order")
		check(is_equal_approx(float(room.player.loadout.effects.cooldowns.get("S06_6", -1.0)) - room.player.loadout.effects.clock, 4.0), "wave starts authored four-second ICD once")
		check(room.player.hit_chain.count == chain_before + 1, "wave does not increase combo or passive roots")

func test_accepted_class_shields() -> void:
	equipped_fixture(["EQ08", "EQ18", "EQ28", "EQ38"])
	var player: HeroActor = room.player
	var amount: int = Rules.integer(game.run.max_hp * 0.08)
	player.grant_guard(game.run.max_hp * 0.35, 30.0, "equipment:cover")
	var pool: int = game.run.shield
	check(not player.loadout.effects.buffs.has("S06_4"), "equipment shield cannot open class window")
	player.grant_guard(amount, 20.0, "hero_passive:three_rivets")
	check(game.run.shield == pool and player.status.guards.has("hero_passive:three_rivets"), "accepted class source is hidden under larger pool")
	check(is_equal_approx(player.loadout.modifiers().damage_bonus, 0.20), "accepted_refresh opens S06 despite no pool increase")
	var first_until: float = player.loadout.effects.buffs.S06_4.until
	advance_clocks(1.0)
	player.grant_guard(amount, 20.0, "hero_passive:three_rivets")
	check(player.loadout.effects.buffs.S06_4.until == first_until, "accepted class refresh respects six-second ICD")
	advance_clocks(5.0)
	player.grant_guard(amount, 20.0, "hero_passive:three_rivets")
	check(game.run.shield == pool and is_equal_approx(player.loadout.effects.buffs.S06_4.until, 10.0), "equal masked refresh reopens at exact six-second boundary")
	advance_clocks(6.0)
	var remaining: float = player.status.guards["hero_passive:three_rivets"].remaining
	player.grant_guard(amount - 1, 30.0, "hero_passive:three_rivets")
	check(not player.loadout.effects.buffs.has("S06_4") and player.status.guards["hero_passive:three_rivets"].remaining == remaining, "rejected weaker source extends neither shield nor S06")
	player.grant_guard(game.run.max_hp * 0.35, 30.0, "equipment:cover")
	check(not player.loadout.effects.buffs.has("S06_4"), "equipment refresh cannot restart expired class window")

func test_shared_health_cap() -> void:
	equipped_fixture(SIX)
	var set_ratio: float = game.run.stats.uncapped_equipment_contribution.hp_ratio
	check(is_equal_approx(set_ratio, 0.10), "real six-piece S06 contributes ten percent to the raw shared bucket")
	# Current legal HP affixes top out below the cap. Exercise future/external
	# bucket contributions without fabricating an attainable over-cap loadout.
	for external_ratio: float in [0.49, 0.50, 0.55, 0.80]:
		var raw := {"hp_ratio":external_ratio + set_ratio}
		var capped: Dictionary = Stats.clamp_equipment_contributions(raw, Rules.V2)
		check(is_equal_approx(capped.hp_ratio, minf(0.60, external_ratio + 0.10)), "S06 plus external health ratios share the same sixty-percent cap: " + str(external_ratio))
		check(is_equal_approx(raw.hp_ratio, external_ratio + 0.10), "health-cap reducer preserves raw contribution for excess reporting")

func test_first_confirmed_w() -> void:
	equipped_fixture(SIX)
	var targets: Array[GateReceiver] = []
	for offset: Vector2 in [Vector2(65, 0), Vector2(75, 10), Vector2(85, 20)]:
		var target := GateReceiver.new()
		target.room = room
		target.position = room.player.position + offset
		target.profile = {"ruleset_version":Rules.V2}
		target.static_actor = true
		target.reward_enabled = false
		target.training_ai_disabled = true
		room.enemies.add_child(target)
		targets.append(target)
	for index: int in 3: basic()
	check(room.player.break_stacks == 3 and game.run.shield > 0, "confirmation fixture earns full-break W and class shield through three actual basics")
	for target: GateReceiver in targets:
		target.receipts.clear()
		target.status.apply("invulnerable", 1, 10)
	var committed: Dictionary = cast("secondary")
	check(committed.spec.full_break_w and committed.spec.shielded_cast, "blocked W commits the earned set conditions")
	check(not room.player.loadout.effects.cooldowns.has("S06_6"), "all-immune W cannot start S06 six-piece ICD")
	for target: GateReceiver in targets:
		check(target.wave_icd_before_direct == [false] and hits(target, "equipment").is_empty(), "immune direct contacts allocate no S06 wave before confirmation")
		var blocked: Array[Dictionary] = hits(target, "secondary")
		check(blocked.size() == 1 and not blocked[0].result.confirmed and blocked[0].loss == 0, "actual W carrier reaches immune receiver without confirming")
	# Re-deliver the exact captured carrier under the same committed root after
	# two receivers become valid. The nearest geometric victim remains immune.
	# This isolates late acceptance without manufacturing another cast or stack.
	for index: int in [1, 2]: targets[index].status.states.erase("invulnerable")
	var release: Dictionary = room.releases.back()
	var resource_before: int = game.run.resource
	room.strike_area(room.player.position, committed.spec.radius, release.amount, &"secondary", "", 0.0, Vector2.RIGHT, committed.spec.arc, true, release.context, true)
	check(targets[0].wave_icd_before_direct == [false, false], "immune first geometric victim still cannot consume set trigger")
	check(targets[1].wave_icd_before_direct == [false, false], "first valid receiver enters before any S06 six-piece ICD")
	check(targets[2].wave_icd_before_direct == [false, true], "later valid receiver observes the single already-consumed set trigger")
	var wave_count := 0
	for target: GateReceiver in targets: wave_count += hits(target, "equipment").size()
	check(wave_count == 3, "one wave emits at most three requests despite multiple valid direct victims")
	check(not hits(targets[0], "equipment")[0].result.confirmed, "derived wave also respects the remaining immune receiver")
	for index: int in [1, 2]:
		receipt_check(hits(targets[index], "equipment")[0], Rules.integer(float(committed.power) * 0.60), "first-confirmed W wave valid receiver")
	check(is_equal_approx(float(room.player.loadout.effects.cooldowns.S06_6) - room.player.loadout.effects.clock, 4.0), "first confirmed W starts one authored four-second wave ICD")
	check(room.player.abilities.cast_serial == 1 and game.run.resource == resource_before, "late same-root confirmation cannot recommit the cast or spend again")

func test_caster_shield_traits() -> void:
	for shielded: bool in [false, true]:
		equipped_fixture(["EQ38", "EQ58"])
		var target: Receiver = dummy(room.player.position + Vector2(65, 0))
		if shielded: room.player.grant_guard(100, 10.0, "fixture:caster")
		else: target.apply_status("chill", 100, 3.0)
		room.player.loadout.event("dash")
		game.run.hp -= 100
		var hp_before: int = game.run.hp
		basic()
		var bonus: Array[Dictionary] = hits(target, "equipment")
		check(bonus.size() == (1 if shielded else 0), "EQ38 uses caster shield, not victim chill")
		check(room.player.status.guards.has("equipment:EQ58") == shielded, "EQ58 uses caster shield, not victim chill")
		check(game.run.hp == hp_before and room.player.loadout.effects.heal_history.is_empty(), "EQ58 never becomes a heal or spends heal budget")
		if shielded:
			receipt_check(bonus[0], Rules.integer(room.player.basic_power() * 0.20), "EQ38 derives from raw X")
			check(room.player.status.guards["equipment:EQ58"].amount == Rules.integer(game.run.max_hp * 0.02), "EQ58 creates exact integer two-percent shield")
			check(is_equal_approx(room.player.status.guards["equipment:EQ58"].remaining, 4.0 - room.player.stat("attack_interval", 0.5)), "EQ58 has four-second source duration")
			check(is_equal_approx(float(room.player.loadout.effects.cooldowns.EQ58), 6.0), "EQ58 uses six-second ICD")
			var expiry: float = room.player.status.guards["equipment:EQ58"].remaining
			basic()
			check(hits(target, "equipment").size() == 1 and room.player.status.guards["equipment:EQ58"].remaining < expiry, "later contacts cannot recurse or refresh equipment ICD")

func test_shared_native_budget() -> void:
	equipped_fixture(["EQ38", "EQ58"])
	var target: Receiver = dummy(room.player.position + Vector2(65, 0))
	var nearby: Receiver = dummy(room.player.position + Vector2(150, 10))
	game.run.relics.assign(["ember", "split", "arc"])
	game.run.shots = 2
	room.player.grant_guard(100, 10.0, "fixture:caster")
	room.player.loadout.event("dash")
	basic()
	var root_id: String = "basic:" + str(room.attack_serial)
	var root: Dictionary = room.player.loadout.effects.roots[root_id]
	var usage: Dictionary = room.player.loadout.effects.root_usage(root_id)
	check(root.reserved.get("relic:ember", false) and root.reserved.get("relic:split", false) and root.reserved.get("relic:arc", false), "real third basic reserves all three native relic packets first")
	check(target.status.has("corrosion") and hits(nearby, "relic_fracture").size() == 1 and room.player.status.guards.has("relic:counterweight"), "native status, relic damage and relic shield really reach receivers")
	check(usage.packets == 4 and hits(target, "equipment").size() == 1, "one equipment packet fills shared four-packet budget")
	check(not room.player.status.guards.has("equipment:EQ58"), "later equipment shield is blocked by full shared budget")
	check(usage.damage_spent == Rules.integer(room.player.basic_power() * 0.20), "native relic damage does not spend equipment amount budget")
	check(room.player.break_stacks == 2 and int(room.player.passives.snapshot().current) == 1, "RL03 cast cadence and extra break remain separate from confirmed passive count")

func test_integer_budget_receivers() -> void:
	# Deliberate boundary packet through the real reducer/adapter: independent
	# X=101 and H_skill=100 make three requests of 60 compete for floor(6X/5)=121.
	# This does not claim that the warrior's W coefficient itself yields X=101.
	equipped_fixture(SIX)
	var targets: Array[Receiver] = []
	for offset: Vector2 in [Vector2(65, 0), Vector2(75, 10), Vector2(85, 20), Vector2(95, 30)]:
		targets.append(dummy(room.player.position + offset))
	var context: Dictionary = {"root_event_id":"integer-boundary", "attack_id":"integer-boundary:0", "target":targets[0], "X":101, "H":100, "H_skill":100,
		"damage_source":"skill", "skill_slot":"secondary", "original_basic":false, "equipment_eligible":true, "proc_depth":0,
		"full_break_w":true, "shielded_cast":true, "confirmed":true, "hp_damage":1, "shield_damage":0}
	room.player.loadout.event("after_hit", context)
	var expected: Array[int] = [60, 60, 1, 0]
	var total := 0
	for index: int in targets.size():
		var packets: Array[Dictionary] = hits(targets[index], "equipment")
		check(packets.size() == (1 if index < 3 else 0), "integer boundary retains stable max-three target order")
		if not packets.is_empty():
			receipt_check(packets[0], expected[index], "integer boundary target " + str(index))
			total += packets[0].loss
	check(total == 121 and room.player.loadout.effects.root_usage("integer-boundary").damage_spent == 121, "actual receivers sum to exact floor six-X-over-five budget")
	room.player.loadout.event("after_hit", context)
	check(hits(targets[0], "equipment").size() == 1, "repeated root cannot spend shared budget again")

func _run() -> void:
	game = get_tree().root.get_node("Game")
	var requested_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="): requested_profile = argument.trim_prefix("--test-profile=")
	if not requested_profile.contains("test_numerical_set_loop") or str(game.profile_path) != requested_profile:
		push_error("Use explicit isolated --test-profile containing test_numerical_set_loop")
		get_tree().quit(2)
		return
	test_active_set_loops()
	test_accepted_class_shields()
	test_shared_health_cap()
	test_first_confirmed_w()
	test_caster_shield_traits()
	test_shared_native_budget()
	test_integer_budget_receivers()
	test_mage_cast_commit()
	test_mage_cast_boundaries()
	test_mage_solar_spell_compatibility()
	test_mage_set_descriptions()
	if is_instance_valid(room): room.free()
	game.run = null
	print("NUMERICAL SET LOOP: %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)

const MAGE_S11: Array[String] = ["EQ73", "EQ74", "EQ75", "EQ76", "EQ77", "EQ78"]
const MAGE_S01: Array[String] = ["EQ03", "EQ13", "EQ23", "EQ33", "EQ43", "EQ53"]
const CAST_COUNT := "S11_6:paid_cast"
const SetDetails = preload("res://scripts/presentation/equipment/equipment_details.gd")

func paid_cast_context(serial: int) -> Dictionary:
	return {"event_id":"paid-fixture:" + str(serial), "root_event_id":"paid-fixture:" + str(serial),
		"slot":"q", "base_cost":40.0, "paid_cost":40.0, "resource_type":"mana", "cast_success":true,
		"damage_source":"skill", "proc_depth":0, "equipment_eligible":true, "original_basic":false,
		"remaining_cooldowns":{"Q":1.0, "right":3.0, "F":2.0, "R":9.0, "dash":20.0}}

func test_mage_cast_commit() -> void:
	for with_targets: bool in [false, true]:
		equipped_fixture(MAGE_S11, "CH03")
		var effects: RefCounted = room.player.loadout.effects
		var targets: Array[Receiver] = []
		if with_targets:
			game.run.stats.branches = {"f":"B"} # Two native E waves still form one cast.
			for offset: Vector2 in [Vector2(65,0), Vector2(75,12), Vector2(85,-12)]:
				targets.append(dummy(room.player.position + offset))
		var before_resource := float(game.run.resource)
		var paid := 0.0
		var cast_index := 0
		for slot: String in ["q", "secondary", "f", "ultimate"]:
			var point := room.player.position + Vector2(80,0)
			var spec: Dictionary = room.player.abilities.spec(slot)
			check(room.player.cast_skill(slot, point), "mage " + slot + " commits without a basic prerequisite")
			var committed: Dictionary = room.player.abilities.active.duplicate(true)
			paid += float(committed.paid_cost)
			cast_index += 1
			check(int(effects.counts.get(CAST_COUNT, 0)) == cast_index % 4, "one paid cast advances one S11 count before any release")
			var expected_cd: float = float(spec.cooldown) - (0.35 if slot == "ultimate" else 0.0)
			check(is_equal_approx(float(room.player.cooldowns[slot]), expected_cd), "fourth cast reduces the already-committed longest cooldown")
			var duplicate := paid_cast_context(100 + cast_index)
			duplicate.root_event_id = "cast_commit:" + str(committed.serial)
			check(effects.handle("skill_cast", duplicate).cooldown_refunds.is_empty() and int(effects.counts.get(CAST_COUNT,0)) == cast_index % 4, "same committed cast cannot recount under another event ID")
			tick_cast(float(committed.spec.duration) + 0.01)
			fly()
			for deployment: Node2D in deployments("node") + deployments("field"):
				if deployment.is_alive(): deployment.advance(1.7)
			fly()
			check(int(effects.counts.get(CAST_COUNT,0)) == cast_index % 4, "Q projectiles, W node, E detonation and R field never add cast counts")
		check(effects.cooldowns.has("S11_6") and effects.refund_history.size() == 1, "four paid casts grant exactly one refund, including legal empty-ground casts")
		check(float(game.run.resource) <= before_resource and paid > 0.0, "real casts paid resources; the refund does not restore resources")
		check(room.player.abilities.cast_serial == 4, "refund and secondary damage never recursively create a cast")
		if with_targets:
			var actual_hits := 0
			for target: Receiver in targets: actual_hits += target.receipts.size()
			check(actual_hits > 4, "multiple real victims and persistent damage were exercised")
		# Failed/previewed attempts never become paid cast events.
		var counter := int(effects.counts.get(CAST_COUNT,0))
		check(not room.player.cast_skill("q", room.player.position), "cooldown rejection stays uncommitted")
		check(int(effects.counts.get(CAST_COUNT,0)) == counter, "rejected cooldown does not advance S11")

func test_mage_cast_boundaries() -> void:
	equipped_fixture(MAGE_S11, "CH03")
	var effects: RefCounted = room.player.loadout.effects
	var point := room.player.position + Vector2(80,0)
	check(room.player.abilities.try_cast("q",point,true) and not effects.counts.has(CAST_COUNT), "cast validation preview never counts")
	game.run.resource = 0
	check(not room.player.cast_skill("q",point) and not effects.counts.has(CAST_COUNT), "resource rejection never counts")
	game.run.resource = 1000
	check(not room.player.cast_skill("secondary",Vector2(INF,0)) and not effects.counts.has(CAST_COUNT), "invalid-ground rejection never counts")
	game.run.level = 1
	check(not room.player.cast_skill("f",point) and not effects.counts.has(CAST_COUNT), "locked spell rejection never counts")
	game.run.level = 20
	for index: int in 4:
		var basic_context := paid_cast_context(90+index)
		basic_context.original_basic = true
		basic_context.damage_source = "primary"
		basic_context.target_id = "basic-fixture"
		check(effects.handle("after_hit",basic_context).cooldown_refunds.is_empty() and not effects.counts.has(CAST_COUNT), "V2 basic hits never advance or refund S11")
	# Historical basic progress must not turn into three prepaid spells.
	effects.counts["S11_6"] = 3
	for invalid: Dictionary in [{"slot":"dash"}, {"paid_cost":0.0}, {"paid_cost":INF}, {"cast_success":false}, {"base_cost":0.0}, {"resource_type":"rage"}, {"proc_depth":1}, {"damage_source":"equipment"}, {"damage_source":"node"}, {"original_basic":true}, {"equipment_eligible":false}]:
		var context := paid_cast_context(10 + checks)
		context.merge(invalid,true)
		check(effects.handle("skill_cast",context).cooldown_refunds.is_empty() and not effects.counts.has(CAST_COUNT), "unpaid, failed, basic and derived events cannot count as paid spells: " + str(invalid))
	for index: int in 4:
		var context := paid_cast_context(index)
		var result: Dictionary = effects.handle("skill_cast",context)
		check(result.cooldown_refunds.size() == (1 if index == 3 else 0), "only every fourth distinct paid cast refunds")
		if index == 3:
			check(result.cooldown_refunds[0].slot == "R" and is_equal_approx(float(result.cooldown_refunds[0].seconds),0.35), "refund selects longest active cooldown, excludes longer dash")
		check(effects.handle("skill_cast",context).cooldown_refunds.is_empty(), "duplicate successful cast callback is idempotent")
	for index: int in 4:
		check(effects.handle("skill_cast",paid_cast_context(20+index)).cooldown_refunds.is_empty(), "five-second internal cooldown blocks rapid four-cast reuse")
	check(int(effects.counts[CAST_COUNT]) == 0, "casts during internal cooldown do not bank a delayed refund")
	effects.advance(5.0,{})
	for index: int in 3: effects.handle("skill_cast",paid_cast_context(30+index))
	effects.refund_history.append({"time":effects.clock,"amount":0.4})
	var capped: Dictionary = effects.handle("skill_cast",paid_cast_context(33))
	check(capped.cooldown_refunds.size() == 1 and is_equal_approx(float(capped.cooldown_refunds[0].seconds),0.1), "S11 shares existing 0.5-second per-second equipment refund cap")
	effects.advance(5.0,{})
	for index: int in 3: effects.handle("skill_cast",paid_cast_context(40+index))
	var short_cd := paid_cast_context(43)
	short_cd.remaining_cooldowns = {"Q":0.07, "dash":20.0}
	var clipped: Dictionary = effects.handle("skill_cast",short_cd)
	check(clipped.cooldown_refunds.size() == 1 and is_equal_approx(float(clipped.cooldown_refunds[0].seconds),0.07), "refund clips to positive remaining cooldown and never creates negative time")
	effects.advance(5.0,{})
	for index: int in 3: effects.handle("skill_cast",paid_cast_context(50+index))
	var ready := paid_cast_context(53)
	ready.remaining_cooldowns = {"Q":0.0,"R":0.0,"dash":20.0}
	check(effects.handle("skill_cast",ready).cooldown_refunds.is_empty(), "all-ready active skills neither refund dash nor bank an award")
	var loadout: Dictionary = game.run.stats.loadout.duplicate()
	loadout.erase("charm")
	var next_stats: Dictionary = game.run.stats.duplicate(true)
	next_stats.loadout = loadout
	next_stats.equipment_templates.erase("charm")
	effects.handle("skill_cast",paid_cast_context(60))
	effects.rebind(loadout,next_stats,"mana")
	check(not effects.counts.has(CAST_COUNT) and effects.cooldowns.has("S11_6"), "breaking six pieces clears cast progress but preserves the internal cooldown")
	# Explicit rule-1 fixture retains the pre-existing basic-hit contract.
	var legacy_loadout := {}
	for id: String in MAGE_S11: legacy_loadout[ContentRegistry.equipment(id).slot] = id
	var legacy := EquipmentEffects.new()
	legacy.configure(legacy_loadout, {"ruleset_version":Rules.LEGACY}, "mana")
	for index: int in 4:
		check(legacy.handle("skill_cast",paid_cast_context(index)).cooldown_refunds.is_empty(), "frozen legacy rules do not gain the new cast proc")
	var refunds := 0.0
	for index: int in 4:
		var context := paid_cast_context(70+index)
		context.original_basic = true
		context.damage_source = "primary"
		context.target_id = "legacy-target"
		for refund: Dictionary in legacy.handle("after_hit",context).cooldown_refunds: refunds += float(refund.seconds)
	check(is_equal_approx(refunds,0.35), "frozen legacy rules retain every-fourth-basic refund")

func test_mage_solar_spell_compatibility() -> void:
	equipped_fixture(MAGE_S01,"CH03")
	var target: Receiver = dummy(room.player.position + Vector2(70,0))
	check(room.player.cast_skill("f",room.player.position), "S01 mage E casts without prior basic attack or node")
	tick_cast(float(room.player.abilities.active.spec.duration) + 0.01)
	check(target.status.has("burn") and room.player.loadout.effects.buffs.has("S01_4"), "original spell applies weapon burn and activates S01 four-piece")
	var context := paid_cast_context(200)
	context.target_id = str(target.get_instance_id())
	context.target_states = ["burn"]
	check(float(room.player.loadout.effects.handle("before_hit",context).damage_bonus) >= 0.08, "S01 two-piece recognizes original skill damage against burn")
	context.X = 1000
	context.nearby_targets = [{"id":"ember-target","distance":10.0,"alive":true}]
	var death: Dictionary = room.player.loadout.effects.handle("kill",context)
	check(death.triggered.has("S01_6") and death.bonus_hits.size() == 1, "S01 six-piece recognizes an original spell kill on burning target")

func test_mage_set_descriptions() -> void:
	for version: int in [Rules.LEGACY, Rules.V2]:
		var definition: Dictionary = ContentRegistry.sets(version).S11.thresholds["6"]
		var stats := {"ruleset_version":version,"sets":{"S11":6}}
		for language: String in ["zh_CN","en"]:
			Words.locale = language
			var expected: String = GameStyle.content_text(definition,"text")
			check(expected.contains("resource-consuming cast") if language == "en" and version == Rules.V2 else expected.contains("消耗资源施法") if version == Rules.V2 else expected.contains("basic hit") if language == "en" else expected.contains("有效普攻"), "set text matches ruleset and language")
			var list := VBoxContainer.new()
			add_child(list)
			SetDetails.set_changes(list,stats,stats,320,"S11")
			var label := list.find_child("SetEffect_S11_6",true,false) as Label
			check(label != null and label.text.contains(expected), "equipment/backpack/comparison detail renders versioned bilingual set rule")
			list.free()
	Words.locale = "zh_CN"
