extends SceneTree
## Regression: a real confirmed heavy contact must remain audible after a light
## contact and under the ordinary six-voice crowd budget. Production PCM/pool,
## real damage/room feedback, silent deterministic scheduler; no listening claim.

var game: Node
var room: Node2D
var target: Node2D
var checks: int = 0
var failures: int = 0
var serial: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failures += 1
		push_error("IMPACT AUDIO PRIORITY: " + description)

func _run() -> void:
	game = root.get_node_or_null("Game")
	if game == null or not str(game.profile_path).contains("test_impact_audio_priority"):
		push_error("Requires isolated test_impact_audio_priority profile")
		quit(2)
		return
	check(game.new_profile() and game.select_hero("CH03") and game.start_run(), "isolated mage production run starts")
	game.profile.settings.merge({"muted":false,"sfx_muted":false,"master_volume":1.0,"sfx_volume":0.85},true)
	game.run.stats["crit_chance"] = 0.0
	game.run.stats["true_damage_bonus"] = 0.0
	game.run.relics.clear()
	room = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn")).instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(430,350)
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	room.combat_audio.stop_all()
	target = room.spawn_enemy(Vector2(490,350),"M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.state = &"chase"
	_test_uncontested_heavy()
	_test_node_before_heavy()
	_test_heavy_before_crowd()
	_test_six_voice_pressure()
	_test_light_crowd_bound()
	await room.combat_audio.wait_for_cleanup()
	room.free()
	print("IMPACT AUDIO PRIORITY: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _reset_audio() -> void:
	room.combat_audio.stop_all()
	room.combat_audio.advance(1.0)
	room.elapsed += 1.0
	room.combat_audio._variation_indices.clear()

func _hit(source: StringName, derived: bool = false) -> void:
	serial += 1
	var context := {"attack_id":"audio-priority:"+str(serial),"root_event_id":"audio-priority:"+str(serial),"damage_type":"magic","attacker_stats":game.run.stats,"equipment_eligible":false}
	if derived:
		room.resolve_derived_hit(target,20.0,source,Vector2.RIGHT,context)
	else:
		room.resolve_direct_hit(target,80.0,source,"",0.0,Vector2.RIGHT,context)

func _playing(cue: String) -> bool:
	for voice: AudioStreamPlayer in room.combat_audio._players:
		for variation: int in room.combat_audio.VARIATIONS:
			if voice.stream == room.combat_audio.stream_for("CH03",cue,variation,"metal"):
				return true
	return false

func _test_uncontested_heavy() -> void:
	_reset_audio()
	var hp: float = target.health.current
	_hit(&"f")
	check(target.health.current < hp and _playing("heavy"), "uncontested real mage F damage schedules its heavy material PCM")
	check(room.combat_audio.active_voice_count() == 1, "uncontested confirmation occupies one real voice")

func _test_node_before_heavy() -> void:
	_reset_audio()
	var before: int = room.player.get_node("HeroFeedback").impact_events
	var hp: float = target.health.current
	_hit(&"node",true)
	var after_node: float = target.health.current
	check(after_node < hp and _playing("impact"), "real passive node damage schedules light contact first")
	_hit(&"f")
	check(target.health.current < after_node and room.player.get_node("HeroFeedback").impact_events == before+2, "node and F both damage and confirm through real room callbacks")
	print("PRIORITY SAME WINDOW voices=",room.combat_audio.active_voice_count()," heavy_pcm=",_playing("heavy")," total_rejected=",room.combat_audio.rejected_events)
	check(_playing("heavy"), "confirmed F heavy PCM survives a node hit earlier in the same 55ms window")
	check(room.combat_audio.active_voice_count() <= room.combat_audio.MAX_VOICES, "same-window heavy handling stays within eight-voice cap")

func _test_six_voice_pressure() -> void:
	_reset_audio()
	var audio: Node = room.combat_audio
	var prime_ok: bool = audio.attack("CH03") and audio.cast("CH03","ultimate") and audio.hurt() and audio.pickup()
	_hit(&"node",true)
	# Passive contacts have their own 100 ms gate, separate from 55 ms direct
	# contacts. Cross it to establish the six live voices this fixture promises.
	audio.advance(audio.PASSIVE_INTERVAL + 0.001)
	room.elapsed += audio.PASSIVE_INTERVAL + 0.001
	_hit(&"node",true)
	check(prime_ok and audio.active_voice_count() == 6, "real public cues and two passive contacts occupy six voices")
	audio.advance(0.056)
	room.elapsed += 0.056
	check(audio.active_voice_count() == 6, "six voices remain active after the impact debounce expires")
	var hp: float = target.health.current
	_hit(&"f")
	check(target.health.current < hp, "heavy F still deals real damage under audio pressure")
	print("PRIORITY POOL voices=",audio.active_voice_count()," free=",audio.MAX_VOICES-audio.active_voice_count()," heavy_pcm=",_playing("heavy")," total_rejected=",audio.rejected_events)
	check(_playing("heavy"), "confirmed heavy PCM can use player-reserved capacity under six-voice pressure")
	check(audio.active_voice_count() <= audio.MAX_VOICES, "priority heavy does not exceed eight-voice cap")

func _test_heavy_before_crowd() -> void:
	_reset_audio()
	var before: int = room.combat_audio.accepted_events
	_hit(&"f")
	var voice: AudioStreamPlayer = room.combat_audio._players[0]
	var original_stream: AudioStreamWAV = voice.stream
	for index in 20:
		_hit(&"node" if index % 2 == 0 else &"f",index % 2 == 0)
	check(room.combat_audio.accepted_events-before == 1 and room.combat_audio.active_voice_count() == 1, "heavy-first mixed crowd emits only one contact cue")
	check(voice.stream == original_stream and _playing("heavy"), "later crowd contacts never cut or replace the active heavy waveform")

func _test_light_crowd_bound() -> void:
	_reset_audio()
	var before: int = room.combat_audio.accepted_events
	for _index in 20: _hit(&"node",true)
	check(room.combat_audio.accepted_events-before == 1 and room.combat_audio.active_voice_count() == 1, "twenty ordinary crowd contacts still aggregate to one light cue")
