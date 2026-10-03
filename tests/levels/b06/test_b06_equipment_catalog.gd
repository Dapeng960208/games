extends SceneTree
## Pure staged-catalog checks; no Game singleton, profile storage or live acquisition.
const Catalog = preload("res://scripts/levels/b06/equipment/equipment_catalog.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var errors := Catalog.validate()
	check(errors.is_empty(), "authored schema: " + str(errors))
	check(Catalog.validate(Catalog.catalog()).is_empty(), "detached identical contract validates")
	check(Catalog.equipment_ids().size() == 35, "35 distinct B06 templates")
	check(Catalog.sets().size() == 4, "four B06 sets")
	check(not Catalog.catalog().runtime_enabled, "catalog does not activate gameplay")
	for number in range(1, 125):
		check("EQ%02d" % number not in Catalog.equipment_ids(), "legacy ID remains separate EQ%02d" % number)
	pool_and_power_contract()
	stat_and_effect_contract()
	malformed_contracts()
	copy_isolation()
	print("B06 equipment catalog: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func pool_and_power_contract() -> void:
	for hero: String in Catalog.HEROES:
		var pool := Catalog.natural_pool(hero)
		var count := 0
		check(pool.size() == 8, hero + " eight-slot pool")
		for slot: String in Catalog.SLOTS:
			check(pool.has(slot) and not pool[slot].is_empty(), hero + " nonempty " + slot)
			for id: String in pool.get(slot, []):
				count += 1
				check(Catalog.equipment(id).slot == slot and hero in Catalog.allowed_heroes(id), "legal natural member " + hero + id)
		check(count == 19, hero + " exactly 19 templates")
		for id: String in Catalog.equipment_ids():
			var binding := Catalog.bind_generation(id, hero)
			var legal: bool = hero in Catalog.allowed_heroes(id)
			check(binding.is_empty() != legal, "generation enforces every slot " + hero + id)
			if not legal: continue
			check(Catalog.validate_binding(binding).is_empty(), "valid generation intent " + id)
			check(binding.power_type == ("magic" if hero == "CH03" else "physical"), "natural power choice " + hero + id)
			var before := binding.duplicate(true)
			for wearer: String in Catalog.HEROES:
				check(Catalog.can_equip(binding, wearer) == (wearer in Catalog.allowed_heroes(id)), "full-slot class qualification " + wearer + id)
			check(binding == before, "equip cannot rewrite fixed power " + id)
	for group: String in ["SW", "SG", "SM", "SU"]:
		var jewelry := Catalog.equipment("B06-" + group + "-accessory")
		check(jewelry.id.ends_with("-accessory") and jewelry.slot == "charm", "preserve design ID and map accessory " + group)
		check(Catalog.equipment("B06-" + group + "-charm").is_empty(), "no alias duplicate " + group)
	for id: String in ["B06-SU-weapon", "B06-SU-ring", "B06-U01", "B06-U02", "B06-U03"]:
		for power: String in ["physical", "magic"]:
			var record := {"catalog_version":1, "template_id":id, "power_type":power}
			for hero: String in Catalog.HEROES:
				check(Catalog.can_equip(record, hero), "same universal fixed instance fits " + id + power + hero)
			check(record.power_type == power, "cross-class does not convert " + id + power)

func stat_and_effect_contract() -> void:
	var slot_rules: Dictionary = Rules.value("slots")
	var affix_rules: Dictionary = Rules.value("affixes")
	for id: String in Catalog.equipment_ids():
		var item := Catalog.equipment(id)
		check(item.base_stats.is_empty() and item.main_coefficient == 1.0, "no doubled/discounted main budget " + id)
		for power: String in item.power_types:
			check(Catalog.main_bases(id, power) == slot_rules[item.slot].get("shared", slot_rules[item.slot].get(power, {})), "inherited mains " + id + power)
			var legal := Catalog.legal_affixes(id, power)
			var expected: Array[String] = []
			for key: String in affix_rules:
				if item.slot in affix_rules[key].slots and affix_rules[key].get("power_type", power) == power: expected.append(key)
			check(legal == expected, "exact inherited legal affixes " + id + power)
			var weights := Catalog.affix_weights(id, power)
			for key: String in Catalog.affix_tendencies(id, power):
				check(key in legal, "tendency remains legal " + id + power + key)
			for key: String in weights:
				check(weights[key] == Rules.value("affix_tendency_weight" if key in Catalog.affix_tendencies(id, power) else "affix_default_weight"), "no new weighting economy " + id + key)
	for sid: String in Catalog.sets():
		var definition: Dictionary = Catalog.sets()[sid]
		check(definition.thresholds.size() == 3 and definition.thresholds.has_all(["2", "4", "6"]), "no eight-piece threshold " + sid)
		check(not definition.runtime_implemented, "set not advertised as implemented " + sid)
		for effect: Dictionary in definition.thresholds.values(): check(not effect.runtime_implemented, "threshold not activated " + sid)
	var sets := Catalog.sets()
	check(sets["B06-SW"].thresholds["2"].parameters.distance_reduction == 0.25, "SW shield requires real active E")
	check(sets["B06-SW"].thresholds["4"].parameters.actual_w_cost_refund_ratio == .15 and "actual_rage_spent_positive" in sets["B06-SW"].thresholds["4"].conditions, "SW refunds actual paid W only")
	check(sets["B06-SW"].thresholds["6"].parameters.range == 120 and sets["B06-SW"].thresholds["6"].parameters.target_cap == 3, "SW actual absorption retaliation bounds")
	check(sets["B06-SG"].thresholds["4"].parameters.e_cooldown_reduction_seconds == 1 and sets["B06-SG"].thresholds["4"].parameters.icd_seconds == 7, "SG Q to marked W grants E reduction")
	check(sets["B06-SG"].thresholds["6"].parameters.projectile_count == 3 and not sets["B06-SG"].thresholds["6"].parameters.cancelled_shots_count, "SG counts actually fired R projectiles")
	check(sets["B06-SM"].thresholds["2"].parameters.radius_bonus == .1 and not sets["B06-SM"].thresholds["2"].parameters.expands_persistent_node, "SM only immediate W radius")
	check(sets["B06-SM"].thresholds["6"].parameters.paid_q_count == 3 and sets["B06-SM"].thresholds["6"].parameters.delay_seconds == .8, "SM paid casts and delayed ring")
	check("no_automatic_node_stacks" in sets["B06-SM"].thresholds["6"].conditions, "SM no node recursion or auto attacks required")
	check(sets["B06-SU"].thresholds["4"].parameters.period_seconds == 12 and "equipment_change_does_not_reset_clock" in sets["B06-SU"].thresholds["4"].conditions, "SU shield cannot be refreshed by equip")
	check("unequip_does_not_trigger" in sets["B06-SU"].thresholds["6"].conditions, "SU retaliation has real source-specific expiry")
	check(Catalog.equipment("B06-U03").unique_effect.parameters.icd_seconds == 15, "U03 completed drain interaction")

func malformed_contracts() -> void:
	for hero: String in ["", "CH04", "ch01"]:
		check(Catalog.natural_pool(hero).is_empty() and Catalog.bind_generation("B06-SU-weapon", hero).is_empty(), "invalid hero fails closed " + hero)
	check(Catalog.bind_generation("EQ01", "CH01").is_empty(), "released catalog not claimed by staged binder")
	for power: String in ["", "true", "physical ", "magic"]:
		check(Catalog.main_bases("B06-SW-weapon", power).is_empty(), "exclusive invalid power rejects " + power)
		check(Catalog.legal_affixes("B06-SW-weapon", power).is_empty(), "invalid affix power rejects " + power)
	for invalid: Variant in [null, [], {}, {"catalog_version":true,"template_id":"B06-SU-head","power_type":"physical"}, {"catalog_version":1,"template_id":"B06-SM-ring","power_type":"physical"}, {"catalog_version":1,"template_id":"B06-SU-ring","power_type":[]}, {"catalog_version":1,"template_id":"B06-SU-ring","power_type":"magic","hero_id":"CH03"}]:
		check(not Catalog.validate_binding(invalid).is_empty(), "invalid generation intent")
		check(not Catalog.can_equip(invalid, "CH01"), "malformed binding cannot equip")
	for malformed: Variant in [[], {}, {"equipment":[]}]: check(not Catalog.validate(malformed).is_empty(), "malformed catalog rejected")
	var mutations: Array = []
	var changed := Catalog.catalog(); changed.runtime_enabled = true; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-SW-ring"].allowed_heroes = Catalog.HEROES.duplicate(); mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-SG-feet"].affix_tendencies_by_power.physical = ["cooldown_reduction"]; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-SU-weapon"].affix_tendencies_by_power.physical = ["ability_power"]; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-SW-accessory"].slot = "accessory"; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-U01"].price = 60; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-U02"].main_coefficient = NAN; mutations.append(changed)
	changed = Catalog.catalog(); changed.sets["B06-SW"].thresholds["8"] = {}; mutations.append(changed)
	changed = Catalog.catalog(); changed.sets["B06-SM"].thresholds["4"].parameters.mana_restore = 600; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-U03"].unique_effect.runtime_implemented = true; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-U03"].base_stats = {"attack":90}; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-U03"].allowed_heroes = null; mutations.append(changed)
	changed = Catalog.catalog(); changed.equipment["B06-U03"].affix_tendencies_by_power = []; mutations.append(changed)
	changed = Catalog.catalog(); changed.effect_contract.shield_stack_rule = "add"; mutations.append(changed)
	for mutant: Dictionary in mutations: check(not Catalog.validate(mutant).is_empty(), "contract mutation rejected")

func copy_isolation() -> void:
	var before := Catalog.catalog()
	var detached := Catalog.catalog(); detached.equipment.clear(); detached.sets.clear()
	var item := Catalog.equipment("B06-SU-head"); item.allowed_heroes.clear(); item.affix_tendencies_by_power.magic.clear()
	var detached_sets := Catalog.sets(); detached_sets["B06-SW"].thresholds["4"].parameters.power_coefficient = 999
	var allowed := Catalog.allowed_heroes("B06-SU-head"); allowed.clear()
	var pool := Catalog.natural_pool("CH01"); pool.weapon.clear()
	var mains := Catalog.main_bases("B06-SU-weapon", "physical"); mains.attack = 999
	var tendencies := Catalog.affix_tendencies("B06-SU-head", "magic"); tendencies.clear()
	check(Catalog.catalog() == before, "all public nested results detached")
	check(Catalog.main_bases("B06-SU-weapon", "physical").attack == 90, "numerical source not mutated")
	check(Catalog.natural_pool("CH01").weapon.size() == 2, "pool copy did not change next query")
