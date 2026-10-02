extends RefCounted
## The sealed index is the single atomic commit point for slot switches.
## Archives contain complete byte-for-byte candidates, never merged economy fields.
## Only identifiers generated here become path components; metadata contains no paths.
const RETENTION_SECONDS := 7 * 24 * 60 * 60
const SUFFIXES := ["", ".tmp", ".bak", ".bak.tmp", ".v1.bak"]
const MAX_BYTES := 256 * 1024 * 1024
var root_path: String
var clock: Callable
var document_validator: Callable
var last_error := ""
var _identity := ""
# Isolated failure injection, never configured by the production controller.
var fail_stage := ""
var max_write_bytes := MAX_BYTES

func _init(profile_path: String, time_source: Callable = Callable()) -> void:
	root_path = profile_path
	clock = time_source

func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())

static func safe_id(value: Variant) -> bool:
	if not value is String or value.length() != 32: return false
	for character: String in value:
		if character not in "0123456789abcdef": return false
	return true

func folder() -> String:
	return root_path + ".recycle"

func _slot_id() -> String:
	if _identity.is_empty(): _identity = _new_id()
	return _identity

func active_path(state: Dictionary) -> String:
	var generation: String = state.get("active_generation", "")
	return root_path if generation.is_empty() else folder() + "/slots/" + generation + "/profile.json"

func _is_link(value: String) -> bool:
	var absolute := ProjectSettings.globalize_path(value)
	var parent := DirAccess.open(absolute.get_base_dir())
	return parent != null and parent.is_link(absolute.get_file())

func _safe_storage() -> bool:
	for directory: String in [folder(), folder()+"/slots", folder()+"/entries"]:
		if FileAccess.file_exists(directory):
			last_error = "STORAGE_RECYCLE_INVALID"
			return false
	for candidate: String in [folder(), folder()+"/slots", folder()+"/entries", folder()+"/index.json"]:
		if _is_link(candidate):
			last_error = "STORAGE_RECYCLE_INVALID"
			return false
	return true

func read_state() -> Dictionary:
	last_error = ""
	if not _safe_storage(): return {}
	var filename := folder() + "/index.json"
	if not FileAccess.file_exists(filename):
		if DirAccess.dir_exists_absolute(filename):
			last_error = "STORAGE_RECYCLE_INVALID"
			return {}
		if DirAccess.dir_exists_absolute(folder()+"/slots"):
			last_error = "STORAGE_RECYCLE_INVALID"
			return {}
		return {"version": 1, "slot_id": _slot_id(), "active_generation": "", "last_seen": 0, "entries": {}}
	var state := _read_sealed(filename)
	if state.is_empty() or state.get("version") != 1 or not safe_id(state.get("slot_id")) \
		or not state.get("active_generation") is String or not state.get("entries") is Dictionary \
		or not _timestamp(state.get("last_seen")):
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	_identity = str(state.slot_id)
	if not state.active_generation.is_empty() and not safe_id(state.active_generation):
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	if _is_link(active_path(state).get_base_dir()) or _is_link(active_path(state)):
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	for entry_id: Variant in state.entries:
		if not safe_id(entry_id) or not _valid_entry(state.entries[entry_id]):
			last_error = "STORAGE_RECYCLE_INVALID"
			return {}
	return state

func _timestamp(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value == floor(value) and value < 9_000_000_000_000

func _valid_entry(entry: Variant) -> bool:
	return entry is Dictionary and safe_id(entry.get("profile_id")) \
		and _timestamp(entry.get("deleted_at")) and int(entry.deleted_at) > 0 \
		and _timestamp(entry.get("expires_at")) and int(entry.expires_at) == int(entry.deleted_at) + RETENTION_SECONDS \
		and entry.get("state") in ["deleted", "restored", "purged"] \
		and entry.get("archive_hash") is String and entry.archive_hash.length() == 64 \
		and entry.get("source_generation") is String \
		and (entry.source_generation.is_empty() or safe_id(entry.source_generation))

func list_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state := read_state()
	if state.is_empty(): return result
	var current_time := now()
	for entry_id: String in state.entries:
		var metadata: Dictionary = state.entries[entry_id]
		if metadata.state != "deleted": continue
		var row := metadata.duplicate(true)
		row.entry_id = entry_id
		row.clock_rollback = current_time < int(state.last_seen) or current_time < int(row.deleted_at)
		row.remaining_seconds = maxi(0, int(row.expires_at) - current_time)
		row.expired = not row.clock_rollback and current_time >= int(row.expires_at)
		var archive := _archive(entry_id, metadata)
		row.valid = not archive.is_empty()
		if row.valid:
			var snapshot: Variant = JSON.parse_string(Marshalls.base64_to_raw(archive.snapshot).get_string_from_utf8())
			row.gold = int(snapshot.get("profile", {}).get("permanent_gold", 0)) if snapshot is Dictionary else 0
			row.hero = str(snapshot.get("profile", {}).get("selected_hero", "CH01")) if snapshot is Dictionary else "CH01"
		result.append(row)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.deleted_at) > int(b.deleted_at))
	return result

