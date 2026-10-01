extends SceneTree
## Core transactions with explicit safe-boundary actor fixtures. Reward payloads
## exercise the real completion API; no engine scene or combat balance probe.
const Controller = preload("res://scripts/core/run_controller.gd")
const Snapshot = preload("res://scripts/combat/combat_snapshot.gd")
const Expedition = preload("res://scripts/core/expedition_state.gd")
var checks: int = 0
var failures: int = 0
var directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FIELD EQUIPMENT FAIL: " + label)

func _game(name: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + name + ".json"
	root.add_child(game)
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

func _advance(game: Node) -> bool:
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		_check(game.choose_run_relic(offer.offer_id, "skip", "", _runtime(game)), "resolve real entrance/reward offer")
	var state: Dictionary = game.expedition_snapshot()
	var next: Dictionary = state.next_node
	if next.is_empty(): return false
	_check(game.choose_expedition_node(int(next.node_index), str(next.room_id)), "lock actual next route node")
	var success: bool = game.advance_expedition_node(_runtime(game), str(state.checkpoint_id))
	_check(success, "advance with committed runtime")
	return success

func _start(game: Node, hero: String = "CH01") -> bool:
	_check(game.new_profile() and game.select_hero(hero), "create isolated " + hero + " profile")
	var started: bool = game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":960208})
	_check(started, "depart with ordinary starter equipment")
	return started and _advance(game)

func _drop_id(game: Node, id: String) -> String:
	return game.run.id + ":node:" + str(game.run.expedition.node_index) + ":gear:" + id

func _clear(game: Node, ids: Array[String]) -> bool:
	var drops: Array = []
	for id: String in ids: drops.append({"drop_id":_drop_id(game, id),"equipment_id":id})
	var completion: String = game.run.id + ":node:" + str(game.run.expedition.node_index) + ":complete"
	var success: bool = game.commit_expedition_completion(completion, _runtime(game), {"gold":12,"xp":0,"mastery":0,"equipment":drops})
	_check(success, "commit room and its actual pending rewards")
	return success

func _run() -> void:
	directory = "user://field_equipment_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for hero: String in ["CH01", "CH02", "CH03"]: _equip_and_restore(hero)
	_keep_and_atomic_failure()
	_runtime_caps()
	_receipt_validation()
	_settlement()
	print("FIELD EQUIPMENT TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _equip_and_restore(hero: String) -> void:
	var game := _game("equip-" + hero)
	if not _start(game, hero): game.free(); return
	var id: String = {"CH01":"EQ08","CH02":"EQ58","CH03":"EQ03"}[hero]
	var drop: String = _drop_id(game, id)
	_check(game.collect_expedition_equipment(drop, id), hero + " stages one real pending drop")
	_check(game.pending_field_equipment().is_empty() and game.preview_field_equipment(drop).is_empty(), "combat does not expose field equipment choices")
	_check(not game.choose_field_equipment(drop, "equip", _runtime(game), game.run.expedition.checkpoint_id), "combat cannot equip staged loot")
	if not _clear(game, [id]): game.free(); return
	var before: Dictionary = game.run.live_receipt().duplicate(true)
	var profile_before: Dictionary = game.profile.duplicate(true)
	var offers: Array = game.pending_field_equipment()
	_check(offers.size() == 1 and offers[0].drop_id == drop and offers[0].equipment_id == id, "one pending drop produces one field choice")
	var preview: Dictionary = game.preview_field_equipment(drop)
	_check(not preview.is_empty() and preview.current_id == before.loadout_snapshot[preview.slot], "preview compares current run slot")
	_check(game.run.live_receipt() == before and game.profile == profile_before, "preview never mutates run or profile")
	preview.next_stats.attack = 99999.0
	_check(float(game.preview_field_equipment(drop).next_stats.attack) < 99999.0, "preview dictionaries do not alias authoritative stats")
	var runtime: Dictionary = _runtime(game)
	runtime.hp = 63.0
	runtime.resource = 7.0
	runtime.player.cooldowns.q = 3.2
	runtime.player.cooldowns.secondary = 1.1
	runtime.player.dash_cooldown = 0.7
	runtime.equipment.clock = 10.0
	runtime.equipment.adapter.clock = 10.0
	runtime.equipment.cooldowns["EQ21:spent-room"] = 16.0
	runtime.equipment.room_low_shield_used = true
	var checkpoint: String = game.run.expedition.checkpoint_id
	_check(not game.choose_field_equipment(drop, "equip", runtime, checkpoint + ":stale"), "stale checkpoint rejects without selecting")
	_check(not game.choose_field_equipment(id, "equip", runtime, checkpoint) and not game.choose_field_equipment(drop, "invalid", runtime, checkpoint), "item IDs and unknown decisions cannot forge a drop choice")
	_check(not game.choose_field_equipment(drop, "equip", {}, checkpoint), "missing actor state cannot silently refill character")
	_check(game.choose_field_equipment(drop, "equip", runtime, checkpoint), hero + " commits real field equipment")
	_check(game.run.loadout_snapshot[preview.slot] == id and game.run.equipment_snapshot[id].level == 0, "only correct slot and level-zero snapshot are updated")
	_check(game.run.expedition.pending_equipment.has(id) and game.profile == profile_before and not game.profile.equipment.has(id), "wearing loot does not secure or permanently equip it")
	_check(is_equal_approx(game.run.hp, 63.0) and is_equal_approx(game.run.resource, 7.0), "field equip preserves absolute health and resource")
	_check(game.run.expedition.runtime.player.cooldowns == runtime.player.cooldowns and is_equal_approx(game.run.expedition.runtime.player.dash_cooldown, 0.7), "field equip preserves skill and dash cooldowns")
	_check(game.run.expedition.runtime.equipment.cooldowns == runtime.equipment.cooldowns and game.run.expedition.runtime.equipment.room_low_shield_used, "field equip preserves equipment ICD and spent room trigger")
	_check(game.pending_field_equipment().is_empty(), "decided drop leaves reward queue")
	var committed: Dictionary = game.run.live_receipt().duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	_check(game.choose_field_equipment(drop, "equip", {}, checkpoint) and not game.choose_field_equipment(drop, "keep", {}, checkpoint), "same decision retries without new mutation; opposite decision rejects")
	_check(game.run.live_receipt() == committed and _files(game.profile_path) == bytes, "idempotent retry does not write or restore stale actor values")
	game.reload_profile()
	_check(game.run != null and _same_json(game.run.receipt(), committed), "reload restores choice, temporary equipment and actor state atomically")
	if game.run == null: game.free(); return
	_check(game.pending_field_equipment().is_empty() and game.choose_field_equipment(drop, "equip", {}, checkpoint), "decision remains idempotent after restart")
	if _advance(game):
		_check(game.run.loadout_snapshot[preview.slot] == id and is_equal_approx(game.run.hp, 63.0), "next room receives chosen equipment without healing")
		_check(not game.choose_field_equipment(drop, "equip", _runtime(game), checkpoint), "old cleared-room callback cannot act during next combat")
	game.free()

func _keep_and_atomic_failure() -> void:
	var game := _game("atomic")
	if not _start(game) or not _clear(game, ["EQ08", "EQ48"]): game.free(); return
	var equip_drop: String = _drop_id(game, "EQ08")
	var keep_drop: String = _drop_id(game, "EQ48")
	var checkpoint: String = game.run.expedition.checkpoint_id
	var runtime: Dictionary = _runtime(game)
	var before: Dictionary = game.run.live_receipt().duplicate(true)
	var profile_before: Dictionary = game.profile.duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	var blocker: String = directory + "/write-blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	_check(file != null, "storage failure fixture is writable")
	if file == null: game.free(); return
	file.store_string("not a directory")
	file.close()
	game._store.path = blocker + "/profile.json"
	_check(not game.choose_field_equipment(equip_drop, "equip", runtime, checkpoint), "failed disk write refuses equip")
	_check(not game.choose_field_equipment(keep_drop, "keep", runtime, checkpoint), "failed disk write refuses keep decision")
	_check(game.run.live_receipt() == before and game.profile == profile_before and _files(game.profile_path) == bytes, "both failures leave live state and saved profile bytes untouched")
	_check(game.pending_field_equipment().size() == 2, "failed choices remain available")
	game._store.path = game.profile_path
	_check(game.choose_field_equipment(keep_drop, "keep", runtime, checkpoint), "keep decision retries after storage recovers")
	_check(game.run.loadout_snapshot == before.loadout_snapshot and game.run.equipment_snapshot == before.equipment_snapshot and game.run.expedition.pending_equipment.has("EQ48"), "keeping current does not throw away the reward or change equipment")
	_check(game.choose_field_equipment(equip_drop, "equip", _runtime(game), checkpoint), "equip retry succeeds once")
	game.reload_profile()
	_check(game.run != null and game.pending_field_equipment().is_empty() and game.run.loadout_snapshot.weapon == "EQ08", "both decisions survive reload without another card")
	game.free()

func _runtime_caps() -> void:
	var game := _game("caps")
	if not _start(game, "CH03") or not _clear(game, ["EQ32"]): game.free(); return
	var drop: String = _drop_id(game, "EQ32")
	var runtime: Dictionary = _runtime(game)
	runtime.hp = 77.0
	runtime.resource = 90.0
	_check(game.choose_field_equipment(drop, "equip", runtime, game.run.expedition.checkpoint_id), "equip larger mana capacity")
	_check(is_equal_approx(game.run.stats.resource_max, 110.0) and is_equal_approx(game.run.resource, 90.0), "larger mana capacity supplies no free mana")
	if not _advance(game) or not _clear(game, ["EQ33", "EQ58"]): game.free(); return
	var checkpoint: String = game.run.expedition.checkpoint_id
	runtime = _runtime(game)
	runtime.resource = 108.0
	runtime.hp = game.run.max_hp
	_check(game.choose_field_equipment(_drop_id(game, "EQ33"), "equip", runtime, checkpoint), "replace mana-bearing hand slot")
	_check(is_equal_approx(game.run.stats.resource_max, 100.0) and is_equal_approx(game.run.resource, 100.0), "lower mana capacity clamps the existing resource")
	var previous_max: float = game.run.max_hp
	_check(game.choose_field_equipment(_drop_id(game, "EQ58"), "equip", _runtime(game), checkpoint), "replace health-bearing charm")
	_check(game.run.max_hp < previous_max and is_equal_approx(game.run.hp, game.run.max_hp), "lower health capacity clamps without creating extra health")
	game.free()

func _receipt_validation() -> void:
	var game := _game("validation")
	if not _start(game) or not _clear(game, ["EQ08", "EQ48"]): game.free(); return
	var old: Dictionary = game.run.live_receipt().duplicate(true)
	_check(Expedition.valid(old, game.profile), "older checkpoint without field decisions remains valid")
	var forged: Dictionary = old.duplicate(true)
	forged.equipment_snapshot["EQ03"] = {"level":0}
	_check(not Expedition.valid(forged, game.profile), "unearned catalog item cannot be injected into snapshot")
	forged = old.duplicate(true)
	forged.equipment_snapshot.EQ01.level = 1
	_check(not Expedition.valid(forged, game.profile), "owned item cannot gain an unearned upgrade in the run")
	forged = old.duplicate(true)
	forged.equipment_snapshot["EQ08"] = {"level":0}
	forged.loadout_snapshot.weapon = "EQ08"
	_check(not Expedition.valid(forged, game.profile), "pending loot without equip decision cannot enter loadout")
	var drop: String = _drop_id(game, "EQ08")
	_check(game.choose_field_equipment(drop, "equip", _runtime(game), game.run.expedition.checkpoint_id), "valid equip establishes provenance")
	var valid: Dictionary = game.run.live_receipt().duplicate(true)
	_check(Expedition.valid(valid, game.profile), "selected pending equipment passes receipt validation")
	forged = valid.duplicate(true)
	forged.equipment_snapshot.EQ08.level = 1
	_check(not Expedition.valid(forged, game.profile), "pending equipment must stay level zero")
	forged = valid.duplicate(true)
	forged.expedition.claimed_drop_ids[drop].field_decision = "keep"
	_check(not Expedition.valid(forged, game.profile), "kept equipment cannot retain a forged equipped snapshot")
	forged = valid.duplicate(true)
	forged.expedition.claimed_drop_ids[drop].field_decision = "invalid"
	_check(not Expedition.valid(forged, game.profile), "invalid decision is rejected on load")
	forged = valid.duplicate(true)
	forged.equipment_snapshot.erase("EQ08")
	forged.loadout_snapshot.weapon = "EQ01"
	_check(not Expedition.valid(forged, game.profile), "equip decision must have its matching owned-for-run snapshot")
	game.free()

func _settlement() -> void:
	for outcome: String in ["death", "extracted"]:
		var game := _game("settle-" + outcome)
		if not _start(game) or not _clear(game, ["EQ08", "EQ48"]): game.free(); continue
		var checkpoint: String = game.run.expedition.checkpoint_id
		_check(game.choose_field_equipment(_drop_id(game, "EQ08"), "equip", _runtime(game), checkpoint), "settlement fixture equips loot")
		_check(game.choose_field_equipment(_drop_id(game, "EQ48"), "keep", _runtime(game), checkpoint), "settlement fixture packs loot")
		var original_loadout: Dictionary = game.profile.loadout.duplicate(true)
		if not _advance(game): game.free(); continue
		var result: Dictionary = {}
		if outcome == "extracted":
			if not _clear(game, []): game.free(); continue
			result = game.finish_run("extracted")
		else:
			game.damage_player(game.run.hp + game.run.shield + 1.0, {"damage_type":"true"})
			result = game.last_result
		_check(not result.is_empty() and result.outcome == outcome, "real " + outcome + " settlement finishes")
		_check(game.profile.loadout == original_loadout, "field decision never replaces permanent default loadout")
		for id: String in ["EQ08", "EQ48"]:
			_check(game.profile.equipment.has(id) == (outcome == "extracted"), outcome + " applies same ownership rule to equipped and packed loot")
			var list: Array = result.get("equipment_retained" if outcome == "extracted" else "equipment_lost", [])
			_check(list.has(id), outcome + " receipt names " + id)
		game.reload_profile()
		_check(game.run == null and game.profile.equipment.has("EQ08") == (outcome == "extracted"), "settlement ownership survives reload")
		game.free()
