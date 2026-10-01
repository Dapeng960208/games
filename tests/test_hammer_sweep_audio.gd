extends "res://tests/test_skill_audio_timing.gd"
## The shared fixture uses actual Room/Player/Ability timeline and silent voices.
## Only the sweep release PCM changes; body impact remains a separate real event.

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HAMMER SWEEP AUDIO FAIL: " + label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_hammer_sweep_audio"):
		push_error("Refusing non-test hammer sweep profile")
		quit(2)
		return
	game.set_process(false)
	for action: String in ["move_left","move_right","move_up","move_down","attack","dash","interact","skill_q","skill_secondary","skill_f","skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated game starts")
	if game.run == null:
		quit(1)
		return
	room_scene = load("res://scenes/room.tscn")
	_test_sweep_pcm()
	_test_sweep_events()
	_test_sweep_rotation()
	check(await room.combat_audio.wait_for_cleanup(), "sweep fixture audio cleanup completes")
	room.free()
	print("HAMMER SWEEP AUDIO: %d/%d passed; actual release/contact and PCM, no listening claim" % [checks-failures,checks])
	quit(1 if failures else 0)

func _test_sweep_events() -> void:
	fixture("CH01")
	check(_cast("secondary"), "real empty-space sweep commits")
	check(events.size() == 1 and events[0].cue == "prepare_secondary", "commitment still plays only existing preparation")
	_advance(0.1799)
	check(_cues("secondary").is_empty(), "mechanical sweep release is not played before the real release boundary")
	_advance(0.0001)
	check(events.size() == 2 and _cues("prepare_secondary").size() == 1 and _cues("secondary").size() == 1, "actual whiff has one preparation and one sweep release")
	check(absf(float(_cues("secondary")[0].time)-0.18) < 0.00001, "release remains exactly on the original 180ms skill event")
	_advance(1.0)
	check(_cues("impact").is_empty() and _cues("heavy").is_empty() and events.size() == 2, "whiff and recovery never manufacture body contact or extra strikes")
	fixture("CH01")
	var target: Node2D = room.spawn_enemy(room.player.position+Vector2(60,0),"M01")
	target.health.reset(10000.0)
	target.status.guards.clear()
	target.training_ai_disabled = true
	check(_cast("secondary"), "real sweep commits toward a living unshielded target")
	_advance(0.1799)
	check(target.health.current == 10000.0 and _cues("heavy").is_empty(), "no premature sweep damage or confirmation")
	_advance(0.0001)
	check(target.health.current < 10000.0 and target.is_alive(), "actual sweep removes enemy health")
	check(_cues("secondary").size() == 1 and _cues("heavy").size() == 1 and _cues("impact").is_empty(), "real contact retains exactly one separate heavy confirmation")
	check(absf(float(_cues("heavy")[0].time)-0.18) < 0.00001, "heavy confirmation remains attached to the actual contact boundary")
	var real_heavy: bool = false
	for voice: AudioStreamPlayer in room.combat_audio.get_children():
		for variant: int in 4:
			if voice.stream == Audio.stream_for("CH01","heavy",variant,target.impact_material()): real_heavy = true
	check(real_heavy, "contact still plays the existing material-aware heavy PCM")
	_advance(1.0)
	check(_cues("heavy").size() == 1 and _cues("secondary").size() == 1, "recovery does not duplicate either layer")
	fixture("CH01")
	check(_cast("secondary"), "cancellation fixture commits real sweep")
	_advance(0.10)
	check(room.player.start_dash(Vector2.UP), "actual defensive dash interrupts the windup")
	_advance(1.0)
	check(events.size() == 1 and events[0].cue == "prepare_secondary", "cancelled windup produces no future sweep or impact sound")

func _test_sweep_rotation() -> void:
	fixture("CH01")
	var signatures: Dictionary = {}
	var first: AudioStream
	for index: int in 5:
		room.combat_audio.stop_all()
		check(room.combat_audio.cast("CH01","secondary"), "actual release API allocates sweep take")
		var stream: AudioStreamWAV = room.combat_audio.get_child(0).stream
		signatures[hash(stream.data)] = true
		if index == 0: first = stream
		elif index == 4: check(stream == first, "fifth release wraps to the first of four cached takes")
	check(signatures.size() == 4, "runtime uses all four independent wind and linkage waveforms")

