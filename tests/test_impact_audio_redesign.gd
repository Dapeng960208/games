extends SceneTree
## Production PCM, four variants, material response and real mixer lifecycle.
## Run with --audio-driver Dummy --script res://tests/test_impact_audio_redesign.gd
## -- --test-profile=<isolated path containing test_impact_audio_redesign>.
## Measurements and muted playback are not a claim of a human listening review.

const Audio = preload("res://scripts/combat/combat_audio.gd")
const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const CUES: Array[String] = ["attack", "impact", "heavy", "q", "secondary", "f", "ultimate"]
const MATERIALS: Array[String] = ["stone", "metal", "organic"]
const PREVIEW_DIRECTORY: String = "res://assets/audio/previews"
const PREVIEW_SECONDS: float = 12.0
const AUDITION_GAIN: float = 4.0

var checks: int = 0
var failures: int = 0
var audio: Node
var game: Node
var measurements: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	var requested_profile: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="):
			requested_profile = argument.trim_prefix("--test-profile=")
	game = root.get_node_or_null("Game")
	if not requested_profile.contains("test_impact_audio_redesign") or game == null or str(game.profile_path) != requested_profile:
		push_error("Refusing non-test profile; pass -- --test-profile=<isolated path containing test_impact_audio_redesign>")
		quit(2)
		return
	var saved_settings: Dictionary = game.profile.settings.duplicate(true)
	game.profile.settings["muted"] = false
	game.profile.settings["sfx_muted"] = false
	game.profile.settings["master_volume"] = 1.0
	game.profile.settings["sfx_volume"] = 1.0
	_test_pcm_library()
	_test_materials_and_dynamics()
	_test_cache_bounds()
	audio = Audio.new()
	audio.audible = false
	root.add_child(audio)
	# Deterministic scheduling tests own the clock; real finished signals still run.
	audio.set_process(false)
	_test_pool_and_throttle()
	_test_event_routing_and_variants()
	_test_passive_priority()
	_test_settings_and_pause()
	await _test_real_playback()
	_export_showcase()
	check(await audio.wait_for_cleanup(), "final teardown releases all mixer playbacks")
	check(audio.pending_playback_count() == 0, "final teardown retains no playback weak references")
	audio.free()
	game.profile.settings = saved_settings
	print("IMPACT AUDIO REDESIGN: %d checks, %d failures (PCM/runtime/muted mixer; no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var bytes: PackedByteArray = stream.data
	var count: int = bytes.size() / 2
	var peak: float = 0.0
	var total: float = 0.0
	var energy: float = 0.0
	for index: int in count:
		var sample_value: float = float(bytes.decode_s16(index * 2)) / 32768.0
		peak = maxf(peak, absf(sample_value))
		total += sample_value
		energy += sample_value * sample_value
	return {
		"peak": peak,
		"mean": total / maxi(count, 1),
		"rms": sqrt(energy / maxi(count, 1)),
		"energy": energy / float(stream.mix_rate),
	}

func _verify_pcm(hero: String, cue: String, variation: int, material: String = "stone") -> AudioStreamWAV:
	var label: String = "%s/%s/v%d/%s" % [hero, cue, variation, material]
	var stream: AudioStreamWAV = Audio.stream_for(hero, cue, variation, material)
	check(stream != null, label + " resolves to production PCM")
	if stream == null:
		return null
	check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo and stream.mix_rate == Audio.SAMPLE_RATE, label + " uses 24 kHz mono 16-bit PCM")
	check(stream.data.size() >= 2 and stream.data.size() % 2 == 0, label + " contains complete PCM frames")
	if stream.data.size() < 2:
		return null
	var metric: Dictionary = _measure(stream)
	measurements[label] = metric
	check(stream.get_length() >= 0.06 and stream.get_length() <= 1.0, label + " has a short bounded duration")
	check(metric.peak > 0.01 and metric.peak <= Audio.SAMPLE_PEAK + 0.001, label + " preserves signal with bounded peak headroom")
	check(absf(metric.mean) < 0.003 and metric.rms > 0.003, label + " has negligible DC and meaningful energy")
	check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0, label + " begins and ends at exact zero")
	check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, label + " is a one-shot")
	check(stream == Audio.stream_for(hero, cue, variation, material), label + " reuses its cached resource")
	return stream

