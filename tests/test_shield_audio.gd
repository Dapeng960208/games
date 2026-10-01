extends SceneTree
## Real shield/HP damage routes plus original PCM, finite pool and gain checks.
## Run only through tools/test.ps1 with its isolated profile.
const Audio = preload("res://scripts/combat/combat_audio.gd")
const Resolver = preload("res://scripts/combat/stat_resolver.gd")
const Music = preload("res://scripts/audio/music_director.gd")
var game: Node
var room: Node2D
var audio: Node
var music: Node
var app: Node
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
		push_error("SHIELD AUDIO FAIL: " + label)

func _run() -> void:
	game = root.get_node("Game")
	if not str(game.profile_path).contains("test_shield_audio"):
		push_error("Refusing non-test shield audio profile")
		quit(2)
		return
	game.set_process(false)
	check(game.new_profile() and game.start_run(), "isolated production game starts")
	if game.run == null:
		quit(1)
		return
	room_scene = load("res://scenes/room.tscn")
	music = Music.new()
	music.audible = false
	root.add_child(music)
	music.configure(game)
	music.set_process(false)
	app = load("res://scripts/ui/main.gd").new()
	app.route = "run"
	app.music = music
	_test_pcm_and_export()
	_test_real_contacts()
	_test_gates_and_priority()
	_test_settings()
	await _test_device_lifecycle()
	check(await audio.wait_for_cleanup(), "shield mixer lifecycle cleanup completes")
	room.free()
	app.free()
	music.free()
	await process_frame
	print("SHIELD AUDIO: %d/%d passed; real damage/PCM/pool, no listening claim" % [checks-failures,checks])
	quit(1 if failures else 0)

func fixture(hero: String = "CH01") -> void:
	paused = false
	if is_instance_valid(room): room.free()
	game.run.hero_id = hero
	game.run.level = 8
	game.run.stats = Resolver.resolve(hero,8,{}, {})
	game.run.stats.crit_chance = 0.0
	game.run.stats.true_damage_bonus = 0.0
	game.run.max_hp = game.run.stats.max_hp
	game.run.hp = game.run.max_hp
	game.run.resource = 100.0
	game.run.shield = 0.0
	game.run.relics.clear()
	game.profile.settings.merge({"muted":false,"sfx_muted":false,"master_volume":1.0,"sfx_volume":0.85,"reduced_fx":false},true)
	room = room_scene.instantiate()
	room.geometry_enabled = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	room.spawn_enabled = false
	room.input_blocked = false
	room.release_gate = false
	for enemy: Node in room.enemies.get_children(): enemy.free()
	room.player.position = Vector2(430,350)
	audio = room.combat_audio
	audio.audible = false
	audio.set_process(false)
	events.clear()
	audio.cue_played.connect(func(cue: String) -> void: events.append(cue))
	audio.cue_played.connect(app._on_combat_cue_played)
	music.set_context("camp")
	music.set_context("combat")
	music.advance(1.3)

func dummy(shield: float = 10.0) -> Node2D:
	var target: Node2D = room.spawn_enemy(Vector2(490,350),"M01")
	target.health.reset(10000.0)
	target.training_ai_disabled = true
	target.status.grant_guard(shield,5.0,"test:shield",target.health.maximum)
	return target

func direct(target: Node2D, damage: float, context: Dictionary = {}) -> bool:
	context.merge({"damage_type":"true","equipment_eligible":false},true)
	return room.resolve_direct_hit(target,damage,&"primary","",0.0,Vector2.RIGHT,context)

