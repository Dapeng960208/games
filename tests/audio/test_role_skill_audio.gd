extends SceneTree
## Exact production skill stingers, bounded scheduling and real mixer cleanup.
## Run with tools/test.ps1 -Suite role_skill_audio for an isolated test profile.
## PCM measurements and muted playback do not claim a human listening review.

const Audio = preload("res://scripts/presentation/combat/combat_audio.gd")
const RoleMusic = preload("res://scripts/infrastructure/audio/role_skill_music.gd")
const HEROES: Array[String] = ["CH01", "CH02", "CH03"]
const SLOTS: Array[String] = ["q", "secondary", "f", "ultimate"]
const PREVIEW_DIRECTORY: String = "res://assets/audio/previews"
const PREVIEW_SFX_GAIN: float = 0.14 * 0.85
const PREVIEW_MUSIC_GAIN: float = 0.08 * 0.55
const PREVIEW_GAP_SECONDS: float = 0.35
const GRENADE_FUSE_SECONDS: float = 0.65

var checks: int = 0
var failures: int = 0
var game: Node
var audio: Node
var music_events: Array[String] = []
var sfx_events: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("ROLE SKILL AUDIO FAIL: " + label)

func _run() -> void:
	var requested_profile: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--test-profile="):
			requested_profile = argument.trim_prefix("--test-profile=")
	game = root.get_node_or_null("Game")
	if not requested_profile.contains("test_role_skill_audio") or game == null or str(game.profile_path) != requested_profile:
		push_error("Refusing non-test profile; pass -- --test-profile=<isolated path containing test_role_skill_audio>")
		quit(2)
		return
	var saved_settings: Dictionary = game.profile.settings.duplicate(true)
	game.set_process(false)
	_restore_settings()
	_test_pcm_and_cache()
	audio = Audio.new()
	audio.audible = false
	root.add_child(audio)
	audio.set_process(false)
	audio.skill_music_played.connect(func(hero: String, slot: String) -> void: music_events.append(hero + "/" + slot))
	audio.cue_played.connect(func(cue: String) -> void: sfx_events.append(cue))
	_test_pool_and_scheduling()
	_test_ultimate_priority()
	_test_settings()
	_test_lifecycle()
	_test_grenade_burst()
	await _test_real_mixer()
	_export_stingers()
	_export_role_chains()
	check(await audio.wait_for_cleanup(), "final teardown reclaims all tracked mixer playbacks")
	check(audio.pending_playback_count() == 0, "final teardown retains no playback objects")
	audio.free()
	game.profile.settings = saved_settings
	await process_frame
	print("ROLE SKILL AUDIO: %d checks, %d failures (production PCM/scheduling/muted mixer; no listening claim)" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _restore_settings() -> void:
	game.profile.settings.merge({"muted":false, "sfx_muted":false, "music_muted":false, "master_volume":1.0, "sfx_volume":1.0, "music_volume":1.0, "reduced_fx":false}, true)

func _reset() -> void:
	paused = false
	_restore_settings()
	audio.stop_all()
	music_events.clear()
	sfx_events.clear()

func _music_player() -> AudioStreamPlayer:
	var sfx_players: Array = audio.get("_players")
	for child: Node in audio.get_children():
		if child is AudioStreamPlayer and child not in sfx_players:
			return child as AudioStreamPlayer
	return null

func _measure(stream: AudioStreamWAV) -> Dictionary:
	var count: int = stream.data.size() / 2
	var peak: float = 0.0
	var total: float = 0.0
	var energy: float = 0.0
	for index: int in count:
		var value: float = float(stream.data.decode_s16(index * 2)) / 32768.0
		peak = maxf(peak, absf(value))
		total += value
		energy += value * value
	return {"peak":peak, "mean":total / maxi(1, count), "rms":sqrt(energy / maxi(1, count))}

func _test_pcm_and_cache() -> void:
	check(RoleMusic.RATE == 24000 and is_equal_approx(RoleMusic.PEAK, 0.56), "role music has authored 24 kHz rate and conservative 0.56 PCM ceiling")
	check(is_equal_approx(Audio.SKILL_MUSIC_GAIN, 0.08), "skill music uses its own quiet 0.08 gain")
	check(Audio.MAX_VOICES == 8 and Audio.RESERVED_PLAYER_VOICES == 2, "skill music preserves the existing eight SFX voices and two player reservations")
	check(Audio.SAMPLE_PEAK * Audio.VOICE_GAIN * Audio.MAX_VOICES + 0.58 * 0.18 + RoleMusic.PEAK * Audio.SKILL_MUSIC_GAIN < 0.99, "all eight correlated SFX peaks, background music and one role stinger retain master headroom")
	var signatures: Dictionary = {}
	for hero: String in HEROES:
		for slot: String in SLOTS:
			var label: String = hero + "/" + slot
			var stream: AudioStreamWAV = Audio.skill_music_stream_for(hero, slot)
			check(stream != null, label + " exposes its exact production stinger")
			if stream == null:
				continue
			var measured: Dictionary = _measure(stream)
			check(stream.mix_rate == 24000 and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS, label + " is predictable mono 16-bit PCM")
			check(stream.get_length() >= 0.58 and stream.get_length() <= 1.40, label + " has a bounded musical phrase duration")
			check(float(measured.peak) > 0.04 and float(measured.peak) <= RoleMusic.PEAK + 0.00004, label + " has audible musical signal within the authored peak ceiling")
			check(absf(float(measured.mean)) < 0.003 and float(measured.rms) > 0.012, label + " has negligible DC and meaningful musical energy")
			check(stream.data.decode_s16(0) == 0 and stream.data.decode_s16(stream.data.size() - 2) == 0, label + " has exact zero endpoints")
			check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, label + " cannot loop")
			check(Audio.skill_music_stream_for(hero, slot) == stream, label + " reuses the identical cached WAV resource")
			check(stream != Audio.stream_for(hero, slot), label + " musical phrase has a separate resource from the release Foley")
			signatures[hash(stream.data)] = true
	check(signatures.size() == 12, "each of twelve role/skill phrases has distinct actual PCM")
	for index: int in 32:
		check(Audio.skill_music_stream_for("unknown" + str(index), "q") == null, "unknown hero cannot manufacture a musical cache entry")
		check(Audio.skill_music_stream_for("CH01", "unknown" + str(index)) == null, "unknown slot cannot manufacture a musical cache entry")
	for cue: String in ["attack", "impact", "heavy", "prepare_q", "pickup"]:
		check(Audio.skill_music_stream_for("CH01", cue) == null, cue + " has no automatic musical phrase")
	check(RoleMusic._streams.size() == 12, "invalid inputs cannot grow the twelve-entry role music cache")

