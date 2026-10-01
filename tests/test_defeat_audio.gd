extends SceneTree
## Material collapse PCM and actual priority scheduler; silent device checks.
const Audio = preload("res://scripts/combat/combat_audio.gd")
var checks: int = 0
var failures: int = 0
var game: Node
var audio: Node
var played: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_defeat_audio"):
		push_error("Refusing non-test profile")
		quit(2)
		return
	var saved_settings: Dictionary = game.profile.settings.duplicate(true)
	game.profile.settings.merge({"muted": false, "sfx_muted": false, "master_volume": 1.0, "sfx_volume": 1.0}, true)
	_test_pcm()
	_test_cache()
	audio = Audio.new()
	audio.audible = false
	root.add_child(audio)
	audio.set_process(false)
	audio.cue_played.connect(func(cue: String) -> void: played.append(cue))
	_test_crowd_and_priority()
	_test_variants()
	_test_settings()
	await _test_real_lifecycle()
	check(await audio.wait_for_cleanup(), "final teardown releases actual mixer objects")
	audio.free()
	game.profile.settings = saved_settings
	print("DEFEAT AUDIO: %d checks, %d failures (PCM/scheduling/muted device, no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var count: int = stream.data.size() / 2
	var peak: float = 0.0
	var sum: float = 0.0
	var energy: float = 0.0
	var bass_energy: float = 0.0
	var lowpass: float = 0.0
	var a: float = 1.0 - exp(-TAU * 200.0 / stream.mix_rate)
	for index: int in count:
		var sample_value: float = float(stream.data.decode_s16(index * 2)) / 32768.0
		peak = maxf(peak, absf(sample_value))
		sum += sample_value
		energy += sample_value * sample_value
		lowpass += a * (sample_value - lowpass)
		bass_energy += lowpass * lowpass
	return {"peak": peak, "mean": sum / count, "rms": sqrt(energy / count), "energy": energy / stream.mix_rate, "bass_energy": bass_energy / stream.mix_rate}

func _test_pcm() -> void:
	check(Audio.CUES == ["attack", "impact", "heavy", "q", "secondary", "f", "ultimate"], "hero cue contract remains seven independent cues")
	check(Audio.MAX_VOICES == 8 and Audio.RESERVED_PLAYER_VOICES == 2, "unchanged eight voices with two player reserves")
	check(Audio.SAMPLE_PEAK * Audio.VOICE_GAIN * Audio.MAX_VOICES < 0.95, "full correlated SFX mix retains existing headroom")
	var total_signatures: Dictionary = {}
	for material: String in Audio.MATERIALS:
		var signatures: Dictionary = {}
		for variant: int in Audio.VARIATIONS:
			var stream: AudioStreamWAV = Audio.stream_for("", "defeat", variant, material)
			var label: String = material + "/v" + str(variant)
			check(stream != null, label + " resolves production stream")
			if stream == null:
				continue
			var m: Dictionary = _measure(stream)
			check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == 24000, label + " uses authored mono 24kHz PCM")
			check(stream.get_length() >= 0.20 and stream.get_length() <= 0.35, label + " is a short collapse without extended ring")
			check(m.peak > 0.09 and m.peak < 0.50, label + " has lower peak than foreground impact budget")
			check(m.rms > 0.01 and absf(m.mean) < 0.003, label + " has meaningful output with negligible DC")
			check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0, label + " begins and ends at zero")
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, label + " never loops")
			for hero: String in Audio.HEROES:
				var heavy: Dictionary = _measure(Audio.stream_for(hero, "heavy", variant, material))
				check(m.energy < heavy.energy * 0.6, label + " collapse energy yields to " + hero + " heavy contact")
				check(m.bass_energy < heavy.bass_energy * 0.4, label + " collapse low end yields to " + hero + " heavy contact")
				check(stream.data != Audio.stream_for(hero, "impact", variant, material).data, label + " is independent of " + hero + " impact")
			check(stream.data != Audio.stream_for("", "pickup", variant).data, label + " is not reward chime PCM")
			signatures[hash(stream.data)] = true
			total_signatures[hash(stream.data)] = true
			print("DEFEAT PCM %s peak=%.4f rms=%.4f energy=%.6f bass=%.6f" % [label, m.peak, m.rms, m.energy, m.bass_energy])
		check(signatures.size() == 4, material + " has four independently excited waveforms")
	check(total_signatures.size() == 12, "all twelve material takes contain different PCM")

func _test_cache() -> void:
	Audio.prewarm()
	check(Audio._streams.size() == 252, "complete library exactly 132 hero release/hit, 48 preparation, 8 hurt/pickup, 12 collapse, 16 deployment, 12 resonance and 24 shield streams")
	for index: int in 40:
		check(Audio.stream_for("unknown" + str(index), "defeat", index * -993, "invalid" + str(index)) == Audio.stream_for("", "defeat", posmod(index * -993, 4), "stone"), "special cue normalizes all public key fields")
		check(Audio.stream_for("", "defeat", index, "metal") == Audio.stream_for("CH01", "defeat", posmod(index, 4), "metal"), "collapse has no hero-duplicated cache")
		check(Audio.stream_for("", "bad" + str(index)) == null, "invalid special cue rejected")
	check(Audio._streams.size() == 252, "arbitrary inputs cannot grow warmed cache")

