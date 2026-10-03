extends SceneTree
const Forge = preload("res://scripts/domain/equipment/instance_forging.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Creation = preload("res://scripts/domain/equipment/instance_transactions.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Migration = preload("res://scripts/infrastructure/persistence/numerical_migration.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
var checks := 0
var failures: Array[String] = []
var serial := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL: ", label)

func fixture(level: int = 20) -> Dictionary:
	var loadout := {}
	for slot: String in Registry.slots(2): loadout[slot] = ""
	return {"ruleset_version":2, "selected_hero":"CH01", "hero_xp":{"CH01":Growth.thresholds()[level - 1], "CH02":0, "CH03":0},
		"equipment":{}, "bosses":["BO01", "BO02", "BO03", "BO04"], "permanent_gold":10000000,
		"materials":{"forge":100000, "race:B01":100000, "race:B02":100000, "race:B03":100000, "race:B04":100000,
			"core:B01":10000, "core:B02":10000, "core:B03":10000, "core:B04":10000}, "loadout":loadout, "talents":{},
		"applied_transactions":{"starter_grant_v1":{"kind":"starter"}}}

func item(id: String = "item", template: String = "EQ01", level: int = 20, gains: Array = [], rarity: String = "green") -> Dictionary:
	var record := Acquisition.roll_item({"instance_id":id, "source_event_id":"fixture:" + id, "template_id":template,
		"item_level":level, "power_type":"physical", "rarity":rarity, "source":"purchase" if rarity in ["white", "green"] else "craft", "location":"inventory"}, 421)
	record.enhancement_rank = gains.size()
	record.enhancement_steps = []
	for index in gains.size(): record.enhancement_steps.append({"g":gains[index], "pity":0, "base_price_peak":Economy.enhancement_price(index + 1, level)})
	return record

func request(id: String = "item", extra: Dictionary = {}) -> Dictionary:
	var result := {"hero_id":"CH01", "instance_id":id}
	result.merge(extra)
	return result

func inherit_request(source: String = "source", target: String = "target") -> Dictionary:
	return {"hero_id":"CH01", "source_instance_id":source, "target_instance_id":target}

func commit(profile: Dictionary, kind: String, spec: Dictionary, operation: String = "") -> Dictionary:
	serial += 1
	var result := Forge.transact(profile, operation if not operation.is_empty() else "test:" + str(serial), kind, spec)
	check(result.ok, kind + " commits " + str(result.error))
	if not result.ok:
		quit(1)
		return profile
	check(Forge.validate_profile(result.profile).is_empty(), kind + " candidate validates " + Forge.validate_profile(result.profile))
	return result.profile

func reject(profile: Dictionary, kind: String, spec: Dictionary, label: String, operation: String = "rejected") -> void:
	var before := JSON.stringify(profile)
	var result := Forge.transact(profile, operation, kind, spec)
	check(not result.ok and JSON.stringify(profile) == before, label + " rejects without touching input")

func op_for(profile: Dictionary, kind: String, spec: Dictionary, minimum: int, maximum: int) -> String:
	for attempt in 10000:
		var operation := "chosen:" + str(serial) + ":" + str(attempt)
		var ticket := Forge._ticket(operation, kind, spec, Forge._items(profile, spec), 100)
		if ticket >= minimum and ticket <= maximum:
			serial += 1
			return operation
	check(false, "deterministic ticket search")
	return "missing"

func _initialize() -> void:
	if "--stress-storage" in OS.get_cmdline_user_args():
		test_storage_envelope()
		print("FORGING STORAGE: ", checks - failures.size(), "/", checks, " failures=", failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	test_probabilities_and_bounds()
	test_enhancement_and_pity()
	test_inheritance_and_refunds()
	test_reforge_and_refine()
	test_migration_and_corruption()
	print("FORGING: ", checks - failures.size(), "/", checks, " passed; failures=", failures.size())
	for failure: String in failures: print("  ", failure)
	quit(0 if failures.is_empty() else 1)

func test_probabilities_and_bounds() -> void:
	var tickets := [9, 10, 29, 30, 69, 70, 89, 90, 99]
	var expected := [8, 9, 9, 10, 10, 11, 11, 12, 12]
	for index in tickets.size(): check(Forge.gain_for_ticket(tickets[index]) == expected[index], "RF01 ticket " + str(tickets[index]))
	var distribution := {8:0, 9:0, 10:0, 11:0, 12:0}
	for ticket in 100: distribution[Forge.gain_for_ticket(ticket)] += 1
	check(distribution == {8:10, 9:20, 10:40, 11:20, 12:10}, "RF01 exact natural distribution")
	check(Forge.gain_for_ticket(-1) == -1 and Forge.gain_for_ticket(100) == -1, "invalid ticket rejected")
	for rarity: String in ["white", "green", "purple", "gold"]:
		var weights := Acquisition.enhancement_weights(rarity)
		var ranks := {}
		for ticket in 100:
			var rank := int(Acquisition.weighted_ticket(weights, ticket))
			ranks[rank] = true
			check(rank >= 0 and rank <= (1 if rarity == "gold" else 5), "RF04 legal generated drop boundary " + rarity)
		check(ranks.size() == (2 if rarity == "gold" else 6), "RF04 every legal drop rank reachable " + rarity)
		for source: String in (["purchase"] if rarity == "white" else (["purchase", "craft"] if rarity == "green" else ["craft"])):
			var generated := Acquisition.roll_item({"instance_id":rarity + source, "source_event_id":"test", "template_id":"EQ01", "item_level":20, "power_type":"physical", "rarity":rarity, "source":source, "location":"inventory"}, 17)
			check(not generated.is_empty() and generated.enhancement_rank == 0, "RF04 all crafted/purchased ranks zero " + rarity)
	var record := item("additive", "EQ21", 20, [8, 9, 10])
	var flat := Instances.main_stats(record)
	for key: String in flat:
		var baseline := record.duplicate(true)
		baseline.main_rolls[key] = 50
		var bases := Instances.main_bases(record.template_id, record.power_type)
		var k := int(record.main_rolls[key])
		var exact := float(bases[key]) * float(Registry.equipment(record.template_id, 2).main_coefficient) * 1.95 * 1.2 * (0.85 + 0.003 * k) * 1.27
		check(flat[key] == Rules.integer(exact), "RF03 additive 1.27 complete-expression integer " + key)

func test_enhancement_and_pity() -> void:
	var profile := fixture()
	profile.equipment["item"] = item("item", "EQ21")
	var original := profile.duplicate(true)
	var quote := Forge.quote(profile, "enhance", request())
	check(quote.ok and not quote.has("candidate") and profile == original, "quote is detached and reveals no free candidate")
	var result := Forge.transact(profile, "first-enhance", "enhance", request("item", {"expected_revision":0}))
	check(result.ok, "RF02 enhancement initial result " + str(result.error))
	if not result.ok: return
	profile = result.profile
	var updated: Dictionary = profile.equipment["item"]
	check(updated.enhancement_steps.size() == 1 and updated.enhancement_rank == 1, "RF02 one shared main step")
	check(updated.main_rolls == original.equipment["item"].main_rolls and updated.affix_type_and_quantile == original.equipment["item"].affix_type_and_quantile, "RF02/RF03 k and u never rerolled")
	for key: String in Instances.main_stats(updated):
		check(Instances.main_stats(updated)[key] >= Instances.main_stats(original.equipment["item"])[key], "RF02 all three main attributes improve " + key)
	check(original.equipment["item"].enhancement_rank == 0, "immutable input")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(profile))
	check(Forge.validate_profile(restored).is_empty(), "RF16 reload validates sealed receipt")
	var replay := Forge.transact(restored, "first-enhance", "enhance", request("item", {"expected_revision":0}))
	check(replay.ok and replay.replayed and replay.profile == restored and Forge._hash(replay.receipt) == Forge._hash(result.receipt), "RF16 committed retry no charge or roll")
	var failed_save_retry := Forge.transact(original, "first-enhance", "enhance", request("item", {"expected_revision":0}))
	check(failed_save_retry.receipt == result.receipt and failed_save_retry.profile == profile, "RF16 failed-save deterministic candidate")
	reject(profile, "enhance", request("item", {"expected_revision":0}), "RF16 stale item version")
	reject(profile, "enhance", request(), "RF16 reused operation conflict", "first-enhance")
	for i in range(2, 11): profile = commit(profile, "enhance", request())
	check(original.permanent_gold - profile.permanent_gold == 3930, "RF09 Lv20 exact sum3930")
	check(original.materials.forge - profile.materials.forge == 107 and original.materials["race:B01"] - profile.materials["race:B01"] == 26 and original.materials["core:B01"] - profile.materials["core:B01"] == 3, "RF09 exact 107/26/3 materials")
	reject(profile, "enhance", request(), "RF09 +10 maximum")
	var full_salvage := Forge.quote(profile, "dismantle", request())
	check(full_salvage.ok and full_salvage.materials_return == {"forge":57, "race:B01":14}, "RF18 refund53/13 plus green base4/1; never core3")
	check(Forge.quote(profile, "sell", request()).gold_return == 814, "RF18 sale28 base +786 real enhancement investment")
	var pity := fixture(10)
	pity.equipment["item"] = item("item", "EQ01", 1, [11])
	for i in 3:
		var spec := request("item", {"rank":1})
		pity = commit(pity, "enhancement_reroll", spec, op_for(pity, "enhancement_reroll", spec, 0, 89))
		check(pity.equipment["item"].enhancement_steps[0].g == 11 and pity.equipment["item"].enhancement_steps[0].pity == i + 1, "RF05 no improvement pity=" + str(i + 1))
	check(Forge.quote(pity, "enhancement_reroll", request("item", {"rank":1})).guaranteed, "RF05 fourth quote guarantees improvement")
	pity = commit(pity, "enhancement_reroll", request("item", {"rank":1}), "guaranteed-fourth")
	check(pity.equipment["item"].enhancement_steps[0].g == 12 and pity.equipment["item"].enhancement_steps[0].pity == 0, "RF05 fourth gives12 resets pity")
	check(pity.forging_transactions.operations["guaranteed-fourth"].result.ticket == -1, "RF05 guaranteed step consumes no random draw")
	check(pity.equipment["item"].enhancement_reroll_history.size() == 4, "RF05 failed attempts retained")
	reject(pity, "enhancement_reroll", request("item", {"rank":1}), "RF08 maximum g no charge")
	var improve := fixture(10)
	improve.equipment["item"] = item("item", "EQ01", 1, [10])
	for i in 2:
		var spec := request("item", {"rank":1})
		improve = commit(improve, "enhancement_reroll", spec, op_for(improve, "enhancement_reroll", spec, 0, 69))
	var improve_spec := request("item", {"rank":1})
	improve = commit(improve, "enhancement_reroll", improve_spec, op_for(improve, "enhancement_reroll", improve_spec, 70, 89))
	check(improve.equipment["item"].enhancement_steps[0].g == 11 and improve.equipment["item"].enhancement_steps[0].pity == 0 and improve.equipment["item"].enhancement_reroll_history.size() == 3, "RF06 lucky improvement resets count; failed history remains")
	check(improve.permanent_gold == fixture().permanent_gold - 60, "RF06 cost once each")
	reject(improve, "enhancement_reroll", request("item", {"rank":2}), "RF07 nonexistent rank")
	var empty := fixture(10)
	empty.equipment["item"] = item()
	reject(empty, "enhancement_reroll", request("item", {"rank":1}), "RF08 N0")
	for pair in [[1, 0], [4, 0], [5, 3], [9, 3], [10, 5], [14, 5], [15, 8], [19, 8], [20, 10]]:
		check(Forge.manual_cap(pair[0]) == pair[1], "manual gate " + str(pair))
	var low := fixture(5)
	low.equipment["item"] = item("item", "EQ01", 1, [8, 8, 8, 8, 8])
	reject(low, "enhance", request(), "legal drop rank not manually extendable")
	check(low.equipment["item"].enhancement_rank == 5 and Instances.can_equip(low.equipment["item"], "CH01", 5), "drop5 remains equipable without manual5")
	reject(low, "enhancement_reroll", request("item", {"rank":1}), "reroll hero10 gate")
	var rank_gate := fixture(10)
	rank_gate.equipment["item"] = item("item", "EQ01", 1, [8, 8, 8, 8, 8, 8])
	reject(rank_gate, "enhancement_reroll", request("item", {"rank":6}), "reroll rank exceeds manual cap")
	var shoes := fixture()
	shoes.equipment["item"] = item("item", "EQ41", 1)
	var shoe_before: Dictionary = shoes.equipment["item"].duplicate(true)
	shoes = commit(shoes, "enhance", request())
	check(Instances.main_stats(shoes.equipment["item"]).move_speed == Instances.main_stats(shoe_before).move_speed and Instances.affix_stats(shoes.equipment["item"]) == Instances.affix_stats(shoe_before), "RF21 shoe percentage and ordinary affixes unchanged")
	check(Registry.equipment(shoes.equipment["item"].template_id, 2) == Registry.equipment(shoe_before.template_id, 2), "RF21 fixed template traits unaffected")
	# The glove's low flat attack can gain potential without crossing an integer.
	var potential := fixture()
	potential.equipment["item"] = item("item", "EQ31", 1, [8], "white")
	potential.equipment["item"].main_rolls.attack = 0
	var stats_before := Instances.main_stats(potential.equipment["item"])
	var potential_spec := request("item", {"rank":1})
	potential = commit(potential, "enhancement_reroll", potential_spec, op_for(potential, "enhancement_reroll", potential_spec, 10, 29))
	check(potential.equipment["item"].enhancement_steps[0].g == 9 and Instances.main_stats(potential.equipment["item"]) == stats_before, "RF20 actual integer unchanged despite potential8to9")

func test_inheritance_and_refunds() -> void:
	var profile := fixture()
	profile.equipment["source"] = item("source", "EQ01", 1, [8,8,8,8,8,8,8,8,8,8])
	profile.equipment["target"] = item("target", "EQ03", 20, [12,12,12,12,12,12,12,12,12])
	var quote := Forge.quote(profile, "inherit", inherit_request())
	check(quote.ok and quote.gold == 1530 and quote.materials == {"forge":8}, "RF13 inheritance1530 no rerolls")
	profile = commit(profile, "inherit", inherit_request(), "inherit-overlap")
	check(Forge._gain_sum(profile.equipment["target"].enhancement_steps) == 116, "RF10 target factor2.16 never source1.80")
	check(profile.equipment["source"].enhancement_rank == 0 and profile.equipment["source"].enhancement_steps.is_empty(), "RF17 source empty after inheritance")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(profile))
	check(Forge.validate_profile(loaded).is_empty() and loaded.equipment["source"].enhancement_rank == 0, "RF17 source0 survives reload")
	check(profile.equipment["target"].enhancement_gold_ledger.size() == 11, "RF15 only10 actual makeup payments plus nonrefundable fee")
	var sale := Forge.quote(profile, "sell", request("target"))
	check(sale.ok and sale.gold_return == int(profile.equipment["target"].purchase_baseline_gold / 4) + 286, "RF15 sale refunds only1430 actually paid at20%")
	var sold := commit(profile, "sell", request("target"), "sell-target")
	check(not sold.equipment.has("target") and Forge.is_retired(sold, "target"), "RF18 retired target")
	reject(sold, "dismantle", request("target"), "RF18 cannot dismantle sold instance")
	var replay := Forge.transact(sold, "sell-target", "sell", request("target"))
	check(replay.ok and replay.replayed and replay.profile == sold, "RF16 recycling retry cannot pay again")
	var same := fixture()
	same.equipment["source"] = item("source", "EQ01", 1, [8,8,8,8,8,8,8,8,8,8])
	same.equipment["target"] = item("target", "EQ03", 1, [12,12,12,12,12,12,12,12,12,12])
	reject(same, "inherit", inherit_request(), "RF11 sameN source no improvement")
	same.equipment["source"].enhancement_steps[0].g = 12
	same.equipment["target"].enhancement_steps[0].g = 8
	same.equipment["source"].enhancement_steps[0].pity = 0
	same = commit(same, "inherit", inherit_request())
	check(same.equipment["target"].enhancement_rank == 10 and same.equipment["target"].enhancement_steps[0].g == 12 and same.equipment["target"].enhancement_steps[1].g == 12, "RF12 sameN merge improves only better rank")
	var rerolls := fixture()
	rerolls.equipment["source"] = item("source", "EQ01", 1, [8,8,8,8,8,8,8,8,8,11])
	rerolls.equipment["target"] = item("target", "EQ03", 20)
	for i in 3:
		var spec := request("source", {"rank":10})
		rerolls = commit(rerolls, "enhancement_reroll", spec, op_for(rerolls, "enhancement_reroll", spec, 0, 89))
	check(Forge.quote(rerolls, "inherit", inherit_request()).gold == 2028, "RF13 three no-improvement rerolls still add498 total2028")
	rerolls = commit(rerolls, "inherit", inherit_request())
	for history: Dictionary in rerolls.equipment["target"].enhancement_reroll_history:
		check(history.settled_price_peak == 456 and history.supplements.size() == 1 and history.supplements[0].amount == 166, "RF13 each failed record settled full456")
	rerolls.equipment["low"] = item("low", "EQ01", 1)
	rerolls = commit(rerolls, "inherit", inherit_request("target", "low"))
	rerolls.equipment["high"] = item("high", "EQ03", 20)
	check(Forge.quote(rerolls, "inherit", inherit_request("low", "high")).gold == 100, "RF14 20to1to20 preserves all peaks; fee only")
	rerolls = commit(rerolls, "inherit", inherit_request("low", "high"))
	check(Forge.quote(rerolls, "sell", request("high")).gold_return == int(rerolls.equipment["high"].purchase_baseline_gold / 4) + 286, "RF18 reroll and498 supplement not refundable")
	var cross := fixture()
	cross.equipment["source"] = item("source", "EQ05", 1)
	cross.equipment["target"] = item("target", "EQ03", 1)
	for i in 4: cross = commit(cross, "enhance", request("source"))
	cross = commit(cross, "inherit", inherit_request())
	var salvage := Forge.quote(cross, "dismantle", request("target"))
	check(salvage.materials_return == {"forge":11, "race:B01":1, "race:B02":1}, "RF18 material refund remains original B02 plus B01 base")
	cross = commit(cross, "dismantle", request("target"))
	check(cross.equipment["source"].material_ledger.is_empty(), "RF18 inherited source cannot refund moved materials")
	# Target failed rerolls also settle, even when source wins that overlap.
	var both := fixture()
	both.equipment["source"] = item("source", "EQ01", 1, [12])
	both.equipment["target"] = item("target", "EQ03", 1, [8])
	var spec := request("target", {"rank":1})
	both = commit(both, "enhancement_reroll", spec, op_for(both, "enhancement_reroll", spec, 0, 9))
	both = commit(both, "inherit", inherit_request())
	check(both.equipment["target"].enhancement_reroll_history.size() == 1, "target losing rank history retained")
	both.equipment["high"] = item("high", "EQ03", 20)
	check(Forge.quote(both, "inherit", inherit_request("target", "high")).gold == 135, "losing target history requires23base+12reroll difference")
	# Ties preserve target pity rather than fusing independently earned counters.
	var tie := fixture()
	tie.equipment["source"] = item("source", "EQ01", 1, [10, 10])
	tie.equipment["target"] = item("target", "EQ03", 1, [10])
	tie.equipment["source"].enhancement_steps[0].pity = 2
	tie.equipment["target"].enhancement_steps[0].pity = 1
	tie = commit(tie, "inherit", inherit_request())
	check(tie.equipment["target"].enhancement_steps[0].pity == 1, "equal gains keep target pity")

