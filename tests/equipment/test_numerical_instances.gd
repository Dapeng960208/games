extends SceneTree
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(template_id: String, rarity: String = "white", power: String = "physical", quantile: int = 50, rank: int = 0, gain: int = 10) -> Dictionary:
	var main := {}
	for key: String in Instances.main_keys(template_id, power): main[key] = quantile
	var affixes: Array = []
	var legal := Instances.legal_affixes(template_id, power)
	var count := int(Rules.value("rarities")[rarity].affix_count)
	for index in count: affixes.append({"type":legal[index], "u":quantile})
	var steps: Array = []
	for index in rank: steps.append({"g":gain, "pity":0, "base_price_peak":0})
	return Instances.create({"instance_id":"fixture:" + template_id + ":" + rarity + ":" + power + ":" + str(quantile), "template_id":template_id, "source_event_id":"fixture:explicit", "item_level":20, "rarity":rarity, "power_type":power, "main_rolls":main, "affix_type_and_quantile":affixes, "enhancement_steps":steps})

func reference_main(base: int, coefficient: int, level: int, quality: int, k: int, total_gain: int) -> int:
	var numerator: int = base * coefficient * (100 + 5 * (level - 1)) * quality * (850 + 3 * k) * (100 + total_gain)
	const DENOMINATOR: int = 10000000000000
	@warning_ignore("integer_division")
	return numerator / DENOMINATOR + (1 if 2 * (numerator % DENOMINATOR) >= DENOMINATOR else 0)

