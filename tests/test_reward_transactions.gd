extends Node
## Real Game + Room completion/optional-cache integration. AI processing is frozen
## for deterministic transaction checks; objectives, damage, route choices,
## snapshots, disk validation and commits are production implementations.
const RoomScene = preload("res://scenes/room.tscn")
const Coordinator = preload("res://scripts/world/expedition_controller.gd")
const Rewards = preload("res://scripts/world/room_rewards.gd")
const Schema = preload("res://scripts/core/expedition_state.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
var room: Node2D
var checks := 0
var failures := 0
var finished := false

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("REWARD TRANSACTIONS FAIL: " + description)
	else:
		print("PASS ", description)

func frames(count: int = 1) -> void:
	for _index in count:
		await get_tree().process_frame

func _destroy_room() -> void:
	if not is_instance_valid(room): return
	if is_instance_valid(room.combat_audio): await room.combat_audio.wait_for_cleanup()
	room.free()
	room = null
	await frames()

func _construct_room() -> void:
	room = RoomScene.instantiate()
	room.process_mode = Node.PROCESS_MODE_DISABLED
	var coordinator = Coordinator.new(Game)
	var prepared: Dictionary = room.prepare_expedition_node(coordinator.current_context())
	check(bool(prepared.get("valid", false)), "current committed room layout prepares")
	if not bool(prepared.get("valid", false)):
		room.free()
		room = null
		return
	room.apply_prepared_expedition_node(prepared)
	get_tree().root.add_child(room)
	check(room.configuration_ready, "room initializes real player, objective host and loadout")
	check(not room.expedition_runtime_snapshot().is_empty(), "real player exports a valid runtime snapshot")

func _skip_offers() -> void:
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers", []):
		if str(offer.decision).is_empty():
			check(Game.choose_run_relic(str(offer.offer_id), "skip", "", room.expedition_runtime_snapshot()), "resolve required offer through Game")

func _enter(id: String) -> void:
	_skip_offers()
	var state: Dictionary = Game.expedition_snapshot()
	var next_index: int = int(state.node_index) + 1
	check(Game.choose_expedition_node(next_index, id), "legal route choice locks " + id)
	check(Game.advance_expedition_node(room.expedition_runtime_snapshot(), str(state.checkpoint_id)), "Game commits entry for " + id)
	await _destroy_room()
	_construct_room()
	check(room.layout_id == id, "real Room matches committed route " + id)

func _interact(id: String) -> bool:
	var item: Dictionary = room.objectives.element(id)
	if item.is_empty():
		check(false, "authored interaction exists " + id)
		return false
	room.player.position = item.get("interaction_position", item.position)
	return room.objectives.interact(id, room.player)

func _kill_living() -> void:
	# Visit the authored encounter zones and drain their finite reinforcements.
	# Moving the player and advancing encounter time does not mark waves complete.
	for _cycle in 40:
		for zone: Dictionary in room.encounter_zones:
			room.player.position = zone.center
			room._update_encounters(3.0)
		for enemy in room.enemies.get_children():
			if enemy.actor_kind != "objective" and enemy.is_alive():
				enemy.take_damage(1000000.0, &"test", Vector2.ZERO, {"damage_type":"true"})
		await frames()
		if room._encounters_exhausted() and room._living_enemy_count() == 0: break
	check(room._encounters_exhausted(), "real encounter spawns exhaust every finite wave")
	check(room._living_enemy_count() == 0, "real damage clears living combat actors")
	# Collect actual spawned coins before measuring the completion transaction.
	for drop: Dictionary in room.gold_drops.duplicate(true):
		room.player.position = drop.at
		room._update_gold(.01)
	check(room.gold_drops.is_empty(), "real coin pickup separates kill income from completion income")

func _objective() -> void:
	var host: Node2D = room.objectives
	check(host.current_combat_rules(), "real expedition uses published FirstFour objectives")
	var biome: String = Rewards.biome_for_reward(str(room.layout_id))
	for index in host.required_count:
		var id: String = ("solar_conduit_" if biome == "B01" else "brood_nest_") + str(index)
		var item: Dictionary = host.element(id)
		check(not item.is_empty(), "authored combat objective exists " + id)
		if item.is_empty(): continue
		if biome == "B01":
			check(_interact(id), "start actual solar conduit " + str(index))
			# Stay at this fixed blueprint point for the full charge duration.
			for _tick in 17: host.tick(.1)
		else:
			check(host.targets.has(id), "authored brood nest has a damageable actor")
			if not host.targets.has(id): continue
			var target: Node2D = host.targets[id]
			target.take_damage(1000000.0, &"test", Vector2.ZERO, {"damage_type":"true"})
		check(bool(host.element(id).done), "real objective action completes " + id)
	check(host.is_complete() and str(host.quality) == "full", str(room.layout_id) + " authored mechanics select the sole current full outcome")

func _complete(gold: int) -> void:
	await _kill_living()
	var gold_before: int = Game.run.gold
	var drops_before: Dictionary = Game.run.expedition.claimed_drop_ids.duplicate(true)
	var xp_before: int = Game.profile.hero_xp[Game.run.hero_id]
	_objective()
	room._tick_expedition(.016)
	check(room.objective_rewarded and str(Game.run.expedition.phase) == "cleared", str(room.layout_id) + " objective reward commits through Room and Game")
	var new_drops: Array = []
	var converted := 0
	for id: String in Game.run.expedition.claimed_drop_ids:
		if not drops_before.has(id):
			var record: Dictionary = Game.run.expedition.claimed_drop_ids[id]
			new_drops.append(record)
			converted += int(record.gold)
			check(Rewards.race_equipment_pool(Rewards.biome_for_reward(str(room.layout_id)), Game.run.hero_id).has(record.equipment_id), "actual completion item belongs to the room faction and fits the hero")
			check(int(record.get("level", 0)) == 0, "actual D0 completion item has the published +0 enhancement")
	check(new_drops.size() == 1, "actual " + str(room.layout_id) + "/full grants exactly one D0 faction equipment drop")
	check(Game.run.gold - gold_before == gold + converted, "actual " + str(room.layout_id) + "/full gold matches the published policy-1 payout plus duplicate conversion")
	check(int(Game.profile.hero_xp[Game.run.hero_id]) - xp_before == 30, "room XP awarded exactly once through commit")
	var receipt: Dictionary = Game.run.live_receipt()
	room._tick_expedition(2.0)
	check(Game.run.live_receipt() == receipt, "repeated completion tick does not award again")
	check(Schema.valid(Game.run.live_receipt(), Game.profile), "live committed reward receipt validates")

func _start_target(id: String, all_faction_owned: bool = false, hero_id: String = "CH01") -> void:
	await _destroy_room()
	if Game.run != null: Game.finish_run("abandoned")
	check(Game.new_profile(), "fresh isolated test profile")
	check(Game.select_hero(hero_id), "select the fixture hero through Game")
	if id == "L11" or all_faction_owned:
		# Legacy fixture APIs create a legitimately unlocked/owned profile. The
		# expedition being tested still uses normal route and transaction APIs.
		check(Game.start_run(), "start setup run through Game")
		check(Game.record_boss_defeat("BO01"), "setup profile has previous biome boss receipt")
		if all_faction_owned: check(Game.add_gold(10000), "setup grants spendable bank via run economy")
		check(not Game.finish_run("extracted").is_empty(), "setup run extracts through settlement")
		if all_faction_owned:
			for eq: String in Rewards.race_equipment_pool("B01", hero_id):
				if not Game.profile.equipment.has(eq): check(Game.buy_equipment(eq, "reward-test-own:" + eq), "purchase faction pool item " + eq)
	check(Game.start_run({"expedition":true,"biome_id":"B02" if id == "L11" else "B01","difficulty":0,"seed":41827}), "normal expedition starts with real default loadout")
	check(int(Game.run.expedition.reward_policy_version) == 1 and int(Game.run.expedition.difficulty) == 0, "integration fixture freezes current policy 1 at D0")
	_construct_room()
	await _enter("L03" if id == "L01" else id)
	if id == "L01":
		await _complete(30)
		await _enter(id)

func _optional_id() -> String:
	return "side_crate" if room.layout_id == "L01" else "research_2"

func _optional_flow(id: String, all_owned: bool = false) -> void:
	# CH01 starts with three of its four eligible B01 items, so the approach
	# room exhausts that pool. CH03 leaves new faction gear for the cache case.
	await _start_target(id, all_owned, "CH03" if id == "L01" and not all_owned else "CH01")
	var optional_id: String = _optional_id()
	if room._living_enemy_count() == 0: room.spawn_enemy(room.layout.entry + Vector2(300, 100), "M01", 1)
	check(room._living_enemy_count() > 0, "live combat actor exists for cache gate")
	_objective()
	room._tick_expedition(.016)
	var before: Dictionary = Game.run.live_receipt()
	check(not _interact(optional_id), id + " cannot claim cache while enemies live after authored objective")
	check(Game.run.live_receipt() == before and not room.objective_rewarded, "early cache attempt grants nothing and cannot bypass clear")
	await _kill_living()
	room._tick_expedition(.016)
	check(room.objective_rewarded, id + " real clear commits before cache")
	var index: int = int(Game.run.expedition.node_index)
	var checkpoint: String = str(Game.run.expedition.checkpoint_id)
	var runtime: Dictionary = room.expedition_runtime_snapshot()
	before = Game.run.live_receipt()
	var profile_before: Dictionary = Game.profile.duplicate(true)
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(Game.profile_path)
	var expected_gold: int = 18 if id == "L01" else 22
	check(not Game.claim_expedition_optional_reward(index, optional_id, runtime, checkpoint + "stale"), "stale checkpoint rejects cache transaction")
	check(not Game.claim_expedition_optional_reward(index + 1, optional_id, runtime, checkpoint), "wrong node rejects cache transaction")
	check(not Game.claim_expedition_optional_reward(index, "unregistered_cache", runtime, checkpoint), "unknown objective rejects cache transaction")
	check(Game.run.live_receipt() == before, "invalid requests preserve complete live receipt")
	var healthy: String = Game._store.path
	Game._store.path = Game.profile_path + "/unwritable.json"
	check(not _interact(optional_id), "storage failure rejects actual cache interaction")
	check(Game.last_error == "STORAGE_WRITE_FAILED", "cache rejection comes from the real storage gate")
	check(room.objectives.optional_ids().has(optional_id) and not bool(room.objectives.element(optional_id).done), "storage failure leaves cache available")
	check(Game.run.live_receipt() == before and Game.profile == profile_before, "failed cache leaves gold, pending drops, claim ledger and profile unchanged")
	check(FileAccess.get_file_as_bytes(Game.profile_path) == bytes_before, "failed cache leaves profile bytes unchanged")
	Game._store.path = healthy
	check(_interact(optional_id), "same cache retries after storage recovery")
	var claim_id: String = Game.run.id + ":node:" + str(index) + ":optional:" + optional_id
	check(Game.run.expedition.get("optional_claims", {}).has(claim_id), "successful cache persists immutable claim identity")
	if not Game.run.expedition.get("optional_claims", {}).has(claim_id): return
	var claim: Dictionary = Game.run.expedition.optional_claims[claim_id]
	var drop: Dictionary = Game.run.expedition.claimed_drop_ids[claim.drop_ids[0]]
	check(int(claim.gold) == expected_gold and claim.drop_ids.size() == 1, "cache receipt records its currency and one equipment drop")
	check(Rewards.race_equipment_pool(Rewards.biome_for_reward(id), Game.run.hero_id).has(drop.equipment_id), "actual cache gear belongs to its advertised faction and fits the hero")
	check(int(claim.reward_version) == 2 and int(drop.get("level", 0)) == 0, "current cache receipt freezes policy-1 version and D0 enhancement")
	check(Game.run.gold - int(before.gold) == expected_gold + int(drop.gold), "cache gold includes exactly the base reward and any duplicate conversion")
	check(Game.profile.hero_xp == profile_before.hero_xp and Game.run.expedition.mastery == before.expedition.mastery, "cache does not repeat room XP or mastery")
	if all_owned:
		check(drop.result == "gold" and int(drop.gold) == int(int(Registry.equipment(drop.equipment_id).price) / 10), "exhausted owned pool converts duplicate at ten percent price")
	else:
		check(drop.result == "pending" and Game.run.expedition.pending_equipment.has(drop.equipment_id), "new cache equipment remains pending extraction")
	var claimed: Dictionary = Game.run.live_receipt()
	check(not _interact(optional_id), "visible cache cannot be reopened after success")
	check(Game.claim_expedition_optional_reward(index, optional_id, runtime, checkpoint), "same committed claim retry is idempotent")
	check(Game.run.live_receipt() == claimed, "duplicate retry does not grant gold or equipment")
	check(Schema.valid(claimed, Game.profile), "successful optional reward receipt validates")
	_schema_negative_cases(claimed, claim_id, str(claim.drop_ids[0]))
	await _destroy_room()
	Game.reload_profile()
	check(Game.run != null and Game.run.expedition.get("optional_claims", {}).has(claim_id), "disk reload restores cache claim")
	# Godot JSON decodes all ledger numbers as floats; compare the expected
	# ledger in that same storage representation, retaining every key/value.
	var expected_disk_drops: Dictionary = JSON.parse_string(JSON.stringify(claimed.expedition.claimed_drop_ids))
	check(Game.run.gold == int(claimed.gold) and Game.run.expedition.pending_equipment == claimed.expedition.pending_equipment and Game.run.expedition.claimed_drop_ids == expected_disk_drops, "disk reload restores exact currency and equipment ledgers")
	_construct_room()
	check(room.objective_rewarded and room.objectives.optional_ids().is_empty(), "claimed cache stays absent in restored cleared room")
	check(room._living_enemy_count() == 0 and room.objectives.hazards.is_empty() and not room.spawn_enabled, "restored cleared room has no encounter or objective hazards")
	var after_reload: Dictionary = Game.run.live_receipt()
	room._tick_expedition(1)
	check(Game.run.live_receipt() == after_reload, "restoring cleared room does not repeat completion reward")
	_skip_offers()
	var next: Dictionary = Game.expedition_snapshot().next_node
	check(Game.choose_expedition_node(int(next.node_index), str(next.room_id)), "departure locks legal next room")
	check(Game.advance_expedition_node(room.expedition_runtime_snapshot(), str(Game.run.expedition.checkpoint_id)), "departure commits next node")
	check(not Game.claim_expedition_optional_reward(index, optional_id, runtime, checkpoint), "old room claim rejected after departure")
	check(not room.claim_optional_objective_reward(optional_id), "stale Room callback cannot grant old-node cache after departure")

func _schema_negative_cases(receipt: Dictionary, claim_id: String, drop_id: String) -> void:
	var bad: Dictionary = receipt.duplicate(true)
	bad.expedition.optional_claims[claim_id].drop_ids = ["missing-drop"]
	check(not Schema.valid(bad, Game.profile), "schema rejects optional claim with missing/mismatched drop")
	bad = receipt.duplicate(true)
	bad.expedition.optional_claims.clear()
	check(not Schema.valid(bad, Game.profile), "schema rejects orphan optional drop without corresponding claim")
	bad = receipt.duplicate(true)
	bad.expedition.optional_claims[claim_id].gold += 1
	check(not Schema.valid(bad, Game.profile), "schema rejects altered optional currency")
	bad = receipt.duplicate(true)
	bad.expedition.claimed_drop_ids[drop_id].result = "pending"
	bad.expedition.claimed_drop_ids[drop_id].gold = 0
	bad.expedition.pending_equipment.erase(str(bad.expedition.claimed_drop_ids[drop_id].equipment_id))
	check(not Schema.valid(bad, Game.profile), "schema rejects claimed pending drop with no pending equipment")

func _unclaimed_restore(id: String) -> void:
	await _start_target(id)
	await _complete(12 if id == "L01" else 18)
	var receipt: Dictionary = Game.run.live_receipt()
	var optional_id: String = _optional_id()
	# A cleared receipt need not have an optional_claims field until a claim.
	check(not receipt.expedition.has("optional_claims") and Schema.valid(receipt, Game.profile), "cleared checkpoint without optional field remains valid")
	await _destroy_room()
	Game.reload_profile()
	_construct_room()
	check(room.objectives.optional_ids() == [optional_id], id + " restart rebuilds only its unclaimed cache")
	check(room.objectives.elements.size() == 1 and room.objectives.targets.is_empty() and room.objectives.hazards.is_empty(), "cleared restore does not rebuild machinery, targets or hazards")
	check(room._living_enemy_count() == 0 and not room.spawn_enabled and room.objective_rewarded, "unclaimed-cache restore remains a cleared safe room")
	var stable: Dictionary = Game.run.live_receipt()
	for _index in 3: room._tick_expedition(.5)
	check(Game.run.live_receipt() == stable and Game.run.gold == int(receipt.gold), "unclaimed restore cannot repeat room reward")
	check(_interact(optional_id), "restored unclaimed cache can still be claimed")

func _demo_isolation() -> void:
	await _destroy_room()
	if Game.run != null: Game.finish_run("abandoned")
	check(Game.new_profile(), "fresh profile before disposable demo")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(Game.profile_path)
	seed(48173)
	check(Game.start_demo("CH01"), "real full-skill demo starts")
	_construct_room()
	# Level-eight routes have a branch at node two; use the objective slot three.
	for id: String in ["L03", "L06", "L01"]:
		await _enter(id)
		await _complete(24 if id == "L06" else (30 if id == "L03" else 12))
	check(_interact("side_crate"), "demo can exercise the real optional reward path")
	check(FileAccess.get_file_as_bytes(Game.profile_path) == original, "demo room rewards and optional claim never change formal profile bytes")
	await _destroy_room()
	Game.reload_profile()
	check(Game.run == null and FileAccess.get_file_as_bytes(Game.profile_path) == original, "discarding demo restores formal profile without writing")

func _historical_policy_cases() -> void:
	# Policy zero remains a callable compatibility contract. These obsolete
	# bargains are not objective choices in a current FirstFour expedition.
	for row: Array in [["L02","full",18,1],["L02","reduced",34,0],["L03","full",30,0],["L03","mobile",12,1],["L06","full",24,2],["L06","reduced",8,0]]:
		var historical: Dictionary = Rewards.build(str(row[0]), str(row[1]), "CH01", 41827, "historical", [], [], [], -1, 0)
		check(int(historical.get("gold", -1)) == int(row[2]) and historical.get("equipment", []).size() == int(row[3]), str(row[0]) + "/" + str(row[1]) + " preserves exact historical policy-0 payout")
		check(int(historical.get("xp", -1)) == 30 and int(historical.get("mastery", -1)) == 180, "historical quality preserves its XP and mastery")
		check(historical == Rewards.build(str(row[0]), str(row[1]), "CH01", 41827, "historical", [], [], [], -1, 0), "historical retry keeps identical deterministic drops")
		if str(row[1]) != "full":
			check(Rewards.build(str(row[0]), str(row[1]), "CH01", 41827, "current", [], [], [], 0, 1).is_empty(), str(row[0]) + " policy 1 rejects retired " + str(row[1]) + " quality")
	for id: String in ["L01", "L02", "L03", "L06", "L11"]:
		check(Rewards.qualities(id, 1) == ["full"], id + " current policy exposes only the authored full outcome")
		check(Rewards.build(id, "full", "CH01", 41827, "current", [], [], [], -1, 1).is_empty(), id + " current policy requires explicit difficulty")

func _run() -> void:
	if not Game.profile_path.get_file().begins_with("test_reward_transactions"):
		push_error("Refusing to run reward tests without isolated profile prefix")
		get_tree().quit(2)
		return
	Game.set_process(false)
	get_tree().create_timer(240).timeout.connect(func():
		if not finished:
			push_error("Reward transaction acceptance timed out")
			get_tree().quit(1))
	_historical_policy_cases()
	for scenario: Array in [["L02",18],["L03",30],["L06",24]]:
		await _start_target(str(scenario[0]))
		await _complete(int(scenario[1]))
	await _optional_flow("L01")
	await _optional_flow("L01", true)
	await _optional_flow("L11")
	await _unclaimed_restore("L01")
	await _unclaimed_restore("L11")
	await _demo_isolation()
	await _destroy_room()
	if Game.run != null: Game.finish_run("abandoned")
	finished = true
	print("REWARD TRANSACTIONS TESTS: ", checks - failures, "/", checks, " passed")
	get_tree().quit(1 if failures else 0)
