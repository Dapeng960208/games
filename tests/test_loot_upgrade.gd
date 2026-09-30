extends SceneTree
## Enhanced drops are real temporary loadouts, secured only by extraction.
## Fixtures enter the same safe-boundary transactions as the live room.
const Controller = preload("res://scripts/core/run_controller.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Expedition = preload("res://scripts/core/expedition_state.gd")
const Store = preload("res://scripts/core/profile_store.gd")
const Registry = preload("res://scripts/data/content_registry.gd")
var checks := 0
var failures := 0
var directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("LOOT UPGRADE FAIL: " + label)

func _game(name: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + name + ".json"
	root.add_child(game)
	_check(game.new_profile(), "create isolated " + name + " profile")
	return game

func _files(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): result[suffix] = FileAccess.get_file_as_bytes(path + suffix)
	return result

func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _runtime(game: Node) -> Dictionary:
	var saved: Dictionary = game.run.expedition.get("runtime", {})
	if saved.get("mode") == "safe_boundary":
		var copy: Dictionary = saved.duplicate(true)
		copy.hp = game.run.hp
		copy.resource = game.run.resource
		return copy
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

func _advance(game: Node, preferred_room: String = "") -> bool:
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		_check(game.choose_run_relic(offer.offer_id, "skip", "", _runtime(game)), "resolve real relic offer")
	var state: Dictionary = game.expedition_snapshot()
	var next: Dictionary = state.next_node
	if next.is_empty(): return false
	var room_id: String = preferred_room if next.options.has(preferred_room) else str(next.room_id)
	_check(game.choose_expedition_node(int(next.node_index), room_id), "lock actual next node")
	var result: bool = game.advance_expedition_node(_runtime(game), str(state.checkpoint_id))
	_check(result, "advance with committed runtime")
	return result

func _start(game: Node, difficulty: int = 0, first_room: String = "") -> bool:
	var started: bool = game.start_run({"expedition":true,"biome_id":"B01","difficulty":difficulty,"seed":960208})
	_check(started, "start genuine expedition difficulty " + str(difficulty))
	return started and _advance(game, first_room)

func _drop_id(game: Node, id: String, suffix: String = "") -> String:
	return game.run.id + ":node:" + str(game.run.expedition.node_index) + ":gear:" + id + suffix

func _clear(game: Node, drops: Array = []) -> bool:
	var completion: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	var result: bool = game.commit_expedition_completion(completion, _runtime(game), {"gold":12,"xp":0,"mastery":0,"equipment":drops})
	_check(result, "commit actual room rewards")
	return result

func _extract(game: Node) -> Dictionary:
	# The route's first extraction is its second combat objective, not the first.
	if not _advance(game) or not _clear(game): return {}
	var result: Dictionary = game.finish_run("extracted")
	_check(not result.is_empty() and result.outcome == "extracted", "secure loot at actual extraction")
	return result

func _run() -> void:
	directory = "user://loot_upgrade_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_legacy_and_claim_identity()
	_field_upgrade_and_settlement("death")
	_field_upgrade_and_settlement("extracted")
	_atomic_transactions()
	_receipt_bounds()
	_optional_difficulty()
	_route_versions()
	print("LOOT UPGRADE TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _legacy_and_claim_identity() -> void:
	var game := _game("legacy")
	if not _start(game): game.free(); return
	var zero: String = _drop_id(game, "EQ08")
	_check(game.collect_expedition_equipment(zero, "EQ08"), "omitted drop level remains valid")
	_check(game.run.expedition.pending_equipment.EQ08 == {"drop_id":zero}, "legacy +0 pending shape is unchanged")
	_check(game.run.expedition.claimed_drop_ids[zero] == {"equipment_id":"EQ08","result":"pending","gold":0}, "legacy +0 claim shape is unchanged")
	var plus: String = _drop_id(game, "EQ04")
	_check(game.collect_expedition_equipment(plus, "EQ04", 5), "maximum legal +5 is staged")
	var before: Dictionary = game.run.live_receipt().duplicate(true)
	_check(game.collect_expedition_equipment(plus, "EQ04", 5.0), "numeric integral replay has same identity")
	_check(not game.collect_expedition_equipment(plus, "EQ04", 4), "same drop cannot replay a changed level")
	_check(not game.collect_expedition_equipment(plus, "EQ05", 5), "same drop cannot replay a changed item")
	_check(game.run.live_receipt() == before, "replay and rejected claims leave staged state unchanged")
	var duplicate: String = _drop_id(game, "EQ04", ":duplicate")
	var gold_before: int = game.run.gold
	_check(game.collect_expedition_equipment(duplicate, "EQ04", 3), "later pending duplicate has defined conversion")
	_check(game.run.expedition.pending_equipment.EQ04 == {"drop_id":plus,"level":5}, "duplicate preserves first pending item and level")
	_check(game.run.gold > gold_before and game.run.expedition.claimed_drop_ids[duplicate].result == "gold", "duplicate adds actual currency exactly once")
	gold_before = game.run.gold
	_check(game.collect_expedition_equipment(duplicate, "EQ04", 3) and game.run.gold == gold_before, "duplicate conversion replay does not award twice")
	if _clear(game):
		_check(Expedition.valid(game.run.live_receipt(), game.profile), "mixed legacy and enhanced cleared receipt is valid")
		var result: Dictionary = _extract(game)
		_check(not result.is_empty() and game.profile.equipment.EQ04.level == 5 and game.profile.equipment.EQ08.level == 0, "packed loot secures its actual levels")
		game.reload_profile()
		_check(game.run == null and game.profile.equipment.EQ04.level == 5, "maximum level persists through reload")
	game.free()

func _field_upgrade_and_settlement(outcome: String) -> void:
	var game := _game(outcome)
	# Earn a permanent +1 first. The next +3 drop is an upgrade of an owned ID.
	if not _start(game): game.free(); return
	var seed_drop: String = _drop_id(game, "EQ21")
	if not _clear(game, [{"drop_id":seed_drop,"equipment_id":"EQ21","drop_level":1}]): game.free(); return
	if _extract(game).is_empty(): game.free(); return
	_check(game.profile.equipment.EQ21.level == 1, "first extraction establishes permanent +1")
	if not _start(game, 3): game.free(); return
	var permanent: Dictionary = game.profile.duplicate(true)
	var drop: String = _drop_id(game, "EQ21")
	if not _clear(game, [{"drop_id":drop,"equipment_id":"EQ21","drop_level":3}]): game.free(); return
	_check(game.run.expedition.pending_equipment.EQ21.level == 3 and game.profile.equipment.EQ21.level == 1, "higher owned drop remains unsecured")
	var preview: Dictionary = game.preview_field_equipment(drop)
	_check(preview.level == 3 and preview.current_level == 1 and preview.current_id == "EQ21", "same-ID comparison exposes both actual levels")
	_check(preview.next_stats.max_hp > preview.current_stats.max_hp, "real resolver gives enhanced gear stronger stats")
	var runtime: Dictionary = _runtime(game)
	runtime.hp = 63.0
	runtime.resource = 7.0
	runtime.player.cooldowns.q = 3.2
	runtime.player.cooldowns.secondary = 1.1
	runtime.equipment.clock = 10.0
	runtime.equipment.adapter.clock = 10.0
	runtime.equipment.cooldowns["EQ21:spent-room"] = 16.0
	var checkpoint: String = game.run.expedition.checkpoint_id
	_check(game.choose_field_equipment(drop, "equip", runtime, checkpoint), "equip actual higher-level same-ID drop")
	_check(game.run.equipment_snapshot.EQ21.level == 3 and game.run.max_hp == preview.next_stats.max_hp, "run snapshot and resolved stats use drop level")
	_check(game.profile == permanent, "field upgrade never changes permanent collection")
	_check(game.run.hp == 63.0 and game.run.resource == 7.0 and game.run.expedition.runtime.player.cooldowns == runtime.player.cooldowns, "upgrade preserves actor health, resource and skills")
	_check(game.run.expedition.runtime.equipment.cooldowns == runtime.equipment.cooldowns, "same item upgrade preserves equipment cooldown history")
	var equipped: Dictionary = game.run.live_receipt().duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	_check(game.choose_field_equipment(drop, "equip", {}, checkpoint), "same upgrade decision retries idempotently")
	_check(game.run.live_receipt() == equipped and _files(game.profile_path) == bytes, "upgrade retry changes no live or saved state")
	game.reload_profile()
	_check(game.run != null and _same_json(game.run.receipt(), equipped), "enhanced temporary equipment survives restart atomically")
	if game.run == null: game.free(); return
	var result: Dictionary = {}
	if outcome == "extracted": result = _extract(game)
	else:
		game.damage_player(game.run.hp + game.run.shield + 1.0, {"damage_type":"true"})
		result = game.last_result
	_check(not result.is_empty() and result.outcome == outcome, "real " + outcome + " finishes enhanced run")
	var expected := 3 if outcome == "extracted" else 1
	_check(game.profile.equipment.EQ21.level == expected, outcome + " applies only its proper permanent level")
	_check(game.profile.loadout == permanent.loadout, "same-ID upgrade preserves chosen permanent slots")
	_check(result.get("equipment_retained" if outcome == "extracted" else "equipment_lost", []).has("EQ21"), "settlement names the secured or lost upgrade")
	game.reload_profile()
	_check(game.run == null and game.profile.equipment.EQ21.level == expected, "settled upgrade result survives reload")
	if outcome == "extracted" and _start(game):
		for level: int in [0, 1, 3]:
			var duplicate: String = _drop_id(game, "EQ21", ":owned:" + str(level))
			_check(game.collect_expedition_equipment(duplicate, "EQ21", level), "same/lower owned level converts safely")
			_check(game.run.expedition.claimed_drop_ids[duplicate].result == "gold" and not game.run.expedition.pending_equipment.has("EQ21"), "weaker drop never downgrades collection")
		if _clear(game):
			_extract(game)
			_check(game.profile.equipment.EQ21.level == 3, "later weak-loot extraction preserves permanent maximum")
	game.free()

func _atomic_transactions() -> void:
	var game := _game("atomic")
	if not _start(game): game.free(); return
	var drop: String = _drop_id(game, "EQ21")
	var rewards: Array = [{"drop_id":drop,"equipment_id":"EQ21","drop_level":3}]
	var receipt: Dictionary = game.run.live_receipt().duplicate(true)
	var profile: Dictionary = game.profile.duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	var blocker: String = directory + "/write-blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	_check(file != null, "create storage failure fixture")
	if file == null: game.free(); return
	file.store_string("not a directory")
	file.close()
	game._store.path = blocker + "/profile.json"
	var completion: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	_check(not game.commit_expedition_completion(completion, _runtime(game), {"gold":12,"equipment":rewards}), "failed completion write does not grant +3")
	_check(game.run.live_receipt() == receipt and game.profile == profile and _files(game.profile_path) == bytes, "failed enhanced reward transaction is fully unchanged")
	game._store.path = game.profile_path
	if not _clear(game, rewards): game.free(); return
	receipt = game.run.live_receipt().duplicate(true)
	profile = game.profile.duplicate(true)
	bytes = _files(game.profile_path)
	game._store.path = blocker + "/profile.json"
	_check(not game.choose_field_equipment(drop, "equip", _runtime(game), game.run.expedition.checkpoint_id), "failed equip write does not apply stronger stats")
	_check(game.run.live_receipt() == receipt and game.profile == profile and _files(game.profile_path) == bytes, "failed equip leaves old ownership and actor intact")
	game._store.path = game.profile_path
	_check(game.choose_field_equipment(drop, "equip", _runtime(game), game.run.expedition.checkpoint_id), "equip retries after storage recovery")
	if not _advance(game) or not _clear(game): game.free(); return
	receipt = game.run.live_receipt().duplicate(true)
	profile = game.profile.duplicate(true)
	bytes = _files(game.profile_path)
	game._store.path = blocker + "/profile.json"
	_check(game.finish_run("extracted").is_empty(), "failed extraction cannot permanently grant upgrade")
	_check(game.run.live_receipt() == receipt and game.profile == profile and _files(game.profile_path) == bytes, "failed extraction leaves permanent +0 and live +3 intact")
	game._store.path = game.profile_path
	var result: Dictionary = game.finish_run("extracted")
	_check(not result.is_empty() and game.profile.equipment.EQ21.level == 3, "extraction retry secures upgrade once")
	bytes = _files(game.profile_path)
	_check(game.finish_run("extracted") == result and _files(game.profile_path) == bytes, "settlement replay neither upgrades nor saves twice")
	game.free()

func _receipt_bounds() -> void:
	var game := _game("bounds")
	if not _start(game): game.free(); return
	for bad: Variant in [-1, 6, 5.1, 0.5, "3", true, null, INF, NAN]:
		var before: Dictionary = game.run.live_receipt().duplicate(true)
		_check(not game.collect_expedition_equipment(_drop_id(game, "EQ21", ":bad"), "EQ21", bad), "reject nonintegral/nonbounded drop " + str(bad))
		_check(game.run.live_receipt() == before, "bad drop produces no discovery, gold or pending record")
	var drop: String = _drop_id(game, "EQ21")
	if not _clear(game, [{"drop_id":drop,"equipment_id":"EQ21","drop_level":3}]): game.free(); return
	var valid: Dictionary = game.run.live_receipt().duplicate(true)
	_check(Expedition.valid(valid, game.profile), "enhanced owned pending receipt passes validation")
	for bad: Variant in [-1, 6, 5.1, "3", true]:
		var forged: Dictionary = valid.duplicate(true)
		forged.expedition.pending_equipment.EQ21.level = bad
		_check(not Expedition.valid(forged, game.profile), "pending validator rejects " + str(bad))
		forged = valid.duplicate(true)
		forged.expedition.claimed_drop_ids[drop].level = bad
		_check(not Expedition.valid(forged, game.profile), "claim validator rejects " + str(bad))
		var invalid_profile: Dictionary = game.profile.duplicate(true)
		invalid_profile.equipment.EQ21.level = bad
		_check(not Store._valid_progression(invalid_profile), "permanent validator rejects " + str(bad))
	var forged: Dictionary = valid.duplicate(true)
	forged.expedition.claimed_drop_ids[drop].level = 2
	_check(not Expedition.valid(forged, game.profile), "claim and pending levels must match")
	forged = valid.duplicate(true)
	forged.expedition.pending_equipment.EQ21.level = 0
	forged.expedition.claimed_drop_ids[drop].level = 0
	_check(not Expedition.valid(forged, game.profile), "owned equal-level drop cannot masquerade as pending upgrade")
	_check(game.choose_field_equipment(drop, "equip", _runtime(game), game.run.expedition.checkpoint_id), "valid equip binds +3 snapshot provenance")
	valid = game.run.live_receipt().duplicate(true)
	for bad: Variant in [0, 2, 4, 5.1, -1, 6, true]:
		forged = valid.duplicate(true)
		forged.equipment_snapshot.EQ21.level = bad
		_check(not Expedition.valid(forged, game.profile), "snapshot cannot forge a different upgrade level " + str(bad))
	forged = valid.duplicate(true)
	forged.expedition.claimed_drop_ids[drop].field_decision = "keep"
	_check(not Expedition.valid(forged, game.profile), "unselected upgrade cannot retain enhanced snapshot")
	game.free()

func _optional_difficulty() -> void:
	var game := _game("optional")
	if not _start(game, 4) or not _clear(game) or not _advance(game, "L01"): game.free(); return
	var node: Dictionary = game.run.expedition.route.nodes[int(game.run.expedition.node_index)]
	_check(node.room_id == "L01", "actual objective branch selects authored side cache room")
	if node.room_id != "L01" or not _clear(game): game.free(); return
	var claimed: bool = game.claim_expedition_optional_reward(int(node.node_index), "side_crate", _runtime(game), game.run.expedition.checkpoint_id)
	_check(claimed, "claim actual cache using active difficulty")
	if not claimed: game.free(); return
	var cache: Dictionary = game.run.expedition.optional_claims.values()[0]
	_check(cache.drop_ids.size() == 2, "highest-difficulty cache includes actual extra gear")
	for id: String in cache.drop_ids:
		_check(game.run.expedition.claimed_drop_ids[id].get("level", 0) == 3, "optional drop uses +3 difficulty reward")
	_check(Expedition.valid(game.run.live_receipt(), game.profile), "enhanced optional receipt has valid source and levels")
	var before: Dictionary = game.run.live_receipt().duplicate(true)
	_check(game.claim_expedition_optional_reward(int(node.node_index), "side_crate", {}, game.run.expedition.checkpoint_id) and game.run.live_receipt() == before, "cache retry does not add stronger gear twice")
	game.reload_profile()
	_check(game.run != null and _same_json(game.run.receipt(), before), "enhanced cache claim survives reload")
	game.free()

func _route_versions() -> void:
	for level: int in [5, 15]:
		var game := _game("route-" + str(level))
		_check(game.start_run(), "earn route-tier XP through regular run")
		_check(game.grant_hero_xp(Registry.XP_THRESHOLDS[level - 1], "route-training"), "earn selected departure tier")
		game.finish_run("extracted")
		_check(game.start_run({"expedition":true,"biome_id":"B01","seed":42000 + level}), "start selected biome at level " + str(level))
		if game.run == null: game.free(); continue
		var fresh: Dictionary = game.run.live_receipt().duplicate(true)
		_check(fresh.expedition.route.dynamic_version == 2, "new tier route uses single-biome v2")
		_check(Expedition.valid(fresh, game.profile), "new tier receipt validates with repeated templates when needed")
		for invalid_version: Variant in [0, 3, 1.5, true, "2", {}]:
			var invalid_route: Dictionary = fresh.duplicate(true)
			invalid_route.expedition.route.dynamic_version = invalid_version
			_check(not Expedition.valid(invalid_route, game.profile), "reject malformed saved route version without coercion")
		for node: Dictionary in fresh.expedition.route.nodes:
			_check(node.biome_id == "B01", "selected biome persists through every node")
		_check(fresh.expedition.route.nodes[-1].room_id == "BO01", "higher hero tier retains selected clan boss")
		var forged: Dictionary = fresh.duplicate(true)
		forged.expedition.route.nodes[-1].room_id = "BO02"
		forged.expedition.route.nodes[-1].biome_id = "B02"
		_check(not Expedition.valid(forged, game.profile), "v2 receipt cannot change to another clan boss")
		if level == 5:
			# Restore an actual old dynamic route, whose descent rotates regions.
			var legacy: Dictionary = Expedition.Routes.generate("B01", int(fresh.expedition.seed), [], level)
			fresh.expedition.route = legacy
			_check(game._store.save_document(game.profile, fresh), "v1 dynamic checkpoint remains persistable")
			game.reload_profile()
			_check(game.run != null and game.run.expedition.route.dynamic_version == 1, "v1 checkpoint reload preserves its historical route version")
			_check(game.run.expedition.route.nodes[-1].room_id == legacy.nodes[-1].room_id, "v1 reload retains its historical adjacent-region boss")
			if _advance(game) and _clear(game):
				var cleared: Dictionary = game.run.live_receipt().duplicate(true)
				game.reload_profile()
				_check(game.run != null and _same_json(game.run.receipt(), cleared) and game.run.expedition.route.dynamic_version == 1, "v1 branch choice and completion continue through real saved APIs")
		else:
			game.reload_profile()
			_check(game.run != null and _same_json(game.run.receipt(), fresh), "Lv15 repeated single-clan templates survive restart")
			if _advance(game) and _clear(game):
				game.reload_profile()
				_check(game.run != null and game.run.expedition.route.dynamic_version == 2 and game.run.expedition.node_index == 1, "v2 branch choice and combat completion remain valid on disk")
		game.free()
