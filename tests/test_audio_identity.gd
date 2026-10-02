extends SceneTree
## Silent PCM, arrangement, voice-priority, context/mix and pause verification.

const Audio = preload("res://scripts/combat/combat_audio.gd")
const Music = preload("res://scripts/audio/music_director.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	var game: Node = root.get_node("Game")
	if not str(game.profile_path).contains("test_audio_identity"):
		push_error("Refusing non-test profile; run tools/test.ps1 -Suite audio_identity")
		quit(2)
		return
	_test_score()
	_test_priority_and_timbres()
	await _test_director(game)
	_export_audition()
	print("AUDIO IDENTITY: %d checks, %d failures (PCM/arrangement/scheduling; no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_score() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/music/score.json"))
	check(manifest.get("license") == "CC0-1.0", "original synthesized score has explicit source/license")
	var fingerprints: Dictionary = {}
	var event_counts: Dictionary = {}
	for track: Dictionary in manifest.tracks:
		var context: String = track.context
		var stream: AudioStreamWAV = Music.stream_for(context)
		check(stream != null, context + " resolves to real PCM")
		if stream == null:
			continue
		var source: AudioStreamWAV = AudioStreamWAV.load_from_file("res://assets/music/" + context + ".wav")
		print("MUSIC PCM %s: format=%d rate=%d frames=%d bytes=%d source_match=%s" % [context, stream.format, stream.mix_rate, roundi(stream.get_length() * stream.mix_rate), stream.data.size(), str(stream.data == source.data)])
		check(stream.stereo and stream.mix_rate == 24000 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.data == source.data, context + " imported 24kHz stereo PCM exactly matches the measured source")
		check(stream.get_length() > 28.0 and stream.get_length() < 48.0, context + " contains a full sixteen-bar arrangement")
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == int(track.frames) and stream.loop_end == roundi(stream.get_length() * stream.mix_rate), context + " loops the complete authored frame count")
		var samples: PackedByteArray = stream.data
		var peak: int = 0
		var energy: float = 0.0
		var dc: float = 0.0
		var max_step: int = 0
		for index: int in samples.size() / 2:
			var value: int = samples.decode_s16(index * 2)
			peak = maxi(peak, absi(value))
			energy += pow(float(value) / 32768.0, 2.0)
			dc += float(value) / 32768.0
			if index >= 2:
				max_step = maxi(max_step, absi(value - samples.decode_s16((index - 2) * 2)))
		var count: int = samples.size() / 2
		check(peak < 19010 and peak > 18500, context + " has measured headroom below 0.581")
		check(sqrt(energy / count) > 0.025 and absf(dc / count) < 0.001, context + " has meaningful energy and negligible DC")
		check(float(max_step) / 32768.0 < 0.3, context + " has bounded sample slopes")
		check(samples.decode_s16(0) == samples.decode_s16(samples.size() - 4) and samples.decode_s16(2) == samples.decode_s16(samples.size() - 2), context + " stereo loop boundary is exactly continuous")
		check(track.bars == 16 and track.events.size() > 100, context + " stores reproducible musical note events")
		var pitches: Dictionary = {}
		var instruments: Dictionary = {}
		for event: Dictionary in track.events:
			pitches[int(event.midi)] = true
			instruments[str(event.instrument)] = true
		check(pitches.size() >= 15 and instruments.size() >= 3, context + " has melody, harmony and multiple instruments")
		fingerprints[hash(samples)] = true
		event_counts[context] = track.note_events
	check(fingerprints.size() == 4, "four contexts use different actual music")
	check(int(event_counts.get("combat", 0)) > int(event_counts.get("explore", 0)) * 2, "combat adds a substantially denser rhythmic arrangement")
	check(Music.stream_for("invalid") == null, "unknown context cannot load arbitrary resources")
	check(Audio.SAMPLE_PEAK * Audio.VOICE_GAIN * Audio.MAX_VOICES + 0.58 * Music.MUSIC_GAIN < 0.95, "music plus eight correlated SFX voices retains master headroom")

func _test_priority_and_timbres() -> void:
	var audio: Node = Audio.new()
	audio.audible = false
	root.add_child(audio)
	# Exercise the actual scheduler with long impacts so its reserve is observable.
	for index: int in 6:
		check(audio._request("CH01", "ultimate", "passive_impact", 0.0), "six background confirmations may take unreserved voices")
	check(not audio._request("CH01", "ultimate", "passive_impact", 0.0), "crowd cannot consume player's reserved voices")
	check(audio.cast("CH03", "q") and audio.hurt(), "player skill and hurt use both reserved voices")
	check(audio.active_voice_count() == Audio.MAX_VOICES, "priority never exceeds the hard eight-voice cap")
	audio.stop_all()
	check(audio.attack("CH02"), "first gunshot is accepted")
	audio.advance(0.074)
	check(not audio.attack("CH02"), "rapid fire obeys 75ms anti-buzz interval")
	audio.advance(0.002)
	check(audio.attack("CH02"), "gunshot becomes available after the interval")
	for hero: String in Audio.HEROES:
		var signatures: Dictionary = {}
		for cue: String in Audio.CUES:
			signatures[hash(Audio.stream_for(hero, cue).data)] = true
		check(signatures.size() == 7, hero + " has seven distinct cue waveforms")
	check(_energy(Audio.stream_for("CH01", "ultimate"), 0.0, 0.035) > 0.002 and Audio.stream_for("CH01", "ultimate").get_length() < 0.40, "hammer ultimate is one immediate piston discharge, never a baked third strike")
	check(_energy(Audio.stream_for("CH02", "f"), 0.0, 0.03) > 0.002 and _energy(Audio.stream_for("CH02", "f"), 0.14, 0.18) < 0.00001, "mechanical F has an immediate deployment clasp and no late third gunshot")
	check(_energy(Audio.stream_for("CH03", "q"), 0.0, 0.03) > 0.002, "crystal Q release begins immediately instead of baking its windup into the projectile sound")
	audio.free()