func _test_pcm_library() -> void:
	check(Audio.SAMPLE_RATE == 24000 and is_equal_approx(Audio.SAMPLE_PEAK, 0.74), "production sample format and peak budget remain explicit")
	check(Audio.MAX_VOICES == 8 and is_equal_approx(Audio.VOICE_GAIN, 0.14), "production voice count and gain remain conservative")
	check(Audio.HEROES == HEROES and Audio.CUES == CUES, "three heroes retain all seven gameplay cues")
	check(Audio.SAMPLE_PEAK * Audio.VOICE_GAIN * Audio.MAX_VOICES < 0.95, "eight correlated peak voices retain master headroom")
	for hero: String in HEROES:
		var cue_signatures: Dictionary = {}
		for cue: String in CUES:
			var variant_signatures: Dictionary = {}
			for variation: int in 4:
				var stream: AudioStreamWAV = _verify_pcm(hero, cue, variation)
				if stream != null:
					variant_signatures[hash(stream.data)] = true
					if variation == 0:
						cue_signatures[hash(stream.data)] = true
			check(variant_signatures.size() == 4, hero + "/" + cue + " provides four different actual PCM variants")
		check(cue_signatures.size() == 7, hero + " retains seven distinct authored cue waveforms")
	for cue: String in ["hurt", "pickup"]:
		var signatures: Dictionary = {}
		for variation: int in 4:
			var stream: AudioStreamWAV = _verify_pcm("", cue, variation)
			if stream != null:
				signatures[hash(stream.data)] = true
		check(signatures.size() == 4, cue + " provides four actual PCM variants")
	for cue: String in CUES:
		var signatures: Dictionary = {}
		for hero: String in HEROES:
			var stream: AudioStreamWAV = Audio.stream_for(hero, cue)
			if stream != null:
				signatures[hash(stream.data)] = true
		check(signatures.size() == 3, cue + " preserves distinct hero sound identities")

func _test_materials_and_dynamics() -> void:
	for hero: String in HEROES:
		for variation: int in 4:
			var impact_signatures: Dictionary = {}
			var heavy_signatures: Dictionary = {}
			for material: String in MATERIALS:
				var light: AudioStreamWAV = _verify_pcm(hero, "impact", variation, material)
				var heavy: AudioStreamWAV = _verify_pcm(hero, "heavy", variation, material)
				if light == null or heavy == null:
					continue
				impact_signatures[hash(light.data)] = true
				heavy_signatures[hash(heavy.data)] = true
				var light_metric: Dictionary = measurements["%s/impact/v%d/%s" % [hero, variation, material]]
				var heavy_metric: Dictionary = measurements["%s/heavy/v%d/%s" % [hero, variation, material]]
				var label: String = "%s/v%d/%s" % [hero, variation, material]
				check(heavy_metric.energy > light_metric.energy * 1.3, label + " heavy hit has at least 30% more integrated PCM energy")
				check(absf(heavy_metric.peak - light_metric.peak) > 0.01, label + " light and heavy are not independently normalized to one peak")
				if variation == 0:
					print("IMPACT ENERGY %s: light=%.6f heavy=%.6f ratio=%.2f peaks=%.3f/%.3f" % [label, light_metric.energy, heavy_metric.energy, heavy_metric.energy / maxf(light_metric.energy, 0.000001), light_metric.peak, heavy_metric.peak])
			check(impact_signatures.size() == 3 and heavy_signatures.size() == 3, "%s/v%d uses different PCM for stone, metal and organic hits" % [hero, variation])

