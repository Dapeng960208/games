extends SceneTree
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func context(source: String = "room", event_id: String = "test:event", difficulty: int = 4) -> Dictionary:
	return {"event_id":event_id, "seed":54873, "source":source, "race_id":"B01", "difficulty":difficulty, "challenge_level":10, "power_type":"physical", "hero_id":"CH01", "wish_slot":"weapon"}

func item_spec(template_id: String = "EQ61", rarity: String = "gold", power: String = "physical", source: String = "drop") -> Dictionary:
	return {"instance_id":"test:instance", "source_event_id":"test:event", "template_id":template_id, "rarity":rarity, "power_type":power, "hero_id":"CH03" if power == "magic" else "CH01", "item_level":20, "source":source}

func sum_weights(weights: Dictionary) -> int:
	var result := 0
	for value: Variant in weights.values(): result += int(value)
	return result

func verify_tickets(weights: Dictionary, label: String) -> void:
	var seen := {}
	for ticket in sum_weights(weights):
		var choice := Acquisition.weighted_ticket(weights, ticket)
		seen[choice] = int(seen.get(choice, 0)) + 1
	for key: String in weights:
		check(int(seen.get(key, 0)) == int(weights[key]), label + " exact tickets " + key)
	check(Acquisition.weighted_ticket(weights, -1).is_empty() and Acquisition.weighted_ticket(weights, sum_weights(weights)).is_empty(), label + " ticket boundaries")

