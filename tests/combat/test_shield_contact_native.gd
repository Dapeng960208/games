extends Node
## Actual hero attacks, native physics/rendering, original Master-bus recording.
## tools/test.ps1 -Suite shield_contact_native -Graphical -SkipImport
const OUTPUT := "res://artifacts/shield_contact_native"
const METHOD := "Audiovisual training fixture, not natural combat or balance. Real Game.start_demo supplies standard Lv8 hero, six starter pieces and initial resource; no player stat/resource/CD resets. Each case creates one real authored enemy with declared 10000 HP, AI disabled and rewards disabled; ordinary status.grant_guard supplies 500 shield, 5 shield or none. Natural armor/resistance remain. Only public fire/cast_skill and actual SubViewport pointer, automatic 60Hz physics at time scale1, normal camera .85. No direct damage/contact/audio calls, manual ticks, slow motion or frame freezing. Three basic shield states plus one class heavy break per hero. First real GPU contact frames retained in memory and PNG-compressed after the hero's observation. Master audio recorded before safety mute without gain change, normalization, microphone or editing. Real room SFX mix; this fixture does not include MusicDirector."
var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var victim: Node2D
var hud_layer: CanvasLayer
var hero := ""
var current_case := ""
var current_slot := ""
var observing := false
var capture_enabled := false
var ending := false
var watchdog_start := 0
var start_wall := 0
var start_elapsed := 0.0
var start_tick := 0
var contact_serial_floor := 0
var recorder: AudioEffectRecord
var recorder_slot := -1
var cues: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var case_reports: Array[Dictionary] = []
var reports: Array[Dictionary] = []
var images: Dictionary = {}
var initial: Dictionary = {}

func _ready() -> void:
	watchdog_start = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(50, true, false, true).timeout.connect(watchdog)
	call_deferred("run_capture")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SHIELD_CONTACT_NATIVE FAIL: " + label)

func stamp() -> Dictionary:
	return {"wall_seconds": (Time.get_ticks_msec() - start_wall) / 1000.0,
		"physics_seconds": snappedf(room.elapsed - start_elapsed, .00001) if is_instance_valid(room) else 0,
		"physics_tick": Engine.get_physics_frames() - start_tick,
		"render_frame": Engine.get_frames_drawn(), "case": current_case}

func pointer() -> void:
	if not is_instance_valid(victim): return
	var mouse := InputEventMouseMotion.new()
	mouse.position = room.get_canvas_transform() * room.to_global(victim.position)
	mouse.global_position = mouse.position
	stage.push_input(mouse, true)

func _process(_delta: float) -> void:
	if ending: return
	if Time.get_ticks_msec() - watchdog_start >= 50000:
		watchdog()
		return
	if observing: pointer()

func on_cue(cue: String) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"cue": cue, "voices": room.combat_audio.active_voice_count()})
	cues.append(event)

func on_damage(amount: float) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"amount": amount, "hp_after": victim.health.current, "shield_after": victim.status.shield(),
		"source": str(victim.last_damage_context.get("skill_slot", victim.last_damage_context.get("damage_source", "")))})
	damage_events.append(event)

func serializable_contact(event: Dictionary) -> Dictionary:
	var copy: Dictionary = event.duplicate(true)
	for key: String in ["anchor", "visual_anchor"]: copy.erase(key)
	return copy

func snapshot() -> Dictionary:
	var result := stamp()
	result.merge({"hero": hero, "slot": current_slot, "resource": Game.run.resource if Game.run != null else 0,
		"target_id": victim.get_instance_id() if is_instance_valid(victim) else 0,
		"target_hp": victim.health.current if is_instance_valid(victim) else 0,
		"target_shield": victim.status.shield() if is_instance_valid(victim) else 0,
		"target_position": victim.position if is_instance_valid(victim) else Vector2.ZERO,
		"player_position": room.player.position, "aim_direction": room.player.aim_direction,
		"pose": room.player.get_meta("hero_visual_pose", ""), "cooldowns": room.player.cooldowns.duplicate(true),
		"camera": room.camera.impact_stats(), "hitstop": room.player.visual_hitstop})
	return result

func after_draw() -> void:
	if not observing or not capture_enabled or images.has(current_case): return
	for event: Dictionary in room.impact_feedback.events:
		if str(event.get("kind", "")) != "hit" or int(event.get("serial", 0)) <= contact_serial_floor: continue
		if str(event.get("source", "")) != ("primary" if current_slot == "basic" else current_slot): continue
		if event.get("anchor") is WeakRef and event.anchor.get_ref() != victim: continue
		var data := snapshot()
		data["contact"] = serializable_contact(event)
		images[current_case] = {"image": stage.get_texture().get_image(), "sample": data}
		break

func start_recording() -> void:
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)

