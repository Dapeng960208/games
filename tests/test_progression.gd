extends SceneTree
## Isolated behavioral acceptance: migration, durable purchases, XP and stat snapshots.

const Controller = preload("res://scripts/core/run_controller.gd")
var failures: int = 0
var checks: int = 0
var directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PROGRESSION FAIL: " + label)

func _game(filename: String) -> Node:
	var game := Controller.new()
	game.profile_path = directory + "/" + filename
	root.add_child(game)
	return game

func _write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "fixture writable")
	if file != null:
		file.store_string(data if data is String else JSON.stringify(data))
		file.close()

func _legacy() -> Dictionary:
	return {"schema_version": 1, "revision": 8, "active_run": null, "profile": {
		"permanent_gold": 100, "discoveries": ["split"], "total_runs": 1,
		"last_result": {"run_id": "old-settled", "outcome": "extracted", "collected": 100,
			"retained": 100, "lost": 0, "permanent_gold": 100, "discoveries": ["split"],
			"kills": 2, "shots": 15, "elapsed": 20.0},
		"settings": {"language": "en", "reduced_fx": true, "fullscreen": false}}}

func _earn(game: Node, gold: int) -> void:
	_check(game.start_run(), "earn fixture starts a real run")
	_check(game.add_gold(gold), "earn fixture collects gold")
	_check(not game.finish_run("extracted").is_empty(), "earn fixture extracts")

func _run() -> void:
	directory = "res://tools/godot/test-runs/progression_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	_migration()
	_transactions()
	_growth_and_damage()
	_branches()
	_settings_preferences()
	print("PROGRESSION TESTS: ", checks - failures, "/", checks, " passed; fixtures=", ProjectSettings.globalize_path(directory))
	quit(1 if failures else 0)

