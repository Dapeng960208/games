extends SceneTree
## One focused B05 contract check. No production save or release activation.
const Rules = preload("res://scripts/infrastructure/content/runtime_rules.gd")
const Acquisition = preload("res://scripts/domain/equipment/equipment_acquisition.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Growth = preload("res://scripts/domain/progression/hero_progression.gd")
const Registry = preload("res://scripts/infrastructure/content/content_registry.gd")
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Native = preload("res://scripts/domain/equipment/numerical_profile.gd")
const Economy = preload("res://scripts/domain/equipment/instance_economy.gd")
const Creation = preload("res://scripts/domain/equipment/instance_transactions.gd")
const Forging = preload("res://scripts/domain/equipment/instance_forging.gd")
const Loot = preload("res://scripts/domain/expedition/expedition_rewards.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func event(hero: String, source: String = "room", level: int = 25, difficulty: int = 4) -> Dictionary:
	return {"event_id":"b05-test:" + hero + ":" + source + ":" + str(level) + ":" + str(difficulty),"seed":510025,"source":source,"race_id":"B05","difficulty":difficulty,"challenge_level":level,"power_type":"magic" if hero == "CH03" else "physical","hero_id":hero,"wish_slot":"weapon","force_gold":false}

func spec(id: String, hero: String, power: String, rarity: String = "purple") -> Dictionary:
	return {"instance_id":"b05-instance:" + id + ":" + power + ":" + rarity,"source_event_id":"b05-test:explicit","template_id":id,"rarity":rarity,"power_type":power,"hero_id":hero,"item_level":25,"source":"drop"}

func _initialize() -> void:
	var original := Rules.parameters()
	check(Growth.level_cap() in [20,25], "only approved B04/B05 release caps")
	if Growth.level_cap() == 20:
		check(not Acquisition.roll_event(event("CH01")).ok, "B05 natural creation blocked before release")
		check(Acquisition.roll_item(spec("B05-SW-weapon","CH01","physical"),1).is_empty(), "B05 explicit creation blocked before release")
	var old_receipts: Array = []
	var golden := {1:"08ce9f701443b3a85f65a4279ec68315fa16e1be790bf7eab64c2cc88bf4d09c",2:"3bf08d214c6326166af98e4549906fb15c55820cb0b3d496cda1dc05e7fc8788"}
	for version in [1,2]:
		var request := event("CH01", "boss",20)
		request.race_id = "B04"
		request.event_id = "b05-archive-golden-v" + str(version)
		request.seed = 54873
		if version == 1: request.erase("hero_id")
		old_receipts.append(Acquisition._roll_event_version(request,version))
		check(Acquisition.event_result_valid(old_receipts.back()), "historical receipt verifies before release " + str(version))
		check(old_receipts.back().result_fingerprint == golden[version], "exact original-HEAD historical receipt " + str(version))
	Rules._parameters.implemented_chapters = 5 # Process-only candidate activation.
	var neutral_v3 := event("CH01","boss")
	neutral_v3.event_id = "b05-neutral-v3-golden"
	neutral_v3.seed = 54873
	old_receipts.append(Acquisition.roll_event(neutral_v3))
	check(old_receipts.back().result_fingerprint == "b530017b91dbc91d0320e17ccb3cc36fe32e23b219067fbe3f6ef3906de7e650", "neutral v3 retains exact pre-bias seeded receipt")
	check(Growth.level_cap() == 25 and Growth.rank_cap() == 7, "B05 release supports25 and inherited talent divisor")
	check(Acquisition._canonical(Growth.thresholds().slice(20)) == [4040,4520,5040,5600,6200], "frozen XP21–25 exact")
	for hero: String in ["CH01","CH02","CH03"]:
		var pool := Acquisition.natural_pool("B05",hero)
		var count := 0
		check(pool.size() == 8, "all eight B05 slots " + hero)
		for slot: String in pool:
			check(not pool[slot].is_empty(), "nonempty slot " + hero + slot)
			count += pool[slot].size()
			for id: String in pool[slot]:
				var template := Registry.equipment(id,2)
				check(template.race_id == "B05" and template.drop_origin == "B05" and hero in template.allowed_heroes, "strict same-race/class pool " + id)
		check(count == 19, "exactly19 legal natural templates " + hero)
		for level in [21,23,25]:
			for source: String in ["room","chest","boss","summon"]:
				for difficulty in range(5):
					var request := event(hero,source,level,difficulty)
					var result := Acquisition.roll_event(request)
					check(result.ok, "B05 source generation " + hero + source + str(level) + str(difficulty))
					if not result.ok: continue
					check(result.generator_version == 3 and Acquisition.event_result_valid(JSON.parse_string(JSON.stringify(result))), "v3 frozen JSON receipt")
					check(Acquisition.roll_event(request,result) == result, "one-time frozen retry")
					for item: Dictionary in result.items:
						check(Instances.validate(item).is_empty(), "generated B05 instance valid")
						check(item.item_level >= 20 and item.item_level <= 25 and (source != "boss" or item.item_level == level), "frozen B05 item levels")
						check(item.class_policy_version == 2 and item.acquired_for_hero == hero and item.power_type == request.power_type, "class-aware fixed power provenance")
						check(item.enhancement_rank <= (1 if item.rarity == "gold" else 5), "natural rank ceiling")
		check(Growth.hero_base(Registry.hero(hero),25).talent_points_available == 24, "Lv25 grants24 points")
	check(Acquisition.natural_pool("B05").is_empty() and Acquisition.natural_pool("B05","CH04").is_empty() and Acquisition.natural_pool("B06","CH01").is_empty(), "no unfiltered B05, fourth class or future fallback")
	for id: String in Acquisition.V3.TEMPLATES:
		var template: Dictionary = Acquisition.V3.TEMPLATES[id]
		for power: String in template.power_types:
			var hero: String = template.allowed_heroes[0] if template.allowed_heroes.size() == 1 else ("CH03" if power == "magic" else "CH01")
			for rarity: String in Acquisition.RARITIES:
				var item := Acquisition.roll_item(spec(id,hero,power,rarity),92)
				check(not item.is_empty() and Instances.validate(item).is_empty(), "all35 templates/types/rarities " + id + power + rarity)
				if item.is_empty(): continue
				check(Instances.affix_weights(id,power) == Acquisition._affix_weights(id,power), "power-specific tendencies exact")
				if template.allowed_heroes.size() == 3:
					var frozen := JSON.stringify(item)
					for wearer: String in ["CH01","CH02","CH03"]: check(Instances.can_equip(item,wearer,25), "same shared instance usable by every class")
					check(JSON.stringify(item) == frozen, "changing wearer cannot change fixed power or rolls")
	_test_bias()
	_test_history(old_receipts)
	_test_progression_save_transactions()
	Rules._parameters = original
	print("B05 acquisition/progression/save: %d checks, failures=%s" % [checks,failures])
	quit(0 if failures.is_empty() else 1)

func _test_history(old_receipts: Array) -> void:
	var biased := event("CH03","boss")
	biased.room_id = "BO05"
	var current := Acquisition.roll_event(biased)
	var catalog := Registry._equipment_v2.duplicate(true)
	var rules := Rules.parameters()
	Registry._equipment_v2["B05-SM-weapon"].price += 1
	Rules._parameters.normal_quality_weights = [[100,0,0,0]]
	check(Acquisition.current_version_error() == "generation_version_mismatch", "unversioned catalog/rule drift blocks new generation")
	Acquisition._validated_fingerprints.clear()
	for receipt: Dictionary in old_receipts + [current]:
		var persisted: Dictionary = JSON.parse_string(JSON.stringify(receipt))
		check(Acquisition.event_result_valid(persisted), "v1/v2/v3 historical receipts ignore mutable catalog")
		check(Acquisition.roll_event(persisted.context,persisted) == persisted, "historical retry preserves receipt byte-values")
	Registry._equipment_v2 = catalog
	Rules._parameters = rules
	var bad := current.duplicate(true)
	bad.items[0].main_rolls[bad.items[0].main_rolls.keys()[0]] = 101
	bad.erase("result_fingerprint")
	bad = Acquisition._seal(bad)
	check(not Acquisition.event_result_valid(bad), "rehashed forged result is rejected")
	check(Economy.historical_purchase_baseline("B05-SW-weapon","green",25,1) == -1, "v1 economy cannot authorize B05")
	check(Economy.historical_purchase_baseline("EQ01","green",21,1) == -1, "v1 economy retains cap20")

func _test_progression_save_transactions() -> void:
	var profile := Native.fresh(Store.fresh_profile())
	profile.hero_xp.CH01 = 3600
	profile.bosses = ["BO01","BO02","BO03","BO04"]
	var gained := Growth.award(profile,"CH01",2600,"b05-test:level25","B05")
	check(not gained.is_empty() and gained.added == 2600 and gained.profile.hero_xp.CH01 == 6200, "old Lv20 save grows naturally to25")
	if gained.is_empty(): return
	var awarded := Growth.award(gained.profile,"CH01",360,"b05-test:research","B05")
	check(awarded.added == 0 and awarded.profile.materials == {"forge":4,"race:B05":1}, "cap25 overflow retains B05 material identity")
	check(Growth.award(awarded.profile,"CH01",360,"b05-test:research","B05").replayed, "research receipt idempotent")
	profile = awarded.profile
	profile.permanent_gold = 100000
	profile.materials = {"forge":1000,"race:B05":1000,"core:B05":100}
	var request := {"hero_id":"CH01","template_id":"B05-SW-weapon","rarity":"purple","power_type":"physical","item_level":25}
	var crafted := Creation.craft(profile,"b05-test:craft",request)
	check(crafted.ok, "B05 craft authorized by BO04 " + str(crafted.error))
	if not crafted.ok: return
	check(crafted.receipt.version == 2 and crafted.receipt.gold == 688 and crafted.receipt.materials == {"forge":24,"race:B05":12,"core:B05":2}, "version2 economy uses unchanged exact costs")
	check(Creation.validate_ledger(JSON.parse_string(JSON.stringify(crafted.profile.instance_transactions))), "version2 creation ledger JSON round-trip")
	check(Creation.craft(crafted.profile,"b05-test:craft",request).profile == crafted.profile, "craft retry debits once")
	var item: Dictionary = crafted.receipt.items[0]
	var enhanced := Forging.transact(crafted.profile,"b05-test:enhance","enhance",{"hero_id":"CH01","instance_id":item.instance_id})
	check(enhanced.ok, "B05 enhancement accepts frozen race " + str(enhanced.error))
	if enhanced.ok: profile = enhanced.profile
	else: profile = crafted.profile
	profile.bosses.append("BO05")
	var document := {"schema_version":3,"revision":1,"profile_initialized":true,"profile":profile,"active_run":null}
	check(Store._valid_document(document), "Lv25 B05/BO05/material/forge profile validates")
	check(Store._valid_document(JSON.parse_string(JSON.stringify(document))), "whole profile JSON round-trip preserves values")
	var store := Store.new("user://b05_acquisition_contract_" + str(Time.get_ticks_usec()) + "/profile.json")
	store.load_document()
	check(store.save_document(profile), "isolated on-disk B05 save " + store.last_error)
	var reopened := Store.new(store.path)
	var loaded := reopened.load_document()
	check(not loaded.is_empty() and Loot.same(loaded.get("profile",{}),profile), "isolated disk reload preserves every profile value")
	profile.gold_pity.erase("B05")
	check(Store._valid_document(document), "old four-key pity map remains valid")
	check(Loot.pity_valid({"B01":0,"B02":0,"B03":0,"B04":0}) and Loot.pity_valid({"B05":3}), "old/new pity snapshots accepted")
	check(Loot.material_map_valid({"race:B05":12,"core:B05":2}) and Loot.material_map_valid({"race:B06":1}) and not Loot.material_map_valid({"race:B07":1}), "implemented B05/B06 material maps; future chapters rejected")
	var prior := Acquisition.roll_event(event("CH01","boss"))
	var pending := {"pending_equipment":{},"pending_materials":{"forge":8,"race:B05":4,"core:B05":1},"difficulty":0,"loot_events":{}}
	for dropped: Dictionary in prior.items: pending.pending_equipment[dropped.instance_id] = dropped
	var count_before: int = profile.equipment.size()
	var retained := Loot.bank(profile,pending,["BO05"])
	check(retained.size() == prior.items.size() and profile.equipment.size() == count_before + prior.items.size(), "pending B05 drops bank only through settlement")
	check(Loot.bank(profile,pending,["BO05"]).is_empty(), "duplicate bank does not duplicate instances")

func _test_bias() -> void:
	var pool := Acquisition.natural_pool("B05","CH01")
	var neutral := event("CH01","normal")
	neutral.wish_slot = ""
	for slot: String in pool:
		var weights := Acquisition.template_weights(pool[slot],neutral)
		for weight: Variant in weights.values(): check(weight == 1, "missing bias context is neutral")
	var preferred := neutral.duplicate(true)
	preferred.monster_id = "B05-M10"
	var mass := Acquisition.preference_slot_weights(pool,preferred)
	var total := 0
	for slot: String in mass:
		check(int(mass[slot]) == (12 if slot == "head" else (8 if slot == "ring" else 6)), "preserve slot/template baseline mass " + slot)
		total += int(mass[slot])
	check(total == 56, "M10 example total56, no global uniform template prior")
	var ring := Acquisition.template_weights(pool.ring,preferred)
	check(ring["B05-U02"] == 2 and ring["B05-SW-ring"] == 1 and ring["B05-SU-ring"] == 1, "unique bias is relative2:1:1")
	preferred.wish_slot = "weapon"
	var excluded := Acquisition.preference_slot_weights(pool,preferred,"weapon")
	check(not excluded.has("weapon") and excluded.values().reduce(func(a: int,b: Variant) -> int: return a+int(b),0) == 50, "non-wish mass excludes weapon and totals50")
	var overlap := neutral.duplicate(true)
	overlap.room_id = "L28"
	overlap.monster_id = "B05-M04"
	var overlap_weights := Acquisition.template_weights(pool.ring,overlap)
	for weight: Variant in overlap_weights.values(): check(weight == 2, "room+monster+unique union never multiplies to4 or8")
	for pair: Array in [["room_id","L31"],["room_id","L01"],["room_id",""],["room_id",5],["room_id",null],["monster_id","B05-M19"],["monster_id","B06-M01"],["monster_id","spawn:42"],["monster_id",""]]:
		var bad := neutral.duplicate(true)
		bad[pair[0]] = pair[1]
		check(not Acquisition.roll_event(bad).ok, "invalid provided context rejects " + str(pair))
	var cross_race := preferred.duplicate(true)
	cross_race.race_id = "B04"
	cross_race.challenge_level = 20
	check(not Acquisition.roll_event(cross_race).ok, "B05 provenance cannot bias another race")
	var nonkill := event("CH01")
	nonkill.monster_id = "B05-M10"
	check(not Acquisition.roll_event(nonkill).ok, "monster species context is kill-only")
	for version in [1,2]:
		var old := neutral.duplicate(true)
		old.challenge_level = 20
		old.room_id = "L25"
		if version == 1: old.erase("hero_id")
		check(Acquisition._event_error(old,version) == "unknown_event_field", "old generators reject newly introduced provenance")
	var neutral_ring := neutral.duplicate(true)
	neutral_ring.source = "room"
	var harmless := neutral_ring.duplicate(true)
	harmless.room_id = "L25"
	check(not Acquisition._has_preference({"ring":pool.ring},harmless), "valid context without a matching preference is neutral")
	var before := Acquisition._event_item(neutral_ring,{"ring":pool.ring},0,false,3)
	var after := Acquisition._event_item(harmless,{"ring":pool.ring},0,false,3)
	before.erase("source_metadata")
	after.erase("source_metadata")
	check(before == after, "no applicable bias retains exact seeded item values")
	var hits := 0
	for index in range(128):
		var plain := event("CH01")
		plain.event_id = "b05-bias-wish:" + str(index)
		var biased := plain.duplicate(true)
		biased.room_id = "L25"
		var original := Acquisition.roll_event(plain)
		var changed := Acquisition.roll_event(biased)
		check(original.ok and changed.ok and original.items.size() == changed.items.size() and original.triggered == changed.triggered, "bias leaves trigger/count unchanged")
		if not original.ok or not changed.ok: continue
		var old_slot: String = Registry.equipment(original.items[0].template_id,2).slot
		var new_slot: String = Registry.equipment(changed.items[0].template_id,2).slot
		check((old_slot == "weapon") == (new_slot == "weapon"), "original wish-hit bit is preserved exactly")
		check(original.items[0].rarity == changed.items[0].rarity, "bias leaves same-seed rarity unchanged")
		if old_slot == "weapon": hits += 1
	check(hits > 0 and hits < 128, "exercise both locked-wish and weighted non-wish branches")

	# Stage only the room lookup in memory until the lead activates world data.
	Loot.Rewards.Catalog._ensure_loaded()
	var room_catalog: Dictionary = Loot.Rewards.Catalog._rooms.duplicate(true)
	Loot.Rewards.Catalog._rooms.rooms["L28"] = {"biome_id":"B05","enemy_level":23}
	var route := {"route":{"nodes":[{"room_id":"L28"}]},"node_index":0,"difficulty":0,"loot_seed":5,"wish_slot":"weapon","pity_snapshot":{},"loot_events":{}}
	var wired := Loot.context(route,"b05-context-run","CH01","b05-context-event","normal",1,3,"B05-M10")
	check(wired.get("room_id") == "L28" and wired.get("monster_id") == "B05-M10", "route room and species flow into v3 receipt")
	for version in [1,2]:
		var prior := Loot.context(route,"b05-context-run","CH01","b05-context-event","normal",1,version,"B05-M10")
		check(not prior.has("room_id") and not prior.has("monster_id"), "old context version omits added provenance")
	var old_neutral := wired.duplicate(true)
	old_neutral.erase("room_id")
	old_neutral.erase("monster_id")
	route.loot_events["b05-context-event"] = {"result":Acquisition.roll_event(old_neutral),"actor_id":"B05-M10"}
	check(Loot.add(route,"b05-context-run","CH01","b05-context-event","normal",1,"B05-M10"), "old neutral v3 Loot retry stays neutral")
	check(not Loot.add(route,"b05-context-run","CH01","b05-context-event","normal",1,"B05-M11"), "historical retry cannot change recorded actor")
	route.route.nodes[0].room_id = "L01"
	var old_chapter := Loot.context(route,"b05-context-run","CH01","b05-context-event","normal",1,3,"M01")
	check(not old_chapter.has("room_id") and not old_chapter.has("monster_id"), "B01–B04 never acquire B05 provenance fields")
	Loot.Rewards.Catalog._rooms = room_catalog
