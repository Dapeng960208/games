extends Node
## Isolated transaction checks; room completions exercise the production save
## path. This fixture does not claim natural combat or balance acceptance.
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Skills = preload("res://scripts/domain/progression/skill_progression.gd")
const RING := "B10-EASTER-RING"
var checks := 0
var failures: Array[String] = []
var stage_error := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func boundary() -> Dictionary:
	var hero: String = Game.run.hero_id
	var player := {"cooldowns":{},"passive_count":0,"walk_distance":0.0,"aim_direction":[1.0,0.0],"cast_serial":0,"role_state":Snapshot.initial_role_state(hero)}
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.0
	for id: String in Skills.skill_ids(hero): player.cooldowns[id] = 0.0
	var equipment := {"room_id":"","room_low_shield_used":false,"room_first_kill_used":false}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: equipment[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 0.0
	equipment.dash_time = -100.0
	equipment.delayed_shield_at = -1.0
	var modifiers := {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 1.0 if key.ends_with("_scale") else 0.0
	equipment["adapter"] = {"clock":0.0,"movement_time":0.0,"event_serial":0,"modifiers":modifiers}
	var value: Dictionary={"snapshot_version":2,"mode":"safe_boundary","hero_id":hero,"hp":int(Game.run.hp),"resource":int(Game.run.resource),
		"ruleset_version":2,"scale_version":10,"resource_regen_remainder":0.0,"resource_decay_remainder":0.0,"player":player,"equipment":equipment,
		"status":{"clock":0.0,"shock_cooldown":0.0,"states":{},"guards":{},"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}}
	# Exercise the persisted JSON shape, including String keys and numeric
	# roundtrips. Production capture normalizes engine-only Dictionary keys too.
	return JSON.parse_string(JSON.stringify(value))

func stop_at(stage: String) -> bool:
	stage_error=stage+": "+Game.last_error
	printerr("B10_RING_STAGE: "+stage_error)
	return false

func begin(hero: String, difficulty: int, capacity: int = 0) -> bool:
	stage_error=""
	Game.run = null
	Game._pending_outcome = ""
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	if not Game.new_profile(): return stop_at("new profile")
	var profile: Dictionary = Game.profile.duplicate(true)
	profile.bosses = ["BO01","BO02","BO03","BO04","BO05","BO06","BO09"]
	for id: String in ProfileStore.HERO_IDS: profile.hero_xp[id] = int(Game.Progression.thresholds().back())
	profile["inventory_capacity"] = capacity
	if not Game._commit_profile(profile): return stop_at("prior progression setup")
	if not Game.select_hero(hero): return stop_at("select "+hero)
	return depart(difficulty)

func depart(difficulty: int = 4) -> bool:
	return true if Game.start_run({"expedition":true,"biome_id":"B10","difficulty":difficulty,"seed":1735}) else stop_at("B10 departure")

func complete_boss() -> bool:
	while Game.run != null:
		if not Snapshot.validate(boundary(),Game.run.hero_id,Game.run.stats): return stop_at("strict JSON boundary")
		for offer: Dictionary in Game.expedition_snapshot().relic_offers:
			if not Game.choose_run_relic(str(offer.offer_id), "skip", "", boundary()): return stop_at("relic skip "+str(offer.offer_id))
		var next: Dictionary = Game.expedition_snapshot().next_node
		if next.is_empty(): return str(Game.run.expedition.route.nodes[-1].room_id) == "BO10" and Game.run.expedition.phase == "cleared"
		if not Game.choose_expedition_node(int(next.node_index), str(next.room_id)): return stop_at("choose "+str(next.room_id))
		if not Game.advance_expedition_node(boundary()): return stop_at("advance "+str(next.room_id))
		if Game.run.expedition.phase == "safe": continue
		var completion: String = Game.run.id + ":node:" + str(int(Game.run.expedition.node_index)) + ":complete"
		if not Game.commit_expedition_completion(completion, boundary()): return stop_at("complete "+str(next.room_id))
	return false

func ring_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in Game.profile.equipment:
		if Game.profile.equipment[id].template_id == RING: result.append(id)
	return result

func persisted_equal(expected: Dictionary, actual: Dictionary, label: String) -> bool:
	# Compare every persisted field using the save writer's own numeric format.
	# JSON reloads integers as floats; engine Dictionary equality is type-sensitive.
	if ProfileStore._serialize(expected) == ProfileStore._serialize(actual): return true
	var changed: Array[String] = []
	for key: Variant in expected:
		if not actual.has(key) or ProfileStore._serialize({"value":expected[key]}) != ProfileStore._serialize({"value":actual[key]}): changed.append(str(key))
	for key: Variant in actual:
		if not expected.has(key): changed.append(str(key))
	printerr("B10_RING_RELOAD: "+label+" changed persisted fields="+str(changed))
	return false

func _d4(hero: String) -> void:
	if not begin(hero, 4) or not complete_boss(): check(false, hero + " reaches saved D4 BO10 completion: "+stage_error); return
	check(ring_ids().is_empty() and not Game.finale_ring_claimed(), hero + " boss checkpoint has not permanently granted the ring")
	Game.reload_profile()
	check(Game.run != null and Game.run.expedition.phase == "cleared", hero + " final boss checkpoint restores")
	if Game.run == null: return
	var source: String = Game.run.id + ":finale_ring"
	var before: Dictionary = Game.profile.duplicate(true)
	var receipt: Dictionary = Game.run.receipt()
	Game._store.max_document_bytes = 1
	check(Game.finish_run("extracted").is_empty() and Game.profile == before and Game.run.receipt() == receipt, hero + " failed extraction keeps ring claim and complete receipt unchanged")
	Game._store.max_document_bytes = ProfileStore.MAX_DOCUMENT_BYTES
	var result: Dictionary = Game.finish_run("extracted")
	var ids: Array[String] = ring_ids()
	check(not result.is_empty() and ids.size() == 1 and Game.profile.get("finale_ring_claimed") == source, hero + " retry atomically grants one ring with permanent receipt")
	if ids.size() != 1: return
	var ring: Dictionary = Game.profile.equipment[ids[0]].duplicate(true)
	check(result.equipment_retained.has(ids[0]) and ring.lock_state and ring.source_event_id == source, hero + " extraction receipt carries the protected original ring")
	for profession: String in ProfileStore.HERO_IDS:
		check(Game.Instances.can_equip(ring, profession, Game.hero_level(profession)), hero + " ring is legal for " + profession)
	var settled: Dictionary = Game.profile.duplicate(true)
	var replay: Dictionary = Game.finish_run("extracted")
	var replay_stable: bool = Game.run == null and Game.profile == settled and replay.get("run_id") == result.run_id and replay.get("equipment_retained") == result.equipment_retained
	Game.reload_profile()
	var loaded: bool = Game.has_profile and Game.run == null and Game.last_error.is_empty()
	var same_identity: bool = ring_ids() == ids and Game.profile.get("finale_ring_claimed") == source and Game.finale_ring_claimed()
	var same_profile: bool = persisted_equal(settled, Game.profile, hero+" profile")
	var same_ring: bool = persisted_equal(ring, Game.profile.get("equipment", {}).get(ids[0], {}), hero+" ring")
	if not (replay_stable and loaded and same_identity and same_profile and same_ring):
		printerr("B10_RING_RELOAD: %s replay=%s loaded=%s identity=%s profile=%s ring=%s ids=%s claim=%s error=%s" % [hero,replay_stable,loaded,same_identity,same_profile,same_ring,ring_ids(),Game.profile.get("finale_ring_claimed", ""),Game.last_error])
	check(replay_stable and loaded and same_identity and same_profile and same_ring, hero + " replay and actual reload preserve exactly one instance")
	check(depart() and complete_boss() and not Game.finish_run("extracted").is_empty() and ring_ids() == ids and Game.profile.finale_ring_claimed == source, hero + " another complete D4 journey cannot grant a second ring")
	if hero == "CH01":
		check(Game.set_equipment_lock_v2(ids[0], false), "ring lock toggle cannot remove its fixed reward protection")
		var protected_profile: Dictionary=Game.profile.duplicate(true)
		for operation: String in ["sell","dismantle","enhance"]:
			var rejected: Dictionary=Game.forge_equipment_v2(operation,{"instance_id":ids[0]},"finale-ring-blocked:"+operation)
			check(not bool(rejected.get("ok",false)) and rejected.get("error")=="FIXED_FINALE_REWARD" and Game.profile==protected_profile,"unlocked ring rejects "+operation+" without profile mutation")
		Game.reload_profile()
		check(ring_ids()==ids and Game.finale_ring_claimed(), "rejected operations and reload retain the original ring and forever claim")
		check(depart() and complete_boss() and not Game.finish_run("extracted").is_empty() and ring_ids()==ids, "another D4 extraction after rejected operations cannot duplicate the ring")

func _eligibility_and_capacity() -> void:
	check(begin("CH01", 3) and complete_boss() and not Game.finish_run("extracted").is_empty() and ring_ids().is_empty() and not Game.finale_ring_claimed(), "D3 extraction does not consume the highest-difficulty reward")
	check(depart() and complete_boss() and not Game.finish_run("extracted").is_empty() and ring_ids().size() == 1, "a prior lower-difficulty BO10 clear still permits the first D4 claim")
	check(begin("CH02", 4) and complete_boss() and not Game.finish_run("death").is_empty() and ring_ids().is_empty() and not Game.finale_ring_claimed(), "death after final boss clear does not grant or consume the ring")
	check(begin("CH03", 4) and complete_boss() and not Game.finish_run("abandoned").is_empty() and ring_ids().is_empty() and not Game.finale_ring_claimed(), "abandonment after final boss clear does not grant or consume the ring")
	check(begin("CH02", 4, 1) and complete_boss() and not Game.finish_run("extracted").is_empty(), "full inventory can commit the final reward")
	var ids: Array[String] = ring_ids()
	check(ids.size() == 1 and Game.profile.equipment[ids[0]].location == "pending" and Game.finale_ring_claimed(), "overflow retains the unique reward for the existing pending-claim flow")
	Game.reload_profile()
	check(ring_ids() == ids and Game.finale_ring_claimed(), "pending ring and permanent claim survive actual reload")
	if ids.size() != 1: return
	var legacy: Dictionary = Game.profile.duplicate(true)
	legacy.erase("finale_ring_claimed")
	check(Game._commit_profile(legacy) and Game.finale_ring_claimed(), "an older profile with the ring cannot receive a migration duplicate")
	check(depart() and complete_boss() and not Game.finish_run("extracted").is_empty() and ring_ids() == ids, "missing new marker never duplicates an existing ring")

func _ready() -> void:
	if not Game.profile_path.contains("test_b10_finale_ring"):
		get_tree().quit(2)
		return
	for hero: String in ProfileStore.HERO_IDS: _d4(hero)
	_eligibility_and_capacity()
	print("B10 finale ring: %d checks; failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
