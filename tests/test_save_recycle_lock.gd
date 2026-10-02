extends SceneTree
## Spawned only by the isolated recycle suite. Never accepts an ordinary save path.
const Store = preload("res://scripts/core/profile_store.gd")
var lease: RefCounted
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var target := ""
	var mode := ""
	var test_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lock-target="): target=argument.trim_prefix("--lock-target=")
		if argument.begins_with("--lock-mode="): mode=argument.trim_prefix("--lock-mode=")
		if argument.begins_with("--test-profile="): test_profile=argument.trim_prefix("--test-profile=")
	var bootstrap := ProjectSettings.globalize_path(test_profile).replace("\\","/")
	var fixture_root := bootstrap.get_base_dir()
	var normalized := ProjectSettings.globalize_path(target).replace("\\","/")
	if bootstrap.get_file() not in ["test_lock_child_boot.json","test_lock_crash_boot.json"] or not fixture_root.get_file().begins_with("test_save_recycle_") or normalized.get_base_dir()!=fixture_root or not normalized.get_file().begins_with("test_") or normalized!=normalized.simplify_path() or mode not in ["blocked","crash"]:
		quit(3)
		return
	if mode=="blocked":
		var store := Store.new(target)
		var denied := not store.save_document(Store.fresh_profile()) and store.last_error=="STORAGE_IN_USE"
		print("LOCK CHILD BLOCKED" if denied else "LOCK CHILD UNEXPECTED WRITE")
		quit(0 if denied else 4)
		return
	lease=Store.SaveLease.acquire(target)
	if lease==null:
		quit(5)
		return
	# Kill only this fixture process, bypassing destructors to model a real crash.
	print("LOCK CHILD CRASHING")
	OS.kill(OS.get_process_id())
