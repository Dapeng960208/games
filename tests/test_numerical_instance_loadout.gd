extends SceneTree
## Explicit v2 equipment identity, aggregation and fixed-trait integration.
const Numbers = preload("res://config/numerical_rules.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Stats = preload("res://scripts/combat/stat_resolver.gd")
const Effects = preload("res://scripts/combat/equipment_effects.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _item(template: String, id: String, power_type: String = "physical", quantile: int = 50, rarity: String = "white", affixes: Array = [], steps: Array = []) -> Dictionary:
	var item: Dictionary = Registry.equipment(template, 2)
	var slot: Dictionary = Numbers.value("slots")[item.slot]
	var rolls: Dictionary = {}
	for key: String in slot.get("shared", slot.get(power_type, {})):
		rolls[key] = quantile
	return Instances.create({"instance_id":id, "template_id":template, "source_event_id":"test:" + id,
		"item_level":20, "rarity":rarity, "power_type":power_type, "main_rolls":rolls,
		"affix_type_and_quantile":affixes, "enhancement_steps":steps})

func _set_loadout(id: String, power_type: String = "physical") -> Dictionary:
	var owned: Dictionary = {}
	var loadout: Dictionary = {}
	for template: String in Registry.set_item_ids(id, 2):
		var instance: String = "fixture:" + template
		owned[instance] = _item(template, instance, power_type)
		loadout[Registry.equipment(template, 2).slot] = instance
	return {"owned":owned, "loadout":loadout}

func _initialize() -> void:
	# Every set really has eight equippable slots; only existing 2/4/6 tiers fire.
	for set_id: String in Registry.sets(2):
		var fixture := _set_loadout(set_id)
		var resolved := Stats.resolve("CH01", 20, fixture.loadout, fixture.owned, 2)
		check(not resolved.is_empty(), set_id + " valid instance stats")
		if resolved.is_empty(): continue
		check(resolved.loadout.size() == 8 and resolved.equipment_templates.size() == 8, set_id + " all eight slots")
		check(resolved.sets[set_id] == 8, set_id + " eight-piece count")
		var binding := Effects.loadout_binding(fixture.loadout, resolved)
		for tier in [2, 4, 6]: check(Effects.source_active(set_id + "_" + str(tier), binding), set_id + " tier " + str(tier))
		check(not Effects.source_active(set_id + "_8", binding), set_id + " no invented eight-piece tier")
		check(binding.instance_loadout == fixture.loadout, set_id + " effect instance identities")
		for slot: String in Registry.slots(2):
			var single := {slot:fixture.loadout[slot]}
			var one := Stats.resolve("CH01", 20, single, fixture.owned, 2)
			var amounts: Dictionary = Instances.stats(fixture.owned[single[slot]])
			check(one.uncapped_equipment_contribution == amounts, set_id + "/" + slot + " exact full instance formula")

	var mix := _set_loadout("S01")
	var second := _set_loadout("S02")
	mix.owned.merge(second.owned)
	for slot: String in ["legs", "ring"]: mix.loadout[slot] = second.loadout[slot]
	var six_two := Stats.resolve("CH01", 20, mix.loadout, mix.owned, 2)
	check(six_two.sets == {"S01":6, "S02":2}, "eight slots support six plus two sets")
	for slot: String in ["feet", "charm"]: mix.loadout[slot] = second.loadout[slot]
	var four_four := Stats.resolve("CH01", 20, mix.loadout, mix.owned, 2)
	var mixed_binding := Effects.loadout_binding(mix.loadout, four_four)
	check(four_four.sets == {"S01":4, "S02":4}, "eight slots support four plus four sets")
	check(not Effects.source_active("S01_6", mixed_binding) and Effects.source_active("S02_4", mixed_binding), "mixed thresholds do not retain removed six-piece effect")

	# A duplicate template is two independent owned items; choosing one neither
	# collapses inventory nor mutates either stored roll dictionary.
	var low := _item("EQ03", "same-template:low", "physical", 0)
	var high := _item("EQ03", "same-template:high", "physical", 100)
	var owned := {low.instance_id:low, high.instance_id:high}
	var original := owned.duplicate(true)
	var lower := Stats.resolve("CH01", 20, {"weapon":low.instance_id}, owned, 2)
	var higher := Stats.resolve("CH01", 20, {"weapon":high.instance_id}, owned, 2)
	check(lower.attack < higher.attack and owned.size() == 2, "same-template instances retain distinct rolls")
	check(lower.loadout.weapon == low.instance_id and higher.equipment_templates.weapon == "EQ03", "instance and trait identities separated")
	check(lower.equipment_contribution.attack == Numbers.integer(90 * 1.95 * .85), "main stat full formula without old static addition")
	check(owned == original, "resolution never mutates instance ownership")
	higher.loadout.weapon = "changed"
	higher.equipment_templates.weapon = "EQ01"
	check(owned == original and lower.loadout.weapon == low.instance_id, "output maps detached from records and other resolves")

	var enhanced := _item("EQ03", "enhanced", "physical", 37, "green",
		[{"type":"attack", "u":73}, {"type":"crit_chance", "u":25}],
		[{"g":8, "pity":0, "base_price_peak":100}, {"g":12, "pity":0, "base_price_peak":100}])
	check(not enhanced.is_empty(), "enhanced affix fixture legal")
	if not enhanced.is_empty():
		var enhanced_stats := Stats.resolve("CH01", 20, {"weapon":"enhanced"}, {"enhanced":enhanced}, 2, {"mastery":5})
		var expected_main := Numbers.integer(90 * 1.95 * 1.2 * (.85 + .003 * 37) * 1.20)
		var expected_affix := Numbers.integer(1.2 * 1.95 * (20 + 20 * .73))
		check(enhanced_stats.equipment_contribution.attack == expected_main + expected_affix, "main rounded once plus separately rounded affix")
		check(enhanced_stats.attack == enhanced_stats.hero_base.attack + expected_main + expected_affix, "talent multiplies hero growth only")
		check(is_equal_approx(enhanced_stats.crit_chance, .05 + 1.1 * (.01 + .02 * .25)), "percentage affix never scaled or enhanced")
		for key: String in Stats.FLAT_KEYS:
			if enhanced_stats.has(key): check(enhanced_stats[key] is int, "flat final integer " + key)
			if enhanced_stats.equipment_contribution.has(key): check(enhanced_stats.equipment_contribution[key] is int, "flat gear integer " + key)

	var health := _item("EQ13", "health", "physical", 50, "green", [{"type":"max_hp", "u":50}, {"type":"hp_ratio", "u":100}])
	var health_stats := Stats.resolve("CH01", 20, {"head":"health"}, {"health":health}, 2, {"vitality":5})
	check(not health_stats.is_empty(), "health ratio fixture legal")
	if not health_stats.is_empty():
		check(health_stats.max_hp == Numbers.integer((int(health_stats.hero_base.max_hp) + int(health_stats.equipment_contribution.max_hp)) * 1.055), "HP ratio applies once after hero talents plus gear flat")

	var magic := _set_loadout("S01", "magic")
	var mage := Stats.resolve("CH03", 20, magic.loadout, magic.owned, 2)
	check(not mage.is_empty() and mage.ability_power > Stats.resolve("CH03", 20, {}, {}, 2).ability_power, "magic main stats activate across eight slots")
	check(Stats.resolve("CH01", 20, magic.loadout, magic.owned, 2).is_empty(), "wrong power type rejected")
	var mana := _item("EQ13", "mana", "magic", 50, "green", [{"type":"max_mana", "u":100}, {"type":"resource_gain_bonus", "u":100}])
	var mana_stats := Stats.resolve("CH03", 20, {"head":"mana"}, {"mana":mana}, 2)
	check(not mana_stats.is_empty(), "mana affixes fixture legal")
	if not mana_stats.is_empty():
		check(mana_stats.resource_max == 1000 + Numbers.integer(1.2 * 1.95 * 160), "mana capacity uses scaled instance units once")
		check(is_equal_approx(mana_stats.resource_gain_bonus, .132), "resource affix remains a percentage")

	check(Stats.resolve("CH01", 20, {"fake":low.instance_id}, owned, 2).is_empty(), "invalid slot rejected")
	check(Stats.resolve("CH01", 20, {"weapon":12}, owned, 2).is_empty(), "invalid loadout value type rejected")
	check(Stats.resolve("CH01", 20, {"head":low.instance_id}, owned, 2).is_empty(), "wrong slot rejected")
	check(Stats.resolve("CH01", 20, {"weapon":low.instance_id}, {}, 2).is_empty(), "unowned instance rejected")
	check(Stats.resolve("CH01", 20, {"weapon":"alias"}, {"alias":low}, 2).is_empty(), "owned key and instance ID mismatch rejected")
	check(Stats.resolve("CH01", 20, {"weapon":low.instance_id, "ring":low.instance_id}, owned, 2).is_empty(), "same instance cannot occupy two slots")
	var broken := low.duplicate(true)
	broken.erase("main_rolls")
	check(Stats.resolve("CH01", 20, {"weapon":low.instance_id}, {low.instance_id:broken}, 2).is_empty(), "missing instance keys rejected")
	check(Stats.resolve("CH01", 20, {"weapon":"EQ03"}, {"EQ03":{"level":5}}, 2).is_empty(), "legacy record cannot enter v2 accidentally")
	check(not Stats.resolve("CH01", 20, {"legs":"", "ring":""}, {}, 2).is_empty(), "empty expanded slots valid")

	# Fixed traits use template IDs while time and ownership survive same-template
	# replacement, and bad instance/stats pairing cannot activate an arbitrary item.
	var fx := Effects.new()
	fx.configure(lower.loadout, lower, "rage")
	check(fx.equipped.has("EQ03") and fx.instance_loadout.weapon == low.instance_id, "fixed trait bound from validated instance")
	var ctx := {"attack_id":"first", "target_id":"enemy", "equipment_eligible":true, "original_basic":true,
		"proc_depth":0, "damage_source":"primary", "target_states":[], "X":300, "H":300}
	var result := fx.handle("after_hit", ctx)
	check(result.statuses.size() == 1 and result.statuses[0].status == "burn", "original template burn fixed trait still fires")
	var before_cooldowns: Dictionary = fx.cooldowns.duplicate(true)
	var next := Stats.resolve("CH01", 20, {"weapon":high.instance_id}, owned, 2)
	fx.rebind(next.loadout, next, "rage")
	check(fx.cooldowns == before_cooldowns and fx.instance_loadout.weapon == high.instance_id, "rebind preserves cooldown and updates instance identity")
	check(Effects.loadout_binding({"weapon":"unowned"}, next).equipped.is_empty(), "mismatched resolved instance cannot bind traits")
	check(owned == original, "events and rebind never mutate records")
	var state := {"clock":1.0, "dash_time":-100.0, "windows":{}, "buffs":{"EQ03":{"amount":.1}}, "counts":{"EQ03":2}, "delayed_shield_at":-1.0}
	var migrated := Effects.for_loadout(state, lower.loadout, next.loadout, lower, next)
	check(migrated.counts.get("EQ03", 0) == 2, "same-template instance swap preserves consumed effect counts")
	var removed := Effects.for_loadout(state, lower.loadout, {}, lower, Stats.resolve("CH01", 20, {}, {}, 2))
	check(removed.counts.is_empty() and state.counts.EQ03 == 2, "removing instance prunes only copied source state")

	var old := Stats.resolve("CH01", 1, {"weapon":"EQ01", "legs":"EQ97", "ring":"EQ98"}, {"EQ01":{"level":1}, "EQ97":{"level":5}, "EQ98":{"level":5}})
	check(old.loadout == {"weapon":"EQ01"} and is_equal_approx(old.equipment_contribution.attack, 4.4), "legacy six-slot arithmetic retained")
	check(not old.has("equipment_templates") and not old.has("talents"), "legacy stat snapshot schema retained")
	var old_fx := Effects.new()
	old_fx.configure({"weapon":"EQ03"}, {"attack":30}, "rage")
	check(old_fx.equipped.has("EQ03") and old_fx.instance_loadout.is_empty(), "legacy trait binding retained")
	print("Numerical instance loadout: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
