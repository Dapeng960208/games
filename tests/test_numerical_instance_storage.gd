extends Node
## S03 tests only: synthetic instances and isolated profile path, never player data.
const Instances = preload("res://scripts/core/equipment_instances.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

static func fixture_instance(id: String, template: String, quantile: int = 50, power: String = "physical", level: int = 1) -> Dictionary:
	var rolls: Dictionary = {}
	for key: String in Instances.main_keys(template, power): rolls[key] = quantile
	return Instances.create({"instance_id":id, "template_id":template, "source_event_id":"fixture:" + id,
		"item_level":level, "rarity":"white", "power_type":power, "main_rolls":rolls,
		"affix_type_and_quantile":[], "enhancement_steps":[]})

static func fixture_profile() -> Dictionary:
	var result := ProfileStore.fresh_profile()
	result.ruleset_version = 2
	result.equipment = {}
	result.loadout = {}
	for slot: String in ContentRegistry.slots(2): result.loadout[slot] = ""
	for template: String in ContentRegistry.set_item_ids("S01", 2):
		var id := "fixture-" + template
		var item := fixture_instance(id, template)
		result.equipment[id] = item
		result.loadout[ContentRegistry.equipment(template, 2).slot] = id
	return result

static func document(profile: Dictionary) -> Dictionary:
	return {"schema_version":3, "revision":1, "profile_initialized":true, "profile":profile, "active_run":null}

func _ready() -> void:
	if not Game.profile_path.contains("test_numerical_instance_storage"):
		get_tree().quit(2)
		return
	var fixture := fixture_profile()
	check(ProfileStore._valid_document(document(fixture)), "generated eight-slot profile validates")
	if not failures.is_empty():
		_finish()
		return
	_schema(fixture)
	_storage(fixture)
	_seed_roundtrip(fixture)
	_controller(fixture)
	_finish()

func _seed_roundtrip(fixture: Dictionary) -> void:
	var next := fixture.duplicate(true)
	next.hero_xp.CH01 = 3600
	next.permanent_gold = 100000
	var operation := "creation:fe4b42e1c12ae8ecec34c52de5228a6e"
	var transactions := load("res://scripts/core/instance_transactions.gd")
	var result: Dictionary = transactions.complete_set(next,operation,{"hero_id":"CH01","set_id":"S06","template_ids":["EQ107","EQ108"],"rarity":"white","power_type":"physical","item_level":20})
	check(result.get("ok",false),"deterministic large-seed purchase fixture")
	if not result.get("ok",false): return
	var expected: int = int(result.receipt.items[0].source_metadata.seed)
	check(expected == 4226806090594618,"known decimal parser rounding boundary")
	var path := Game.profile_path+".seed-roundtrip"
	var store := ProfileStore.new(path)
	for cycle in 3:
		check(store.save_document(result.profile),"save integer receipt seed cycle "+str(cycle))
		var loaded := ProfileStore.new(path).load_document()
		check(not loaded.is_empty(),"reload still accepts sealed purchase cycle "+str(cycle))
		if loaded.is_empty(): return
		check(int(loaded.profile.instance_transactions.operations[operation].items[0].source_metadata.seed) == expected and transactions.validate_ledger(loaded.profile.instance_transactions),"seed and receipt hash survive reload/resave cycle "+str(cycle))
		result.profile = loaded.profile

func _schema(fixture: Dictionary) -> void:
	check(ProfileStore._valid_document(document(ProfileStore.fresh_profile())), "default legacy profile unchanged")
	var bad := ProfileStore.fresh_profile()
	bad.ruleset_version = 2
	check(not ProfileStore._valid_document(document(bad)), "ruleset2 cannot disguise legacy template inventory")
	bad = fixture.duplicate(true)
	bad.ruleset_version = 2.1
	check(not ProfileStore._valid_document(document(bad)), "fractional ruleset rejected")
	bad = fixture.duplicate(true)
	bad.equipment["fixture-EQ03"].instance_id = "other-id"
	check(not ProfileStore._valid_document(document(bad)), "map key must match instance identity")
	bad = fixture.duplicate(true)
	bad.equipment["fixture-EQ03"].erase("main_rolls")
	check(not ProfileStore._valid_document(document(bad)), "missing instance field rejected")
	bad = fixture.duplicate(true)
	bad.equipment["fixture-EQ03"].power_type = "unknown"
	check(not ProfileStore._valid_document(document(bad)), "invalid power type rejected")
	bad = fixture.duplicate(true)
	bad.loadout.weapon = "EQ03"
	check(not ProfileStore._valid_document(document(bad)), "template ID cannot substitute for instance ID")
	bad = fixture.duplicate(true)
	bad.loadout.ring = "missing-instance"
	check(not ProfileStore._valid_document(document(bad)), "missing inventory reference rejected")
	bad = fixture.duplicate(true)
	bad.loadout.legs = bad.loadout.chest
	check(not ProfileStore._valid_document(document(bad)), "slot mismatch and duplicate reference rejected")
	bad = fixture.duplicate(true)
	bad.loadout.erase("ring")
	check(not ProfileStore._valid_document(document(bad)), "all eight slots required")
	bad = fixture.duplicate(true)
	bad.loadout["cape"] = ""
	check(not ProfileStore._valid_document(document(bad)), "unknown slot rejected")
	bad = fixture.duplicate(true)
	bad.loadout_presets = {"CH02":fixture.loadout.duplicate(true)}
	bad.loadout_presets.CH02.weapon = "missing-instance"
	check(not ProfileStore._valid_document(document(bad)), "missing preset reference rejected")
	bad = fixture.duplicate(true)
	bad.loadout_presets = {"CH03":fixture.loadout.duplicate(true)}
	check(not ProfileStore._valid_document(document(bad)), "incompatible preset rejected")
	bad = fixture.duplicate(true)
	bad.equipment["fixture-EQ03"].location = "pending"
	check(not ProfileStore._valid_document(document(bad)), "pending instance cannot be worn")
	bad.loadout.weapon = ""
	check(ProfileStore._valid_document(document(bad)), "pending instance retained without equipping or conversion")
	bad.equipment["fixture-EQ03"].location = "equipped"
	check(not ProfileStore._valid_document(document(bad)), "equipped marker requires current loadout reference")
	bad = fixture.duplicate(true)
	bad.loadout.weapon = ""
	bad.equipment["fixture-EQ03"] = fixture_instance("fixture-EQ03", "EQ03", 50, "physical", 20)
	check(ProfileStore._valid_document(document(bad)), "high-level owned item can remain in inventory")
	bad.loadout.weapon = "fixture-EQ03"
	check(not ProfileStore._valid_document(document(bad)), "high-level owned item cannot bypass equip gate")
	var many := fixture.duplicate(true)
	for index in range(125):
		var id := "duplicate-%d" % index
		many.equipment[id] = fixture_instance(id, "EQ03", index % 101)
	check(ProfileStore._valid_document(document(many)), "inventory can exceed template count with distinct instances")
	var audited := fixture.duplicate(true)
	audited.applied_transactions["legacy-buy"] = {"kind":"purchase", "item":"EQ03", "price":180, "level":0}
	check(ProfileStore._valid_document(document(audited)), "legacy receipts retained only as valid audit history")
	audited.applied_transactions["legacy-buy"].price += 1
	check(not ProfileStore._valid_document(document(audited)), "legacy audit still rejects forged receipt")

func _storage(fixture: Dictionary) -> void:
	var path: String = Game.profile_path + ".instance-roundtrip"
	var store := ProfileStore.new(path)
	var next := fixture.duplicate(true)
	next.equipment["duplicate-low"] = fixture_instance("duplicate-low", "EQ03", 0)
	next.equipment["duplicate-high"] = fixture_instance("duplicate-high", "EQ03", 100)
	next.loadout.weapon = "duplicate-high"
	next.loadout_presets = {"CH01":next.loadout.duplicate(true), "CH02":fixture.loadout.duplicate(true)}
	next.equipment["pending-copy"] = fixture_instance("pending-copy", "EQ03", 25)
	next.equipment["pending-copy"].location = "pending"
	check(store.save_document(next), "save duplicate instances and eight-slot presets")
	var saved := next.duplicate(true)
	next.equipment["duplicate-high"].main_rolls.attack = 2
	var loaded := ProfileStore.new(path).load_document()
	check(not loaded.is_empty() and loaded.profile == JSON.parse_string(JSON.stringify(saved)), "save/reload preserves rolls identity presets pending and balance")
	loaded.profile.equipment["duplicate-low"].main_rolls.attack = 77
	check(saved.equipment["duplicate-low"].main_rolls.attack == 0 and saved.equipment["duplicate-high"].main_rolls.attack == 100, "same-template instances and saved copies do not share dictionaries")
	var before_bytes := FileAccess.get_file_as_bytes(path)
	store.max_document_bytes = 1
	check(not store.save_document(saved) and store.last_error == "STORAGE_CAPACITY_EXCEEDED", "full storage rejects complete write")
	check(FileAccess.get_file_as_bytes(path) == before_bytes and saved.equipment.has("pending-copy") and saved.permanent_gold == 0, "full storage keeps pending ownership and never invents gold")

func _controller(fixture: Dictionary) -> void:
	Game.run = null
	check(Game.new_profile(), "controller starts isolated legacy profile")
	var next := fixture.duplicate(true)
	next.equipment["copy-low"] = fixture_instance("copy-low", "EQ03", 0)
	next.equipment["copy-high"] = fixture_instance("copy-high", "EQ03", 100)
	next.equipment["copy-magic"] = fixture_instance("copy-magic", "EQ03", 50, "magic")
	next.equipment["pending-copy"] = fixture_instance("pending-copy", "EQ03", 50)
	next.equipment["pending-copy"].location = "pending"
	next.equipment["high-level"] = fixture_instance("high-level", "EQ03", 50, "physical", 20)
	next.equipment["copy-high"].lock_state = true
	next.equipment["copy-high"].enhancement_rank = 2
	next.equipment["copy-high"].enhancement_steps = [{"g":10,"pity":0,"base_price_peak":40}, {"g":10,"pity":0,"base_price_peak":60}]
	check(Game._commit_profile(next), "controller saves generated v2 instances")
	check(Game.profile.equipment["fixture-EQ03"].location == "equipped" and Game.profile.equipment["copy-low"].location == "inventory", "initial commit normalizes active and unequipped locations")
	check(Game.profile.equipment["pending-copy"].location == "pending" and next.equipment["fixture-EQ03"].location == "inventory", "normalization preserves pending items and caller-owned values")
	next.equipment["copy-low"].main_rolls.attack = 33
	check(Game.profile.equipment["copy-low"].main_rolls.attack == 0, "controller keeps detached committed profile")
	check(Game.equipment_slots().size() == 8 and Game.equipment_slots().has("legs") and Game.equipment_slots().has("ring"), "controller exposes eight actual slots")
	var definition := Game.equipment_definition("copy-low")
	check(definition.id == "EQ03" and definition.instance_id == "copy-low" and definition.instance_stats == Instances.stats(Game.profile.equipment["copy-low"]), "UI bridge preserves template identity and actual instance stats")
	definition.instance_record.main_rolls.attack = 100
	check(Game.profile.equipment["copy-low"].main_rolls.attack == 0 and not ContentRegistry.equipment("EQ03", 2).has("instance_id"), "UI copies cannot mutate ownership or template catalog")
	check(Game.equipment_definition("EQ97").slot == "legs" and Game.equipment_definition("missing").is_empty(), "UI resolves v2 templates without inventing ownership")
	check(not Game.equip_item("EQ03") and not Game.equip_item("missing"), "camp rejects template or missing identity")
	check(not Game.equip_item("pending-copy") and not Game.equip_item("high-level") and not Game.equip_item("copy-magic"), "camp enforces location level and class")
	check(Game.equip_item("copy-low"), "equip first copy")
	check(Game.profile.equipment["copy-low"].location == "equipped" and Game.profile.equipment["fixture-EQ03"].location == "inventory", "equip moves new and previous instance locations atomically")
	var lower_attack := int(Game.selected_stats().attack)
	check(Game.equip_item("copy-high") and int(Game.selected_stats().attack) > lower_attack, "equip other roll changes actual stats while lock remains non-destructive")
	check(Game.profile.equipment.has("copy-low") and Game.profile.equipment["copy-high"].lock_state, "equip preserves duplicate and lock")
	check(Game.profile.equipment["copy-high"].location == "equipped" and Game.profile.equipment["copy-low"].location == "inventory", "duplicate swap updates exact instance locations")
	check(Game.equipment_level("copy-high") == 2 and not Game.preview_stats("copy-high").is_empty(), "instance level and comparison helpers")
	check(Game.select_hero("CH03") and Game.profile.loadout.values().all(func(id: String) -> bool: return id.is_empty()), "switch to magic hero never equips physical instances")
	check(Game.profile.equipment.values().all(func(record: Dictionary) -> bool: return record.location != "equipped"), "empty new hero loadout returns all previous worn instances to inventory")
	check(Game.equip_item("copy-magic") and Game.profile.loadout.weapon == "copy-magic", "magic hero equips exact matching copy")
	check(Game.select_hero("CH01") and Game.profile.loadout.weapon == "copy-high", "physical preset remembers exact duplicate")
	check(Game.profile.equipment["copy-high"].location == "equipped" and Game.profile.equipment["copy-magic"].location == "inventory", "hero preset switch restores location truth without changing locks")
	Game.reload_profile()
	check(Game.profile.loadout.weapon == "copy-high" and Game.profile.loadout_presets.CH03.weapon == "copy-magic", "reload keeps both class presets and rolls")
	check(Game.profile.equipment["copy-high"].location == "equipped" and Game.profile.equipment["copy-magic"].location == "inventory" and Game.profile.equipment["pending-copy"].location == "pending", "all location categories survive reload")
	var before := Game.profile.duplicate(true)
	var previous_limit: int = Game._store.max_document_bytes
	Game._store.max_document_bytes = 1
	check(not Game.equip_item("copy-low") and Game.last_error == "STORAGE_CAPACITY_EXCEEDED", "failed equip save rejects normalized candidate")
	check(Game.profile == before, "failed equip leaves prior loadout locations rolls and locks untouched")
	Game._store.max_document_bytes = previous_limit
	check(not Game.buy_equipment("EQ03", "s03-buy") and not Game.buy_equipment_set("S01", "s03-set"), "zero-wallet fixture cannot buy equipment")
	check(not Game.upgrade_equipment("copy-low", "s03-upgrade") and not Game.sell_equipment_items(["copy-low"], "s03-sale"), "level-one upgrade and missing-sale-baseline recycling reject safely")
	check(Game.upgrade_cost("copy-low") == 0 and Game.equipment_sell_value("copy-low") == 0 and Game.preview_upgrade_stats("copy-low").is_empty(), "legacy price and fake enhancement previews disabled")
	check(not Game._add_equipment_drop({}, "s03-drop", "EQ03", 0), "v2 drop cannot enter template overwrite or auto-gold path")
	check(Game.profile == before, "rejected operations leave every asset and receipt unchanged")
	check(Game.start_run({"expedition":true}) and Game.run.ruleset_version() == 2, "S04 enables versioned v2 expedition start")
	check(not Game.finish_run("abandoned").is_empty() and Game.run == null, "S04 versioned expedition can return to camp")
	check(Game.start_run(), "synthetic non-expedition v2 growth/combat path remains available")
	check(Game.equipment_slots(true).size() == 8 and Game.equipment_definition("copy-high", true).instance_id == "copy-high", "frozen run UI resolves instances")
	Game.run.equipment_snapshot["copy-high"].main_rolls.attack = 25
	check(Game.profile.equipment["copy-high"].main_rolls.attack == 100, "run snapshot is detached from permanent profile")
	Game.run = null

func _finish() -> void:
	print("Numerical instance storage: ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
