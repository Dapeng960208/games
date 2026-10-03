extends SceneTree
## Isolated class qualification, migration and frozen-generation contract tests.
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Transactions = preload("res://scripts/domain/equipment/instance_transactions.gd")
const Migration = preload("res://scripts/infrastructure/persistence/equipment_class_migration.gd")
const NativeProfile = preload("res://scripts/domain/equipment/numerical_profile.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Forging = preload("res://scripts/domain/equipment/instance_forging.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Eligibility = preload("res://scripts/presentation/equipment/equipment_eligibility.gd")
const Text = preload("res://scripts/infrastructure/localization/strings.gd")
const GOLDEN_V1 := ["05e9c82f06e7c3438d062026e9ae5ffb41fe364745d3e488e84f63a83dde6034", "92dd3ea6d1673c6946456239cf4bcd79f56ef293adf5b2bc582b1b5619f1f5e6", "f53e97a728fb8a67fc0fa5fc66efdb9073042e67c13e6deba662b8f1ea8f85fb", "11669ebfbbff013ecd08df111f495053fa414f2032bb021617baa6fcbbdc68dc"]
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func specimen(template: String, power: String = "physical") -> Dictionary:
	var rolls := {}
	for key: String in Instances.main_keys(template,power): rolls[key] = 50
	return Instances.create({"instance_id":"test:class:"+template+":"+power,"source_event_id":"test:historical", "template_id":template,"item_level":1,"rarity":"white","power_type":power,"main_rolls":rolls,"affix_type_and_quantile":[]})

func fresh() -> Dictionary:
	var profile := NativeProfile.fresh(Store.fresh_profile())
	profile.permanent_gold = 1000000
	profile.bosses = ["BO01","BO02","BO03","BO04"]
	profile.hero_xp = {"CH01":3600,"CH02":3600,"CH03":3600}
	profile.materials = {"forge":100000,"race:B01":100000,"core:B01":100000}
	return profile

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	catalog_and_generation()
	history_and_transactions()
	migration_and_backend()
	role_checkpoint_lifecycle()
	print("EQUIPMENT_CLASS_POLICY checks=%d failures=%d" % [checks,failures.size()])
	for failure: String in failures: printerr("FAIL: "+failure)
	quit(0 if failures.is_empty() else 1)

func catalog_and_generation() -> void:
	check(Registry.equipment_ids(2).size() == 124 and Registry.sets(2).size() == 14,"124 templates/14 sets remain")
	check(Acquisition.current_version_error().is_empty(),"current v2 matches frozen numerical and qualification contracts")
	for template: String in Registry.equipment_ids(2):
		var definition := Registry.equipment(template,2)
		var allowed: Array = definition.allowed_heroes
		for power: String in ["physical","magic"]:
			var old := specimen(template,power)
			var spec := {"instance_id":"test:new:"+template+power,"source_event_id":"test:new","template_id":template,"rarity":"white","power_type":power,"item_level":1,"source":"purchase","hero_id":"CH01"}
			var generated := Acquisition.roll_item(spec,4451)
			var legal_type: bool = allowed.size() == 3 or power == Registry.ClassPolicy.power_type(str(allowed[0]))
			check(generated.is_empty() != legal_type,"new generation class/type "+template+power)
			if legal_type: check(Instances.validate(generated).is_empty() and generated.class_policy_version == 1,"new qualification metadata valid "+template+power)
			for hero: String in Registry.heroes():
				var expected: bool = hero in allowed and (allowed.size() == 3 or power == Registry.ClassPolicy.power_type(hero))
				check(Instances.can_equip(old,hero,20) == expected,"authoritative class qualification "+template+power+hero)
				if allowed.size() == 3: check(Instances.can_equip(old,hero,20),"every universal instance really fits "+template+power+hero)
				if hero not in allowed: check(Instances.equip_error(old,hero,20) == "CLASS_LOCKED","all class slots including jewelry block "+template+hero)
		for locale: String in ["zh_CN","en"]:
			Text.locale = locale
			check(not Eligibility.label(definition).is_empty(),"localized exact qualification "+template+locale)
	for hero: String in Registry.heroes():
		for race: String in ["B01","B02","B03","B04"]:
			var pool := Acquisition.natural_pool(race,hero)
			check(pool.size() == 8,"all eight natural slots for "+hero+race)
			var pool_size := 0
			for candidates: Array in pool.values(): pool_size += candidates.size()
			var preferred: String = {"B01":"CH03","B02":"CH02","B03":"CH01","B04":"CH02"}[race]
			check(pool_size == (19 if hero == preferred else 11),"exact same-race pool coverage "+hero+race)
			var context := {"hero_id":hero,"event_id":"test:drop:"+hero+race,"seed":18521,"source":"boss","race_id":race,"difficulty":4,"challenge_level":20,"power_type":Registry.ClassPolicy.power_type(hero)}
			var drop := Acquisition.roll_event(context)
			check(drop.get("ok",false) and Acquisition.event_result_valid(drop),"v2 race/class result seals and regenerates "+hero+race)
			for item: Dictionary in drop.get("items",[]):
				check(Instances.can_equip(item,hero,20) and Registry.equipment(item.template_id,2).race_id == race,"natural loot stays race+class "+hero+race)
			var changed := context.duplicate(true); changed.hero_id = "CH02" if hero != "CH02" else "CH01"; changed.power_type = "physical"
			check(not Acquisition.roll_event(changed,drop).ok,"hero context cannot replay another class "+hero+race)

func history_and_transactions() -> void:
	var index := 0
	for source: String in ["room","boss","normal","summon"]:
		var context := {"event_id":"policy:old:"+source,"seed":54873,"source":source,"race_id":"B01","difficulty":4,"challenge_level":10,"power_type":"physical","wish_slot":"weapon"}
		var receipt := Acquisition._roll_event_v1(context)
		check(receipt.result_fingerprint == GOLDEN_V1[index],"pre-change v1 golden hash identical "+source)
		check(Acquisition.event_result_valid(receipt) and Acquisition.roll_event(context,receipt) == receipt,"historical v1 archive replay "+source)
		var tampered := receipt.duplicate(true); tampered.generator_version = 2
		tampered.erase("result_fingerprint"); tampered = Acquisition._seal(tampered)
		check(not Acquisition.event_result_valid(tampered),"rehashed version transplant rejected "+source)
		index += 1
	var old_receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve("res://tests/fixtures/equipment_class_v1_transaction.json")))
	var profile := fresh()
	profile.instance_transactions = {"version":1,"operations":{old_receipt.operation_id:old_receipt}}
	for item: Dictionary in old_receipt.items: profile.equipment[item.instance_id] = item
	check(old_receipt.result_hash == "9e25990606bbea62fc87471b07bb3a1ea3560b67b34d3711329a39e6b6894157" and Transactions.validate_ledger(profile.instance_transactions),"original v1 purchase receipt hash and validation remain identical")
	var replay := Transactions.purchase(profile,old_receipt.operation_id,old_receipt.request)
	check(replay.ok and replay.replayed and replay.profile == profile and replay.receipt == old_receipt,"v1 now-wrong-class purchase replays without reroll/charge")
	var request := {"hero_id":"CH01","template_id":"EQ03","rarity":"white","power_type":"physical","item_level":1}
	check(Transactions.quote_purchase(profile,request).error == "CLASS_POWER_MISMATCH","new wrong class stat variant rejected")
	request.power_type = "magic"
	var purchase := Transactions.purchase(profile,"test:new:mage-purchase",request)
	check(purchase.ok,"can buy correct mage item for another hero")
	if purchase.ok:
		var item: Dictionary = purchase.receipt.items[0]
		check(not Instances.can_equip(item,"CH01",20) and Instances.can_equip(item,"CH03",20),"purchase does not imply current hero equip")
		var again := Transactions.purchase(purchase.profile,"test:new:mage-purchase",request)
		check(again.ok and again.replayed and again.profile == purchase.profile,"v2 purchase replay exact no charge/reroll")
		var stripped := item.duplicate(true); stripped.erase("class_policy_version")
		check(not Instances.validate(stripped).is_empty(),"v2 cannot strip policy provenance")
	request.rarity = "green"
	var craft := Transactions.craft(profile,"test:new:mage-craft",request)
	check(craft.ok,"craft correct exclusive stat variant")
	request.power_type = "physical"
	var rejected := Transactions.craft(profile,"test:new:wrong-craft",request)
	check(not rejected.ok and rejected.profile.is_empty(),"craft mismatch fails transactionally")
	var set_request := {"hero_id":"CH01","set_id":"S01","template_ids":Registry.set_item_ids("S01",2),"rarity":"white","power_type":"physical","item_level":1}
	check(not Transactions.quote_set(profile,set_request).ok,"complete-set rejects illegal stat variant too")
	set_request.power_type = "magic"
	var full_set := Transactions.complete_set(fresh(),"test:new:mage-set",set_request)
	check(full_set.ok and full_set.receipt.items.size() == 8,"buy valid class set retains all eight pieces")

