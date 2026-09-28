extends SceneTree
## Run: godot --headless --path . --script res://tests/test_core.gd
## Tests only use a unique user://test_core_* directory, never the player profile.

const Controller = preload("res://scripts/core/run_controller.gd")
var failures: int = 0
var checks: int = 0
var test_directory: String

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _controller(filename: String) -> Node:
	var controller := Controller.new()
	controller.profile_path = test_directory + "/" + filename
	root.add_child(controller)
	return controller

func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "test fixture can be written")
	if file != null:
		file.store_string(value if value is String else JSON.stringify(value))
		file.close()

func _run() -> void:
	test_directory = "user://test_core_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	for gold: int in [0, 1, 4, 5, 17, 99, 100, 103]:
		_check(Balance.death_keep(gold) == gold / 5, "death rounds down: " + str(gold))
	var game := _controller("normal.json")
	_check(not game.has_profile, "empty save has no profile")
	_check(not game.start_run(), "cannot start without a profile")
	_check(game.new_profile(), "create profile")
	_check(game.start_run(), "start first run")
	_check(not game.start_run(), "active run cannot be replaced")
	var first_id: String = game.run.id
	game.add_gold(17)
	game.add_gold(-200)
	_check(game.run.gold == 17, "negative pickup cannot remove gold")
	_check(game.equip_relic("split"), "equip implemented relic")
	_check(not game.equip_relic("split"), "duplicate relic rejected")
	_check(not game.equip_relic("unimplemented"), "unknown relic rejected")
	game.record_kill()
	var old_run: RunState = game.run
	var extraction: Dictionary = game.finish_run("extracted")
	_check(extraction.retained == 17 and extraction.lost == 0, "extraction retains all gold")
	_check(game.profile.permanent_gold == 17 and game.profile.total_runs == 1, "extraction pays once")
	_check(extraction.run_id == first_id and extraction.kills == 1, "result identifies the run and kills")
	_check(game.run == null and old_run.relics.is_empty(), "settlement clears transient relics")
	var contradictory := {"schema_version": 1, "revision": 99, "profile": game.profile.duplicate(true),
		"active_run": {"id": first_id, "gold": 17, "discoveries": [], "shots": 0, "kills": 0, "elapsed": 0.0}}
	_check(not ProfileStore._valid_document(contradictory), "settled run cannot also appear as active in a save")
	game.finish_run("extracted")
	game.finish_run("death")
	_check(game.profile.permanent_gold == 17 and game.profile.total_runs == 1, "repeat settlement does not pay")
	game.reload_profile()
	_check(game.run == null and game.profile.permanent_gold == 17, "reload retains settled balance")
	_check(game.profile.discoveries == ["split"], "discovery survives reload")
	_check(game.start_run(), "second run starts after settlement")
	_check(game.run.id != first_id and game.run.relics.is_empty(), "second run is fresh")
	game.add_gold(19)
	game.equip_relic("ember")
	game.damage_player(100.0)
	_check(game.run == null and game.last_result.outcome == "death", "health depletion settles death")
	_check(game.last_result.retained == 3 and game.last_result.lost == 16, "death payout rounds down")
	_check(game.profile.permanent_gold == 20 and game.profile.total_runs == 2, "death adds only retained gold")
	_check("ember" in game.profile.discoveries, "death preserves discoveries")
	game.reload_profile()
	_check(game.profile.permanent_gold == 20 and game.profile.total_runs == 2, "death result survives restart")
	_check(game.start_run(), "third run starts")
	game.add_gold(34)
	game.equip_relic("arc")
	game.reload_profile()
	_check(game.run == null and game.last_result.outcome == "abandoned", "forced quit abandons instead of resuming")
	_check(game.profile.permanent_gold == 26 and game.profile.total_runs == 3, "forced quit retains 20 percent once")
	_check("arc" in game.profile.discoveries, "forced quit preserves pickup discovery")
	game.reload_profile()
	_check(game.profile.permanent_gold == 26 and game.profile.total_runs == 3, "repeated restart cannot repay abandonment")
	game.set_setting("language", "en")
	game.set_setting("reduced_fx", true)
	game.set_setting("fullscreen", true)
	game.set_setting("language", "invalid")
	game.reload_profile()
	_check(game.profile.settings == {"language": "en", "reduced_fx": true, "fullscreen": true}, "settings persist and reject invalid language")
	game.free()
	_test_recovery()
	_test_failed_save()
	print("CORE TESTS: ", checks - failures, "/", checks, " passed; fixtures: ", ProjectSettings.globalize_path(test_directory))
	quit(1 if failures else 0)