func test_reforge_and_refine() -> void:
	var profile := fixture()
	profile.equipment["item"] = item()
	var record: Dictionary = profile.equipment["item"]
	var types := Instances.legal_affixes(record.template_id, record.power_type)
	var chosen: String = record.affix_type_and_quantile[0].type
	for type: String in types:
		if type != record.affix_type_and_quantile[1].type and type != chosen:
			chosen = type
			break
	var spec := request("item", {"affix_index":0, "affix_type":chosen})
	var original := profile.duplicate(true)
	var quote := Forge.quote(profile, "reforge", spec)
	check(quote.ok and quote.gold == 79 and quote.materials == {"forge":4, "race:B01":2} and not quote.has("candidate"), "reforge cost50S no preview random sample")
	profile = commit(profile, "reforge", spec, "paid-reforge")
	check(profile.equipment["item"].affix_type_and_quantile == original.equipment["item"].affix_type_and_quantile and profile.equipment["item"].reforge_slot == 0 and profile.equipment["item"].has("pending_reforge"), "paid reforge freezes candidate, binds slot, preserves original pending choice")
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(profile))
	var replay := Forge.transact(reloaded, "paid-reforge", "reforge", spec)
	check(replay.ok and replay.replayed and replay.profile == reloaded, "RF16 paid candidate replay after reload")
	for kind: String in ["enhance", "sell", "dismantle"]: reject(profile, kind, request(), "pending candidate blocks " + kind)
	reject(profile, "refine", request("item", {"affix_index":0}), "pending candidate blocks refinement")
	var candidate: Dictionary = profile.equipment["item"].pending_reforge.new_affix.duplicate(true)
	var resolved := commit(profile, "resolve_reforge", request("item", {"pending_operation_id":"paid-reforge", "choice":"replace"}), "chosen-new")
	check(not resolved.equipment["item"].has("pending_reforge") and resolved.equipment["item"].affix_type_and_quantile[0] == candidate and resolved.permanent_gold == profile.permanent_gold, "replace frozen candidate is free and exact")
	var kept := commit(profile, "resolve_reforge", request("item", {"pending_operation_id":"paid-reforge", "choice":"keep"}), "chosen-old")
	check(kept.equipment["item"].affix_type_and_quantile == original.equipment["item"].affix_type_and_quantile and kept.equipment["item"].reforge_slot == 0, "keep old still permanently binds slot and cost")
	reject(kept, "reforge", request("item", {"affix_index":1, "affix_type":chosen}), "cannot bind another reforge slot")
	reject(kept, "reforge", request("item", {"affix_index":0, "affix_type":kept.equipment["item"].affix_type_and_quantile[1].type}), "cannot duplicate another affix slot")
	var same_type := request("item", {"affix_index":0, "affix_type":kept.equipment["item"].affix_type_and_quantile[0].type})
	check(Forge.quote(kept, "reforge", same_type).ok, "same current type may reroll quantile")
	var refinement := fixture()
	refinement.equipment["item"] = item()
	refinement.equipment["item"].affix_type_and_quantile[0].u = 95
	var before_refine: Dictionary = refinement.equipment["item"].duplicate(true)
	var preview := Forge.quote(refinement, "refine", request("item", {"affix_index":0}))
	check(preview.ok and preview.gold == 126 and preview.has("current_loadout_before") and preview.has("current_loadout_after") and not preview.equipped, "unequipped refinement shows actual current loadout comparison")
	refinement = commit(refinement, "refine", request("item", {"affix_index":0}))
	check(refinement.equipment["item"].affix_type_and_quantile[0].u == 100 and refinement.equipment["item"].main_rolls == before_refine.main_rolls, "refine clamps100 without changing k or type")
	reject(refinement, "refine", request("item", {"affix_index":0}), "refine maxu no charge")
	# Six high attack-speed affixes plus agility fill the actual total cap.
	var capped := fixture()
	capped.talents = {"CH01":{"agility":5}}
	var templates := ["EQ03", "EQ13", "EQ23", "EQ33", "EQ43", "EQ53", "EQ97", "EQ98"]
	var selected := ""
	var selected_index := -1
	for i in templates.size():
		var id := "cap:" + str(i)
		var gear := item(id, templates[i], 20, [], "gold")
		var legal := Instances.legal_affixes(gear.template_id, gear.power_type)
		if "attack_speed" in legal:
			var index := -1
			for a in gear.affix_type_and_quantile.size():
				if gear.affix_type_and_quantile[a].type == "attack_speed": index = a
			if index < 0:
				index = 0
				gear.affix_type_and_quantile[0].type = "attack_speed"
			gear.affix_type_and_quantile[index].u = 100
			selected = id
			selected_index = index
		capped.equipment[id] = gear
		capped.loadout[Registry.equipment(gear.template_id, 2).slot] = id
	capped.equipment[selected].affix_type_and_quantile[selected_index].u = 90
	var saved_cap: float = Rules._parameters.caps.attack_speed
	# Future capped builds use the same resolver. Lower its configured cap in
	# this isolated stress fixture; do not fabricate an effective stat result.
	Rules._parameters.caps.attack_speed = 0.30
	var capped_quote := Forge.quote(capped, "refine", request(selected, {"affix_index":selected_index}))
	Rules._parameters.caps.attack_speed = saved_cap
	check(not capped_quote.ok and capped_quote.error == "NO_EFFECTIVE_IMPROVEMENT" and capped_quote.has("current_loadout_after"), "actual Stats talent-aware capped refine rejects and retains display comparison: " + str(capped_quote.error))
	var locked := fixture()
	locked.equipment["item"] = item()
	locked.equipment["item"].lock_state = true
	check(Forge.quote(locked, "enhance", request()).ok, "locked safe enhancement allowed")
	for kind: String in ["sell", "dismantle"]: reject(locked, kind, request(), "locked rejects " + kind)
	locked.equipment["item"].lock_state = false
	locked.loadout.weapon = "item"
	for kind: String in ["sell", "dismantle"]: reject(locked, kind, request(), "loadout reference protects " + kind)
	locked.loadout.weapon = ""
	locked.equipment["item"].location = "pending"
	for kind: String in ["enhance", "sell", "dismantle"]: reject(locked, kind, request(), "pending inventory protects " + kind)

