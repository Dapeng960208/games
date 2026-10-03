extends Node
## Controlled presentation acceptance, NOT a normal-save/balance playthrough.
## tools/test.ps1 -Suite skill_feedback_capture -Graphical -SkipImport
## Real wall/physics clocks, public combat actions and actual projectile collision.

const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const SECONDS := 14.0
const RESOLVER = preload("res://scripts/domain/combat/stat_resolver.gd")
var checks := 0
var failures := 0
var room: Node2D
var music: Node
var stage: SubViewport
var presentation: TextureRect
var caption: Label
var targets: Array[Node2D] = []
var aim_target: Node2D
var hero := ""
var graphical := false
var observing := false
var start_wall := 0
var start_elapsed := 0.0
var release_cursor := 0
var max_voices := 0
var captured := false
var pending_capture := false
var cues: Array[Dictionary] = []
var releases: Array[Dictionary] = []
var damage: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var configurations: Array[Dictionary] = []
var reports: Array[Dictionary] = []
var capture_report: Dictionary = {}
var recorder: AudioEffectRecord
var recorder_slot := -1

func _ready() -> void:
	call_deferred("run_probe")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SKILL_FEEDBACK_CAPTURE FAIL: " + label)

func stamp() -> Dictionary:
	return {"wall_seconds": (Time.get_ticks_msec() - start_wall) / 1000.0,
		"physics_seconds": snappedf(room.elapsed - start_elapsed, .0001)}

func movement(direction: Vector2) -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)
	if direction.x < 0: Input.action_press("move_left", -direction.x)
	if direction.x > 0: Input.action_press("move_right", direction.x)
	if direction.y < 0: Input.action_press("move_up", -direction.y)
	if direction.y > 0: Input.action_press("move_down", direction.y)

func aim(at: Vector2) -> void:
	var pointer := InputEventMouseMotion.new()
	pointer.position = room.get_canvas_transform() * room.to_global(at)
	pointer.global_position = pointer.position
	stage.push_input(pointer, true)

func _process(_delta: float) -> void:
	if not observing: return
	if is_instance_valid(aim_target): aim(aim_target.position)
	var direction := Vector2.ZERO
	if hero == "CH01" and is_instance_valid(aim_target) and not room.player.abilities.busy():
		if room.player.position.distance_to(aim_target.position) > 65.0:
			direction = room.player.position.direction_to(aim_target.position)
	movement(direction)
	max_voices = maxi(max_voices, room.combat_audio.active_voice_count())
	collect_releases()

func collect_releases() -> void:
	var events: Array = room.player.get_node("HeroFeedback").release_events
	while release_cursor < events.size():
		var event: Dictionary = events[release_cursor].duplicate(true)
		event.merge(stamp())
		releases.append(event)
		release_cursor += 1

func on_cue(cue: String) -> void:
	# Same accepted-impact music callback as main.gd; no custom mix/gain.
	if cue in ["impact", "heavy"]: music.notify_impact(cue == "heavy")
	if not observing: return
	var event := stamp()
	event.merge({"cue": cue, "active_voices": room.combat_audio.active_voice_count(),
		"impact_duck_gain": music.impact_duck_gain()})
	cues.append(event)

func on_damage(amount: float, target: Node2D) -> void:
	if not observing: return
	var context: Dictionary = target.last_damage_context
	var event := stamp()
	event.merge({"enemy_id": target.enemy_id, "material": target.impact_material(),
		"amount": amount, "source": str(context.get("skill_slot", context.get("damage_source", ""))),
		"damage_source": str(context.get("damage_source", "")),
		"attack_id": str(context.get("attack_id", "")), "hp_after": target.health.current})
	damage.append(event)
	var representative: bool = str(event.source) == ("q" if hero == "CH03" else "secondary")
	if graphical and not captured and representative:
		captured = true
		capture_contact(event)