func _test_cache_bounds() -> void:
	# Warm the complete finite domain before probing arbitrary external inputs.
	for hero: String in HEROES:
		for cue: String in CUES + Audio.PREPARE_CUES:
			for variation: int in 4:
				for material: String in MATERIALS:
					Audio.stream_for(hero, cue, variation, material)
	for cue: String in ["hurt", "pickup"]:
		for variation: int in 4:
			for material: String in MATERIALS:
				Audio.stream_for("", cue, variation, material)
	for variation: int in 4:
		for material: String in MATERIALS:
			Audio.stream_for("", "defeat", variation, material)
		for cue: String in Audio.DEPLOYMENT_CUES:
			Audio.stream_for("", cue, variation)
	var warmed_size: int = Audio._streams.size()
	check(warmed_size == 248, "cache is exactly 132 hero releases/hits, 48 preparations, 8 hurt/pickup, 12 defeats, 12 deployment, 12 resonance and 24 shield events")
	for index: int in 64:
		check(Audio.stream_for("missing_%d" % index, "impact") == null, "invalid hero cannot create a stream")
		check(Audio.stream_for("CH01", "missing_%d" % index) == null, "invalid cue cannot create a stream")
		# Rejection or normalization is acceptable; a new cache key is not.
		Audio.stream_for("CH01", "impact", index * 1003 - 31000, "unknown_%d" % index)
		Audio.stream_for("CH02", "heavy", index * 997 + 4, "metal")
		Audio.stream_for("CH03", "q", index * -991 - 1, "organic")
		Audio.stream_for("unknown_%d" % index, "hurt", index, "unknown_%d" % index)
		Audio.stream_for("unknown_%d" % index, "defeat", index * 991 - 27000, "unknown_%d" % index)
		Audio.stream_for("CH02", "prepare_secondary", index * -13, "unknown_%d" % index)
	check(Audio._streams.size() == warmed_size, "invalid and out-of-range inputs cannot grow the warmed cache")

func _test_pool_and_throttle() -> void:
	check(audio.get_child_count() == 8, "pool owns exactly eight players")
	for voice: AudioStreamPlayer in audio.get_children():
		check(voice.max_polyphony == 1 and is_equal_approx(voice.pitch_scale, 1.0), "each player is monophonic at authored PCM pitch")
	check(audio.attack("CH01") and audio.impact("CH01", false, "stone"), "action and confirmed hit may coexist")
	check(audio.impact("CH02", true, "metal"), "first heavy contact survives an earlier ordinary contact in the same window")
	for index: int in 24:
		check(not audio.impact(HEROES[index % 3], index % 2 == 0, MATERIALS[index % 3]), "heavy AOE contact suppresses subsequent same-window contacts across hero and material")
	check(audio.active_voice_count() == 3, "mixed same-frame AOE keeps at most one ordinary and one heavy contact voice")
	audio.advance(0.054)
	check(not audio.impact("CH02", true, "metal"), "impact remains blocked at 54 ms")
	audio.advance(0.002)
	check(audio.impact("CH03", true, "organic"), "impact reopens beyond the 55 ms interval")
	audio.stop_all()
	for index: int in 6:
		check(audio._request("CH01", "ultimate", "passive_impact", 0.0), "background confirmation may occupy an unreserved voice")
	check(not audio._request("CH01", "ultimate", "passive_impact", 0.0), "background confirmations cannot occupy either player reserve")
	check(audio.attack("CH02") and audio.impact("CH02", false, "metal"), "six background voices preserve both player attack and ordinary direct contact")
	check(_is_variant(audio.get_child(7).stream, "CH02", "impact", "metal"), "eighth voice is the actual direct light-contact PCM, not a heavy workaround")
	check(audio.active_voice_count() == 8, "mixed-priority pool respects the hard eight-voice cap")
	var retained_streams: Array[AudioStream] = []
	for voice: AudioStreamPlayer in audio.get_children():
		retained_streams.append(voice.stream)
	var retained_endings: Array = audio._ends.duplicate()
	check(not audio.cast("CH03", "q"), "ninth voice is rejected without stealing a live tail")
	check(audio._ends == retained_endings, "rejected player event leaves all scheduled tail endings intact")
	for index: int in retained_streams.size():
		check(audio.get_child(index).stream == retained_streams[index], "rejected player event retains every active production stream")
	for voice: AudioStreamPlayer in audio.get_children():
		check(not voice.playing and is_equal_approx(voice.pitch_scale, 1.0), "silent scheduling retains authored pitch without device playback")
	audio.advance(1.1)
	check(audio.active_voice_count() == 0 and audio.cast("CH03", "q"), "completed silent voices return to the pool")
	audio.stop_all()
	check(audio.attack("CH02"), "rail action starts the 75 ms anti-buzz interval")
	audio.advance(0.074)
	check(not audio.attack("CH02"), "rail action remains throttled at 74 ms")
	audio.advance(0.002)
	check(audio.attack("CH02"), "rail action reopens beyond 75 ms")
	audio.stop_all()