func _migration() -> void:
	var original := _legacy()
	var path := directory + "/v1.json"
	var original_text := JSON.stringify(original, "\t")
	_write(path, original_text)
	var game := _game("v1.json")
	_check(game.has_profile and game.profile.permanent_gold == 100, "v1 wallet preserved 1:1")
	_check(game.profile.settings.language == "en" and game.profile.settings.reduced_fx, "v1 settings preserved")
	_check(game.profile.equipment.size() == 6 and game.profile.loadout.size() == 6, "starter equipment exactly six")
	_check(game.profile.migration_id == "profile_v1_to_v2", "migration marker saved")
	_check(game.last_result.rules_version == 1 and game.last_result.wallet_before == 0, "legacy historical rule frozen")
	_check(FileAccess.get_file_as_string(path + ".v1.bak") == original_text, "v1 original bytes preserved")
	game.reload_profile()
	game.reload_profile()
	_check(game.profile.permanent_gold == 100 and game.profile.equipment.size() == 6, "migration does not pay or grant twice")
	_check(game.buy_equipment("EQ02", "post-migration-buy"), "migrated wallet can purchase")
	_check(game.profile.permanent_gold == 0 and game.last_result.permanent_gold == 100, "purchase does not rewrite settlement history")
	game.reload_profile()
	_check(game.profile.permanent_gold == 0 and game.last_result.permanent_gold == 100, "stale result wallet is valid in v2")
	game.free()
	var active := _legacy()
	active.active_run = {"id": "old-active", "gold": 119, "discoveries": ["arc"], "shots": 7, "kills": 3, "elapsed": 9.5}
	_write(directory + "/v1-active.json", active)
	game = _game("v1-active.json")
	_check(game.run == null and game.profile.permanent_gold == 123 and game.profile.total_runs == 2, "active v1 abandoned atomically once")
	_check(game.last_result.outcome == "abandoned" and game.last_result.retained == 23 and game.last_result.lost == 96, "old rule retains floor 20 percent")
	_check(game.profile.discoveries == ["split", "arc"], "migration merges only new discoveries")
	game.reload_profile()
	_check(game.profile.permanent_gold == 123 and game.profile.total_runs == 2, "active migration restart cannot repay")
	game.free()
	var invalid := _legacy()
	invalid.profile.permanent_gold = 99
	_check(not ProfileStore._valid_document(invalid), "strict v1 result-wallet contradiction rejected before migration")
	_write(directory + "/v1-invalid.json", invalid)
	game = _game("v1-invalid.json")
	_check(not game.has_profile and not game.new_profile(), "invalid v1 cannot migrate or clobber")
	_check(not FileAccess.file_exists(directory + "/v1-invalid.json.v1.bak"), "invalid v1 never becomes migration backup")
	game.free()
	var retry_path := directory + "/v1-retry.json"
	_write(retry_path, original_text)
	DirAccess.make_dir_absolute(retry_path + ".tmp")
	var retry_store := ProfileStore.new(retry_path)
	_check(retry_store.load_document().is_empty() and retry_store.unresolved_error and not retry_store.has_profile, "failed migration is not acknowledged as a new profile")
	_check(FileAccess.get_file_as_string(retry_path) == original_text, "failed migration leaves old primary bytes intact")
	_check(FileAccess.get_file_as_string(retry_path + ".v1.bak") == original_text, "failed migration preserves legacy backup")
	DirAccess.remove_absolute(retry_path + ".tmp")
	retry_store = ProfileStore.new(retry_path)
	_check(retry_store.load_document().get("schema_version") == ProfileStore.SCHEMA_VERSION, "migration can retry to the current schema after storage repair")
	_check(FileAccess.get_file_as_string(retry_path + ".v1.bak") == original_text, "migration retry never replaces original backup")
	# Whole-document selection across versions: newer v2 beats valid v1 primary.
	var mixed := ProfileStore.new(directory + "/mixed.json")
	var newer := {"schema_version": 2, "revision": 9, "profile": ProfileStore.fresh_profile(), "active_run": null}
	newer.profile.permanent_gold = 37
	_write(directory + "/mixed.json", _legacy())
	_write(directory + "/mixed.json.tmp", newer)
	var selected := mixed.load_document()
	_check(selected.schema_version == 2 and selected.profile.permanent_gold == 37, "highest revision selects whole v2 over v1")
	_check(selected.profile.discoveries.is_empty() and selected.profile.migration_id == "new_v2", "mixed candidates never merge old fields")
	var malformed := _legacy()
	for bad: Variant in [-1, 1.5, "100", 1e20, INF, NAN]:
		malformed.profile.permanent_gold = bad
		_check(not ProfileStore._valid_document(malformed), "invalid v1 amount cannot be migrated")