func capture_contact(event: Dictionary) -> void:
	pending_capture = true
	capture_report = {"trigger": event.duplicate(true)}
	await RenderingServer.frame_post_draw
	var filename: String = "skill_feedback_" + hero + "_contact.png"
	var status: Error = stage.get_texture().get_image().save_png("res://artifacts/" + filename)
	check(status == OK, hero + " real contact framebuffer saved")
	capture_report.merge({"path": filename, "rendered_at": stamp(),
		"impact_events_rendered": room.impact_feedback.events.size()})
	pending_capture = false

func wait_until(seconds: float) -> void:
	while (Time.get_ticks_msec() - start_wall) / 1000.0 < seconds:
		await get_tree().process_frame

func choose_target(slot: String) -> Node2D:
	var selected: Node2D = targets[0]
	var best := INF
	var desired: float = 180.0 if hero == "CH01" and slot == "q" else 60.0 if hero == "CH01" else 240.0
	for target: Node2D in targets:
		var score: float = absf(room.player.position.distance_to(target.position) - desired)
		if score < best:
			best = score
			selected = target
	return selected

func perform(at_time: float, slot: String, reset_cooldown: bool = false) -> int:
	await wait_until(at_time)
	aim_target = choose_target(slot)
	aim(aim_target.position)
	await get_tree().physics_frame
	await get_tree().process_frame
	var event := stamp()
	event.merge({"action": slot, "target": aim_target.enemy_id,
		"target_distance": room.player.position.distance_to(aim_target.position),
		"resource_before_test_refill": Game.run.resource})
	if slot != "basic":
		# Explicit test configuration, never presented as ordinary resource pacing.
		Game.run.resource = float(Game.run.stats.get("resource_max", 100.0))
		configurations.append({"at": stamp(), "change": "refill resource before representative skill", "value": Game.run.resource})
		if reset_cooldown:
			configurations.append({"at": stamp(), "change": "reset ultimate cooldown for cancellation sample", "previous": room.player.cooldowns[slot]})
			room.player.cooldowns[slot] = 0.0
	var cast_target: Vector2 = aim_target.position
	if hero == "CH03" and slot in ["secondary", "ultimate"]:
		# Real basic knockback can move the target beyond legal ground-cast range.
		# Choose legal ground near it, rather than overriding targets or cast rules.
		var cast_range: float = float(room.player.skill_definition(slot).range) - 8.0
		cast_target = room.player.position + (cast_target - room.player.position).limit_length(cast_range)
	event["cast_target"] = [cast_target.x, cast_target.y]
	var accepted: bool = room.player.fire(room.player.position.direction_to(aim_target.position)) if slot == "basic" else room.player.cast_skill(slot, cast_target)
	event.merge({"accepted": accepted, "cast_serial": room.player.abilities.cast_serial,
		"rejection": "" if accepted else room.player.last_cast_error})
	actions.append(event)
	check(accepted, hero + " scheduled " + slot + " accepted")
	caption.text = hero + " / Lv8 训练演示 · " + ("鼠标左键 · 普攻" if slot == "basic" else "鼠标右键 · " + str(room.player.skill_definition(slot).name) if slot == "secondary" else slot.to_upper() + " · " + str(room.player.skill_definition(slot).name))
	return int(room.player.abilities.cast_serial)

func start_recording() -> void:
	if not graphical: return
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	recorder.set_recording_active(true)

func stop_recording() -> Dictionary:
	if recorder == null:
		return {"status": "skipped", "reason": "Headless is not audible-mix acceptance."}
	recorder.set_recording_active(false)
	var recording: AudioStreamWAV = recorder.get_recording()
	AudioServer.remove_bus_effect(0, recorder_slot)
	recorder = null
	if recording == null or recording.data.is_empty():
		return {"status": "unavailable", "reason": "Muted Master returned no PCM; no unmuted retry."}
	var pcm: PackedByteArray = recording.data
	var peak := 0.0
	var energy := 0.0
	for offset in range(0, pcm.size() - 1, 2):
		var sample_value: float = float(pcm.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(sample_value))
		energy += sample_value * sample_value
	var filename: String = "skill_feedback_" + hero + "_native_mix.wav"
	var result: Error = recording.save_to_wav("res://artifacts/" + filename)
	check(result == OK and peak > .000001 and peak < 1.0, hero + " real native mix is non-silent and not clipped")
	return {"status": "saved" if result == OK else "unavailable", "path": filename,
		"duration": recording.get_length(), "mix_rate": recording.mix_rate, "stereo": recording.stereo,
		"peak": peak, "rms": sqrt(energy / maxf(1.0, pcm.size() / 2.0)),
		"source": "Unmodified Master-bus recording before safety mute; original game music and SFX, no microphone, gain, normalization, or audio editing."}

