extends "res://tests/combat/test_combat_playability.gd"
## Observational acceptance: normal Lv1 starters, real enemy AI and world geometry.
## Inherits the movement/action bot; aim uses official local Viewport input.
## Never patches damage, HP, actor positions, resources or release-time aim.
## tools/test.ps1 -Suite crowd_feedback -SkipImport [-Graphical]

const OBSERVATION_SECONDS := 30.0
var graphical := false
var observing := false
var observed_enemies: Dictionary = {}
var cue_counts: Dictionary = {}
var cue_timeline: Array[Dictionary] = []
var damage_events := 0
var consumed_health := 0.0
var actual_deaths := 0
var voices_peak := 0
var bodies_peak := 0
var music_streams_peak := 0
var body_accepts := 0
var music_gain_min := INF
var music_gain_max := 0.0
var impact_duck_min := 1.0
var screenshot_records: Array[Dictionary] = []
var combat_capture_started := false
var kill_capture_started := false
var pending_captures := 0
var observation_wall_start := 0
var recorder: AudioEffectRecord
var recording_slot := -1
var recording_start := 0
var recording_report: Dictionary = {}
var pending_swing: Dictionary = {}
var swing_observations: Array[Dictionary] = []
var pointer_requests := 0
var pointer_clipped_requests := 0
var pointer_max_world_error := 0.0
var pointer_last_request: Dictionary = {}
var pointer_preflight: Array[Dictionary] = []
var stage: SubViewport
var presentation: TextureRect

func aim(at: Vector2) -> void:
	var room: Node2D = app.room
	var viewport: Viewport = room.get_viewport()
	var world_requested: Vector2 = room.to_global(at)
	var viewport_requested: Vector2 = room.get_canvas_transform()*world_requested
	var inside: Rect2 = viewport.get_visible_rect().grow(-4.0)
	var viewport_applied := Vector2(clampf(viewport_requested.x,inside.position.x,inside.end.x),clampf(viewport_requested.y,inside.position.y,inside.end.y))
	# A standalone SubViewport stores local event positions through push_input.
	# The unmodified player reads that same engine-owned mouse position in physics.
	# No OS cursor, direct aim write, or attack release override is involved.
	var event := InputEventMouseMotion.new()
	event.position = viewport_applied
	event.global_position = viewport_applied
	viewport.push_input(event,true)
	var world_applied: Vector2 = room.get_canvas_transform().affine_inverse()*viewport_applied
	var actual: Vector2 = room.player.get_global_mouse_position()
	var error: float = actual.distance_to(world_applied)
	pointer_requests += 1
	var clipped: bool = viewport_applied.distance_to(viewport_requested)>1.0
	if clipped: pointer_clipped_requests += 1
	pointer_max_world_error = maxf(pointer_max_world_error,error)
	pointer_last_request = {"world_requested":[world_requested.x,world_requested.y],
		"world_applied":[world_applied.x,world_applied.y],"actual_world":[actual.x,actual.y],
		"world_error":error,"clipped_to_window":clipped}

func verify_local_pointer(hero: String) -> bool:
	# Both directions are on screen at the ordinary entrance. Enemy AI and physics
	# remain live while the local pointer event reaches the player's own reader.
	for offset: Vector2 in [Vector2(-50,40),Vector2(70,-35)]:
		var requested: Vector2 = app.room.player.position+offset
		aim(requested)
		await frames(1)
		var actual: Vector2 = app.room.player.get_global_mouse_position()
		var world_requested: Vector2 = app.room.to_global(requested)
		var error: float = actual.distance_to(world_requested)
		var expected_direction: Vector2 = app.room.player.global_position.direction_to(actual)
		var direction_dot: float = app.room.player.aim_direction.dot(expected_direction)
		var passed: bool = error<=3.0 and direction_dot>.98 and not bool(pointer_last_request.clipped_to_window)
		pointer_preflight.append({"world_requested":[world_requested.x,world_requested.y],
			"actual_world":[actual.x,actual.y],"world_error":error,"production_aim_dot":direction_dot,"passed":passed})
		check(passed,hero+" official local mouse world target and production aim agree")
		if not passed:
			print("CROWD_POINTER_FAILURE ",JSON.stringify(pointer_preflight))
			print("CROWD_POINTER_COORDINATES viewport_size=",stage.size,
				" viewport_mouse=",stage.get_mouse_position()," canvas=",app.room.get_canvas_transform(),
				" immediate_request=",JSON.stringify(pointer_last_request))
			return false
	return true

