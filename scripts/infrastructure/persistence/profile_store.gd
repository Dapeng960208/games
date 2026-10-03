class_name ProfileStore
extends RefCounted
## One document commits rewards, discoveries, and active-run clearing together.
## A flushed newer temporary document is a recoverable commit intent.

const SaveLease = preload("res://scripts/infrastructure/persistence/profile_save_lease.gd")
const Recycle = preload("res://scripts/infrastructure/persistence/profile_recycle_bin.gd")
const SCHEMA_VERSION := 3
const SETTLEMENT_RULES_VERSION := 3
const Economy = preload("res://scripts/domain/equipment/economy_history.gd")
const ECONOMY_RULES_VERSION := Economy.CURRENT_VERSION
const Progression = preload("res://scripts/domain/progression/hero_progression.gd")
const SkillProgress = preload("res://scripts/domain/progression/skill_progression.gd")
const CombatState = preload("res://scripts/domain/combat/combat_snapshot.gd")
const Loot = preload("res://scripts/domain/expedition/expedition_rewards.gd")
const Transactions = preload("res://scripts/domain/equipment/instance_transactions.gd")
const Forging = preload("res://scripts/domain/equipment/instance_forging.gd")
const EnemyCalibration = preload("res://scripts/domain/combat/enemy_calibration.gd")
const ClassMigration = preload("res://scripts/infrastructure/persistence/equipment_class_migration.gd")
const NativeProfile = preload("res://scripts/domain/equipment/numerical_profile.gd")
const Instances = preload("res://scripts/domain/equipment/equipment_instances.gd")
const Expedition = preload("res://scripts/domain/expedition/expedition_state.gd")
const MAX_NUMBER := 1_000_000_000_000
const RELIC_IDS := ["split", "ember", "arc"]
const OUTCOMES := ["extracted", "death", "abandoned"]
const HERO_IDS := ["CH01", "CH02", "CH03"]
const BOSS_IDS := ["BO01", "BO02", "BO03", "BO04", "BO05", "BO06", "BO10"]
const SLOTS := ["weapon", "head", "chest", "hands", "feet", "charm"]
const STARTER_IDS := ["EQ01", "EQ11", "EQ21", "EQ31", "EQ41", "EQ51"]
const MAX_TRANSACTIONS := 4096 # Bounded purchase/upgrade/recycle receipts; never evict IDs.
# Compact JSON fits the entire bounded ledger, including 4095 full-catalog sales.
# Keep every receipt ID: truncation/eviction would permit old requests to replay.
const MAX_DOCUMENT_BYTES := 32 * 1024 * 1024
const VOLUME_DEFAULTS := {"master_volume":1.0,"music_volume":0.55,"sfx_volume":0.85}
const Controls = preload("res://scripts/infrastructure/input/control_bindings.gd")
const COMBAT_SETTING_DEFAULTS := {"auto_attack": false, "enemy_skill_paths": true}

var path: String
# A lower instance limit supports constrained storage and exact boundary tests.
var max_document_bytes: int = MAX_DOCUMENT_BYTES
var last_error: String = ""
var warning: String = ""
var has_profile: bool = false
var unresolved_error: bool:
	get:
		return _blocked
var _current: Dictionary = {}
var _acknowledged_bytes := PackedByteArray()
var _pending_save_bytes := PackedByteArray()
var _pending_profile_id := ""
var _blocked: bool = false
var recycle_clock: Callable
var recycle_fail_stage := ""
var _generation := ""

func _init(save_path: String = "user://profile.json") -> void:
	path = save_path

static func fresh_profile() -> Dictionary:
	var result := {
		"permanent_gold": 0, "discoveries": [], "total_runs": 0,
		"last_result": {},
		"settings": {"language": "zh_CN", "reduced_fx": false, "camera_shake": false, "fullscreen": false,
			"auto_attack": false, "enemy_skill_paths": true, "controls": {},
			"master_volume":1.0,"music_volume":0.55,"sfx_volume":0.85},
		"selected_hero": "CH01", "hero_xp": {"CH01": 0, "CH02": 0, "CH03": 0},
		"branches": {"CH01": {"q": "", "ultimate": ""}, "CH02": {"q": "", "ultimate": ""},
			"CH03": {"q": "", "ultimate": ""}},
		"equipment": {"EQ01": {"level": 0}, "EQ11": {"level": 0}, "EQ21": {"level": 0},
			"EQ31": {"level": 0}, "EQ41": {"level": 0}, "EQ51": {"level": 0}},
		"loadout": {"weapon": "EQ01", "head": "EQ11", "chest": "EQ21",
			"hands": "EQ31", "feet": "EQ41", "charm": "EQ51"},
		"bosses": [], "tutorial_completed": [], "migration_id": "new_v2",
		"equipment_discoveries": [],
		"applied_transactions": {"starter_grant_v1": {"kind": "starter"}},
	}
	result.merge(SkillProgress.fresh_fields(), true)
	return result

func load_document() -> Dictionary:
	var lease := SaveLease.acquire(path)
	if lease == null:
		_blocked = true
		has_profile = false
		last_error = "STORAGE_IN_USE"
		return {}
	return _load_document_locked()