func _transactions() -> void:
	var game := _game("transactions.json")
	_check(game.new_profile(), "fresh progression profile")
	_check(not game.buy_equipment("EQ02") and not game.equip_item("EQ02"), "cannot buy unaffordable or equip unowned")
	_earn(game, 5000)
	_check(not game.buy_equipment("missing") and not game.buy_equipment("EQ04"), "unknown and boss-locked catalog rejected")
	_check(game.buy_equipment("EQ02", "buy-A"), "purchase catalog item")
	_check(game.profile.permanent_gold == 4900 and game.profile.equipment.has("EQ02"), "one debit and one owned item")
	_check(game.buy_equipment("EQ02", "buy-A") and game.profile.permanent_gold == 4900, "same purchase idempotent")
	_check(not game.buy_equipment("EQ12", "buy-A") and not game.buy_equipment("EQ02", "buy-B"), "transaction collision and duplicate ownership reject")
	game.reload_profile()
	_check(game.buy_equipment("EQ02", "buy-A") and game.profile.permanent_gold == 4900, "purchase retry after restart stays idempotent")
	_check(game.equip_item("EQ02") and game.profile.loadout.weapon == "EQ02", "equip owned item in catalog slot")
	var before_preview: Dictionary = game.profile.duplicate(true)
	_check(not game.preview_stats("EQ12").is_empty() and game.profile == before_preview, "shop preview cannot mutate inventory")
	_check(game.upgrade_equipment("EQ02", "upgrade-A"), "upgrade deducts catalog step price")
	_check(game.equipment_level("EQ02") == 1 and game.profile.permanent_gold == 4840, "upgrade plus one costs 60")
	_check(game.upgrade_equipment("EQ02", "upgrade-A") and game.profile.permanent_gold == 4840, "same upgrade never reapplies")
	var before_upgrade_preview: Dictionary = game.profile.duplicate(true)
	_check(not game.preview_upgrade_stats("EQ02").is_empty() and game.profile == before_upgrade_preview, "upgrade preview cannot charge or level inventory")
	game.reload_profile()
	_check(game.upgrade_equipment("EQ02", "upgrade-A") and game.equipment_level("EQ02") == 1, "upgrade idempotent after restart")
	for level: int in range(2, 6):
		_check(game.upgrade_equipment("EQ02", "upgrade-" + str(level)), "upgrade to +" + str(level))
	_check(game.equipment_level("EQ02") == 5 and game.upgrade_cost("EQ02") == 0, "upgrade cap has no price")
	_check(not game.upgrade_equipment("EQ02", "upgrade-six") and not game.upgrade_equipment("EQ12"), "reject overcap and unowned upgrade")
	# Deterministic storage failure: all mutations stay unapplied until a successful retry.
	var blocker := directory + "/blocker"
	_write(blocker, "not a directory")
	var before: Dictionary = game.profile.duplicate(true)
	game._store.path = blocker + "/profile.json"
	_check(not game.buy_equipment("EQ12", "failed-buy") and game.profile == before, "failed purchase rolls back wallet/inventory/ledger")
	_check(not game.buy_equipment("missing") and game.last_error.is_empty(), "normal business rejection clears an older storage error")
	_check(not game.upgrade_equipment("EQ11", "failed-upgrade") and game.profile == before, "failed upgrade rolls back all fields")
	game._store.path = game.profile_path
	_check(game.buy_equipment("EQ12", "failed-buy"), "same failed transaction can retry")
	var balance: int = game.profile.permanent_gold
	_check(game.buy_equipment("EQ12", "failed-buy") and game.profile.permanent_gold == balance, "repaired transaction pays once")
	# Simulate a crash after a durable whole purchase intent, before primary rename.
	var acknowledged: Dictionary = game._store.load_document()
	var intent: Dictionary = acknowledged.duplicate(true)
	intent.revision = int(intent.revision) + 1
	intent.profile.permanent_gold = int(intent.profile.permanent_gold) - 100
	intent.profile.equipment.EQ22 = {"level": 0}
	intent.profile.applied_transactions["flushed-intent"] = {"kind": "purchase", "item": "EQ22", "price": 100, "level": 0}
	_write(game.profile_path + ".tmp", intent)
	game.reload_profile()
	_check(game.profile.equipment.has("EQ22") and game.profile.permanent_gold == balance - 100, "flushed purchase intent recovers inventory and debit together")
	_check(game.buy_equipment("EQ22", "flushed-intent") and game.profile.permanent_gold == balance - 100, "recovered intent retry cannot debit again")
	_check(game.select_hero("CH02") and game.hero_level() == 1, "three heroes available immediately")
	_check(game.start_run(), "snapshot run begins")
	_check(not game.select_hero("CH03") and not game.equip_item("EQ01") and not game.buy_equipment("EQ22"), "camp mutations disallowed during expedition")
	_check(game.record_boss_defeat("BO01"), "boss recorded in run receipt")
	game.finish_run("death")
	_check(not "BO01" in game.profile.bosses and not game.buy_equipment("EQ04"), "failed boss run does not unlock workshop")
	game.start_run()
	game.record_boss_defeat("BO01")
	game.finish_run("extracted")
	_check("BO01" in game.profile.bosses and game.buy_equipment("EQ04"), "successful boss settlement unlocks catalog")
	game.free()

