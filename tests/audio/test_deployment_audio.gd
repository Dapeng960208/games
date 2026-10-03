extends SceneTree
## Actual deployment lifecycles, generated PCM, bounded scheduling and teardown.
## All profiles are isolated; the real device path is explicitly bus-muted.
const Audio = preload("res://scripts/presentation/combat/combat_audio.gd")
const Music = preload("res://scripts/infrastructure/audio/music_director.gd")
const Resolver = preload("res://scripts/domain/combat/stat_resolver.gd")
var game: Node
var room: Node2D
var room_scene: PackedScene
var events: Array[String] = []
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DEPLOYMENT AUDIO FAIL: " + label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_deployment_audio"):
		push_error("Refusing non-test deployment audio profile")
		quit(2)
		return
	for action: String in ["move_left", "move_right", "move_up", "move_down", "attack", "dash", "interact", "skill_q", "skill_secondary", "skill_f", "skill_ultimate"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	check(game.new_profile() and game.start_run(), "isolated actual run starts")
	if game.run == null:
		quit(1)
		return
	room_scene = load(AssetCatalog.resolve("res://scenes/gameplay/world/room.tscn"))
	_test_pcm_and_cache()
	_test_trap()
	_test_node()
	_test_field()
	_test_retirement()
	_test_pool_and_settings()
	await _test_real_playback()
	check(await room.combat_audio.wait_for_cleanup(), "all deployment mixer objects released before shutdown")
	room.free()
	print("DEPLOYMENT AUDIO: %d checks, %d failures (real lifecycle/PCM/muted device; no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func fixture(hero: String = "CH03") -> void:
	if is_instance_valid(room): room.free()
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = Resolver.resolve(hero, 8, {}, {})
	game.run.stats["crit_chance"] = 0.0
	game.run.max_hp = float(game.run.stats.max_hp)
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	game.profile.settings.merge({"muted":false, "sfx_muted":false, "master_volume":1.0, "sfx_volume":1.0, "reduced_fx":false}, true)
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.release_gate = false
	room.input_blocked = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.combat_audio.audible = false
	room.combat_audio.set_process(false)
	room.player.position = Vector2(430, 350)
	room.player.aim_direction = Vector2.RIGHT
	events.clear()
	room.combat_audio.cue_played.connect(func(cue: String) -> void: events.append(cue))

func _deploy(kind: String, at: Vector2 = Vector2(480, 350), lifetime: float = 5.0) -> Node2D:
	return room.add_deployment(kind, at, {"damage":20.0, "power":20.0, "radius":120.0, "lifetime":lifetime, "owner_player":room.player, "damage_type":"physical" if kind == "trap" else "magic", "attacker_stats":game.run.stats.duplicate(true)})

func _dummy(at: Vector2 = Vector2(550, 350)) -> Node2D:
	var target: Node2D = room.spawn_enemy(at)
	target.health.reset(10000.0)
	target.state = &"chase"
	return target

func _step(deployment: Node2D, delta: float) -> void:
	room.combat_audio.advance(delta)
	deployment.advance(delta)

func _count(cue: String) -> int:
	return events.count(cue)

func _deployment_count() -> int:
	var total: int = 0
	for cue: String in Audio.DEPLOYMENT_CUES: total += _count(cue)
	return total

func _test_trap() -> void:
	fixture("CH02")
	var trap: Node2D = _deploy("trap")
	var targets: Array[Node2D] = [_dummy(Vector2(535, 350)), _dummy(Vector2(525, 370)), _dummy(Vector2(540, 330))]
	check(_deployment_count() == 0, "trap creation does not duplicate existing cast sound")
	_step(trap, 0.349)
	check(_count("trap_trigger") == 0 and targets[0].health.current == 10000.0, "trap cannot sound or hit before unfolding")
	_step(trap, 0.001)
	check(_count("trap_trigger") == 1 and not trap.is_alive(), "occupied trap sounds exactly once at actual activation")
	for target: Node2D in targets:
		check(target.health.current < 10000.0, "one trap cue accompanies real damage to each of three targets")
	_step(trap, 1.0)
	check(_count("trap_trigger") == 1, "retired trap cannot replay activation")
	fixture("CH02")
	trap = _deploy("trap")
	_step(trap, 0.5)
	check(trap.is_alive() and _count("trap_trigger") == 0, "armed trap without targets remains silent")
	_dummy()
	room.obstructions.assign([Rect2(510, 300, 20, 100)])
	check(not room.has_line_of_sight(trap.position, Vector2(550, 350)), "fixture uses actual blocking geometry")
	_step(trap, 0.2)
	check(trap.is_alive() and _count("trap_trigger") == 0, "occluded targets cannot trigger trap audio")
	room.obstructions.clear()
	_step(trap, 0.01)
	check(_count("trap_trigger") == 1, "exposed target triggers trap without changing gameplay timing")
	fixture("CH02")
	trap = _deploy("trap")
	_dummy()
	for index: int in 6: check(room.combat_audio._request("CH01", "heavy", "passive_impact", 0.0), "fill six background tracks for trap rejection")
	trap.advance(0.35)
	check(_count("trap_trigger") == 0 and not trap.is_alive(), "full background budget rejects sound while actual trap still triggers")
	_step(trap, 1.0)
	check(_count("trap_trigger") == 0, "rejected spent-trap audio is never queued for later")

func _test_node() -> void:
	fixture()
	var node: Node2D = _deploy("node")
	_step(node, 0.35)
	check(node.charge_node(1) and node.charge_node(2), "actual node can receive both partial and full charge")
	check(_count("node_fire") == 0, "visual charge pulses do not masquerade as node shooting")
	_step(node, 1.2)
	check(_count("node_fire") == 0 and room.projectiles.get_child_count() == 0, "node without a visible target never fires or sounds")
	_dummy()
	room.obstructions.assign([Rect2(510, 300, 20, 100)])
	_step(node, 1.2)
	check(_count("node_fire") == 0 and room.projectiles.get_child_count() == 0, "node cannot fire through actual LOS obstruction")
	room.obstructions.clear()
	_step(node, 1.2)
	check(_count("node_fire") == 1 and room.projectiles.get_child_count() == 1, "node audio occurs only after actual bolt is successfully spawned")
	check(room.projectiles.get_child(0).source == &"node", "sounded projectile has production node source")
	fixture()
	node = _deploy("node", Vector2(480, 350), 10.0)
	_dummy()
	for index: int in 100:
		room.spawn_projectile(Vector2(300, 300), Vector2.LEFT, 1.0, &"skill")
	check(room.projectiles.get_child_count() == 100, "real projectile cap is filled")
	_step(node, 1.55)
	check(_count("node_fire") == 0 and room.projectiles.get_child_count() == 100, "actual projectile-cap failure produces no node firing sound")
	room.projectiles.get_child(0).free()
	_step(node, 1.19)
	check(_count("node_fire") == 0 and room.projectiles.get_child_count() == 99, "failed node event is not retried after capacity returns")
	_step(node, 0.01)
	check(_count("node_fire") == 1 and room.projectiles.get_child_count() == 100, "next authored node attack fires and sounds normally")
	fixture()
	node = _deploy("node", Vector2(480, 350), 10.0)
	_dummy()
	_step(node, 5.15)
	check(room.projectiles.get_child_count() == 4 and _count("node_fire") == 1, "node catch-up keeps four real bolts but coalesces same-frame audio")
	room.combat_audio.advance(0.2)
	node.advance(0.0)
	check(_count("node_fire") == 1, "cluster-rejected node sounds do not replay after cooldown")

func _test_field() -> void:
	fixture()
	var field: Node2D = _deploy("field")
	var target: Node2D = _dummy()
	check(_count("field_pulse") == 0, "field creation does not duplicate existing ultimate sound")
	_step(field, 0.999)
	check(_count("field_pulse") == 0 and target.health.current == 10000.0, "field has no premature sound or fractional tick")
	_step(field, 0.001)
	var tick_damage: float = 10000.0 - target.health.current
	check(_count("field_pulse") == 1 and tick_damage > 0.0, "field sound occurs at actual first one-second damage pulse")
	_step(field, 4.0)
	check(_count("field_pulse") == 2, "four catch-up field ticks produce one additional audio pulse")
	check(is_equal_approx(10000.0 - target.health.current, tick_damage * 5.0), "audio consolidation preserves all five actual damage ticks including expiry")
	check(not field.is_alive(), "field still retires at existing lifetime")
	_step(field, 2.0)
	check(_count("field_pulse") == 2, "expired field never replays skipped audio")
	fixture()
	field = _deploy("field")
	_step(field, 1.0)
	check(_count("field_pulse") == 1 and field.pulse > 0.0, "visible empty-field pulse has its light energy sound")
	fixture()
	field = _deploy("field")
	_dummy()
	for index: int in 6: check(room.combat_audio._request("CH01", "heavy", "passive_impact", 0.0), "fill background pool for field rejection")
	field.advance(1.0)
	check(_count("field_pulse") == 0, "field pulse yields to an already full background pool")
	room.combat_audio.advance(0.5)
	field.advance(0.0)
	check(_count("field_pulse") == 0, "field audio rejection is not retried")
	_step(field, 1.0)
	check(_count("field_pulse") == 1, "future real field pulse can sound after pool recovers")

func _test_retirement() -> void:
	fixture()
	var node: Node2D = _deploy("node")
	_step(node, 0.35)
	check(node.detonate(), "actual node detonation still works")
	check(_deployment_count() == 0, "node detonation adds no duplicate deployment explosion")
	for kind: String in ["node", "trap", "field"]:
		fixture("CH02" if kind == "trap" else "CH03")
		var deployed: Node2D = _deploy(kind)
		deployed.retire()
		_step(deployed, 10.0)
		check(_deployment_count() == 0, kind + " explicit retirement is silent")
	fixture()
	node = _deploy("node")
	var trap: Node2D = _deploy("trap")
	var field: Node2D = _deploy("field")
	check(room.load_room_layout("L02", 0, 41927), "actual room transition succeeds")
	for deployed: Node2D in [node, trap, field]:
		check(not deployed.is_alive(), "transition retires old deployment")
		deployed.advance(10.0)
	check(_deployment_count() == 0, "room transition and stale callbacks create no deployment sound")

func _test_pool_and_settings() -> void:
	fixture()
	var audio: Node = room.combat_audio
	var music: Node = Music.new()
	music.audible = false
	root.add_child(music)
	music.configure(game)
	music.set_context("combat")
	music.advance(1.3)
	var observer: Callable = func(cue: String) -> void:
		if cue in ["impact", "heavy"]: music.notify_impact(cue == "heavy")
	audio.cue_played.connect(observer)
	for cue: String in Audio.DEPLOYMENT_CUES:
		check(audio.deployment(cue), cue + " has independent same-frame clustering group")
		check(not audio.deployment(cue), cue + " rejects same-frame repeat")
	check(_deployment_count() == Audio.DEPLOYMENT_CUES.size() and is_equal_approx(music.impact_duck_gain(), 1.0), "four accepted deployment cues never trigger combat music duck")
	for index: int in Audio.DEPLOYMENT_CUES.size():
		var cue: String = Audio.DEPLOYMENT_CUES[index]
		check(is_equal_approx(db_to_linear(audio.get_child(index).volume_db), Audio.VOICE_GAIN * float(Audio.DEPLOYMENT_GAINS[cue])), cue + " actual player uses low deployment gain")
	# Four simultaneous families plus their second round would exceed the six
	# background slots. Check cadence independently from the reservation limit.
	audio.stop_all()
	for cue: String in Audio.DEPLOYMENT_CUES:
		check(audio.deployment(cue), cue + " starts an independent cadence fixture")
		audio.advance(0.099)
		check(not audio.deployment(cue), cue + " gate remains closed at 99ms")
		audio.advance(0.002)
		check(audio.deployment(cue), cue + " gate opens beyond 100ms")
		audio.stop_all()
	audio.stop_all()
	for index: int in 6:
		check(audio._request("", "field_pulse", "field_pulse", 0.0, "stone", 0.24), "deployment fixtures occupy six actual background tracks")
	var retained: Array[AudioStream] = []
	for voice: AudioStreamPlayer in audio.get_children(): retained.append(voice.stream)
	check(not audio.deployment("node_fire") and audio.active_voice_count() == 6, "deployment cannot consume either player reserve")
	check(audio.attack("CH02") and audio.impact("CH02"), "player action and actual ordinary contact retain two reserved tracks")
	check(audio.active_voice_count() == 8 and not audio.deployment("trap_trigger"), "deployment event obeys total eight-track ceiling")
	for index: int in 6: check(audio.get_child(index).stream == retained[index], "new rejected events never cut existing deployment waveform")
	audio.stop_all()
	# A grenade is the player's delayed release, not passive machinery. Its
	# explosion and one direct hit must survive six occupied background voices.
	for index: int in 6:
		check(audio._request("", "field_pulse", "field_pulse", 0.0, "stone", 0.24), "grenade priority fixture occupies a background voice")
	retained.clear()
	for voice: AudioStreamPlayer in audio._players: retained.append(voice.stream)
	check(audio.deployment("grenade_burst") and audio.active_voice_count() == 7, "real grenade detonation uses the seventh foreground voice behind six background voices")
	check(not audio.deployment("grenade_burst") and audio.active_voice_count() == 7, "foreground admission preserves the grenade's same-frame clustering gate")
	check(audio.impact("CH02", true) and audio.active_voice_count() == 8, "direct heavy contact retains the eighth voice beside grenade detonation")
	audio.advance(0.101)
	check(not audio.deployment("grenade_burst") and audio.active_voice_count() == 8, "grenade with an open clustering gate still respects the full eight-voice cap")
	for index: int in 6: check(audio._players[index].stream == retained[index], "foreground grenade and contact never steal a background waveform")
	audio.stop_all()
	game.profile.settings.reduced_fx = true
	check(audio.deployment("node_fire"), "reduced visual effects retains deployment audio")
	game.profile.settings.merge({"master_volume":0.4, "sfx_volume":0.5}, true)
	audio.advance(0.01)
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db), Audio.VOICE_GAIN * 0.32 * 0.2), "settings refresh preserves deployment attenuation")
	game.profile.settings.sfx_muted = true
	audio.advance(0.01)
	check(audio.active_voice_count() == 0 and not audio.deployment("trap_trigger"), "SFX mute stops and refuses deployment audio")
	game.profile.settings.merge({"master_volume":1.0, "sfx_volume":1.0, "sfx_muted":false}, true)
	check(audio.deployment("field_pulse"), "restored settings permit a fresh field cue")
	paused = true
	audio.advance(0.2)
	check(audio.active_voice_count() == 0 and not audio.deployment("node_fire"), "pause stops and rejects mechanism audio")
	paused = false
	check(audio.deployment("node_fire"), "resume has no stale deployment cooldown")
	audio.stop_all()
	for cue: String in Audio.DEPLOYMENT_CUES:
		var signatures: Dictionary = {}
		var first: AudioStream
		for index: int in 5:
			audio.stop_all()
			check(audio.deployment(cue), cue + " accepts another finite PCM take")
			var stream: AudioStreamWAV = audio.get_child(0).stream
			signatures[hash(stream.data)] = true
			if index == 0: first = stream
			elif index == 4: check(stream == first, cue + " wraps its four-take rotation")
		check(signatures.size() == 4, cue + " runtime cycles four actual waveforms")
	check(not audio.deployment("armed") and not audio.deployment("node_charge"), "unsupported deployment effects cannot create new cache or cue groups")
	audio.cue_played.disconnect(observer)
	music.free()
	audio.stop_all()

