extends SceneTree
## Transaction boundaries use explicit synthetic actor fixtures, never production
## default snapshots. Restart modes are run in independent Godot processes.
const Controller = preload("res://scripts/core/run_controller.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Expedition = preload("res://scripts/core/expedition_state.gd")
var checks: int = 0
var failures: int = 0
var directory: String
var mode: String = "all"
var restart_path: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		if argument.begins_with("--restart-profile="): restart_path = argument.trim_prefix("--restart-profile=")
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CORE EXPEDITION FAIL: " + label)

func _game(name: String) -> Node:
	var game := Controller.new()
	game.profile_path = name if name.is_absolute_path() else directory + "/" + name
	root.add_child(game)
	return game

func _write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture writable")
	if file:
		file.store_string(data if data is String else JSON.stringify(data))
		file.close()

func _runtime(game: Node) -> Dictionary:
	var player: Dictionary = {"cooldowns":{},"passive_count":0,"walk_distance":0.0,"aim_direction":[1.0,0.0],"cast_serial":0}
	for key: String in Snapshot.SKILLS: player.cooldowns[key] = 0.0
	for key: String in Snapshot.PLAYER_TIMERS: player[key] = 0.0
	var equipment: Dictionary = {"room_id":"","room_low_shield_used":false,"room_first_kill_used":false}
	for key: String in Snapshot.EFFECT_MAPS: equipment[key] = {}
	for key: String in Snapshot.EFFECT_HISTORIES: equipment[key] = []
	for key: String in Snapshot.EFFECT_NUMBERS: equipment[key] = 0.0
	equipment.dash_time = -100.0
	equipment.delayed_shield_at = -1.0
	var modifiers: Dictionary = {}
	for key: String in Snapshot.MODIFIERS: modifiers[key] = 1.0 if key.ends_with("_scale") else 0.0
	equipment["adapter"] = {"clock":0.0,"movement_time":0.0,"event_serial":0,"modifiers":modifiers}
	return {"snapshot_version":1,"mode":"safe_boundary","hero_id":game.run.hero_id,"hp":game.run.hp,"resource":game.run.resource,
		"player":player,"equipment":equipment,"status":{"clock":0.0,"shock_cooldown":0.0,"states":{},"guards":{},"origins":{},"slow_remaining":0.0,"slow_multiplier":1.0}}

func _start(game: Node, difficulty: int = 0, hero: String = "CH01") -> void:
	_check(game.new_profile(), "new isolated profile")
	_check(game.select_hero(hero), "select hero before expedition")
	_check(game.start_run({"expedition":true,"biome_id":"B01","difficulty":difficulty,"seed":960208}), "start actual level-sized expedition")
	if game.run != null:
		var runtime: Dictionary = _runtime(game)
		_check(Expedition.runtime_valid(runtime, game.run.hero_id, game.run.stats), "full synthetic boundary validates")

func _skip_offers(game: Node) -> void:
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		_check(game.choose_run_relic(offer.offer_id, "skip", "", _runtime(game)), "resolve frozen relic offer " + offer.offer_id)

func _advance(game: Node) -> bool:
	_skip_offers(game)
	var snapshot: Dictionary = game.expedition_snapshot()
	var next: Dictionary = snapshot.next_node
	if next.is_empty(): return false
	var selected: String = str(next.room_id)
	_check(game.choose_expedition_node(int(next.node_index), selected), "lock next room " + str(next.node_index))
	var advanced: bool = game.advance_expedition_node(_runtime(game), snapshot.checkpoint_id)
	_check(advanced, "commit entry " + str(next.node_index) + " " + game.last_error)
	if advanced: _check(not game.advance_expedition_node(_runtime(game), snapshot.checkpoint_id), "stale button cannot advance the same transition twice")
	return advanced

func _complete(game: Node, rewards: Dictionary = {}) -> bool:
	var id: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	var result: bool = game.commit_expedition_completion(id, _runtime(game), rewards)
	_check(result, "complete current node atomically " + game.last_error)
	return result

func _run() -> void:
	directory = "res://tools/godot/test-runs/core_expedition_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if mode != "all": _restart_mode()
	else:
		_eight_nodes()
		_atomic_boundary()
		_supplies()
		_death_and_legacy()
		_invalid_documents()
		_dynamic_tiers()
		_legacy_eight_checkpoint()
	print("CORE EXPEDITION TESTS: ", checks - failures, "/", checks, " passed; mode=", mode, "; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _eight_nodes() -> void:
	var game := _game("eight.json")
	_start(game, 4)
	if game.run == null: game.free(); return
	var count: int = game.run.expedition.route.nodes.size()
	_check(count == 6 and game.run.expedition.mastery_rank == 1, "level-one route starts with six nodes and rank one")
	var entrance: Dictionary = game.expedition_snapshot()
	_check(not game.advance_expedition_node(_runtime(game)), "required entrance offer cannot be bypassed")
	_check(not game.choose_expedition_node(1, "missing") and not game.choose_expedition_node(8, "missing"), "illegal room and out-of-range index reject")
	var offer: Dictionary = entrance.relic_offers[0]
	var relic: String = offer.candidates[0]
	_check(game.choose_run_relic(offer.offer_id, relic), "fresh entrance permits first choice")
	_check(game.choose_run_relic(offer.offer_id, relic) and not game.choose_run_relic(offer.offer_id, "skip"), "choice is immutable and retry idempotent")
	var expected_gold: int = 0
	var combat_clears: int = 0
	for index in range(1, count):
		if not _advance(game): break
		_check(game.run.expedition.node_index == index, "sequential route advancement")
		if game.expedition_snapshot().node.role == "supply":
			_check(game.run.expedition.phase == "safe" and game.expedition_snapshot().supply_offers.size() == 7, "supply node has seven frozen products")
			continue
		_check(not game.advance_expedition_node(_runtime(game)), "cannot skip active combat")
		game.add_gold(10)
		expected_gold += 22
		var rewards: Dictionary = {"gold":12,"xp":50,"mastery":180}
		if index == 1: rewards.equipment = [{"drop_id":"drop-first","equipment_id":"EQ02"}]
		if not _complete(game, rewards): break
		combat_clears += 1
		var id: String = game.run.id + ":node:" + str(index) + ":complete"
		var before: Dictionary = game.run.receipt()
		_check(game.commit_expedition_completion(id, _runtime(game), rewards) and game.run.receipt() == before, "same completion never duplicates rewards")
		_check(game.run.gold == expected_gold, "kill and completion gold share committed ledger")
		_check(game.profile.hero_xp.CH01 == 50 * combat_clears, "XP once per completed combat")
		if index == 1: _check(game.run.expedition.mastery_rank == 2, "180 mastery crosses first threshold only")
		if index == 2: _check(game.run.expedition.mastery_rank == 3, "360 mastery is rank three")
		var node: Dictionary = game.expedition_snapshot().node
		if not node.early_extraction and node.role != "boss": _check(game.finish_run("extracted").is_empty(), "extraction only at designated nodes")
	_check(game.run.expedition.node_index == count - 1 and game.run.expedition.completed_nodes.size() == count and game.run.expedition.mastery == mini(900, combat_clears * 180), "entire level-sized expedition reaches boss and earned mastery")
	_check(not game.choose_expedition_node(count, "missing"), "completed final room has no extra node")
	var result: Dictionary = game.finish_run("extracted")
	_check(result.get("equipment_retained", []) == ["EQ02"] and game.profile.equipment.has("EQ02"), "successful extraction banks pending equipment")
	_check(game.profile.bosses == ["BO01"] and game.profile.permanent_gold == expected_gold, "boss unlock and wallet settle together")
	_check(game.finish_run("extracted") == result and game.profile.total_runs == 1, "settlement retry pays once")
	game.reload_profile()
	_check(game.run == null and game.profile.equipment.has("EQ02") and game.profile.total_runs == 1, "settled gear remains after disk reload")
	game.free()

func _atomic_boundary() -> void:
	var game := _game("atomic.json")
	_start(game)
	if game.run == null or not _advance(game): game.free(); return
	var id: String = game.run.id
	var frozen: Dictionary = game.run.expedition.route.duplicate(true)
	_check(game.add_gold(35) and game.collect_expedition_equipment("uncommitted-drop", "EQ02"), "partial room income and drop staged")
	_check(game.grant_hero_xp(40, "staged-xp"), "room XP staged")
	game.set_setting("language", "en")
	game.reload_profile()
	_check(game.run != null and game.run.id == id and game.run.gold == 0 and game.profile.hero_xp.CH01 == 0, "settings cannot leak partial room ledger or XP")
	var same_route: bool = true
	for index in range(frozen.nodes.size()):
		if game.run.expedition.route.nodes[index].room_id != frozen.nodes[index].room_id: same_route = false
	_check(game.run.expedition.pending_equipment.is_empty() and same_route, "restart uses locked entry, discards partial drops")
	_check(game.add_gold(35) and game.collect_expedition_equipment("drop-stable", "EQ02"), "replayed room can collect deterministic drop")
	_check(game.collect_expedition_equipment("drop-stable", "EQ02") and not game.collect_expedition_equipment("drop-stable", "EQ12"), "drop identifier cannot be paid twice or reused for another item")
	_check(game.collect_expedition_equipment("duplicate-eq", "EQ02") and game.run.gold == 45, "duplicate pending item becomes ten percent price gold")
	var runtime: Dictionary = _runtime(game)
	runtime.hp = 50.0
	runtime.player.cooldowns.q = 4.25
	runtime.equipment.clock = 8.0
	runtime.equipment.cooldowns["EQ52"] = 11.5
	var blocker: String = directory + "/storage-blocker"
	_write(blocker, "not a directory")
	var before: Dictionary = game.run.live_receipt()
	game._store.path = blocker + "/profile.json"
	_check(not game.commit_expedition_completion("atomic-complete", runtime, {"gold":12,"xp":90}), "failed disk write rejects entire clear")
	_check(game.run.live_receipt() == before and game.profile.hero_xp.CH01 == 0, "failed clear preserves route, XP and reward ledger")
	game._store.path = game.profile_path
	_check(game.commit_expedition_completion("atomic-complete", runtime, {"gold":12,"xp":90}), "same failed clear retries successfully")
	game.reload_profile()
	_check(game.run.expedition.phase == "cleared" and game.run.hp == 50.0 and game.run.gold == 57, "safe clear snapshot and total gold restore")
	_check(game.run.expedition.runtime.player.cooldowns.q == 4.25 and game.run.expedition.runtime.equipment.cooldowns.EQ52 == 11.5, "cooldowns and affix ICD survive checkpoint")
	var next: Dictionary = game.expedition_snapshot().next_node
	_check(game.choose_expedition_node(2, next.room_id), "next candidate locks durably")
	var chosen: String = next.room_id
	game.reload_profile()
	_check(game.expedition_snapshot().next_node.options == [chosen] and not game.choose_expedition_node(2, "wrong"), "restart cannot reroll a locked candidate")
	game.free()

func _supplies() -> void:
	var game := _game("supply.json")
	_start(game, 0, "CH03")
	if game.run == null: game.free(); return
	var supply: int = Expedition.Routes.supply_index(game.run.expedition.route)
	for index in range(1, supply + 1):
		if not _advance(game): game.free(); return
		if index != supply: _complete(game, {"gold":150,"xp":0,"mastery":0})
	var offers: Dictionary = {}
	for offer: Dictionary in game.expedition_snapshot().supply_offers: offers[offer.product_id] = offer.offer_id
	var runtime: Dictionary = _runtime(game)
	runtime.hp = game.run.max_hp * 0.4
	runtime.resource = 10.0
	_check(game.purchase_run_supply(offers.heal_small, runtime), "small heal purchases at supply")
	var expected_gold: int = (supply - 1) * 150 - 20
	_check(is_equal_approx(game.run.hp, game.run.max_hp * 0.55) and game.run.gold == expected_gold, "small heal gives fifteen percent and debits twenty")
	var hp: float = game.run.hp
	_check(game.purchase_run_supply(offers.heal_small, _runtime(game)) and game.run.hp == hp and game.run.gold == expected_gold, "duplicate purchase cannot heal or debit again")
	_check(not game.purchase_run_supply(offers.heal_large, _runtime(game)), "heal services mutually exclusive")
	_check(not game.purchase_run_supply(offers.energy, _runtime(game)), "resource potion must match hero type")
	_check(game.purchase_run_supply(offers.mana, _runtime(game)) and game.run.resource == 40.0, "mana supply restores thirty percent maximum")
	_check(game.purchase_run_supply(offers.amplify, _runtime(game)) and game.run.stats.temporary_buffs.amplify.remaining_rooms == 2, "amplifier commits two-room duration")
	_check(game.purchase_run_supply(offers.scan, _runtime(game)) and game.run.expedition.scan_nodes == Expedition.Routes.scan_indices(game.run.expedition.route), "scan unlocks remaining authored encounters for this route length")
	_check(game.purchase_run_supply(offers.shield, _runtime(game)), "shield supply is a real committed purchase")
	_check(_advance(game), "depart supply after purchases")
	_check(game.run.shield >= game.run.max_hp * 0.15, "supply shield reaches next encounter")
	_complete(game, {"gold":0,"xp":0,"mastery":0})
	_check(game.run.stats.temporary_buffs.amplify.remaining_rooms == 1, "one cleared combat consumes one amplifier room")
	_check(not game.purchase_run_supply(offers.scan, _runtime(game)), "cannot shop outside safe supply node")
	game.free()

func _death_and_legacy() -> void:
	var game := _game("death.json")
	_start(game)
	if game.run == null or not _advance(game): game.free(); return
	game.add_gold(101)
	game.collect_expedition_equipment("death-drop", "EQ02")
	var result: Dictionary = game.finish_run("death")
	_check(result.get("equipment_lost", []) == ["EQ02"] and not game.profile.equipment.has("EQ02"), "death discards pending equipment")
	# New settlements use v2; the following legacy recovery fixture remains v1.
	_check(result.rules_version == 2 and game.profile.permanent_gold == 50 and game.profile.equipment_discoveries == ["EQ02"], "v2 death keeps fifty percent gold and equipment discovery")
	game.reload_profile()
	_check(game.run == null and game.profile.total_runs == 1 and not game.profile.equipment.has("EQ02"), "death restart cannot recover lost gear")
	game.free()
	game = _game("old-active.json")
	_check(game.new_profile() and game.start_run() and game.add_gold(119), "legacy fixture uses old start_run contract")
	var legacy: Dictionary = game._store._current.duplicate(true)
	legacy.schema_version = 2
	_write(directory + "/v2-active.json", legacy)
	game.free()
	game = _game("v2-active.json")
	_check(game.run == null and game.profile.permanent_gold == 23 and game.profile.total_runs == 1, "v2 receipt is one abandonment, never fake resume")
	game.reload_profile()
	_check(game.profile.permanent_gold == 23 and game.profile.total_runs == 1, "legacy recovery does not duplicate wallet")
	game.free()

func _invalid_documents() -> void:
	var game := _game("validation.json")
	_start(game)
	if game.run == null: game.free(); return
	var valid: Dictionary = game._store._current.duplicate(true)
	_check(ProfileStore._valid_document(valid), "checkpoint document validates whole transaction")
	for field: String in ["pending_equipment", "claimed_drop_ids", "offers"]:
		var corrupted: Dictionary = valid.duplicate(true)
		corrupted.active_run.expedition[field] = []
		_check(not ProfileStore._valid_document(corrupted), "wrong type rejected for " + field)
	var corrupted: Dictionary = valid.duplicate(true)
	corrupted.active_run.expedition.runtime.hp = -1
	_check(not ProfileStore._valid_document(corrupted), "invalid runtime cannot become resume checkpoint")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.gold_earned = 99
	_check(not ProfileStore._valid_document(corrupted), "receipt gold must equal earned minus spent")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.completed_nodes = [1]
	_check(not ProfileStore._valid_document(corrupted), "future completion cannot be loaded")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.mastery_rank = 6
	_check(not ProfileStore._valid_document(corrupted), "mastery rank must match actual accumulated points")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.checkpoint_id = "invented"
	_check(not ProfileStore._valid_document(corrupted), "checkpoint identity must match run and node")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.relic_levels["RL01"] = 2
	_check(not ProfileStore._valid_document(corrupted), "relic levels require committed choice history")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.temporary_buffs["amplify"] = {"damage_bonus":99,"remaining_rooms":2}
	_check(not ProfileStore._valid_document(corrupted), "unpaid or out-of-range temporary buff cannot load")
	corrupted = valid.duplicate(true)
	corrupted.active_run.expedition.scan_nodes = [5,6]
	_check(not ProfileStore._valid_document(corrupted), "scan reveals require paid supply transaction")
	var runtime: Dictionary = _runtime(game)
	runtime.player.cooldowns.q = NAN
	_check(not game.save_expedition_checkpoint(runtime), "non-finite actor snapshot rejected before save")
	game.free()

func _dynamic_tiers() -> void:
	for level: int in [1, 5, 10, 15]:
		var game := _game("tier-" + str(level) + ".json")
		_check(game.new_profile(), "tier fixture creates isolated profile")
		if level > 1:
			_check(game.start_run(), "tier fixture earns XP through normal API")
			_check(game.grant_hero_xp(ContentRegistry.XP_THRESHOLDS[level - 1], "tier-training"), "tier departure level is earned")
			game.finish_run("extracted")
		_check(game.start_run({"expedition":true,"biome_id":"B01","seed":42000 + level}), "start dynamic tier " + str(level))
		if game.run == null: game.free(); continue
		var count: int = Expedition.Routes.node_count_for_level(level)
		var route_id: String = game.run.id
		_check(game.run.expedition.route.nodes.size() == count and game.run.expedition.departure_level == level, "departure tier fixes route length")
		var document: Dictionary = game._store.load_document()
		var corrupt: Dictionary = document.duplicate(true)
		corrupt.active_run.expedition.node_count = count + 2
		_check(not ProfileStore._valid_document(corrupt), "mismatched saved route length rejects")
		corrupt = document.duplicate(true)
		corrupt.active_run.expedition.route.nodes[-1].biome_id = "invalid"
		_check(not ProfileStore._valid_document(corrupt), "saved boss biome must match the selected clan")
		var final_boss := ""
		for index in range(1, count):
			var next: Dictionary = game.expedition_snapshot().next_node
			if Expedition.Routes.is_template_node(next) and next.options.size() > 1:
				_check(game.choose_expedition_node(index, str(next.options.back())), "alternative route branch locks before entering")
				game.reload_profile()
				_check(game.run != null and game.run.id == route_id and game.run.expedition.route.nodes.size() == count, "locked dynamic branch survives disk reload")
			if not _advance(game): break
			var node: Dictionary = game.expedition_snapshot().node
			if node.role == "supply":
				var offers: Dictionary = {}
				for offer: Dictionary in game.expedition_snapshot().supply_offers: offers[offer.product_id] = offer.offer_id
				_check(game.purchase_run_supply(offers.scan, _runtime(game)), "dynamic supply scan purchases at role-derived index")
				_check(game.run.expedition.scan_nodes == Expedition.Routes.scan_indices(game.run.expedition.route), "scan covers this tier's remaining template encounters")
				_check(game.purchase_run_supply(offers.shield, _runtime(game)), "dynamic supply shield purchases")
			else:
				if Expedition.Routes.is_template_node(node):
					_check(Expedition.Catalog.room(str(node.room_id)).get("biome_id","") == game.run.expedition.route.biome_id, "fresh dynamic templates stay within the selected clan")
				if node.role == "boss": final_boss = str(node.room_id)
				var rewards: Dictionary = {"gold":100,"xp":900,"mastery":180}
				if node.role == "boss": rewards.boss_id = final_boss
				if not _complete(game, rewards): break
				_check(game.run.expedition.route.nodes.size() == count and game.run.expedition.departure_level == level, "in-run level ups cannot enlarge the chosen expedition")
				var id: String = route_id + ":node:" + str(index) + ":complete"
				var before: int = game.run.gold
				_check(game.commit_expedition_completion(id, _runtime(game), rewards) and game.run.gold == before, "dynamic completion reward remains idempotent")
			game.reload_profile()
			_check(game.run != null and game.run.id == route_id and game.run.expedition.node_index == index, "each dynamic node checkpoint resumes at the exact node")
		_check(game.run != null and game.run.expedition.node_index == count - 1 and game.expedition_snapshot().node.role == "boss" and not final_boss.is_empty(), "each tier reaches its actual final boss")
		var result: Dictionary = game.finish_run("extracted")
		_check(result.get("outcome") == "extracted" and final_boss == "BO01" and final_boss in game.profile.bosses, "correct selected-clan boss is recorded and extraction settles")
		game.reload_profile()
		_check(game.run == null and game.last_result.get("run_id") == route_id, "dynamic boss settlement survives disk reload")
		game.free()

func _legacy_eight_checkpoint() -> void:
	var game := _game("legacy-eight.json")
	_start(game)
	if game.run == null: game.free(); return
	var receipt: Dictionary = game.run.live_receipt()
	var old_route: Dictionary = Expedition.Routes.generate("B01", int(receipt.expedition.seed))
	old_route.erase("candidate_paths")
	receipt.expedition.route = old_route
	receipt.expedition.erase("departure_level")
	receipt.expedition.erase("node_count")
	_check(game._store.save_document(game.profile, receipt), "pre-dynamic eight-node receipt remains a valid stored checkpoint")
	var original_id: String = game.run.id
	game.reload_profile()
	_check(game.run != null and game.run.id == original_id and game.run.expedition.route.nodes.size() == 8 and not game.run.expedition.has("departure_level"), "level-one legacy expedition resumes eight nodes without regeneration")
	for index in range(1, 8):
		if not _advance(game): break
		if game.expedition_snapshot().node.role != "supply": _complete(game, {"gold":10,"xp":0,"mastery":0})
	game.reload_profile()
	_check(game.run != null and game.run.expedition.node_index == 7 and game.expedition_snapshot().node.room_id == "BO01", "legacy route still reaches its original boss")
	_check(game.finish_run("extracted").get("outcome") == "extracted" and "BO01" in game.profile.bosses, "legacy final boss extracts normally")
	game.free()

func _restart_mode() -> void:
	_check(not restart_path.is_empty() and restart_path.is_absolute_path(), "restart path is explicit and isolated")
	if restart_path.is_empty(): return
	var game := _game(restart_path)
	if mode == "write":
		_start(game)
		if game.run != null and _advance(game):
			game.add_gold(37)
			game.collect_expedition_equipment("cross-process-drop", "EQ02")
			var runtime: Dictionary = _runtime(game)
			runtime.hp = 71.0
			runtime.player.cooldowns.q = 3.5
			_check(game.commit_expedition_completion("cross-process-complete", runtime, {"gold":12,"xp":60}), "write actual cleared checkpoint")
	elif mode == "read":
		_check(game.run != null and game.run.expedition.phase == "cleared", "new process resumes checkpoint")
		if game.run != null:
			_check(game.run.hp == 71.0 and game.run.gold == 49 and game.profile.hero_xp.CH01 == 60, "new process restores exact actor and reward values")
			_check(game.run.expedition.runtime.player.cooldowns.q == 3.5 and game.run.expedition.pending_equipment.has("EQ02"), "new process retains cooldown and pending gear")
			_check(game.commit_expedition_completion("cross-process-complete", _runtime(game), {"gold":999,"xp":900}) and game.run.gold == 49, "new process duplicate event cannot repay")
	else: _check(false, "known restart mode")
	game.free()