func _growth_and_damage() -> void:
	var game := _game("growth.json")
	game.new_profile()
	game.start_run()
	_check(game.run.hero_id == "CH01" and game.run.hp == game.run.stats.max_hp and game.run.hp >= 150.0, "new run snapshots actual hero stats")
	game.run.hp = 37.0
	game.run.resource = 11.0
	_check(game.grant_hero_xp(30, "room:1") and game.hero_level() == 2, "completed room XP unlocks level two")
	_check(game.run.hp == 37.0 and game.run.resource == 11.0, "level gain preserves absolute hp/resource")
	_check(game.grant_hero_xp(30, "room:1") and game.profile.hero_xp.CH01 == 30, "room event only grants once")
	_check(game.hero_level("CH02") == 1 and game.hero_level("CH03") == 1, "hero XP isolated")
	var blocker := directory + "/xp-blocker"
	_write(blocker, "not a directory")
	game._store.path = blocker + "/profile.json"
	_check(not game.grant_hero_xp(30, "room:2") and game.profile.hero_xp.CH01 == 30 \
		and not "room:2" in game.run.completed_reward_ids, "failed XP award keeps reward retryable")
	game._store.path = game.profile_path
	_check(game.grant_hero_xp(30, "room:2") and game.profile.hero_xp.CH01 == 60, "XP award retries atomically")
	game.reload_profile()
	_check(game.run == null and game.profile.hero_xp.CH01 == 60, "interrupted run abandons but committed XP survives")
	game.reload_profile()
	_check(game.profile.hero_xp.CH01 == 60 and not game.grant_hero_xp(30, "room:2"), "recovery cannot replay XP without active run")
	game.start_run()
	game.grant_hero_xp(3600, "mastery")
	_check(game.hero_level() == 20 and game.profile.hero_xp.CH01 == 3600, "XP clamps at permanent level twenty")
	_check(not game.grant_hero_xp(-1, "bad") and not game.grant_hero_xp(1, ""), "invalid reward data rejected")
	game.run.hp = 100.0
	game.run.stats.armor = 100.0
	game.run.stats.equipment_damage_reduction = 0.35
	game.run.shield = 10.0
	var dealt: float = game.damage_player(100.0)
	_check(is_equal_approx(dealt, 22.5) and is_equal_approx(game.run.hp, 77.5) and game.run.shield == 0.0, "physical armor then generic equipment reduction then shield and HP")
	game.run.resource = 0.0
	_check(not game.try_spend_resource(1.0) and not game.try_spend_resource(-1.0), "resource insufficient and negative cost rejected")
	game.restore_resource(9999.0)
	_check(game.run.resource == game.run.stats.resource_max, "resource restore clamped to class pool")
	_check(game.try_spend_resource(10.0), "resource spend succeeds exactly once per request")
	var hp_before: float = game.run.hp
	game.damage_player(NAN)
	game.restore_resource(INF)
	game.add_shield(INF)
	_check(game.run.hp == hp_before and is_finite(game.run.resource) and is_finite(game.run.shield), "nonfinite battle mutations rejected")
	game.finish_run("extracted")
	game.select_hero("CH02")
	game.start_run()
	game.run.hp = 30.0
	game.run.resource = 5.0
	_check(game.complete_hero_tutorial() and game.hero_level("CH02") == 2, "tutorial grants 30 XP for its hero")
	_check(game.run.hp == 30.0 and game.run.resource == 5.0, "tutorial level cannot refill bars")
	_check(not game.complete_hero_tutorial() and game.profile.hero_xp.CH02 == 30, "tutorial duplicate does not grant again")
	game.reload_profile()
	game.start_run()
	_check(not game.complete_hero_tutorial() and game.profile.hero_xp.CH02 == 30, "tutorial persists across restart and fresh run")
	game.finish_run("extracted")
	game.select_hero("CH03")
	game.start_run()
	_check(game.complete_hero_tutorial() and game.profile.hero_xp.CH03 == 30, "another hero owns its own tutorial reward")
	game.finish_run("extracted")
	game.free()