func _initialize() -> void:
	_test_catalog_and_sources()
	_test_probability_tables()
	_test_freezing_and_independence()
	_test_sampling()
	_test_forced_gold()
	_test_reference_equalities()
	_test_historical_stability()
	print("NUMERICAL_ACQUISITION_TESTS checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _test_catalog_and_sources() -> void:
	var snapshot := Rules.parameters()
	var catalog := {}
	for id: String in Registry.equipment_ids(2):
		catalog[id] = Registry.equipment(id, 2)
		for power: String in ["physical", "magic"]:
			check(Instances.legal_affixes(id, power).size() >= 4, "four legal affixes " + id + power)
			var weights := Instances.affix_weights(id, power)
			for key: String in weights:
				check(weights[key] == (2 if key in catalog[id].affix_tendencies else 1), "legal tendency weights " + id + power + key)
			for rarity: String in Acquisition.RARITIES:
				var item := Acquisition.roll_item(item_spec(id, rarity, power), 10394)
				var allowed: Array = catalog[id].allowed_heroes
				if allowed.size() == 1 and power != Registry.ClassPolicy.power_type(str(allowed[0])):
					check(item.is_empty(), "exclusive template rejects wrong stat version " + id + power)
					continue
				check(not item.is_empty() and Instances.validate(item).is_empty(), "all templates/types/rarities " + id + power + rarity)
				if item.is_empty(): continue
				check(item.enhancement_rank <= (1 if rarity == "gold" else 5), "natural enhancement ceiling")
				check(item.enhancement_gold_ledger.is_empty() and item.material_ledger.is_empty(), "free ranks have no payment history")
				check(item.purchase_baseline_gold == Economy.purchase_baseline_price(id, rarity, 20), "canonical frozen purchase baseline")
				for step in item.enhancement_steps.size():
					check(item.enhancement_steps[step].base_price_peak == Economy.enhancement_price(step + 1, 20), "free step retains normative price peak")
				check(item.source_event_id == "test:event" and item.source_metadata.generator_version == Acquisition.GENERATOR_VERSION and item.source_metadata.rules_source_commit == snapshot.source_commit and item.source_metadata.versions.ruleset_version == 2, "source and version frozen")
	for race: String in ["B01", "B02", "B03", "B04"]:
		var pool := Acquisition.natural_pool(race)
		check(pool.size() == 8, "each released race covers eight slots " + race)
		for slot: String in pool:
			for id: String in pool[slot]:
				check(catalog[id].slot == slot and catalog[id].race_id == race and catalog[id].drop_origin == race and not catalog[id].get("shop_only", false), "only same-race natural templates " + id)
		var event := context("room", "race:" + race)
		event.race_id = race
		var result := Acquisition.roll_event(event)
		check(result.ok and result.items.size() == 1 and catalog[result.items[0].template_id].race_id == race, "race event isolation")
	check(Acquisition.natural_pool("B99").is_empty(), "unknown race never falls back")
	var invalid := context()
	invalid.race_id = "B99"
	check(not Acquisition.roll_event(invalid).ok, "empty source pool rejected")
	for source: String in ["purchase", "craft"]:
		var qualities: Array = ["white", "green"] if source == "purchase" else ["green", "purple", "gold"]
		for rarity: String in qualities:
			var item := Acquisition.roll_item(item_spec("EQ73", rarity, "magic", source), 754)
			check(not item.is_empty() and item.enhancement_rank == 0 and item.enhancement_steps.is_empty() and item.location == "inventory", source + " starts at zero")
	check(Acquisition.roll_item(item_spec("EQ61", "gold", "physical", "purchase"), 1).is_empty(), "shop cannot sell gold")
	check(Acquisition.roll_item(item_spec("EQ61", "white", "physical", "craft"), 1).is_empty(), "craft cannot silently substitute white")
	var bad := item_spec()
	bad.enhancement_rank = 5
	check(Acquisition.roll_item(bad, 1).is_empty(), "cannot inject paid history or forced rank")
	for source: String in ["room", "chest", "boss", "summon"]:
		for difficulty in 5:
			var result := Acquisition.roll_event(context(source, source + str(difficulty), difficulty))
			var expected := int(Rules.value("boss_drop_counts")[difficulty]) if source == "boss" else (0 if source == "summon" else 1)
			check(result.ok and result.items.size() == expected and result.triggered == (source != "summon"), "source counts " + source + str(difficulty))
			for item: Dictionary in result.items:
				check(item.item_level == 10 if source == "boss" else item.item_level >= 9 and item.item_level <= 11, "challenge levels")
	for level in [1, 20]:
		for seed in 32:
			var event := context("room", "edge:" + str(seed))
			event.challenge_level = level
			check(Acquisition.roll_event(event).items[0].item_level in ([1, 2] if level == 1 else [19, 20]), "ordinary level clamped to release cap")
	check(Rules.parameters() == snapshot, "generator cannot mutate numerical definitions")
	for id: String in catalog: check(Registry.equipment(id, 2) == catalog[id], "generator cannot mutate catalog " + id)

func _test_probability_tables() -> void:
	verify_tickets(Rules.value("enhancement_random").gain_percent_weights, "g=8..12")
	verify_tickets(Rules.value("item_level_offsets"), "item-level offsets")
	for rarity: String in Acquisition.RARITIES:
		var weights := Acquisition.enhancement_weights(rarity)
		check(sum_weights(weights) == 100, "rank probabilities total 100 " + rarity)
		verify_tickets(weights, "rank " + rarity)
	for source: String in ["normal", "elite", "room", "chest", "boss"]:
		for difficulty in 5:
			var quality := Acquisition.quality_weights(source, difficulty)
			check(sum_weights(quality) == 100, "quality sum " + source + str(difficulty))
			verify_tickets(quality, source + str(difficulty))
			var joint_total := 0
			for rarity: String in quality:
				for rank: String in Acquisition.enhancement_weights(rarity):
					joint_total += int(quality[rarity]) * int(Acquisition.enhancement_weights(rarity)[rank])
			check(joint_total == 10000, "complete quality x rank joint distribution")
	var chances: Dictionary = Rules.value("kill_drop_chance")
	check(chances.normal == 0.01 and chances.elite == 0.15 and chances.summon == 0.0, "natural trigger probabilities")
	check(is_equal_approx(chances.normal * Acquisition.quality_weights("normal", 4).gold / 100.0 * Acquisition.enhancement_weights("gold")["1"] / 100.0, 0.00075), "D4 normal gold+1 raw probability .075 percent")
	check(is_equal_approx(chances.normal * Acquisition.quality_weights("normal", 0).white / 100.0 * Acquisition.enhancement_weights("white")["5"] / 100.0, 0.00012), "D0 normal white+5 raw probability .012 percent")
	var slots := Acquisition.slot_weights(Acquisition.natural_pool("B01"), "weapon")
	verify_tickets(slots, "wish slot")
	check(slots.weapon * 2 == sum_weights(slots), "wish exactly 50 percent")
	for key: String in slots:
		if key != "weapon": check(slots[key] == 1, "others have equal weights")
	check(Acquisition.slot_weights({"feet":["only"]}, "feet") == {"feet":1}, "sole wish slot is certain")
	check(Acquisition.slot_weights({"feet":["x"], "head":["y"]}, "weapon") == {"feet":1, "head":1}, "unavailable wish splits legal slots")
	check(Acquisition.slot_weights({"feet":["x"], "head":["y"]}) == {"feet":1, "head":1}, "unset wish uniform")

func _test_freezing_and_independence() -> void:
	var request := context("boss")
	var unchanged := request.duplicate(true)
	var first := Acquisition.roll_event(request)
	check(first.ok and Acquisition.event_result_valid(first), "fresh event validates by exact deterministic reproduction")
	check(request == unchanged, "request never modified")
	check(Acquisition.roll_event(request) == first and Acquisition.roll_event(request, first) == first, "same event and retry are exactly frozen")
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(first))
	check(Acquisition.event_result_valid(persisted) and Acquisition.roll_event(request, persisted) == persisted, "JSON reload preserves event and RNG result")
	for pair: Array in [["seed", 123], ["event_id", "other"], ["race_id", "B02"], ["difficulty", 3], ["challenge_level", 11], ["power_type", "magic"], ["wish_slot", "feet"], ["force_gold", true], ["source", "room"]]:
		var changed := request.duplicate(true)
		changed[pair[0]] = pair[1]
		check(not Acquisition.roll_event(changed, first).ok, "frozen event rejects context change " + str(pair[0]))
	var tampered := first.duplicate(true)
	tampered.items[0].main_rolls[Instances.main_keys(tampered.items[0].template_id, "physical")[0]] = 37
	check(not Acquisition.event_result_valid(tampered), "tampered frozen attributes rejected")
	tampered.erase("result_fingerprint")
	tampered.result_fingerprint = Acquisition._fingerprint(tampered)
	check(not Acquisition.event_result_valid(tampered), "rehashed changed item still cannot pass deterministic replay")
	var retry := Acquisition.roll_event(request, first)
	retry.items[0].source_metadata.versions.ruleset_version = 900
	retry.items[0].main_rolls.clear()
	check(Acquisition.roll_event(request, first) == first, "mutating returned retry never aliases stored receipt")
	var baseline := Acquisition.roll_item(item_spec(), 91)
	var next_spec := item_spec()
	next_spec.instance_id = "test:second"
	var next := Acquisition.roll_item(next_spec, 91)
	check(baseline.instance_id != next.instance_id and baseline.main_rolls != next.main_rolls, "same template creates independent identity and stream")
	next.main_rolls.clear()
	check(not baseline.main_rolls.is_empty(), "instances do not share nested values")
	seed(873)
	var global_expected := randi()
	seed(873)
	Acquisition.roll_event(request)
	check(randi() == global_expected, "acquisition never advances global combat RNG")
	for index in 50: Acquisition.roll_event(context("room", "unrelated:" + str(index)))
	check(Acquisition.roll_event(request) == first, "unrelated events never perturb frozen stream")
	var no_wish := context()
	no_wish.erase("wish_slot")
	var default_receipt := Acquisition.roll_event(no_wish)
	no_wish.wish_slot = ""
	no_wish.force_gold = false
	check(Acquisition.roll_event(no_wish, default_receipt).ok, "equivalent explicit defaults accepted")