func _test_real_playback() -> void:
	var audio: Node = room.combat_audio
	var previous_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	audio.audible = true
	check(audio.deployment("trap_trigger"), "muted actual device accepts production mechanism PCM")
	var voice: AudioStreamPlayer = audio.get_child(0)
	check(voice.playing and voice.has_stream_playback(), "actual mechanism voice creates real mixer playback")
	var playback: WeakRef = weakref(voice.get_stream_playback())
	audio.advance(10.0)
	check(voice.playing, "large game delta never truncates a real mechanism waveform")
	var deadline: int = Time.get_ticks_msec() + 2000
	while (voice.playing or voice.stream != null) and Time.get_ticks_msec() < deadline: await process_frame
	check(not voice.playing and voice.stream == null, "natural mechanism completion releases track")
	check(await audio.wait_for_cleanup() and playback.get_ref() == null, "real mechanism mixer playback is destroyed after completion")
	for index: int in 9:
		check(audio.deployment(Audio.DEPLOYMENT_CUES[index % Audio.DEPLOYMENT_CUES.size()]), "immediate-stop lifecycle creates real mechanism voice")
		audio.stop_all()
	check(await audio.wait_for_cleanup() and audio.pending_playback_count() == 0, "repeated immediate mechanism stops leave no live playback")
	audio.audible = false
	AudioServer.set_bus_mute(0, previous_mute)