func stop_recording() -> Dictionary:
	if recorder == null: return {"status":"missing"}
	recorder.set_recording_active(false)
	var recording: AudioStreamWAV = recorder.get_recording()
	AudioServer.remove_bus_effect(0, recorder_slot)
	recorder = null
	check(recording != null and not recording.data.is_empty(), hero + " actual Master recording contains PCM")
	if recording == null or recording.data.is_empty(): return {"status":"missing", "reason":"No PCM; no unmuted retry"}
	var peak := 0.0
	var energy := 0.0
	var pcm: PackedByteArray = recording.data
	for offset in range(0, pcm.size() - 1, 2):
		var value: float = float(pcm.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value))
		energy += value * value
	var path: String = hero + "_native_mix.wav"
	var saved: Error = recording.save_to_wav(OUTPUT.path_join(path))
	check(saved == OK and peak > .000001 and peak < 1, hero + " native SFX mix saves non-silent unclipped PCM")
	return {"status":"saved" if saved == OK else "failed", "path":path, "duration":recording.get_length(),
		"mix_rate":recording.mix_rate, "stereo":recording.stereo, "peak":peak,
		"rms":sqrt(energy / maxf(1, pcm.size() / 2.0)), "master_safety_muted":AudioServer.is_bus_mute(0)}

func fixture(next_hero: String) -> bool:
	hero = next_hero
	check(Game.new_profile() and Game.start_demo(hero, 0), hero + " genuine standard Lv8 demo starts")
	if Game.run == null: return false
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	stage.add_child(room)
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(1400, 900)
	room.release_gate = false
	room.input_blocked = false
	room.combat_audio.cue_played.connect(on_cue)
	hud_layer = CanvasLayer.new()
	stage.add_child(hud_layer)
	var hud: Control = load(AssetCatalog.resolve("res://scripts/presentation/hud/hud.gd")).new()
	hud.room = room
	hud_layer.add_child(hud)
	hud.size = Vector2(1280, 720)
	cues = []; damage_events = []; case_reports = []; images = {}
	current_case = "setup"; current_slot = ""
	start_wall = Time.get_ticks_msec(); start_elapsed = room.elapsed; start_tick = Engine.get_physics_frames()
	initial = {"hero":hero, "level":Game.run.level, "stats":Game.run.stats.duplicate(true),
		"loadout":Game.run.loadout_snapshot.duplicate(true), "resource":Game.run.resource,
		"settings":Game.profile.settings.duplicate(true)}
	check(Game.run.level == 8 and Game.run.loadout_snapshot.size() == 6 and Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1 and room.camera.zoom == Vector2(.85, .85), hero + " standard build and native 60Hz/.85 camera")
	start_recording()
	observing = true
	return true

func run_case(label: String, shield_amount: float, slot: String) -> void:
	current_case = label
	current_slot = slot
	capture_enabled = false
	if is_instance_valid(victim): victim.free()
	var enemy_id: String = {"CH01":"M01", "CH02":"M10", "CH03":"M31"}[hero]
	var offset: Vector2 = Vector2(78, 24) if hero == "CH01" else Vector2(200, 35) if hero == "CH02" else Vector2(95, 25)
	victim = room.spawn_enemy(room.player.position + offset, enemy_id, 8, {"reward_enabled":false})
	victim.health.reset(10000.0)
	victim.training_ai_disabled = true
	if shield_amount > 0: check(victim.status.grant_guard(shield_amount, 30, "audiovisual_training", victim.health.maximum), hero + " " + label + " grants a real production guard")
	victim.health.damaged.connect(on_damage)
	var deadline: int = Time.get_ticks_msec() + 5500
	var ready := false
	while Time.get_ticks_msec() < deadline and not ending:
		pointer()
		await get_tree().physics_frame
		await get_tree().process_frame
		var cooldown: float = room.player.shot_cooldown if slot == "basic" else float(room.player.cooldowns.get(slot, 0))
		ready = not room.player.abilities.busy() and room.player.attack_remaining <= 0 and cooldown <= 0 and room.player.aim_direction.dot(room.player.position.direction_to(victim.position)) > .995
		if ready: break
	if ending: return
	check(ready, hero + " " + label + " becomes ready through actual time and pointer")
	var before: Dictionary = snapshot()
	contact_serial_floor = room.impact_feedback._serial
	var first_cue: int = cues.size()
	var first_damage: int = damage_events.size()
	capture_enabled = true
	var accepted: bool = room.player.fire(room.player.aim_direction) if slot == "basic" else room.player.cast_skill(slot, victim.position)
	check(accepted, hero + " " + label + " public action accepted")
	var requested_at: Dictionary = stamp()
	deadline = Time.get_ticks_msec() + 2200
	while Time.get_ticks_msec() < deadline and not ending:
		await get_tree().process_frame
		if images.has(label) and not room.player.abilities.busy() and room.elapsed - start_elapsed > float(images[label].sample.physics_seconds) + .40: break
	if ending: return
	capture_enabled = false
	var has_frame: bool = images.has(label)
	check(has_frame, hero + " " + label + " captures a real contact frame")
	var hit: Dictionary = images[label].sample.contact if has_frame else {}
	if has_frame:
		var absorbed: bool = shield_amount >= 500
		var broken: bool = shield_amount > 0 and not absorbed
		check((float(hit.get("shield_damage", 0)) > 0) == (shield_amount > 0) and bool(hit.get("shield_broken", false)) == broken, hero + " " + label + " actual shield contact classification")
		check((float(hit.get("hp_damage", 0)) > 0) == (not absorbed), hero + " " + label + " body damage only for overflow/no shield")
		check(str(hit.get("hero_id", "")) == hero and (slot == "basic" or bool(hit.get("heavy", false))), hero + " " + label + " retains actual hero/heavy identity")
	var actual_cues: Array = cues.slice(first_cue)
	var shield_events: Array[Dictionary] = []
	for cue: Dictionary in actual_cues:
		if str(cue.cue) in ["shield_hit", "shield_break"]: shield_events.append(cue)
	check(shield_events.size() == (1 if shield_amount > 0 else 0), hero + " " + label + " real mix admits exactly the expected shield cue")
	if shield_amount > 0 and not shield_events.is_empty() and has_frame:
		var expected: String = "shield_hit" if shield_amount >= 500 else "shield_break"
		check(str(shield_events[0].cue) == expected and absf(float(shield_events[0].physics_seconds) - float(images[label].sample.physics_seconds)) <= .10, hero + " " + label + " shield audio is tied to the actual contact frame")
	case_reports.append({"label":label, "slot":slot, "declared_training_shield":shield_amount,
		"target_profile":victim.profile.duplicate(true), "training_max_hp":victim.health.maximum,
		"before":before, "requested_at":requested_at, "accepted":accepted, "after":snapshot(),
		"contact":hit, "audio_cues":actual_cues, "actual_health_damage_events":damage_events.slice(first_damage),
		"capture_status":"captured" if has_frame else "missing"})