func _branches() -> void:
	var game := _game("branches.json")
	_check(game.new_profile(), "branch fixture profile created")
	_check(game.hero_branches() == {"q": "", "ultimate": ""}, "fresh hero has explicit empty branch choices")
	_check(not game.set_hero_branch("q", "A") and not game.set_hero_branch("ultimate", "B"), "locked branch levels reject selection")
	_check(not game.set_hero_branch("invalid", "A") and not game.set_hero_branch("q", "C") \
		and not game.set_hero_branch("q", "A", "missing"), "unknown branch slot choice and hero reject")
	game.start_run()
	game.grant_hero_xp(3060, "branch-level-18")
	_check(game.hero_level() == 18 and not game.set_hero_branch("q", "A"), "unlock during expedition still requires return to camp")
	game.finish_run("extracted")
	var wallet: int = game.profile.permanent_gold
	_check(game.set_hero_branch("q", "A") and not game.set_hero_branch("ultimate", "B"), "level eighteen unlocks q but not ultimate branch")
	_check(game.set_hero_branch("q", "B") and game.set_hero_branch("q", "") and game.set_hero_branch("q", "A"), "camp freely switches and clears unlocked branch")
	_check(game.profile.permanent_gold == wallet, "branch selection and clearing never spend gold")
	var choices: Dictionary = game.hero_branches()
	choices.q = "B"
	_check(game.hero_branches().q == "A", "branch accessor returns a copy")
	game.reload_profile()
	_check(game.hero_branches().q == "A", "branch choice survives disk reload")
	game.start_run()
	_check(game.run.stats.branches == {"q": "A", "ultimate": ""}, "departure snapshots selected branches")
	_check(not game.set_hero_branch("q", "B") and not game.set_hero_branch("q", ""), "active run blocks branch changes and clearing")
	game.run.hp = 33.0
	game.run.resource = 12.0
	game.grant_hero_xp(540, "branch-level-20")
	_check(game.run.level == 20 and game.run.stats.branches == {"q": "A", "ultimate": ""}, "level twenty refresh keeps departure branch snapshot")
	_check(game.run.hp == 33.0 and game.run.resource == 12.0, "branch-bearing stat refresh still preserves bars")
	_check(game.complete_hero_tutorial() and game.run.stats.branches.q == "A", "tutorial stat refresh keeps departure branch snapshot")
	game.finish_run("extracted")
	_check(game.set_hero_branch("ultimate", "B") and game.selected_stats().branches.ultimate == "B", "level twenty ultimate choice enters camp resolved stats")
	_check(game.select_hero("CH02") and game.hero_branches() == {"q": "", "ultimate": ""} \
		and not game.set_hero_branch("q", "A"), "second hero branch choices and unlock levels remain independent")
	game.start_run()
	game.grant_hero_xp(3600, "second-hero-mastery")
	game.finish_run("extracted")
	_check(game.set_hero_branch("q", "B") and game.set_hero_branch("ultimate", "A"), "second mastered hero chooses different branches")
	_check(game.hero_branches("CH01") == {"q": "A", "ultimate": "B"}, "second hero changes do not alter first hero choices")
	var before: Dictionary = game.profile.duplicate(true)
	var blocker := directory + "/branch-blocker"
	_write(blocker, "not a directory")
	game._store.path = blocker + "/profile.json"
	_check(not game.set_hero_branch("q", "A") and game.profile == before, "failed branch save leaves choice and wallet unchanged")
	game._store.path = game.profile_path
	_check(game.set_hero_branch("q", "A"), "failed branch choice retries after storage repair")
	game.reload_profile()
	_check(game.hero_branches("CH01").ultimate == "B" and game.hero_branches("CH02").q == "A", "all hero choices survive shared profile reload")
	_check(game.profile.permanent_gold == wallet, "all hero branch changes remained free")
	game.free()
	# Schema 2 documents written before branches existed remain valid and upgrade atomically.
	var early := {"schema_version": 2, "revision": 20, "profile": ProfileStore.fresh_profile(), "active_run": null}
	early.profile.erase("branches")
	early.profile.permanent_gold = 71
	var receipt := RunState.new()
	receipt.id = "early-v2-active"
	receipt.gold = 19
	early.active_run = receipt.receipt()
	_check(ProfileStore._valid_document(early), "early schema two without branch field is accepted")
	var path := directory + "/early-v2.json"
	_write(path, early)
	var store := ProfileStore.new(path)
	var normalized := store.load_document()
	_check(normalized.profile.branches.CH01 == {"q": "", "ultimate": ""} \
		and normalized.revision == 21 and normalized.profile.permanent_gold == 71 \
		and normalized.active_run.id == "early-v2-active", "normalization commits defaults with original assets and active receipt")
	_check(store.load_document().revision == 21, "normalized schema two is not rewritten on every load")
	game = _game("early-v2.json")
	_check(game.run == null and game.profile.permanent_gold == 74 and game.profile.total_runs == 1, "normalized active receipt still abandons exactly once")
	game.reload_profile()
	_check(game.profile.permanent_gold == 74 and game.profile.total_runs == 1, "normalized active receipt cannot repay after restart")
	game.free()
	var invalid: Dictionary = normalized.duplicate(true)
	invalid.profile.branches.CH01.q = "A"
	_check(not ProfileStore._valid_document(invalid), "persisted locked-level choice is rejected")
	invalid.profile.branches.CH01.q = "unknown"
	_check(not ProfileStore._valid_document(invalid), "persisted unknown choice is rejected")
	var retry_path := directory + "/early-v2-retry.json"
	var original_text := JSON.stringify(early)
	_write(retry_path, original_text)
	DirAccess.make_dir_absolute(retry_path + ".tmp")
	store = ProfileStore.new(retry_path)
	_check(store.load_document().is_empty() and store.unresolved_error \
		and FileAccess.get_file_as_string(retry_path) == original_text, "failed normalization preserves early schema two bytes")
	DirAccess.remove_absolute(retry_path + ".tmp")
	store = ProfileStore.new(retry_path)
	_check(store.load_document().profile.has("branches"), "normalization safely retries after storage repair")

