class_name CombatAudio
extends Node
## Original procedural Foley. No recordings or external assets.
## One room owns this node. Samples are cached across rooms; players are local.

signal cue_played(cue: String)

const Foley = preload("res://scripts/audio/impact_synth.gd")
const ShieldFoley = preload("res://scripts/audio/shield_synth.gd")
const SAMPLE_RATE: int = 24000
const MAX_VOICES: int = 8
const SAMPLE_PEAK: float = 0.74
# Even eight perfectly correlated peaks remain below full scale on our bus.
const VOICE_GAIN: float = 0.14
const RESERVED_PLAYER_VOICES: int = 2
const IMPACT_INTERVAL: float = 0.055
const DEFEAT_INTERVAL: float = 0.100
const PASSIVE_INTERVAL: float = 0.100
const PASSIVE_GAIN: float = 0.48
const DEPLOYMENT_INTERVAL: float = 0.100
const DEPLOYMENT_CUES: Array[String] = ["trap_trigger", "node_fire", "field_pulse"]
const DEPLOYMENT_GAINS: Dictionary = {"trap_trigger":0.44, "node_fire":0.32, "field_pulse":0.24}
const RESONANCE_INTERVAL: float = 0.100
const RESONANCE_CUES: Array[String] = ["resonance_1", "resonance_2", "resonance_full"]
# Charge is a sparse player-action confirmation, not continuous machinery.
# Its short ceramic transients must survive the attack/impact mix; batching,
# background reservation and sub-unity gains still keep it behind direct hits.
const RESONANCE_GAINS: Array[float] = [0.70, 0.80, 0.90]
const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const CUES: Array[String] = ["attack", "impact", "heavy", "q", "secondary", "f", "ultimate"]
const PREPARE_CUES: Array[String] = ["prepare_q", "prepare_secondary", "prepare_f", "prepare_ultimate"]
const VARIATIONS: int = Foley.VARIANTS
const MATERIALS: Array[String] = ["stone", "metal", "organic"]
const SHIELD_CUES: Array[String] = ["shield_hit", "shield_break"]

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
var _voice_gains: Array[float] = []
var _clock: float = 0.0
var _cooldowns: Dictionary = {}
var _variation_indices: Dictionary = {}
var _gain: float = 0.85
var _muted: bool = false
var accepted_events: int = 0
var rejected_events: int = 0
var _resonance_pending_level: int = 0
var _resonance_generation: int = 0
var _resonance_last_level: int = 0

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
	return _request(hero_id, "attack", "attack", 0.075 if hero_id == "CH02" else 0.04)

func cast(hero_id: String, slot: String) -> bool:
	if slot not in ["q", "secondary", "f", "ultimate"]:
		return false
	# The finite ability timeline owns cadence/count. A second audio-clock gate
	# can swallow legitimate 60ms Q releases between physics/render clocks.
	return _request(hero_id, slot, "cast", 0.0)

func prepare(hero_id: String, slot: String) -> bool:
	if "prepare_" + slot not in PREPARE_CUES:
		return false
	return _request(hero_id, "prepare_" + slot, "prepare", 0.04)

func impact(hero_id: String, heavy: bool = false, material: String = "stone", passive: bool = false) -> bool:
	if passive:
		return _request(hero_id, "heavy" if heavy else "impact", "passive_impact", PASSIVE_INTERVAL, material, PASSIVE_GAIN)
	# A prior node or light hit must not swallow the player's heavy contact.
	# Permit one stronger layer, then suppress both crowd tiers for this window.
	if heavy:
		var accepted: bool = _request(hero_id, "heavy", "heavy_impact", IMPACT_INTERVAL, material)
		if accepted:
			_cooldowns["impact"] = _clock + IMPACT_INTERVAL
			_cooldowns["passive_impact"] = maxf(float(_cooldowns.get("passive_impact", -1.0)), _clock + IMPACT_INTERVAL)
		return accepted
	var accepted: bool = _request(hero_id, "impact", "impact", IMPACT_INTERVAL, material)
	if accepted:
		_cooldowns["passive_impact"] = maxf(float(_cooldowns.get("passive_impact", -1.0)), _clock + IMPACT_INTERVAL)
	return accepted