func _process(_delta: float) -> void:
	if not observing or not is_instance_valid(app) or not is_instance_valid(app.room):
		return
	var room: Node2D = app.room
	voices_peak = maxi(voices_peak, room.combat_audio.active_voice_count())
	bodies_peak = maxi(bodies_peak, room.defeat_feedback.events.size())
	body_accepts = room.defeat_feedback.accepted_events
	music_streams_peak = maxi(music_streams_peak, app.music.active_stream_count())
	music_gain_min = minf(music_gain_min, app.music.effective_music_gain())
	music_gain_max = maxf(music_gain_max, app.music.effective_music_gain())
	impact_duck_min = minf(impact_duck_min, app.music.impact_duck_gain())
	if not pending_swing.is_empty() and room.player.attack_resolved:
		var swing: Dictionary = pending_swing.duplicate()
		var enemy: Node2D = pending_swing.target.get_ref()
		swing.erase("target")
		swing["resolved_time"] = snappedf(room.elapsed-start_elapsed,.001)
		swing["attack_remaining"] = room.player.attack_remaining
		swing["dashing"] = room.player.dash_remaining>0.0
		swing["player_position"] = [room.player.position.x,room.player.position.y]
		swing["release_direction"] = [room.player._attack_direction.x,room.player._attack_direction.y]
		var mouse_world: Vector2 = room.player.get_global_mouse_position()
		swing["release_mouse_world"] = [mouse_world.x,mouse_world.y]
		swing["release_mouse_angle_degrees"] = rad_to_deg(absf(room.player._attack_direction.angle_to(mouse_world-room.player.global_position)))
		swing["damage_callbacks_since_start"] = damage_events-int(swing.damage_callbacks_at_start)
		if is_instance_valid(enemy):
			var offset: Vector2 = enemy.position-room.player.position
			swing["target_distance_at_release"] = offset.length()
			swing["release_target_angle_degrees"] = rad_to_deg(absf(room.player._attack_direction.angle_to(offset)))
			swing["target_alive"] = enemy.is_alive()
			swing["line_of_sight_at_release"] = room.has_line_of_sight(room.player.position,enemy.position)
		swing_observations.append(swing)
		pending_swing.clear()
	if graphical and not combat_capture_started and room.elapsed-start_elapsed >= 5.0:
		combat_capture_started = true
		capture_frame("combat")
	if recorder != null and Time.get_ticks_msec()-recording_start >= 10000:
		stop_recording()

func watch_enemy(enemy: Node) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.get("actor_kind") != "enemy":
		return
	var health: Node = enemy.get("health")
	if not is_instance_valid(health):
		watch_enemy.call_deferred(enemy)
		return
	var key: int = enemy.get_instance_id()
	if observed_enemies.has(key): return
	observed_enemies[key] = {"enemy_id":enemy.enemy_id,"hp":health.current,"max_hp":health.maximum}
	health.damaged.connect(on_enemy_damage.bind(key))
	health.depleted.connect(on_enemy_death.bind(key))

func on_enemy_damage(amount: float, key: int) -> void:
	if not observing: return
	var before: float = observed_enemies[key].hp
	consumed_health += minf(before, maxf(0.0, amount))
	observed_enemies[key].hp = maxf(0.0, before-amount)
	damage_events += 1

func on_enemy_death(key: int) -> void:
	if not observing: return
	actual_deaths += 1
	# EnemyActor's own depleted callback runs first, producing its real snapshot.
	# Capture follows the very next rendered frame; gameplay is never paused.
	if graphical and not kill_capture_started:
		kill_capture_started = true
		capture_frame("first_defeat", str(observed_enemies[key].enemy_id))

func on_cue(cue: String) -> void:
	if not observing: return
	cue_counts[cue] = int(cue_counts.get(cue,0))+1
	if cue == "attack" and str(current.hero) == "CH01":
		var enemy: Node2D = nearest_enemy()
		if enemy != null:
			pending_swing = {"target":weakref(enemy),"target_id":enemy.enemy_id,
				"start_time":snappedf(app.room.elapsed-start_elapsed,.001),
				"target_distance_at_start":enemy.position.distance_to(app.room.player.position),
				"damage_callbacks_at_start":damage_events,"pointer_request":pointer_last_request.duplicate(true)}
	if cue_timeline.size() < 1024:
		cue_timeline.append({"cue":cue,"time":snappedf(app.room.elapsed-start_elapsed,.001),
			"music_gain":snappedf(app.music.effective_music_gain(),.00001),
			"impact_duck_gain":snappedf(app.music.impact_duck_gain(),.00001),
			"active_sfx_voices":app.room.combat_audio.active_voice_count()})

