extends RefCounted
## Camp configuration and permanent releases use the existing whole-document
## transaction. A permanent write carries the committed checkpoint, never live
## combat, and a failed flushed candidate is retried byte-for-byte first.

const Progress = preload("res://scripts/domain/progression/skill_progression.gd")
const Catalog = preload("res://scripts/domain/combat/skill_catalog.gd")
var host
var _pending: Dictionary = {}

func _init(context: Node) -> void:
	host = context

func get_loadout(hero_id: String = "") -> Array[String]:
	var id := _hero(hero_id)
	var result: Array[String] = []
	var value: Array = host.run.skill_loadout_snapshot if host.run != null and host.run.hero_id == id else host.profile.get("skill_state", {}).get(id, {}).get("loadout", Progress.starter_ids(id))
	for entry: String in value: result.append(entry)
	return result

func get_branches(hero_id: String = "") -> Dictionary:
	var id := _hero(hero_id)
	if host.run != null and host.run.hero_id == id: return host.run.skill_branches_snapshot.duplicate(true)
	return host.profile.get("skill_state", {}).get(id, Progress.fresh_state(id)).get("branches", {}).duplicate(true)

func get_progress(hero_id: String = "", skill_id: String = "") -> Dictionary:
	var id := _hero(hero_id)
	if id not in Progress.HERO_IDS: return {}
	var state: Dictionary = host.profile.get("skill_state", {}).get(id, Progress.fresh_state(id))
	var branches := get_branches(id)
	if not skill_id.is_empty():
		if skill_id not in Progress.skill_ids(id): return {}
		var entry := Progress.view(state, skill_id)
		entry.branch = str(branches.get(skill_id, ""))
		return entry
	var result: Dictionary = {}
	for skill: String in Progress.skill_ids(id):
		result[skill] = Progress.view(state, skill)
		result[skill].branch = str(branches.get(skill, ""))
	return result

func apply_skill_config(hero_id: String, four_skill_ids: Array, branch_choices: Dictionary = {}, operation_id: String = "") -> Dictionary:
	var operation := operation_id if not operation_id.is_empty() else "skillcfg:" + Crypto.new().generate_random_bytes(16).hex_encode()
	if not _operation_valid(operation): return _result(false, "SKILL_INVALID_OPERATION", operation)
	# This guard covers safe rooms, pauses and cleared encounters too.
	if host.run != null or not host._camp_available(): return _result(false, "SKILL_CAMP_ONLY", operation)
	if hero_id not in Progress.HERO_IDS: return _result(false, "SKILL_WRONG_CLASS", operation)
	if not _pending.is_empty() and _pending.operation_id != operation:
		var retried := retry_pending()
		if not retried.ok: return _result(false, str(retried.reason), operation)
	var state: Dictionary = host.profile.get("skill_state", {}).get(hero_id, {})
	if state.is_empty(): return _result(false, "SKILL_PROFILE_NOT_READY", operation)
	var choices: Dictionary = state.branches.duplicate(true)
	for id: Variant in branch_choices:
		if not choices.has(id): return _result(false, "SKILL_INVALID_BRANCH", operation)
		choices[id] = branch_choices[id]
	if not Progress.valid_loadout(four_skill_ids, hero_id, state.learned): return _result(false, "SKILL_INVALID_LOADOUT", operation)
	if not Progress.valid_branches(choices, hero_id, state.mastery): return _result(false, "SKILL_BRANCH_LOCKED", operation)
	var record := {"hero_id":hero_id, "loadout":four_skill_ids.duplicate(), "branches":choices}
	var prior: Dictionary = host.profile.get("skill_config_receipts", {}).get(operation, {})
	if not prior.is_empty(): return _result(prior == record, "" if prior == record else "SKILL_OPERATION_CONFLICT", operation)
	if not _pending.is_empty():
		if _pending.candidate.skill_config_receipts.get(operation) != record: return _result(false, "SKILL_OPERATION_CONFLICT", operation)
		return retry_pending()
	var next: Dictionary = host.profile.duplicate(true)
	if next.skill_config_receipts.size() >= Progress.MAX_CONFIG_RECEIPTS: return _result(false, "SKILL_CONFIG_CAPACITY", operation)
	next.skill_state[hero_id].loadout = four_skill_ids.duplicate()
	next.skill_state[hero_id].branches = choices
	next.skill_config_receipts[operation] = record
	return _commit(next, operation)