func make_fixture(next_hero: String) -> void:
	hero = next_hero
	check(Game.new_profile() and Game.select_hero(hero) and Game.start_run(), hero + " isolated test run")
	Game.run.level = 8
	Game.run.stats = RESOLVER.resolve(hero, 8, {}, {})
	Game.run.stats.crit_chance = 0.0
	Game.run.max_hp = float(Game.run.stats.max_hp)
	Game.run.hp = Game.run.max_hp
	Game.run.resource = float(Game.run.stats.get("resource_max", 100.0))
	Game.run.relics.clear()
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.spawn_enabled = false
	room.relic_positions = {}
	stage.add_child(room)
	for child: Node in room.enemies.get_children(): child.free()
	room.player.position = Vector2(1100, 850)
	room.release_gate = false
	room.input_blocked = false
	targets.clear()
	var offsets: Array = [Vector2(70, 0), Vector2(205, -25), Vector2(300, 50)] if hero == "CH01" else [Vector2(220, 0), Vector2(260, -90), Vector2(270, 100)]
	var ids: Array[String] = ["M01", "M10", "M31"]
	for index in ids.size():
		var target: Node2D = room.spawn_enemy(room.player.position + offsets[index], ids[index], 8, {"reward_enabled": false})
		target.health.reset(10000.0)
		target.training_ai_disabled = true
		target.state = &"chase"
		target.health.damaged.connect(on_damage.bind(target))
		targets.append(target)
	aim_target = targets[0]
	music = load(AssetCatalog.resolve("res://scripts/infrastructure/audio/music_director.gd")).new()
	add_child(music)
	music.configure(Game)
	music.set_context("combat")
	room.combat_audio.cue_played.connect(on_cue)
	await get_tree().physics_frame
	await get_tree().process_frame
	aim(aim_target.position)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(room.player.aim_direction.dot(room.player.position.direction_to(aim_target.position)) > .99, hero + " local engine mouse reader agrees with target")
	cues = []; releases = []; damage = []; actions = []; configurations = []
	release_cursor = 0; max_voices = 0; captured = false; capture_report = {}
	start_elapsed = room.elapsed
	start_wall = Time.get_ticks_msec()
	observing = true
	start_recording()