func capture_frame(phase: String, enemy_id: String = "") -> void:
	if not graphical or not observing: return
	pending_captures += 1
	var capture: Dictionary = {"phase":phase,"enemy_id":enemy_id,"hero":current.hero,
		"requested_time":snappedf(app.room.elapsed-start_elapsed,.001),
		"kills_at_request":actual_deaths,"bodies_at_request":app.room.defeat_feedback.events.size()}
	await RenderingServer.frame_post_draw
	if is_instance_valid(app) and is_instance_valid(app.room):
		capture["rendered_time"] = snappedf(app.room.elapsed-start_elapsed,.001)
		capture["bodies_rendered"] = app.room.defeat_feedback.events.size()
		capture["body_ages"] = []
		for event: Dictionary in app.room.defeat_feedback.events:
			capture.body_ages.append(snappedf(event.age,.001))
		var filename: String = "crowd_feedback_"+str(current.hero)+"_"+phase+".png"
		var frame_image: Image = stage.get_texture().get_image()
		var status: Error = frame_image.save_png("res://artifacts/"+filename)
		check(status == OK, "real framebuffer saved "+filename)
		capture["path"] = filename if status == OK else ""
		screenshot_records.append(capture)
	pending_captures -= 1

func start_recording() -> void:
	recording_report = {"status":"skipped", "reason":"Headless Dummy mixer does not establish audible mixed-output quality."}
	if not graphical: return
	# The effect records the actual Master bus, upstream of its safety mute.
	# No microphone or external input is enabled. No synthesis/normalization is applied.
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recording_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder)
	recording_start = Time.get_ticks_msec()
	recorder.set_recording_active(true)
	recording_report = {"status":"recording","safety":"Master muted before the effect was installed; native game bus only"}

func stop_recording() -> void:
	if recorder == null: return
	recorder.set_recording_active(false)
	var recording: AudioStreamWAV = recorder.get_recording()
	AudioServer.remove_bus_effect(0, recording_slot)
	recorder = null
	recording_slot = -1
	if recording == null or recording.data.is_empty():
		recording_report = {"status":"unavailable","reason":"Master recording returned no PCM while safely muted; no unmuted retry attempted."}
		return
	var pcm: PackedByteArray = recording.data
	var peak := 0.0
	var energy := 0.0
	for offset in range(0,pcm.size()-1,2):
		var sample_value: float = float(pcm.decode_s16(offset))/32768.0
		peak = maxf(peak,absf(sample_value))
		energy += sample_value*sample_value
	if peak <= .000001:
		recording_report = {"status":"unavailable","reason":"Muted Master yielded silent PCM; scheduling metrics remain valid, recorded audio quality is unverified.","duration":recording.get_length()}
		return
	var filename: String = "crowd_feedback_"+str(current.hero)+"_native_mix.wav"
	var status: Error = recording.save_to_wav("res://artifacts/"+filename)
	recording_report = {"status":"saved" if status == OK else "unavailable","path":filename if status == OK else "",
		"duration":recording.get_length(),"peak":peak,"rms":sqrt(energy/maxf(1.0,pcm.size()/2.0)),
		"source":"Unmodified real Master-bus mix, before the safety mute; no microphone input or level normalization."}

func crowd_snapshot() -> Dictionary:
	var snapshot: Dictionary = observe()
	snapshot["actual_enemy_damage_events"] = damage_events
	snapshot["actual_enemy_deaths"] = actual_deaths
	snapshot["sfx_voices"] = app.room.combat_audio.active_voice_count()
	snapshot["defeat_bodies"] = app.room.defeat_feedback.events.size()
	snapshot["music_gain"] = snappedf(app.music.effective_music_gain(),.00001)
	snapshot["impact_duck_gain"] = snappedf(app.music.impact_duck_gain(),.00001)
	return snapshot

