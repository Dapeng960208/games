extends Node
## Accepted real-room contact -> main cue connection -> persistent music deck.
## Bus is muted for automation; player gain/resources still use production APIs.

const Music = preload("res://scripts/infrastructure/audio/music_director.gd")
var checks: int = 0
var failures: int = 0
var app: Node
var music: Node
var room: Node
var audio: Node
var baseline: float
var serial: int = 0
var cues: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MUSIC DUCK: " + description)

func frames(count: int = 2) -> void:
	for _frame in count:
		await get_tree().process_frame

func reset_contact() -> void:
	audio.stop_all()
	music.advance(1.0)
	cues.clear()

func tick(delta: float) -> void:
	audio.advance(delta)
	music.advance(delta)

func deck() -> AudioStreamPlayer:
	return music._players[music._active]

func ratio() -> float:
	return db_to_linear(deck().volume_db) / baseline

func contact(target: Node, source: StringName = &"primary") -> void:
	serial += 1
	var id: String = "music-contact:" + str(serial)
	room.resolve_direct_hit(target, 11.0, source, "", 0.0, Vector2.RIGHT,
		{"attack_id":id,"root_event_id":id,"equipment_eligible":false})

func run_checks() -> void:
	if not Game.profile_path.contains("test_music_duck"):
		get_tree().quit(2)
		return
	var bus_muted: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	check(Game.new_profile(), "isolated real profile created")
	app = load(AssetCatalog.resolve("res://scenes/app/main.tscn")).instantiate()
	add_child(app)
	app.set_process(false)
	music = app.music
	music.set_process(false)
	check(Game.start_run(), "real Game signal mounts main's production room")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(430, 350)
	Game.run.stats["crit_chance"] = 0.0
	Game.run.stats["true_damage_bonus"] = 0.0
	audio = room.combat_audio
	audio.audible = false
	audio.set_process(false)
	audio.cue_played.connect(func(cue: String): cues.append(cue))
	check(audio.cue_played.is_connected(app._on_combat_cue_played), "actual main mounts contact cue signal exactly once")
	music.stop_all()
	music.set_context("combat")
	music.advance(1.25)
	baseline = Music.MUSIC_GAIN * float(Game.profile.settings.master_volume) * float(Game.profile.settings.music_volume)
	check(deck().playing and is_equal_approx(ratio(), 1.0), "real persistent music deck plays at saved music gain")
	var before_settings: Dictionary = Game.profile.settings.duplicate(true)
	var stream: AudioStream = deck().stream
	var playback: AudioStreamPlayback = deck().get_stream_playback()
	var transitions: int = music.transition_count
	var target: Node = room.spawn_enemy(room.player.position + Vector2(60, 0), "M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	var hp: float = target.health.current
	contact(target)
	check(target.health.current < hp and cues == ["impact"], "actual damage emits accepted ordinary contact through room audio")
	check(is_equal_approx(music.impact_duck_gain(), 1.0), "contact has an eight-millisecond attack without an instantaneous volume jump")
	tick(0.004)
	check(ratio() < 1.0 and ratio() > Music.LIGHT_IMPACT_GAIN, "actual music player's gain begins the short attack")
	tick(0.004)
	check(is_equal_approx(ratio(), Music.LIGHT_IMPACT_GAIN), "accepted ordinary hit ducks the real deck to minus three dB")
	tick(0.056)
	check(ratio() >= Music.LIGHT_IMPACT_GAIN and ratio() < 0.71, "ordinary contact retains its short hold before smooth release")
	tick(0.16)
	check(is_equal_approx(ratio(), 1.0), "ordinary contact automatically returns to the saved gain")
	reset_contact()
	contact(target, &"secondary")
	tick(0.008)
	check(cues == ["heavy"] and is_equal_approx(ratio(), Music.HEAVY_IMPACT_GAIN), "real secondary contact applies the heavy envelope through main")
	for _index in 40:
		contact(target, &"secondary")
		check(ratio() >= Music.HEAVY_IMPACT_GAIN - 0.00001, "same-frame crowd cannot multiply duck envelopes")
	check(cues == ["heavy"], "rate-limited crowd rejection emits no extra accepted cue")
	tick(0.264)
	check(is_equal_approx(ratio(), 1.0), "heavy crowd envelope finishes without accumulated ducking")
	_test_release_and_retrigger()
	_test_non_contact_and_rejection()
	_test_settings()
	_test_invalid_delta()
	check(Game.profile.settings == before_settings, "all impact automation leaves user volume/settings untouched")
	check(music.transition_count == transitions and deck().stream == stream and deck().get_stream_playback() == playback, "hits never restart music or replace its stream/playback")
	check(music.get_child_count() == 2 and music.active_stream_count() == 1, "combat feedback cannot allocate music voices beyond the persistent two-deck pool")
	# Release the test reference before checking mixer cleanup.
	playback = null
	await _test_pause_room_and_camp()
	await _test_expedition_room_change()
	check(await music.wait_for_cleanup(), "music mixer releases both decks on explicit cleanup")
	check(music.active_stream_count() == 0 and music.impact_duck_gain() == 1.0, "stop clears both music streams and temporary envelopes")
	app.free()
	await frames(3)
	AudioServer.set_bus_mute(0, bus_muted)
	print("MUSIC DUCK: %d checks, %d failures (real main/room/accepted audio connection; deterministic gain checks)" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_release_and_retrigger() -> void:
	reset_contact()
	check(audio.impact("CH01", true), "heavy source starts independent envelope")
	tick(0.008)
	for _index in 8:
		tick(0.06)
		check(audio.impact("CH02"), "sustained gun contact is accepted after its interval")
		music.advance(0.008)
	check(is_equal_approx(ratio(), Music.LIGHT_IMPACT_GAIN), "continuing ordinary hits cannot keep the expired heavy depth alive")
	tick(0.23)
	check(is_equal_approx(ratio(), 1.0), "sustained ordinary fire recovers when contacts stop")
	reset_contact()
	check(audio.impact("CH01", true), "heavy retrigger setup accepted")
	tick(0.12)
	var releasing: float = music.impact_duck_gain()
	check(releasing > Music.HEAVY_IMPACT_GAIN and releasing < 1.0, "heavy envelope is releasing before its next hit")
	check(audio.impact("CH01", true), "next heavy contact accepted during release")
	check(is_equal_approx(music.impact_duck_gain(), releasing), "heavy retrigger starts from its current envelope with no upward jump")
	tick(0.008)
	check(is_equal_approx(ratio(), Music.HEAVY_IMPACT_GAIN), "retrigger smoothly restores the bounded heavy depth")

func _test_non_contact_and_rejection() -> void:
	reset_contact()
	for action: String in ["attack", "q", "secondary", "f", "ultimate", "defeat", "pickup", "hurt"]:
		audio.stop_all()
		var accepted: bool
		match action:
			"attack": accepted = audio.attack("CH01")
			"defeat": accepted = audio.defeat("metal")
			"pickup": accepted = audio.pickup()
			"hurt": accepted = audio.hurt()
			_: accepted = audio.cast("CH03", action)
		music.advance(0.01)
		check(accepted and is_equal_approx(ratio(), 1.0), action + " cue cannot cause music ducking")
	reset_contact()
	check(audio.impact("CH01"), "rate-limit probe starts an ordinary contact")
	tick(0.03)
	var age: float = music._light_impact_age
	var accepted_count: int = audio.accepted_events
	check(not audio.impact("CH02"), "rate-limited impact is actually rejected by the scheduler")
	check(music._light_impact_age == age and audio.accepted_events == accepted_count, "rejected rate-limited impact cannot restart the music envelope")
	reset_contact()
	for _index in 8:
		check(audio.cast("CH03", "ultimate"), "long skill voice fills the actual bounded scheduler")
		tick(0.061)
	check(audio.active_voice_count() == 8, "full-voice rejection test fills all eight real scheduler slots")
	check(not audio.impact("CH01", true), "even heavy impact is rejected when every slot is occupied")
	music.advance(0.02)
	check(is_equal_approx(ratio(), 1.0), "pool-full rejected contact cannot duck the actual music player")
	reset_contact()
	check(not audio.impact("missing", true), "invalid hero request is rejected")
	music.advance(0.02)
	check(is_equal_approx(ratio(), 1.0), "invalid contact leaves music unchanged")

func _test_settings() -> void:
	var original: Dictionary = Game.profile.settings.duplicate(true)
	for setting: String in ["sfx_muted", "muted", "sfx_volume", "master_volume"]:
		reset_contact()
		Game.profile.settings[setting] = true if setting.ends_with("muted") else 0.0
		Game.changed.emit()
		check(not audio.impact("CH03", true), setting + " prevents accepted contact")
		music.advance(0.01)
		check(is_equal_approx(music.impact_duck_gain(), 1.0), setting + " prevents contact-driven ducking")
		Game.profile.settings = original.duplicate(true)
		Game.changed.emit()
	reset_contact()
	Game.profile.settings["music_muted"] = true
	Game.changed.emit()
	check(audio.impact("CH03", true), "music mute does not disable independent combat sound")
	music.advance(0.01)
	check(music.impact_duck_gain() == 1.0 and music.effective_music_gain() == 0.0, "muted music has no latent contact envelope")
	Game.profile.settings = original
	Game.changed.emit()

func _test_invalid_delta() -> void:
	reset_contact()
	audio.impact("CH01", true)
	tick(0.02)
	for delta: float in [-1.0, NAN, INF, -INF]:
		var age: float = music._heavy_impact_age
		var gain: float = music.impact_duck_gain()
		music.advance(delta)
		check(is_finite(music.effective_music_gain()) and is_finite(deck().volume_db), "invalid delta does not contaminate player gain")
		check(music._heavy_impact_age == age and music.impact_duck_gain() == gain, "invalid delta cannot rewind or skip the envelope")
	music.advance(100000.0)
	check(is_equal_approx(ratio(), 1.0), "oversized finite delta safely completes the bounded envelope")

func _test_pause_room_and_camp() -> void:
	reset_contact()
	audio.impact("CH01", true)
	tick(0.008)
	get_tree().paused = true
	music.advance(0.01)
	check(music.impact_duck_gain() == 1.0, "pause clears temporary hit duck before applying normal pause mix")
	check(not audio.impact("CH01", true), "paused room cannot enqueue a new ducking contact")
	get_tree().paused = false
	music.advance(1.0)
	check(is_equal_approx(ratio(), 1.0), "unpause restores saved gain without stale impact")
	var music_id: int = music.get_instance_id()
	var previous_room: WeakRef = weakref(room)
	check(not Game.finish_run("abandoned").is_empty(), "production settlement leaves old combat room")
	await frames(2)
	check(previous_room.get_ref() == null, "settlement destroys old room and its cue emitter")
	app.show_camp()
	app.music_tick = 0.0
	app._process(0.0)
	music.advance(1.25)

	check(music.desired_context == "camp" and music.impact_duck_gain() == 1.0, "production return to camp resets combat attenuation")
	app._on_combat_cue_played("heavy")
	music.advance(0.008)
	check(music.impact_duck_gain() == 1.0, "late combat cue outside run route cannot attenuate camp music")
	check(Game.start_run(), "second actual run mounts a new room")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	room.spawn_enabled = false
	audio = room.combat_audio
	audio.audible = false
	audio.set_process(false)
	app.music_tick = 0.0
	app._process(0.0)
	music.advance(1.25)
	check(music.get_instance_id() == music_id and music.get_child_count() == 2, "new room reuses the single music director and its existing decks")
	check(audio.cue_played.is_connected(app._on_combat_cue_played), "new room reconnects its own accepted audio source")
	check(audio.impact("CH02", true), "replacement room accepts its contact")
	tick(0.008)
	check(is_equal_approx(music.impact_duck_gain(), Music.HEAVY_IMPACT_GAIN), "replacement room signal drives the existing music director")
	check(not Game.finish_run("abandoned").is_empty(), "second run shuts down cleanly")
	await frames(2)
	app.show_camp()
	app.music_tick = 0.0
	app._process(0.0)
	music.advance(1.25)

func _test_expedition_room_change() -> void:
	check(Game.start_run({"expedition":true,"biome_id":"B01","difficulty":0}), "real multi-room expedition starts")
	room = app.room
	room.process_mode = Node.PROCESS_MODE_DISABLED
	audio = room.combat_audio
	audio.audible = false
	audio.set_process(false)
	await frames(1)
	for offer: Dictionary in Game.expedition_snapshot().get("relic_offers", []):
		if str(offer.get("decision", "")).is_empty():
			app._choose_expedition_relic(str(offer.offer_id), "skip")
	app._clear_modals()
	app.music_tick = 0.0
	app._process(0.0)
	music.advance(1.25)
	var old_room_id: int = room.get_instance_id()
	var old_audio_id: int = audio.get_instance_id()
	var old_music_id: int = music.get_instance_id()
	var options: Array = app.expedition.next_options()
	check(not options.is_empty() and app.expedition.current_index() == 0, "entry offers a legal next room")
	if not options.is_empty():
		app._advance_expedition(str(options[0]))
	check(app.expedition.current_index() == 1, "main commits and installs the actual next expedition room")
	check(app.room.get_instance_id() == old_room_id and app.room.combat_audio.get_instance_id() == old_audio_id, "room layout change preserves the connected bounded audio owner")
	check(music.get_instance_id() == old_music_id and music.get_child_count() == 2, "expedition node change retains the original two music decks")
	check(audio.cue_played.get_connections().filter(func(connection: Dictionary): return connection.callable == app._on_combat_cue_played).size() == 1, "next node has exactly one main audio-to-music connection")
	app._clear_modals()
	app.music_tick = 0.0
	app._process(0.0)
	music.advance(1.25)
	audio.stop_all()
	check(audio.impact("CH01", true), "contact scheduler still accepts after real expedition transition")
	tick(0.008)
	check(is_equal_approx(music.impact_duck_gain(), Music.HEAVY_IMPACT_GAIN), "post-transition accepted contact still ducks the current music deck")
	tick(0.27)
	check(music.impact_duck_gain() == 1.0, "post-transition contact recovers without a stuck envelope")
	check(not Game.finish_run("abandoned").is_empty(), "expedition fixture settles through actual production transaction")
	await frames(2)
	app.show_camp()
	app.music_tick = 0.0
	app._process(0.0)
	music.advance(1.25)
