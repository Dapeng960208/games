extends RefCounted
## One writer per logical save path, including normal saves and recycle cleanup.
## mkdir is the cross-process atomic exclusion primitive. Unknown locks are kept.
static var _held: Dictionary = {}
var _directory := ""
var _token := ""

static func acquire(save_path: String) -> RefCounted:
	var directory := ProjectSettings.globalize_path(save_path)+".writer-lock"
	if _held.has(directory):
		var existing: Variant = _held[directory].get_ref()
		if existing != null: return existing
		_held.erase(directory)
	var parent := DirAccess.open(directory.get_base_dir())
	if parent != null and parent.is_link(directory.get_file()): return null
	if FileAccess.file_exists(AssetCatalog.resolve(directory)): return null
	if DirAccess.make_dir_recursive_absolute(directory.get_base_dir()) != OK: return null
	if DirAccess.dir_exists_absolute(directory):
		# Never infer a stale lock from age alone. A live/reused PID, invalid owner,
		# missing owner or extra files is uncertain and remains locked.
		var owner := _read_owner(directory)
		if owner.is_empty() or not _definitely_dead(int(owner.pid)): return null
		# Atomically claim the exact dead owner's uniquely named file. Competing
		# reclaimers cannot move a later owner's file because its token differs.
		var retired := directory+".retired_"+str(owner.token)
		if FileAccess.file_exists(AssetCatalog.resolve(retired)) or DirAccess.dir_exists_absolute(retired): return null
		if DirAccess.rename_absolute(directory+"/owner_"+str(owner.token)+".json",retired) != OK: return null
		if DirAccess.remove_absolute(directory) != OK: return null
		DirAccess.remove_absolute(retired)
	if DirAccess.make_dir_absolute(directory) != OK: return null
	var lease = load(AssetCatalog.resolve("res://scripts/infrastructure/persistence/profile_save_lease.gd")).new()
	lease._directory=directory
	lease._token=Crypto.new().generate_random_bytes(16).hex_encode()
	var owner := {"pid": OS.get_process_id(), "token": lease._token}
	var bytes := JSON.stringify(owner).to_utf8_buffer()
	var file := FileAccess.open(AssetCatalog.resolve(directory+"/owner_"+str(lease._token)+".json"),FileAccess.WRITE)
	if file == null:
		DirAccess.remove_absolute(directory)
		return null
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(AssetCatalog.resolve(directory+"/owner_"+str(lease._token)+".json")) != bytes:
		# Only our newly acquired lock is touched, never profile data.
		DirAccess.remove_absolute(directory+"/owner_"+str(lease._token)+".json")
		DirAccess.remove_absolute(directory)
		return null
	_held[directory]=weakref(lease)
	return lease

static func _definitely_dead(pid: int) -> bool:
	if pid==OS.get_process_id(): return false
	if OS.get_name()=="Linux":
		# Godot's Unix is_process_running can only reliably wait on its own
		# children on some engine versions. procfs checks any same-user owner.
		if not FileAccess.file_exists(AssetCatalog.resolve("/proc/self/stat")): return false
		return not DirAccess.dir_exists_absolute("/proc/"+str(pid))
	if OS.get_name()=="Windows":
		var system_root := OS.get_environment("SystemRoot")
		if system_root.is_empty(): return false
		var executable := system_root+"/System32/WindowsPowerShell/v1.0/powershell.exe"
		if not FileAccess.file_exists(AssetCatalog.resolve(executable)): return false
		var output: Array = []
		var command := "try { $null = Get-Process -Id "+str(pid)+" -ErrorAction Stop; exit 0 } catch { if ($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId*') { exit 3 }; exit 4 }"
		return OS.execute(executable,["-NoProfile","-NonInteractive","-Command",command],output,true)==3
	# An unsupported process-query platform is never permission to steal a lock.
	return false

static func _read_owner(directory: String) -> Dictionary:
	var folder := DirAccess.open(directory)
	if folder == null: return {}
	var files := folder.get_files()
	if files.size()!=1 or not folder.get_directories().is_empty(): return {}
	var filename: String = files[0]
	if not filename.begins_with("owner_") or not filename.ends_with(".json") or folder.is_link(filename): return {}
	var file := FileAccess.open(AssetCatalog.resolve(directory+"/"+filename),FileAccess.READ)
	if file == null or file.get_length()>1024: return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary or value.size()!=2 or not value.get("token") is String or value.token.length()!=32: return {}
	if filename != "owner_"+str(value.token)+".json": return {}
	if not (value.get("pid") is int or value.get("pid") is float) or not is_finite(value.pid) or value.pid<=0 or value.pid!=floor(value.pid) or value.pid>2147483647: return {}
	for character: String in value.token:
		if character not in "0123456789abcdef": return {}
	return value

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _directory.is_empty(): return
	var owner := _read_owner(_directory)
	if owner.get("token") == _token and int(owner.get("pid",0)) == OS.get_process_id():
		DirAccess.remove_absolute(_directory+"/owner_"+_token+".json")
		DirAccess.remove_absolute(_directory)
	_held.erase(_directory)
