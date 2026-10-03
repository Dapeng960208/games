extends SceneTree
## Disposable fixtures only. No actual player directory, graphics, or background jobs.
const Store = preload("res://scripts/infrastructure/persistence/profile_store.gd")
const Bin = preload("res://scripts/infrastructure/persistence/profile_recycle_bin.gd")
var checks := 0
var failures: Array[String] = []
var directory := ""
var current_time := 1_800_000_000

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("SAVE RECYCLE: " + label)

func clock() -> int:
	return current_time

func fixture(label: String, gold: int = 321) -> ProfileStore:
	var path := directory+"/test_"+label+".json"
	var store := Store.new(path)
	store.recycle_clock = clock
	var profile := Store.NativeProfile.fresh(Store.fresh_profile())
	profile.permanent_gold = gold
	profile.hero_xp.CH01 = 120
	profile["future_extension"] = {"memo":"完整保存 / exact", "ids":["one", "two"]}
	check(store.save_document(profile),label+" first save")
	check(store.save_document(profile),label+" backup save")
	return store

func reload(store: ProfileStore) -> ProfileStore:
	var fresh := Store.new(store.path)
	fresh.recycle_clock = clock
	fresh.load_document()
	return fresh

func make_bin(path: String) -> Bin:
	var bin := Bin.new(path,clock)
	bin.document_validator = Store._valid_document
	return bin

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(AssetCatalog.resolve(path),FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func same(a: Dictionary, b: Dictionary) -> bool:
	return Store._serialize(a) == Store._serialize(b)

func snapshot_files(path: String) -> Dictionary:
	var files := {}
	for suffix: String in Bin.SUFFIXES:
		if FileAccess.file_exists(AssetCatalog.resolve(path+suffix)): files[suffix] = FileAccess.get_file_as_bytes(AssetCatalog.resolve(path+suffix))
	return files

func basic_restore() -> void:
	var store := fixture("basic")
	var old := store._current.duplicate(true)
	var raw := snapshot_files(store.path)
	var manual := store.path+".manual-backup"
	write_bytes(manual,"untouched manual backup".to_utf8_buffer())
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()), false),"delete atomically creates blank slot")
	check(not store.has_profile,"deletion clears playable profile")
	var rows := store.recycle_entries()
	check(rows.size()==1,"one committed deletion appears")
	if rows.is_empty(): return
	var id: String = rows[0].entry_id
	check(Bin.safe_id(id) and rows[0].profile_id == old.profile_id,"separate safe entry and original logical identity")
	check(int(rows[0].expires_at)-int(rows[0].deleted_at)==604800,"retention is exactly 7x24 hours")
	var bin := make_bin(store.path)
	var archive := bin.get_archive(id)
	for suffix: String in raw:
		check(Marshalls.base64_to_raw(archive.files[suffix].bytes)==raw[suffix],"exact original candidate bytes "+suffix)
	check(same(JSON.parse_string(Marshalls.base64_to_raw(archive.snapshot).get_string_from_utf8()),old),"whole document archived without economy merging")
	var state_bytes := FileAccess.get_file_as_bytes(AssetCatalog.resolve(bin.folder()+"/index.json"))
	store.recycle_entries()
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(bin.folder()+"/index.json"))==state_bytes,"listing is read-only")
	store = reload(store)
	check(not store.has_profile and store.recycle_entries().size()==1,"restart persists deleted state and archive")
	check(store.restore_recycled(id),"whole original profile restores")
	check(same(store._current.profile,old.profile) and store._current.active_run == old.active_run,"gold, inventory, receipts and extensions restored exactly")
	check(store._current.profile_id==old.profile_id,"restore preserves original identity")
	check(store._current.revision>old.revision,"restored commit has a newer revision")
	check(not store.restore_recycled(id),"double restore never duplicates economy")
	check(store.recycle_entries().is_empty(),"consumed archive is no longer restorable")
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(manual))=="untouched manual backup".to_utf8_buffer(),"unrelated backup stays untouched")
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"restored profile can be deleted again")
	var second := store.recycle_entries()
	check(second.size()==1 and second[0].entry_id!=id and second[0].profile_id==old.profile_id,"repeated deletion uses unique entry and stable profile identity")
	check(not store.restore_recycled(id) and store.last_error=="STORAGE_RECYCLE_UNAVAILABLE","consumed entry stays consumed after later deletion")
	check(store.restore_recycled(second[0].entry_id),"later deletion restores once")
	current_time += Bin.RETENTION_SECONDS
	check(store.cleanup_recycle_bin(),"expired consumed archives can be cleaned")
	check(same(reload(store)._current.profile,old.profile),"cleanup cannot delete restored active profile")
	check(FileAccess.file_exists(AssetCatalog.resolve(manual)),"cleanup never purges unrelated backups")

