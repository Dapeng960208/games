extends SceneTree
## Trial sessions use the production checkpoint APIs with isolated files.
const Controller = preload("res://scripts/app/game.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DEMO SESSION FAIL: " + label)

func _game(name: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + name + ".json"
	root.add_child(game)
	return game

func _files(path: String) -> Dictionary:
	var result := {}
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(AssetCatalog.resolve(path + suffix)): result[suffix] = FileAccess.get_file_as_bytes(AssetCatalog.resolve(path + suffix))
	return result

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

func _advance(game: Node) -> bool:
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		_check(game.choose_run_relic(offer.offer_id, "skip", "", _runtime(game)), "trial resolves real relic offers")
	var next: Dictionary = game.expedition_snapshot().next_node
	_check(game.choose_expedition_node(int(next.node_index), str(next.room_id)), "trial locks a real route choice")
	var advanced: bool = game.advance_expedition_node(_runtime(game))
	_check(advanced, "trial commits real node advancement")
	_check(game.run.demo, "checkpoint rebuild preserves demo identity")
	return advanced

func _run() -> void:
	directory = "user://demo_session_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_existing_profile_trial()
	_new_player_trials()
	_settings_compatibility()
	print("DEMO SESSION TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _existing_profile_trial() -> void:
	var game := _game("existing")
	_check(game.new_profile() and game.select_hero("CH03"), "seed existing mage profile")
	_check(game.start_run(), "seed a normal run")
	game.add_gold(85)
	game.grant_hero_xp(70, "existing-xp")
	game.finish_run("extracted")
	game.set_setting("music_volume", 0.31)
	var original: Dictionary = game.profile.duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	var signals := {"started":0,"finished":0}
	game.run_started.connect(func() -> void: signals.started += 1)
	game.run_finished.connect(func(_result: Dictionary) -> void:
		signals.finished += 1
		signals["profile_at_finish"] = game.profile.duplicate(true)
		signals["result_at_finish"] = game.last_result
		signals["run_cleared_at_finish"] = game.run == null)
	_check(game.start_demo("CH01", 2), "existing player can start full-skill trial")
	_check(game.run.demo and game.run.level == 8 and game.run.hero_id == "CH01", "trial uses selected hero at level eight")
	_check(game.run.hp == game.run.max_hp and game.run.resource == game.run.stats.resource_max, "trial starts at full health and resource")
	_check(game.run.loadout_snapshot == ProfileStore.fresh_profile().loadout and game.run.equipment_snapshot == ProfileStore.fresh_profile().equipment, "trial uses ordinary starter equipment")
	_check(game.run.expedition.route.nodes.size() == 8 and game.run.expedition.difficulty == 2, "trial uses real eight-node route at chosen difficulty")
	_check(signals.started == 1, "trial emits the normal start signal once")
	game.set_setting("music_volume", 0.9)
	game.set_setting("master_volume", 0.4)
	game.set_setting("sfx_volume", 0.2)
	game.set_setting("language", "en")
	for index in range(1, 8):
		if not _advance(game): break
		if index != 4:
			game.add_gold(15)
			game.record_kill()
			game.grant_hero_xp(20, "trial-staged-" + str(index))
			game.complete_hero_tutorial()
			var reward: Dictionary = {"gold":12,"xp":50,"mastery":180}
			if index == 1: reward["equipment"] = [{"drop_id":"trial-gear","equipment_id":"EQ02"}]
			_check(game.commit_expedition_completion("trial-clear-" + str(index), _runtime(game), reward), "trial completion grants temporary progression")
			_check(game.run.demo, "completion preserves sandbox after RunSession replacement")
		_check(_files(game.profile_path) == bytes, "trial route, rewards and settings never write any profile bytes")
	_check(game.run.expedition.node_index == 7 and game.run.expedition.phase == "cleared", "trial reaches and clears its eighth node")
	var result: Dictionary = game.finish_run("extracted")
	_check(result.get("demo", false) and result.collected > 0 and result.retained == 0 and result.hero_xp_gained == 0, "trial result reports play without permanent awards")
	_check(game.profile == original and game.has_profile and game.run == null, "extraction restores exact original profile")
	_check(signals.profile_at_finish == original and signals.result_at_finish == result and signals.run_cleared_at_finish, "finish UI observes restored profile and still receives trial result")
	_check(game.selected_stats().hero_id == "CH03" and game.hero_level() == 3 and game.selected_stats().max_hp == StatResolver.resolve("CH03", 3, original.loadout, original.equipment).max_hp, "temporary trial hero and stat values do not leak into camp")
	_check(_files(game.profile_path) == bytes, "extraction leaves primary, backup and temporary bytes unchanged")
	_check(game.last_result == result and game.finish_run("extracted") == result and signals.finished == 1, "trial result remains readable and duplicate settlement is harmless")
	_check(game.start_run({"expedition":true}), "normal expedition starts after trial")
	_check(not game.run.demo and game.run.hero_id == "CH03" and game.run.level == 3, "normal expedition keeps original hero and level unlocks")
	var active_id: String = game.run.id
	var active_bytes: Dictionary = _files(game.profile_path)
	_check(not game.start_demo("CH02"), "trial refuses to replace active normal run")
	_check(game.run.id == active_id and _files(game.profile_path) == active_bytes, "rejected trial preserves active receipt bytes")
	game.reload_profile()
	_check(game.run != null and game.run.id == active_id and not game.run.demo, "normal expedition remains resumable")
	game.finish_run("abandoned")
	var settled: Dictionary = game.profile.duplicate(true)
	var settled_bytes: Dictionary = _files(game.profile_path)
	_check(game.start_demo("CH02"), "second hero trial starts")
	_check(not game.start_demo("CH03"), "an active trial cannot be overwritten")
	game.damage_player(100000.0)
	_check(game.run == null and game.last_result.outcome == "death" and game.last_result.demo, "trial death goes through normal finish signal")
	_check(game.profile == settled and _files(game.profile_path) == settled_bytes, "trial death restores profile and leaves disk untouched")
	_check(game.start_demo("CH03"), "third hero trial starts")
	game.set_setting("fullscreen", true)
	game.finish_run("abandoned")
	_check(game.profile == settled and _files(game.profile_path) == settled_bytes, "abandon restores settings and permanent profile")
	_check(game.start_demo("CH01"), "trial may be restarted")
	game.reload_profile()
	_check(game.run == null and game.profile == settled and _files(game.profile_path) == settled_bytes, "explicit reload discards trial without settling permanent run")
	game.free()

func _new_player_trials() -> void:
	var game := _game("new-player")
	var original: Dictionary = game.profile.duplicate(true)
	_check(not game.has_profile and not FileAccess.file_exists(AssetCatalog.resolve(game.profile_path)), "new player starts with no save")
	for hero: String in ProfileStore.HERO_IDS:
		_check(game.start_demo(hero), "new player can try " + hero)
		_check(game.run.demo and game.run.level == 8 and game.run.resource == game.run.stats.resource_max, "each new-player hero has full skills and resource")
		game.set_setting("music_volume", 0.0)
		game.add_gold(30)
		game.finish_run("abandoned")
		_check(game.profile == original and not game.has_profile and _files(game.profile_path).is_empty(), "new-player trial creates no profile and leaves no progression")
	_check(not game.start_demo("unknown") and not game.start_demo("CH01", -1) and not game.start_demo("CH01", 5), "invalid trial selections reject before mutation")
	_check(game.run == null and game.profile == original and _files(game.profile_path).is_empty(), "invalid trials leave original state unchanged")
	game.set_setting("sfx_volume", 0.3)
	var preferences: Dictionary = game.profile.duplicate(true)
	var preferences_bytes: Dictionary = _files(game.profile_path)
	_check(not game.has_profile and game.start_demo("CH02"), "settings-only user can enter trial without creating a campaign")
	game.set_setting("sfx_volume", 0.8)
	game.damage_player(100000.0)
	_check(not game.has_profile and game.profile == preferences and _files(game.profile_path) == preferences_bytes, "settings-only file and initialization flag survive trial unchanged")
	_check(game.new_profile() and game.start_run(), "normal new profile can begin after trials")
	_check(game.run.level == 1 and not game.run.demo, "normal new player retains progressive level-one unlocks")
	game.finish_run("abandoned")
	game.free()

func _settings_compatibility() -> void:
	var path := directory + "/old-settings.json"
	var old_profile := ProfileStore.fresh_profile()
	for key: String in ProfileStore.VOLUME_DEFAULTS: old_profile.settings.erase(key)
	var store := ProfileStore.new(path)
	_check(store.save_document(old_profile), "old settings without volume fields remain valid")
	var bytes := _files(path)
	var loaded: Dictionary = store.load_document()
	for key: String in ProfileStore.VOLUME_DEFAULTS:
		_check(loaded.profile.settings[key] == ProfileStore.VOLUME_DEFAULTS[key], "old settings receive in-memory default for " + key)
	_check(_files(path) == bytes, "default normalization does not rewrite old profile bytes")
	var game := Controller.new()
	game.profile_path = path
	root.add_child(game)
	for key: String in ProfileStore.VOLUME_DEFAULTS:
		game.set_setting(key, 0.23)
		_check(is_equal_approx(float(game.profile.settings[key]), 0.23), "valid volume persists for " + key)
		for bad: Variant in [-0.1, 1.01, NAN, INF, "0.5", true]:
			game.set_setting(key, bad)
			_check(is_equal_approx(float(game.profile.settings[key]), 0.23), "out-of-range/non-finite/wrong-type volume rejected")
	game.reload_profile()
	for key: String in ProfileStore.VOLUME_DEFAULTS:
		_check(is_equal_approx(float(game.profile.settings[key]), 0.23), "volume survives normal reload")
	var document: Dictionary = store.load_document()
	for key: String in ProfileStore.VOLUME_DEFAULTS:
		var invalid := document.duplicate(true)
		invalid.profile.settings[key] = 1.1
		_check(not ProfileStore._valid_document(invalid), "save validation rejects invalid " + key)
	game.free()