func _test_pool_and_scheduling() -> void:
	check(audio.get_child_count() == 8 and _music_player() == null, "ordinary combat lazily allocates only the original eight SFX players")
	check(not audio.skill_music("unknown", "q") and not audio.skill_music("CH01", "attack"), "invalid role and basic attack reject musical playback")
	check(audio.get_child_count() == 8 and music_events.is_empty(), "invalid requests cannot allocate a dedicated player or emit success")
	for index: int in 8:
		check(audio.cast("CH03", "ultimate"), "fill the original pool with an actual foreground SFX release")
	check(audio.active_voice_count() == 8, "eight SFX voices remain available before role music")
	var retained: Array[AudioStream] = []
	var sfx_players: Array = audio.get("_players")
	for voice: AudioStreamPlayer in sfx_players:
		retained.append(voice.stream)
	check(audio.skill_music("CH01", "q"), "role music can coexist with a fully occupied eight-voice SFX pool")
	var voice: AudioStreamPlayer = _music_player()
	check(voice != null and audio.get_child_count() == 9 and sfx_players.size() == 8, "first musical release creates one separate player without enlarging the SFX pool")
	if voice == null:
		return
	var first: AudioStreamWAV = Audio.skill_music_stream_for("CH01", "q")
	check(voice.stream == first and voice.max_polyphony == 1 and is_equal_approx(voice.pitch_scale, 1.0), "dedicated player uses the exact cached phrase and authored speed")
	check(audio.active_skill_music_count() == 1 and audio.active_voice_count() == 8, "music and SFX maintain independent bounded counts")
	for index: int in 8:
		check(sfx_players[index].stream == retained[index], "music admission preserves every existing SFX waveform")
	check(music_events == ["CH01/q"] and sfx_events.size() == 8, "music success signal names role and skill without adding an SFX event")
	for hero: String in HEROES:
		for slot: String in ["q", "secondary", "f"]:
			check(not audio.skill_music(hero, slot), "new musical requests yield to the currently playing phrase")
	check(voice.stream == first and music_events.size() == 1 and audio.active_skill_music_count() == 1, "rejection neither steals, stacks nor reports the current phrase again")
	audio.advance(first.get_length() - 0.0001)
	check(audio.active_skill_music_count() == 1 and not audio.skill_music("CH02", "secondary"), "silent scheduling preserves music until its exact duration")
	audio.advance(0.0002)
	check(audio.active_skill_music_count() == 0 and voice.stream == null, "silent scheduling releases the ended musical phrase")
	check(music_events == ["CH01/q"], "rejected musical requests never retry after the track is free")
	check(audio.skill_music("CH02", "ultimate") and music_events == ["CH01/q", "CH02/ultimate"], "a fresh musical release is accepted after natural scheduling completion")
	for child: Node in audio.get_children():
		if child is AudioStreamPlayer:
			check(not child.playing, "silent scheduling never sends sound to a device")
	_reset()
	check(audio.attack("CH01") and audio.cast("CH01", "q"), "ordinary attack and release Foley still accept without an automatic phrase")
	check(audio.active_skill_music_count() == 0 and music_events.is_empty(), "music is scheduled only through the explicit skill release hook")