func boundaries_and_clock() -> void:
	current_time = 1_810_000_000
	var store := fixture("boundary")
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"boundary delete")
	var row := store.recycle_entries()[0]
	var archive_file := make_bin(store.path)._archive_path(row.entry_id)
	current_time = int(row.expires_at)-1
	check(store.cleanup_recycle_bin() and FileAccess.file_exists(AssetCatalog.resolve(archive_file)),"one second before expiry remains recoverable")
	check(not store.recycle_entries()[0].expired,"one second remaining is not expired")
	current_time = int(row.expires_at)
	var index_before := FileAccess.get_file_as_bytes(AssetCatalog.resolve(store.path+".recycle/index.json"))
	check(store.recycle_entries()[0].expired,"exact seven-day boundary is expired")
	check(FileAccess.file_exists(AssetCatalog.resolve(archive_file)) and FileAccess.get_file_as_bytes(AssetCatalog.resolve(store.path+".recycle/index.json"))==index_before,"read-only expired view destroys nothing")
	check(not store.restore_recycled(row.entry_id) and store.last_error=="STORAGE_RECYCLE_EXPIRED","expired entry cannot be restored")
	check(store.cleanup_recycle_bin() and not FileAccess.file_exists(AssetCatalog.resolve(archive_file)),"explicit lifecycle cleanup removes expired archive")
	check(store.recycle_entries().is_empty(),"purged entry absent after cleanup")
	current_time = 1_820_000_000
	store = fixture("clock")
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"clock delete")
	row = store.recycle_entries()[0]
	current_time += 3600
	check(store.cleanup_recycle_bin(),"clock watermark is persisted at lifecycle operation")
	current_time -= 7200
	store = reload(store)
	check(store.recycle_entries()[0].clock_rollback,"rollback detected across restart")
	check(not store.cleanup_recycle_bin() and store.last_error=="STORAGE_RECYCLE_CLOCK","rollback pauses cleanup")
	check(store.restore_recycled(row.entry_id),"rollback never removes ability to recover")
	check(not store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false) and store.has_profile,"rollback blocks an unsafe new deletion timestamp")

