extends Node
## Native right-click choreography: real timeline/pointer/contacts, never pose injection.
## tools/test.ps1 -Suite hammer_secondary_native -Graphical -SkipImport -SkipRestart
const OUTPUT := "res://artifacts/hammer_secondary_native"
const Atlas = preload("res://scripts/combat/hero_skill_atlas.gd")
const FRAME_NAMES: Array[String] = ["plant", "coil", "drive", "contact", "follow", "ready"]
const METHOD := "Controlled audiovisual training capture, not balance or natural progression. Standard CH01 Lv8 Game.start_demo keeps starter gear, crit, resources and cooldown rules. Fresh real M01 Lv8 targets have declared 10000HP, AI disabled, rewards disabled. Four complete secondary casts: front hit/whiff and back hit/whiff; a fifth starts then cancels through the public dash action before release and continues normal movement. Native 60Hz physics, time scale1, real SubViewport pointer, normal .85 camera. Cooldown is waited in real time. Any required rage is earned only by real public basic attacks against a separately declared preparation target. Preparation targets are replaced before each cast to give a fixed hit80/whiff400 starting distance. No resource/CD reset, manual physics/timeline/pose sampling, direct contact/damage/audio injection, pause or slow motion. First actual rendered occurrence of each of six frames is retained in memory per bank across complete casts; missed per-cast frames are explicitly reported. PNG compression happens after observation. Original Master SFX PCM before safety mute, no MusicDirector/BGM, gain adjustment, normalization, microphone or editing."
var checks := 0
var failures := 0
var stage: SubViewport
var room: Node2D
var target: Node2D
var hud_layer: CanvasLayer
var observing := false
var ending := false
var stage_name := "setup"
var case_name := ""
var bank := "front"
var aim_target := Vector2.ZERO
var watchdog_start := 0
var start_wall := 0
var start_elapsed := 0.0
var start_tick := 0
var cast_elapsed := 0.0
var metadata: Dictionary = {}
var expected_sources: Dictionary = {}
var bank_frames: Dictionary = {"front":{}, "back":{}}
var bank_order: Dictionary = {"front":[], "back":[]}
var per_cast_frames: Array[String] = []
var samples: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var damages: Array[Dictionary] = []
var cues: Array[Dictionary] = []
var releases: Array[Dictionary] = []
var records: Array[Dictionary] = []
var initial: Dictionary = {}
var cancel_frame: Dictionary = {}
var recording_info: Dictionary = {}
var release_cursor := 0
var recorder: AudioEffectRecord
var recorder_slot := -1

func _ready() -> void:
	watchdog_start = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(42, true, false, true).timeout.connect(watchdog)
	call_deferred("run_capture")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HAMMER_SECONDARY_NATIVE FAIL: " + label)

func stamp() -> Dictionary:
	return {"wall_seconds":(Time.get_ticks_msec() - start_wall) / 1000.0,
		"physics_seconds":snappedf(room.elapsed - start_elapsed, .00001) if is_instance_valid(room) else 0,
		"physics_tick":Engine.get_physics_frames() - start_tick, "render_frame":Engine.get_frames_drawn(),
		"stage":stage_name, "case":case_name}

func direction_for(next_bank: String) -> Vector2:
	return Vector2(1, .65 if next_bank == "front" else -.65).normalized()

func pointer(at: Vector2) -> void:
	aim_target = at
	var event := InputEventMouseMotion.new()
	event.position = room.get_canvas_transform() * room.to_global(at)
	event.global_position = event.position
	stage.push_input(event, true)

func movement(direction: Vector2) -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		if InputMap.has_action(action): Input.action_release(action)
	var move := direction.limit_length(1)
	if move.x < 0: Input.action_press("move_left", -move.x)
	if move.x > 0: Input.action_press("move_right", move.x)
	if move.y < 0: Input.action_press("move_up", -move.y)
	if move.y > 0: Input.action_press("move_down", move.y)

func _process(_delta: float) -> void:
	if ending: return
	if Time.get_ticks_msec() - watchdog_start >= 42000:
		watchdog()
		return
	if not observing: return
	if is_instance_valid(target) and stage_name == "rage_and_cooldown": pointer(target.position)
	else: pointer(aim_target)

func _physics_process(_delta: float) -> void:
	if not observing: return
	collect_releases()

func collect_releases() -> void:
	var events: Array = room.player.get_node("HeroFeedback").release_events
	while release_cursor < events.size():
		var event: Dictionary = events[release_cursor].duplicate(true)
		event.merge(stamp())
		releases.append(event)
		release_cursor += 1