func archive_and_switch(snapshot: PackedByteArray, profile_id: String, replacement: PackedByteArray, expected_generation: String) -> bool:
	var state := read_state()
	if state.is_empty(): return false
	if not FileAccess.file_exists(folder()+"/index.json"):
		if not _atomic_write(folder()+"/index.json", _seal(state), "bootstrap"): return false
		state = read_state()
		if state.is_empty(): return false
	if state.active_generation != expected_generation:
		last_error = "STORAGE_RECYCLE_CHANGED"
		return false
	var current_time := now()
	if current_time <= 0 or current_time < int(state.last_seen):
		last_error = "STORAGE_RECYCLE_CLOCK"
		return false
	var entry_id := _new_id()
	var generation := _new_id()
	if not _unused(entry_id, generation): return false
	var files := {}
	var source := active_path(state)
	for suffix: String in SUFFIXES:
		var filename := source + suffix
		if DirAccess.dir_exists_absolute(filename) or _is_link(filename):
			last_error = "STORAGE_RECYCLE_INVALID"
			return false
		if not FileAccess.file_exists(filename): continue
		var bytes := _read_bytes(filename)
		if not last_error.is_empty(): return false
		files[suffix] = {"bytes": Marshalls.raw_to_base64(bytes), "sha256": _hash(bytes)}
	if files.is_empty() or snapshot.is_empty() or not safe_id(profile_id):
		last_error = "STORAGE_RECYCLE_INVALID"
		return false
	var metadata := {"profile_id": profile_id, "deleted_at": current_time,
		"expires_at": current_time + RETENTION_SECONDS, "source_generation": expected_generation, "state": "deleted"}
	var archive := {"version": 1, "entry_id": entry_id, "slot_id": _slot_id(),
		"profile_id": profile_id, "deleted_at": current_time, "expires_at": current_time + RETENTION_SECONDS,
		"source_generation": expected_generation, "snapshot": Marshalls.raw_to_base64(snapshot), "snapshot_hash": _hash(snapshot), "files": files}
	var archive_bytes := _seal(archive)
	if not _atomic_write(_archive_path(entry_id), archive_bytes, "archive"): return false
	metadata.archive_hash = _hash(archive_bytes)
	var destination := folder()+"/slots/"+generation+"/profile.json"
	if not _atomic_write(destination, replacement, "replacement"): return false
	var next := state.duplicate(true)
	next.entries[entry_id] = metadata
	next.active_generation = generation
	next.last_seen = current_time
	if not _commit(state, next): return false
	# Only exact copied candidates are retired. Unrelated migration/corrupt/manual
	# backups are never scanned. A crash here leaves harmless retained duplicates.
	_retire_source(metadata, archive)
	return true

func restore(entry_id: String, replacement: PackedByteArray, expected_generation: String) -> bool:
	var state := read_state()
	if state.is_empty(): return false
	if state.active_generation != expected_generation:
		last_error = "STORAGE_RECYCLE_CHANGED"
		return false
	var archive := get_archive(entry_id, state)
	if archive.is_empty(): return false
	var generation := _new_id()
	if not _unused("", generation): return false
	if not _atomic_write(folder()+"/slots/"+generation+"/profile.json", replacement, "replacement"): return false
	var next := state.duplicate(true)
	next.active_generation = generation
	next.entries[entry_id].state = "restored"
	next.last_seen = maxi(now(), int(state.last_seen))
	return _commit(state, next)

func get_archive(entry_id: String, state: Dictionary = {}) -> Dictionary:
	if state.is_empty(): state = read_state()
	if state.is_empty(): return {}
	if not safe_id(entry_id) or not state.entries.has(entry_id) or state.entries[entry_id].state != "deleted":
		last_error = "STORAGE_RECYCLE_UNAVAILABLE"
		return {}
	var entry: Dictionary = state.entries[entry_id]
	# Clock rollback always preserves recovery; it must never accelerate expiry.
	if now() >= int(entry.expires_at) and now() >= int(state.last_seen):
		last_error = "STORAGE_RECYCLE_EXPIRED"
		return {}
	return _archive(entry_id, entry)

func cleanup_expired() -> bool:
	var state := read_state()
	if state.is_empty(): return false
	if state.active_generation.is_empty(): return true
	var current_time := now()
	if current_time < int(state.last_seen):
		last_error = "STORAGE_RECYCLE_CLOCK"
		return false
	var next := state.duplicate(true)
	var removable := {}
	for entry_id: String in state.entries:
		var metadata: Dictionary = state.entries[entry_id]
		if current_time < int(metadata.expires_at): continue
		if metadata.state == "purged" and not FileAccess.file_exists(_archive_path(entry_id)): continue
		var archive := _archive(entry_id, metadata)
		if archive.is_empty(): continue # Invalid evidence never authorizes a purge.
		removable[entry_id] = archive
		next.entries[entry_id].state = "purged"
	next.last_seen = current_time
	if not _commit(state, next): return false
	for entry_id: String in removable:
		var metadata: Dictionary = state.entries[entry_id]
		# Never touch a source that is currently active, even with forged metadata.
		if metadata.source_generation != state.active_generation:
			if not _retire_source(metadata, removable[entry_id]):
				last_error = "STORAGE_RECYCLE_CLEANUP_FAILED"
				return false
		if DirAccess.remove_absolute(_archive_path(entry_id)) != OK:
			last_error = "STORAGE_RECYCLE_CLEANUP_FAILED"
			return false
	return true