func _load_document_locked() -> Dictionary:
	last_error = ""
	warning = ""
	_current = {}
	_acknowledged_bytes = PackedByteArray()
	_pending_save_bytes = PackedByteArray()
	_pending_profile_id = ""
	_blocked = false
	has_profile = false
	var recycle := _recycle()
	var recycle_state := recycle.read_state()
	if recycle_state.is_empty():
		last_error = recycle.last_error
		_blocked = true
		return {}
	_generation = str(recycle_state.active_generation)
	var disk_path := recycle.active_path(recycle_state)
	if not _generation.is_empty() and not FileAccess.file_exists(AssetCatalog.resolve(disk_path)) and not FileAccess.file_exists(AssetCatalog.resolve(disk_path + ".tmp")) and not FileAccess.file_exists(AssetCatalog.resolve(disk_path + ".bak")) and not FileAccess.file_exists(AssetCatalog.resolve(disk_path + ".bak.tmp")):
		last_error = "STORAGE_RECYCLE_INVALID"
		_blocked = true
		return {}
	var best_path := ""
	var best_needs_class_upgrade := false
	var legacy_document: Dictionary = {}
	var blocked_migration_revision := -1
	# All candidates contain whole transactions; never merge fields across files.
	for candidate: String in [disk_path, disk_path + ".tmp", disk_path + ".bak", disk_path + ".bak.tmp"]:
		if not FileAccess.file_exists(AssetCatalog.resolve(candidate)):
			continue
		var file := FileAccess.open(AssetCatalog.resolve(candidate), FileAccess.READ)
		if file == null:
			_blocked = true
			last_error = "STORAGE_READ_FAILED"
			continue
		var parser := JSON.new()
		var parsed: Variant = null
		if file.get_length() <= _byte_limit() and parser.parse(file.get_as_text()) == OK:
			parsed = parser.data
		file.close()
		# A valid current backup takes precedence over every obsolete candidate.
		# Validate the old document before resetting; damage is never a reset trigger.
		if _is_legacy_document(parsed) and _valid_document(parsed):
			if legacy_document.is_empty() or int(parsed.revision) > int(legacy_document.revision):
				legacy_document = parsed.duplicate(true)
			continue
		var needs_class_upgrade: bool = parsed is Dictionary and parsed.get("profile") is Dictionary and parsed.get("profile", {}).get("ruleset_version", 1) == 2 and (not parsed.get("profile", {}).has("equipment_class_migration") or parsed.get("profile", {}).get("hero_role_revision", 0) != 1)
		if parsed is Dictionary:
			var source_revision := int(parsed.get("revision", 0))
			parsed = ClassMigration.upgrade_document(parsed)
			if needs_class_upgrade and parsed.is_empty():
				blocked_migration_revision = maxi(blocked_migration_revision, source_revision)
				continue
		if not _valid_document(parsed):
			# Keep unreadable bytes available for inspection; never silently delete.
			var preserved := candidate + ".corrupt." + str(int(Time.get_unix_time_from_system())) + "_" + str(Time.get_ticks_usec())
			if DirAccess.copy_absolute(candidate, preserved) != OK:
				_blocked = true
				last_error = "STORAGE_PRESERVE_FAILED"
			warning = "STORAGE_CORRUPT_PRESERVED"
			continue
		var document: Dictionary = parsed
		if _current.is_empty() or int(document.revision) > int(_current.revision):
			_current = document.duplicate(true)
			best_path = candidate
			best_needs_class_upgrade = needs_class_upgrade
	if blocked_migration_revision >= 0 and (_current.is_empty() or blocked_migration_revision >= int(_current.revision)):
		_blocked = true
		last_error = "STORAGE_CLASS_MIGRATION_BLOCKED"
	if _blocked:
		return {}
	if _current.is_empty():
		if not legacy_document.is_empty():
			return _reset_legacy_locked(legacy_document)
		if not warning.is_empty():
			last_error = "STORAGE_NO_VALID_PROFILE"
			_blocked = true
		return {}
	has_profile = bool(_current.get("profile_initialized", true))
	if best_path != disk_path:
		warning = "STORAGE_RECOVERED"
	if not _current.profile.has("branches"):
		# Early v2 saves predate talent choices. Normalize the whole document once;
		# retain its active receipt so the controller still performs one abandonment.
		var normalized: Dictionary = _current.profile.duplicate(true)
		normalized.branches = fresh_profile().branches
		if not save_document(normalized, _current.active_run, bool(_current.get("profile_initialized", true))):
			_blocked = true
			has_profile = false
			return {}
	if best_needs_class_upgrade:
		# Preserve original acknowledged bytes before atomically saving qualification
		# metadata/loadout cleanup. Failed writes leave the original recoverable.
		_acknowledged_bytes = FileAccess.get_file_as_bytes(AssetCatalog.resolve(best_path))
		if not save_document(_current.profile, _current.active_run, bool(_current.get("profile_initialized", true))):
			_blocked = true
			has_profile = false
			return {}
	if not _current.profile.get("equipment_class_migration", {}).get("removed_slots", []).is_empty():
		warning = "STORAGE_CLASS_EQUIPMENT_UPDATED"
	if _acknowledged_bytes.is_empty(): _acknowledged_bytes = FileAccess.get_file_as_bytes(AssetCatalog.resolve(best_path))
	if not _current.profile.has("skill_system_version") or (_current.active_run is Dictionary and _current.active_run.has("expedition") and not _current.active_run.has("skill_loadout_snapshot")):
		# The old whole document has passed every validator above. Preserve its
		# bytes and checkpoint while adding only the two scoped subsystem versions.
		var migrated := upgrade_skill_document(_current)
		if migrated.is_empty() or not save_document(migrated.profile, migrated.active_run, bool(migrated.get("profile_initialized", true))):
			_blocked = true
			has_profile = false
			if last_error.is_empty(): last_error = "STORAGE_SKILL_MIGRATION_BLOCKED"
			return {}
	var loaded := _current.duplicate(true)
	# Normalize optional presentation settings in memory only; opening a demo
	# must not rewrite a save just to add the comfort default or volume keys.
	if not loaded.profile.settings.has("camera_shake"): loaded.profile.settings.camera_shake = false
	for key: String in VOLUME_DEFAULTS:
		if not loaded.profile.settings.has(key): loaded.profile.settings[key] = VOLUME_DEFAULTS[key]
	for key: String in COMBAT_SETTING_DEFAULTS:
		if not loaded.profile.settings.has(key): loaded.profile.settings[key] = COMBAT_SETTING_DEFAULTS[key]
	# Fill absent keys without changing any bindings already chosen by the player.
	if not loaded.profile.settings.has("controls"): loaded.profile.settings.controls = {}
	return loaded

static func _is_legacy_document(value: Variant) -> bool:
	if not value is Dictionary or not value.get("profile") is Dictionary: return false
	return value.get("schema_version") in [1, 2] or value.profile.get("ruleset_version", 1) == 1

