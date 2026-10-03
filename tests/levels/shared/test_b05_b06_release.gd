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
	check(Rules.parameters().implemented_chapters == 6 and Growth.level_cap() == 30,"six chapters and Lv30 from shipped JSON")
	check(Catalog.validate().is_empty() and Registry.validate(2).is_empty(),"released catalogs validate")
	check(Catalog.room_ids().size() == 36 and Catalog.enemy_ids().size() == 90 and Catalog.bosses().size() == 6,"36 ordinary rooms, 90 species, six bosses")
	check(Registry.equipment_ids(2).size() == 194 and Registry.sets(2).size() == 22,"194 templates and 22 sets")
	var plan := Catalog.region_plan()
	check(plan.slice(0,6).all(func(row: Dictionary): return row.implemented) and plan.slice(6).all(func(row: Dictionary): return not row.implemented),"B01-B06 released, B07-B12 closed")
	for chapter: String in ["B05","B06"]:
		check(Catalog.biomes()[chapter].status == "released" and Catalog.biomes()[chapter].runtime_enabled,"formal catalog status "+chapter)
		check(Routes.generate_single_biome(chapter,560630,[],30).valid,"normal Lv30 route "+chapter)
	check(not Routes.generate_single_biome("B07",560630,[],30).valid,"future chapter rejected")
	check(CreationUI.creation_ids(false).filter(func(id: String): return id.begins_with("B06-")).size() == 35 and CreationUI.creation_ids(true).filter(func(id: String): return id.begins_with("B06-")).size() == 4,"B06 camp creation catalog present")
	check(Economy.historical_purchase_baseline("B06-SW-weapon","green",30,2) == -1 and Economy.historical_creation_cost({"template_id":"B06-SW-weapon","rarity":"gold","item_level":30},"craft",2).is_empty(),"v2 cannot authorize new B06 or Lv30 purchases")
	check(Economy.historical_purchase_baseline("B05-SW-weapon","green",25,2) == Economy.historical_purchase_baseline("B05-SW-weapon","green",25,3),"old B05 price remains exact")
	var base := Native.fresh(Store.fresh_profile())
	check(not Expedition.unlocked_biomes(base).has("B05"),"new profile retains sequential unlock")
	base.bosses = ["BO01","BO02","BO03","BO04"]
	check(Expedition.unlocked_biomes(base).has("B05") and not Expedition.unlocked_biomes(base).has("B06"),"BO04 banks B05 only")
	base.bosses.append("BO05")
	check(Expedition.unlocked_biomes(base).has("B06"),"BO05 banks B06")
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
			check(result.receipt.version == 3 and Transactions._valid_receipt(operation,JSON.parse_string(JSON.stringify(result.receipt))),"v3 receipt validates after JSON "+kind)
			check(result.receipt.items.size() == (7 if kind == "complete_set" else 1),"exact item count "+kind)
			for item: Dictionary in result.receipt.items:
				check(Instances.validate(item).is_empty() and item.item_level == 30 and item.class_policy_version == 3,"actual Lv30 class-qualified item")
			profile = result.profile
			var repeated := Transactions.craft(profile,operation,request) if kind == "craft" else Transactions.complete_set(profile,operation,request) if kind == "complete_set" else Transactions.purchase(profile,operation,request)
			check(repeated.ok and repeated.receipt == result.receipt and repeated.profile == profile,"repeat never charges or rerolls "+kind)
		var store := Store.new(output.path_join("release_"+hero+".json"))
		check(store.save_document(profile),"durable v3 B06 profile "+hero+store.last_error)
		var loaded := Store.new(store.path).load_document()
		check(not loaded.is_empty() and loaded.profile.equipment.size() == profile.equipment.size() and Transactions.validate_ledger(loaded.profile.instance_transactions),"disk reload preserves items and receipts "+hero)
	print("B05_B06_RELEASE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