func finish_hero() -> void:
	observing = false
	var recording: Dictionary = stop_recording()
	check(Game.run.stats == initial.stats and Game.run.loadout_snapshot == initial.loadout, hero + " leaves standard player stats/equipment unchanged")
	var paths: Array[String] = []
	for label: String in images:
		var path: String = hero + "_" + label + ".png"
		var bitmap: Image = images[label].image
		check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png(OUTPUT.path_join(path)) == OK, "save actual framebuffer " + path)
		paths.append(path)
	reports.append({"initial":initial, "cases":case_reports, "captures":paths, "audio_cues":cues, "recording":recording})
	print("SHIELD_NATIVE hero=", hero, " cases=", case_reports.size(), " captures=", paths.size(), " recording=", recording)
	images.clear()

func write_report(timed_out: bool = false) -> void:
	var file := FileAccess.open(AssetCatalog.resolve(OUTPUT.path_join("native_capture.json")), FileAccess.WRITE)
	check(file != null, "open shield native report")
	if file == null: return
	file.store_string(JSON.stringify({"method":METHOD, "checks":checks + 1, "failures":failures,
		"timed_out":timed_out, "reports":reports, "total_wall_seconds":(Time.get_ticks_msec() - watchdog_start) / 1000.0}, "\t"))
	check(file.get_error() == OK, "write shield native report")
	file.close()

func cleanup() -> void:
	observing = false
	capture_enabled = false
	if recorder != null:
		recorder.set_recording_active(false)
		AudioServer.remove_bus_effect(0, recorder_slot)
		recorder = null
	if is_instance_valid(hud_layer): hud_layer.free()
	if is_instance_valid(room): room.free()
	if Game.run != null: Game.finish_run("abandoned")

func watchdog() -> void:
	if ending: return
	ending = true
	failures += 1
	push_error("Shield native observation timed out at 50 seconds; cleanup and quit")
	reports.append({"hero":hero, "status":"watchdog", "completed_cases":case_reports, "audio_cues":cues})
	cleanup()
	write_report(true)
	get_tree().quit(1)

func run_capture() -> void:
	if not str(Game.profile_path).contains("test_shield_contact_native") or DisplayServer.get_name() == "headless":
		ending = true
		push_error("Native shield test requires graphical renderer and isolated test_shield_contact_native profile")
		get_tree().quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	for key: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(key): InputMap.add_action(key)
		Input.action_release(key)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var display := TextureRect.new()
	display.texture = stage.get_texture()
	display.size = Vector2(1280, 720)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	RenderingServer.frame_post_draw.connect(after_draw)
	for next_hero: String in ["CH01", "CH02", "CH03"]:
		if not fixture(next_hero):
			ending = true
			cleanup(); write_report(); get_tree().quit(1)
			return
		for specification: Array in [["basic_shield", 500, "basic"], ["basic_break", 5, "basic"], ["basic_body", 0, "basic"], ["heavy_break", 5, "f" if hero == "CH03" else "secondary"]]:
			await run_case(str(specification[0]), float(specification[1]), str(specification[2]))
			if ending: return
		finish_hero()
		await room.combat_audio.wait_for_cleanup()
		cleanup()
		await get_tree().process_frame
	ending = true
	RenderingServer.frame_post_draw.disconnect(after_draw)
	write_report()
	print("SHIELD_CONTACT_NATIVE_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