## One replacement contact for a shielded packet, never an extra body layer.
## A breakthrough selects only the stronger fracture, even if HP also fell.
func shield_contact(hero_id: String, broken: bool = false, passive: bool = false) -> bool:
	var cue: String = "shield_break" if broken else "shield_hit"
	if passive:
		return _request(hero_id,cue,"passive_impact",PASSIVE_INTERVAL,"stone",PASSIVE_GAIN)
	var accepted: bool = _request(hero_id,cue,"heavy_impact" if broken else "impact",IMPACT_INTERVAL)
	if accepted:
		if broken: _cooldowns["impact"] = _clock+IMPACT_INTERVAL
		_cooldowns["passive_impact"] = maxf(float(_cooldowns.get("passive_impact",-1.0)),_clock+IMPACT_INTERVAL)
	return accepted

func hurt() -> bool:
	return _request("", "hurt", "hurt", 0.12)

func defeat(material: String = "stone") -> bool:
	# Kill debris shares the six background slots; player releases and heavy
	# contacts retain both reserves and their independent confirmation cooldown.
	return _request("", "defeat", "defeat", DEFEAT_INTERVAL, material)

func pickup() -> bool:
	return _request("", "pickup", "pickup", 0.08)

func deployment(cue: String) -> bool:
	if cue not in DEPLOYMENT_CUES:
		return false
	# Background machinery keeps one independent clustering gate per action;
	# cue names stay distinct from impact/heavy so they do not duck the music.
	return _request("", cue, cue, DEPLOYMENT_INTERVAL, "stone", float(DEPLOYMENT_GAINS[cue]))

## True means admitted to this synchronous event batch, not a playing voice.
## The one deferred flush picks its highest level; cue_played confirms actual
## allocation. Refused/expired batches are discarded, never queued for retry.
func resonance_charge(level: int) -> bool:
	if level < 1 or level > 3:
		return false
	if not is_inside_tree() or get_tree().paused:
		stop_all()
		return false
	_refresh_settings()
	if _muted or _gain <= 0.0 or not _resonance_gate_open(level):
		rejected_events += 1
		return false
	if _resonance_pending_level > 0:
		_resonance_pending_level = maxi(_resonance_pending_level, level)
		return true
	_resonance_pending_level = level
	_resonance_generation += 1
	call_deferred("_flush_resonance_charge", _resonance_generation)
	return true

func _resonance_gate_open(level: int) -> bool:
	return _clock >= float(_cooldowns.get("resonance_charge", -1.0)) or (level == 3 and _resonance_last_level < 3)

func _flush_resonance_charge(generation: int) -> void:
	# An old callback must not clear a newer batch admitted after stop/unmute.
	if generation != _resonance_generation or _resonance_pending_level == 0:
		return
	var level: int = _resonance_pending_level
	_resonance_pending_level = 0
	if not _resonance_gate_open(level):
		rejected_events += 1
		return
	# Only the full cue may bypass a preceding partial confirmation's gate.
	# Both groups remain background events, using at most the existing six slots.
	var group: String = "resonance_full" if _clock < float(_cooldowns.get("resonance_charge", -1.0)) else "resonance_charge"
	var accepted: bool = _request("", RESONANCE_CUES[level-1], group, RESONANCE_INTERVAL, "stone", RESONANCE_GAINS[level-1])
	# A synchronous cue_played listener can stop playback or change the room.
	if accepted and generation == _resonance_generation:
		_resonance_last_level = level
		_cooldowns["resonance_charge"] = _clock + RESONANCE_INTERVAL

func stop_all() -> void:
	for index: int in _players.size():
		_players[index].stop()
		_players[index].stream = null
		_ends[index] = -1.0
		_voice_gains[index] = 1.0
	_cooldowns.clear()
	_resonance_generation += 1
	_resonance_pending_level = 0
	_resonance_last_level = 0

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
			_voice_gains[index] = 1.0

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
		_voice_gains.append(1.0)

func _refresh_settings() -> void:
	# Normalized profile values are independent of reduced visual effects.
	var settings: Dictionary = {}
	var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	if game != null:
		settings = game.profile.get("settings", {})
	_muted = bool(settings.get("muted", false)) or bool(settings.get("sfx_muted", false))
	_gain = _volume(settings.get("master_volume", 1.0)) * _volume(settings.get("sfx_volume", 0.85))
	if _muted or _gain <= 0.0:
		stop_all()
	for index: int in _players.size():
		_players[index].volume_db = linear_to_db(maxf(0.000001, VOICE_GAIN * _gain * _voice_gains[index]))