func _test_recovery() -> void:
	var path := test_directory + "/recovery.json"
	var store := ProfileStore.new(path)
	_check(store.save_document(ProfileStore.fresh_profile()), "first whole-document save")
	var document := store.load_document()
	# Simulate power loss after flushing a committed settlement but before rename.
	document.revision = int(document.revision) + 1
	document.profile.permanent_gold = 37
	_write(path + ".tmp", document)
	var recovered := ProfileStore.new(path)
	var recovered_document := recovered.load_document()
	_check(recovered_document.profile.permanent_gold == 37, "newest valid temporary transaction wins")
	_check(recovered.warning == "STORAGE_RECOVERED", "temporary recovery is surfaced")
	_check(recovered.save_document(recovered_document.profile), "recovered profile saves normally")
	_write(path, "{interrupted")
	var backup_store := ProfileStore.new(path)
	var backup_document := backup_store.load_document()
	_check(backup_document.profile.permanent_gold == 37, "backup restores whole transaction after corrupt primary")
	_check(not backup_store.warning.is_empty(), "corruption warning is surfaced")
	var preserved := false
	for filename: String in DirAccess.get_files_at(test_directory):
		if filename.begins_with("recovery.json.corrupt."):
			preserved = true
	_check(preserved, "corrupt bytes retained for inspection")
	# Untrusted file values must never mint negative/non-finite/huge balances.
	for bad: Variant in [-1, 1.5, "999", 1e20]:
		var invalid: Dictionary = document.duplicate(true)
		invalid.profile.permanent_gold = bad
		_check(not ProfileStore._valid_document(invalid), "invalid balance rejected: " + str(bad))
	var invalid_path := test_directory + "/invalid.json"
	_write(invalid_path, "invalid bytes")
	var invalid_game := _controller("invalid.json")
	_check(not invalid_game.last_error.is_empty(), "all-corrupt profile reports unresolved error")
	_check(not invalid_game.new_profile(), "new profile cannot clobber unresolved corrupt save")
	invalid_game.reload_profile()
	_check(not invalid_game.new_profile(), "reload cannot bypass unresolved corrupt save protection")
	invalid_game.free()

func _test_failed_save() -> void:
	var game := _controller("failed.json")
	_check(game.new_profile() and game.start_run(), "prepare save failure run")
	game.add_gold(29)
	# A regular file used as a parent directory deterministically rejects writes.
	var blocker := test_directory + "/not_a_directory"
	_write(blocker, "blocker")
	game._store.path = blocker + "/profile.json"
	_check(not game.add_gold(5) and game.run.gold == 29, "failed gold pickup rolls back and remains retryable")
	_check(not game.equip_relic("arc") and game.run.relics.is_empty(), "failed relic pickup rolls back and remains retryable")
	var failed: Dictionary = game.finish_run("extracted")
	_check(failed.is_empty() and not game.last_error.is_empty(), "save failure is not reported as settlement success")
	_check(game.run != null and game.profile.permanent_gold == 0, "save failure retains run without paying")
	_check(not game.new_profile(), "save failure cannot be hidden by resetting profile")
	_check(not game.add_gold(100), "pending settlement freezes pickups")
	game._store.path = game.profile_path
	var retry: Dictionary = game.finish_run("death")
	_check(retry.outcome == "extracted", "settlement retry cannot change original outcome")
	_check(retry.retained == 29 and game.profile.permanent_gold == 29, "settlement can be retried after storage repair")
	game.finish_run("extracted")
	game.reload_profile()
	_check(game.profile.permanent_gold == 29 and game.profile.total_runs == 1, "retry settles once across restart")
	game.start_run()
	game.add_gold(19)
	game._store.path = blocker + "/profile.json"
	game.damage_player(100.0)
	_check(game.run != null and game.run.hp == 0.0, "failed death settlement remains pending")
	game._store.path = game.profile_path
	var death_retry: Dictionary = game.finish_run("extracted")
	_check(death_retry.outcome == "death" and death_retry.retained == 3, "failed death cannot become full extraction")
	game.free()
