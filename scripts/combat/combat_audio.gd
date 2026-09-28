class_name CombatAudio
extends Node
## Original deterministic oscillator/noise SFX. No recordings or external assets.
## One room owns this node. Samples are cached across rooms; players are local.

const SAMPLE_RATE: int = 24000
const MAX_VOICES: int = 8
const SAMPLE_PEAK: float = 0.74
# Even eight perfectly correlated peaks remain below full scale on our bus.
const VOICE_GAIN: float = 0.16
const IMPACT_INTERVAL: float = 0.055
const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const CUES: Array[String] = ["attack", "impact", "heavy", "q", "secondary", "f", "ultimate"]

static var _streams: Dictionary = {}
static var _playback_refs: Array[WeakRef] = []

## False keeps the real scheduling/pool path testable without sending audio.
@export var audible: bool = true:
	set(value):
		audible = value
		if not value:
			stop_all()

var _players: Array[AudioStreamPlayer] = []
var _ends: Array[float] = []
var _clock: float = 0.0
var _cooldowns: Dictionary = {}
var _gain: float = 0.85
var _muted: bool = false
var accepted_events: int = 0
var rejected_events: int = 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	prewarm()
	_ensure_players()
	_refresh_settings()

func _process(delta: float) -> void:
	advance(delta)

func _exit_tree() -> void:
	stop_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		stop_all()

func attack(hero_id: String) -> bool:
	return _request(hero_id, "attack", "attack", 0.04)

func cast(hero_id: String, slot: String) -> bool:
	if slot not in ["q", "secondary", "f", "ultimate"]:
		return false
	return _request(hero_id, slot, "cast", 0.06)

func impact(hero_id: String, heavy: bool = false) -> bool:
	# Shared across heroes/heavy hits: an AOE hitting a crowd makes one impact.
	return _request(hero_id, "heavy" if heavy else "impact", "impact", IMPACT_INTERVAL)

func hurt() -> bool:
	return _request("", "hurt", "hurt", 0.12)

func pickup() -> bool:
	return _request("", "pickup", "pickup", 0.08)

func stop_all() -> void:
	for index: int in _players.size():
		_players[index].stop()
		_players[index].stream = null
		_ends[index] = -1.0
	_cooldowns.clear()

## AudioServer frees stopped streams after a mixer tick and main-thread cleanup.
## Weak references observe that lifecycle without keeping any playback alive.
func pending_playback_count() -> int:
	for index: int in range(_playback_refs.size() - 1, -1, -1):
		if _playback_refs[index].get_ref() == null:
			_playback_refs.remove_at(index)
	return _playback_refs.size()

## Test/application teardown may await this before immediately quitting Godot.
## Ordinary pause/room changes call stop_all synchronously; they never wait.
func wait_for_cleanup(timeout_seconds: float = 2.0) -> bool:
	stop_all()
	if not is_inside_tree():
		return pending_playback_count() == 0
	var tree: SceneTree = get_tree()
	var deadline: int = Time.get_ticks_msec() + roundi(maxf(0.0, timeout_seconds) * 1000.0)
	while pending_playback_count() > 0:
		if Time.get_ticks_msec() >= deadline:
			return false
		await tree.process_frame
	return true

func active_voice_count() -> int:
	var count: int = 0
	for ending: float in _ends:
		if ending >= 0.0:
			count += 1
	return count

## Called by _process; explicit delta also permits deterministic silent tests.
func advance(delta: float) -> void:
	pending_playback_count()
	if not is_inside_tree() or get_tree().paused:
		stop_all()
		return
	_refresh_settings()
	_clock += maxf(0.0, delta) if is_finite(delta) else 0.0
	for index: int in _players.size():
		# Real WAVs run on the mixer clock: slow motion must not cut their tails.
		# Silent scheduling has no playback/finished signal, so uses game delta.
		if not audible and _ends[index] >= 0.0 and _ends[index] <= _clock:
			_players[index].stop()
			_players[index].stream = null
			_ends[index] = -1.0