func on_cue(cue: String) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"cue":cue, "voices":room.combat_audio.active_voice_count()})
	cues.append(event)

func on_damage(amount: float) -> void:
	if not observing: return
	var event := stamp()
	event.merge({"amount":amount, "hp_after":target.health.current,
		"source":str(target.last_damage_context.get("skill_slot", target.last_damage_context.get("damage_source", ""))),
		"attack_id":str(target.last_damage_context.get("attack_id", "")),
		"target_position":target.position, "target_id":target.get_instance_id()})
	damages.append(event)

func contact_snapshot() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for hit: Dictionary in room.impact_feedback.events:
		if str(hit.get("kind", "")) != "hit": continue
		var copy: Dictionary = hit.duplicate(true)
		copy.erase("anchor"); copy.erase("visual_anchor")
		events.append(copy)
	return events

func snapshot() -> Dictionary:
	var player: Node2D = room.player
	var source: String = str(player.get_meta("hero_visual_source", ""))
	var visual_bank: String = str(player.get_meta("hero_visual_bank", ""))
	var frame_index: int = int(player.get_meta("hero_visual_frame", -1))
	var frame_name := ""
	if visual_bank in ["front", "back"] and source == str(expected_sources.get(visual_bank, "")) and frame_index in range(6):
		frame_name = str(metadata[visual_bank].frames[frame_index].name)
	var data := stamp()
	data.merge({"source":source, "bank":visual_bank, "frame_index":frame_index, "frame_name":frame_name,
		"frame_name_origin":"actual rendered metadata index mapped to enabled manifest; no atlas sampling call",
		"pose":str(player.get_meta("hero_visual_pose", "")), "pose_state":player.get_node("HeroFeedback").pose_state(),
		"target_hp":target.health.current if is_instance_valid(target) else 0,
		"target_position":target.position if is_instance_valid(target) else Vector2.ZERO,
		"player_position":player.position, "aim_direction":player.aim_direction,
		"resource":Game.run.resource if Game.run != null else 0, "cooldown":player.cooldowns.secondary,
		"busy":player.abilities.busy(), "hitstop":player.visual_hitstop,
		"camera":room.camera.impact_stats(), "contacts":contact_snapshot()})
	return data

func after_draw() -> void:
	if not observing or stage_name not in ["signature", "cancel", "moving_after_cancel"]: return
	var data := snapshot()
	samples.append(data)
	if stage_name == "signature" and str(data.bank) == bank and str(data.source) == str(expected_sources.get(bank, "")) and not str(data.frame_name).is_empty():
		var name: String = str(data.frame_name)
		if not per_cast_frames.has(name): per_cast_frames.append(name)
		if not bank_frames[bank].has(name):
			bank_frames[bank][name] = {"image":stage.get_texture().get_image(), "sample":data.duplicate(true)}
			bank_order[bank].append(name)
	if stage_name == "moving_after_cancel" and cancel_frame.is_empty() and room.player.dash_remaining <= 0 and room.player.velocity.length() > 1 and not bool(data.busy) and str(data.source) not in expected_sources.values():
		cancel_frame = {"image":stage.get_texture().get_image(), "sample":data.duplicate(true)}

func validate_assets() -> bool:
	var valid := true
	for next_bank: String in ["front", "back"]:
		var path: String = "res://assets/generated/heroes/CH01_secondary_%s_v1.json" % next_bank
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var enabled: bool = parsed is Dictionary and typeof(parsed.get("enabled")) == TYPE_BOOL and parsed.enabled
		check(enabled, next_bank + " CH01 secondary manifest explicitly enabled")
		if not enabled:
			valid = false
			continue
		var clip: Dictionary = Atlas.load_clip(path)
		check(not clip.is_empty(), next_bank + " approved real authored clip loads")
		if clip.is_empty():
			valid = false
			continue
		var names: Array[String] = []
		for definition: Dictionary in parsed.frames: names.append(str(definition.name))
		check(names == FRAME_NAMES and parsed.phase_frames == {"windup":["plant", "coil", "drive"], "release":["contact"], "recovery":["follow", "ready"]}, next_bank + " exact six-frame contract")
		metadata[next_bank] = parsed
		expected_sources[next_bank] = str(parsed.texture)
		for frame: Dictionary in clip.frames.values(): check(float(frame.body_height) == 88 and frame.anchors.foot == Vector2(0, 8), next_bank + " body height/foot anchor")
	return valid

func spawn_training_target(distance: float) -> void:
	if is_instance_valid(target): target.free()
	target = room.spawn_enemy(room.player.position + direction_for(bank) * distance, "M01", 8, {"reward_enabled":false})
	target.health.reset(10000)
	target.training_ai_disabled = true
	target.health.damaged.connect(on_damage)
	pointer(target.position)

