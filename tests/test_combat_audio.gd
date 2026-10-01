extends Node
## Verify generated PCM and production scheduling silently; no listening claim.

const Audio = preload("res://scripts/combat/combat_audio.gd")
var checks: int = 0
var failures: int = 0
var audio: Node

func _ready() -> void:
	call_deferred("run_checks")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func run_checks() -> void:
	if not Game.profile_path.contains("test_combat_audio"):
		push_error("Refusing non-test profile; use test_combat_audio in profile path")
		get_tree().quit(2)
		return
	_test_pcm()
	_test_timbres()
	audio = Audio.new()
	audio.audible = false
	add_child(audio)
	_test_schedule()
	_test_settings()
	await _test_muted_device_path()
	_test_lifecycle()
	if "--export-audio" in OS.get_cmdline_user_args():
		_export_samples()
	check(await audio.wait_for_cleanup(), "all tracked mixer playbacks are released before test shutdown")
	audio.free()
	print("COMBAT AUDIO: %d checks, %d failures (silent PCM/scheduling verification)" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _all_streams() -> Dictionary:
	var streams: Dictionary = {}
	for hero: String in Audio.HEROES:
		for cue: String in Audio.CUES:
			streams[hero + "_" + cue] = Audio.stream_for(hero, cue)
	streams["hurt"] = Audio.stream_for("", "hurt")
	streams["pickup"] = Audio.stream_for("", "pickup")
	return streams

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var bytes: PackedByteArray = stream.data
	var peak: float = 0.0
	var sum: float = 0.0
	var energy: float = 0.0
	var max_step: float = 0.0
	var previous: float = 0.0
	var crossings: int = 0
	var count: int = bytes.size() / 2
	for index: int in count:
		var value: float = float(bytes.decode_s16(index * 2)) / 32768.0
		peak = maxf(peak, absf(value))
		sum += value
		energy += value * value
		max_step = maxf(max_step, absf(value - previous))
		if index > 0 and value * previous < 0.0:
			crossings += 1
		previous = value
	return {"peak":peak,"mean":sum/count,"rms":sqrt(energy/count),"step":max_step,"crossings":float(crossings)/stream.get_length()}

func _test_pcm() -> void:
	var streams: Dictionary = _all_streams()
	check(streams.size() == 23, "all three heroes have seven cues plus hurt and pickup")
	for key: String in streams:
		var stream: AudioStreamWAV = streams[key]
		var metric: Dictionary = _measure(stream)
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == 24000, key + " has predictable 24kHz mono PCM")
		check(stream.get_length() >= 0.15 and stream.get_length() <= 0.79, key + " has short bounded duration")
		# Fixed-transfer Foley preserves release/contact dynamics; normalizing every
		# quiet wind or loud slam to the same .74 peak would destroy that contrast.
		check(metric.peak > 0.09 and metric.peak <= 0.741, key + " has audible signal, preserves dynamics and never clips")
		check(absf(metric.mean) < 0.025 and metric.rms > 0.018, key + " has low DC and meaningful signal")
		check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0, key + " begins and ends at zero")
		check(metric.step < 0.75, key + " keeps broadband contact transients below a full-scale sample jump")
		check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, key + " cannot accidentally loop")
	check(Audio.SAMPLE_PEAK * Audio.VOICE_GAIN * Audio.MAX_VOICES < 0.95, "worst-case correlated eight-voice mix retains full-scale headroom")
	check(Audio.stream_for("CH01", "attack") == Audio.stream_for("CH01", "attack"), "repeated events reuse the identical WAV resource")
	check(Audio.stream_for("missing", "attack") == null and Audio.stream_for("CH01", "missing") == null, "invalid hero/cue cannot manufacture unbounded cache keys")

func _test_timbres() -> void:
	var hammer: AudioStreamWAV = Audio.stream_for("CH01", "attack")
	var rail: AudioStreamWAV = Audio.stream_for("CH02", "attack")
	var resonance: AudioStreamWAV = Audio.stream_for("CH03", "attack")
	check(hammer.data != rail.data and rail.data != resonance.data and hammer.data != resonance.data, "three attacks have different actual PCM")
	# Noise-heavy physical releases are not meaningfully ranked by zero-crossing pitch.
	check(hammer.data != Audio.stream_for("CH01", "impact").data and resonance.data != Audio.stream_for("CH03", "impact").data, "weapon release and confirmed target contact use different authored layers")
	check(rail.get_length() < hammer.get_length(), "rail attack has the shorter dry envelope")
	for hero: String in Audio.HEROES:
		check(Audio.stream_for(hero, "impact").data != Audio.stream_for(hero, "heavy").data, hero + " heavy confirmation differs from ordinary hit")
		var signatures: Dictionary = {}
		for cue: String in ["q", "secondary", "f", "ultimate"]:
			signatures[hash(Audio.stream_for(hero, cue).data)] = true
		check(signatures.size() == 4, hero + " skills have distinct original waveforms")

