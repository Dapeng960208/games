extends SceneTree
## Lawful B06 factory/persistence fixtures. Not a strength calibration or natural-play test.
const Rules = preload("res://config/numerical_rules.gd")
const Acquisition = preload("res://scripts/core/equipment_acquisition.gd")
const Instances = preload("res://scripts/core/equipment_instances.gd")
const Growth = preload("res://scripts/core/hero_progression.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
const Store = preload("res://scripts/core/profile_store.gd")
const Native = preload("res://scripts/core/numerical_profile.gd")
const Forging = preload("res://scripts/core/instance_forging.gd")
const Loot = preload("res://scripts/core/expedition_rewards.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
static func event(hero: String, room: String = "BO06", source: String = "boss", difficulty: int = 4) -> Dictionary:
	return {"event_id":"b06-contract:"+hero+":"+room+":"+source+":"+str(difficulty),"seed":260028,"source":source,"race_id":"B06","room_id":room,"difficulty":difficulty,"challenge_level":Acquisition.V4.ROOM_LEVELS[room],"power_type":"magic" if hero=="CH03" else "physical","hero_id":hero,"wish_slot":"weapon","force_gold":false}
static func spec(id: String, hero: String, power: String, rarity: String = "purple", level: int = 30) -> Dictionary:
	return {"instance_id":"b06-fixture:"+id+":"+hero+":"+power+":"+rarity+":"+str(level),"source_event_id":"b06-contract:explicit","template_id":id,"rarity":rarity,"power_type":power,"hero_id":hero,"item_level":level,"source":"drop"}
## All eight genuine legal pieces, usable by later isolated combat benchmarks.
## Rolls are factory-derived; no caller-written affixes, ranks or fake provenance.
static func loadout_fixture(hero: String, shared: bool = false, rarity: String = "purple", level: int = 30) -> Dictionary:
	var result := {"equipment":{},"loadout":{}}
	var sid: String = "B06-SU" if shared else {"CH01":"B06-SW","CH02":"B06-SG","CH03":"B06-SM"}.get(hero,"")
	if sid.is_empty(): return {}
	for slot: String in Registry.slots(2):
		var id: String = sid+"-"+("accessory" if slot=="charm" else slot)
		var item := Acquisition.roll_item(spec(id,hero,"magic" if hero=="CH03" else "physical",rarity,level),260028)
		if item.is_empty(): return {}
		item.location = "inventory"
		result.equipment[item.instance_id] = item
		result.loadout[slot] = item.instance_id
	return result
func _initialize() -> void:
	var original := Rules.parameters()
	check(int(original.implemented_chapters)==4,"shipped gate remains four chapters")
	if Growth.level_cap()<30:
		check(not Acquisition.roll_event(event("CH01")).ok,"unreleased natural B06 blocked")
		check(Acquisition.roll_item(spec("B06-SW-weapon","CH01","physical"),1).is_empty(),"unreleased explicit B06 blocked")
	Rules._parameters.implemented_chapters = 6 # Process-only isolated contract fixture.
	check(Acquisition.current_version_error().is_empty(),"registered frozen contract matches")
	_history()
	for hero: String in ["CH01","CH02","CH03"]:
		var pool := Acquisition.natural_pool("B06",hero)
		var count := 0
		check(pool.size()==8,"eight legal slots "+hero)
		for slot: String in pool:
			count += pool[slot].size()
			for id: String in pool[slot]:
				var template := Registry.equipment(id,2)
				check(template.race_id=="B06" and template.drop_origin=="B06" and hero in template.allowed_heroes,"only true B06/legal class "+id)
		check(count==19,"exact legal pool19 "+hero)
		for room: String in Acquisition.V4.ROOM_LEVELS:
			for source: String in (["boss","summon"] if room=="BO06" else ["room","chest","normal","elite","summon"]):
				for difficulty in range(5):
					var request := event(hero,room,source,difficulty)
					var result := Acquisition.roll_event(request)
					check(result.ok,"event "+str(request))
					if not result.ok: continue
					check(result.generator_version==4 and Acquisition.event_result_valid(JSON.parse_string(JSON.stringify(result))),"frozen v4 JSON receipt")
					check(Acquisition.roll_event(request,result)==result,"repeat returns exact receipt")
					for item: Dictionary in result.items:
						check(Instances.validate(item).is_empty(),"valid natural item "+str(Instances.validate(item)))
						check(item.template_id.begins_with("B06-") and item.class_policy_version==3 and item.acquired_for_hero==hero,"genuine class-stamped B06")
						check(item.item_level>=25 and item.item_level<=30 and (source!="boss" or item.item_level==30),"fixed-room iLv bounds")
						check(item.enhancement_rank<=(1 if item.rarity=="gold" else 5),"approved natural rank caps")
		var fixture := loadout_fixture(hero)
		check(fixture.get("equipment",{}).size()==8 and fixture.get("loadout",{}).size()==8,"lawful strength fixture "+hero)
	for id: String in Acquisition.V4.TEMPLATES:
		var template: Dictionary = Acquisition.V4.TEMPLATES[id]
		for power: String in template.power_types:
			var hero: String = template.allowed_heroes[0] if template.allowed_heroes.size()==1 else ("CH03" if power=="magic" else "CH01")
			for rarity: String in Acquisition.RARITIES:
				var item := Acquisition.roll_item(spec(id,hero,power,rarity),92)
				check(not item.is_empty() and Instances.validate(item).is_empty(),"all35/rarities/powers "+id+rarity+power)
				if item.is_empty(): continue
				check(Forging._item_error(item).is_empty(),"natural enhancement price peak persistence "+id)
				check(Instances.affix_weights(id,power)==Acquisition._affix_weights(id,power,4),"frozen tendency weights")
				if template.allowed_heroes.size()==3:
					var before := JSON.stringify(item)
					for wearer: String in ["CH01","CH02","CH03"]: check(Instances.can_equip(item,wearer,30),"shared piece equips all heroes")
					check(JSON.stringify(item)==before,"shared fixed power never changes")
	check(Acquisition.natural_pool("B06").is_empty() and Acquisition.natural_pool("B06","CH04").is_empty() and Acquisition.natural_pool("B06","CH01",3).is_empty(),"no absent/unknown class or v3 fallback")
	_bad_inputs()
	_drift()
	_pending_replay()
	_save()
	Rules._parameters = original
	print("B06 acquisition/save: %d checks, %d failures: %s" % [checks,failures.size(),failures])
	quit(0 if failures.is_empty() else 1)
func _history() -> void:
	for version in [1,2,3]:
		var request := event("CH01")
		request.erase("room_id")
		request.race_id="B04" if version<3 else "B05"
		request.challenge_level=20 if version<3 else 25
		request.seed=54873
		request.event_id="b05-archive-golden-v"+str(version) if version<3 else "b05-neutral-v3-golden"
		if version==1: request.erase("hero_id")
		var result := Acquisition._roll_event_version(request,version)
		var hashes := {1:"08ce9f701443b3a85f65a4279ec68315fa16e1be790bf7eab64c2cc88bf4d09c",2:"3bf08d214c6326166af98e4549906fb15c55820cb0b3d496cda1dc05e7fc8788",3:"b530017b91dbc91d0320e17ccb3cc36fe32e23b219067fbe3f6ef3906de7e650"}
		check(result.get("result_fingerprint")==hashes[version],"exact v1/v2/v3 history "+str(version))
		check(Acquisition.event_result_valid(result),"historical receipt validates "+str(version))
		if version==3: check(Acquisition.roll_event(request).result_fingerprint==hashes[version],"new B05 keeps v3 RNG domain")
func _bad_inputs() -> void:
	for change: Dictionary in [{"challenge_level":29},{"room_id":"L01"},{"room_id":"L31"},{"monster_id":"B05-M01"},{"hero_id":"CH04"}]:
		var bad := event("CH01")
		bad.merge(change,true)
		check(not Acquisition.roll_event(bad).ok,"reject invalid room/level/class "+str(change))
	var result := Acquisition.roll_event(event("CH01"))
	var forged := result.duplicate(true)
	forged.items[0].item_level=29
	forged=Acquisition._seal(forged)
	check(not Acquisition.event_result_valid(forged),"rehashed forged receipt fails regeneration")
	var exclusive := Acquisition.roll_item(spec("B06-SW-ring","CH01","physical"),9)
	check(not Instances.can_equip(exclusive,"CH03",30),"exclusive ring is not cross-class")
	var altered := exclusive.duplicate(true)
	altered.source_metadata.generator_version=3
	check(not Instances.validate(altered).is_empty(),"B06 cannot borrow v3 provenance")
func _save() -> void:
	var profile := Native.fresh(Store.fresh_profile())
	profile.hero_xp.CH01=Growth.thresholds().back()
	profile.bosses=["BO01","BO02","BO03","BO04","BO05"]
	var gained := Growth.award(profile,"CH01",360,"b06-contract:xp","B06",true)
	check(not gained.is_empty(),"B06 XP research receipt registered")
	if gained.is_empty(): return
	profile=gained.profile
	var request := event("CH01")
	var count_before: int = profile.equipment.size()
	var dropped := Acquisition.roll_event(request)
	var pending := {"pending_equipment":{},"pending_materials":{"forge":8,"race:B06":4,"core:B06":1},"difficulty":0,"loot_events":{}}
	for item: Dictionary in dropped.items: pending.pending_equipment[item.instance_id]=item
	check(profile.equipment.size()==count_before,"drop remains unsettled before bank")
	var ids := Loot.bank(profile,pending,["BO06"])
	check(ids.size()==dropped.items.size() and profile.equipment.size()==count_before+ids.size(),"extraction bank preserves distinct IDs")
	for id: String in ids: check(profile.equipment[id].location=="inventory" and profile.equipment[id].template_id.begins_with("B06-"),"banked real B06 inventory")
	profile.bosses.append("BO06")
	var path := "user://test_b06_candidate/acquisition_"+str(Time.get_ticks_usec())+".json"
	var store := Store.new(path)
	store.load_document()
	check(store.save_document(profile),"B06 isolated profile saves: "+store.last_error)
	var reopened := Store.new(path)
	var loaded := reopened.load_document()
	check(not loaded.is_empty() and Loot.same(loaded.get("profile",{}),profile),"disk reload preserves B06 records and receipts")
	check(Loot.material_map_valid({"race:B06":1,"core:B06":1}) and Loot.pity_valid({"B06":3}),"B06 materials and pity registered")
	check(not Loot.material_map_valid({"race:B07":1}),"future materials remain excluded")
	check(Growth.award(profile,"CH01",360,"b06-contract:xp","B06",true).replayed,"XP retry never grants twice")

func _drift() -> void:
	var result := Acquisition.roll_event(event("CH02","L34","room"))
	var original: Dictionary = Registry._equipment_v2.duplicate(true)
	Registry._equipment_v2["B06-SG-weapon"].price += 1
	check(Acquisition.current_version_error()=="generation_version_mismatch","unversioned B06 catalog drift blocks new generation")
	Acquisition._validated_fingerprints.clear()
	check(Acquisition.event_result_valid(JSON.parse_string(JSON.stringify(result))),"v4 receipt validates only from immutable archive")
	check(Acquisition.roll_event(result.context,result)==result,"frozen retry survives live drift")
	Registry._equipment_v2=original

func _pending_replay() -> void:
	Loot.Rewards.Catalog._ensure_loaded()
	var catalog: Dictionary = Loot.Rewards.Catalog._rooms.duplicate(true)
	Loot.Rewards.Catalog._rooms.rooms["L31"]={"biome_id":"B06","enemy_level":26}
	var route := {"route":{"nodes":[{"room_id":"L31"}]},"node_index":0,"difficulty":0,"loot_seed":260031,"wish_slot":"weapon","pity_snapshot":{},"loot_events":{},"pending_equipment":{},"pending_materials":{},"claimed_drop_ids":{},"equipment_discoveries":[]}
	check(Loot.add(route,"b06-pending","CH01","b06-pending:room","room"),"live reward owner produces pending B06")
	var before: Dictionary = route.duplicate(true)
	check(Loot.add(route,"b06-pending","CH01","b06-pending:room","room") and route==before,"duplicate event neither rerolls nor grants gear/materials")
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(route))
	check(Loot.add(reloaded,"b06-pending","CH01","b06-pending:room","room") and Loot.same(reloaded,before),"JSON resumed pending journal remains idempotent")
	check(not Loot.add(reloaded,"b06-pending","CH02","b06-pending:room","room"),"same event cannot change acquisition hero")
	check(route.pending_equipment.size()==1 and route.pending_equipment.values()[0].template_id.begins_with("B06-"),"pending record never substitutes B05")
	Loot.Rewards.Catalog._rooms=catalog