func _initialize() -> void:
	check(Registry.validate().is_empty(), "legacy catalog remains valid")
	check(Registry.validate(2).is_empty(), "version-two catalog validates: " + str(Registry.validate(2)))
	var shop_races := {"S09":"B01", "S10":"B02", "S11":"B01", "S12":"B02", "S13":"B03", "S14":"B04"}
	for set_id: String in shop_races:
		for id: String in Registry.set_item_ids(set_id, 2):
			check(Registry.equipment(id, 2).race_id == shop_races[set_id], "registered shop crafting race " + id)
	for id: String in ["EQ61", "EQ113", "EQ13", "EQ97"]:
		var original: Variant = Registry._equipment_v2[id].race_id
		Registry._equipment_v2[id].race_id = "B04" if original != "B04" else "B01"
		check(not Registry.validate(2).is_empty(), "reject altered shop or natural race " + id)
		Registry._equipment_v2[id].race_id = original
	check(Registry.validate(2).is_empty(), "catalog validation restores without changing legacy definitions")
	check(Registry.equipment_ids().size() == 96 and Registry.slots().size() == 6, "legacy remains 96 templates and six slots")
	check(Registry.equipment_ids(2).size() == 124 and Registry.slots(2).size() == 8, "explicit version two has 124 templates and eight slots")
	check(Registry.equipment("EQ97").is_empty() and Registry.equipment("EQ124").is_empty(), "new IDs never leak into legacy")
	for number in range(1, 15):
		var set_id := "S%02d" % number
		check(Registry.set_item_ids(set_id).size() == 6 and Registry.set_item_ids(set_id, 2).size() == 8, "set slot counts " + set_id)
		check(Registry.sets(2)[set_id].thresholds.keys() == ["2", "4", "6"], "no eight-piece threshold " + set_id)
		check(Registry.equipment("EQ%02d" % (97 + (number - 1) * 2), 2).slot == "legs", "legs ID ordering")
		check(Registry.equipment("EQ%02d" % (98 + (number - 1) * 2), 2).slot == "ring", "ring ID ordering")
	var catalog_copy := Registry.equipment("EQ03", 2)
	catalog_copy.affix_tendencies.clear()
	catalog_copy.legacy_base_stats.ability_power = 999
	check(not Registry.equipment("EQ03", 2).affix_tendencies.is_empty() and Registry.equipment("EQ03").base_stats.ability_power == 12, "template values are deep copies")
	var set_copy := Registry.sets(2)
	set_copy.S01.thresholds["8"] = {}
	check(not Registry.sets(2).S01.thresholds.has("8"), "set values are deep copies")
	var coverage := {}
	for id: String in Registry.equipment_ids(2):
		for power: String in ["physical", "magic"]:
			var legal := Instances.legal_affixes(id, power)
			check(legal.size() >= 4, "at least four legal affixes " + id + power)
			for key: String in legal: coverage[key] = true
			for rarity: String in ["white", "green", "purple", "gold"]:
				for quantile in [0, 50, 100]:
					var record := fixture(id, rarity, power, quantile, 10, 12)
					check(not record.is_empty() and Instances.validate(record).is_empty(), "full catalog explicit fixture " + id + rarity + power + str(quantile))
					if record.is_empty(): continue
					var stats := Instances.stats(record)
					var main := Instances.main_stats(record)
					var template := Registry.equipment(id, 2)
					for key: String in Instances.main_bases(id, power):
						var base := float(Instances.main_bases(id, power)[key])
						var roll: float = 0.85 + 0.003 * quantile
						var rarity_data: Dictionary = Rules.value("rarities")[rarity]
						if key == "move_speed":
							check(is_equal_approx(main[key], base * float(template.main_coefficient) * float(rarity_data.percentage_multiplier) * roll), "percentage main excludes level and enhancement")
						else:
							check(main[key] is int and main[key] == reference_main(int(base), int(round(float(template.main_coefficient) * 1000)), 20, int(round(float(rarity_data.main_multiplier) * 1000)), quantile, 120), "flat main complete formula " + id + key)
					for key: String in Rules.value("affixes"):
						check(stats.has(key), "every stat initialized " + key)
	check(coverage.size() == 21, "all twenty-one legal affixes represented")
	var original := fixture("EQ03", "green")
	var first := Instances.create(original)
	var second := Instances.create(original)
	second.instance_id = "same-template:second"
	second.main_rolls.attack = 100
	second.affix_type_and_quantile[0].u = 100
	var inventory := {first.instance_id:first, second.instance_id:second}
	check(inventory.size() == 2 and first.template_id == second.template_id, "same template creates independent instance ownership")
	check(first.main_rolls.attack == 50 and original.main_rolls.attack == 50 and first.affix_type_and_quantile[0].u == 50, "constructor copies nested rolls independently")
	check(Instances.stats(second).attack > Instances.stats(first).attack, "independent rolls affect real stats")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(inventory))
	check(Instances.validate(roundtrip[first.instance_id]).is_empty() and Instances.stats(roundtrip[first.instance_id]) == Instances.stats(first), "JSON reload preserves exact stats")
	for key: String in Instances.REQUIRED:
		var broken := first.duplicate(true)
		broken.erase(key)
		check(not Instances.validate(broken).is_empty(), "missing required field rejected " + key)
	for mutation in [{"item_level":0}, {"item_level":21}, {"item_level":1.5}, {"power_type":"hybrid"}, {"rarity":"orange"}, {"template_id":"EQ125"}, {"slot":"head"}, {"main_rolls":{}}, {"main_rolls":{"attack":101}}, {"main_rolls":{"attack":NAN}}, {"affix_type_and_quantile":[{"type":"attack","u":50},{"type":"attack","u":50}]}, {"affix_type_and_quantile":[{"type":"ability_power","u":50},{"type":"armor_penetration","u":50}]}, {"enhancement_rank":11}, {"enhancement_rank":1}, {"enhancement_steps":[{"g":7,"pity":0,"base_price_peak":0}],"enhancement_rank":1}, {"enhancement_steps":[{"g":10,"pity":4,"base_price_peak":0}],"enhancement_rank":1}, {"enhancement_steps":[{"g":10,"pity":0,"base_price_peak":-1}],"enhancement_rank":1}, {"lock_state":1}, {"location":"sold"}, {"reforge_slot":2}, {"ruleset_version":1}, {"equipment_instance_version":99}, {"enhancement_gold_ledger":[{"event_id":"pay", "amount":-1}]}, {"material_ledger":[{"event_id":"pay", "amount":2}]}]:
		var broken := first.duplicate(true)
		broken.merge(mutation, true)
		check(not Instances.validate(broken).is_empty() and Instances.create(broken).is_empty() and Instances.stats(broken).is_empty(), "invalid explicit values rejected " + str(mutation))
	for mutation in [{"main_rolls":{1:50}}, {"main_rolls":[]}, {"affix_type_and_quantile":{}}, {"affix_type_and_quantile":[{"type":[],"u":50},null]}, {"affix_type_and_quantile":[{"type":{},"u":50},1]}, {"enhancement_steps":[{"g":{},"pity":0,"base_price_peak":0}], "enhancement_rank":1}, {"enhancement_steps":{}}, {"rarity":null}, {"rarity":[]}, {"power_type":null}, {"source_event_id":42}, {"location":[]}, {"material_ledger":{}}, {"enhancement_reroll_history":[null]}, {"legacy_equip_waiver":null}]:
		var broken := first.duplicate(true)
		broken.merge(mutation, true)
		check(not Instances.validate(broken).is_empty(), "malformed data returns errors without crashing " + str(mutation))
	var perfect_step := fixture("EQ03", "white", "physical", 50, 1, 12)
	check(Instances.validate(perfect_step).is_empty(), "maximum gain with cleared pity remains valid")
	for pity in [1, 2, 3]:
		perfect_step.enhancement_steps[0].pity = pity
		var persisted: Dictionary = JSON.parse_string(JSON.stringify(perfect_step))
		check(not Instances.validate(persisted).is_empty() and Instances.create(persisted).is_empty() and Instances.stats(persisted).is_empty(), "persisted maximum-gain step rejects nonzero pity " + str(pity))
	perfect_step.enhancement_steps[0].g = 11
	check(Instances.validate(perfect_step).is_empty(), "below-maximum gain keeps legal pity-three state")
	for sample in [["EQ31","white",50,0,9,32], ["EQ31","purple",50,10,9,95], ["EQ33","white",25,10,1,56], ["EQ33","purple",100,10,1,104], ["EQ33","green",100,10,6,104], ["EQ33","gold",100,0,13,104]]:
		var halfpoint := fixture(sample[0],sample[1],"physical",sample[2],sample[3])
		halfpoint.item_level = sample[4]
		check(Instances.main_stats(halfpoint).attack == sample[5], "rational main halfpoint independent regression " + str(sample))
	for affix_type: String in Rules.value("affixes"):
		var template_id := ""
		var power := "physical"
		for candidate: String in Registry.equipment_ids(2):
			for candidate_power: String in ["physical","magic"]:
				if affix_type in Instances.legal_affixes(candidate,candidate_power):
					template_id = candidate
					power = candidate_power
					break
			if not template_id.is_empty(): break
		for level in [1,20]:
			for u in [0,50,100]:
				var record := fixture(template_id,"gold",power)
				record.item_level = level
				record.affix_type_and_quantile = [{"type":affix_type,"u":u}]
				for key: String in Instances.legal_affixes(template_id,power):
					if key != affix_type and record.affix_type_and_quantile.size() < 4: record.affix_type_and_quantile.append({"type":key,"u":50})
				var definition: Dictionary = Rules.value("affixes")[affix_type]
				var actual: Variant = Instances.affix_stats(record)[affix_type]
				if definition.scaling == "flat":
					var numerator: int = (int(definition.min)*100+(int(definition.max)-int(definition.min))*int(u))*1875*(100+5*(int(level)-1))
					@warning_ignore("integer_division")
					var expected: int = numerator/10000000+(1 if 2*(numerator%10000000)>=10000000 else 0)
					check(actual is int and actual == expected, "exact rational flat affix " + affix_type)
				else:
					check(is_equal_approx(actual,(float(definition.min)+(float(definition.max)-float(definition.min))*float(u)/100.0)*1.4), "percentage affix excludes level and enhancement " + affix_type)
	var boots := fixture("EQ43", "gold", "physical", 100)
	var upgraded := boots.duplicate(true)
	upgraded.enhancement_rank = 10
	for index in 10: upgraded.enhancement_steps.append({"g":12,"pity":0,"base_price_peak":0})
	check(Instances.main_stats(boots).move_speed == Instances.main_stats(upgraded).move_speed, "shoe speed never gains enhancement")
	check(Instances.affix_stats(boots) == Instances.affix_stats(upgraded), "affixes never gain enhancement")
	for pair in [["white",5,"green",3,263,274], ["green",5,"purple",2,316,316], ["purple",5,"gold",2,395,395]]:
		check(Instances.main_stats(fixture("EQ03",pair[0],"physical",50,pair[1])).attack == pair[4] and Instances.main_stats(fixture("EQ03",pair[2],"physical",50,pair[3])).attack == pair[5], "documented complete-expression reference equivalence")
	var physical := fixture("EQ61", "purple", "physical", 50, 5)
	check(Instances.can_equip(physical,"CH01",20) and not Instances.can_equip(physical,"CH02",20) and not Instances.can_equip(physical,"CH03",20), "warrior set class restriction")
	check(not Instances.can_equip(physical,"CH01",19) and not Instances.can_equip(physical,"CH99",20), "level and hero restriction")
	var low_drop := physical.duplicate(true)
	low_drop.item_level = 1
	check(Instances.can_equip(low_drop,"CH01",1), "pre-enhanced gear is wearable below manual enhancement unlock")
	physical.source_event_id = "migration:test"
	physical.legacy = {"template_id":"EQ61", "referenced_heroes":["CH01","CH03"]}
	physical.legacy_equip_waiver = {"hero_ids":["CH01","CH03"], "type":true, "level":true}
	check(not Instances.can_equip(physical,"CH03",1) and Instances.can_equip(physical,"CH01",1) and not Instances.can_equip(physical,"CH02",1), "retained level waiver cannot bypass current class membership")
	physical.legacy_equip_waiver.type = false
	check(not Instances.can_equip(physical,"CH03",1) and Instances.can_equip(physical,"CH01",1), "type waiver flag independent")
	physical.legacy_equip_waiver.type = true
	physical.legacy_equip_waiver.level = false
	check(not Instances.can_equip(physical,"CH03",1) and not Instances.can_equip(physical,"CH03",20) and Instances.can_equip(physical,"CH01",20), "level waiver cannot bypass current class membership")
	physical.legacy_equip_waiver.hero_ids.append("CH02")
	check(not Instances.validate(physical).is_empty(), "waiver cannot add unreferenced hero")
	physical.legacy_equip_waiver.hero_ids.pop_back()
	physical.source_event_id = "drop:new"
	check(not Instances.validate(physical).is_empty(), "non-migrated drop cannot claim waiver")
	print("Numerical instances: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