func _test_ultimate_priority() -> void:
	_reset()
	check(audio.skill_music("CH01", "q"), "priority fixture starts an ordinary warrior phrase")
	var voice: AudioStreamPlayer = _music_player()
	check(audio.skill_music("CH02", "ultimate"), "ultimate release takes priority over an active ordinary phrase")
	var ultimate: AudioStreamWAV = Audio.skill_music_stream_for("CH02", "ultimate")
	check(_music_player() == voice and voice != null and voice.stream == ultimate, "ultimate takeover reuses the one dedicated player and exact ultimate resource")
	check(audio.active_skill_music_count() == 1 and audio.active_voice_count() == 0 and audio.get_child_count() == 9, "ultimate priority maintains one musical layer and the original SFX pool")
	check(music_events == ["CH01/q", "CH02/ultimate"], "only the accepted ordinary and ultimate releases emit musical success")
	for hero: String in HEROES:
		for slot: String in SLOTS:
			check(not audio.skill_music(hero, slot), "an active ultimate refuses ordinary and repeated ultimate phrases")
	check(voice.stream == ultimate and music_events.size() == 2, "rejected overlap neither cuts nor stacks the ultimate")
	audio.advance(ultimate.get_length() + 0.0001)
	check(audio.active_skill_music_count() == 0 and music_events.size() == 2, "ultimate completion cannot replay the superseded ordinary or rejected phrases")
	check(audio.skill_music("CH03", "q"), "new ordinary release resumes after ultimate completion")
	_reset()

