class_name ProfileStore
extends RefCounted
## One document commits rewards, discoveries, and active-run clearing together.
## A flushed newer temporary document is a recoverable commit intent.

const SCHEMA_VERSION := 1
const MAX_NUMBER := 1_000_000_000_000
const RELIC_IDS := ["split", "ember", "arc"]
const OUTCOMES := ["extracted", "death", "abandoned"]

var path: String
var last_error: String = ""
var warning: String = ""
var has_profile: bool = false
var unresolved_error: bool:
	get:
		return _blocked
var _current: Dictionary = {}
var _blocked: bool = false

func _init(save_path: String = "user://profile.json") -> void:
	path = save_path

static func fresh_profile() -> Dictionary:
	return {
		"permanent_gold": 0, "discoveries": [], "total_runs": 0,
		"last_result": {},
		"settings": {"language": "zh_CN", "reduced_fx": false, "fullscreen": false},
	}

func load_document() -> Dictionary:
	last_error = ""
	warning = ""
	_current = {}
	_blocked = false
	has_profile = false
	var best_path := ""
	# All candidates contain whole transactions; never merge fields across files.
	for candidate: String in [path, path + ".tmp", path + ".bak", path + ".bak.tmp"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			_blocked = true
			last_error = "STORAGE_READ_FAILED"
			continue
		var parser := JSON.new()
		var parsed: Variant = null
		if file.get_length() <= 1_048_576 and parser.parse(file.get_as_text()) == OK:
			parsed = parser.data
		file.close()
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
	if _blocked:
		return {}
	if _current.is_empty():
		if not warning.is_empty():
			last_error = "STORAGE_NO_VALID_PROFILE"
			_blocked = true
		return {}
	has_profile = true
	if best_path != path:
		warning = "STORAGE_RECOVERED"
	return _current.duplicate(true)

func save_document(profile: Dictionary, active_run: Variant = null) -> bool:
	last_error = ""
	if _blocked:
		last_error = "STORAGE_NO_VALID_PROFILE"
		return false
	var document := {
		"schema_version": SCHEMA_VERSION,
		"revision": int(_current.get("revision", 0)) + 1,
		"profile": profile.duplicate(true),
		"active_run": active_run.duplicate(true) if active_run is Dictionary else null,
	}
	if not _valid_document(document):
		last_error = "STORAGE_INVALID_DATA"
		return false
	var directory := ProjectSettings.globalize_path(path).get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	# Preserve the last acknowledged whole transaction before replacing a candidate.
	if not _current.is_empty():
		if not _write_document(path + ".bak.tmp", _current):
			return false
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			last_error = "STORAGE_REPLACE_FAILED"
			return false
	if not _write_document(path + ".tmp", document):
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		last_error = "STORAGE_REPLACE_FAILED"
		return false
	_current = document
	has_profile = true
	return true

func _write_document(destination: String, document: Dictionary) -> bool:
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		last_error = "STORAGE_WRITE_FAILED"
		return false
	file.store_string(JSON.stringify(document, "\t"))
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

static func _valid_receipt(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not value.get("id") is String or value.id.is_empty() or value.id.length() > 80:
		return false
	return _number(value.get("gold")) and _relics(value.get("discoveries")) \
		and _number(value.get("shots")) and _number(value.get("kills")) \
		and _number(value.get("elapsed"), MAX_NUMBER, false)

static func _valid_result(value: Variant) -> bool:
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
	var expected_retained := int(value.collected) if value.outcome == "extracted" else Balance.death_keep(int(value.collected))
	return int(value.retained) == expected_retained and int(value.retained) + int(value.lost) == int(value.collected) \
		and _relics(value.get("discoveries")) and _number(value.get("elapsed"), MAX_NUMBER, false)

static func _valid_document(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema_version") != SCHEMA_VERSION:
		return false
	if not _number(value.get("revision")) or not value.get("profile") is Dictionary:
		return false
	var profile: Dictionary = value.profile
	if not _number(profile.get("permanent_gold")) or not _number(profile.get("total_runs")) \
		or not _relics(profile.get("discoveries")) or not _valid_result(profile.get("last_result")):
		return false
	var settings: Variant = profile.get("settings")
	if not settings is Dictionary or not settings.get("language") in ["zh_CN", "en"] \
		or not settings.get("reduced_fx") is bool or not settings.get("fullscreen") is bool:
		return false
	if not value.has("active_run"):
		return false
	if not profile.last_result.is_empty():
		if int(profile.last_result.permanent_gold) != int(profile.permanent_gold):
			return false
		for id: String in profile.last_result.discoveries:
			if not id in profile.discoveries:
				return false
	if value.active_run == null:
		return true
	return _valid_receipt(value.active_run) and value.active_run.id != profile.last_result.get("run_id", "")