func failed_transactions() -> void:
	current_time = 1_830_000_000
	for stage: String in ["archive", "archive_rename", "replacement", "replacement_rename", "index", "index_rename"]:
		var store := fixture("failure_"+stage)
		var before := snapshot_files(store.path)
		var profile: Dictionary = store._current.profile.duplicate(true)
		store.recycle_fail_stage = stage
		check(not store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),stage+" failure rejects deletion")
		check(snapshot_files(store.path)==before and store.has_profile,stage+" leaves original exact bytes active")
		var fresh := reload(store)
		check(fresh.has_profile and same(fresh._current.profile,profile),stage+" restart still loads original")
		check(fresh.recycle_entries().is_empty(),stage+" incomplete archive never exposed as a second profile")
	var store := fixture("capacity")
	var before := snapshot_files(store.path)
	store.max_document_bytes = 1
	check(not store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"capacity rejection fails before switch")
	check(snapshot_files(store.path)==before,"capacity rejection never deletes original")
	store = fixture("blocked_directory")
	before = snapshot_files(store.path)
	write_bytes(store.path+".recycle","directory blocked".to_utf8_buffer())
	check(not store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"filesystem write failure rejects deletion")
	check(snapshot_files(store.path)==before,"filesystem failure preserves primary and backup")
	store = fixture("archive_budget")
	var bin := make_bin(store.path)
	bin.max_write_bytes = 1
	before = snapshot_files(store.path)
	check(not bin.archive_and_switch(Store._serialize(store._current),store._current.profile_id,Store._serialize(store._current),""),"archive capacity limit rejects deletion")
	check(snapshot_files(store.path)==before,"archive capacity rejection does not evict any save")
	store = fixture("restore_failure")
	var original: Dictionary = store._current.profile.duplicate(true)
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"restore-failure fixture deletion")
	var id: String = store.recycle_entries()[0].entry_id
	for stage: String in ["replacement", "replacement_rename", "index", "index_rename"]:
		store.recycle_fail_stage = stage
		check(not store.restore_recycled(id),"restore "+stage+" failure rejects commit")
		store = reload(store)
		check(not store.has_profile and store.recycle_entries().size()==1,"failed restore retains complete archive and blank current slot")
	check(store.restore_recycled(id) and same(store._current.profile,original),"restore retries successfully without duplicate gold")
	store = fixture("normal_save_retry")
	var next_profile: Dictionary = store._current.profile.duplicate(true)
	next_profile.permanent_gold = 654
	# Keep its acknowledged .bak, then make only the final rename target fail.
	write_bytes(store.path+".bak",Store._serialize(store._current))
	DirAccess.remove_absolute(store.path)
	DirAccess.make_dir_absolute(store.path)
	check(not store.save_document(next_profile) and store.last_error=="STORAGE_REPLACE_FAILED","normal save can leave a flushed pending intent")
	DirAccess.remove_absolute(store.path)
	var pending_files := snapshot_files(store.path)
	var changed_intent: Dictionary = next_profile.duplicate(true)
	changed_intent.permanent_gold = 987
	check(not store.save_document(changed_intent) and store.last_error=="STORAGE_RECYCLE_CHANGED","a different request cannot replace a flushed pending intent")
	check(snapshot_files(store.path)==pending_files,"rejected changed retry preserves pending intent and acknowledged backup")
	check(store.save_document(next_profile),"normal save retries its own failed rename without restart")
	check(reload(store)._current.profile.permanent_gold==654,"normal retry commits intended gold once")
	store = Store.new(directory+"/test_initial_save_retry.json")
	store.recycle_clock=clock
	DirAccess.make_dir_absolute(store.path)
	var initial := Store.NativeProfile.fresh(Store.fresh_profile())
	initial.permanent_gold=111
	check(not store.save_document(initial) and store.last_error=="STORAGE_REPLACE_FAILED","initial save can leave its own flushed intent")
	var initial_bytes := FileAccess.get_file_as_bytes(AssetCatalog.resolve(store.path+".tmp"))
	DirAccess.remove_absolute(store.path)
	check(store.save_document(initial),"initial save retries with the same generated profile identity")
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(store.path))==initial_bytes,"initial retry preserves exact original intent bytes")
	check(reload(store)._current.profile.permanent_gold==111,"initial retry survives restart once")

func interrupted_backup_recovery() -> void:
	current_time=1_835_000_000
	for suffix: String in [".tmp", ".bak", ".bak.tmp"]:
		for stage: String in ["replacement_rename", "index", "index_rename"]:
			var store := fixture("backup_only_"+suffix.replace(".","_")+"_"+stage)
			var original := Store._serialize(store._current)
			for candidate: String in ["", ".tmp", ".bak", ".bak.tmp"]:
				if FileAccess.file_exists(AssetCatalog.resolve(store.path+candidate)): DirAccess.remove_absolute(store.path+candidate)
			write_bytes(store.path+suffix,original)
			store=reload(store)
			check(store.has_profile,"backup-only original loads "+suffix)
			store.recycle_fail_stage=stage
			check(not store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"backup-only interrupted switch fails "+stage)
			check(reload(store).has_profile,"backup-only interrupted switch preserves restart "+suffix+stage)
	var store := fixture("missing_index_after_commit")
	var original := Store._serialize(store._current)
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"committed index fixture")
	# Simulate an unrelated stale candidate reappearing, then loss of the index.
	write_bytes(store.path+".bak",original)
	DirAccess.remove_absolute(store.path+".recycle/index.json")
	check(reload(store).unresolved_error,"missing committed index cannot revive retired backup")
	store=fixture("active_bak_tmp")
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"active bak.tmp fixture")
	var bin := make_bin(store.path)
	var disk_path := bin.active_path(bin.read_state())
	DirAccess.rename_absolute(disk_path,disk_path+".bak.tmp")
	var fresh := reload(store)
	check(not fresh.unresolved_error and not fresh._current.is_empty(),"active generation recovers its only bak.tmp candidate")