func _test_real_contacts() -> void:
	for hero: String in Audio.HEROES:
		fixture(hero)
		var target: Node2D = dummy(40.0)
		check(direct(target,5.0), hero + " true packet is actually absorbed by enemy shield")
		check(target.health.current == 10000.0 and target.status.shield() < 40.0, hero + " pure shield contact consumes no body health")
		check(events == ["shield_hit"] and audio.active_voice_count() == 1, hero + " shield contact replaces body impact with exactly one shield cue")
		check(_is_shield_stream(audio.get_child(0).stream,hero,false), hero + " actual contact plays authored shield PCM")
		fixture(hero)
		target = dummy(5.0)
		check(direct(target,25.0), hero + " breakthrough actually consumes shield and body health")
		check(target.status.shield() == 0.0 and target.health.current < 10000.0, hero + " breakthrough fixture spans both pools")
		check(events == ["shield_break"] and audio.active_voice_count() == 1, hero + " breakthrough chooses one stronger fracture without duplicate body sound")
		check(_is_shield_stream(audio.get_child(0).stream,hero,true), hero + " breakthrough selects original fracture PCM")
		fixture(hero)
		target = dummy(0.0)
		check(direct(target,5.0) and events == ["impact"], hero + " unshielded damage keeps existing body contact")
	fixture("CH03")
	var target: Node2D = dummy(20.0)
	target.status.apply("invulnerable",1.0,2.0)
	check(not direct(target,10.0) and events.is_empty(), "immune shield emits no false contact")
	target.status.states.clear()
	check(not direct(target,0.0) and events.is_empty(), "zero damage emits no shield cue")
	room.resolve_derived_hit(target,3.0,&"node",Vector2.RIGHT,{"damage_type":"true"})
	check(events == ["passive_impact"] and _is_shield_stream(audio.get_child(0).stream,"CH03",false), "derived node shield contact uses shield timbre but retains passive attribution")
	check(is_equal_approx(music.impact_duck_gain(),1.0), "passive shield feedback never ducks music")
	fixture()
	check(audio.shield_contact("CH01"), "direct shield cue accepts")
	music.advance(0.02)
	check(music.impact_duck_gain() < 1.0, "real main handler treats accepted direct shield tap as light contact")
	fixture()
	check(audio.shield_contact("CH01",true), "direct fracture accepts")
	music.advance(0.02)
	check(music.impact_duck_gain() < Music.LIGHT_IMPACT_GAIN, "real main handler gives fracture the heavy contact music envelope")

func _test_gates_and_priority() -> void:
	fixture()
	check(audio.impact("CH01") and audio.shield_contact("CH01",true), "fracture upgrades a prior ordinary body contact in the existing heavy group")
	check(events == ["impact","shield_break"], "at most one ordinary and one stronger cluster cue")
	check(not audio.shield_contact("CH02") and not audio.shield_contact("CH03",true) and not audio.impact("CH01",true), "fracture suppresses both following shield and body tiers in its window")
	audio.advance(0.056)
	check(audio.shield_contact("CH01"), "new shield contact is eligible after fifty-five milliseconds")
	fixture()
	check(audio.shield_contact("CH03",false,true) and audio.shield_contact("CH01") and audio.shield_contact("CH01",true), "passive shield gate cannot swallow direct shield or fracture")
	check(events == ["passive_impact","shield_hit","shield_break"], "passive and direct signal identities remain distinct")
	audio.advance(0.060)
	check(not audio.shield_contact("CH03",false,true), "direct contact does not shorten preexisting passive hundred-millisecond gate")
	audio.advance(0.041)
	check(audio.shield_contact("CH03",false,true), "passive gate reopens at its own real deadline")
	fixture()
	for index: int in 6: check(audio._request("CH03","shield_hit","passive_impact",0.0,"stone",Audio.PASSIVE_GAIN), "fill six background shield voices")
	check(not audio.shield_contact("CH03",true,true), "even passive fracture cannot consume player reserves")
	var retained: Array = []
	for voice: AudioStreamPlayer in audio.get_children(): retained.append(voice.stream)
	check(audio.attack("CH01") and audio.shield_contact("CH01",true), "actual player release and fracture retain both reserved voices")
	check(audio.active_voice_count() == 8 and not audio.cast("CH02","q"), "shield feature preserves total eight-track cap")
	for index: int in 6: check(audio.get_child(index).stream == retained[index], "foreground cue never truncates a live background waveform")
	var before: int = events.size()
	audio.advance(1.0)
	check(events.size() == before, "rejected shield events have no delayed retry")

func _test_settings() -> void:
	fixture("CH03")
	game.profile.settings.reduced_fx = true
	check(audio.shield_contact("CH03",false,true), "reduced visuals retain shield audio")
	game.profile.settings.merge({"master_volume":0.4,"sfx_volume":0.5},true)
	audio.advance(0.01)
	check(is_equal_approx(db_to_linear(audio.get_child(0).volume_db),Audio.VOICE_GAIN*0.2*Audio.PASSIVE_GAIN), "volume refresh keeps passive shield attenuation")
	game.profile.settings.sfx_muted = true
	check(not audio.shield_contact("CH03",true) and audio.active_voice_count() == 0, "mute stops and refuses shield audio")
	game.profile.settings.sfx_muted = false
	paused = true
	check(not audio.shield_contact("CH03",true), "pause rejects shield feedback")
	paused = false
	check(audio.shield_contact("CH03",true), "resume accepts a fresh fracture without stale gate")
	check(not audio.shield_contact("unknown",true), "unknown hero cannot synthesize a shield family")