func _sweep_measure(stream: AudioStreamWAV) -> Dictionary:
	var m: Dictionary = {"peak":0.0,"dc":0.0,"energy":0.0,"early":0.0,"core":0.0,"late":0.0,"centroid_seconds":0.0,"rms":0.0,"peak20ms_rms":0.0,"peak20ms_center":0.0}
	var count: int = stream.data.size()/2
	var window: int = roundi(stream.mix_rate*0.02)
	var squares: PackedFloat64Array = []
	squares.resize(count)
	var rolling: float = 0.0
	for index: int in count:
		var v: float = float(stream.data.decode_s16(index*2))/32768.0
		var t: float = float(index)/stream.mix_rate
		var energy: float = v*v/stream.mix_rate
		squares[index] = v*v
		rolling += squares[index]
		if index >= window: rolling -= squares[index-window]
		if index >= window-1 and rolling/window > m.peak20ms_rms:
			m.peak20ms_rms = rolling/window
			m.peak20ms_center = t-0.01
		m.peak = maxf(m.peak,absf(v))
		m.dc += v/count
		m.energy += energy
		m.centroid_seconds += t*energy
		if t < 0.025: m.early += energy
		if t >= 0.045 and t < 0.16: m.core += energy
		if t >= 0.245: m.late += energy
	m.centroid_seconds /= maxf(m.energy,0.000000001)
	m.rms = sqrt(m.energy/stream.get_length())
	m.peak20ms_rms = sqrt(maxf(0.0,m.peak20ms_rms))
	return m

func _test_sweep_pcm() -> void:
	Audio.prewarm()
	check(Audio._streams.size() == 248 and Audio.CUES.size() == 7 and Audio.MAX_VOICES == 8, "sweep redesign adds no cache domain or voices")
	var directory: String = "res://artifacts/hammer_sweep_audio"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "raw sweep sample directory is available")
	var signatures: Dictionary = {}
	var samples: Array = []
	for variant: int in 4:
		var stream: AudioStreamWAV = Audio.stream_for("CH01","secondary",variant)
		var m: Dictionary = _sweep_measure(stream)
		var q: Dictionary = _sweep_measure(Audio.stream_for("CH01","q",variant))
		var f: Dictionary = _sweep_measure(Audio.stream_for("CH01","f",variant))
		signatures[hash(stream.data)] = true
		check(absf(stream.get_length()-0.28) <= 1.1/Audio.SAMPLE_RATE and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 24000 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "sweep keeps its 280ms mono nonlooping format")
		check(m.peak > 0.15 and m.peak <= Audio.SAMPLE_PEAK and absf(m.dc) < 0.003 and stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size()-2) == 0, "sweep retains substantial signal, clean endpoints and peak/DC safety")
		check(m.energy > 0.0004 and m.peak20ms_rms*Audio.VOICE_GAIN*0.85 > 0.008, "sweep core has useful runtime-level transient energy rather than only a measurable click")
		check(m.core/m.energy > 0.55 and m.early/m.energy < 0.15 and m.peak20ms_center > 0.045, "wide sweep grows after the small mechanical release rather than starting with a blast")
		check(m.centroid_seconds > q.centroid_seconds+0.015 and m.centroid_seconds > f.centroid_seconds+0.015, "sweep contour is measurably later than Q/F piston releases at independent waveform gains")
		check(m.late/m.energy < 0.01, "wind ends within the cue without a sustained hum or hidden late strike")
		check(stream.data != Audio.stream_for("CH01","heavy",variant).data and stream.data != Audio.stream_for("CH01","attack",variant).data, "sweep is distinct from actual impact and ordinary attack")
		var path: String = directory+"/CH01_secondary_v"+str(variant)+".wav"
		check(stream.save_to_wav(path) == OK, "export the unchanged production sweep PCM")
		samples.append({"variant":variant,"wav":ProjectSettings.globalize_path(path),"metrics":m,"q_centroid_seconds":q.centroid_seconds,"f_centroid_seconds":f.centroid_seconds})
		print("HAMMER SWEEP PCM v%d peak=%.4f RMS=%.4f center=%.3fs core=%.1f%% early=%.1f%%" % [variant,m.peak,m.rms,m.centroid_seconds,m.core/m.energy*100,m.early/m.energy*100])
	check(signatures.size() == 4, "all four sweep takes contain independent waveforms")
	check(Audio.SAMPLE_PEAK*Audio.VOICE_GAIN*Audio.MAX_VOICES+0.58*0.18 < 0.95, "unchanged correlated mix headroom remains within its existing budget")
	var file: FileAccess = FileAccess.open(directory+"/samples.json",FileAccess.WRITE)
	check(file != null, "sweep metrics and export gain contract are writable")
	if file != null:
		file.store_string(JSON.stringify({"format":"original production PCM, no audition normalization or gain adjustment","cue":"CH01/secondary","release_time_seconds":0.18,"cue_duration_seconds":0.28,"voice_gain":Audio.VOICE_GAIN,"example_master":1.0,"example_sfx_volume":0.85,"event_gain":1.0,"samples":samples},"\t"))
		file.close()