func conflicts_and_integrity() -> void:
	current_time = 1_840_000_000
	var store := fixture("conflict",333)
	var original: Dictionary = store._current.profile.duplicate(true)
	var stale := reload(store)
	var newer := Store.NativeProfile.fresh(Store.fresh_profile())
	newer.permanent_gold=444
	check(store.recycle_and_replace(newer),"new-game replacement archives old profile")
	var id: String = store.recycle_entries()[0].entry_id
	check(not store.restore_recycled(id) and store.last_error=="STORAGE_RECYCLE_CONFLICT","current valid profile blocks restore")
	check(store._current.profile.permanent_gold==444,"conflict never overwrites newer economy")
	check(not stale.save_document(original) and stale.last_error=="STORAGE_RECYCLE_CHANGED","stale pre-deletion store cannot resurrect retired generation")
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"new profile can be explicitly archived before restore")
	check(store.restore_recycled(id) and same(store._current.profile,original),"selected original restores without mixing two profiles")
	check(store.recycle_entries().size()==1,"other profile stays independently recoverable")
	store = fixture("stale_same_generation")
	stale = reload(store)
	newer = store._current.profile.duplicate(true)
	newer.permanent_gold = 555
	check(store.save_document(newer),"newer same-generation save")
	var latest_files := snapshot_files(store.path)
	check(not stale.save_document(original) and stale.last_error=="STORAGE_RECYCLE_CHANGED","stale ordinary save cannot overwrite a newer same-generation revision")
	check(snapshot_files(store.path)==latest_files,"stale ordinary save preserves every latest candidate byte")
	check(not stale.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false) and stale.last_error=="STORAGE_RECYCLE_CHANGED","stale snapshot cannot archive over newer save")
	check(reload(store)._current.profile.permanent_gold==555,"stale deletion preserves latest data")
	store = fixture("corrupt_archive")
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"corrupt fixture deletion")
	id = store.recycle_entries()[0].entry_id
	var bin := make_bin(store.path)
	var filename := bin._archive_path(id)
	var bytes := FileAccess.get_file_as_bytes(AssetCatalog.resolve(filename))
	write_bytes(filename,"corrupt".to_utf8_buffer())
	check(not store.restore_recycled(id) and store.last_error=="STORAGE_RECYCLE_INVALID","corrupt archive cannot restore")
	current_time += Bin.RETENTION_SECONDS
	store.cleanup_recycle_bin()
	check(FileAccess.get_file_as_bytes(AssetCatalog.resolve(filename))=="corrupt".to_utf8_buffer(),"bad checksum blocks automatic destruction even after expiry")
	write_bytes(filename,bytes)
	current_time -= Bin.RETENTION_SECONDS
	check(not store.restore_recycled("../../outside") and not store.restore_recycled("/tmp/outside"),"traversal and absolute entry IDs rejected")
	var state := bin.read_state()
	state.entries[id].source_generation="../../outside"
	write_bytes(bin.folder()+"/index.json",Bin._seal(state))
	check(reload(store).unresolved_error,"unsafe index fields fail closed at startup")
	check(not store.cleanup_recycle_bin() and FileAccess.file_exists(AssetCatalog.resolve(filename)),"unsafe metadata cannot authorize cleanup")
	store = fixture("collision")
	bin = make_bin(store.path)
	var collision := "a".repeat(32)
	DirAccess.make_dir_recursive_absolute(bin.folder()+"/slots/"+collision)
	check(not bin._unused("",collision) and bin.last_error=="STORAGE_RECYCLE_COLLISION","generation collisions never overwrite")
	check(not Bin.safe_id("..") and not Bin.safe_id("/tmp/"+collision),"safe ID whitelist has no filesystem syntax")

func copy_tree(source: String, target: String) -> void:
	DirAccess.make_dir_recursive_absolute(target)
	var directory_reader := DirAccess.open(source)
	for filename: String in directory_reader.get_files():
		check(DirAccess.copy_absolute(source+"/"+filename,target+"/"+filename)==OK,"copy complete portable backup file")
	for child: String in directory_reader.get_directories(): copy_tree(source+"/"+child,target+"/"+child)