func _is_variant(stream: AudioStreamWAV, hero: String, cue: String, material: String = "stone") -> bool:
	for variation: int in 4:
		if stream == Audio.stream_for(hero, cue, variation, material):
			return true
	return false

func _test_event_routing_and_variants() -> void:
	for hero: String in HEROES:
		for cue: String in CUES:
			var signatures: Dictionary = {}
			var first_stream: AudioStreamWAV
			for repetition: int in 5:
				audio.stop_all()
				var accepted: bool = false
				if cue == "attack":
					accepted = audio.attack(hero)
				elif cue in ["impact", "heavy"]:
					accepted = audio.impact(hero, cue == "heavy", "metal")
				else:
					accepted = audio.cast(hero, cue)
				check(accepted and audio.active_voice_count() == 1, hero + "/" + cue + " routes to one explicit event voice")
				var voice: AudioStreamPlayer = audio.get_child(0)
				var played_stream: AudioStreamWAV = voice.stream as AudioStreamWAV
				var material: String = "metal" if cue in ["impact", "heavy"] else "stone"
				check(_is_variant(played_stream, hero, cue, material), hero + "/" + cue + " selects its correct cue/material PCM family")
				check(is_equal_approx(voice.pitch_scale, 1.0), hero + "/" + cue + " varies the waveform without playback pitch shifting")
				if played_stream != null:
					signatures[hash(played_stream.data)] = true
				if repetition == 0:
					first_stream = played_stream
				elif repetition == 4:
					check(voice.stream == first_stream, hero + "/" + cue + " returns to the first PCM after a four-variant cycle")
			check(signatures.size() == 4, hero + "/" + cue + " cycles all four authored runtime variants")
	# This checks event separation; waveform perception still requires listening.
	audio.stop_all()
	check(audio.attack("CH01"), "a miss schedules the action cue")
	check(audio.active_voice_count() == 1 and _is_variant(audio.get_child(0).stream, "CH01", "attack"), "swinging into air schedules no confirmation event")
	audio.stop_all()
	check(not audio.cast("CH01", "impact") and not audio.cast("CH01", "heavy"), "cast API cannot manufacture hit-confirmation cues")
	audio.stop_all()