func test_migration_and_corruption() -> void:
	var old := Store.fresh_profile()
	old.equipment.EQ01.level = 3
	old.applied_transactions["legacy-paid"] = {"kind":"upgrade", "item":"EQ01", "level":1, "price":Forge.OldEconomy.upgrade_price(1, 1), "economy_version":1}
	var migrated := Migration.migrate_profile(old)
	check(not migrated.is_empty(), "RF19 synthetic migration initial")
	if migrated.is_empty(): return
	check(Migration.migrate_profile(migrated) == migrated, "RF19 second migration identical g/c/gold/materials")
	var id: String = migrated.numerical_migration.template_instance_ids.EQ01
	check(migrated.equipment[id].enhancement_steps.size() == 3 and migrated.equipment[id].enhancement_steps[0].g == 10, "RF19 legacy vector deterministic10")
	migrated.loadout.weapon = ""
	migrated.equipment[id].location = "inventory"
	var quote := Forge.quote(migrated, "sell", request(id))
	check(quote.ok and quote.gold_return == int(migrated.equipment[id].purchase_baseline_gold / 4) + int(Forge.OldEconomy.upgrade_price(1,1) / 5), "RF15 proven migration payment only, not three fabricated ranks: " + str(quote.error))
	var forged := fixture()
	forged.equipment["item"] = item()
	forged.equipment["item"].enhancement_gold_ledger = [{"event_id":"fiction", "amount":10000, "kind":"enhancement", "rank":1}]
	check(not Forge.validate_profile(forged).is_empty(), "fabricated unsigned investment rejected")
	var base := fixture()
	base.equipment["item"] = item()
	base = commit(base, "enhance", request(), "proven-payment")
	var duplicate := base.duplicate(true)
	duplicate.equipment["copy"] = duplicate.equipment["item"].duplicate(true)
	duplicate.equipment["copy"].instance_id = "copy"
	check(Forge.validate_profile(duplicate) == "DUPLICATE_PAYMENT_OWNERSHIP", "globally duplicate payment ownership rejects")
	var corrupt := base.duplicate(true)
	corrupt.equipment["item"].enhancement_gold_ledger[0].amount += 1
	check(not Forge.validate_profile(corrupt).is_empty(), "payment amount corruption rejects")
	corrupt = base.duplicate(true)
	corrupt.equipment["item"].enhancement_steps[0].base_price_peak = 1
	check(Forge.validate_profile(corrupt) == "INVALID_PRICE_PEAK", "canonical price peak below current item level rejects")
	corrupt = base.duplicate(true)
	corrupt.equipment["item"].enhancement_steps[0].base_price_peak = 999999
	check(Forge.validate_profile(corrupt) == "INVALID_PRICE_PEAK", "impossible forged canonical peak rejects")
	corrupt = base.duplicate(true)
	corrupt.forging_transactions.operations["proven-payment"].result.gain = 12
	corrupt.forging_transactions.operations["proven-payment"].result_hash = Forge._receipt_hash(corrupt.forging_transactions.operations["proven-payment"])
	check(not Forge.validate_profile(corrupt).is_empty(), "resealed wrong deterministic result rejected")
	corrupt = base.duplicate(true)
	corrupt.forging_transactions.operations["proven-payment"].gold += 1
	corrupt.forging_transactions.operations["proven-payment"].result_hash = Forge._receipt_hash(corrupt.forging_transactions.operations["proven-payment"])
	check(not Forge.validate_profile(corrupt).is_empty(), "resealed wrong immutable cost rejected")
	var historical: Dictionary = JSON.parse_string(JSON.stringify(base))
	var original_cost: Variant = Rules._parameters.enhancement_gold[0]
	Rules._parameters.enhancement_gold[0] = 999
	Forge._validated_receipts.clear()
	check(Forge.validate_profile(historical).is_empty(), "historical receipts use archived costs after live repricing")
	check(Forge.transact(historical, "proven-payment", "enhance", request()).replayed, "historical replay survives live repricing")
	check(Forge.quote(historical, "enhance", request()).error == "ECONOMY_VERSION_MISMATCH", "new operations fail closed on economic drift")
	Rules._parameters.enhancement_gold[0] = original_cost
	for field: String in ["loadout", "loadout_presets", "talents", "applied_transactions", "pending_claim_receipts", "numerical_migration"]:
		var malformed := fixture_with_item()
		malformed[field] = []
		check(not Forge.validate_profile(malformed).is_empty(), "malformed optional map safe rejection " + field)
	var split := base.duplicate(true)
	split.equipment["copy"] = item("copy")
	split.equipment["copy"].material_ledger = split.equipment["item"].material_ledger.duplicate(true)
	split.equipment["item"].material_ledger = []
	check(Forge.validate_profile(split) == "DUPLICATE_PAYMENT_OWNERSHIP", "one operation cannot split gold and material ownership")
	var retired := commit(base, "sell", request(), "retire-once")
	retired.equipment["copy"] = base.equipment["item"].duplicate(true)
	retired.equipment["copy"].instance_id = "copy"
	check(Forge.validate_profile(retired) == "DUPLICATE_PAYMENT_OWNERSHIP", "retired payments cannot be attached to another item")
	var locked := base.duplicate(true)
	locked.equipment["item"].lock_state = true
	locked.equipment["item"].forge_revision += 1
	check(Forge.validate_profile(locked).is_empty(), "standalone lock revision does not invalidate forge history")
	var poor := fixture()
	poor.equipment["item"] = item()
	poor.permanent_gold = 0
	reject(poor, "enhance", request(), "insufficient gold atomic")
	poor.permanent_gold = 10000
	poor.materials.forge = 0
	reject(poor, "enhance", request(), "insufficient material atomic")
	var detached := Forge.transact(fixture_with_item(), "detached", "enhance", request())
	check(detached.ok, "detached receipt fixture")
	if detached.ok:
		detached.receipt.after.item.enhancement_steps[0].g = 99
		check(Forge.validate_profile(detached.profile).is_empty(), "returned receipt detached from profile/ledger")