func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for index: int in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "CombatVoice%d" % index
		voice.bus = &"Master"
		voice.max_polyphony = 1
		voice.finished.connect(_on_voice_finished.bind(index))
		add_child(voice)
		_players.append(voice)
		_ends.append(-1.0)

func _refresh_settings() -> void:
	# The current settings UI has no volume control. These optional normalized
	# values are independent of reduced_fx and will work if controls are added.
	var settings: Dictionary = {}
	var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if game != null:
		settings = game.profile.get("settings", {})
	_muted = bool(settings.get("muted", false)) or bool(settings.get("sfx_muted", false))
	_gain = _volume(settings.get("master_volume", 1.0)) * _volume(settings.get("sfx_volume", 0.85))
	if _muted or _gain <= 0.0:
		stop_all()
	var decibels: float = linear_to_db(maxf(0.000001, VOICE_GAIN * _gain))
	for voice: AudioStreamPlayer in _players:
		voice.volume_db = decibels

func _volume(value: Variant) -> float:
	if not value is float and not value is int:
		return 0.0
	return clampf(float(value), 0.0, 1.0) if is_finite(float(value)) else 0.0

func _request(hero_id: String, cue: String, group: String, interval: float) -> bool:
	if not is_inside_tree() or get_tree().paused:
		stop_all()
		return false
	_refresh_settings()
	if _muted or _gain <= 0.0 or _clock < float(_cooldowns.get(group, -1.0)):
		rejected_events += 1
		return false
	var stream: AudioStreamWAV = stream_for(hero_id, cue)
	if stream == null:
		return false
	_ensure_players()
	var index: int = _free_voice()
	if index < 0:
		# Do not steal an older voice: abruptly stopping its waveform clicks.
		rejected_events += 1
		return false
	var voice: AudioStreamPlayer = _players[index]
	voice.stream = stream
	voice.volume_db = linear_to_db(VOICE_GAIN * _gain)
	voice.pitch_scale = 1.0
	_ends[index] = _clock + stream.get_length()
	_cooldowns[group] = _clock + interval
	accepted_events += 1
	if audible:
		voice.play()
		if voice.has_stream_playback():
			_playback_refs.append(weakref(voice.get_stream_playback()))
	return true

func _free_voice() -> int:
	for index: int in _ends.size():
		if _ends[index] < 0.0:
			return index
	return -1

func _on_voice_finished(index: int) -> void:
	_players[index].stream = null
	_ends[index] = -1.0

static func prewarm() -> void:
	for hero_id: String in HEROES:
		for cue: String in CUES:
			stream_for(hero_id, cue)
	stream_for("", "hurt")
	stream_for("", "pickup")

static func stream_for(hero_id: String, cue: String) -> AudioStreamWAV:
	if cue in ["hurt", "pickup"]:
		hero_id = ""
	elif hero_id not in HEROES or cue not in CUES:
		return null
	var key: String = hero_id + ":" + cue
	if not _streams.has(key):
		_streams[key] = _synthesize(hero_id, cue)
	return _streams[key]

static func _duration(hero_id: String, cue: String) -> float:
	match cue:
		"hurt": return 0.22
		"pickup": return 0.27
		"ultimate": return 0.78
		"secondary": return 0.40
		"f": return 0.36
		"q": return 0.33
		"heavy": return 0.32 if hero_id != "CH03" else 0.39
		"impact": return 0.15 if hero_id == "CH02" else 0.23
		_: return 0.16 if hero_id == "CH02" else 0.26