func _test_settings() -> void:
	_reset()
	game.profile.settings.sfx_muted = true
	check(audio.skill_music("CH02", "q") and not audio.attack("CH02"), "SFX mute leaves role music available while refusing combat Foley")
	var voice: AudioStreamPlayer = _music_player()
	audio.advance(0.01)
	check(audio.active_skill_music_count() == 1, "refreshing SFX mute does not cancel the musical phrase")
	game.profile.settings.merge({"master_volume":0.4, "music_volume":0.5}, true)
	audio.advance(0.01)
	if voice != null:
		check(is_equal_approx(db_to_linear(voice.volume_db), Audio.SKILL_MUSIC_GAIN * 0.2), "master and music settings multiply the dedicated player's conservative gain")
	game.profile.settings.reduced_fx = true
	audio.stop_all()
	check(audio.skill_music("CH03", "secondary"), "reduced visual effects preserves role music")
	_reset()
	check(audio.attack("CH01") and audio.skill_music("CH01", "f"), "prepare simultaneous SFX and music for independent mute")
	game.profile.settings.music_muted = true
	audio.advance(0.01)
	check(audio.active_skill_music_count() == 0 and audio.active_voice_count() == 1, "music mute clears only the musical phrase and preserves foreground SFX")
	check(not audio.skill_music("CH03", "f"), "music mute refuses new phrases")
	game.profile.settings.music_muted = false
	audio.advance(2.0)
	check(audio.active_skill_music_count() == 0 and music_events.size() == 1, "unmuting never retries the rejected or cancelled phrase")
	check(audio.skill_music("CH03", "f"), "unmuting accepts a genuinely new musical release")
	for setting: String in ["master_volume", "music_volume"]:
		for value: Variant in [0.0, -1.0, INF, -INF, NAN, "invalid"]:
			_reset()
			game.profile.settings[setting] = value
			check(not audio.skill_music("CH01", "q") and audio.active_skill_music_count() == 0 and music_events.is_empty(), setting + " rejects zero, negative, nonfinite or nonnumeric volume")
	_reset()
	check(audio.skill_music("CH01", "q"), "global mute fixture has an active phrase")
	game.profile.settings.muted = true
	audio.advance(0.01)
	check(audio.active_skill_music_count() == 0 and not audio.skill_music("CH01", "ultimate"), "global mute immediately clears and refuses role music")
	_reset()

func _test_lifecycle() -> void:
	check(audio.skill_music("CH01", "ultimate"), "pause fixture starts a phrase")
	paused = true
	audio.advance(0.2)
	check(audio.active_skill_music_count() == 0 and not audio.skill_music("CH02", "q"), "paused scenes clear music and reject new requests")
	paused = false
	audio.advance(2.0)
	check(music_events.size() == 1 and audio.active_skill_music_count() == 0, "resume never replays cancelled or rejected music")
	check(audio.skill_music("CH02", "q"), "resume accepts a fresh phrase without a stale gate")
	audio.stop_all()
	var voice: AudioStreamPlayer = _music_player()
	check(audio.active_skill_music_count() == 0 and voice != null and voice.stream == null, "stop_all releases the musical stream and virtual scheduling slot")
	check(audio.skill_music("CH03", "ultimate"), "scene removal fixture starts a phrase")
	root.remove_child(audio)
	check(audio.active_skill_music_count() == 0 and not audio.skill_music("CH01", "q"), "scene removal clears and refuses orphan musical playback")
	root.add_child(audio)
	audio.set_process(false)
	check(audio.skill_music("CH01", "q"), "re-entered audio node can accept a fresh musical release")
	_reset()

func _test_grenade_burst() -> void:
	check("grenade_burst" in Audio.DEPLOYMENT_CUES, "gunner grenade detonation has a distinct production deployment cue")
	var stream: AudioStreamWAV = Audio.stream_for("", "grenade_burst")
	check(stream != null, "grenade detonation exposes original production PCM")
	if stream != null:
		var measured: Dictionary = _measure(stream)
		check(stream.get_length() <= 0.35 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and float(measured.peak) <= Audio.SAMPLE_PEAK and float(measured.rms) > 0.012, "grenade detonation is bounded, nonlooping and contains meaningful impact energy")
	check(audio.deployment("grenade_burst") and not audio.deployment("grenade_burst"), "actual grenade audio schedules once and coalesces same-frame detonation crowd")
	check(sfx_events == ["grenade_burst"] and music_events.is_empty() and audio.active_skill_music_count() == 0, "detonation cue does not invent a second skill musical phrase")
	_reset()