func _test_passive_priority() -> void:
	audio.stop_all()
	var events: Array[String] = []
	var observer: Callable = func(cue: String) -> void: events.append(cue)
	audio.cue_played.connect(observer)
	check(audio.impact("CH03", false, "metal", true), "passive contact accepts its own background event")
	check(events == ["passive_impact"], "passive confirmation does not emit foreground impact/music-duck cue")
	var passive_voice: AudioStreamPlayer = audio.get_child(0)
	check(is_equal_approx(db_to_linear(passive_voice.volume_db), Audio.VOICE_GAIN * 0.48), "passive actual voice has 0.48 relative gain")
	audio.advance(0.01)
	check(is_equal_approx(db_to_linear(passive_voice.volume_db), Audio.VOICE_GAIN * 0.48), "settings refresh preserves per-voice passive gain")
	check(audio.impact("CH03", false, "metal") and audio.impact("CH01", true), "recent passive hit swallows neither direct light nor heavy contact")
	check(events == ["passive_impact", "impact", "heavy"], "direct player cues remain independent and foreground")
	check(not audio.impact("CH02", false, "stone", true), "player contact suppresses subsequent passive crowd")
	audio.advance(0.089)
	check(not audio.impact("CH03", false, "organic", true), "passive retains own 100ms gate even after a foreground hit")
	audio.advance(0.002)
	check(audio.impact("CH03", false, "organic", true), "passive gate reopens after 100ms")
	audio.stop_all()
	check(audio.impact("CH01"), "direct hit can lead a fresh interval")
	audio.advance(0.054)
	check(not audio.impact("CH03", false, "stone", true), "fresh passive hit cannot intrude before 55ms after direct contact")
	audio.advance(0.002)
	check(audio.impact("CH03", false, "stone", true), "passive becomes eligible after direct suppression expires")
	audio.stop_all()
	for index: int in 6:
		check(audio._request("CH01", "heavy", "passive_impact", 0.0, "stone", 0.48), "passive fill remains in shared background budget")
	check(not audio.impact("CH03", true, "stone", true), "even heavy passive cues cannot occupy player reserves")
	check(audio.cast("CH02", "secondary") and audio.impact("CH01", true), "actual skill release and heavy contact retain both player reserves")
	check(audio.active_voice_count() == 8, "passive routing never expands voice count")
	audio.stop_all()
	check(audio.attack("CH02"), "recycled passive slot accepts direct shot")
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db), Audio.VOICE_GAIN), "recycled foreground voice resets passive attenuation")
	audio.cue_played.disconnect(observer)
	audio.stop_all()

func _test_settings_and_pause() -> void:
	game.profile.settings["reduced_fx"] = true
	check(audio.attack("CH01"), "reduced visual effects preserves sound")
	game.profile.settings["master_volume"] = 0.4
	game.profile.settings["sfx_volume"] = 0.5
	audio.advance(0.01)
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db), Audio.VOICE_GAIN * 0.2), "master and SFX gain multiply once")
	game.profile.settings["sfx_muted"] = true
	audio.advance(0.01)
	check(audio.active_voice_count() == 0 and not audio.impact("CH01"), "SFX mute stops tails and refuses new confirmations")
	game.profile.settings["sfx_muted"] = false
	game.profile.settings["muted"] = true
	check(not audio.hurt(), "master mute refuses new player sounds")
	game.profile.settings["muted"] = false
	game.profile.settings["sfx_volume"] = 0.0
	check(not audio.pickup(), "zero SFX gain refuses playback")
	game.profile.settings["sfx_volume"] = INF
	check(not audio.pickup(), "nonfinite gain cannot create playback")
	game.profile.settings["master_volume"] = 1.0
	game.profile.settings["sfx_volume"] = 1.0
	check(audio.impact("CH01", true, "metal"), "restored settings allow a fresh impact")
	paused = true
	audio.advance(0.2)
	check(audio.active_voice_count() == 0, "pause clears existing tails")
	check(not audio.attack("CH01") and not audio.cast("CH03", "q"), "pause rejects fresh combat sounds")
	paused = false
	check(audio.impact("CH03", false, "organic"), "resume accepts a fresh hit without stale cooldown")
	audio.stop_all()
	for voice: AudioStreamPlayer in audio.get_children():
		check(voice.stream == null and not voice.playing, "stop_all releases player streams")
	root.remove_child(audio)
	check(not audio.pickup() and audio.active_voice_count() == 0, "orphan audio refuses playback")
	root.add_child(audio)
	check(audio.attack("CH02"), "re-entered audio accepts a fresh action")
	audio.stop_all()