func prepare_cast(next_bank: String, next_case: String, whiff: bool) -> bool:
	bank = next_bank
	case_name = next_case
	stage_name = "rage_and_cooldown"
	spawn_training_target(75)
	var cost: float = float(room.player.skill_definition("secondary").cost)
	var deadline: int = Time.get_ticks_msec() + 8000
	var next_basic := 0.0
	while Time.get_ticks_msec() < deadline and not ending:
		pointer(target.position)
		var offset: Vector2 = target.position - room.player.position
		movement(offset.normalized() if offset.length() > 85 else Vector2.ZERO)
		if Game.run.resource < cost + 8 and room.elapsed >= next_basic:
			next_basic = room.elapsed + .20
			var before: float = Game.run.resource
			var accepted: bool = room.player.fire(room.player.aim_direction)
			var action := stamp()
			action.merge({"slot":"basic", "accepted":accepted, "resource_at_request":before, "purpose":"earn rage through actual hit during natural cooldown"})
			actions.append(action)
		if float(room.player.cooldowns.secondary) <= 0 and not room.player.abilities.busy() and room.player.attack_remaining <= 0 and Game.run.resource >= cost + 1:
			break
		await get_tree().process_frame
	if ending: return false
	movement(Vector2.ZERO)
	var ready: bool = float(room.player.cooldowns.secondary) <= 0 and not room.player.abilities.busy() and room.player.attack_remaining <= 0 and Game.run.resource >= cost
	check(ready, next_case + " real cooldown expires and natural basic-hit rage funds skill")
	spawn_training_target(400 if whiff else 80)
	stage_name = "aim_ready"
	for _index in 3:
		pointer(target.position)
		await get_tree().physics_frame
		await get_tree().process_frame
	check(room.player.aim_direction.dot(direction_for(bank)) > .995, next_case + " actual local pointer selects requested bank/direction")
	return ready

func record_cast(next_bank: String, hit: bool) -> void:
	var label: String = next_bank + ("_hit" if hit else "_whiff")
	if not await prepare_cast(next_bank, label, not hit): return
	var before: Dictionary = snapshot()
	var damage_start: int = damages.size()
	var cue_start: int = cues.size()
	var release_start: int = releases.size()
	var sample_start: int = samples.size()
	per_cast_frames = []
	stage_name = "signature"
	cast_elapsed = room.elapsed
	var accepted: bool = room.player.cast_skill("secondary", target.position)
	check(accepted, label + " public right-click cast commits")
	var action := stamp()
	action.merge({"slot":"secondary", "accepted":accepted, "resource_before":before.resource, "resource_after":Game.run.resource, "cooldown_after_commit":room.player.cooldowns.secondary})
	actions.append(action)
	var deadline: int = Time.get_ticks_msec() + 1800
	while room.elapsed - cast_elapsed < .95 and Time.get_ticks_msec() < deadline and not ending:
		await get_tree().process_frame
	if ending: return
	collect_releases()
	stage_name = "between_casts"
	var actual_releases: Array = releases.slice(release_start)
	var actual_damage: Array = damages.slice(damage_start)
	var actual_cues: Array = cues.slice(cue_start)
	var contact_hits: Array[Dictionary] = []
	for damage: Dictionary in actual_damage:
		if str(damage.source) == "secondary": contact_hits.append(damage)
	check(actual_releases.size() == 1 and str(actual_releases[0].slot) == "secondary", label + " one real release")
	check((not contact_hits.is_empty()) == hit and (target.health.current < float(before.target_hp)) == hit, label + " genuine hit/whiff outcome")
	check(not room.player.abilities.busy(), label + " recovery finishes naturally")
	var release_cues := 0
	var impact_cues: Array[Dictionary] = []
	for cue: Dictionary in actual_cues:
		if str(cue.cue) == "secondary": release_cues += 1
		if str(cue.cue) in ["impact", "heavy"]: impact_cues.append(cue)
	check(release_cues == 1 and (not impact_cues.is_empty()) == hit, label + " release sound once and contact sound only on a real hit")
	if hit and not contact_hits.is_empty() and not impact_cues.is_empty():
		check(absf(float(contact_hits[0].physics_seconds) - float(impact_cues[0].physics_seconds)) <= .02, label + " actual contact audio matches damage physics tick")
		check(absf(float(contact_hits[0].physics_seconds) - float(action.physics_seconds) - .18) <= .035, label + " damage occurs at real .18-second release boundary")
	var missing: Array[String] = []
	for name: String in FRAME_NAMES:
		if not per_cast_frames.has(name): missing.append(name)
	var maximum_hitstop := 0.0
	for sample: Dictionary in samples.slice(sample_start): maximum_hitstop = maxf(maximum_hitstop, float(sample.hitstop))
	check((maximum_hitstop > 0) == hit, label + " hit-pause only follows confirmed contact")
	check(not per_cast_frames.is_empty(), label + " real renderer consumes enabled secondary atlas")
	records.append({"case":label, "bank":bank, "expected_hit":hit, "before":before, "after":snapshot(),
		"action":action, "release_events":actual_releases, "actual_damage":actual_damage, "audio_cues":actual_cues,
		"captured_frame_names":per_cast_frames.duplicate(), "missing_frame_names":missing,
		"maximum_observed_hitstop":maximum_hitstop, "native_elapsed":room.elapsed - cast_elapsed})
	print("HAMMER_NATIVE case=", label, " frames=", per_cast_frames, " missing=", missing, " actual_hits=", contact_hits.size())