func _test_sampling() -> void:
	var ks := {}; var us := {}; var gs := {}; var ranks := {}; var affix_first := {}; var quality := {}; var slots := {}; var levels := {}
	var samples := 4096
	var template := "EQ61"
	for index in samples:
		var spec := item_spec(template, "purple")
		spec.instance_id = "sampling:" + str(index)
		var item := Acquisition.roll_item(spec, 991)
		for key: String in item.main_rolls: ks[item.main_rolls[key]] = int(ks.get(item.main_rolls[key], 0)) + 1
		for affix: Dictionary in item.affix_type_and_quantile: us[affix.u] = int(us.get(affix.u, 0)) + 1
		for step: Dictionary in item.enhancement_steps: gs[step.g] = int(gs.get(step.g, 0)) + 1
		ranks[item.enhancement_rank] = int(ranks.get(item.enhancement_rank, 0)) + 1
		affix_first[item.affix_type_and_quantile[0].type] = int(affix_first.get(item.affix_type_and_quantile[0].type, 0)) + 1
		if index < 1024:
			var event := Acquisition.roll_event(context("room", "sample:event:" + str(index)))
			var drop: Dictionary = event.items[0]
			quality[drop.rarity] = int(quality.get(drop.rarity, 0)) + 1
			var slot: String = Registry.equipment(drop.template_id, 2).slot
			slots[slot] = int(slots.get(slot, 0)) + 1
			levels[drop.item_level] = int(levels.get(drop.item_level, 0)) + 1
	check(ks.size() == 101 and ks.has(0) and ks.has(100), "all 101 main k outcomes sampled including endpoints")
	check(us.size() == 101 and us.has(0) and us.has(100), "all 101 affix u outcomes sampled including endpoints")
	var total_g := sum_weights(gs)
	for gain: String in Rules.value("enhancement_random").gain_percent_weights:
		check(absf(float(gs.get(int(gain), 0)) / total_g - float(Rules.value("enhancement_random").gain_percent_weights[gain]) / 100.0) < 0.035, "independent initial g distribution " + gain)
	for rank: String in Acquisition.enhancement_weights("purple"):
		check(absf(float(ranks.get(int(rank), 0)) / samples - float(Acquisition.enhancement_weights("purple")[rank]) / 100.0) < 0.035, "initial N distribution " + rank)
	var weights := Instances.affix_weights(template, "physical")
	for key: String in weights:
		check(absf(float(affix_first.get(key, 0)) / samples - float(weights[key]) / sum_weights(weights)) < 0.025, "weighted first affix distribution " + key)
	check(absf(float(slots.get("weapon", 0)) / 1024 - 0.5) < 0.055, "sampled wish 50 percent")
	for rarity: String in Acquisition.quality_weights("room", 4):
		check(absf(float(quality.get(rarity, 0)) / 1024 - float(Acquisition.quality_weights("room", 4)[rarity]) / 100.0) < 0.055, "sampled quality distribution " + rarity)
	for level in [9, 10, 11]: check(absf(float(levels.get(level, 0)) / 1024 - (0.6 if level == 10 else 0.2)) < 0.055, "sampled item-level distribution")
	for source: String in ["normal", "elite", "summon"]:
		var triggered := 0
		for index in 1024:
			var event := Acquisition.roll_event(context(source, "kill:" + source + ":" + str(index)))
			triggered += 1 if event.triggered else 0
		check(absf(float(triggered) / 1024 - float(Rules.value("kill_drop_chance")[source])) < (0.0 + 0.025 if source != "summon" else 0.0001), "sampled natural kill trigger " + source)

