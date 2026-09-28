extends Node
## The UI observes this node; it never calculates damage or grants rewards.

signal changed()
signal run_started()
signal run_finished(result: Dictionary)
signal settlement_failed(outcome: String)

var profile: Dictionary = ProfileStore.fresh_profile()
var run: RunState = null
var last_error: String = ""
var storage_warning: String = ""
var has_profile: bool = false
var last_result: Dictionary:
	get:
		return profile.get("last_result", {}).duplicate(true)

# Tests use isolated paths. Production uses Godot's OS-specific user data folder.
var profile_path := "user://profile.json"
var _store: ProfileStore
var _settling := false
var _pending_outcome: String = ""

func _ready() -> void:
	if OS.has_feature("debug") and profile_path == "user://profile.json":
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--test-profile="):
				profile_path = argument.trim_prefix("--test-profile=")
	reload_profile()

func _process(delta: float) -> void:
	if run != null and run.hp > 0.0 and _pending_outcome.is_empty():
		run.elapsed += delta

func reload_profile() -> void:
	_store = ProfileStore.new(profile_path)
	var document := _store.load_document()
	last_error = _store.last_error
	storage_warning = _store.warning
	has_profile = _store.has_profile
	run = null
	_pending_outcome = ""
	if document.is_empty():
		profile = ProfileStore.fresh_profile()
		changed.emit()
		return
	profile = document.profile.duplicate(true)
	if document.active_run is Dictionary:
		# M1 never resumes a room. A crash/forced quit is one abandonment settlement.
		var receipt: Dictionary = document.active_run
		run = RunState.new()
		run.id = receipt.id
		run.gold = int(receipt.gold)
		run.relics.assign(receipt.discoveries)
		run.shots = int(receipt.shots)
		run.kills = int(receipt.kills)
		run.elapsed = float(receipt.elapsed)
		run.hp = 0.0
		if not finish_run("abandoned").is_empty():
			storage_warning = "STORAGE_ABANDONED_RECOVERED"
	changed.emit()

func new_profile() -> bool:
	if run != null or (_store != null and _store.unresolved_error):
		return false
	var fresh := ProfileStore.fresh_profile()
	if not _save(fresh, null):
		return false
	profile = fresh
	storage_warning = ""
	has_profile = true
	changed.emit()
	return true

func start_run() -> bool:
	if run != null or not has_profile:
		return false
	var next := RunState.new()
	next.id = Crypto.new().generate_random_bytes(16).hex_encode()
	if not _save(profile, next.receipt()):
		return false
	run = next
	_pending_outcome = ""
	changed.emit()
	run_started.emit()
	return true

func add_gold(amount: int) -> bool:
	if run == null or run.hp <= 0.0 or amount <= 0 or not _pending_outcome.is_empty():
		return false
	run.gold += amount
	if not _save(profile, run.receipt()):
		run.gold -= amount
		changed.emit()
		return false
	changed.emit()
	return true

func equip_relic(id: String) -> bool:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not id in ProfileStore.RELIC_IDS or id in run.relics:
		return false
	run.relics.append(id)
	if not _save(profile, run.receipt()):
		run.relics.erase(id)
		changed.emit()
		return false
	changed.emit()
	return true

func record_kill() -> void:
	if run != null and _pending_outcome.is_empty():
		run.kills += 1
		changed.emit()

func damage_player(amount: float) -> void:
	if run == null or run.hp <= 0.0 or not _pending_outcome.is_empty() or not is_finite(amount) or amount <= 0.0:
		return
	run.hp = maxf(0.0, run.hp - amount)
	changed.emit()
	if run.hp <= 0.0:
		finish_run("death")

func finish_run(outcome: String) -> Dictionary:
	if _settling or not outcome in ProfileStore.OUTCOMES:
		return {}
	if run == null:
		return last_result
	if run.id == str(last_result.get("run_id", "")):
		last_error = "STORAGE_DUPLICATE_RUN"
		return {}
	if _pending_outcome.is_empty():
		_pending_outcome = "death" if run.hp <= 0.0 and outcome == "extracted" else outcome
	outcome = _pending_outcome
	_settling = true
	var retained := run.gold if outcome == "extracted" else Balance.death_keep(run.gold)
	var next_profile := profile.duplicate(true)
	var discoveries: Array = []
	for id: String in run.relics:
		if not id in next_profile.discoveries:
			next_profile.discoveries.append(id)
			discoveries.append(id)
	next_profile.permanent_gold = int(next_profile.permanent_gold) + retained
	next_profile.total_runs = int(next_profile.total_runs) + 1
	var result := {
		"run_id": run.id, "outcome": outcome, "collected": run.gold,
		"retained": retained, "lost": run.gold - retained,
		"permanent_gold": next_profile.permanent_gold,
		"discoveries": discoveries, "kills": run.kills,
		"shots": run.shots, "elapsed": run.elapsed,
	}
	next_profile.last_result = result.duplicate(true)
	if not _save(next_profile, null):
		_settling = false
		changed.emit()
		settlement_failed.emit(outcome)
		return {}
	profile = next_profile
	run.relics.clear()
	run = null
	_pending_outcome = ""
	_settling = false
	changed.emit()
	run_finished.emit(result.duplicate(true))
	return result

func set_setting(key: String, value: Variant) -> void:
	if key == "language" and not value in ["zh_CN", "en"]:
		return
	if key in ["reduced_fx", "fullscreen"] and not value is bool:
		return
	if not key in ["language", "reduced_fx", "fullscreen"]:
		return
	var next_profile := profile.duplicate(true)
	next_profile.settings[key] = value
	if _save(next_profile, run.receipt() if run != null else null):
		profile = next_profile
		changed.emit()

func _save(next_profile: Dictionary, active_run: Variant) -> bool:
	if _store == null:
		_store = ProfileStore.new(profile_path)
	var success := _store.save_document(next_profile, active_run)
	last_error = _store.last_error
	if success:
		has_profile = true
	return success