func run_probe() -> void:
	if not str(Game.profile_path).contains("test_skill_feedback_capture"):
		push_error("Refusing non-isolated test profile.")
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	AudioServer.set_bus_mute(0, true)
	get_tree().create_timer(100.0).timeout.connect(func(): push_error("Skill capture timed out"); get_tree().quit(1))
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage = SubViewport.new()
	stage.size = Vector2i(1280, 720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	add_child(stage)
	presentation = TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280, 720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(28, 26)
	caption.add_theme_font_override("font", load(AssetCatalog.resolve("asset://fonts/NotoSansSC.ttf")))
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(caption)
	for next_hero: String in HEROES:
		seed(41827)
		await make_fixture(next_hero)
		await perform(.5, "basic")
		await perform(1.5, "basic")
		await perform(2.5, "secondary")
		await perform(3.8, "basic")
		await perform(4.8, "q")
		await perform(6.0, "basic")
		var full_r_serial := -1
		var cancelled_r_serial := -1
		if hero == "CH03":
			await perform(6.8, "f")
			await perform(8.2, "ultimate")
		else:
			full_r_serial = await perform(7.1, "ultimate")
			if hero == "CH02":
				cancelled_r_serial = await perform(10.0, "ultimate", true)
				var cancel_wall: float = (Time.get_ticks_msec() - start_wall) / 1000.0 + .36
				await wait_until(cancel_wall)
				var cancelled: bool = room.player.start_dash(Vector2.DOWN)
				var cancellation := stamp()
				cancellation.merge({"action": "dash_cancel_second_R", "accepted": cancelled, "cast_serial": cancelled_r_serial})
				actions.append(cancellation)
				check(cancelled and not room.player.abilities.busy(), "CH02 real dash cancels remaining R events")
			else:
				await perform(10.0, "basic")
		await wait_until(SECONDS)
		collect_releases()
		var recording := stop_recording()
		observing = false
		movement(Vector2.ZERO)
		while pending_capture: await get_tree().process_frame
		var source_counts: Dictionary = {}
		for hit: Dictionary in damage: source_counts[hit.source] = int(source_counts.get(hit.source, 0)) + 1
		check(int(source_counts.get("primary", 0)) > 0, hero + " real basics damaged training enemies")
		check(not releases.is_empty() and not damage.is_empty(), hero + " actual ability releases and contacts observed")
		check(max_voices <= 8, hero + " bounded SFX voices")
		if graphical: check(not capture_report.is_empty(), hero + " representative actual contact captured")
		if hero == "CH02":
			var full_count := 0
			var cancelled_count := 0
			for release: Dictionary in releases:
				if int(release.serial) == full_r_serial: full_count += 1
				if int(release.serial) == cancelled_r_serial: cancelled_count += 1
			check(full_count == 4 and cancelled_count == 1, "CH02 four live R releases then one release before cancellation")
		var report: Dictionary = {"hero": hero, "level": 8, "wall_seconds": stamp().wall_seconds,
			"physics_seconds": stamp().physics_seconds, "stats": Game.run.stats.duplicate(true),
			"settings": Game.profile.settings.duplicate(true), "actions": actions.duplicate(true),
			"fixture_changes": configurations.duplicate(true), "release_timeline": releases.duplicate(true),
			"accepted_cue_timeline": cues.duplicate(true), "damage_timeline": damage.duplicate(true),
			"damage_count_by_source": source_counts, "sfx_voices_peak": max_voices,
			"contact_screenshot": capture_report.duplicate(true), "recording": recording}
		reports.append(report)
		print("SKILL_FEEDBACK_HERO ", JSON.stringify({"hero": hero, "damage_count_by_source": source_counts,
			"releases": releases.size(), "accepted_cues": cues.size(), "recording": recording}))
		await room.combat_audio.wait_for_cleanup()
		await music.wait_for_cleanup()
		room.free()
		music.free()
		Game.finish_run("abandoned")
		await get_tree().process_frame
	var file := FileAccess.open(AssetCatalog.resolve("res://artifacts/skill_feedback_" + ("graphical" if graphical else "headless") + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"method": "Controlled Lv8 presentation fixture, not normal-save progression or balance. Real room/player/enemy/skill/projectile/camera with native wall and physics clocks; standalone SubViewport local pointer. Public fire/cast/dash; no direct damage or manual ability ticks. M01/M10/M31 Lv8, 10000 HP each, AI disabled, rewards disabled. Geometry/random spawning disabled, fixed initial actor positions, no relics, no equipment bonuses, crit chance zero. Each skill receives a declared test resource refill; second CH02 R gets a declared cooldown reset. Production music director with main's impact callback and ordinary mix settings. Framebuffer PNGs and original Master PCM only; no subjective hearing-quality certification.",
		"graphical": graphical, "seconds_per_hero": SECONDS, "master_safety_muted": AudioServer.is_bus_mute(0),
		"reports": reports, "checks": checks, "failures": failures}, "\t"))
	file.close()
	print("SKILL_FEEDBACK_CAPTURE_RESULT checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