func _test_schedule() -> void:
	check(audio.get_child_count() == 8, "pool allocates exactly eight AudioStreamPlayers")
	check(audio.attack("CH01"), "accepted attack schedules a cached stream")
	check(audio.impact("CH01"), "confirmed impact can coexist with attack onset")
	check(audio.impact("CH02", true), "heavy contact is not swallowed by a preceding light contact")
	for index: int in 24:
		check(not audio.impact("CH02", index % 2 == 0), "same-frame crowd is suppressed after the heavy contact")
	check(audio.active_voice_count() == 3, "mixed crowd keeps at most one light and one heavy contact voice")
	audio.advance(0.054)
	check(not audio.impact("CH01"), "impact ICD suppresses before 55ms")
	audio.advance(0.002)
	check(audio.impact("CH03", true), "impact reopens after 55ms")
	for voice: AudioStreamPlayer in audio.get_children():
		check(not voice.playing, "audible=false never sends any sound to the device")
	audio.stop_all()
	for index: int in 8:
		check(audio.cast("CH03", "ultimate"), "simultaneous real releases fill free pool voices without a second cadence gate")
	check(audio.active_voice_count() == 8, "eight overlapping long voices fill pool")
	check(not audio.attack("CH02") and audio.active_voice_count() == 8, "ninth voice is rejected without stealing or exceeding cap")
	audio.advance(0.8)
	check(audio.active_voice_count() == 0 and audio.attack("CH02"), "completed voices recycle cleanly")

func _test_settings() -> void:
	var original: Dictionary = Game.profile.settings.duplicate(true)
	audio.stop_all()
	Game.profile.settings["reduced_fx"] = true
	check(audio.attack("CH01"), "reduced visual effects does not mute audio")
	Game.profile.settings["sfx_volume"] = 0.5
	Game.profile.settings["master_volume"] = 0.4
	audio.advance(0.1)
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db), Audio.VOICE_GAIN * 0.2), "current master and SFX settings multiply conservatively")
	Game.profile.settings["sfx_muted"] = true
	audio.advance(0.01)
	check(audio.active_voice_count() == 0 and not audio.hurt(), "mute stops existing voices and rejects later sounds")
	Game.profile.settings["sfx_muted"] = false
	Game.profile.settings["sfx_volume"] = 0.0
	check(not audio.pickup(), "zero volume has no playback")
	Game.profile.settings["sfx_volume"] = INF
	check(not audio.pickup(), "invalid volume cannot amplify into nonfinite samples")
	Game.profile.settings = original
	audio.advance(0.01)
	check(audio.pickup(), "restored settings allow normal sounds")

func _test_lifecycle() -> void:
	get_tree().paused = true
	audio.advance(0.2)
	check(audio.active_voice_count() == 0, "pause clears tails immediately without queued catch-up")
	check(not audio.attack("CH01") and not audio.cast("CH03", "q"), "paused scene rejects new combat sounds")
	get_tree().paused = false
	check(audio.impact("CH01") and audio.hurt(), "unpause accepts fresh sounds without stale ICD")
	audio.stop_all()
	check(audio.active_voice_count() == 0, "stop_all clears virtual and real players")
	for voice: AudioStreamPlayer in audio.get_children():
		check(voice.stream == null and not voice.playing, "stop_all releases every player's stream")
	check(audio.impact("CH01"), "explicit stop resets hit cooldown")
	remove_child(audio)
	check(audio.active_voice_count() == 0 and not audio.pickup(), "scene removal stops and rejects orphan playback")
	add_child(audio)
	check(audio.attack("CH02"), "re-entered node can accept a fresh attack")

func _test_muted_device_path() -> void:
	# Exercise AudioStreamPlayer.play itself behind an explicitly muted bus.
	# This remains silent even if this suite is launched with a real driver.
	audio.stop_all()
	var previous_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	audio.audible = true
	check(audio.attack("CH02"), "real playback request accepts its cached PCM")
	var voice: AudioStreamPlayer = audio.get_child(0)
	var is_production_take: bool = false
	for variation: int in Audio.VARIATIONS:
		is_production_take = is_production_take or voice.stream == Audio.stream_for("CH02", "attack", variation)
	check(voice.playing and is_production_take and is_equal_approx(voice.pitch_scale, 1.0), "muted real player plays a cached Foley take at its authored speed")
	audio.advance(1.0)
	check(voice.playing and audio.active_voice_count() == 1, "large game delta cannot truncate a real mixer-clock sound")
	await get_tree().create_timer(0.04).timeout
	audio.audible = false
	check(not voice.playing and audio.active_voice_count() == 0, "disabling audibility stops real playback immediately")
	await get_tree().create_timer(0.04).timeout
	audio.audible = true
	check(audio.attack("CH02"), "real voice can play again after explicit stop")
	await get_tree().create_timer(0.24).timeout
	check(audio.active_voice_count() == 0 and voice.stream == null, "real finished signal releases the voice and stream naturally")
	audio.audible = false
	AudioServer.set_bus_mute(0, previous_mute)

	# Exercise the formerly misleading leak-at-exit path: stop on the same frame
	# as play, then observe actual weak-reference release instead of sleeping.
	AudioServer.set_bus_mute(0, true)
	audio.audible = true
	for index: int in 16:
		check(audio.attack("CH02"), "same-frame teardown regression accepts a real attack")
		audio.stop_all()
	check(await audio.wait_for_cleanup(), "same-frame play/stop objects are reclaimed by the mixer")
	check(audio.pending_playback_count() == 0, "repeated immediate stops retain no playback objects")
	audio.audible = false
	AudioServer.set_bus_mute(0, previous_mute)

func _export_samples() -> void:
	var directory: String = "res://artifacts/audio"
	DirAccess.make_dir_recursive_absolute(directory)
	for key: String in _all_streams():
		check(_all_streams()[key].save_to_wav(directory + "/" + key + ".wav") == OK, key + " exports original preview WAV")