func record_cancel() -> void:
	if not await prepare_cast("front", "cancel_then_move", true): return
	stage_name = "cancel"
	var start: float = room.elapsed
	var release_start: int = releases.size()
	var damage_start: int = damages.size()
	var cue_start: int = cues.size()
	check(room.player.cast_skill("secondary", target.position), "cancel scenario starts genuine right-click windup")
	var committed_resource: float = Game.run.resource
	while room.elapsed - start < .05 and not ending: await get_tree().process_frame
	if ending: return
	var cancelled_at: Dictionary = stamp()
	var cancelled: bool = room.player.start_dash(Vector2.LEFT)
	check(cancelled and not room.player.abilities.busy(), "public dash cancels right-click windup before release")
	check(Game.run.resource <= committed_resource and float(room.player.cooldowns.secondary) > 0, "cancellation retains committed rage and cooldown")
	stage_name = "moving_after_cancel"
	var move_start: Vector2 = room.player.position
	movement(Vector2.LEFT)
	while room.elapsed - start < .85 and not ending: await get_tree().process_frame
	if ending: return
	movement(Vector2.ZERO)
	collect_releases()
	var forbidden_audio := false
	for cue: Dictionary in cues.slice(cue_start):
		if str(cue.cue) in ["secondary", "impact", "heavy"]: forbidden_audio = true
	check(releases.size() == release_start and damages.size() == damage_start and not forbidden_audio, "cancelled windup creates no later release, contact or delayed impact sound")
	check(room.player.position.distance_to(move_start) > 20 and not room.player.abilities.busy() and not cancel_frame.is_empty(), "actual movement resumes without a stale secondary pose")
	records.append({"case":"cancel_then_move", "cancel_at":cancelled_at,
		"cancelled":cancelled, "resource_after_commit":committed_resource, "final":snapshot(),
		"audio_cues":cues.slice(cue_start), "release_count":releases.size() - release_start,
		"damage_count":damages.size() - damage_start, "captured_moving_frame":cancel_frame.get("sample", {})})
	stage_name = "finished"

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
	check(recording != null and not recording.data.is_empty(), "native original Master mix contains PCM")
	if recording == null or recording.data.is_empty(): return {"status":"missing", "reason":"No PCM; no unmuted retry"}
	var peak := 0.0
	var energy := 0.0
	var pcm: PackedByteArray = recording.data
	for offset in range(0, pcm.size() - 1, 2):
		var value: float = float(pcm.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value)); energy += value * value
	var path := "hammer_secondary_native_mix.wav"
	var saved: Error = recording.save_to_wav(OUTPUT.path_join(path))
	check(saved == OK and peak > .000001 and peak < 1, "native unmodified SFX PCM saved, non-silent and unclipped")
	return {"status":"saved" if saved == OK else "failed", "path":path, "duration":recording.get_length(),
		"mix_rate":recording.mix_rate, "stereo":recording.stereo, "peak":peak, "rms":sqrt(energy / maxf(1, pcm.size() / 2.0)), "bgm":false}