func _archive_path(entry_id: String) -> String:
	return folder()+"/entries/"+entry_id+".json"

func _archive(entry_id: String, metadata: Dictionary) -> Dictionary:
	var filename := _archive_path(entry_id)
	if _is_link(filename):
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	var bytes := _read_bytes(filename)
	if bytes.is_empty() or _hash(bytes) != metadata.archive_hash:
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	var archive := _unseal(bytes)
	if archive.get("version") != 1 or archive.get("entry_id") != entry_id or archive.get("slot_id") != _slot_id() \
		or archive.get("profile_id") != metadata.profile_id or archive.get("deleted_at") != metadata.deleted_at \
		or archive.get("expires_at") != metadata.expires_at or archive.get("source_generation") != metadata.source_generation or not archive.get("snapshot") is String \
		or not archive.get("files") is Dictionary or archive.files.is_empty() \
		or _hash(Marshalls.base64_to_raw(archive.snapshot)) != archive.get("snapshot_hash"):
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	var snapshot: Variant = JSON.parse_string(Marshalls.base64_to_raw(archive.snapshot).get_string_from_utf8())
	if not document_validator.is_valid() or not bool(document_validator.call(snapshot)):
		last_error = "STORAGE_RECYCLE_INVALID"
		return {}
	for suffix: Variant in archive.files:
		var file: Variant = archive.files[suffix]
		if suffix not in SUFFIXES or not file is Dictionary or not file.get("bytes") is String \
			or _hash(Marshalls.base64_to_raw(file.bytes)) != file.get("sha256"):
			last_error = "STORAGE_RECYCLE_INVALID"
			return {}
	return archive

func _retire_source(metadata: Dictionary, archive: Dictionary) -> bool:
	var source := root_path if metadata.source_generation.is_empty() else folder()+"/slots/"+str(metadata.source_generation)+"/profile.json"
	if _is_link(source.get_base_dir()): return false
	for suffix: String in archive.files:
		var filename := source + suffix
		if _is_link(filename) or not FileAccess.file_exists(filename): continue
		var bytes := _read_bytes(filename)
		if _hash(bytes) == archive.files[suffix].sha256 and DirAccess.remove_absolute(filename) != OK: return false
	return true

func _unused(entry_id: String, generation: String) -> bool:
	if (not entry_id.is_empty() and (FileAccess.file_exists(_archive_path(entry_id)) or DirAccess.dir_exists_absolute(_archive_path(entry_id)))) \
		or DirAccess.dir_exists_absolute(folder()+"/slots/"+generation):
		last_error = "STORAGE_RECYCLE_COLLISION"
		return false
	return true

func _new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _commit(previous: Dictionary, next: Dictionary) -> bool:
	# Repeated clicks/stale store instances cannot commit over a changed index.
	var observed := read_state()
	if observed != previous:
		last_error = "STORAGE_RECYCLE_CHANGED"
		return false
	return _atomic_write(folder()+"/index.json", _seal(next), "index")

func _atomic_write(filename: String, bytes: PackedByteArray, stage: String) -> bool:
	if bytes.size() > mini(MAX_BYTES, max_write_bytes):
		last_error = "STORAGE_CAPACITY_EXCEEDED"
		return false
	if fail_stage == stage or _is_link(filename) or DirAccess.make_dir_recursive_absolute(filename.get_base_dir()) != OK:
		last_error = "STORAGE_RECYCLE_WRITE_FAILED"
		return false
	var temporary := filename + ".pending_" + _new_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "STORAGE_RECYCLE_WRITE_FAILED"
		return false
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or _read_bytes(temporary) != bytes or fail_stage == stage + "_rename":
		last_error = "STORAGE_RECYCLE_WRITE_FAILED"
		return false
	if DirAccess.rename_absolute(temporary, filename) != OK:
		last_error = "STORAGE_RECYCLE_WRITE_FAILED"
		return false
	return true

func _read_bytes(filename: String) -> PackedByteArray:
	var file := FileAccess.open(filename, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		last_error = "STORAGE_RECYCLE_INVALID"
		return PackedByteArray()
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or error != OK:
		last_error = "STORAGE_RECYCLE_INVALID"
		return PackedByteArray()
	return bytes

static func _hash(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

static func _seal(value: Dictionary) -> PackedByteArray:
	var payload := JSON.stringify(value, "", true, true)
	return JSON.stringify({"payload": payload, "sha256": payload.sha256_text()}, "", true, true).to_utf8_buffer()

func _read_sealed(filename: String) -> Dictionary:
	return _unseal(_read_bytes(filename))

static func _unseal(bytes: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("payload") is String or parsed.get("sha256") != parsed.payload.sha256_text(): return {}
	var value: Variant = JSON.parse_string(parsed.payload)
	return value if value is Dictionary else {}