func _reset_legacy_locked(legacy: Dictionary) -> Dictionary:
	var replacement := {
		"schema_version": SCHEMA_VERSION,
		"profile_id": Crypto.new().generate_random_bytes(16).hex_encode(),
		"profile_initialized": true, "revision": int(legacy.revision) + 1,
		"profile": NativeProfile.fresh(fresh_profile()), "active_run": null,
	}
	var bytes := _serialize(replacement)
	if not _valid_document(replacement) or bytes.size() > _byte_limit():
		last_error = "STORAGE_INVALID_DATA" if bytes.size() <= _byte_limit() else "STORAGE_CAPACITY_EXCEEDED"
		_blocked = true
		return {}
	var recycle := _recycle()
	# Preserve the exact source candidates before switching the active generation.
	# A failed archive/write/index commit leaves the old files and progress intact.
	if not recycle.archive_and_switch(_serialize(legacy), str(legacy.get("profile_id", _legacy_profile_id())), bytes, _generation):
		last_error = recycle.last_error
		_blocked = true
		return {}
	_generation = str(recycle.read_state().get("active_generation", ""))
	_current = replacement
	_acknowledged_bytes = bytes
	has_profile = true
	warning = "STORAGE_LEGACY_RESET"
	return replacement.duplicate(true)

func save_document(profile: Dictionary, active_run: Variant = null, profile_initialized: bool = true) -> bool:
	var lease := SaveLease.acquire(path)
	if lease == null:
		last_error = "STORAGE_IN_USE"
		return false
	return _save_document_locked(profile, active_run, profile_initialized)

func _save_document_locked(profile: Dictionary, active_run: Variant = null, profile_initialized: bool = true) -> bool:
	last_error = ""
	if _blocked:
		last_error = "STORAGE_NO_VALID_PROFILE"
		return false
	var recycle := _recycle()
	var recycle_state := recycle.read_state()
	if recycle_state.is_empty():
		last_error = recycle.last_error
		return false
	if recycle_state.active_generation != _generation:
		last_error = "STORAGE_RECYCLE_CHANGED"
		return false
	var disk_path := recycle.active_path(recycle_state)
	var document := _next_document(profile, active_run, profile_initialized)
	# _current is a detached document accepted by this store. Reuse progression
	# validation only when every permanent field is exactly equal, in the same
	# schema. The changing run receipt still receives all normal checks.
	var same_profile: bool = int(_current.get("schema_version",0)) == SCHEMA_VERSION and document.profile == _current.get("profile")
	if not _valid_candidate(document,same_profile):
		last_error = "STORAGE_INVALID_DATA"
		return false
	# Check the exact bytes before touching primary, temporary, or backup files.
	var serialized := _serialize(document)
	if serialized.size() > _byte_limit():
		last_error = "STORAGE_CAPACITY_EXCEEDED"
		return false
	# The lease prevents overlapping writes; compare revisions while holding it
	# as well, so an older window cannot overwrite another completed transaction.
	# Only this store's exact flushed intent may be retried without reloading.
	if not _disk_matches_current(serialized): return false
	var directory := ProjectSettings.globalize_path(disk_path).get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	# Preserve the last acknowledged whole transaction before replacing a candidate.
	if not _current.is_empty():
		if _acknowledged_bytes.is_empty(): _acknowledged_bytes = _serialize(_current)
		if not _write_serialized(disk_path + ".bak.tmp", _acknowledged_bytes):
			return false
		if DirAccess.rename_absolute(disk_path + ".bak.tmp", disk_path + ".bak") != OK:
			last_error = "STORAGE_REPLACE_FAILED"
			return false
	if not _write_serialized(disk_path + ".tmp", serialized):
		return false
	_pending_save_bytes = serialized
	_pending_profile_id = str(document.profile_id)
	if DirAccess.rename_absolute(disk_path + ".tmp", disk_path) != OK:
		last_error = "STORAGE_REPLACE_FAILED"
		return false
	_current = document
	_acknowledged_bytes = serialized
	_pending_save_bytes = PackedByteArray()
	_pending_profile_id = ""
	has_profile = profile_initialized
	return true

func _recycle() -> Recycle:
	var recycle := Recycle.new(path, recycle_clock)
	recycle.fail_stage = recycle_fail_stage
	recycle.document_validator = _valid_document
	return recycle

func _disk_matches_current(retry_bytes: PackedByteArray = PackedByteArray()) -> bool:
	var recycle := _recycle()
	var state := recycle.read_state()
	if state.is_empty():
		last_error = recycle.last_error
		return false
	if state.active_generation != _generation:
		last_error = "STORAGE_RECYCLE_CHANGED"
		return false
	var disk_path := recycle.active_path(state)
	var found := _current.is_empty()
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		var filename := disk_path + suffix
		if not FileAccess.file_exists(AssetCatalog.resolve(filename)): continue
		var file := FileAccess.open(AssetCatalog.resolve(filename), FileAccess.READ)
		if file == null or file.get_length() > _byte_limit():
			last_error = "STORAGE_READ_FAILED"
			return false
		var expected_length := file.get_length()
		var bytes := file.get_buffer(expected_length)
		var read_error := file.get_error()
		file.close()
		if read_error != OK or bytes.size() != expected_length:
			last_error = "STORAGE_READ_FAILED"
			return false
		if not _acknowledged_bytes.is_empty() and bytes == _acknowledged_bytes:
			found = true
			continue
		if suffix == ".tmp" and not _pending_save_bytes.is_empty() and bytes == _pending_save_bytes and bytes == retry_bytes:
			continue
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not parsed is Dictionary or not _number(parsed.get("revision")): continue
		if int(parsed.revision) < int(_current.get("revision", 0)): continue
		if _is_legacy_document(parsed) or not _valid_document(parsed): continue
		if _serialize(parsed) != _serialize(_current):
			last_error = "STORAGE_RECYCLE_CHANGED"
			return false
		found = true
	if not found: last_error = "STORAGE_RECYCLE_CHANGED"
	return found

func _legacy_profile_id() -> String:
	return ProjectSettings.globalize_path(path).sha256_text().substr(0, 32)

func recycle_entries() -> Array[Dictionary]:
	var recycle := _recycle()
	var entries: Array[Dictionary] = recycle.list_entries()
	last_error = recycle.last_error
	return entries