func run_probe() -> void:
	if not Game.profile_path.contains("test_crowd_feedback"):
		get_tree().quit(2)
		return
	graphical = DisplayServer.get_name() != "headless"
	get_viewport().size = Vector2i(1280,720)
	get_tree().create_timer(180.0).timeout.connect(func(): push_error("Crowd feedback probe exceeded 180 seconds"); get_tree().quit(1))
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	stage = SubViewport.new()
	stage.name = "CrowdLocalInputViewport"
	stage.size = Vector2i(1280,720)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.handle_input_locally = true
	# TextureRect presents this independent viewport without forwarding native OS
	# mouse input, unlike a SubViewportContainer. Production main is unchanged.
	add_child(stage)
	presentation = TextureRect.new()
	presentation.texture = stage.get_texture()
	presentation.size = Vector2(1280,720)
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	for hero: String in ["CH01","CH02","CH03"]:
		movement(Vector2.ZERO)
		check(Game.new_profile(),"fresh isolated profile "+hero)
		check(Game.select_hero(hero),"select normal hero "+hero)
		app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
		stage.add_child(app)
		await frames(2)
		check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0,"seed":SEED}),"normal seeded departure "+hero)
		await frames(2)
		for offer: Dictionary in Game.expedition_snapshot().get("relic_offers",[]):
			if str(offer.get("decision","")).is_empty(): app._choose_expedition_relic(str(offer.offer_id),"skip")
		app._clear_modals()
		var options: Array = app.expedition.next_options()
		check(not options.is_empty(),"real first room available "+hero)
		if options.is_empty(): get_tree().quit(1); return
		app._advance_expedition(str(options[0]))
		app._clear_modals()
		await frames(2)
		check(app.expedition.current_index()==1 and app.room.configuration_ready,"real combat room installed "+hero)
		check(Game.run.level==1 and not Game.run.demo and Game.run.relics.is_empty(),"normal Lv1 starter without trial boosts "+hero)
		check(is_instance_valid(app.room.get("defeat_feedback")),"production defeat layer installed "+hero)
		check(app.room.combat_audio.has_signal("cue_played"),"production accepted-cue observation signal "+hero)
		if not is_instance_valid(app.room.get("defeat_feedback")) or not app.room.combat_audio.has_signal("cue_played"):
			get_tree().quit(1); return
		current = {"hero":hero,"level":Game.run.level,"difficulty":0,"route_seed":SEED,"room":app.room.layout_id,
			"layout_seed":app.room.layout_seed,"stats":Game.run.stats.duplicate(true),"loadout":Game.run.loadout_snapshot.duplicate(true),
			"settings":Game.profile.settings.duplicate(true),"samples":[],"locked_slots":[]}
		for slot: String in ["q","secondary","f","ultimate"]:
			if Game.run.level < int(app.room.player.skill_definition(slot).unlock): current.locked_slots.append(slot)
		cast_counts = {}; cast_failures = {}; total_damage = 0; travelled = 0; idle_motion_seconds = 0; fire_successes = 0
		observed_enemies = {}; cue_counts = {}; cue_timeline = []; screenshot_records = []
		pending_swing = {}; swing_observations = []
		pointer_requests = 0; pointer_clipped_requests = 0; pointer_max_world_error = 0; pointer_last_request = {}; pointer_preflight = []
		damage_events = 0; consumed_health = 0; actual_deaths = 0; voices_peak = 0; bodies_peak = 0; body_accepts = 0; music_streams_peak = 0
		music_gain_min = INF; music_gain_max = 0; impact_duck_min = 1; combat_capture_started = false; kill_capture_started = false
		previous_hp = Game.run.hp
		last_position = app.room.player.position
		start_elapsed = app.room.elapsed
		observation_wall_start = Time.get_ticks_msec()
		seed(SEED)
		var initial_stats: Dictionary = Game.run.stats.duplicate(true)
		app.room.enemies.child_entered_tree.connect(watch_enemy)
		for enemy: Node in app.room.enemies.get_children(): watch_enemy(enemy)
		app.room.combat_audio.connect("cue_played",on_cue)
		if not await verify_local_pointer(hero):
			movement(Vector2.ZERO)
			await app.room.combat_audio.wait_for_cleanup()
			await app.music.wait_for_cleanup()
			get_tree().quit(1)
			return
		observing = true
		start_recording()
		var snapshot: Dictionary = crowd_snapshot()
		var next_sample := 0.0
		for tick in int(OBSERVATION_SECONDS*90):
			if Game.run == null or not is_instance_valid(app.room) or not app.modals.is_empty(): break
			if tick%6 == 0: bot_step(tick)
			await frames(1)
			if Game.run == null or not is_instance_valid(app.room): break
			var moved: float = app.room.player.position.distance_to(last_position)
			travelled += moved
			if desired_motion.length()>.1 and moved<.2: idle_motion_seconds += 1.0/60.0
			last_position = app.room.player.position
			total_damage += maxf(0.0,previous_hp-Game.run.hp)
			previous_hp = Game.run.hp
			snapshot = crowd_snapshot()
			if app.room.elapsed-start_elapsed >= next_sample:
				current.samples.append(snapshot.duplicate(true))
				next_sample += 1.0
			if app.room.elapsed-start_elapsed >= OBSERVATION_SECONDS: break
		stop_recording()
		observing = false
		while pending_captures > 0: await get_tree().process_frame
		current["final"] = snapshot
		current["wall_seconds"] = (Time.get_ticks_msec()-observation_wall_start)/1000.0
		current["died"] = Game.run == null and str(Game.last_result.get("outcome","")) == "death"
		current["result"] = Game.last_result.duplicate(true) if Game.run == null else {}
		current["damage_received"] = snappedf(total_damage,.01)
		current["enemy_health_consumed"] = snappedf(consumed_health,.01)
		current["damage_callbacks"] = damage_events
		current["actual_enemy_deaths"] = actual_deaths
		current["defeat_bodies_accepted"] = body_accepts
		current["defeat_bodies_peak"] = bodies_peak
		current["sfx_voices_peak"] = voices_peak
		current["music_streams_peak"] = music_streams_peak
		current["music_gain_range"] = [music_gain_min if is_finite(music_gain_min) else 0.0,music_gain_max]
		current["impact_duck_min"] = impact_duck_min
		current["cue_counts"] = cue_counts.duplicate(true)
		current["cue_timeline"] = cue_timeline.duplicate(true)
		current["melee_swing_observations"] = swing_observations.duplicate(true)
		current["pointer_input"] = {"method":"official standalone SubViewport.push_input; production CanvasItem read; not native OS cursor certification", "preflight":pointer_preflight.duplicate(true),
			"requests":pointer_requests,"clipped_navigation_requests":pointer_clipped_requests,"max_immediate_world_error":pointer_max_world_error}
		current["sfx_per_voice_gain"] = app.room.combat_audio.VOICE_GAIN*float(app.room.combat_audio.get("_gain")) if is_instance_valid(app.room) else 0.0
		current["distance_travelled"] = snappedf(travelled,.1)
		current["blocked_motion_seconds"] = snappedf(idle_motion_seconds,.01)
		current["fire_actions_accepted"] = fire_successes
		current["casts"] = cast_counts.duplicate(true)
		current["cast_rejections"] = cast_failures.duplicate(true)
		current["paused_by_modal"] = not app.modals.is_empty()
		current["screenshots"] = screenshot_records.duplicate(true)
		current["recording"] = recording_report.duplicate(true)
		current["kill_observation"] = "Real deaths observed" if actual_deaths>0 else "No deaths observed; this bot run alone cannot establish a design failure."
		check(voices_peak<=8,"real combat preserves eight SFX voices "+hero)
		check(bodies_peak<=20,"real defeat body layer stays bounded "+hero)
		check(music_streams_peak<=2,"real music mix uses two decks at most "+hero)
		if Game.run != null: check(Game.run.stats == initial_stats,"probe never rewrites starter stats "+hero)
		reports.append(current.duplicate(true))
		var console_report: Dictionary = current.duplicate(true)
		console_report.erase("cue_timeline")
		console_report.erase("melee_swing_observations")
		console_report.erase("samples")
		print("CROWD_FEEDBACK_OBSERVATION ",JSON.stringify(console_report))
		movement(Vector2.ZERO)
		if is_instance_valid(app.room): await app.room.combat_audio.wait_for_cleanup()
		if Game.run != null: Game.finish_run("abandoned")
		await frames(2)
		app.set_process(false)
		await app.music.wait_for_cleanup()
		app.free()
		await frames(2)
	var output := FileAccess.open(AssetCatalog.resolve("res://artifacts/crowd_feedback_"+("graphical" if graphical else "headless")+".json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"method":"Real main/room in an independent SubViewport, official push_input mouse events read by production player physics, normal Lv1 default starter gear, real enemy AI and geometry; public combat actions and movement input only. No actor/health/damage/position/resource modifications. Certifies local engine input, not native OS cursor access. Observational bot, not human quality or balance acceptance.",
		"graphical":graphical,"seconds_per_hero":OBSERVATION_SECONDS,"master_safety_muted":AudioServer.is_bus_mute(0),"reports":reports},"\t"))
	output.close()
	print("CROWD_FEEDBACK_RESULT checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)