func _volume(value: Variant) -> float:
	if not value is float and not value is int:
		return 0.0
	return clampf(float(value), 0.0, 1.0) if is_finite(float(value)) else 0.0

func _request(hero_id: String, cue: String, group: String, interval: float, material: String = "stone", event_gain: float = 1.0) -> bool:
	if not is_inside_tree() or get_tree().paused:
		stop_all()
		return false
	_refresh_settings()
	if _muted or _gain <= 0.0 or _clock < float(_cooldowns.get(group, -1.0)):
		rejected_events += 1
		return false
	var variation_key: String = hero_id + ":" + cue
	if cue == "defeat":
		variation_key = "defeat:" + (material if material in MATERIALS else "stone")
	var variation: int = int(_variation_indices.get(variation_key, 0)) % VARIATIONS
	var stream: AudioStreamWAV = stream_for(hero_id, cue, variation, material)
	if stream == null:
		return false
	_ensure_players()
	# Passive hits and loot leave two slots for player actions and direct contact.
	var player_priority: bool = group in ["attack", "cast", "hurt", "impact", "heavy_impact"]
	var index: int = _free_voice(player_priority)
	if index < 0:
		# Do not steal an older voice: abruptly stopping its waveform clicks.
		rejected_events += 1
		return false
	var voice: AudioStreamPlayer = _players[index]
	voice.stream = stream
	_voice_gains[index] = _volume(event_gain)
	voice.volume_db = linear_to_db(maxf(0.000001, VOICE_GAIN * _gain * _voice_gains[index]))
	# Every accepted cue advances its own four independently excited Foley takes.
	# Rejected crowd events neither consume a take nor change the next player cue.
	voice.pitch_scale = 1.0
	_variation_indices[variation_key] = (variation + 1) % VARIATIONS
	_ends[index] = _clock + stream.get_length()
	_cooldowns[group] = _clock + interval
	accepted_events += 1
	if audible:
		voice.play()
		if voice.has_stream_playback():
			_playback_refs.append(weakref(voice.get_stream_playback()))
	cue_played.emit("passive_impact" if group == "passive_impact" else cue)
	return true

func _free_voice(player_priority: bool = true) -> int:
	if not player_priority and active_voice_count() >= MAX_VOICES - RESERVED_PLAYER_VOICES:
		return -1
	for index: int in _ends.size():
		if _ends[index] < 0.0:
			return index
	return -1

func _on_voice_finished(index: int) -> void:
	_players[index].stream = null
	_ends[index] = -1.0
	_voice_gains[index] = 1.0

static func prewarm() -> void:
	for hero_id: String in HEROES:
		for cue: String in CUES + PREPARE_CUES + SHIELD_CUES:
			for variation: int in VARIATIONS:
				for material: String in (MATERIALS if cue in ["impact", "heavy"] else ["stone"]):
					stream_for(hero_id, cue, variation, material)
	for variation: int in VARIATIONS:
		stream_for("", "hurt", variation)
		stream_for("", "pickup", variation)
		for cue: String in DEPLOYMENT_CUES + RESONANCE_CUES:
			stream_for("", cue, variation)
		for material: String in MATERIALS:
			stream_for("", "defeat", variation, material)

static func stream_for(hero_id: String, cue: String, variation: int = 0, material: String = "stone") -> AudioStreamWAV:
	if cue in ["hurt", "pickup", "defeat"] or cue in DEPLOYMENT_CUES or cue in RESONANCE_CUES:
		hero_id = ""
	elif hero_id not in HEROES or (cue not in CUES and cue not in PREPARE_CUES and cue not in SHIELD_CUES):
		return null
	# Normalize public inputs before constructing a key: the cache is strictly bounded.
	variation = posmod(variation, VARIATIONS)
	if cue not in ["impact", "heavy", "defeat"] or material not in MATERIALS:
		material = "stone"
	var key: String = "%s:%s:%d:%s" % [hero_id, cue, variation, material]
	if not _streams.has(key):
		_streams[key] = ShieldFoley.synthesize(hero_id,cue == "shield_break",variation) if cue in SHIELD_CUES else Foley.synthesize(hero_id, cue, variation, material)
	return _streams[key]