func _settings_preferences() -> void:
	var game := _game("settings-only.json")
	_check(not game.has_profile, "first launch has no initialized campaign")
	game.set_setting("language", "en")
	_check(game.profile.settings.language == "en" and not game.has_profile and game.last_error.is_empty(), "language preference does not create a campaign")
	game.set_setting("reduced_fx", true)
	game.set_setting("fullscreen", true)
	game.reload_profile()
	_check(not game.has_profile and not game.start_run(), "settings-only restart still cannot Continue")
	_check(game.profile.settings == {"language": "en", "reduced_fx": true, "camera_shake": false, "fullscreen": true,
		"master_volume":1.0,"music_volume":0.55,"sfx_volume":0.85}, "settings persist before campaign creation")
	var preferences: Dictionary = game._store.load_document()
	_check(preferences.profile_initialized == false and not game._store.has_profile, "document records preferences without claiming a profile")
	var invalid: Dictionary = preferences.duplicate(true)
	invalid.profile.permanent_gold = 1
	_check(not ProfileStore._valid_document(invalid), "preferences-only document cannot hide earned gold")
	var blocker := directory + "/settings-blocker"
	_write(blocker, "not a directory")
	game._store.path = blocker + "/profile.json"
	game.set_setting("language", "zh_CN")
	_check(game.profile.settings.language == "en" and not game.has_profile, "failed preference write cannot create profile or alter settings")
	game._store.path = game.profile_path
	_check(game.new_profile() and game.has_profile, "explicit New Game initializes the campaign")
	_check(game.profile.settings == {"language": "en", "reduced_fx": true, "camera_shake": false, "fullscreen": true,
		"master_volume":1.0,"music_volume":0.55,"sfx_volume":0.85}, "New Game preserves already chosen preferences")
	game.reload_profile()
	_check(game.has_profile and game.start_run(), "explicitly initialized profile supports Continue after restart")
	game.finish_run("extracted")
	game.free()
	var old := {"schema_version": 2, "revision": 1, "profile": ProfileStore.fresh_profile(), "active_run": null}
	_write(directory + "/before-initialized-flag.json", old)
	game = _game("before-initialized-flag.json")
	_check(game.has_profile and game.start_run(), "older documents without initialization flag retain their campaign")
	game.finish_run("extracted")
	game.free()
