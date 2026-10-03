extends Node
## Diagnostic only: actual Main._quit(), with/without existing audio drainage.
## The launcher supplies a brand-new XDG root and this exact isolated profile.
## No production shutdown changes; --verbose owns leaked-type identification.
var app: Node
var mode := "normal"
var evidence_path := ""
var evidence: Dictionary = {"snapshots":[]}
var completed := false
var checks := 0
var room_playbacks: Array[WeakRef] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")
	get_tree().create_timer(20.0).timeout.connect(_timeout)

func _timeout() -> void:
	if not completed: _fail("diagnostic timed out before Main._quit")

func _fail(reason: String) -> void:
	completed = true
	evidence["failure"] = reason
	_save_evidence()
	push_error("AUDIO SHUTDOWN DIAGNOSTIC: "+reason)
	get_tree().quit(2)

func _check(condition: bool, description: String) -> bool:
	checks += 1
	if not condition:
		_fail(description)
		return false
	print("AUDIO_SHUTDOWN_CHECK ",description)
	return true

func _observe_exit() -> void:
	# The exit signal precedes owner destruction. Observe weak playback refs
	# only; never retain the playback or WAV while Godot shuts down.
	var pending := int(app.music._prune_playbacks()) if is_instance_valid(app.music) else -1
	var pending_room := 0
	for reference: WeakRef in room_playbacks:
		if reference.get_ref() != null: pending_room += 1
	evidence["exit_room_playbacks"] = pending_room
	evidence["exit_music_playbacks"] = pending
	evidence["shutdown_started"] = bool(app._shutdown_started)
	evidence["checks"] = checks
	print("AUDIO_SHUTDOWN_EXIT ",JSON.stringify({"mode":mode,"pending_music_playbacks":pending,"pending_room_playbacks":pending_room,"shutdown_started":app._shutdown_started,"checks":checks}))
	_save_evidence()

func _save_evidence() -> void:
	if evidence_path.is_empty(): return
	var file := FileAccess.open(AssetCatalog.resolve(evidence_path),FileAccess.WRITE)
	if file == null:
		push_error("Could not save shutdown diagnostic evidence: "+evidence_path)
		return
	file.store_string(JSON.stringify(evidence,"\t",true,true))

