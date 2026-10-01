extends SceneTree
## Directed checks for the bounded charge-feedback API. Silent scheduling uses
## the real pool; no fabricated success signal or pending playback retry exists.
const Audio = preload("res://scripts/combat/combat_audio.gd")
const Music = preload("res://scripts/audio/music_director.gd")
var game: Node
var audio: Node
var music: Node
var app: Node
var events: Array[String] = []
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RESONANCE AUDIO FAIL: " + label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_resonance_audio"):
		push_error("Refusing non-test resonance profile")
		quit(2)
		return
	game.set_process(false)
	game.profile.settings.merge({"muted":false,"sfx_muted":false,"master_volume":1.0,"sfx_volume":1.0,"music_muted":false},true)
	audio = Audio.new()
	audio.audible = false
	root.add_child(audio)
	audio.set_process(false)
	audio.cue_played.connect(func(cue: String) -> void: events.append(cue))
	music = Music.new()
	music.audible = false
	root.add_child(music)
	music.configure(game)
	music.set_context("combat")
	music.set_process(false)
	# Invoke the production routing callback without starting its UI/room scene.
	app = load("res://scripts/ui/main.gd").new()
	app.route = "run"
	app.music = music
	audio.cue_played.connect(app._on_combat_cue_played)
	_test_pcm_and_cache()
	_export_samples()
	await _test_batch_and_full_priority()
	await _test_pool_and_no_retry()
	await _test_cancellation_interleaving()
	await _test_settings_and_rotation()
	check(await audio.wait_for_cleanup(), "charge fixture leaves no playback objects")
	app.free()
	music.free()
	audio.free()
	await process_frame
	print("RESONANCE AUDIO: %d/%d passed; PCM/actual signal and pool; no listening claim" % [checks-failures,checks])
	quit(1 if failures else 0)

func _flush() -> void:
	# The real call_deferred callback drains once. Extra observation never calls
	# it manually and must not invent an event on the following frame.
	await process_frame
	await process_frame

func _reset() -> void:
	paused = false
	game.profile.settings.merge({"muted":false,"sfx_muted":false,"master_volume":1.0,"sfx_volume":1.0},true)
	audio.stop_all()
	events.clear()

func _test_batch_and_full_priority() -> void:
	_reset()
	var before: int = audio.accepted_events
	for level: int in [1,2,1,3,2,3]: check(audio.resonance_charge(level), "synchronous batch admits charge " + str(level))
	check(events.is_empty() and audio.accepted_events == before and audio.active_voice_count() == 0, "admission is not reported as playback before the batch flush")
	await _flush()
	check(events == ["resonance_full"] and audio.active_voice_count() == 1 and audio.accepted_events == before+1, "one batch allocates only the highest charge, never partial plus full")
	check(is_equal_approx(music.impact_duck_gain(),1.0), "actual main cue handler never ducks music for charge confirmation")
	check(not audio.resonance_charge(3) and not audio.resonance_charge(1), "same-window duplicates are rejected after the full confirmation")
	await _flush()
	check(events.size() == 1, "rejected duplicates cannot emit later")
	_reset()
	check(audio.resonance_charge(1), "partial charge is admitted")
	await _flush()
	audio.advance(0.02)
	check(not audio.resonance_charge(2), "ordinary higher partial charge obeys the shared crowd gate")
	check(audio.resonance_charge(3), "new full charge can bypass a preceding partial confirmation gate")
	await _flush()
	check(events == ["resonance_1","resonance_full"] and audio.active_voice_count() == 2, "cross-batch full upgrade is one bounded quiet layer")
	check(not audio.resonance_charge(3), "full upgrade privilege is not repeatable in its window")
	audio.advance(0.099)
	check(not audio.resonance_charge(1), "charge clustering still blocks at 99ms")
	audio.advance(0.002)
	check(audio.resonance_charge(2), "next genuine charge opens after 100ms")
	await _flush()
	check(events.back() == "resonance_2", "all three charge stages have independent actual signal names")
	check(not audio.resonance_charge(0) and not audio.resonance_charge(4) and not audio.resonance_charge(-99), "unsupported levels reject instead of producing cache families")
	# Positive control: the same production handler still ducks for a real hit.
	check(audio.impact("CH03",true), "real heavy contact retains its foreground cue")
	music.advance(0.02)
	check(music.impact_duck_gain() < 1.0, "music routing positive control responds to heavy contact")