func _test_forced_gold() -> void:
	var found := false
	for index in 2048:
		var request := context("boss", "pity:" + str(index))
		var base := Acquisition.roll_event(request)
		var any_gold := false
		for item: Dictionary in base.items: any_gold = any_gold or item.rarity == "gold"
		if any_gold or int(base.items[0].enhancement_rank) != 5: continue
		request.force_gold = true
		var replaced := Acquisition.roll_event(request)
		check(replaced.forced_gold and replaced.items.size() == base.items.size() and replaced.items[0].rarity == "gold" and replaced.items[0].enhancement_rank <= 1, "D4 purple+5 replacement freshly rolls legal gold N")
		check(replaced.items[0].source_metadata.forced_gold and replaced.items[0].enhancement_gold_ledger.is_empty(), "gold replacement is free acquisition with immutable provenance")
		check(Acquisition.roll_event(request, replaced) == replaced, "gold replacement is frozen across retry")
		for other in range(1, base.items.size()):
			check(base.items[other].main_rolls == replaced.items[other].main_rolls and base.items[other].rarity == replaced.items[other].rarity and base.items[other].enhancement_steps == replaced.items[other].enhancement_steps, "forced gold does not perturb other item streams")
		found = true
		break
	check(found, "exercise existing purple+5 D4 replacement")
	var request := context("boss", "already:gold")
	var ordinary := Acquisition.roll_event(request)
	var has_gold := false
	for item: Dictionary in ordinary.items: has_gold = has_gold or item.rarity == "gold"
	check(has_gold, "existing gold fixture")
	request.force_gold = true
	check(not Acquisition.roll_event(request).forced_gold, "do not replace when boss batch already has gold")
	var invalid := context("room")
	invalid.force_gold = true
	check(not Acquisition.roll_event(invalid).ok, "D4 pity does not apply to room drops")
	invalid = context("boss", "wrong:difficulty", 3)
	invalid.force_gold = true
	check(not Acquisition.roll_event(invalid).ok, "D4 pity does not apply to other difficulty")