func _energy(stream: AudioStreamWAV, start: float, end: float) -> float:
	var first: int = roundi(start * stream.mix_rate)
	var last: int = mini(roundi(end * stream.mix_rate), stream.data.size() / 2)
	var energy: float = 0.0
	for index: int in range(first, last):
		energy += pow(float(stream.data.decode_s16(index * 2)) / 32768.0, 2.0)
	return energy / maxi(1, last - first)

func _test_director(game: Node) -> void:
	var director: Node = Music.new()
	director.audible = false
	root.add_child(director)
	director.configure(game)
	director.set_context("camp")
	for index: int in 20:
		director.configure(game)
		director.set_context("camp")
	check(director.get_child_count() == 2 and director.transition_count == 1, "repeated configure/UI context is idempotent")
	director.advance(1.3)
	check(director.active_stream_count() == 1 and director.current_context == "camp", "initial fade settles to one loop")
	director.set_context("explore")
	director.advance(0.5)
	check(director.active_stream_count() == 2 and director.is_transitioning(), "context changes crossfade two real streams")
	director.set_context("combat")
	director.set_context("boss")
	check(director.active_stream_count() == 2, "rapid context requests cannot stack a third stream")
	director.advance(1.0)
	check(director.current_context == "boss" and director.active_stream_count() == 2, "latest queued context replaces obsolete requests")
	director.advance(1.3)
	check(director.active_stream_count() == 1 and not director.is_transitioning(), "outgoing music releases after the crossfade")
	director.set_mix(0.5, 0.4, 0.8)
	check(is_equal_approx(director.effective_music_gain(), Music.MUSIC_GAIN * 0.2), "master/music volume multiply once")
	paused = true
	director.advance(1.0)
	check(is_equal_approx(director.effective_music_gain(), Music.MUSIC_GAIN * 0.2 * Music.PAUSED_GAIN), "pause smoothly ducks the same loop")
	for index: int in 20:
		director.set_context("boss")
	check(director.active_stream_count() == 1, "multiple paused overlays never add music voices")
	paused = false
	director.advance(1.0)
	check(is_equal_approx(director.effective_music_gain(), Music.MUSIC_GAIN * 0.2), "resume restores music without restarting it")
	director.set_mix(INF, 1.0, 1.0)
	check(director.effective_music_gain() == 0.0, "nonfinite mixer input cannot amplify music")
	var saved_settings: Dictionary = game.profile.settings.duplicate(true)
	game.profile.settings.music_muted = true
	game.changed.emit()
	check(director.effective_music_gain() == 0.0, "music-only mute is respected")
	game.profile.settings = saved_settings
	game.changed.emit()
	# Exercise actual player/loop setup through a muted device, never audible.
	var previous_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	director.audible = true
	check(director.get_child(0).playing or director.get_child(1).playing, "real player starts the selected looping stream")
	check(await director.wait_for_cleanup(), "music teardown releases mixer playback")
	AudioServer.set_bus_mute(0, previous_mute)
	director.free()

func _export_audition() -> void:
	# Preview is built from the exact production streams, not a second synth.
	var directory: String = "res://assets/audio/previews"
	DirAccess.make_dir_recursive_absolute(directory)
	var bytes := PackedByteArray()
	var gap := PackedByteArray()
	gap.resize(roundi(Audio.SAMPLE_RATE * 0.14) * 2)
	gap.fill(0)
	for hero: String in Audio.HEROES:
		for cue: String in Audio.CUES:
			var stream: AudioStreamWAV = Audio.stream_for(hero, cue)
			check(stream.save_to_wav(directory + "/" + hero + "_" + cue + ".wav") == OK, hero + " " + cue + " exports its audition sample")
			bytes.append_array(stream.data)
			bytes.append_array(gap)
	var showcase := AudioStreamWAV.new()
	showcase.format = AudioStreamWAV.FORMAT_16_BITS
	showcase.mix_rate = Audio.SAMPLE_RATE
	showcase.data = bytes
	check(showcase.save_to_wav(directory + "/sfx_showcase.wav") == OK, "combined hero/SFX audition exports")