func portable_backup_and_locks() -> void:
	current_time=1_845_000_000
	var store := fixture("portable")
	var original: Dictionary = store._current.profile.duplicate(true)
	check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"portable backup deletion")
	var id: String = store.recycle_entries()[0].entry_id
	var relocated := directory+"/test_other_user/test_moved.json"
	copy_tree(store.path+".recycle",relocated+".recycle")
	var moved := Store.new(relocated)
	moved.recycle_clock=clock
	moved.load_document()
	check(not moved.unresolved_error and moved.restore_recycled(id),"whole save tree restores under a different absolute path")
	check(same(moved._current.profile,original),"portable backup retains original economy and identity")
	var lease = Store.SaveLease.acquire(store.path)
	check(lease!=null,"writer lease acquired")
	var nested = Store.SaveLease.acquire(store.path)
	check(nested==lease,"same-process nested load/migration reuses lease")
	nested=null
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(),["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/persistence/test_save_recycle_lock.gd","--","--test-profile="+directory+"/test_lock_child_boot.json","--lock-target="+store.path,"--lock-mode=blocked"],output,true)
	if exit_code!=0 or "LOCK CHILD BLOCKED" not in "".join(output): print("LOCK CHILD DIAGNOSTIC: ",exit_code," ",output)
	check(exit_code==0 and "LOCK CHILD BLOCKED" in "".join(output),"independent process cannot write while lease is held")
	lease=null
	check(not DirAccess.dir_exists_absolute(store.path+".writer-lock"),"lease is released after transaction")
	output.clear()
	exit_code=OS.execute(OS.get_executable_path(),["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/persistence/test_save_recycle_lock.gd","--","--test-profile="+directory+"/test_lock_crash_boot.json","--lock-target="+store.path,"--lock-mode=crash"],output,true)
	# Windows TerminateProcess may report exit 0 even for an abrupt self-kill.
	check("LOCK CHILD CRASHING" in "".join(output) and DirAccess.dir_exists_absolute(store.path+".writer-lock"),"killed isolated child leaves its crash lock")
	lease=Store.SaveLease.acquire(store.path)
	check(lease!=null,"confirmed dead child lock is safely reclaimed")
	lease=null
	DirAccess.make_dir_absolute(store.path+".writer-lock")
	write_bytes(store.path+".writer-lock/unknown.json","invalid owner".to_utf8_buffer())
	check(Store.SaveLease.acquire(store.path)==null,"uncertain or corrupt lock is never stolen")
	check(not store.cleanup_recycle_bin() and store.last_error=="STORAGE_IN_USE","cleanup obeys same writer guard")
	check(FileAccess.file_exists(AssetCatalog.resolve(store.path+".writer-lock/unknown.json")),"uncertain lock evidence preserved")
	DirAccess.remove_absolute(store.path+".writer-lock/unknown.json")
	var reused_token := "b".repeat(32)
	write_bytes(store.path+".writer-lock/owner_"+reused_token+".json",JSON.stringify({"pid":OS.get_process_id(),"token":reused_token}).to_utf8_buffer())
	check(Store.SaveLease.acquire(store.path)==null,"live or reused PID lock is conservatively preserved")

func active_receipt() -> void:
	current_time = 1_850_000_000
	# Preserve a valid complete active receipt rather than granting its rewards.
	var receipt := {"id":"test_receipt","gold":17,"discoveries":[],"shots":0,"kills":0,"elapsed":2.0,"hero_id":"CH01","level":1,"hero_xp_gained":0,"rules_version":1,"ruleset_version":2,"completed_reward_ids":[],"boss_defeats":[]}
	receipt.merge(Store.Expedition.versions(2),true)
	var source := Store.NativeProfile.fresh(Store.fresh_profile())
	var store := Store.new(directory+"/test_receipt.json")
	store.recycle_clock=clock
	check(store.save_document(source,receipt),"current active receipt fixture saves")
	if store.has_profile:
		var expected: Dictionary = store._current.active_run.duplicate(true)
		check(store.recycle_and_replace(Store.NativeProfile.fresh(Store.fresh_profile()),false),"active receipt archived as whole document")
		var row := store.recycle_entries()[0]
		check(store.restore_recycled(row.entry_id),"active receipt document restores")
		check(same(store._current.active_run,expected) and store._current.profile.permanent_gold==0,"restore does not independently settle or duplicate pending gold")

func _run() -> void:
	var test_profile := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="): test_profile=argument.trim_prefix("--test-profile=").replace("\\","/")
	if not test_profile.get_file().begins_with("test_save_recycle_bin") or test_profile!=test_profile.simplify_path():
		push_error("Save recycle core suite requires its explicit disposable test path")
		quit(2)
		return
	var base := ProjectSettings.globalize_path(test_profile).get_base_dir()+"/test_save_recycle_"+str(Time.get_ticks_usec())
	directory=base
	DirAccess.make_dir_recursive_absolute(directory)
	basic_restore()
	boundaries_and_clock()
	failed_transactions()
	interrupted_backup_recovery()
	conflicts_and_integrity()
	portable_backup_and_locks()
	active_receipt()
	print("SAVE RECYCLE BIN: ",checks," checks; failures=",failures)
	quit(0 if failures.is_empty() else 1)
