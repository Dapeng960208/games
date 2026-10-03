extends "res://tests/equipment/test_loot_upgrade.gd"
## Round-two production-controller regressions, always using isolated profiles.

func _run() -> void:
	directory = "user://audit_controller_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_stronger_pending()
	_pending_lifecycle("extracted")
	_pending_lifecycle("death")
	_pending_save_failure()
	_presets_and_discovery()
	_branch_trial()
	_free_preparation()
	print("AUDIT CONTROLLER TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _stronger_pending() -> void:
	var game := _game("stronger_pending")
	if not _start(game): game.free(); return
	var low: String = _drop_id(game, "EQ21", ":low")
	var high: String = _drop_id(game, "EQ21", ":high")
	_check(game.collect_expedition_equipment(low, "EQ21", 1), "A13 stage +1")
	var before: int = game.run.gold
	_check(game.collect_expedition_equipment(high, "EQ21", 2), "A13 stage later +2")
	_check(game.run.expedition.pending_equipment.EQ21.level == 2, "A13 highest pending level survives")
	_check(game.run.gold == before, "A13 stronger drop is not converted to gold")
	game.free()

func _pending_lifecycle(outcome: String) -> void:
	var game := _game("pending_" + outcome)
	if not _start(game): game.free(); return
	var low: String = _drop_id(game, "EQ21", ":low")
	if not _clear(game, [{"drop_id":low,"equipment_id":"EQ21","drop_level":1}]): game.free(); return
	var runtime: Dictionary = _runtime(game)
	runtime.hp = 67.0
	runtime.player.cooldowns.q = 3.0
	_check(game.choose_field_equipment(low, "equip", runtime, game.run.expedition.checkpoint_id), "A13 equip original +1")
	if not _advance(game): game.free(); return
	var high: String = _drop_id(game, "EQ21", ":high")
	var top: String = _drop_id(game, "EQ21", ":top")
	_check(game.collect_expedition_equipment(high, "EQ21", 2), "A13 later +2 replaces pending")
	_check(game.collect_expedition_equipment(top, "EQ21", 3), "A13 multiple higher pending upgrades")
	_check(game.run.equipment_snapshot.EQ21.level == 1, "A13 does not silently alter currently worn copy")
	var staged: Dictionary = game.run.live_receipt().duplicate(true)
	_check(game.collect_expedition_equipment(low, "EQ21", 1) and game.collect_expedition_equipment(top, "EQ21", 3), "A13 old/new event retries accepted")
	_check(game.run.live_receipt() == staged, "A13 retries neither convert nor duplicate")
	_check(not game.collect_expedition_equipment(low, "EQ21", 2), "A13 old event cannot change its frozen strength")
	var gold_before: int = game.run.gold
	var weak: String = _drop_id(game, "EQ21", ":weak")
	_check(game.collect_expedition_equipment(weak, "EQ21", 2), "A13 later weaker duplicate converted")
	_check(game.run.gold > gold_before and game.run.expedition.pending_equipment.EQ21.level == 3, "A13 reverse order keeps strongest")
	if not _clear(game): game.free(); return
	_check(Expedition.valid(game.run.live_receipt(), game.profile), "A13 valid provenance retains earlier worn copy")
	var catalog_item: Dictionary = Registry._equipment["EQ21"]
	var old_price: int = int(catalog_item.price)
	catalog_item.price = old_price + 100
	_check(Expedition.valid(game.run.live_receipt(), game.profile), "A14 duplicate conversion receipt survives live catalog repricing")
	catalog_item.price = old_price
	_check(game.run.hp == 67.0 and game.run.expedition.runtime.player.cooldowns.q == 3.0, "A13 no healing or cooldown refresh")
	game.reload_profile()
	_check(game.run != null and game.run.equipment_snapshot.EQ21.level == 1 and game.run.expedition.pending_equipment.EQ21.level == 3, "A13 restart keeps worn/pending distinction")
	if game.run == null: game.free(); return
	_check(game.choose_field_equipment(top, "equip", _runtime(game), game.run.expedition.checkpoint_id), "A13 player explicitly chooses newest version")
	var forged: Dictionary = game.run.live_receipt().duplicate(true)
	forged.expedition.claimed_drop_ids[low].level = 4
	_check(not Expedition.valid(forged, game.profile), "A13 superseded provenance cannot forge stronger original")
	var result: Dictionary = {}
	if outcome == "death":
		game.damage_player(99999.0, {"damage_type":"true","source_id":"audit_enemy","attack_id":"audit_hit"})
		result = game.last_result
	else: result = game.finish_run("extracted")
	_check(not result.is_empty(), "A13 final settlement succeeds")
	_check(game.profile.equipment.EQ21.level == (3 if outcome == "extracted" else 0), "A13 extraction secures best; death loses pending")
	if outcome == "death":
		_check(result.death_review.lethal_event.attack_id == "audit_hit", "A29 lethal event captured before clearing run")
		_check(not game.profile.last_result.has("death_review") and not FileAccess.get_file_as_string(AssetCatalog.resolve(game.profile_path)).contains("death_review"), "A29 explanation is never persisted")
	game.free()

func _pending_save_failure() -> void:
	var game := _game("pending_failure")
	if not _start(game): game.free(); return
	var low: String = _drop_id(game, "EQ21", ":low")
	_check(game.collect_expedition_equipment(low, "EQ21", 1), "A13 failure fixture low drop")
	var staged: Dictionary = game.run.live_receipt().duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	var old_limit: int = game._store.max_document_bytes
	game._store.max_document_bytes = 1
	var high: String = _drop_id(game, "EQ21", ":high")
	var completion: String = game.run.id+":node:"+str(game.run.expedition.node_index)+":complete"
	var rewards := {"gold":12,"xp":0,"mastery":0,"equipment":[{"drop_id":high,"equipment_id":"EQ21","drop_level":2}]}
	_check(not game.commit_expedition_completion(completion, _runtime(game), rewards), "A13/A15 rejected save refuses pending upgrade atomically")
	_check(game.run.live_receipt() == staged and _files(game.profile_path) == bytes, "A13/A15 failure leaves all prior bytes/claims unchanged")
	game._store.max_document_bytes = old_limit
	_check(game.commit_expedition_completion(completion, _runtime(game), rewards), "A13 retry saves upgraded pending once")
	_check(game.run.expedition.pending_equipment.EQ21.level == 2, "A13 retry retains higher item")
	game.free()

func _fund(game: Node) -> void:
	_check(game.start_run(), "funding fixture run")
	_check(game.add_gold(10000), "funding earned gold")
	_check(not game.finish_run("extracted").is_empty(), "funding extraction")

func _presets_and_discovery() -> void:
	var game := _game("presets")
	_fund(game)
	_check(game.buy_equipment("EQ03", "buy:eq03"), "A21 purchase shared alternate weapon")
	_check(game.equip_item("EQ03"), "A21 warrior alternate loadout")
	_check(game.select_hero("CH02") and game.equip_item("EQ01"), "A21 gunner chooses starter weapon")
	_check(game.select_hero("CH03") and game.equip_item("EQ03"), "A21 mage chooses shared weapon")
	_check(game.select_hero("CH01") and game.profile.loadout.weapon == "EQ03", "A21 warrior preset restored")
	_check(game.hero_loadout("CH02").weapon == "EQ01" and game.profile.loadout.weapon == "EQ03", "A21 hero dossier previews saved preset without changing current gear")
	_check(game.select_hero("CH02") and game.profile.loadout.weapon == "EQ01", "A21 gunner preset restored")
	_check(game.sell_equipment_items(["EQ03"], "sale:eq03"), "A21 sell item used only in inactive presets")
	_check(game.profile.loadout_presets.CH01.weapon == "" and game.profile.loadout_presets.CH03.weapon == "", "A21 sale safely invalidates both references")
	_check(game.select_hero("CH03") and game.profile.loadout.weapon == "EQ01" and game.last_loadout_missing.has("weapon"), "A21 missing item falls back with notice, never duplicates")
	game.reload_profile()
	_check(not game.profile.equipment.has("EQ03") and game.profile.loadout.weapon == "EQ01", "A21 safe preset persists through restart")
	_check(game.start_run({"expedition":true,"biome_id":"B01","seed":123}), "A17 new policy expedition")
	_check(game.reward_discovery_ids().has("EQ03"), "A17 sold historical item remains discovered")
	var known: Array = game.reward_discovery_ids()
	game.run.expedition.erase("reward_policy_version")
	_check(not game.reward_discovery_ids().has("EQ03"), "A17 old active policy retains frozen current-ownership inputs")
	game.run.expedition.reward_policy_version = 1
	_check(game.reward_discovery_ids() == known, "A17 new policy restores historical discovery without replay")
	game.free()

func _branch_trial() -> void:
	var game := _game("branch_trial")
	var before: Dictionary = game.profile.duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	_check(not game.set_hero_branch("q", "A"), "A22 permanent early unlock remains forbidden")
	_check(game.start_demo("CH02", 0, {"q":"B","ultimate":"A"}, true), "A22 early branch preview starts")
	_check(game.run.level == 20 and game.run.branches_snapshot == {"q":"B","ultimate":"A"}, "A22 preview has real branch mechanics at level20")
	_check(not game.finish_run("abandoned").is_empty(), "A22 leave preview")
	_check(game.profile == before and _files(game.profile_path) == bytes, "A22 preview does not change permanent XP/branch/save")
	_check(game.start_demo("CH01"), "A22 normal trial remains available")
	_check(game.run.level == 8 and game.run.branches_snapshot.q == "", "A22 old normal trial remains level8")
	game.finish_run("abandoned")
	game.free()

func _free_preparation() -> void:
	var game := _game("preparation")
	_check(game.select_hero("CH02"), "A18 choose regenerating energy hero")
	if not _start(game): game.free(); return
	while game.run.expedition.route.nodes[game.run.expedition.node_index].role != "supply":
		if game.run.expedition.phase == "combat" and not _clear(game): game.free(); return
		if not _advance(game): game.free(); return
	var runtime: Dictionary = _runtime(game)
	runtime.resource = 12.0
	runtime.player.cooldowns.q = 2.5
	runtime.hp = 68.0
	game.run.resource = 12.0
	var gold_before: int = game.run.gold
	_check(game.prepare_safe_resources(runtime, game.run.expedition.checkpoint_id), "A18 free safe resource preparation")
	_check(game.run.resource == game.run.stats.resource_max and game.run.gold == gold_before, "A18 refill consumes no gold")
	_check(game.run.hp == 68.0 and game.run.expedition.runtime.player.cooldowns.q == 2.5, "A18 preserves HP and cooldowns")
	for offer: Dictionary in game.run.expedition.offers.values():
		_check(offer.get("product_id", "") not in ["mana", "energy"], "A18 new safe room never sells naturally recovering resources")
	var bytes: Dictionary = _files(game.profile_path)
	_check(game.prepare_safe_resources(_runtime(game), game.run.expedition.checkpoint_id) and _files(game.profile_path) == bytes, "A18 full resource repeat is no-op")
	_check(not game.prepare_safe_resources(_runtime(game), "stale"), "A18 stale checkpoint rejected")
	game.reload_profile()
	_check(game.run != null and game.run.resource == game.run.stats.resource_max, "A18 preparation persists across restart")
	game.free()