func _test_device_lifecycle() -> void:
	fixture()
	var previous_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	audio.audible = true
	check(audio.shield_contact("CH01",true), "muted real mixer allocates the fracture stream")
	var voice: AudioStreamPlayer = audio.get_child(0)
	check(voice.playing and voice.has_stream_playback(), "accepted fracture creates actual playback")
	var weak: WeakRef = weakref(voice.get_stream_playback())
	audio.advance(5.0)
	check(voice.playing, "game-clock advance does not truncate a real fracture waveform")
	var deadline: int = Time.get_ticks_msec()+2000
	while voice.stream != null and Time.get_ticks_msec() < deadline: await process_frame
	check(voice.stream == null and not voice.playing, "real fracture naturally releases its voice")
	check(await audio.wait_for_cleanup() and weak.get_ref() == null, "finished fracture playback is released before test exit")
	audio.audible = false
	AudioServer.set_bus_mute(0,previous_mute)

func _is_shield_stream(stream: AudioStream, hero: String, broken: bool) -> bool:
	for variant: int in 4:
		if stream == Audio.stream_for(hero,"shield_break" if broken else "shield_hit",variant): return true
	return false

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var m: Dictionary = {"peak":0.0,"energy":0.0,"dc":0.0,"rms":0.0}
	var count: int = stream.data.size()/2
	for index: int in count:
		var v: float = float(stream.data.decode_s16(index*2))/32768.0
		m.peak = maxf(m.peak,absf(v))
		m.energy += v*v/stream.mix_rate
		m.dc += v/count
	m.rms = sqrt(m.energy/stream.get_length())
	return m

func _test_pcm_and_export() -> void:
	Audio.prewarm()
	check(Audio._streams.size() == 252 and Audio.SHIELD_CUES.size() == 2 and Audio.CUES.size() == 7, "two shield cues add exactly twenty-four finite streams without changing hero skill slots")
	var signatures: Dictionary = {}
	var exports: Array = []
	var directory: String = "res://artifacts/shield_audio"
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "shield sample output directory available")
	for hero: String in Audio.HEROES:
		for broken: bool in [false,true]:
			var cue: String = "shield_break" if broken else "shield_hit"
			var variants: Array = []
			for variant: int in 4:
				var stream: AudioStreamWAV = Audio.stream_for(hero,cue,variant)
				var m: Dictionary = _measure(stream)
				variants.append(m)
				signatures[hash(stream.data)] = true
				check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 24000 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, hero+cue+" uses nonlooping mono PCM")
				check(stream.get_length() >= 0.13 and stream.get_length() <= 0.27 and m.peak >= 0.15 and m.peak <= Audio.SAMPLE_PEAK and m.rms > 0.02 and absf(m.dc) < 0.003, hero+cue+" is short, substantive and within peak/DC limits")
				check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size()-2) == 0, hero+cue+" has clean zero endpoints")
				check(stream.data != Audio.stream_for(hero,"impact",variant).data and stream.data != Audio.stream_for(hero,"heavy",variant).data, hero+cue+" does not reuse body Foley")
				check(Audio.stream_for(hero,cue,variant+8,"organic") == stream, "shield cache ignores body material and wraps variants")
				if broken:
					var light: Dictionary = _measure(Audio.stream_for(hero,"shield_hit",variant))
					check(m.energy > light.energy*1.25, hero+" fracture has more energy than its shield tap without separate peak normalization")
			var output: String = directory+"/"+hero+"_"+cue+"_v0.wav"
			check(Audio.stream_for(hero,cue,0).save_to_wav(output) == OK, hero+cue+" exports actual production PCM")
			exports.append({"hero":hero,"cue":cue,"wav":ProjectSettings.globalize_path(output),"variants":variants})
	check(signatures.size() == 24, "all hero shield takes are independently generated")
	for index: int in 12:
		check(Audio.stream_for("unknown", "shield_hit",index) == null and Audio.stream_for("CH01","shield_"+str(index)) == null, "unknown shield input cannot grow cache")
	check(Audio._streams.size() == 252 and Audio.MAX_VOICES == 8 and Audio.RESERVED_PLAYER_VOICES == 2, "bounded cache and foreground reservations remain unchanged")
	check(Audio.SAMPLE_PEAK*Audio.VOICE_GAIN*Audio.MAX_VOICES+0.58*Music.MUSIC_GAIN < 0.95, "existing correlated SFX-plus-music headroom remains safe")
	var file: FileAccess = FileAccess.open(directory+"/samples.json",FileAccess.WRITE)
	check(file != null, "shield sample metrics are writable")
	if file != null:
		file.store_string(JSON.stringify({"format":"unchanged production PCM; no audition normalization","voice_gain":Audio.VOICE_GAIN,"direct_event_gain":1.0,"passive_event_gain":Audio.PASSIVE_GAIN,"samples":exports},"\t"))
		file.close()
