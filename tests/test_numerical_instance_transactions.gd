extends SceneTree
const Transactions = preload("res://scripts/core/instance_transactions.gd")
const Economy = preload("res://scripts/core/instance_economy.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Rules = preload("res://config/numerical_rules.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(level: int = 20) -> Dictionary:
	return {"ruleset_version":2, "selected_hero":"CH01", "hero_xp":{"CH01":Growth.thresholds()[level - 1], "CH02":0, "CH03":0},
		"equipment":{}, "bosses":["BO01", "BO02", "BO03", "BO04"], "permanent_gold":1000000,
		"materials":{"forge":100000, "race:B01":100000, "race:B02":100000, "race:B03":100000, "race:B04":100000,
			"core:B01":10000, "core:B02":10000, "core:B03":10000, "core:B04":10000},
		"applied_transactions":{"starter_grant_v1":{"kind":"starter"}}}

func request(template_id: String = "EQ01", rarity: String = "green", level: int = 20, power: String = "physical") -> Dictionary:
	return {"hero_id":"CH01", "template_id":template_id, "rarity":rarity, "power_type":power, "item_level":level}

func rejected_unchanged(profile: Dictionary, operation: String, spec: Dictionary, kind: String, label: String) -> void:
	var before := JSON.stringify(profile)
	var result: Dictionary = Transactions.purchase(profile, operation, spec) if kind == "purchase" else (Transactions.craft(profile, operation, spec) if kind == "craft" else Transactions.complete_set(profile, operation, spec))
	check(not result.ok and result.profile.is_empty() and JSON.stringify(profile) == before, label + " reject without mutation")

func _initialize() -> void:
	var sum := 0
	for rank in range(1, 11): sum += Economy.enhancement_price(rank, 20)
	check(sum == 3930, "canonical Lv20 enhancement sum uses each exact ceil, not 3925 aggregate")
	check(Economy.enhancement_price(4, 20) == 205 and Economy.enhancement_reroll_price(4, 20) == 103, "half price applied before ceil")
	check(Economy.enhancement_materials(3, "B02", true) == {"forge":2}, "reroll materials exact half ceil")
	check(Economy.enhancement_materials(10, "B03") == {"forge":25, "race:B03":6, "core:B03":2}, "canonical material identity")
	check(Economy.enhancement_materials(10, "B03", true) == {"forge":13, "race:B03":3}, "reroll cores zero")
	for level in range(1, 21):
		for id: String in Registry.equipment_ids(2):
			var base := int(Registry.equipment(id, 2).price)
			for pair in [["white", 8], ["green", 12]]:
				var numerator: int = base * int(pair[1]) * (100 + 3 * (level - 1))
				@warning_ignore("integer_division")
				var expected: int = numerator / 1000 + (1 if numerator % 1000 else 0)
				check(Economy.purchase_price(id, pair[0], level) == expected, "all catalogue prices exact " + id)
	check(Economy.purchase_price("EQ01", "purple", 1) == -1 and Economy.purchase_price("EQ01", "gold", 1) == -1, "shop quality gate")
	check(Economy.purchase_baseline_price("EQ01", "gold", 20) == 114, "gold uses same-template green sale baseline")
	check(Economy.crafting_cost("EQ01", "green", 20) == {"gold":314, "materials":{"forge":12, "race:B01":6}}, "green creation is not combat-scaled")
	check(Economy.crafting_cost("EQ01", "purple", 20).gold == 628 and Economy.crafting_cost("EQ01", "gold", 20).gold == 1256, "exact integral prices do not over-ceil")
	for pair in [["EQ61", "B01"], ["EQ67", "B02"], ["EQ73", "B01"], ["EQ79", "B02"], ["EQ85", "B03"], ["EQ91", "B04"], ["EQ113", "B01"], ["EQ124", "B04"]]:
		var cost := Economy.crafting_cost(pair[0], "gold", 20)
		check(cost.get("materials", {}).get("race:" + pair[1]) == 24 and cost.get("materials", {}).get("core:" + pair[1]) == 6, "shop-themed crafting materials " + pair[0])
	for template_id: String in Registry.equipment_ids(2):
		for rarity: String in ["green", "purple", "gold"]:
			check(Economy.crafting_cost(template_id, rarity, 20) == Economy.historical_creation_cost(request(template_id, rarity), "craft"), "all creation costs match immutable v1 snapshot " + template_id + rarity)
	var profile := fixture()
	var original := profile.duplicate(true)
	var bought := Transactions.purchase(profile, "purchase-one", request())
	check(bought.ok, "purchase succeeds " + str(bought.error))
	if not bought.ok:
		_finish()
		return
	check(profile == original and bought.profile.permanent_gold == 999886, "candidate is detached and debits 114 once")
	check(bought.profile.applied_transactions == original.applied_transactions, "legacy receipts preserved byte-values")
	var item: Dictionary = bought.receipt.items[0]
	check(item.enhancement_rank == 0 and item.enhancement_gold_ledger.is_empty() and item.material_ledger.is_empty(), "purchase +0 and no refundable investment")
	check(item.purchase_baseline_gold == 114 and item.location == "inventory", "creation sale baseline frozen")
	check(Transactions.validate_ledger(bought.profile.instance_transactions), "new receipt validates")
	var detached := bought.duplicate(true)
	detached.receipt.items[0].main_rolls[detached.receipt.items[0].main_rolls.keys()[0]] = 101
	check(Transactions.validate_ledger(detached.profile.instance_transactions) and detached.profile.equipment[item.instance_id] == item, "returned receipt detached from candidate equipment and ledger")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(bought.profile))
	check(Transactions.validate_ledger(restored.instance_transactions), "JSON round trip preserves receipt validation")
	var retry := Transactions.purchase(bought.profile, "purchase-one", request())
	check(retry.ok and retry.replayed and retry.receipt == bought.receipt and retry.profile == bought.profile, "same request replays without debit or grant")
	var failed_save_retry := Transactions.purchase(profile, "purchase-one", request())
	check(failed_save_retry.receipt == bought.receipt and failed_save_retry.profile == bought.profile, "retry after failed save produces identical candidate and rolls")
	var duplicate := Transactions.purchase(bought.profile, "purchase-two", request())
	check(duplicate.ok and duplicate.profile.equipment.size() == 2 and duplicate.receipt.items[0].instance_id != item.instance_id, "duplicate template distinct instances")
	var sold: Dictionary = bought.profile.duplicate(true)
	sold.equipment.clear()
	var sold_retry := Transactions.purchase(sold, "purchase-one", request())
	check(sold_retry.ok and sold_retry.replayed and sold_retry.profile.equipment.is_empty() and sold_retry.receipt == bought.receipt, "historical replay never resurrects consumed item")
	var conflict := request("EQ11")
	rejected_unchanged(bought.profile, "purchase-one", conflict, "purchase", "operation conflict")
	rejected_unchanged(bought.profile, "purchase-one", request(), "craft", "cross-kind conflict")
	var no_gold := fixture()
	no_gold.permanent_gold = 113
	rejected_unchanged(no_gold, "poor", request(), "purchase", "insufficient gold")
	var no_material := fixture()
	no_material.materials["race:B01"] = 5
	rejected_unchanged(no_material, "poor-craft", request(), "craft", "insufficient material")
	rejected_unchanged(profile, "invalid-quality", request("EQ01", "purple"), "purchase", "purple shop")
	rejected_unchanged(profile, "white-craft", request("EQ01", "white"), "craft", "white craft")
	rejected_unchanged(fixture(4), "low-level", request("EQ01", "green", 5), "purchase", "item level gate")
	var locked := fixture()
	locked.bosses.clear()
	rejected_unchanged(locked, "locked", request("EQ04"), "purchase", "template unlock gate")
	for pair in [["green", 5], ["purple", 10], ["gold", 15]]:
		var rarity: String = pair[0]
		var gate: int = pair[1]
		rejected_unchanged(fixture(gate - 1), "gate-" + rarity, request("EQ01", rarity, 1), "craft", "craft gate " + rarity)
		var crafted := Transactions.craft(fixture(gate), "craft-" + rarity, request("EQ01", rarity, gate))
		check(crafted.ok and crafted.receipt.items[0].enhancement_rank == 0, "craft at exact gate " + rarity)
		check(crafted.receipt.items[0].enhancement_gold_ledger.is_empty() and crafted.receipt.items[0].material_ledger.is_empty(), "creation costs excluded from all refunds " + rarity)
		check(crafted.receipt.materials.get("core:B01", 0) == {"green":0, "purple":2, "gold":6}[rarity], "matching race core count " + rarity)
	var magic := Transactions.purchase(profile, "choose-magic", request("EQ01", "white", 1, "magic"))
	check(magic.ok and magic.receipt.items[0].power_type == "magic", "shop allows explicit off-class type choice")
	var wrong_hero := request()
	wrong_hero.hero_id = "CH03"
	rejected_unchanged(profile, "hero-context", wrong_hero, "purchase", "selected hero level context")
	for mutation in [{"seed":7}, {"item_level":1.5}, {"item_level":21}, {"power_type":"hybrid"}, {"rarity":null}, {"template_id":[]}, {"hero_id":[]}]:
		var malformed := request()
		malformed.merge(mutation, true)
		rejected_unchanged(profile, "bad", malformed, "purchase", "malformed " + str(mutation))
	var limited := fixture()
	limited.inventory_capacity = 1
	var full_first := Transactions.purchase(limited, "full-one", request())
	var full_second := Transactions.purchase(full_first.profile, "full-two", request())
	check(full_second.ok and full_second.profile.equipment.size() == 2 and full_second.receipt.items[0].location == "pending", "full capacity retains overflow without sale/delete")
	check(full_second.receipt.pending_instance_ids == [full_second.receipt.items[0].instance_id], "pending receipt explicit")
	var unlimited: Dictionary = full_second.profile.duplicate(true)
	unlimited.inventory_capacity = 0
	check(Transactions.quote_purchase(unlimited, request()).pending_count == 0, "capacity zero unlimited")
	var set_request := {"hero_id":"CH01", "set_id":"S09", "template_ids":Registry.set_item_ids("S09", 2), "rarity":"green", "power_type":"physical", "item_level":1}
	var quote := Transactions.quote_set(profile, set_request)
	check(quote.ok and quote.template_ids.size() == 8 and quote.set_slot_count == 8 and quote.all_template_ids.size() == 8, "set quote eight slots")
	check(not quote.has("items"), "quote exposes no random outcomes")
	var raw := 0
	for template: String in quote.template_ids: raw += Economy.purchase_price(template, "green", 1)
	check(quote.gold == Economy.completion_price(raw), "set discount ceil aggregate total")
	var set_bought := Transactions.complete_set(profile, "set-all", set_request)
	check(set_bought.ok and set_bought.profile.equipment.size() == 8, "eight-piece completion grant")
	check(Transactions.validate_ledger(set_bought.profile.instance_transactions), "set receipt validates")
	var reversed := set_request.duplicate(true)
	reversed.template_ids.reverse()
	check(Transactions.complete_set(set_bought.profile, "set-all", reversed).replayed, "set selection ordering has same canonical request")
	rejected_unchanged(set_bought.profile, "set-repeat", set_request, "complete_set", "owned missing-piece discount rejected")
	var magic_set := set_request.duplicate(true)
	magic_set.power_type = "magic"
	check(Transactions.quote_set(set_bought.profile, magic_set).error == "CLASS_POWER_MISMATCH", "exclusive class set cannot be bought with opposite stat type")
	var partial := set_request.duplicate(true)
	partial.item_level = 1
	partial.template_ids = ["EQ61", "EQ62"]
	var partial_quote := Transactions.quote_set(profile, partial)
	check(partial_quote.gold == 346 and partial_quote.gold != Economy.completion_price(Economy.purchase_price("EQ61", "green", 1)) + Economy.completion_price(Economy.purchase_price("EQ62", "green", 1)), "two-item discount once: ceil(90% of 384)=346, not 347")
	check(Transactions.complete_set(profile, "selected-two", partial).receipt.items.size() == 2, "only explicitly selected missing pieces bought")
	var saved_config: Dictionary = Rules._parameters.duplicate(true)
	var saved_catalog: Dictionary = Registry._equipment_v2.duplicate(true)
	Rules._parameters.shop_price_multiplier.green = 3.0
	Rules._parameters.forge_costs.gold.gold = 9999
	Rules._parameters.set_completion_discount = 0.5
	Registry._equipment_v2.EQ01.price = 99999
	Registry._equipment_v2.EQ61.set_id = "S10"
	Registry._equipment_v2.EQ61.race_id = "B04"
	check(Transactions.validate_ledger(bought.profile.instance_transactions), "historical purchase validates after live prices change")
	check(Transactions.validate_ledger(set_bought.profile.instance_transactions), "historical set validates after live discount/membership/race change")
	check(Transactions.purchase(bought.profile, "purchase-one", request()).replayed, "historical replay stable after price changes")
	check(not Transactions.quote_purchase(profile, request()).ok, "unversioned live price changes cannot create unverifiable new receipts")
	Rules._parameters = saved_config
	Registry._equipment_v2 = saved_catalog
	var tampered: Dictionary = bought.profile.instance_transactions.duplicate(true)
	tampered.operations["purchase-one"].gold += 1
	check(not Transactions.validate_ledger(tampered), "tampered price rejected")
	tampered = bought.profile.instance_transactions.duplicate(true)
	tampered.operations["purchase-one"].items[0].enhancement_gold_ledger.append({"event_id":"fake", "amount":99})
	check(not Transactions.validate_ledger(tampered), "creation cannot fabricate enhancement refund record")
	tampered = bought.profile.instance_transactions.duplicate(true)
	var roll_key: String = tampered.operations["purchase-one"].items[0].main_rolls.keys()[0]
	tampered.operations["purchase-one"].items[0].main_rolls[roll_key] = (int(tampered.operations["purchase-one"].items[0].main_rolls[roll_key]) + 1) % 101
	check(not Transactions.validate_ledger(tampered), "frozen random output checksum rejects silent mutation")
	var drop := Acquisition.roll_item({"instance_id":"free-drop", "source_event_id":"event-free", "template_id":"EQ01", "item_level":20, "rarity":"green", "power_type":"physical", "source":"drop", "hero_id":"CH01"}, 21)
	for seed_value in range(22, 72):
		if not drop.is_empty() and int(drop.enhancement_rank) > 0: break
		drop = Acquisition.roll_item({"instance_id":"free-drop", "source_event_id":"event-free", "template_id":"EQ01", "item_level":20, "rarity":"green", "power_type":"physical", "source":"drop", "hero_id":"CH01"}, seed_value)
	check(not drop.is_empty() and int(drop.enhancement_rank) > 0 and drop.enhancement_gold_ledger.is_empty() and drop.material_ledger.is_empty(), "free pre-enhanced drop ranks never manufacture payment")
	for index in drop.enhancement_steps.size(): check(drop.enhancement_steps[index].base_price_peak == Economy.enhancement_price(index + 1, 20), "free rank canonical peak")
	# Scale the immutable receipt map past the old legacy ceiling without executing
	# thousands of sequential full-document copies. Each receipt retains a unique ID.
	var long_profile := fixture()
	long_profile.instance_transactions = {"version":1, "operations":{}}
	for index in 4097:
		var operation := "history-" + str(index)
		var receipt: Dictionary = bought.receipt.duplicate(true)
		receipt.operation_id = operation
		receipt.items[0].instance_id = "instance:tx:" + operation.sha256_text().substr(0, 32) + ":0"
		receipt.items[0].source_event_id = "transaction:" + operation
		receipt.result_hash = Transactions._receipt_hash(receipt)
		long_profile.instance_transactions.operations[operation] = receipt
	check(Transactions.validate_ledger(long_profile.instance_transactions), "4097 immutable operation receipts valid")
	var long_result := Transactions.purchase(long_profile, "history-next", request())
	check(long_result.ok and long_result.profile.instance_transactions.operations.size() == 4098, "new transactions do not fail at old 4096 cap")
	_finish()

func _finish() -> void:
	for failure: String in failures: push_error(failure)
	print("NUMERICAL INSTANCE TRANSACTIONS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