func save_frames() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for next_bank: String in ["front", "back"]:
		var missing: Array[String] = []
		var files: Array[Dictionary] = []
		for name: String in FRAME_NAMES:
			if not bank_frames[next_bank].has(name):
				missing.append(name)
				continue
			var capture: Dictionary = bank_frames[next_bank][name]
			var filename: String = "CH01_secondary_" + next_bank + "_" + name + ".png"
			var bitmap: Image = capture.image
			check(bitmap.get_size() == Vector2i(1280, 720) and bitmap.save_png(OUTPUT.path_join(filename)) == OK, "save actual native frame " + filename)
			files.append({"path":filename, "sample":capture.sample})
		check(not files.is_empty(), next_bank + " has actual authored frames; no fallback-only pass")
		summaries.append({"bank":next_bank, "status":"all_six_observed" if missing.is_empty() else "explicit_native_frame_gaps",
			"missing_frame_names":missing, "first_observed_order":bank_order[next_bank], "files":files})
	if not cancel_frame.is_empty():
		var bitmap: Image = cancel_frame.image
		check(bitmap.save_png(OUTPUT.path_join("cancelled_moving.png")) == OK, "save actual movement after cancellation")
	return summaries

func write_report(bank_summary: Array = [], timed_out: bool = false) -> void:
	var file := FileAccess.open(OUTPUT.path_join("native_capture.json"), FileAccess.WRITE)
	check(file != null, "open hammer native report")
	if file == null: return
	file.store_string(JSON.stringify({"method":METHOD, "checks":checks + 1, "failures":failures,
		"timed_out":timed_out, "initial":initial, "banks":bank_summary, "cases":records,
		"all_render_samples":samples, "all_public_actions":actions, "actual_damage":damages,
		"accepted_audio_cues":cues, "actual_releases":releases, "recording":recording_info,
		"total_wall_seconds":(Time.get_ticks_msec() - watchdog_start) / 1000.0}, "\t"))
	check(file.get_error() == OK, "write hammer native report")
	file.close()

func cleanup() -> void:
	observing = false
	movement(Vector2.ZERO)
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
	push_error("Hammer secondary native capture hit 42-second watchdog; cleanup and quit")
	cleanup()
	write_report([], true)
	get_tree().quit(1)

func run_capture() -> void:
	if not str(Game.profile_path).contains("test_hammer_secondary_native") or DisplayServer.get_name() == "headless":
		ending = true
		push_error("Hammer native capture requires isolated test_hammer_secondary_native profile and actual graphical renderer")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	if not validate_assets():
		ending = true
		write_report()
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	for key: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(key): InputMap.add_action(key)
		Input.action_release(key)
	check(Game.new_profile() and Game.start_demo("CH01", 0), "genuine standard CH01 Lv8 demo starts")
	if Game.run == null:
		ending = true
		write_report(); get_tree().quit(1)
		return
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	var display := TextureRect.new()
	display.texture = stage.get_texture(); display.size = Vector2(1280, 720)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	room = load("res://scenes/room.tscn").instantiate()
	room.geometry_enabled = false; room.spawn_enabled = false; room.relic_positions = {}
	stage.add_child(room)
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(1400, 900)
	room.release_gate = false; room.input_blocked = false
	room.combat_audio.cue_played.connect(on_cue)
	hud_layer = CanvasLayer.new(); stage.add_child(hud_layer)
	var hud: Control = load("res://scripts/ui/hud.gd").new(); hud.room = room
	hud_layer.add_child(hud); hud.size = Vector2(1280, 720)
	var specification: Dictionary = room.player.skill_definition("secondary")
	check(Game.run.level == 8 and Game.run.loadout_snapshot.size() == 6, "standard Lv8 complete starter build")
	check(is_equal_approx(float(specification.windup), .18) and is_equal_approx(float(specification.duration), .54) and is_equal_approx(float(specification.cooldown), 4), "actual secondary .18 windup/.54 duration/4 cooldown")
	check(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1 and room.camera.zoom == Vector2(.85, .85), "normal native 60Hz/.85 camera")
	initial = {"stats":Game.run.stats.duplicate(true), "loadout":Game.run.loadout_snapshot.duplicate(true), "resource":Game.run.resource, "skill":specification}
	start_wall = Time.get_ticks_msec(); start_elapsed = room.elapsed; start_tick = Engine.get_physics_frames()
	RenderingServer.frame_post_draw.connect(after_draw)
	start_recording(); observing = true
	for next_bank: String in ["front", "back"]:
		for hit: bool in [true, false]:
			await record_cast(next_bank, hit)
			if ending: return
	await record_cancel()
	if ending: return
	observing = false
	recording_info = stop_recording()
	check(Game.run.stats == initial.stats and Game.run.loadout_snapshot == initial.loadout, "player stats and equipment remain the real demo build")
	var summary: Array[Dictionary] = save_frames()
	await room.combat_audio.wait_for_cleanup()
	cleanup()
	ending = true
	RenderingServer.frame_post_draw.disconnect(after_draw)
	write_report(summary)
	print("HAMMER_SECONDARY_NATIVE_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
