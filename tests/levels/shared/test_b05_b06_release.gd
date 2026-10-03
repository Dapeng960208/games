extends Node
## Default release gate and lawful camp transactions; no candidate arguments.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Catalog = preload("res://scripts/domain/world/world_catalog.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Routes = preload("res://scripts/domain/world/route_generator.gd")
const Expedition = preload("res://scripts/app/expedition_controller.gd")
const Transactions = preload("res://scripts/domain/equipment/instance_transactions.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Native = preload("res://scripts/domain/equipment/numerical_profile.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const CreationUI = preload("res://scripts/presentation/equipment/instance_acquisition_panel.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("RELEASE: "+label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	check(not Rules.b05_candidate_enabled() and not Rules.b06_candidate_enabled(),"normal process has no isolated experiment flags")
	check(Rules.parameters().implemented_chapters == 6 and Rules.released_chapters() == ["B01","B02","B03","B04","B05","B06","B10"] and Growth.level_cap() == 50,"six contiguous chapters plus the explicit final court and Lv50 from shipped JSON")
	check(Catalog.validate().is_empty() and Registry.validate(2).is_empty(),"released catalogs validate")
	check(Catalog.room_ids().size() == 42 and Catalog.enemy_ids().size() == 108 and Catalog.bosses().size() == 13,"42 ordinary rooms, 108 species, six original bosses, six guardians and the single-headed Star-Crown Ancient Dragon")
	check(Registry.equipment_ids(2).size() == 230 and Registry.sets(2).size() == 26,"194 original templates plus 35 final templates and one unique ring, with 26 sets")
	var plan := Catalog.region_plan()
	check(plan.size() == 10 and plan.slice(0,6).all(func(row: Dictionary): return row.implemented) and plan.slice(6,9).all(func(row: Dictionary): return not row.implemented) and plan[-1].biome_id == "B10" and plan[-1].implemented,"B01-B06 and final B10 released; B07-B09 remain closed in the ten-chapter plan")
	for chapter: String in ["B05","B06"]:
		check(Catalog.biomes()[chapter].status == "released" and Catalog.biomes()[chapter].runtime_enabled,"formal catalog status "+chapter)
		check(Routes.generate_single_biome(chapter,560630,[],30).valid,"normal Lv30 route "+chapter)
	for chapter: String in ["B07","B08","B09"]:
		check(not Rules.chapter_enabled(chapter) and not Routes.generate_single_biome(chapter,560630,[],30).valid,"unreleased chapter rejected "+chapter)
	check(CreationUI.creation_ids(false).filter(func(id: String): return id.begins_with("B06-")).size() == 35 and CreationUI.creation_ids(true).filter(func(id: String): return id.begins_with("B06-")).size() == 4,"B06 camp creation catalog present")
	check(Economy.historical_purchase_baseline("B06-SW-weapon","green",30,2) == -1 and Economy.historical_creation_cost({"template_id":"B06-SW-weapon","rarity":"gold","item_level":30},"craft",2).is_empty(),"v2 cannot authorize new B06 or Lv30 purchases")
	check(Economy.historical_purchase_baseline("B05-SW-weapon","green",25,2) == Economy.historical_purchase_baseline("B05-SW-weapon","green",25,3),"old B05 price remains exact")
	var base := Native.fresh(Store.fresh_profile())
	check(not Expedition.unlocked_biomes(base).has("B05"),"new profile retains sequential unlock")
	base.bosses = ["BO01","BO02","BO03","BO04"]
	check(Expedition.unlocked_biomes(base).has("B05") and not Expedition.unlocked_biomes(base).has("B06") and not Expedition.unlocked_biomes(base).has("B10"),"BO04 banks B05 only")
	base.bosses.append("BO05")
	check(Expedition.unlocked_biomes(base).has("B06") and not Expedition.unlocked_biomes(base).has("B10"),"BO05 banks B06 without bypassing the final prerequisite")
	base.bosses.append("BO06")
	check(not Expedition.unlocked_biomes(base).has("B10"),"the six released bosses cannot replace BO09")
	base.bosses.append("BO09")
	check(Expedition.unlocked_biomes(base).has("B10"),"the saved BO09 extraction flag unlocks B10")
	var output := OS.get_environment("GAMES_TEST_OUTPUT_DIR")
	check(not output.is_empty() and FileAccess.file_exists(output.path_join(".managed-test-run.json")),"managed isolated output")
	if output.is_empty(): get_tree().quit(2); return
	for hero: String in ["CH01","CH02","CH03"]:
		var profile := base.duplicate(true)
		profile.selected_hero = hero
		profile.hero_xp[hero] = Growth.thresholds().back()
		profile.permanent_gold = 1000000
		profile.materials = {"forge":10000,"race:B06":10000,"core:B06":10000}
		var power := "magic" if hero == "CH03" else "physical"
		var sid: String = {"CH01":"B06-SW","CH02":"B06-SG","CH03":"B06-SM"}[hero]
		for kind: String in ["purchase","craft","complete_set"]:
			var request := {"hero_id":hero,"rarity":"gold" if kind == "craft" else "green","power_type":power,"item_level":30}
			if kind == "complete_set": request.merge({"set_id":sid,"template_ids":Transactions.missing_set_templates(profile,sid,power)})
			else: request["template_id"] = sid+"-weapon"
			var operation := "release:"+hero+":"+kind
			var before := var_to_str(profile)
			var result := Transactions.craft(profile,operation,request) if kind == "craft" else Transactions.complete_set(profile,operation,request) if kind == "complete_set" else Transactions.purchase(profile,operation,request)
			check(result.ok and var_to_str(profile) == before,"immutable lawful B06 "+hero+kind+str(result.get("error","")))
			if not result.ok: continue
			check(result.receipt.version == Transactions.RECEIPT_VERSION and Transactions._valid_receipt(operation,JSON.parse_string(JSON.stringify(result.receipt))),"current receipt validates after JSON "+kind)
			_historical_v3(hero, kind, base)
			check(result.receipt.items.size() == (7 if kind == "complete_set" else 1),"exact item count "+kind)
			for item: Dictionary in result.receipt.items:
				check(Instances.validate(item).is_empty() and item.item_level == 30 and item.class_policy_version == 3,"actual Lv30 class-qualified item")
			profile = result.profile
			var repeated := Transactions.craft(profile,operation,request) if kind == "craft" else Transactions.complete_set(profile,operation,request) if kind == "complete_set" else Transactions.purchase(profile,operation,request)
			check(repeated.ok and repeated.receipt == result.receipt and repeated.profile == profile,"repeat never charges or rerolls "+kind)
		var store := Store.new(output.path_join("release_"+hero+".json"))
		check(store.save_document(profile),"durable current B06 profile "+hero+store.last_error)
		var loaded := Store.new(store.path).load_document()
		check(not loaded.is_empty() and loaded.profile.equipment.size() == profile.equipment.size() and Transactions.validate_ledger(loaded.profile.instance_transactions),"disk reload preserves items and receipts "+hero)
	print("B05_B06_RELEASE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)

func _historical_v3(hero: String, kind: String, base: Dictionary) -> void:
	# origin/main e67e32a: transaction v3's original request, seed and item stream.
	# Generate directly from frozen B06 generator v4; never relabel a v4 receipt.
	var sid: String = {"CH01":"B06-SW", "CH02":"B06-SG", "CH03":"B06-SM"}[hero]
	var request := {"hero_id":hero, "rarity":"gold" if kind == "craft" else "green", "power_type":"magic" if hero == "CH03" else "physical", "item_level":30}
	if kind == "complete_set":
		var templates: Array = Economy.historical_set_items(sid, 3)
		templates.sort()
		request.merge({"set_id":sid, "template_ids":templates})
	else: request["template_id"] = sid + "-weapon"
	var operation := "historical:v3:" + hero + ":" + kind
	var fingerprint: String = JSON.stringify([kind, request], "", true, true).sha256_text()
	var seed: int = (operation + ":" + fingerprint).sha256_text().substr(0, 13).hex_to_int()
	var cost: Dictionary = Economy.historical_creation_cost(request, kind, 3)
	check(cost.get("gold") == {"purchase":404, "craft":1496, "complete_set":2509}[kind] and cost.get("materials") == ({"forge":48, "race:B06":24, "core:B06":6} if kind == "craft" else {}), "v3 frozen exact financial contract " + hero + kind)
	if cost.is_empty(): return
	var items: Array = []
	var ids: Array = request.template_ids if kind == "complete_set" else [request.template_id]
	for index: int in ids.size():
		var identity := "instance:tx:" + operation.sha256_text().substr(0, 32) + ":" + str(index)
		var spec: Dictionary = Acquisition._canonical({"instance_id":identity, "source_event_id":"transaction:" + operation, "template_id":ids[index], "rarity":request.rarity, "power_type":request.power_type, "hero_id":hero, "item_level":30, "source":"craft" if kind == "craft" else "purchase", "location":"inventory"})
		var rng: RandomNumberGenerator = Acquisition._rng(seed, spec.source_event_id, "item:" + identity + ":" + str(spec.source), 4)
		var item: Dictionary = Acquisition._finish_item(spec, rng, seed, Acquisition._fingerprint(spec), 4)
		check(Acquisition.V4.TEMPLATES.has(item.template_id) and item.class_policy_version == 3 and item.source_metadata.generator_version == 4 and Instances.validate(item).is_empty(), "v3 receipt owns an original archived B06 instance")
		items.append(item)
	var receipt := {"version":3, "operation_id":operation, "kind":kind, "request":request, "request_hash":fingerprint, "gold":int(cost.gold), "materials":cost.materials.duplicate(true), "items":items, "pending_instance_ids":[]}
	# The original v3 hash normalizes integral numbers and sorts JSON keys.
	receipt["result_hash"] = JSON.stringify(Acquisition._canonical(receipt), "", true, true).sha256_text()
	check(Transactions._valid_receipt(operation, receipt), "original v3 receipt remains valid " + hero + kind)
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(receipt))
	check(Transactions._valid_receipt(operation, persisted) and Transactions._receipt_hash(persisted) == receipt.result_hash, "original v3 receipt survives numeric JSON roundtrip " + hero + kind)
	var profile := base.duplicate(true)
	profile.selected_hero = hero
	profile.hero_xp[hero] = Growth.thresholds().back()
	profile["instance_transactions"] = {"version":1, "operations":{operation:receipt}}
	for item: Dictionary in items: profile.equipment[item.instance_id] = item.duplicate(true)
	profile = JSON.parse_string(JSON.stringify(profile))
	var before := JSON.stringify(profile, "", true, true)
	var replayed := Transactions.craft(profile, operation, request) if kind == "craft" else Transactions.complete_set(profile, operation, request) if kind == "complete_set" else Transactions.purchase(profile, operation, request)
	check(replayed.ok and replayed.replayed and replayed.receipt.version == 3 and Transactions._receipt_hash(replayed.receipt) == receipt.result_hash and JSON.stringify(replayed.profile, "", true, true) == before and JSON.stringify(profile, "", true, true) == before, "current service replays original v3 without repricing, charging or rerolling " + hero + kind)
	var damaged := persisted.duplicate(true)
	damaged.gold += 1
	damaged.result_hash = Transactions._receipt_hash(damaged)
	check(not Transactions._valid_receipt(operation, damaged), "v3 rejects a resealed wrong historical cost")
	damaged = persisted.duplicate(true)
	damaged.items[0].purchase_baseline_gold += 1
	damaged.result_hash = Transactions._receipt_hash(damaged)
	check(not Transactions._valid_receipt(operation, damaged), "v3 rejects a resealed wrong purchase baseline")
