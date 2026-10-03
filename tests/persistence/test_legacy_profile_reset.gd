extends SceneTree

const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Native = preload("res://scripts/domain/equipment/numerical_profile.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func same(a: Dictionary, b: Dictionary) -> bool:
	return Store._serialize(a) == Store._serialize(b)

func write(path: String, value: Dictionary) -> PackedByteArray:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var bytes := Store._serialize(value)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return bytes

func document(current: bool, revision: int = 1, schema: int = 3) -> Dictionary:
	var profile := Native.fresh(Store.fresh_profile()) if current else Store.fresh_profile()
	profile.permanent_gold = 42
	return {"schema_version": schema, "revision": revision, "profile_initialized": true,
		"profile": profile, "active_run": null}

func _initialize() -> void:
	for schema: int in [1, 2, 3]:
		var path := "user://test_legacy_reset/schema_%s/profile.json" % schema
		var old := document(false, 9, schema)
		var before := write(path, old)
		check(Store._valid_document(old), "legacy fixture valid %s" % schema)
		var store := Store.new(path)
		var result := store.load_document()
		check(not result.is_empty() and store.warning == "STORAGE_LEGACY_RESET", "old format reset %s" % schema)
		if result.is_empty(): continue
		check(result.schema_version == 3 and result.profile.ruleset_version == 2 and result.active_run == null, "current format %s" % schema)
		check(result.profile.permanent_gold == 0 and result.profile.total_runs == 0 and result.profile.equipment.size() == 12, "fresh progress %s" % schema)
		var entries := store.recycle_entries()
		check(entries.size() == 1 and entries[0].valid, "raw archive valid %s" % schema)
		var archive := store._recycle().get_archive(entries[0].entry_id)
		check(Marshalls.base64_to_raw(archive.files[""].bytes) == before, "original bytes retained %s" % schema)
		var second := Store.new(path)
		var reloaded := second.load_document()
		check(same(reloaded, result) and second.warning != "STORAGE_LEGACY_RESET" and second.recycle_entries().size() == 1, "reset happens once %s" % schema)
	var current_path := "user://test_legacy_reset/current/profile.json"
	var current := document(true, 3)
	var current_bytes := write(current_path, current)
	var current_store := Store.new(current_path)
	check(same(current_store.load_document().profile, current.profile), "current progress continues")
	check(FileAccess.get_file_as_bytes(current_path) == current_bytes and current_store.recycle_entries().is_empty(), "current read does not reset or rewrite")
	var recovery_path := "user://test_legacy_reset/recovery/profile.json"
	write(recovery_path, document(false, 100))
	write(recovery_path + ".bak", current)
	var recovered := Store.new(recovery_path)
	check(same(recovered.load_document().profile, current.profile) and recovered.warning == "STORAGE_RECOVERED", "current backup wins over newer obsolete primary")
	check(recovered.save_document(current.profile), "obsolete primary cannot block current save")
	for stage: String in ["archive", "replacement", "index"]:
		var path := "user://test_legacy_reset/fail_%s/profile.json" % stage
		var before := write(path, document(false))
		var store := Store.new(path)
		store.recycle_fail_stage = stage
		check(store.load_document().is_empty() and store.unresolved_error, "failure blocks reset " + stage)
		check(FileAccess.get_file_as_bytes(path) == before, "failure preserves old bytes " + stage)
		var retry := Store.new(path)
		check(not retry.load_document().is_empty() and retry.warning == "STORAGE_LEGACY_RESET", "failed reset retry " + stage)
	var corrupt_path := "user://test_legacy_reset/corrupt/profile.json"
	var invalid := document(false)
	invalid.profile.permanent_gold = -1
	var corrupt_bytes := write(corrupt_path, invalid)
	var corrupt := Store.new(corrupt_path)
	check(corrupt.load_document().is_empty() and corrupt.unresolved_error, "corruption is not treated as obsolete format")
	check(FileAccess.get_file_as_bytes(corrupt_path) == corrupt_bytes, "corrupt original retained")
	print("Legacy profile reset: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