func _snapshot(phase: String) -> void:
	var voices: Array = []
	for voice: AudioStreamPlayer in app.music._players:
		# Only strings/scalars leave this loop. Retaining a playback/stream Ref
		# here would contaminate the very leak this diagnostic is measuring.
		voices.append({"name":str(voice.name),"playing":voice.playing,
			"stream_class":voice.stream.get_class() if voice.stream != null else "",
			"stream_path":voice.stream.resource_path if voice.stream != null else "",
			"playback_class":voice.get_stream_playback().get_class() if voice.has_stream_playback() else ""})
	var sample := {"phase":phase,"route":app.route,"run_present":Game.run != null,
		"audible":app.music.audible,"master_bus_muted":AudioServer.is_bus_mute(0),
		"music_context":app.music.current_context,"pending_playbacks":app.music._prune_playbacks(),
		"active_streams":app.music.active_stream_count(),"voices":voices}
	evidence.snapshots.append(sample)
	print("AUDIO_SHUTDOWN_SNAPSHOT ",JSON.stringify(sample))
	_save_evidence()

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shutdown-mode="): mode = argument.trim_prefix("--shutdown-mode=")
		if argument.begins_with("--shutdown-evidence="): evidence_path = argument.trim_prefix("--shutdown-evidence=")
	evidence.merge({"mode":mode,"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name()})
	if mode not in ["normal","drained","abandon"]:
		_fail("mode must be normal, drained or abandon")
		return
	var runner_profile := Game._isolated_test_path(Game.profile_path) and Game.profile_path.replace("\\", "/").get_file() == "test_main_audio_shutdown.json"
	if Game.profile_path != "user://test_main_audio_shutdown/profile.json" and not runner_profile:
		_fail("requires isolated test_main_audio_shutdown profile")
		return
	if Game.has_profile or FileAccess.file_exists(AssetCatalog.resolve(Game.profile_path)) or Game.run != null:
		_fail("requires a fresh synthetic profile; refuses existing save")
		return
	if not Game.new_profile():
		_fail("new isolated profile failed: "+Game.last_error)
		return
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	app.tree_exiting.connect(_observe_exit)
	app.show_camp()
	# Let the normal Main._process route select camp and the real music deck
	# start, fade in and advance on the mixer. Never fake delta or audible=false.
	var start := Time.get_ticks_msec()
	while app.music.current_context != "camp" or app.music.is_transitioning() or app.music._prune_playbacks() == 0:
		if Time.get_ticks_msec()-start > 10000:
			_fail("audible camp playback did not initialize")
			return
		await get_tree().process_frame
	_snapshot("audible_camp_ready")
	if not app.music.audible or AudioServer.is_bus_mute(0) or app.music.active_stream_count() != 1:
		_fail("expected one audible camp stream on unmuted master bus")
		return
	# Existing required-dialog semantics must prevent shutdown from beginning.
	var required: Panel = app._push_modal("",Vector2(400,240))
	app.modals[-1]["required"] = true
	app._quit()
	if not _check(not app._shutdown_started and required.is_inside_tree(),"required modal blocks normal Quit before audio shutdown"): return
	app.modals[-1]["required"] = false
	app._pop_modal()
	if mode == "abandon":
		await _abandon_with_retry()
		return
	if mode == "drained":
		# Comparison only: prevent Main's periodic context updater from restarting
		# camp music while its existing bounded cleanup waits for mixer release.
		app.set_process(false)
		var cleanup_start := Time.get_ticks_msec()
		var drained: bool = await app.music.wait_for_cleanup()
		evidence["cleanup_ms"] = Time.get_ticks_msec()-cleanup_start
		evidence["cleanup_succeeded"] = drained
		_snapshot("after_existing_audio_drain")
		if not drained or app.music._prune_playbacks() != 0:
			_fail("existing music cleanup did not release tracked playback")
			return
	completed = true
	evidence["quit_path"] = "Main._quit from camp, run=null"
	_save_evidence()
	print("AUDIO_SHUTDOWN_QUIT mode=",mode," path=Main._quit; completed setup and invoking actual production exit")
	app._quit()
	_check(app._shutdown_started,"production exit enters guarded cleanup")
	app._quit() # Repeated terminal request is idempotent while the mixer drains.

func _abandon_with_retry() -> void:
	if not _check(Game.start_run(),"actual main creates isolated active run"): return
	# Freeze the synthetic encounter while inspecting real exit dialogs.
	app.room.set_physics_process(false)
	app.room.player.set_physics_process(false)
	for enemy: Node in app.room.enemies.get_children(): enemy.set_physics_process(false)
	app._quit()
	if not _check(not app._shutdown_started and not app.modals.is_empty() and Game.run != null,"active run Quit opens abandonment confirmation without draining"): return
	app._pop_modal()
	if not _check(not app._shutdown_started and Game.run != null,"cancel preserves active run and audio"): return
	# Exercise the production save-failure gate, then its real Retry button.
	var original_limit: int = Game._store.max_document_bytes
	Game._store.max_document_bytes = 1
	app.show_abandon(true)
	var confirm: Button = null
	for button: Button in app.modals[-1].node.find_children("*","Button",true,false):
		if button.text == Words.text("CONFIRM_ABANDON"): confirm = button
	if not _check(confirm != null,"actual abandonment confirmation button exists"): return
	confirm.pressed.emit()
	for index in 3: await get_tree().process_frame
	if not _check(not app._shutdown_started and Game.run != null and app.pending_outcome == "abandoned" and bool(app.modals[-1].get("required",false)),"failed settlement remains required and cannot quit"): return
	app._quit()
	if not _check(not app._shutdown_started,"repeated Quit cannot bypass failed settlement"): return
	Game._store.max_document_bytes = original_limit
	var retry: Button = null
	for button: Button in app.modals[-1].node.find_children("*","Button",true,false):
		if button.text == Words.text("RETRY"): retry = button
	if not _check(retry != null,"actual required Retry button exists"): return
	completed = true
	evidence["quit_path"] = "Main abandonment confirmation -> failed save -> required Retry -> settled result -> audio cleanup"
	_save_evidence()
	print("AUDIO_SHUTDOWN_QUIT mode=abandon path=required_retry_then_settled_exit")
	retry.pressed.emit()
	if not _check(Game.run == null,"retry durably settles before shutdown is requested"): return
	# The Retry handler clears pause; show_result is deferred. Create a real
	# room voice in that interval, then observe that terminal cleanup drains it
	# before deleting the room. This checks ownership rather than audible output.
	if not _check(app.room.combat_audio.hurt(),"room SFX creates actual playback before deferred settled exit"): return
	for voice: AudioStreamPlayer in app.room.combat_audio._players:
		if voice.has_stream_playback(): room_playbacks.append(weakref(voice.get_stream_playback()))
	if not _check(not room_playbacks.is_empty(),"room playback weak reference captured without retaining it"): return