static func _synthesize(hero_id: String, cue: String) -> AudioStreamWAV:
	var duration: float = _duration(hero_id, cue)
	var size: int = ceili(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(size)
	var random := RandomNumberGenerator.new()
	random.seed = (hero_id + ":" + cue).hash()
	var noise: float = 0.0
	var peak: float = 0.0
	var pitch: float = {"q":0.90,"secondary":0.72,"f":1.20,"ultimate":0.62,"heavy":0.78}.get(cue, 1.0)
	var impact_cue: bool = cue in ["impact", "heavy"]
	var decay: float = 5.5 if cue == "ultimate" else 7.5
	for index: int in size:
		var t: float = float(index) / SAMPLE_RATE
		var u: float = t / duration
		noise = lerpf(noise, random.randf_range(-1.0, 1.0), 0.22)
		var body: float = 0.0
		if cue == "hurt":
			body = 0.72 * sin(_chirp(138.0, 48.0, t, duration)) * exp(-u * 6.0) + noise * 0.45 * exp(-u * 9.0)
		elif cue == "pickup":
			# Three overlapping rising bell notes, each with its own soft attack.
			for note: int in 3:
				var elapsed: float = t - float(note) * 0.057
				if elapsed >= 0.0:
					var hz: float = [660.0, 880.0, 1100.0][note]
					body += sin(TAU * hz * elapsed) * _edge(elapsed, 0.18, 0.003) * exp(-elapsed * 25.0) * 0.32
		elif hero_id == "CH01":
			# Hydraulic body plus inharmonic steel. Pressure noise stays low-pass.
			body = sin(_chirp(108.0 * pitch, 43.0 * pitch, t, duration)) * exp(-u * decay) * 0.85
			body += (sin(TAU * 327.0 * pitch * t) + sin(TAU * 559.0 * pitch * t) * 0.40) * exp(-u * 13.0) * (0.36 if impact_cue else 0.20)
			body += noise * exp(-u * 10.0) * 0.34
			if cue in ["secondary", "ultimate"]:
				body += sin(TAU * 52.0 * t) * exp(-u * 5.5) * 0.28
		elif hero_id == "CH02":
			# Short rail discharge, dry body and two quiet mechanical return ticks.
			body = sin(_chirp(360.0 * pitch, 104.0 * pitch, t, duration)) * exp(-u * 12.0) * 0.58
			body += sin(_chirp(1630.0 * pitch, 620.0 * pitch, t, duration)) * exp(-u * 29.0) * 0.24
			body += noise * exp(-u * 20.0) * 0.57
			if not impact_cue:
				for tick: int in 2:
					var elapsed: float = t - (0.058 + float(tick) * 0.042)
					if elapsed >= 0.0:
						body += sin(TAU * (790.0 + tick * 280.0) * elapsed) * exp(-elapsed * 160.0) * _edge(elapsed, 0.028, 0.0015) * 0.11
		elif hero_id == "CH03":
			# Tuned resonance harmonics above a short capacitor discharge.
			body = sin(_chirp(440.0 * pitch, 330.0 * pitch, t, duration)) * exp(-u * 5.0) * 0.59
			body += sin(TAU * 660.0 * pitch * t) * exp(-u * 6.8) * 0.25
			body += sin(TAU * 994.0 * pitch * t) * exp(-u * 10.0) * 0.11
			body += sin(_chirp(1480.0, 710.0, t, duration)) * exp(-u * 27.0) * (0.18 if impact_cue else 0.10)
			body += noise * exp(-u * 25.0) * 0.07
		# 3 ms onset and 20 ms release eliminate sample-boundary discontinuities.
		var sample_value: float = body * _edge(t, duration - 1.0 / SAMPLE_RATE, 0.003)
		samples[index] = sample_value
		peak = maxf(peak, absf(sample_value))
	var bytes := PackedByteArray()
	bytes.resize(size * 2)
	var gain: float = SAMPLE_PEAK / maxf(peak, 0.0001)
	for index: int in size:
		bytes.encode_s16(index * 2, roundi(samples[index] * gain * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = bytes
	return stream

static func _chirp(start_hz: float, end_hz: float, t: float, duration: float) -> float:
	# Integrate a linear frequency sweep (do not multiply t by changing Hz).
	return TAU * (start_hz * t + (end_hz - start_hz) * t * t / (2.0 * duration))

static func _edge(t: float, duration: float, attack_time: float) -> float:
	if t < 0.0 or t >= duration:
		return 0.0
	var onset: float = clampf(t / attack_time, 0.0, 1.0)
	var release: float = clampf((duration - t) / 0.020, 0.0, 1.0)
	return sin(onset * PI * 0.5) * sin(release * PI * 0.5)