func safe_runtime(stats: Dictionary) -> Dictionary:
	var player := {"cooldowns":{"q":2.0,"secondary":3.0,"f":4.0,"ultimate":5.0},"passive_count":0,"walk_distance":0.0,"aim_direction":[1.0,0.0],"cast_serial":0}
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.75
	var equipment := {"room_id":"L01","room_low_shield_used":false,"room_first_kill_used":false}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: equipment[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 0.0
	equipment.delayed_shield_at = -1.0
	var modifiers := {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 0.0
	equipment.adapter = {"clock":0.0,"movement_time":0.0,"event_serial":0,"modifiers":modifiers,"self_status_sources":{}}
	var status := {"clock":0.0,"shock_cooldown":0.0,"states":{},"guards":{"equipment:EQ13":{"amount":20,"remaining":2.0}},"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}
	return {"snapshot_version":1,"mode":"safe_boundary","hero_id":"CH01","hp":int(stats.max_hp)-50,"resource":30,"ruleset_version":2,"scale_version":10,"resource_regen_remainder":0.0,"resource_decay_remainder":0.0,"player":player,"status":status,"equipment":equipment}

func migration_and_backend() -> void:
	var profile := fresh()
	profile.erase("equipment_class_migration")
	var old := specimen("EQ13")
	old.location = "equipped"
	profile.equipment[old.instance_id] = old
	profile.equipment[profile.loadout.head].location = "inventory"
	profile.loadout.head = old.instance_id
	profile.loadout_presets.CH01.head = old.instance_id
	var old_equipment: Dictionary = profile.equipment.duplicate(true)
	var before_value := Forging._cost({old.instance_id:old},"sell",{"instance_id":old.instance_id})
	var old_stats := Resolver.resolve("CH01",20,profile.loadout,profile.equipment,2,{},true)
	check(not old_stats.is_empty() and Resolver.resolve("CH01",20,profile.loadout,profile.equipment,2).is_empty(),"stat aggregation rejects wrong class; migration-only prior calculation available")
	var runtime: Dictionary = JSON.parse_string(JSON.stringify(safe_runtime(old_stats)))
	check(Snapshot.validate(runtime,"CH01",old_stats),"historical safe runtime fixture valid")
	var active := {"hero_id":"CH01","level":20,"ruleset_version":2,"loadout_snapshot":profile.loadout.duplicate(true),"equipment_snapshot":profile.equipment.duplicate(true),"expedition":{"runtime":runtime}}
	var input := {"profile":profile,"active_run":active}
	var migrated := Migration.upgrade_document(input)
	check(not migrated.is_empty(),"active V2 migration succeeds")
	if migrated.is_empty(): return
	check(input.profile.loadout.head == old.instance_id,"migration leaves input untouched")
	check(migrated.profile.loadout.head == "" and migrated.profile.loadout_presets.CH01.head == "" and migrated.active_run.loadout_snapshot.head == "","all camp/preset/run slots remove ineligible class")
	var retained: Dictionary = migrated.profile.equipment[old.instance_id]
	check(retained.location == "inventory" and Forging._cost({retained.instance_id:retained},"sell",{"instance_id":retained.instance_id}) == before_value,"old gear preserved in inventory at same sale value")
	for key: String in old:
		if key != "location": check(retained[key] == old[key],"owned field retained exactly "+key)
	var after: Dictionary = migrated.active_run.expedition.runtime
	check(after.hp <= runtime.hp and after.resource == runtime.resource and after.player == runtime.player,"migration never heals/refunds/resets any cooldown")
	check(not after.status.guards.has("equipment:EQ13"),"removed class equipment cannot keep its active shield")
	check(Migration.upgrade_document(migrated) == migrated,"migration repeats as exact no-op")
	# Real loader performs one atomic save and preserves the original document.
	var path := "user://test_equipment_classes/migration.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var document := {"schema_version":3,"revision":10,"profile_initialized":true,"profile":profile,"active_run":null}
	var file := FileAccess.open(AssetCatalog.resolve(path),FileAccess.WRITE); file.store_string(JSON.stringify(document)); file.close()
	var store := Store.new(path)
	var loaded := store.load_document()
	check(not loaded.is_empty() and loaded.profile.loadout.head == "" and store.warning == "STORAGE_CLASS_EQUIPMENT_UPDATED","real old-save load migrates and explains unequip")
	check(FileAccess.file_exists(AssetCatalog.resolve(path+".bak")) and JSON.parse_string(FileAccess.get_file_as_string(AssetCatalog.resolve(path+".bak"))).profile.loadout.head == old.instance_id,"original save preserved before atomic migration")
	var second := Store.new(path).load_document()
	check(not second.is_empty() and Acquisition._fingerprint(second.profile) == Acquisition._fingerprint(loaded.profile) and second.revision == loaded.revision,"migrated save reload exact with no second write")
	var game := root.get_node("Game")
	game.run = null; game.profile = migrated.profile; game.has_profile = true
	check(not game.equip_item(old.instance_id) and game.last_error == "CLASS_LOCKED","actual individual equip endpoint rejects wrong-class old gear")
	check(not game.equip_equipment_set("S01") and game.last_error == "CLASS_LOCKED","actual set equip endpoint cannot bypass")
	check(game.select_hero("CH02") and game.profile.loadout.head != old.instance_id,"class swap/preset cannot reuse forbidden equipment")

func role_checkpoint_lifecycle() -> void:
	var game := root.get_node("Game")
	for hero: String in Registry.heroes():
		for mode: String in ["fresh_entry","safe_boundary"]:
			game.run = null
			var profile := fresh()
			profile.selected_hero = hero
			profile.loadout = profile.loadout_presets[hero].duplicate(true)
			for id: String in profile.equipment: profile.equipment[id].location = "equipped" if id in profile.loadout.values() else "inventory"
			game.profile = profile
			game.has_profile = true
			check(game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":193}),"real expedition setup "+hero+mode)
			if game.run == null: continue
			if hero == "CH01" and mode == "safe_boundary":
				var boundary := Migration._fresh_boundary(game.run.expedition.runtime)
				for offer: Dictionary in game.expedition_snapshot().relic_offers:
					check(game.choose_run_relic(str(offer.offer_id), "skip", "", boundary),"skip initial relic through real transaction")
				var next: Dictionary = game.expedition_snapshot().next_node
				check(game.choose_expedition_node(int(next.node_index),str(next.room_id)) and game.advance_expedition_node(boundary),"enter real combat checkpoint for historical drop")
			var receipt: Dictionary = game.run.receipt().duplicate(true)
			var historical_pending := ""
			if hero == "CH01" and mode == "safe_boundary":
				historical_pending = add_historical_pending(receipt, hero)
				check(not historical_pending.is_empty(),"actual v1 wrong-class pending loot fixture found")
				profile.erase("equipment_class_migration")
			var old_stats := Resolver.resolve(hero,20,receipt.loadout_snapshot,receipt.equipment_snapshot,2,{},true,true)
			var runtime := {"snapshot_version":1,"mode":"fresh_entry","hero_id":hero,"hp":int(old_stats.max_hp),"resource":int(old_stats.starting_resource),"ruleset_version":2,"scale_version":10,"resource_regen_remainder":0.0,"resource_decay_remainder":0.0}
			if mode == "safe_boundary":
				runtime = safe_runtime(old_stats)
				runtime.hero_id = hero
				runtime.status.guards.clear()
				runtime.resource = 300
				runtime = Snapshot._json_keys(runtime)
			check(Snapshot.validate(runtime,hero,old_stats,true),"original old-growth runtime valid "+hero+mode)
			receipt.expedition.runtime = runtime
			profile.erase("hero_role_revision")
			var input := {"schema_version":3,"revision":1,"profile_initialized":true,"profile":profile,"active_run":receipt}
			var expected := Migration.upgrade_document(input)
			check(not expected.is_empty(),"growth-only migration no gear removal "+hero+mode)
			if expected.is_empty(): continue
			var after: Dictionary = expected.active_run.expedition.runtime
			check(after.mode == "safe_boundary" and after.hp <= runtime.hp and after.resource <= runtime.resource,"growth migration never heals or grants mana "+hero+mode)
			if mode == "safe_boundary": check(after.player == runtime.player,"all spent timers preserved "+hero)
			check(expected.profile.hero_role_revision == 1 and (expected.profile.equipment_class_migration.removed_slots.is_empty() if historical_pending.is_empty() else expected.profile.equipment_class_migration.removed_slots.size() == 1),"role revision migration independent or atomic with class migration "+hero+mode)
			check(Store._valid_document(expected),"full real migrated checkpoint validates "+hero+mode)
			if not historical_pending.is_empty():
				check(expected.active_run.expedition.pending_equipment == receipt.expedition.pending_equipment and expected.active_run.expedition.loot_events == receipt.expedition.loot_events,"v1 pending records and frozen event receipts unchanged through loadout/role migration")
				check(historical_pending not in expected.active_run.loadout_snapshot.values(),"historical pending wrong-class item stays owned without equipped contribution")
			var path := "user://test_equipment_classes/role-"+hero+mode+str(Time.get_ticks_usec())+".json"
			var file := FileAccess.open(AssetCatalog.resolve(path),FileAccess.WRITE); file.store_string(JSON.stringify(input)); file.close()
			game.profile_path = path
			game.reload_profile()
			check(game.run != null and game.last_error.is_empty() and game.profile.hero_role_revision == 1,"real reload resumes migrated adventure "+hero+mode)
			if game.run != null:
				check(game.run.hp == after.hp and game.run.resource == after.resource,"resume retains exact migrated survival values "+hero+mode)
			game.run = null

func add_historical_pending(receipt: Dictionary, hero: String) -> String:
	var loot: Script = load(AssetCatalog.resolve("res://scripts/domain/expedition/expedition_rewards.gd"))
	for serial in 2000:
		var node_index := int(receipt.expedition.node_index)
		var event_id := str(receipt.id)+":node:"+str(node_index)+":kill:historic-"+str(serial)
		var context: Dictionary = loot.context(receipt.expedition,receipt.id,hero,event_id,"elite",0,1)
		var result := Acquisition._roll_event_v1(context)
		if not result.get("ok",false):
			return ""
		if not result.triggered or result.items.is_empty() or Registry.equipment(result.items[0].template_id,2).set_id != "S01": continue
		var item: Dictionary = result.items[0]
		var earned: Dictionary = loot.materials("elite", "B01", 0)
		receipt.expedition.loot_events[event_id] = {"node_index":node_index,"zone_index":0,"actor_id":"M01","ordinal":0,"result":result,"grant_items":true,"materials":earned,"research_materials":{},"gold":0,"tutorial_xp":0}
		receipt.expedition.pending_materials = earned
		receipt.expedition.pending_equipment[item.instance_id] = item.duplicate(true)
		receipt.expedition.claimed_drop_ids[item.instance_id] = {"equipment_id":item.instance_id,"event_id":event_id,"result":"pending","gold":0,"field_decision":"equip"}
		receipt.expedition.equipment_discoveries.append(item.template_id)
		receipt.equipment_snapshot[item.instance_id] = item.duplicate(true)
		receipt.loadout_snapshot[Registry.equipment(item.template_id,2).slot] = item.instance_id
		check(loot.add(receipt.expedition,receipt.id,hero,event_id,"elite",0,"M01"),"existing v1 loot event replays against old hero-less context")
		return item.instance_id
	return ""