func fixture_with_item() -> Dictionary:
	var profile := fixture()
	profile.equipment["item"] = item()
	return profile


## Separate slow acceptance gate uses real transactions, never fabricated audit
## receipts. All 160 worst-case rerolls are forced only by choosing a deterministic
## operation ID whose ordinary sampled ticket loses; production accepts no rolls.
func test_storage_envelope() -> void:
	if "--stress-eight" in OS.get_cmdline_user_args():
		test_eight_storage()
		return
	var profile := fixture()
	profile.equipment["item"] = item("item", "EQ01", 20, [8,8,8,8,8,8,8,8,8,8])
	for rank in range(1, 11):
		for attempt in 16:
			var spec := request("item", {"rank":rank})
			var result := Forge.transact(profile, op_for(profile, "enhancement_reroll", spec, 0, 9), "enhancement_reroll", spec)
			check(result.ok, "RF05 worst160 real operation rank" + str(rank) + " try" + str(attempt) + ":" + str(result.error))
			if not result.ok: return
			profile = result.profile
		check(profile.equipment["item"].enhancement_steps[rank - 1].g == 12, "RF05 max16 per rank" + str(rank))
		print("STORAGE worst progression rank=", rank, " bytes=", JSON.stringify(profile).to_utf8_buffer().size())
	var worst_bytes := JSON.stringify(profile).to_utf8_buffer().size()
	print("STORAGE_WORST_160_BYTES=", worst_bytes)
	check(worst_bytes < Forge.MAX_BYTES, "single10x16 complete worst-case below32MiB")
	check(Forge.validate_profile(JSON.parse_string(JSON.stringify(profile))).is_empty(), "RF16 worst160 survives JSON reload")
	test_eight_storage()

func test_eight_storage() -> void:
	var eight := fixture()
	for index in 8:
		var id := "eight:" + str(index)
		eight.equipment[id] = item(id, "EQ01", 20, [8,8,8,8,8,8,8,8,8,8])
		for attempt in 44:
			@warning_ignore("integer_division")
			var rank := attempt / 16 + 1
			var spec := request(id, {"rank":rank})
			var result := Forge.transact(eight, op_for(eight, "enhancement_reroll", spec, 0, 9), "enhancement_reroll", spec)
			check(result.ok, "eight44 transaction " + id + ":" + str(attempt) + ":" + str(result.error))
			if not result.ok: return
			eight = result.profile
		print("STORAGE eight progression items=", index + 1, " bytes=", JSON.stringify(eight).to_utf8_buffer().size())
	var eight_bytes := JSON.stringify(eight).to_utf8_buffer().size()
	print("STORAGE_EIGHT_44_BYTES=", eight_bytes)
	check(eight_bytes < Forge.MAX_BYTES, "eightx44 real paid rerolls below32MiB")
	check(Forge.validate_profile(JSON.parse_string(JSON.stringify(eight))).is_empty(), "RF16 eight44 reload validates")
