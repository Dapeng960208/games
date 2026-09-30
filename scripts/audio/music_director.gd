class_name MusicDirector
extends Node
## Four original sixteen-bar arrangements; one persistent owner, two voices only.
## UI open/close and repeated context requests never create extra playback nodes.
## Music is sample-looped; combat SFX keep their own bounded, higher-priority pool.

const CONTEXTS: Array[String] = ["camp", "explore", "combat", "boss"]
const MUSIC_GAIN: float = 0.18
const CROSSFADE_SECONDS: float = 1.25
const PAUSED_GAIN: float = 0.22
const IMPACT_ATTACK: float = 0.008
const LIGHT_IMPACT_GAIN: float = 0.708 # -3 dB, enough room for short gun contacts.
const HEAVY_IMPACT_GAIN: float = 0.596 # -4.5 dB; never multiply crowd impacts.
const TRACK_DIRECTORY: String = "res://assets/music/"
static var _streams: Dictionary = {}

@export var audible: bool = true:
	set(value):
		if audible == value:
			return
		audible = value
		for voice: AudioStreamPlayer in _players:
			if value and voice.stream != null:
				voice.play()
				if voice.has_stream_playback():
					_playback_refs.append(weakref(voice.get_stream_playback()))
			elif not value:
				voice.stop()

var current_context: String = ""
var desired_context: String = ""
var transition_count: int = 0
var _game: Node
var _players: Array[AudioStreamPlayer] = []
var _weights: Array[float] = [0.0, 0.0]
var _from_weights: Array[float] = [0.0, 0.0]
var _active: int = -1
var _fade_elapsed: float = CROSSFADE_SECONDS
var _master: float = 1.0
var _music: float = 0.55
var _sfx: float = 0.85
var _muted: bool = false
var _pause_gain: float = 1.0
var _playback_refs: Array[WeakRef] = []
var _light_impact_age: float = 1.0
var _heavy_impact_age: float = 1.0
var _light_impact_start: float = 1.0
var _heavy_impact_start: float = 1.0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_ensure_players()

func configure(game: Node) -> void:
	if is_instance_valid(_game) and _game.has_signal("changed") and _game.is_connected("changed", _read_settings):
		_game.disconnect("changed", _read_settings)
	_game = game
	_ensure_players()
	if is_instance_valid(_game) and _game.has_signal("changed"):
		_game.connect("changed", _read_settings)
	_read_settings()

func set_context(context: String) -> void:
	if context not in CONTEXTS or desired_context == context:
		return
	desired_context = context
	if context == "camp": _clear_impact_duck()
	_ensure_players()
	# Finish the current crossfade before starting the latest queued request.
	# This bounds concurrent streams even during rapid room/UI state changes.
	if not is_transitioning():
		_begin_transition(context)

## Values are normalized [0,1]. Caller persists all three in profile.settings;
## CombatAudio reads master_volume/sfx_volume directly, so it shares this mix.
func set_mix(master: float, music: float, sfx: float) -> void:
	_master = _volume(master)
	_music = _volume(music)
	_sfx = _volume(sfx)
	_apply_volumes()

func _read_settings() -> void:
	var settings: Dictionary = {}
	if is_instance_valid(_game):
		var profile: Variant = _game.get("profile")
		if profile is Dictionary:
			settings = profile.get("settings", {})
	_muted = bool(settings.get("muted", false)) or bool(settings.get("music_muted", false))
	set_mix(_volume(settings.get("master_volume", 1.0)), _volume(settings.get("music_volume", 0.55)), _volume(settings.get("sfx_volume", 0.85)))

func _process(delta: float) -> void:
	advance(delta)

## Called only for an accepted contact voice, never a swing or UI sound.
func notify_impact(heavy: bool = false) -> void:
	if not is_inside_tree() or get_tree().paused or _muted or _sfx <= 0.0 or _master <= 0.0 or desired_context == "camp":
		return
	# Two independent envelopes let a heavy hit expire even if lighter hits
	# continue. Retrigger from the current gain, without an upward volume jump.
	if heavy:
		_heavy_impact_start = _impact_envelope(_heavy_impact_age, _heavy_impact_start, true)
		_heavy_impact_age = 0.0
	else:
		_light_impact_start = _impact_envelope(_light_impact_age, _light_impact_start, false)
		_light_impact_age = 0.0

func impact_duck_gain() -> float:
	return minf(_impact_envelope(_light_impact_age, _light_impact_start, false), _impact_envelope(_heavy_impact_age, _heavy_impact_start, true))

func _impact_envelope(age: float, start: float, heavy: bool) -> float:
	var depth: float = HEAVY_IMPACT_GAIN if heavy else LIGHT_IMPACT_GAIN
	var hold: float = 0.075 if heavy else 0.055
	var release: float = 0.18 if heavy else 0.16
	if age < IMPACT_ATTACK:
		return lerpf(start, depth, clampf(age / IMPACT_ATTACK, 0.0, 1.0))
	if age < IMPACT_ATTACK + hold: return depth
	var recovery: float = clampf((age - IMPACT_ATTACK - hold) / release, 0.0, 1.0)
	return lerpf(depth, 1.0, recovery * recovery * (3.0 - 2.0 * recovery))