func cleanup_recycle_bin() -> bool:
	var lease := SaveLease.acquire(path)
	if lease == null:
		last_error = "STORAGE_IN_USE"
		return false
	return _cleanup_recycle_bin_locked()

func _cleanup_recycle_bin_locked() -> bool:
	var recycle := _recycle()
	var success: bool = recycle.cleanup_expired()
	last_error = recycle.last_error
	return success

func recycle_and_replace(profile: Dictionary, initialized: bool = true) -> bool:
	var lease := SaveLease.acquire(path)
	if lease == null:
		last_error = "STORAGE_IN_USE"
		return false
	return _recycle_and_replace_locked(profile, initialized)

func _recycle_and_replace_locked(profile: Dictionary, initialized: bool = true) -> bool:
	last_error = ""
	if _blocked or not has_profile or _current.is_empty():
		last_error = "STORAGE_RECYCLE_UNAVAILABLE"
		return false
	if not _disk_matches_current(): return false
	var replacement := _next_document(profile, null, initialized)
	replacement.profile_id = Crypto.new().generate_random_bytes(16).hex_encode()
	if not _valid_document(replacement):
		last_error = "STORAGE_INVALID_DATA"
		return false
	var bytes := _serialize(replacement)
	if bytes.size() > _byte_limit():
		last_error = "STORAGE_CAPACITY_EXCEEDED"
		return false
	var recycle := _recycle()
	# The accepted complete document includes the active receipt and migration
	# metadata. Raw candidate files are retained alongside it without alteration.
	if not recycle.archive_and_switch(_serialize(_current), str(_current.get("profile_id", _legacy_profile_id())), bytes, _generation):
		last_error = recycle.last_error
		return false
	_generation = str(recycle.read_state().get("active_generation", ""))
	_current = replacement
	_acknowledged_bytes = bytes
	has_profile = initialized
	return true

func restore_recycled(entry_id: String) -> bool:
	var lease := SaveLease.acquire(path)
	if lease == null:
		last_error = "STORAGE_IN_USE"
		return false
	return _restore_recycled_locked(entry_id)

func _restore_recycled_locked(entry_id: String) -> bool:
	last_error = ""
	if _blocked:
		last_error = "STORAGE_RECYCLE_INVALID"
		return false
	# Recovery never overwrites even a newly created, otherwise empty profile.
	if has_profile:
		last_error = "STORAGE_RECYCLE_CONFLICT"
		return false
	if not _disk_matches_current(): return false
	var recycle := _recycle()
	var archive: Dictionary = recycle.get_archive(entry_id)
	if archive.is_empty():
		last_error = recycle.last_error
		return false
	var value: Variant = JSON.parse_string(Marshalls.base64_to_raw(archive.snapshot).get_string_from_utf8())
	if _is_legacy_document(value) or not _valid_document(value) or not bool(value.get("profile_initialized", true)):
		last_error = "STORAGE_RECYCLE_INVALID"
		return false
	var restored: Dictionary = value.duplicate(true)
	if restored.has("profile_id") and restored.profile_id != archive.profile_id:
		last_error = "STORAGE_RECYCLE_INVALID"
		return false
	restored.profile_id = archive.profile_id
	restored.revision = maxi(int(_current.get("revision", 0)), int(restored.revision)) + 1
	var bytes := _serialize(restored)
	if bytes.size() > _byte_limit():
		last_error = "STORAGE_CAPACITY_EXCEEDED"
		return false
	if not recycle.restore(entry_id, bytes, _generation):
		last_error = recycle.last_error
		return false
	_generation = str(recycle.read_state().get("active_generation", ""))
	_current = restored
	_acknowledged_bytes = bytes
	has_profile = true
	return true

func _next_document(profile: Dictionary, active_run: Variant, profile_initialized: bool) -> Dictionary:
	var identity := str(_current.get("profile_id", ""))
	if identity.is_empty():
		identity = _legacy_profile_id() if not _current.is_empty() else _pending_profile_id
		if identity.is_empty(): identity = Crypto.new().generate_random_bytes(16).hex_encode()
	return {
		"schema_version": SCHEMA_VERSION,
		"profile_id": identity,
		"profile_initialized": profile_initialized,
		"revision": int(_current.get("revision", 0)) + 1,
		"profile": profile.duplicate(true),
		"active_run": active_run.duplicate(true) if active_run is Dictionary else null,
	}

func _byte_limit() -> int:
	return clampi(max_document_bytes, 1, MAX_DOCUMENT_BYTES)

static func _serialize(document: Dictionary) -> PackedByteArray:
	# Count and write the same UTF-8 bytes; String.length() is not a byte count.
	# Reloaded JSON integers are floats. A decimal suffix on a large integral
	# seed can lose one unit in Godot's next parse and invalidate its receipt.
	return JSON.stringify(_json_values(document), "", true, true).to_utf8_buffer()