func _test_crowd_and_priority() -> void:
	check(audio.impact("CH01"), "ordinary hit accepts first")
	check(audio.defeat("metal"), "kill material may coexist with killing hit")
	check(audio.impact("CH01", true), "collapse does not swallow heavy contact after light")
	check(played == ["impact", "defeat", "heavy"], "accepted cue signal reports actual granted audio slots")
	for index: int in 24:
		check(not audio.defeat(Audio.MATERIALS[index % 3]), "same-frame multikill is suppressed across materials")
	check(played.size() == 3, "rejected multikill emits no cue signal")
	audio.advance(0.056)
	check(audio.impact("CH03", true) and not audio.defeat("organic"), "55ms heavy cadence is independent of 100ms kill cadence")
	audio.advance(0.043)
	check(not audio.defeat(), "collapse remains gated at 99ms")
	audio.advance(0.002)
	check(audio.defeat("organic"), "collapse opens after 100ms")
	check(audio.active_voice_count() == 5, "crowd requests never become deferred playback")
	audio.stop_all()
	for index: int in 5:
		check(audio._request("CH03", "ultimate", "passive_impact", 0.0), "background hit occupies shared background budget")
	check(audio.defeat("stone"), "collapse may use sixth background voice")
	audio.advance(0.101)
	var endings: Array = audio._ends.duplicate()
	var retained: Array[AudioStream] = []
	for voice: AudioStreamPlayer in audio.get_children():
		retained.append(voice.stream)
	var signal_count: int = played.size()
	check(not audio.defeat("metal"), "collapse cannot consume player reserve")
	check(played.size() == signal_count and audio._ends == endings, "full-background rejection preserves tails and emits no cue")
	for index: int in retained.size():
		check(audio.get_child(index).stream == retained[index], "full pool never truncates an existing stream")
	check(audio.attack("CH02") and audio.impact("CH01", true), "player release and heavy confirmation use both reserve slots")
	check(audio.active_voice_count() == 8, "mixed foreground/background pool stays at eight")
	check(not audio.defeat() and not audio.cast("CH01", "q"), "full pool rejects without stealing tails")
	audio.advance(1.0)
	check(audio.active_voice_count() == 0, "silent complete waves recycle naturally")
	audio.stop_all()
	check(not audio.cast("CH01", "defeat"), "skill API cannot manufacture kill cue")

func _test_variants() -> void:
	for material: String in Audio.MATERIALS:
		var signatures: Dictionary = {}
		var first: AudioStreamWAV
		for index: int in 5:
			audio.stop_all()
			check(audio.defeat(material), "collapse API accepts " + material)
			var voice: AudioStreamPlayer = audio.get_child(0)
			var stream: AudioStreamWAV = voice.stream
			check(is_equal_approx(voice.pitch_scale, 1.0) and not voice.playing, "variants use waveform changes without pitch shift or test sound")
			var correct_family: bool = false
			for variant: int in 4:
				correct_family = correct_family or stream == Audio.stream_for("", "defeat", variant, material)
			check(correct_family, "runtime selects correct material family")
			signatures[hash(stream.data)] = true
			if index == 0:
				first = stream
			elif index == 4:
				check(stream == first, "four collapse takes wrap to original cached resource")
		check(signatures.size() == 4, material + " actually cycles all four takes")
	audio.stop_all()

func _test_settings() -> void:
	game.profile.settings["reduced_fx"] = true
	check(audio.defeat(), "reduced visuals preserve kill audio")
	game.profile.settings.merge({"master_volume": 0.4, "sfx_volume": 0.5}, true)
	audio.advance(0.01)
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db), Audio.VOICE_GAIN * 0.2), "collapse obeys existing gain product")
	game.profile.settings["sfx_muted"] = true
	var signal_count: int = played.size()
	check(not audio.defeat() and audio.active_voice_count() == 0, "muting stops collapse and rejects next event")
	check(played.size() == signal_count, "muted event emits no cue signal")
	game.profile.settings["sfx_muted"] = false
	game.profile.settings["master_volume"] = 0.0
	check(not audio.defeat(), "zero master volume rejects collapse")
	game.profile.settings["master_volume"] = INF
	check(not audio.defeat(), "nonfinite volume cannot amplify collapse")
	game.profile.settings.merge({"master_volume": 1.0, "sfx_volume": 1.0}, true)
	check(audio.defeat(), "settings restoration permits fresh collapse")
	paused = true
	audio.advance(0.01)
	check(audio.active_voice_count() == 0 and not audio.defeat(), "pause stops collapse and rejects queued tails")
	paused = false
	check(audio.defeat(), "resume permits a fresh event without stale cooldown")
	root.remove_child(audio)
	check(audio.active_voice_count() == 0 and not audio.defeat(), "orphan audio stops and rejects collapse")
	root.add_child(audio)
	audio.set_process(false)

func _test_real_lifecycle() -> void:
	var old_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	audio.audible = true
	check(audio.defeat("metal"), "real muted device plays collapse PCM")
	var voice: AudioStreamPlayer = audio.get_child(0)
	check(voice.playing and voice.has_stream_playback(), "actual collapse voice obtains mixer playback")
	var playback: WeakRef = weakref(voice.get_stream_playback())
	audio.advance(10.0)
	check(voice.playing and audio.active_voice_count() == 1, "large game delta cannot truncate real collapse tail")
	var deadline: int = Time.get_ticks_msec() + 2000
	while (voice.playing or voice.stream != null or audio.active_voice_count() > 0) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not voice.playing and voice.stream == null and audio.active_voice_count() == 0, "real mixer finishes and recycles collapse voice")
	check(await audio.wait_for_cleanup() and playback.get_ref() == null, "actual completed collapse releases its playback")
	for index: int in 12:
		check(audio.defeat(Audio.MATERIALS[index % 3]), "same-frame teardown accepts material wave")
		audio.stop_all()
	check(await audio.wait_for_cleanup() and audio.pending_playback_count() == 0, "repeated immediate stops leak no actual mixer playback")
	audio.audible = false
	AudioServer.set_bus_mute(0, old_mute)