func _energy(stream: AudioStreamWAV) -> float:
	var result: float = 0.0
	for index: int in stream.data.size() / 2:
		var sample_value: float = float(stream.data.decode_s16(index * 2)) / 32768.0
		result += sample_value * sample_value / stream.mix_rate
	return result

func _test_pcm_and_cache() -> void:
	Audio.prewarm()
	check(Audio.DEPLOYMENT_CUES == ["trap_trigger", "node_fire", "field_pulse", "grenade_burst"] and Audio._streams.size() == 252, "four deployment action families coexist with the finite 252-stream library including resonance and twenty-four shield streams")
	var all_signatures: Dictionary = {}
	for cue: String in Audio.DEPLOYMENT_CUES:
		var signatures: Dictionary = {}
		for variant: int in 4:
			var stream: AudioStreamWAV = Audio.stream_for("", cue, variant)
			var label: String = cue + "/v" + str(variant)
			check(stream != null and stream.mix_rate == 24000 and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS, label + " has real authored mono PCM")
			check(stream.get_length() >= 0.10 and stream.get_length() <= (0.35 if cue == "grenade_burst" else 0.20), label + " is a short mechanism action")
			var peak: float = 0.0
			var total: float = 0.0
			for index: int in stream.data.size() / 2:
				var value: float = float(stream.data.decode_s16(index * 2)) / 32768.0
				peak = maxf(peak, absf(value))
				total += value
			check(peak > 0.08 and peak <= Audio.SAMPLE_PEAK, label + " preserves audible signal and peak headroom")
			check(absf(total / (stream.data.size() / 2)) < 0.003 and _energy(stream) > 0.00001, label + " has negligible DC and nonzero meaningful energy")
			check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, label + " starts/ends at zero and never loops")
			var hero: String = "CH02" if cue in ["trap_trigger", "grenade_burst"] else "CH03"
			var relative_gain: float = float(Audio.DEPLOYMENT_GAINS[cue])
			if cue == "grenade_burst":
				var mixed_energy: float = _energy(stream) * relative_gain * relative_gain
				check(mixed_energy > _energy(Audio.stream_for("CH02", "attack", variant)) * 0.6 and mixed_energy < _energy(Audio.stream_for("CH01", "heavy", variant)) * 1.2, label + " physical detonation is stronger than a dry report and bounded by heavy melee energy")
			else:
				check(_energy(stream) * relative_gain * relative_gain < _energy(Audio.stream_for(hero, "heavy", variant)) * 0.10, label + " foreground heavy contact dominates actual mixed energy")
			signatures[hash(stream.data)] = true
			all_signatures[hash(stream.data)] = true
		check(signatures.size() == 4, cue + " has four independently generated waveforms")
	check(all_signatures.size() == 16, "all deployment cues and variations are distinct PCM")
	for index: int in 40:
		for cue: String in Audio.DEPLOYMENT_CUES:
			check(Audio.stream_for("unknown" + str(index), cue, index * -119, "unknown" + str(index)) == Audio.stream_for("", cue, posmod(index * -119, 4)), "deployment external inputs normalize to authored bounded resource")
		check(Audio.stream_for("", "deployment_unknown" + str(index)) == null, "unknown cue cannot create arbitrary synth resource")
	check(Audio._streams.size() == 252, "external input probes cannot grow deployment cache")
	check(Audio.MAX_VOICES == 8 and Audio.RESERVED_PLAYER_VOICES == 2 and Audio.VOICE_GAIN * Audio.SAMPLE_PEAK * Audio.MAX_VOICES < 0.95, "existing voice count and correlated peak headroom remain unchanged")