func record_skill_release(skill_id: String, cast_id: int, in_combat: bool = true) -> Dictionary:
	var operation := "skillxp:" + str(host.run.id if host.run != null else "") + ":" + str(cast_id)
	if host.run == null or not in_combat or bool(host.run.demo) or host.run.hp <= 0.0: return _result(false, "SKILL_NOT_COMBAT", operation)
	if not host.run.expedition.is_empty() and host.run.expedition.get("phase") != "combat": return _result(false, "SKILL_NOT_COMBAT", operation)
	var hero_id: String = host.run.hero_id
	if cast_id < 1 or cast_id > Progress.MAX_CAST or skill_id not in get_loadout(hero_id): return _result(false, "SKILL_INVALID_RELEASE", operation)
	if not _pending.is_empty():
		var retried := retry_pending()
		if not retried.ok: return _result(false, str(retried.reason), operation)
	var state: Dictionary = host.profile.get("skill_state", {}).get(hero_id, {})
	if state.is_empty() or skill_id not in state.learned: return _result(false, "SKILL_PROFILE_NOT_READY", operation)
	if state.cast_run_id == host.run.id and cast_id <= int(state.cast_cursor): return _result(true, "", operation)
	var spec := Catalog.skill(skill_id)
	if spec.is_empty(): return _result(false, "SKILL_UNKNOWN", operation)
	var next: Dictionary = host.profile.duplicate(true)
	var delta := Progress.release_xp(float(spec.get("base_cooldown", spec.get("cooldown", 0.0))))
	next.skill_state[hero_id].mastery[skill_id] = mini(300, int(state.mastery[skill_id]) + delta)
	next.skill_state[hero_id].cast_run_id = host.run.id
	next.skill_state[hero_id].cast_cursor = cast_id
	return _commit(next, operation)

func grant_skill_group(group_id: String, operation_id: String = "") -> Dictionary:
	var operation := operation_id if not operation_id.is_empty() else "skillgroup:" + group_id
	if group_id not in Progress.GROUPS or not _operation_valid(operation): return _result(false, "SKILL_UNKNOWN_GROUP", operation)
	if host.run != null and bool(host.run.demo): return _result(false, "SKILL_PREVIEW_ONLY", operation)
	if not _pending.is_empty():
		var retried := retry_pending()
		if not retried.ok: return _result(false, str(retried.reason), operation)
	if group_id in host.profile.get("skill_unlock_groups", []): return _result(true, "", operation)
	if not Progress.valid(host.profile, true): return _result(false, "SKILL_PROFILE_NOT_READY", operation)
	var next := Progress.unlock_group(host.profile, group_id)
	return _commit(next, operation)

func retry_pending() -> Dictionary:
	if _pending.is_empty(): return _result(true, "", "")
	var operation: String = _pending.operation_id
	# A separate successful permanent transaction must never be overwritten by
	# an old candidate. The store also protects the acknowledged disk revision.
	if host.profile != _pending.base_profile: return _result(false, "SKILL_PENDING_CONFLICT", operation)
	if not host._save(_pending.candidate, _pending.receipt): return _result(false, str(host.last_error), operation)
	host.profile = _pending.candidate.duplicate(true)
	_pending.clear()
	host.changed.emit()
	return _result(true, "", operation)

func pending_operation() -> String:
	return str(_pending.get("operation_id", ""))

func has_pending() -> bool:
	return not _pending.is_empty()

func pending_matches(candidate: Dictionary, receipt: Variant) -> bool:
	return not _pending.is_empty() and candidate == _pending.candidate and receipt == _pending.receipt

func _commit(candidate: Dictionary, operation: String) -> Dictionary:
	if not Progress.valid(candidate, true): return _result(false, "SKILL_INVALID_DATA", operation)
	var receipt: Variant = host.run.receipt() if host.run != null else null
	_pending = {"candidate":candidate.duplicate(true), "receipt":receipt,
		"base_profile":host.profile.duplicate(true), "operation_id":operation}
	return retry_pending()

func _hero(hero_id: String) -> String:
	if not hero_id.is_empty(): return hero_id
	return str(host.run.hero_id) if host.run != null else str(host.profile.get("selected_hero", "CH01"))

static func _operation_valid(value: String) -> bool:
	return not value.is_empty() and value.length() <= 160

static func _result(ok: bool, reason: String, operation: String) -> Dictionary:
	return {"ok":ok, "reason":reason, "operation_id":operation}