func _test_pool_and_no_retry() -> void:
	_reset()
	for index: int in 6: check(audio._request("CH01","heavy","passive_impact",0.0), "populate the six background slots")
	var streams: Array = []
	for voice: AudioStreamPlayer in audio.get_children(): streams.append(voice.stream)
	events.clear()
	check(audio.resonance_charge(3), "batch may be admitted before playback capacity is resolved")
	await _flush()
	check(events.is_empty() and audio.active_voice_count() == 6, "full charge cannot borrow either player reservation")
	check(audio.attack("CH03") and audio.impact("CH03"), "player attack and direct contact retain two reserved voices")
	check(audio.active_voice_count() == 8, "charge feature preserves total eight-voice cap")
	for index: int in 6: check(audio.get_child(index).stream == streams[index], "capacity rejection does not cut an existing waveform")
	var before: int = events.size()
	audio.advance(1.0)
	await _flush()
	check(events.size() == before and audio.active_voice_count() == 0, "rejected charge never retries after voice capacity returns")
	_reset()
	for index: int in 5: audio._request("CH01","heavy","passive_impact",0.0)
	events.clear()
	check(audio.resonance_charge(1), "last available background slot admits partial charge")
	await _flush()
	audio.advance(0.01)
	check(audio.resonance_charge(3), "full upgrade is admitted without stealing an earlier voice")
	await _flush()
	check(events == ["resonance_1"] and audio.active_voice_count() == 6, "full confirmation still yields when all six background voices are occupied")
	audio.advance(1.0)
	await _flush()
	check(events == ["resonance_1"], "failed upgrade also has no delayed retry")

func _test_cancellation_interleaving() -> void:
	_reset()
	check(audio.resonance_charge(1), "old partial request admitted before stop")
	audio.stop_all()
	check(audio.resonance_charge(3), "new full request admitted after stop in the same batch")
	await _flush()
	check(events == ["resonance_full"], "stale callback cannot clear or play over the newer post-stop request")
	_reset()
	check(audio.resonance_charge(1), "old request admitted before mute")
	game.profile.settings.sfx_muted = true
	check(not audio.resonance_charge(2), "mute cancels pending batch and refuses new admission")
	game.profile.settings.sfx_muted = false
	check(audio.resonance_charge(3), "unmute admits a fresh request before old callback drains")
	await _flush()
	check(events == ["resonance_full"] and audio.active_voice_count() == 1, "mute/unmute interleave plays only the fresh full confirmation")
	_reset()
	audio.resonance_charge(3)
	game.profile.settings.muted = true
	await _flush()
	check(events.is_empty() and audio.active_voice_count() == 0, "mute between admission and flush prevents playback")
	game.profile.settings.muted = false
	audio.advance(1.0)
	await _flush()
	check(events.is_empty(), "unmute cannot revive a discarded request")
	_reset()
	audio.resonance_charge(3)
	paused = true
	await _flush()
	check(events.is_empty() and audio.active_voice_count() == 0 and not audio.resonance_charge(2), "paused flush cancels charge without playback")
	paused = false
	audio.advance(1.0)
	await _flush()
	check(events.is_empty(), "resume has no queued charge retry")
	var stop_listener: Callable = func(_cue: String) -> void: audio.stop_all()
	audio.cue_played.connect(stop_listener)
	audio.resonance_charge(3)
	await _flush()
	check(events == ["resonance_full"] and audio.active_voice_count() == 0 and audio._cooldowns.is_empty(), "synchronous cue listener stop is not undone by stale post-signal state")
	audio.cue_played.disconnect(stop_listener)
	events.clear()
	check(audio.resonance_charge(1), "new partial request remains eligible after a reentrant stop")
	await _flush()
	check(events == ["resonance_1"], "post-stop request still runs normally")

func _test_settings_and_rotation() -> void:
	_reset()
	game.profile.settings.reduced_fx = true
	check(audio.resonance_charge(3), "reduced visual effects do not suppress charge feedback")
	await _flush()
	game.profile.settings.merge({"master_volume":0.4,"sfx_volume":0.5},true)
	audio.advance(0.01)
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db), Audio.VOICE_GAIN*Audio.RESONANCE_GAINS[2]*0.2), "settings refresh preserves full-charge attenuation")
	game.profile.settings.sfx_volume = 0.0
	check(not audio.resonance_charge(3) and audio.active_voice_count() == 0, "zero SFX volume stops and rejects charge")
	_reset()
	for level: int in [1,2,3]:
		var signatures: Dictionary = {}
		var first: AudioStream
		for index: int in 5:
			audio.stop_all()
			check(audio.resonance_charge(level), "finite rotation admits level " + str(level))
			await _flush()
			var stream: AudioStreamWAV = audio.get_child(0).stream
			signatures[hash(stream.data)] = true
			if index == 0: first = stream
			elif index == 4: check(stream == first, "four-variant rotation wraps level " + str(level))
		check(signatures.size() == 4, "all four independent takes occur at runtime for level " + str(level))

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var m: Dictionary = {"peak":0.0,"dc":0.0,"energy":0.0,"low":0.0,"late":0.0,"closure":0.0}
	var filtered: float = 0.0
	var alpha: float = 1.0-exp(-TAU*260.0/stream.mix_rate)
	for index: int in stream.data.size()/2:
		var sample_value: float = float(stream.data.decode_s16(index*2))/32768.0
		var energy: float = sample_value*sample_value/stream.mix_rate
		filtered += alpha*(sample_value-filtered)
		m.peak = maxf(m.peak,absf(sample_value))
		m.dc += sample_value/(stream.data.size()/2)
		m.energy += energy
		m.low += filtered*filtered/stream.mix_rate
		if index >= roundi(0.12*stream.mix_rate): m.late += energy
		if index >= roundi(0.035*stream.mix_rate) and index < roundi(0.095*stream.mix_rate): m.closure += energy
	return m