func _test_real_mixer() -> void:
	var previous_mute: bool = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	audio.audible = true
	check(audio.skill_music("CH03", "q"), "muted real device accepts the actual mage musical phrase")
	var voice: AudioStreamPlayer = _music_player()
	if voice == null:
		audio.audible = false
		AudioServer.set_bus_mute(0, previous_mute)
		return
	check(voice.playing and voice.has_stream_playback(), "dedicated player creates real mixer playback")
	var playback: WeakRef = weakref(voice.get_stream_playback())
	audio.advance(10.0)
	check(voice.playing and audio.active_skill_music_count() == 1, "large game delta cannot truncate a real mixer-clock phrase")
	check(not audio.skill_music("CH02", "secondary"), "actual mixer playback refuses a competing ordinary role phrase")
	var deadline: int = Time.get_ticks_msec() + 2500
	while (voice.playing or voice.stream != null) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not voice.playing and voice.stream == null and audio.active_skill_music_count() == 0, "real finished signal naturally releases the musical stream and slot")
	check(await audio.wait_for_cleanup() and playback.get_ref() == null, "natural completion destroys the tracked musical mixer playback")
	check(music_events == ["CH03/q"], "actual completion never retries the refused competing phrase")
	check(audio.skill_music("CH02", "secondary"), "real track can accept a fresh phrase after finishing")
	game.profile.settings.music_muted = true
	audio.advance(0.01)
	check(not voice.playing and voice.stream == null and audio.active_skill_music_count() == 0, "music mute immediately stops actual mixer playback")
	check(await audio.wait_for_cleanup(), "mute releases actual mixer references")
	_restore_settings()
	check(audio.skill_music("CH01", "q"), "actual priority fixture starts an ordinary musical phrase")
	var replaced_playback: WeakRef = weakref(voice.get_stream_playback())
	check(audio.skill_music("CH03", "ultimate"), "actual ultimate takes over the dedicated mixer track")
	check(voice.playing and voice.stream == Audio.skill_music_stream_for("CH03", "ultimate") and audio.active_skill_music_count() == 1, "actual ultimate takeover retains exactly one player and authored ultimate PCM")
	deadline = Time.get_ticks_msec() + 750
	while replaced_playback.get_ref() != null and Time.get_ticks_msec() < deadline:
		await process_frame
	check(replaced_playback.get_ref() == null and voice.playing, "superseded mixer playback is reclaimed while the ultimate continues")
	paused = true
	audio.advance(0.1)
	check(not voice.playing and voice.stream == null and audio.active_skill_music_count() == 0, "pause clears actual musical mixer playback")
	paused = false
	check(await audio.wait_for_cleanup(), "pause leaves no retained musical mixer references")
	var before: int = music_events.size()
	audio.advance(2.0)
	check(audio.active_skill_music_count() == 0 and music_events.size() == before, "actual pause cancellation has no deferred replay after resume")
	for index: int in 12:
		check(audio.skill_music(HEROES[index / 4], SLOTS[index % 4]), "same-frame stop regression creates real musical playback")
		audio.stop_all()
	check(await audio.wait_for_cleanup() and audio.pending_playback_count() == 0, "twelve immediate musical starts/stops leave no retained mixer playback")
	audio.audible = false
	AudioServer.set_bus_mute(0, previous_mute)
	_reset()

func _export_stingers() -> void:
	check(DirAccess.make_dir_recursive_absolute(PREVIEW_DIRECTORY) == OK, "production stinger preview directory is available")
	for hero: String in HEROES:
		for slot: String in SLOTS:
			var stream: AudioStreamWAV = Audio.skill_music_stream_for(hero, slot)
			if stream != null:
				# Direct resource export preserves authored PCM. No audition boost,
				# resynthesis, normalization or substituted demo mix is applied.
				check(stream.save_to_wav(PREVIEW_DIRECTORY + "/role_music_" + hero + "_" + slot + ".wav") == OK, hero + "/" + slot + " exports its unamplified production stinger")