func _clear_impact_duck() -> void:
	_light_impact_age = 1.0
	_heavy_impact_age = 1.0
	_light_impact_start = 1.0
	_heavy_impact_start = 1.0

func advance(delta: float) -> void:
	var elapsed: float = maxf(0.0, delta) if is_finite(delta) else 0.0
	# Keep one loop moving through pause. UI repeatedly opening cannot stack it.
	var paused: bool = is_inside_tree() and get_tree().paused
	if paused:
		_clear_impact_duck()
	else:
		_light_impact_age = minf(1.0, _light_impact_age + elapsed)
		_heavy_impact_age = minf(1.0, _heavy_impact_age + elapsed)
	_pause_gain = move_toward(_pause_gain, PAUSED_GAIN if paused else 1.0, elapsed * 2.6)
	if is_transitioning():
		_fade_elapsed = minf(CROSSFADE_SECONDS, _fade_elapsed + elapsed)
		var ratio: float = _fade_elapsed / CROSSFADE_SECONDS
		var eased: float = ratio * ratio * (3.0 - 2.0 * ratio)
		for index: int in _weights.size():
			_weights[index] = lerpf(_from_weights[index], 1.0 if index == _active else 0.0, eased)
		if not is_transitioning():
			for index: int in _players.size():
				if index != _active:
					_players[index].stop()
					_players[index].stream = null
			if desired_context != current_context:
				_begin_transition(desired_context)
	_apply_volumes()
	_prune_playbacks()

func is_transitioning() -> bool:
	return _fade_elapsed < CROSSFADE_SECONDS

func active_stream_count() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in _players:
		if voice.stream != null:
			count += 1
	return count

func effective_music_gain() -> float:
	return 0.0 if _muted else MUSIC_GAIN * _master * _music * _pause_gain * impact_duck_gain()

func stop_all() -> void:
	_clear_impact_duck()
	for voice: AudioStreamPlayer in _players:
		voice.stop()
		voice.stream = null
	_weights = [0.0, 0.0]
	_from_weights = [0.0, 0.0]
	_active = -1
	_fade_elapsed = CROSSFADE_SECONDS
	current_context = ""
	desired_context = ""

func _exit_tree() -> void:
	stop_all()
	if is_instance_valid(_game) and _game.has_signal("changed") and _game.is_connected("changed", _read_settings):
		_game.disconnect("changed", _read_settings)

func wait_for_cleanup(timeout_seconds: float = 2.0) -> bool:
	stop_all()
	var deadline: int = Time.get_ticks_msec() + roundi(maxf(0.0, timeout_seconds) * 1000.0)
	while _prune_playbacks() > 0:
		if not is_inside_tree() or Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().process_frame
	return true

func _prune_playbacks() -> int:
	for index: int in range(_playback_refs.size() - 1, -1, -1):
		if _playback_refs[index].get_ref() == null:
			_playback_refs.remove_at(index)
	return _playback_refs.size()

func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for index: int in 2:
		var voice := AudioStreamPlayer.new()
		voice.name = "MusicDeck%d" % index
		voice.bus = &"Master"
		voice.max_polyphony = 1
		voice.volume_db = -80.0
		add_child(voice)
		_players.append(voice)

func _begin_transition(context: String) -> void:
	var stream: AudioStreamWAV = stream_for(context)
	if stream == null:
		return
	_active = 0 if _active < 0 else 1 - _active
	var voice: AudioStreamPlayer = _players[_active]
	voice.stream = stream
	voice.volume_db = -80.0
	_from_weights = _weights.duplicate()
	_fade_elapsed = 0.0
	current_context = context
	transition_count += 1
	if audible:
		voice.play()
		if voice.has_stream_playback():
			_playback_refs.append(weakref(voice.get_stream_playback()))

func _apply_volumes() -> void:
	var gain: float = effective_music_gain()
	for index: int in _players.size():
		# Complementary amplitude fades keep the combined peak budget constant.
		_players[index].volume_db = linear_to_db(maxf(0.000001, gain * _weights[index]))

static func _volume(value: Variant) -> float:
	if not value is float and not value is int:
		return 0.0
	return clampf(float(value), 0.0, 1.0) if is_finite(float(value)) else 0.0

static func stream_for(context: String) -> AudioStreamWAV:
	if context not in CONTEXTS:
		return null
	if not _streams.has(context):
		# The checked-in WAV import settings explicitly disable compression so
		# shipped samples preserve the measured PCM and exact loop endpoints.
		# Source loading also allows isolated tests before an editor import.
		var path: String = TRACK_DIRECTORY + context + ".wav"
		var stream: AudioStreamWAV
		if FileAccess.file_exists(path + ".import") or not FileAccess.file_exists(path):
			stream = load(path) as AudioStreamWAV
		else:
			stream = AudioStreamWAV.load_from_file(path)
		if stream == null:
			push_error("Missing original score: " + context)
			return null
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# Loop positions are decoded sample frames, never compressed byte counts.
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
		_streams[context] = stream
	return _streams[context]
