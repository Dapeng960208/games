extends SceneTree
## Spawned only by the isolated recycle suite. Never accepts an ordinary save path.
const Store = preload("res://scripts/core/profile_store.gd")
var lease: RefCounted
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var target := ""
	var mode := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--lock-target="): target=argument.trim_prefix("--lock-target=")
		if argument.begins_with("--lock-mode="): mode=argument.trim_prefix("--lock-mode=")
	if not target.begins_with("/tmp/test_save_recycle_") or "/../" in target or mode not in ["blocked","crash"]:
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
	OS.kill(OS.get_process_id())