func reference_item(rarity: String, rank: int) -> Dictionary:
	var item := Acquisition.roll_item(item_spec("EQ61", rarity), 8273)
	for key: String in item.main_rolls: item.main_rolls[key] = 50
	item.enhancement_rank = rank
	item.enhancement_steps = []
	for index in rank: item.enhancement_steps.append({"g":10, "pity":0, "base_price_peak":Economy.enhancement_price(index + 1, 20)})
	return item

func _test_reference_equalities() -> void:
	var white: int = Instances.main_stats(reference_item("white", 5)).attack
	var green3: int = Instances.main_stats(reference_item("green", 3)).attack
	var green5: int = Instances.main_stats(reference_item("green", 5)).attack
	var purple2: int = Instances.main_stats(reference_item("purple", 2)).attack
	var purple5: int = Instances.main_stats(reference_item("purple", 5)).attack
	var gold2: int = Instances.main_stats(reference_item("gold", 2)).attack
	check(white == 263 and green3 == 274 and absf(float(green3) / white - 1.04) < 0.005, "white+5 approximately green+3, about four percent")
	check(green5 == 316 and green5 == purple2, "green+5 equals purple+2")
	check(purple5 == 395 and purple5 == gold2, "purple+5 equals gold+2 after manual enhancement")

func _test_historical_stability() -> void:
	var request := context("boss", "history:v1")
	request.force_gold = true
	var original := Acquisition.roll_event(request)
	var item_request := item_spec("EQ73", "green", "magic", "purchase")
	var bought := Acquisition.roll_item(item_request, 673)
	var old_rules := Rules.parameters()
	var old_catalog := Registry._equipment_v2.duplicate(true)
	# Isolate drift categories without changing version metadata: the creation
	# guard must detect real input changes, not merely the versions field.
	for pair: Array in [["normal_quality_weights", [[0, 0, 0, 100]]], ["drop_enhancement", {"gold":{"0":100}, "non_gold":{"0":100}}], ["main_roll", {"min":0.7, "max":1.3, "steps":100}], ["shop_price_multiplier", {"white":0.8, "green":2.0}], ["wish_slot_chance", 0.75]]:
		var one_change := old_rules.duplicate(true)
		one_change[pair[0]] = pair[1]
		Rules._parameters = one_change
		var current := Acquisition.roll_event(request)
		check(not current.ok and current.error == "generation_version_mismatch", "isolated live drift rejected: " + str(pair[0]))
		Acquisition._validated_fingerprints.clear()
		check(Acquisition.event_result_valid(JSON.parse_string(JSON.stringify(original))), "cold historical replay survives isolated drift: " + str(pair[0]))
	Rules._parameters = old_rules
	Registry._equipment_v2["EQ01"].price = int(Registry._equipment_v2["EQ01"].price) + 1
	check(Acquisition.current_version_error() == "generation_version_mismatch", "catalog-only price drift rejects current generation")
	Acquisition._validated_fingerprints.clear()
	check(Acquisition.event_result_valid(JSON.parse_string(JSON.stringify(original))), "cold historical replay survives catalog-only drift")
	Registry._equipment_v2 = old_catalog.duplicate(true)
	var mutated := old_rules.duplicate(true)
	# Simulate later live balance/schema/template edits, then a saved JSON reload.
	mutated.normal_quality_weights = [[0, 0, 0, 100]]
	mutated.elite_quality_weights = [[0, 0, 0, 100]]
	mutated.boss_quality_weights = [[100, 0, 0, 0]]
	mutated.boss_drop_counts = [1]
	mutated.kill_drop_chance = {"normal":1.0, "elite":1.0, "summon":1.0}
	mutated.drop_enhancement = {"gold":{"5":100}, "non_gold":{"9":100}}
	mutated.enhancement_random.gain_percent_weights = {"8":100}
	mutated.main_roll = {"min":0.5, "max":1.5, "steps":7}
	mutated.rarities.gold.affix_count = 0
	mutated.affixes.attack.slots = []
	mutated.affixes.attack.min = 999
	mutated.affixes.attack.max = 1000
	mutated.slots.weapon.physical = {"armor":500}
	mutated.shop_price_multiplier.green = 5.0
	mutated.cost_item_level_per_level = 0.9
	mutated.enhancement_gold = [1]
	mutated.item_level_offsets = {"0":100}
	mutated.wish_slot_chance = 1.0
	mutated.versions = {"ruleset":3, "equipment_instance":9, "reward_policy":4, "optional_chest_receipt":4, "scale":100}
	mutated.source_commit = "future-version"
	Rules._parameters = mutated
	Registry._equipment_v2 = {"EQ61":{"slot":"head", "price":1, "race_id":"B99", "drop_origin":"B99", "affix_tendencies":[]}}
	Acquisition._validated_fingerprints.clear()
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(original))
	check(Acquisition.event_result_valid(persisted), "historical v1 receipt validates after live rules/catalog changes and JSON reload")
	check(Acquisition.roll_event(request, persisted) == persisted, "historical retry returns saved result across live changes")
	var rejected := Acquisition.roll_event(request)
	check(not rejected.ok and rejected.error == "generation_version_mismatch", "new request rejects unversioned live config/archive drift")
	check(Acquisition.current_version_error() == "generation_version_mismatch", "shared creation gate exposes clear version mismatch")
	check(Acquisition.roll_item(item_request, 673).is_empty(), "new purchase generation rejects unversioned live changes")
	var forged := persisted.duplicate(true)
	forged.items[0].main_rolls[forged.items[0].main_rolls.keys()[0]] = 37
	forged.erase("result_fingerprint")
	forged.result_fingerprint = Acquisition._fingerprint(forged)
	check(not Acquisition.event_result_valid(forged), "history preservation rejects rehashed forged attributes")
	forged = persisted.duplicate(true)
	forged.items[0].purchase_baseline_gold = 1
	forged.erase("result_fingerprint")
	forged.result_fingerprint = Acquisition._fingerprint(forged)
	check(not Acquisition.event_result_valid(forged), "history preservation verifies frozen price baseline")
	forged = persisted.duplicate(true)
	forged.versions.equipment_instance = 9
	forged.erase("result_fingerprint")
	forged.result_fingerprint = Acquisition._fingerprint(forged)
	check(not Acquisition.event_result_valid(forged), "unknown historical schema cannot borrow live versions")
	Rules._parameters = old_rules
	Registry._equipment_v2 = old_catalog
	check(Acquisition.event_result_valid(original), "live data restored after mutation proof")
	check(Acquisition.current_version_error().is_empty() and Acquisition.roll_item(item_request, 673) == bought, "restored authoritative config permits creation again")