func _export_role_chains() -> void:
	# Simulated skill auditions assemble exact production WAV resources at the
	# default gains. These files are not recordings of a gameplay session.
	check(is_equal_approx(PREVIEW_SFX_GAIN, Audio.VOICE_GAIN * 0.85) and is_equal_approx(PREVIEW_MUSIC_GAIN, Audio.SKILL_MUSIC_GAIN * 0.55), "simulated role auditions preserve production default SFX/music gains without a listening boost")
	check(is_equal_approx(float(Audio.DEPLOYMENT_GAINS["grenade_burst"]), 0.66), "simulated grenade audition preserves its production 0.66 event attenuation")
	for hero: String in HEROES:
		var samples := PackedFloat32Array()
		for slot: String in SLOTS:
			var prepare: AudioStreamWAV = Audio.stream_for(hero, "prepare_" + slot)
			var release: AudioStreamWAV = Audio.stream_for(hero, slot)
			var motif: AudioStreamWAV = Audio.skill_music_stream_for(hero, slot)
			if prepare == null or release == null or motif == null:
				check(false, hero + "/" + slot + " practical chain requires exact production resources")
				continue
			var prepare_at: int = samples.size()
			var release_at: int = prepare_at + prepare.data.size() / 2
			var end: int = release_at + maxi(release.data.size(), motif.data.size()) / 2
			var grenade: AudioStreamWAV = Audio.stream_for("", "grenade_burst") if hero == "CH02" and slot == "f" else null
			var grenade_at: int = release_at + roundi(GRENADE_FUSE_SECONDS * RoleMusic.RATE)
			if grenade != null:
				end = maxi(end, grenade_at + grenade.data.size() / 2)
				# Foley's ceiling can encode one extra sample for the 0.34-second
				# resource. Preserve that exact PCM rather than trimming its tail.
				check(end - release_at >= roundi(0.99 * RoleMusic.RATE) and end - release_at <= roundi(0.99 * RoleMusic.RATE) + 1, "gunner F audition includes its 0.65-second fuse and full 0.34-second detonation before the gap")
			samples.resize(end + roundi(PREVIEW_GAP_SECONDS * RoleMusic.RATE))
			_mix(samples, prepare, prepare_at, PREVIEW_SFX_GAIN)
			_mix(samples, release, release_at, PREVIEW_SFX_GAIN)
			_mix(samples, motif, release_at, PREVIEW_MUSIC_GAIN)
			if grenade != null:
				# Empty-space throws still detonate. Body-hit confirmation is never
				# fabricated in this simulated audition.
				_mix(samples, grenade, grenade_at, PREVIEW_SFX_GAIN * float(Audio.DEPLOYMENT_GAINS["grenade_burst"]))
		var bytes := PackedByteArray()
		bytes.resize(samples.size() * 2)
		var peak: float = 0.0
		for index: int in samples.size():
			peak = maxf(peak, absf(samples[index]))
			bytes.encode_s16(index * 2, roundi(samples[index] * 32767.0))
		var chain := AudioStreamWAV.new()
		chain.mix_rate = RoleMusic.RATE
		chain.format = AudioStreamWAV.FORMAT_16_BITS
		chain.stereo = false
		chain.loop_mode = AudioStreamWAV.LOOP_DISABLED
		chain.data = bytes
		check(peak > 0.005 and peak <= Audio.SAMPLE_PEAK * PREVIEW_SFX_GAIN + RoleMusic.PEAK * PREVIEW_MUSIC_GAIN, hero + " chain retains meaningful signal within the sum of production gains")
		check(chain.save_to_wav(PREVIEW_DIRECTORY + "/role_skill_" + hero + ".wav") == OK, hero + " exports a simulated Q/secondary/F/ultimate audition from production WAVs/default gains without body impacts")
	var description: FileAccess = FileAccess.open(AssetCatalog.resolve(PREVIEW_DIRECTORY + "/role_skill_auditions.txt"), FileAccess.WRITE)
	check(description != null, "simulated audition description can be saved beside the role preview WAVs")
	if description != null:
		description.store_string("Simulated skill auditions, not recorded gameplay.\n\nEach role file assembles isolated Q, secondary, F, and ultimate excerpts from exact production prepare/release WAVs and role motifs. Preparation is concatenated before release plus motif, with a 0.35-second gap after each excerpt.\n\nDefault gains: SFX 0.14 * 0.85; music 0.08 * 0.55. CH02 F includes the exact grenade_burst WAV at release + 0.65 seconds, using SFX gain * 0.66. Its full 0.34-second detonation precedes the gap.\n\nNo normalization, gain boost, fabricated body impacts, or recorded gameplay is included. Actual gameplay timings and repeated projectile events are validated separately.\n")
		description.close()

func _mix(out: PackedFloat32Array, stream: AudioStreamWAV, start: int, gain: float) -> void:
	for index: int in stream.data.size() / 2:
		out[start + index] += float(stream.data.decode_s16(index * 2)) / 32768.0 * gain