func _export_samples() -> void:
	var directory: String = "res://artifacts/resonance_audio"
	var created: Error = DirAccess.make_dir_recursive_absolute(directory)
	check(created == OK, "resonance audition output directory is available")
	if created != OK: return
	var summary: Dictionary = {"format":"production PCM, unchanged gain, no normalization", "runtime_voice_gain":Audio.VOICE_GAIN, "gain_rationale":"Sparse charge confirmations use event gains 0.70/0.80/0.90 so short transients are distinguishable alongside attacks. Full confirmation may reach 20% of heavy-contact energy; partial confirmations stay below 10%. PCM, master gain and pool priority are unchanged.", "samples":[]}
	for level: int in [1,2,3]:
		var cue: String = Audio.RESONANCE_CUES[level-1]
		var stream: AudioStreamWAV = Audio.stream_for("",cue,0)
		var file_path: String = directory+"/"+cue+"_v0.wav"
		check(stream.save_to_wav(file_path) == OK, cue + " exports the actual variant-zero PCM")
		var variants: Array = []
		for variant: int in 4: variants.append(_measure(Audio.stream_for("",cue,variant)))
		summary.samples.append({"cue":cue,"wav":ProjectSettings.globalize_path(file_path),"duration_seconds":stream.get_length(),"event_gain":Audio.RESONANCE_GAINS[level-1],"variant_metrics":variants})
	var file: FileAccess = FileAccess.open(directory+"/samples.json",FileAccess.WRITE)
	check(file != null, "resonance exports retain four-variant metrics and runtime gain metadata")
	if file != null:
		file.store_string(JSON.stringify(summary,"\t"))
		file.close()

func _test_pcm_and_cache() -> void:
	Audio.prewarm()
	check(Audio.RESONANCE_CUES == ["resonance_1","resonance_2","resonance_full"] and Audio._streams.size() == 248, "three four-take resonance families coexist with the finite 248-stream library including twenty-four shield streams")
	var signatures: Dictionary = {}
	for level: int in [1,2,3]:
		var cue: String = Audio.RESONANCE_CUES[level-1]
		for variant: int in 4:
			var stream: AudioStreamWAV = Audio.stream_for("",cue,variant)
			var m: Dictionary = _measure(stream)
			check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 24000 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, cue + " retains bounded mono PCM format")
			check(stream.get_length() >= 0.10 and stream.get_length() <= 0.20 and m.peak > 0.03 and m.peak <= Audio.SAMPLE_PEAK and absf(m.dc) < 0.003, cue + " has a short nonzero signal within peak/DC bounds")
			check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size()-2) == 0, cue + " waveform endpoints are zero")
			check(m.energy > 0.00001 and m.low/m.energy < 0.35 and m.late/m.energy < 0.03, cue + " avoids low-frequency dominance and sustained late hum")
			var foreground: Dictionary = _measure(Audio.stream_for("CH03","heavy",variant))
			# Full charge confirms a newly available player action. Its old 10%
			# background-layer ceiling hid that confirmation behind ordinary casts.
			# Allow 20% for full only; partial stages retain the 10% heavy budget.
			var heavy_limit: float = 0.20 if level == 3 else 0.10
			check(m.energy*pow(Audio.RESONANCE_GAINS[level-1],2) < foreground.energy*heavy_limit, cue + " remains below its explicit foreground-heavy energy budget")
			if level == 3:
				var partial: Dictionary = _measure(Audio.stream_for("","resonance_1",variant))
				check(m.closure > partial.closure*2.0, "full cue has a distinct late latch closure, not only a pitched-up partial")
			signatures[hash(stream.data)] = true
			check(stream.data != Audio.stream_for("","node_fire",variant).data and stream.data != Audio.stream_for("CH03","impact",variant).data, cue + " does not reuse firing or impact PCM")
	check(signatures.size() == 12, "three charge stages contain twelve distinct authored waveforms")
	for index: int in 12:
		for cue: String in Audio.RESONANCE_CUES:
			check(Audio.stream_for("unknown",cue,-41*index,"unknown") == Audio.stream_for("",cue,posmod(-41*index,4)), "charge cache inputs normalize before constructing keys")
		check(Audio.stream_for("","resonance_"+str(index+4)) == null, "unknown charge names cannot grow the cue domain")
	check(Audio._streams.size() == 248 and Audio.CUES.size() == 7 and Audio.MAX_VOICES == 8 and Audio.RESERVED_PLAYER_VOICES == 2, "new family preserves finite cache, seven hero slots and existing polyphony")
	check(Audio.SAMPLE_PEAK*Audio.VOICE_GAIN*Audio.MAX_VOICES+0.58*Music.MUSIC_GAIN < 0.95, "unchanged correlated SFX-plus-music peak budget remains below full scale")