static func _json_values(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0: return int(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = _json_values(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_json_values(child))
		return result
	return value

func storage_capacity(profile: Dictionary, active_run: Variant = null, profile_initialized: bool = true) -> Dictionary:
	var bytes := _serialize(_next_document(profile, active_run, profile_initialized)).size()
	var count := (profile.get("applied_transactions", {}) as Dictionary).size()
	return {"bytes": bytes, "limit_bytes": _byte_limit(),
		"remaining_bytes": maxi(0, _byte_limit() - bytes), "transactions": count,
		"remaining_transactions": maxi(0, MAX_TRANSACTIONS - count)}

func _write_document(destination: String, document: Dictionary) -> bool:
	return _write_serialized(destination, _serialize(document))

func _write_serialized(destination: String, serialized: PackedByteArray) -> bool:
	if serialized.size() > _byte_limit():
		last_error = "STORAGE_CAPACITY_EXCEEDED"
		return false
	var file := FileAccess.open(AssetCatalog.resolve(destination), FileAccess.WRITE)
	if file == null:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	file.store_buffer(serialized)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	return true

static func _number(value: Variant, maximum: float = MAX_NUMBER, integral: bool = true) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= maximum and (not integral or number == floor(number))

static func _relics(value: Variant) -> bool:
	if not value is Array or value.size() > RELIC_IDS.size():
		return false
	var seen: Array = []
	for id: Variant in value:
		if not id is String or not id in RELIC_IDS or id in seen:
			return false
		seen.append(id)
	return true

static func retained_gold(gold: int, outcome: String, rules_version: int = SETTLEMENT_RULES_VERSION) -> int:
	# Historical receipts never depend on today's tunable Balance constants.
	if rules_version not in [1, 2, 3] or gold < 0 or outcome not in OUTCOMES:
		return -1
	if outcome == "extracted": return gold
	if rules_version >= 2 and (outcome == "death" or rules_version >= 3): return int(gold / 2)
	return int(gold / 5)

static func _valid_receipt(value: Variant, version: int = 1) -> bool:
	if not value is Dictionary:
		return false
	if not value.get("id") is String or value.id.is_empty() or value.id.length() > 80:
		return false
	var numerical: Variant = value.get("ruleset_version", 1)
	if not _number(numerical, 2) or int(numerical) < 1 or not Expedition.versions_valid(value, int(numerical), int(numerical) == 2): return false
	if value.has("enemy_calibration_snapshot") and (numerical != 2 or not EnemyCalibration.valid(value.enemy_calibration_snapshot)): return false
	var valid := _number(value.get("gold")) and _relics(value.get("discoveries")) \
		and _number(value.get("shots")) and _number(value.get("kills")) \
		and _number(value.get("elapsed"), MAX_NUMBER, false)
	if not valid or version == 1:
		return valid
	return value.get("hero_id") in HERO_IDS and _number(value.get("level"), Progression.level_cap() if numerical == 2 else 20) and value.level >= 1 \
		and _number(value.get("hero_xp_gained"), 3600) and value.get("rules_version") == 1 \
		and _unique_ids(value.get("completed_reward_ids"), 512) \
		and _allowed_ids(value.get("boss_defeats"), BOSS_IDS)

static func _valid_result(value: Variant, version: int = 1, ruleset: int = 1) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not value.get("run_id") is String or value.run_id.is_empty() or value.run_id.length() > 80:
		return false
	if not value.get("outcome") in OUTCOMES:
		return false
	for key: String in ["collected", "retained", "lost", "permanent_gold", "shots", "kills"]:
		if not _number(value.get(key)):
			return false
	# Missing rules belong to the original format. Never reinterpret an old
	# receipt with the default used for newly settled runs.
	var rules: Variant = value.get("rules_version", 1)
	if not _number(rules, SETTLEMENT_RULES_VERSION) or int(rules) < 1: return false
	if version == 1 and int(rules) != 1: return false
	var expected_retained := retained_gold(int(value.collected), str(value.outcome), int(rules))
	var valid := int(value.retained) == expected_retained and int(value.retained) + int(value.lost) == int(value.collected) \
		and _relics(value.get("discoveries")) and _number(value.get("elapsed"), MAX_NUMBER, false)
	if not valid or version == 1:
		return valid
	if value.has("field_xp_gained"):
		if not _number(value.field_xp_gained, 18): return false
		if int(value.field_xp_gained) > 0 and (int(rules) < 2 or value.outcome != "death"): return false
		if not _number(value.get("hero_xp_gained"), 3600) or int(value.field_xp_gained) > int(value.hero_xp_gained): return false
	if version >= 3:
		for key: String in ["equipment_retained", "equipment_lost"]:
			if value.has(key):
				if not _unique_ids(value[key], 512 if ruleset == 2 else ContentRegistry.equipment_ids().size()): return false
				for id: String in value[key]:
					if ruleset != 2 and ContentRegistry.equipment(id).is_empty(): return false
		if value.outcome != "extracted" and not value.get("equipment_retained", []).is_empty(): return false
		if value.outcome == "extracted" and not value.get("equipment_lost", []).is_empty(): return false
	return _number(value.get("wallet_before")) \
		and _number(value.get("wallet_after")) and int(value.wallet_after) == int(value.permanent_gold) \
		and int(value.wallet_before) + int(value.retained) == int(value.wallet_after)

static func _valid_document(value: Variant) -> bool:
	return _valid_candidate(value)

static func upgrade_skill_document(document: Dictionary) -> Dictionary:
	if not _valid_document(document): return {}
	var result := document.duplicate(true)
	result.profile = SkillProgress.upgrade_profile(result.profile)
	if result.profile.is_empty(): return {}
	var receipt: Variant = result.active_run
	if receipt is Dictionary and not receipt.has("skill_loadout_snapshot"):
		var hero_id: String = receipt.hero_id
		receipt["skill_loadout_snapshot"] = SkillProgress.starter_ids(hero_id)
		receipt["skill_branches_snapshot"] = {hero_id + "_SK01":"", hero_id + "_SK04":""}
		receipt["role_combat_version"] = SkillProgress.ROLE_VERSION
		for pair: Array in [["q", 1, 4], ["ultimate", 4, 5]]:
			var choice := str(receipt.get("branches_snapshot", {}).get(pair[0], ""))
			if choice in ["A", "B"]:
				var id := "%s_SK%02d" % [hero_id, int(pair[1])]
				receipt.skill_branches_snapshot[id] = choice
				result.profile.skill_state[hero_id].mastery[id] = maxi(int(result.profile.skill_state[hero_id].mastery[id]), int(SkillProgress.THRESHOLDS[int(pair[2]) - 1]))
		if receipt.has("expedition"):
			var stats := Expedition.Resolver.resolve(hero_id, int(receipt.level), receipt.loadout_snapshot, receipt.equipment_snapshot, int(result.profile.get("ruleset_version", 1)), result.profile.get("talents", {}).get(hero_id, {}))
			receipt.expedition.runtime = CombatState.upgrade(receipt.expedition.runtime, hero_id, stats, int(receipt.expedition.node_index) == 0 and receipt.expedition.completed_nodes.is_empty())
			if receipt.expedition.runtime.is_empty(): return {}
	return result if _valid_document(result) else {}

static func _valid_candidate(value: Variant, identical_progression: bool = false) -> bool:
	# Godot JSON parses numeric tokens as floats; Array.has is type-sensitive.
	if not value is Dictionary or not _number(value.get("schema_version"), SCHEMA_VERSION) \
		or int(value.schema_version) < 1:
		return false
	if value.has("profile_id") and not Recycle.safe_id(value.profile_id): return false
	var version := int(value.schema_version)
	if value.has("profile_initialized") and not value.profile_initialized is bool:
		return false
	if not _number(value.get("revision")) or not value.get("profile") is Dictionary:
		return false
	var profile: Dictionary = value.profile
	if not _number(profile.get("permanent_gold")) or not _number(profile.get("total_runs")) \
		or not _relics(profile.get("discoveries")) or not _valid_result(profile.get("last_result"), version, int(profile.get("ruleset_version", 1))):
		return false
	var settings: Variant = profile.get("settings")
	if not settings is Dictionary or not settings.get("language") in ["zh_CN", "en"] \
		or not settings.get("reduced_fx") is bool or not settings.get("fullscreen") is bool:
		return false
	if settings.has("camera_shake") and not settings.camera_shake is bool: return false
	for key: String in COMBAT_SETTING_DEFAULTS:
		if settings.has(key) and not settings[key] is bool: return false
	if settings.has("controls") and not Controls.valid_overrides(settings.controls): return false
	for key: String in VOLUME_DEFAULTS:
		if settings.has(key) and not _number(settings[key], 1.0, false): return false
	if not value.has("active_run"):
		return false
	if not profile.last_result.is_empty():
		if version == 1 and int(profile.last_result.permanent_gold) != int(profile.permanent_gold):
			return false
		for id: String in profile.last_result.discoveries:
			if not id in profile.discoveries:
				return false
	if version >= 2 and not identical_progression and not _valid_progression(profile):
		return false
	if version >= 2 and not bool(value.get("profile_initialized", true)):
		# A settings-only file must not disguise earned assets or an active run.
		if value.active_run != null or not _settings_only(profile):
			return false
	if value.active_run == null:
		return true
	if not value.active_run is Dictionary: return false
	if not SkillProgress.valid_run_skills(value.active_run, profile): return false
	if not _valid_receipt(value.active_run, version) or value.active_run.id == profile.last_result.get("run_id", ""): return false
	if int(value.active_run.get("ruleset_version", 1)) != int(profile.get("ruleset_version", 1)): return false
	if value.active_run.has("expedition"):
		return version == 3 and Expedition.valid(value.active_run, profile)
	if value.active_run.has("pending_research_materials"):
		if int(profile.get("ruleset_version", 1)) != 2 or not Loot.material_map_valid(value.active_run.pending_research_materials): return false
		var pending := {}
		for event: String in value.active_run.completed_reward_ids:
			var row: Variant = profile.get("progression_receipts", {}).get(event)
			if not row is Dictionary: return false
			if row.get("deferred_materials", false):
				for key: String in row.material_reward: pending[key] = int(pending.get(key, 0)) + int(row.material_reward[key])
		if not Loot.same(pending, value.active_run.pending_research_materials): return false
	return true

static func _unique_ids(value: Variant, maximum: int = 512) -> bool:
	if not value is Array or value.size() > maximum:
		return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not id is String or id.is_empty() or id.length() > 160 or seen.has(id):
			return false
		seen[id] = true
	return true

static func _allowed_ids(value: Variant, allowed: Array) -> bool:
	if not _unique_ids(value, allowed.size()):
		return false
	for id: String in value:
		if not id in allowed:
			return false
	return true

static func _valid_progression(profile: Dictionary) -> bool:
	if not SkillProgress.valid(profile): return false
	var version: Variant = profile.get("ruleset_version", 1)
	if not _number(version, 2) or int(version) < 1: return false
	var ruleset: int = int(version)
	if not Expedition.versions_valid(profile, ruleset, profile.has("numerical_migration")): return false
	if profile.has("numerical_migration") and not _valid_numerical_migration(profile): return false
	if profile.has("gold_pity"):
		if ruleset != 2 or not Loot.pity_valid(profile.gold_pity): return false
		for biome: String in ["B01", "B02", "B03", "B04"]:
			if not _number(profile.gold_pity.get(biome), 3): return false
	if ruleset == 2:
		if not _valid_v2_growth(profile): return false
	if profile.has("equipment_discoveries"):
		if not _unique_ids(profile.equipment_discoveries, ContentRegistry.equipment_ids(ruleset).size()): return false
		for eq: String in profile.equipment_discoveries:
			if ContentRegistry.equipment(eq, ruleset).is_empty(): return false
	if not profile.get("selected_hero") in HERO_IDS or not profile.get("hero_xp") is Dictionary:
		return false
	if profile.hero_xp.size() != HERO_IDS.size():
		return false
	for id: String in HERO_IDS:
		if not _number(profile.hero_xp.get(id), int(Progression.thresholds().back()) if ruleset == 2 else 3600):
			return false
	# A missing field is a valid early v2 document and is atomically normalized on load.
	if profile.has("branches") and not _valid_branches(profile.branches, profile.hero_xp, ruleset):
		return false
	if ruleset == 2:
		if not _valid_instance_equipment(profile): return false
	else:
		if not profile.get("equipment") is Dictionary or profile.equipment.size() > ContentRegistry.equipment_ids().size() \
			or not profile.get("loadout") is Dictionary or profile.loadout.size() != SLOTS.size():
			return false
		for id: Variant in profile.equipment:
			if not id is String or ContentRegistry.equipment(id).is_empty():
				return false
			var owned: Variant = profile.equipment[id]
			if not owned is Dictionary or not _number(owned.get("level"), Expedition.MAX_EQUIPMENT_LEVEL):
				return false
		for slot: String in SLOTS:
			var id: Variant = profile.loadout.get(slot)
			if not id is String or not profile.equipment.has(id) or ContentRegistry.equipment(id).get("slot") != slot:
				return false
		if profile.has("loadout_presets") and not _valid_loadout_presets(profile.loadout_presets): return false
	if not _allowed_ids(profile.get("bosses"), BOSS_IDS) \
		or not _allowed_ids(profile.get("tutorial_completed"), HERO_IDS) \
		or not profile.get("migration_id") in ["new_v2", "profile_v1_to_v2"]:
		return false
	var ledger: Variant = profile.get("applied_transactions")
	if not ledger is Dictionary or ledger.size() > MAX_TRANSACTIONS or not ledger.has("starter_grant_v1"):
		return false
	for id: Variant in ledger:
		if not id is String or id.is_empty() or id.length() > 160 or not ledger[id] is Dictionary:
			return false
		var entry: Dictionary = ledger[id]
		if id == "starter_grant_v1":
			if entry.get("kind") != "starter":
				return false
		elif not _valid_economy_receipt(entry):
			return false
	return true

## Explicit ruleset2 documents store identities, not one entry per template.
## Document byte limits bound storage; catalog size must not cap duplicates.
static func _valid_instance_equipment(profile: Dictionary) -> bool:
	if not profile.get("equipment") is Dictionary: return false
	if profile.has("hero_role_revision") and (profile.hero_role_revision != 1 or profile.hero_role_revision is bool): return false
	if profile.has("equipment_class_migration") and not ClassMigration.valid_marker(profile.equipment_class_migration): return false
	if not Forging.validate_profile(profile).is_empty(): return false
	if not Transactions.validate_ledger(profile.get("instance_transactions")): return false
	if not _number(profile.get("inventory_capacity", 0), MAX_NUMBER) or not Loot.pity_valid(profile.get("gold_pity", {})): return false
	if not profile.get("pending_claim_receipts", {}) is Dictionary: return false
	for operation: Variant in profile.get("pending_claim_receipts", {}):
		if not operation is String or operation.is_empty() or operation.length() > 160: return false
		var id: Variant = profile.pending_claim_receipts[operation]
		if not id is String: return false
		if not profile.equipment.has(id):
			if not Forging.is_retired(profile, id): return false
		elif profile.equipment[id].get("location") == "pending": return false
	for id: Variant in profile.equipment:
		if not id is String or id.is_empty() or id.length() > 160: return false
		var record: Variant = profile.equipment[id]
		if not record is Dictionary or record.get("instance_id") != id or not Instances.validate(record).is_empty(): return false
	if not _valid_instance_loadout(profile.get("loadout"), profile.equipment, str(profile.selected_hero),
		ContentRegistry.level_for_xp(int(profile.hero_xp[profile.selected_hero]), 2)): return false
	# Newly constructed values may say inventory before their first commit, but
	# an explicit equipped marker must point to the current active loadout.
	for id: String in profile.equipment:
		if profile.equipment[id].location == "equipped" and id not in profile.loadout.values(): return false
	var presets: Variant = profile.get("loadout_presets", {})
	if not presets is Dictionary or presets.size() > HERO_IDS.size(): return false
	for hero: Variant in presets:
		if hero not in HERO_IDS or not _valid_instance_loadout(presets[hero], profile.equipment, hero,
			ContentRegistry.level_for_xp(int(profile.hero_xp[hero]), 2)): return false
	return true

static func _valid_instance_loadout(value: Variant, equipment: Dictionary, hero: String, level: int) -> bool:
	var slots: Array = ContentRegistry.slots(2)
	if not value is Dictionary or value.size() != slots.size(): return false
	var seen: Dictionary = {}
	for slot: String in slots:
		var id: Variant = value.get(slot)
		if not id is String: return false
		if id.is_empty(): continue
		if seen.has(id) or not equipment.has(id): return false
		var record: Dictionary = equipment[id]
		if record.get("location") not in ["inventory", "equipped"] or not Instances.can_equip(record, hero, level): return false
		if ContentRegistry.equipment(str(record.template_id), 2).get("slot") != slot: return false
		seen[id] = true
	return true

static func _valid_loadout_presets(value: Variant) -> bool:
	if not value is Dictionary or value.size() > HERO_IDS.size(): return false
	for hero: Variant in value:
		if hero not in HERO_IDS or not value[hero] is Dictionary or value[hero].size() != SLOTS.size(): return false
		for slot: String in SLOTS:
			var id: Variant = value[hero].get(slot)
			if not id is String: return false
			# Presets reference the shared inventory; missing/sold entries may be empty.
			# Known stale IDs are safe to load and are resolved by the controller.
			if not id.is_empty() and ContentRegistry.equipment(id).get("slot") != slot: return false
	return true

static func _valid_economy_receipt(entry: Dictionary) -> bool:
	# Versionless receipts belong to the frozen original economy, never today's catalog.
	var version: Variant = entry.get("economy_version", 1)
	if not _number(version, ECONOMY_RULES_VERSION) or not Economy.supported(int(version)): return false
	var rules := int(version)
	if not _number(entry.get("price")) or not entry.get("item") is String: return false
	match entry.get("kind"):
		"purchase_set":
			var pieces := Economy.set_items(entry.item, rules)
			if pieces.size() != SLOTS.size() or not _unique_ids(entry.get("items"), SLOTS.size()) or entry.items.is_empty(): return false
			var paid := 0
			for eq_id: String in entry.items:
				if not eq_id in pieces: return false
				paid += Economy.item_price(eq_id, rules) * 9 / 10
			return paid == int(entry.price)
		"sale":
			if not entry.get("items") is Dictionary or entry.items.is_empty() or entry.items.size() > Economy.item_count(rules): return false
			var sold_ids: Array = entry.items.keys()
			for id: Variant in sold_ids:
				if not id is String: return false
			sold_ids.sort()
			if entry.item != ",".join(sold_ids): return false
			var proceeds := 0
			for eq_id: String in sold_ids:
				var record: Variant = entry.items[eq_id]
				if not record is Dictionary or not _number(record.get("level"), Economy.maximum_level(rules)): return false
				var worth := Economy.sell_price(eq_id, int(record.level), rules)
				if worth <= 0 or record.get("price") != worth: return false
				proceeds += worth
			return proceeds == int(entry.price)
		"purchase":
			return _number(entry.get("level"), 0) and Economy.item_price(entry.item, rules) == int(entry.price)
		"upgrade":
			return Economy.item_price(entry.item, rules) >= 0 and _number(entry.get("level"), Economy.maximum_level(rules)) \
				and Economy.upgrade_price(int(entry.level), rules) == int(entry.price)
	return false

static func equipment_sell_price(eq_id: String, level: int) -> int:
	var item := ContentRegistry.equipment(eq_id)
	if item.is_empty() or level < 0 or level > Expedition.MAX_EQUIPMENT_LEVEL: return 0
	var worth := int(item.price) / 4
	for index in range(level): worth += ContentRegistry.UPGRADE_COSTS[index] / 5
	return worth

static func _valid_branches(value: Variant, hero_xp: Dictionary, ruleset: int = 1) -> bool:
	if not value is Dictionary or value.size() != HERO_IDS.size():
		return false
	for id: String in HERO_IDS:
		var choices: Variant = value.get(id)
		if not choices is Dictionary or choices.size() != 2:
			return false
		var level := ContentRegistry.level_for_xp(int(hero_xp[id]), ruleset)
		for slot: String in ["q", "ultimate"]:
			if not choices.get(slot) in ["", "A", "B"]:
				return false
			if choices[slot] != "" and level < (18 if slot == "q" else 20):
				return false
	return true

static func _settings_only(profile: Dictionary) -> bool:
	if int(profile.get("ruleset_version", 1)) == 2:
		var blank := NativeProfile.fresh(fresh_profile())
		blank.settings = profile.settings.duplicate(true)
		if not profile.has("skill_system_version"):
			for field: String in SkillProgress.fresh_fields(): blank.erase(field)
		return _serialize(profile) == _serialize(blank)
	# Structural validation is retained for preserving obsolete source bytes.
	if int(profile.get("ruleset_version", 1)) != 1: return false
	if profile.has("skill_system_version"):
		for field: String in SkillProgress.fresh_fields():
			if profile[field] != SkillProgress.fresh_fields()[field]: return false
	if not profile.get("equipment_discoveries", []).is_empty(): return false
	if int(profile.permanent_gold) != 0 or int(profile.total_runs) != 0 or not profile.last_result.is_empty() \
		or not profile.discoveries.is_empty() or not profile.bosses.is_empty() or not profile.tutorial_completed.is_empty() \
		or profile.selected_hero != "CH01" or profile.migration_id != "new_v2" \
		or profile.applied_transactions.size() != 1 or profile.equipment.size() != STARTER_IDS.size() \
		or profile.loadout != fresh_profile().loadout:
		return false
	for id: String in HERO_IDS:
		if int(profile.hero_xp[id]) != 0:
			return false
	for id: String in STARTER_IDS:
		if not profile.equipment.has(id) or int(profile.equipment[id].level) != 0:
			return false
	# _valid_branches already excludes nonempty choices at level one.
	return true

static func _valid_v2_growth(profile: Dictionary) -> bool:
	for field in ["talents", "research_xp", "materials", "progression_receipts"]:
		if not profile.get(field, {}) is Dictionary: return false
	if not profile.get("hero_xp") is Dictionary: return false
	for hero: Variant in profile.get("talents", {}):
		if hero not in HERO_IDS: return false
		if not Progression.valid_talents(profile.talents[hero], Progression.level_for_xp(int(profile.hero_xp.get(hero, 0)))): return false
	for hero: Variant in profile.get("research_xp", {}):
		if hero not in HERO_IDS or not _number(profile.research_xp[hero], 359): return false
	for material: Variant in profile.get("materials", {}):
		if not Transactions._material_id(material) or not _number(profile.materials[material], MAX_NUMBER): return false
	var receipts: Dictionary = profile.get("progression_receipts", {})
	if receipts.size() > 100000: return false
	for event: Variant in receipts:
		if not event is String or event.is_empty() or event.length() > 160: return false
		var row: Variant = receipts[event]
		if not row is Dictionary or row.get("hero") not in HERO_IDS or not _number(row.get("amount"), 3600) or row.get("race") not in ["B01", "B02", "B03", "B04", "B05", "B06", "B10"]: return false
		if row.has("deferred_materials"):
			if row.deferred_materials != true or not _number(row.get("research_rewards"), 11) or not Loot.material_map_valid(row.get("material_reward")): return false
			var expected := {} if int(row.research_rewards) == 0 else {"forge":int(row.research_rewards) * 4,"race:" + str(row.race):int(row.research_rewards)}
			if not Loot.same(row.material_reward, expected): return false
	return true

static func _valid_numerical_migration(profile: Dictionary) -> bool:
	if profile.get("ruleset_version") != 2: return false
	var migration: Variant = profile.numerical_migration
	if not migration is Dictionary or not Expedition.json_tree(migration) or migration.size() != 4 or migration.get("version") != 1: return false
	var event: Variant = migration.get("event_id")
	if not event is String or not event.begins_with("migration:") or event.length() <= 10 or event.length() > 120: return false
	var original: Variant = migration.get("original")
	var identities: Variant = migration.get("template_instance_ids")
	if not original is Dictionary or not original.has_all(["hero_xp", "equipment", "loadout"]) or original.size() not in [3, 4] or not identities is Dictionary: return false
	if original.size() == 4 and not original.has("loadout_presets"): return false
	if not original.hero_xp is Dictionary or original.hero_xp.size() != HERO_IDS.size() or not original.equipment is Dictionary or identities.size() != original.equipment.size(): return false
	for hero: String in HERO_IDS:
		if not _number(original.hero_xp.get(hero), 3600): return false
	for template: Variant in original.equipment:
		if not template is String or ContentRegistry.equipment(template).is_empty() or not original.equipment[template] is Dictionary or not _number(original.equipment[template].get("level"), 5): return false
		if identities.get(template) != event + ":" + template: return false
	if not original.loadout is Dictionary or original.loadout.size() != SLOTS.size(): return false
	for slot: String in SLOTS:
		var template: Variant = original.loadout.get(slot)
		if not template is String or not original.equipment.has(template) or ContentRegistry.equipment(template).get("slot") != slot: return false
	if original.has("loadout_presets") and not _valid_loadout_presets(original.loadout_presets): return false
	return true