func _test_real_playback() -> void:
	var previous_master_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	audio.audible = true
	check(audio.impact("CH01", true, "metal"), "muted device path accepts a real material impact")
	var voice: AudioStreamPlayer = audio.get_child(0)
	check(voice.playing and voice.has_stream_playback() and _is_variant(voice.stream as AudioStreamWAV, "CH01", "heavy", "metal"), "AudioStreamPlayer plays the production material PCM")
	check(is_equal_approx(voice.pitch_scale, 1.0), "real playback preserves authored pitch")
	var playback_ref: WeakRef = weakref(voice.get_stream_playback()) if voice.has_stream_playback() else null
	audio.advance(10.0)
	check(voice.playing and audio.active_voice_count() == 1, "game-clock advancement cannot truncate a mixer-clock tail")
	# SceneTreeTimer uses game-frame delta: first-frame synthesis work can make
	# that timer expire before the independent audio mixer has played its tail.
	var natural_deadline: int = Time.get_ticks_msec() + 2000
	# Mixer completion can precede the main-thread finished callback by one frame.
	while (voice.playing or voice.stream != null or audio.active_voice_count() > 0) and Time.get_ticks_msec() < natural_deadline:
		await process_frame
	check(not voice.playing and voice.stream == null and audio.active_voice_count() == 0, "real finished signal releases the completed voice")
	check(await audio.wait_for_cleanup(), "natural completion releases tracked mixer playback")
	check(playback_ref != null and playback_ref.get_ref() == null, "natural completion actually destroys its weakly observed playback")
	check(audio.attack("CH02"), "real action starts before audibility is disabled")
	audio.audible = false
	check(not voice.playing and audio.active_voice_count() == 0, "disabling audibility stops real playback immediately")
	audio.audible = true
	check(audio.hurt() and voice.playing, "real player sound starts before SFX mute")
	game.profile.settings["sfx_muted"] = true
	audio.advance(0.01)
	check(not voice.playing and voice.stream == null and not audio.pickup(), "SFX mute stops real playback and rejects a new sound")
	game.profile.settings["sfx_muted"] = false
	check(audio.cast("CH03", "q") and voice.playing, "real skill sound starts before pause")
	paused = true
	audio.advance(0.01)
	check(not voice.playing and voice.stream == null and not audio.attack("CH01"), "pause stops real playback and rejects a new sound")
	paused = false
	var immediate_refs: Array[WeakRef] = []
	for index: int in 16:
		check(audio.attack("CH02"), "same-frame teardown accepts a real action")
		if voice.has_stream_playback():
			immediate_refs.append(weakref(voice.get_stream_playback()))
		audio.stop_all()
	check(immediate_refs.size() == 16, "every immediate-stop case creates a real mixer playback")
	check(await audio.wait_for_cleanup(), "same-frame play/stop waits for actual mixer cleanup")
	for playback: WeakRef in immediate_refs:
		check(playback.get_ref() == null, "same-frame stop releases its weakly observed playback")
	check(audio.pending_playback_count() == 0, "real playback tests retain no mixer objects")
	audio.audible = false
	AudioServer.set_bus_mute(0, previous_master_mute)

