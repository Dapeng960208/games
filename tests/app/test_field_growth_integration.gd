extends SceneTree
## Real profile/expedition transactions. Runtime snapshots are explicit safe
## boundary fixtures; no save editing is used to earn XP, kills, or money.
const Controller = preload("res://scripts/app/game.gd")
const Snapshot = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Expedition = preload("res://scripts/domain/expedition/expedition_state.gd")
var abilities_script: Script
var checks: int = 0
var failures: int = 0
var directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FIELD GROWTH INTEGRATION FAIL: " + label)

func _game(name: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + name + ".json"
	root.add_child(game)
	return game

func _files(path: String) -> Dictionary:
	var result: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(AssetCatalog.resolve(path + suffix)): result[suffix] = FileAccess.get_file_as_bytes(AssetCatalog.resolve(path + suffix))
	return result

func _same_json(left: Variant, right: Variant) -> bool:
	# Disk JSON normalizes integer tokens to floats and dictionary keys to String.
	# Compare full persisted values after the same codec, not runtime key types.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(AssetCatalog.resolve(path), FileAccess.WRITE)
	_check(file != null, "isolated test fixture writable")
	if file:
		file.store_string(content)
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

func _start(game: Node, hero: String = "CH01", fresh: bool = true) -> bool:
	if fresh:
		_check(game.new_profile(), "new isolated profile")
	_check(game.select_hero(hero), "select actual hero " + hero)
	var started: bool = game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":960208})
	_check(started, "begin actual expedition")
	if not started: return false
	_check(Expedition.runtime_valid(_runtime(game), hero, game.run.stats), "boundary fixture validates against actual run")
	_check(game.save_expedition_checkpoint(_runtime(game)), "save real safe entrance checkpoint")
	return _advance(game)

func _advance(game: Node) -> bool:
	for offer: Dictionary in game.expedition_snapshot().relic_offers:
		_check(game.choose_run_relic(offer.offer_id, "skip", "", _runtime(game)), "resolve real relic offer")
	var snapshot: Dictionary = game.expedition_snapshot()
	var next: Dictionary = snapshot.next_node
	if next.is_empty(): return false
	_check(game.choose_expedition_node(int(next.node_index), str(next.room_id)), "lock actual route choice")
	var advanced: bool = game.advance_expedition_node(_runtime(game), snapshot.checkpoint_id)
	_check(advanced, "commit actual next-room entry")
	return advanced

func _kills(game: Node, amount: int) -> void:
	var before: int = game.run.kills
	for unused in range(amount): game.record_kill()
	_check(game.run.kills == before + amount, "kill count advanced through production API")

func _die(game: Node) -> Dictionary:
	game.damage_player(game.run.hp + game.run.shield + 1.0, {"damage_type":"true"})
	return game.last_result

func _run() -> void:
	# The SceneTree script is parsed before autoload names are registered.
	# Load the real combat API after initialization, as first_run_progression does.
	abilities_script = load(AssetCatalog.resolve("res://scripts/gameplay/characters/hero_abilities.gd"))
	_check(abilities_script != null and abilities_script.can_instantiate(), "real hero ability script loads after autoload initialization")
	directory = "user://field_growth_integration_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_atomic_defeat()
	for hero: String in ProfileStore.HERO_IDS: _persistent_skill_growth(hero)
	_completed_room_kills()
	_no_death_award()
	_demo_isolation()
	_legacy_history()
	_xp_cap()
	print("FIELD GROWTH INTEGRATION TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _atomic_defeat() -> void:
	var game := _game("atomic")
	if not _start(game): game.free(); return
	_kills(game, 12)
	_check(game.add_gold(101), "collect unfinished-room gold")
	_check(game.grant_hero_xp(30, "unfinished-room") and game.complete_hero_tutorial(), "stage room and tutorial XP through real APIs")
	_check(game.profile.hero_xp.CH01 == 0, "uncompleted objectives remain unbanked")
	var profile_before: Dictionary = game.profile.duplicate(true)
	var bytes_before: Dictionary = _files(game.profile_path)
	var blocker: String = directory + "/atomic-write-blocker"
	_write(blocker, "not a directory")
	game._store.path = blocker + "/profile.json"
	var notifications := {"finished":0,"failed":0}
	game.run_finished.connect(func(_result: Dictionary) -> void: notifications.finished += 1)
	game.settlement_failed.connect(func(_outcome: String) -> void: notifications.failed += 1)
	_die(game)
	_check(game.run != null and game.run.hp == 0.0 and not game.last_error.is_empty(), "failed death settlement remains pending")
	_check(game.profile == profile_before and _files(game.profile_path) == bytes_before, "failed save grants no field XP, money, tutorial, or disk changes")
	_check(game.finish_run("death").is_empty() and game.profile == profile_before, "second failed retry does not accumulate field XP")
	_check(not game.add_gold(1), "pending settlement rejects further income")
	_check(notifications.finished == 0 and notifications.failed == 2, "only failure events fire until durable settlement")
	game._store.path = game.profile_path
	var result: Dictionary = game.finish_run("extracted")
	_check(result.outcome == "death" and result.rules_version == 2, "retry preserves original defeat and selects v2 settlement")
	_check(result.field_xp_gained == 18 and result.hero_xp_gained == 18, "twelve unfinished kills award only capped eighteen field XP")
	_check(result.retained == 50 and result.lost == 51 and result.wallet_before == 0 and result.wallet_after == 50, "v2 death atomically retains floor half of 101 gold")
	_check(game.profile.hero_xp.CH01 == 18 and not "CH01" in game.profile.tutorial_completed, "field practice excludes staged room and tutorial awards")
	_check(notifications.finished == 1 and game.profile.total_runs == 1, "successful retry finishes exactly once")
	_check(game.finish_run("death") == result and game.profile.hero_xp.CH01 == 18, "duplicate finish cannot grant XP twice")
	game.reload_profile()
	_check(game.run == null and game.profile.hero_xp.CH01 == 18 and game.profile.permanent_gold == 50 and game.profile.total_runs == 1, "reload keeps the whole settled transaction")
	_check(_same_json(game.last_result, result) and _same_json(game.finish_run("death"), result), "reloaded result remains an idempotent receipt")
	game.free()

func _persistent_skill_growth(hero: String) -> void:
	var game := _game("skill-" + hero)
	if not _start(game, hero): game.free(); return
	var before: Dictionary = abilities_script.preview_spec(hero, game.run.level, game.run.stats, "secondary")
	_check(game.run.level == 1 and game.run.level < int(before.unlock), hero + " initially cannot use secondary")
	_kills(game, 9)
	var first: Dictionary = _die(game)
	_check(first.field_xp_gained == 18 and game.hero_level(hero) == 1, hero + " first defeat has visible but sub-level progress")
	game.reload_profile()
	if not _start(game, hero, false): game.free(); return
	_check(game.run.level == 1 and int(game.profile.hero_xp[hero]) == 18, hero + " next run inherits exact field XP")
	_kills(game, 6)
	var second: Dictionary = _die(game)
	_check(second.field_xp_gained == 12 and int(game.profile.hero_xp[hero]) == 30 and game.hero_level(hero) == 2, hero + " six more kills cross real level-two threshold")
	for other: String in ProfileStore.HERO_IDS:
		if other != hero: _check(int(game.profile.hero_xp[other]) == 0, hero + " never awards another hero XP")
	game.reload_profile()
	if not _start(game, hero, false): game.free(); return
	var secondary: Dictionary = abilities_script.preview_spec(hero, game.run.level, game.run.stats, "secondary")
	var f: Dictionary = abilities_script.preview_spec(hero, game.run.level, game.run.stats, "f")
	_check(game.run.level == 2 and game.run.level >= int(secondary.unlock), hero + " next departure unlocks the actual secondary specification")
	_check(game.run.level < int(f.unlock), hero + " higher skill remains gated by actual XP")
	var no_kills: Dictionary = _die(game)
	_check(no_kills.field_xp_gained == 0 and int(game.profile.hero_xp[hero]) == 30, hero + " zero kills never mint field XP")
	game.free()

func _completed_room_kills() -> void:
	var game := _game("completed-kills")
	if not _start(game): game.free(); return
	_kills(game, 12)
	_check(game.commit_expedition_completion("first-clear", _runtime(game), {"gold":12,"xp":30,"mastery":0}), "complete first room with actual committed XP")
	_check(game.save_expedition_checkpoint(_runtime(game)), "save cleared checkpoint with committed kills")
	game.reload_profile()
	_check(game.run.kills == 12 and game.profile.hero_xp.CH01 == 30 and game.run.expedition.phase == "cleared", "reload retains completed-room kills and XP")
	if not _advance(game): game.free(); return
	_check(game.run.expedition.room_entry_kills == 12, "next room establishes committed kill baseline")
	game.reload_profile()
	_check(game.run.expedition.room_entry_kills == 12, "entry baseline remains durable after reload")
	_kills(game, 3)
	var result: Dictionary = _die(game)
	_check(result.kills == 15 and result.field_xp_gained == 6, "only three current-room kills earn field XP")
	_check(result.hero_xp_gained == 36 and game.profile.hero_xp.CH01 == 36, "completed XP and fresh field XP counted exactly once")
	game.reload_profile()
	_check(game.profile.hero_xp.CH01 == 36 and game.profile.total_runs == 1, "completed and field XP survive settlement reload without duplication")
	game.free()

func _no_death_award() -> void:
	var game := _game("abandoned")
	if not _start(game): game.free(); return
	_kills(game, 10)
	game.add_gold(101)
	var result: Dictionary = game.finish_run("abandoned")
	_check(result.rules_version == 2 and result.field_xp_gained == 0 and game.profile.hero_xp.CH01 == 0, "voluntary abandon awards no field practice")
	_check(result.retained == 20 and game.profile.permanent_gold == 20, "v2 abandon still retains floor twenty percent")
	game.free()
	game = _game("cleared-death")
	if not _start(game): game.free(); return
	_kills(game, 10)
	_check(game.commit_expedition_completion("clear-before-death", _runtime(game), {"xp":30,"mastery":0}), "clear before administrative death fixture")
	result = _die(game)
	_check(result.field_xp_gained == 0 and game.profile.hero_xp.CH01 == 30, "cleared-node kills never receive a second XP award")
	game.free()

func _demo_isolation() -> void:
	var game := _game("demo")
	_check(game.new_profile() and game.start_run(), "create actual saved campaign before trial")
	_check(game.add_gold(17) and game.grant_hero_xp(11, "saved-xp"), "earn real saved progress")
	game.finish_run("extracted")
	var before: Dictionary = game.profile.duplicate(true)
	var bytes: Dictionary = _files(game.profile_path)
	_check(game.start_demo("CH03"), "start actual isolated full-skill trial")
	if not _advance(game): game.free(); return
	_kills(game, 12)
	game.add_gold(101)
	var result: Dictionary = _die(game)
	_check(result.demo and result.field_xp_gained == 0 and result.hero_xp_gained == 0 and result.retained == 0, "trial defeat grants no permanent field XP or gold")
	_check(game.profile == before and _files(game.profile_path) == bytes, "trial leaves primary, backup, and temporary save bytes unchanged")
	game.reload_profile()
	_check(_same_json(game.profile, before) and _files(game.profile_path) == bytes, "reload after trial still preserves exact real campaign")
	game.free()

func _legacy_history() -> void:
	# Author an authentic schema-one historical fixture, as migration tests do.
	# It is validated before writing; modern earned saves are never rewritten.
	var old: Dictionary = {"schema_version":1,"revision":8,"active_run":null,"profile":{
		"permanent_gold":20,"discoveries":[],"total_runs":1,
		"last_result":{"run_id":"historical-death","outcome":"death","collected":101,"retained":20,"lost":81,
			"permanent_gold":20,"discoveries":[],"kills":12,"shots":13,"elapsed":20.0},
		"settings":{"language":"zh_CN","reduced_fx":false,"fullscreen":false}}}
	_check(ProfileStore._valid_document(old), "genuine v1 death history validates under original twenty-percent rule")
	var original: String = JSON.stringify(old, "\t")
	_write(directory + "/legacy.json", original)
	var game := _game("legacy")
	_check(game.has_profile and game.last_result.rules_version == 1 and game.last_result.retained == 20, "historical v1 death is not revalued to fifty percent")
	_check(game.profile.permanent_gold == 20 and game.profile.hero_xp.CH01 == 0, "migration does not retroactively award field XP")
	_check(FileAccess.get_file_as_string(AssetCatalog.resolve(game.profile_path + ".v1.bak")) == original, "original v1 bytes remain preserved")
	var migrated_history: Dictionary = game.last_result.duplicate(true)
	game.reload_profile()
	# Settings may gain volume defaults on the next read; the economic history
	# itself must stay value-equivalent after the JSON numeric normalization.
	_check(_same_json(game.last_result, migrated_history) and game.last_result.rules_version == 1, "migrated history remains unchanged on reload")
	_check(game.profile.permanent_gold == 20 and game.profile.total_runs == 1 and game.profile.hero_xp.CH01 == 0, "history reload changes no wallet, XP, or settled-run count")
	if not _start(game, "CH01", false): game.free(); return
	_kills(game, 1)
	game.add_gold(101)
	var current: Dictionary = _die(game)
	_check(current.rules_version == 2 and current.retained == 50 and current.field_xp_gained == 2, "new run on migrated profile uses current rules")
	_check(game.profile.permanent_gold == 70 and game.profile.hero_xp.CH01 == 2 and game.profile.total_runs == 2, "new settlement adds only new income to historical wallet")
	game.free()

func _xp_cap() -> void:
	var game := _game("cap")
	_check(game.new_profile() and game.start_run(), "create XP cap earning run")
	_check(game.grant_hero_xp(3595, "earned-before-cap"), "earn near-cap XP through production progression")
	game.finish_run("extracted")
	if not _start(game, "CH01", false): game.free(); return
	_kills(game, 12)
	var result: Dictionary = _die(game)
	_check(result.field_xp_gained == 5 and game.profile.hero_xp.CH01 == 3600, "field practice respects remaining XP capacity")
	game.reload_profile()
	_check(game.profile.hero_xp.CH01 == 3600 and game.hero_level() == 20, "capped progression remains loadable")
	game.free()