func _mix_cue(samples: PackedFloat32Array, at_seconds: float, hero: String, cue: String, variation: int, material: String, timeline: Array[String]) -> void:
	var stream: AudioStreamWAV = Audio.stream_for(hero, cue, variation, material)
	if stream == null:
		check(false, "showcase cue resolves: " + hero + "/" + cue)
		return
	var offset: int = roundi(at_seconds * Audio.SAMPLE_RATE)
	check(offset + stream.data.size() / 2 <= samples.size(), "showcase preserves the entire production tail: " + hero + "/" + cue)
	for index: int in stream.data.size() / 2:
		if offset + index < samples.size():
			# One fixed audition gain preserves authored event-to-event dynamics.
			samples[offset + index] += float(stream.data.decode_s16(index * 2)) / 32768.0 * Audio.VOICE_GAIN * AUDITION_GAIN
	timeline.append("%06.3f s  %s  %-9s variation=%d material=%s duration=%.3f s" % [at_seconds, hero, cue, variation, material, stream.get_length()])

func _export_showcase() -> void:
	check(DirAccess.make_dir_recursive_absolute(PREVIEW_DIRECTORY) == OK, "showcase output directory is available")
	var samples := PackedFloat32Array()
	samples.resize(roundi(PREVIEW_SECONDS * Audio.SAMPLE_RATE))
	samples.fill(0.0)
	var timeline: Array[String] = [
		"Impact redesign showcase — 12.000 s / 24 kHz / mono / 16-bit PCM",
		"Generated from exact CombatAudio.stream_for production PCM at VOICE_GAIN=0.14, with one fixed AUDITION_GAIN=4.0 (+12.04 dB).",
		"The audition is louder than runtime by the same factor for every cue; relative event dynamics are preserved.",
		"No per-cue normalization, extra limiter, synthesis or pitch shifting is applied here.",
		"Each 4 s hero block: swing/fire into air, light confirmed hit, heavy confirmed hit, skill with hit confirmation.",
		"The bus was muted during automated playback checks; this export is for a separate listening review.",
		"",
	]
	for hero_index: int in HEROES.size():
		var hero: String = HEROES[hero_index]
		var base: float = float(hero_index) * 4.0
		var material: String = MATERIALS[hero_index]
		timeline.append("--- %s / %s ---" % [hero, material])
		_mix_cue(samples, base + 0.20, hero, "attack", 0, material, timeline)
		_mix_cue(samples, base + 1.00, hero, "attack", 1, material, timeline)
		_mix_cue(samples, base + 1.12, hero, "impact", 1, material, timeline)
		_mix_cue(samples, base + 1.90, hero, "attack", 2, material, timeline)
		_mix_cue(samples, base + 2.02, hero, "heavy", 2, material, timeline)
		_mix_cue(samples, base + 2.95, hero, "q", 3, material, timeline)
		_mix_cue(samples, base + 3.09, hero, "heavy", 3, material, timeline)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var peak: float = 0.0
	for index: int in samples.size():
		peak = maxf(peak, absf(samples[index]))
		bytes.encode_s16(index * 2, roundi(clampf(samples[index], -1.0, 1.0) * 32767.0))
	check(peak > 0.01 and peak < 1.0, "showcase mixes production dynamics with no clipping")
	var showcase := AudioStreamWAV.new()
	showcase.format = AudioStreamWAV.FORMAT_16_BITS
	showcase.mix_rate = Audio.SAMPLE_RATE
	showcase.stereo = false
	showcase.loop_mode = AudioStreamWAV.LOOP_DISABLED
	showcase.data = bytes
	check(showcase.save_to_wav(PREVIEW_DIRECTORY + "/impact_redesign_showcase.wav") == OK, "12-second production showcase exports")
	check(is_equal_approx(showcase.get_length(), PREVIEW_SECONDS), "showcase is exactly twelve seconds")
	var description: FileAccess = FileAccess.open(PREVIEW_DIRECTORY + "/impact_redesign_showcase.txt", FileAccess.WRITE)
	check(description != null, "showcase cue timeline opens for export")
	if description != null:
		description.store_string("\n".join(timeline) + "\n")
		description.close()
	print("IMPACT SHOWCASE: %s/impact_redesign_showcase.wav (%.3f s, peak=%.4f)" % [PREVIEW_DIRECTORY, PREVIEW_SECONDS, peak])
